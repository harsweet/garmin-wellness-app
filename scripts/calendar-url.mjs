import { mkdir, writeFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

export async function configureCalendarUrl(value) {
  const url = new URL(value);
  const loopback = ['127.0.0.1', 'localhost'].includes(url.hostname) && url.protocol === 'http:' && url.port === '8787' && url.pathname === '/';
  const google = url.protocol === 'https:' && url.hostname === 'script.google.com' && /^\/macros\/s\/[\w-]+\/exec$/.test(url.pathname);
  const tunnel = url.protocol === 'https:' && /^[a-z0-9-]+\.trycloudflare\.com$/.test(url.hostname) && url.pathname === '/';
  if ((!loopback && !google && !tunnel) || url.username || url.password || url.search || url.hash) {
    throw new Error('Use the demo HTTPS tunnel URL, or your Google Apps Script /exec URL.');
  }
  const directory = fileURLToPath(new URL('../resources-fenix7pro/settings/', import.meta.url));
  await mkdir(directory, { recursive: true });
  const normalized = url.href.replace(/\/$/, '');
  await writeFile(path.join(directory, 'properties.xml'), `<properties>\n    <property id="CalendarServerUrl" type="string">${normalized}</property>\n</properties>\n`);
  const strings = path.join(directory, '..', 'strings');
  await mkdir(strings, { recursive: true });
  await writeFile(path.join(strings, 'calendar.xml'), `<strings>\n    <string id="CalendarBuildServerUrl">${normalized}</string>\n</strings>\n`);
  const local = fileURLToPath(new URL('../.local/', import.meta.url));
  await mkdir(local, { recursive: true });
  await writeFile(path.join(local, 'calendar-endpoint.json'), JSON.stringify({url: normalized, mode: google ? 'google' : 'demo'}));
  return normalized;
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  try {
    console.log(`Calendar URL configured: ${await configureCalendarUrl(process.argv[2])}`);
    console.log('Rebuild the watch app to use this URL.');
  } catch (error) {
    console.error(error.message);
    process.exitCode = 1;
  }
}
