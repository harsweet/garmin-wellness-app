import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { DemoCalendar } from './demo-calendar.mjs';
import { GrokSuggestions } from './grok.mjs';
import { WellnessService } from './wellness-service.mjs';
import { createDemoServer } from './server.mjs';
import { OnboardingService } from './onboarding.mjs';

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
  const calendar = new DemoCalendar({ stateFile: path.join(local, 'demo-calendar.json'), timeZone: process.env.MOMO_TIME_ZONE || 'America/Edmonton' });
  await calendar.load();
  const wellness = new WellnessService(calendar, { suggestionProvider: provider });
  const onboarding = new OnboardingService(calendar, { publicOrigin: process.env.MOMO_PUBLIC_URL || '' });
  const server = createDemoServer(calendar, { wellness, deviceToken, onboarding });
  return { server, calendar, wellness, provider, deviceToken, onboarding };
}
