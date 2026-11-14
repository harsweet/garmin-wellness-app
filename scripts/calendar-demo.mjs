import { access, chmod, mkdir, readFile, writeFile } from 'node:fs/promises';
import { spawn, spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import { DemoCalendar } from '../backend/demo-calendar.mjs';
import { createDemoServer } from '../backend/server.mjs';
import { configureCalendarUrl } from './calendar-url.mjs';

const root = fileURLToPath(new URL('../', import.meta.url));
const tools = path.join(root, '.local/tools');
await mkdir(tools, { recursive: true });
let executable = process.env.CLOUDFLARED || path.join(tools, 'cloudflared');
try {
  await access(executable);
} catch {
  if (process.platform !== 'darwin' || !['arm64', 'x64'].includes(process.arch)) {
    throw new Error('Install cloudflared and set CLOUDFLARED to its path.');
  }
  const architecture = process.arch === 'arm64' ? 'arm64' : 'amd64';
  console.log('Downloading Cloudflare’s HTTPS demo helper (first run only)…');
  const response = await fetch(`https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-darwin-${architecture}.tgz`, { signal: AbortSignal.timeout(60_000) });
  if (!response.ok) throw new Error('Could not download cloudflared. Set CLOUDFLARED to an installed copy.');
  const archive = path.join(tools, 'cloudflared.tgz');
  await writeFile(archive, new Uint8Array(await response.arrayBuffer()));
  const unpack = spawnSync('tar', ['-xzf', archive, '-C', tools], { stdio: 'inherit' });
  if (unpack.status !== 0) throw new Error('Could not unpack the HTTPS helper.');
  await chmod(executable, 0o755);
}

const calendar = new DemoCalendar({ stateFile: path.join(root, '.local/demo-calendar.json'), timeZone: process.env.MOMO_TIME_ZONE || 'America/Edmonton' });
await calendar.load();
const server = createDemoServer(calendar);
await new Promise((resolve, reject) => {
  server.once('error', reject);
  server.listen(8787, '127.0.0.1', resolve);
});
console.log('Local DEMO calendar: http://127.0.0.1:8787');
console.log('Starting a temporary public HTTPS URL for sample data only…');
const child = spawn(executable, ['tunnel', '--url', 'http://127.0.0.1:8787', '--http-host-header', '127.0.0.1:8787', '--no-autoupdate', '--protocol', 'http2'], { stdio: ['ignore', 'pipe', 'pipe'] });
let started = false;
let tail = '';
let finished = false;
function stop(code) {
  if (finished) return;
  finished = true;
  child.kill('SIGTERM');
  server.close();
  process.exitCode = code;
}
async function onOutput(chunk) {
  tail = (tail + chunk.toString()).slice(-12_000);
  const match = tail.match(/https:\/\/[a-z0-9-]+\.trycloudflare\.com/);
  if (!match || started) return;
  started = true;
  const url = await configureCalendarUrl(match[0]);
  const deadline = Date.now() + 120_000;
  let lastError = '';
  console.log('Waiting for the temporary HTTPS address to become reachable…');
  // Wait for authoritative DNS first. An immediate OS lookup can cache NXDOMAIN
  // while Cloudflare is still registering a brand-new temporary hostname.
  let dnsReady = false;
  while (Date.now() < deadline && !finished && !dnsReady) {
    try {
      const lookup = new URL('https://cloudflare-dns.com/dns-query');
      lookup.searchParams.set('name', new URL(url).hostname);
      lookup.searchParams.set('type', 'A');
      const response = await fetch(lookup, { headers: { Accept: 'application/dns-json' }, signal: AbortSignal.timeout(3000) });
      const result = await response.json();
      dnsReady = result.Status === 0 && result.Answer?.some(record => record.type === 1);
    } catch (error) { lastError = error.message; }
    if (!dnsReady) await new Promise(resolve => setTimeout(resolve, 1000));
  }
  while (Date.now() < deadline && !finished) {
    try {
      const response = await fetch(`${url}/api/demo`, { signal: AbortSignal.timeout(2000) });
      const result = await response.json();
      if (response.ok && result.mode === 'demo') {
        console.log(`\nHTTPS demo ready: ${url}`);
        console.log('Run ./scripts/ciq.sh run in another terminal, then hold UP on Momo.');
        console.log('Leave this terminal open. Ctrl+C stops the demo and its HTTPS URL.');
        return;
      }
    } catch (error) { lastError = error.cause?.code || error.message; }
    await new Promise(resolve => setTimeout(resolve, 1000));
  }
  console.error(`HTTPS endpoint did not become reachable (${lastError}). Restart npm run calendar:demo.`);
  stop(1);
}
child.stdout.on('data', chunk => { onOutput(chunk).catch(error => { console.error(error.message); stop(1); }); });
child.stderr.on('data', chunk => { onOutput(chunk).catch(error => { console.error(error.message); stop(1); }); });
child.on('error', error => { console.error(error.message); stop(1); });
child.on('exit', () => { if (!finished) { console.error('HTTPS helper stopped. Restart the demo service.'); stop(1); } });
process.on('SIGINT', () => stop(0));
process.on('SIGTERM', () => stop(0));
