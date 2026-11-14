import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DemoCalendar } from './demo-calendar.mjs';
import { GrokSuggestions } from './grok.mjs';
import { MomoWorkspace } from './workspace.mjs';

export async function createRuntime(root = fileURLToPath(new URL('../', import.meta.url))) {
  try { process.loadEnvFile(path.join(root, '.env')); } catch (error) {
    if (error.code !== 'ENOENT') throw new Error('Could not load .env. Check its KEY=value format.');
  }
  const local = path.join(root, '.local');
  await mkdir(local, { recursive: true });
  const tokenFile = path.join(local, 'demo-device-token');
  let deviceToken;
  if (process.env.MOMO_DEVICE_TOKEN) {
    deviceToken = process.env.MOMO_DEVICE_TOKEN;
    if (!/^[A-Za-z0-9_-]{43}$/.test(deviceToken)) throw new Error('MOMO_DEVICE_TOKEN must be a 43-character base64url token.');
    await writeFile(tokenFile, deviceToken, { mode: 0o600 });
  } else try {
    deviceToken = (await readFile(tokenFile, 'utf8')).trim();
    if (!/^[A-Za-z0-9_-]{43}$/.test(deviceToken)) throw new Error('Invalid local device token.');
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
    deviceToken = randomBytes(32).toString('base64url');
    await writeFile(tokenFile, deviceToken, { mode: 0o600, flag: 'wx' });
  }
  const provider = new GrokSuggestions({ apiKey: process.env.XAI_API_KEY || process.env.GROK_API_KEY || '', model: process.env.XAI_MODEL || 'grok-4.7' });
  const adminFile = path.join(local, 'admin-token');
  let adminToken = process.env.MOMO_ADMIN_TOKEN;
  if (adminToken) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(adminToken)) throw new Error('MOMO_ADMIN_TOKEN must be a 43-character access key.');
    await writeFile(adminFile, adminToken, { mode: 0o600 });
  } else try { adminToken = (await readFile(adminFile, 'utf8')).trim(); }
  catch (error) { if (error.code !== 'ENOENT') throw error; adminToken = randomBytes(32).toString('base64url'); await writeFile(adminFile, adminToken, { mode: 0o600, flag: 'wx' }); }
  if (!/^[A-Za-z0-9_-]{43}$/.test(adminToken)) throw new Error('Invalid local admin access key.');
  const stateFile = path.join(local, 'workspace.json');
  let initialState;
  try { initialState = JSON.parse(await readFile(stateFile, 'utf8')); }
  catch (error) {
    if (error.code !== 'ENOENT') throw error;
    const legacy = new DemoCalendar({ stateFile: path.join(local, 'demo-calendar.json'), timeZone: process.env.MOMO_TIME_ZONE || 'America/Edmonton' });
    await legacy.load();
    initialState = legacy.snapshot();
  }
  const workspace = new MomoWorkspace({ initialState, deviceToken, adminToken, provider, publicOrigin: process.env.MOMO_PUBLIC_URL || '', timeZone: process.env.MOMO_TIME_ZONE || 'America/Edmonton', save: async state => {
    await writeFile(`${stateFile}.tmp`, JSON.stringify(state), { mode: 0o600 });
    await rename(`${stateFile}.tmp`, stateFile);
  } });
  await workspace.initialize();
  const { calendar, wellness } = workspace.context(workspace.activeUserId());
  return { server: workspace.createServer(), calendar, wellness, provider, deviceToken, onboarding: workspace, workspace };
}
