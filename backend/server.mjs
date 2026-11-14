import http from 'node:http';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { readFile } from 'node:fs/promises';
import { timingSafeEqual } from 'node:crypto';
import { DemoCalendar, CalendarError } from './demo-calendar.mjs';
import { WellnessService } from './wellness-service.mjs';
import { OnboardingService, ONBOARDING_COOKIE } from './onboarding.mjs';

export function json(response, data, status = 200) {
  response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff' });
  response.end(JSON.stringify(data));
}

export async function readBody(request) {
  // Vercel's Node helpers may have parsed the body before this handler runs.
  if (request.body !== undefined) {
    let parsed = request.body;
    try {
      if (typeof parsed === 'string' || Buffer.isBuffer(parsed)) parsed = JSON.parse(parsed.toString());
      if (Buffer.byteLength(JSON.stringify(parsed)) > 16_384) throw new CalendarError(413, 'too_large', 'Request too large.');
      return parsed;
    } catch (error) {
      if (error instanceof CalendarError) throw error;
      throw new CalendarError(400, 'invalid_json', 'Invalid request.');
    }
  }
  let body = '';
  for await (const chunk of request) {
    body += chunk;
    if (Buffer.byteLength(body) > 16_384) throw new CalendarError(413, 'too_large', 'Request too large.');
  }
  try { return JSON.parse(body); } catch { throw new CalendarError(400, 'invalid_json', 'Invalid request.'); }
}

export function tokenMatches(value, expected) {
  if (typeof value !== 'string' || typeof expected !== 'string') return false;
  const a = Buffer.from(value), b = Buffer.from(expected);
  return a.length === b.length && timingSafeEqual(a, b);
}

export function isLocalBrowser(request) {
  const address = request.socket.remoteAddress;
  return ['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(address) && !['cf-connecting-ip', 'x-forwarded-for', 'forwarded', 'x-forwarded-host'].some(header => request.headers[header] !== undefined);
}

const STATIC_FILES = {
  '/': ['index.html', 'text/html; charset=utf-8'],
  '/onboard': ['index.html', 'text/html; charset=utf-8'],
  '/setup': ['index.html', 'text/html; charset=utf-8'],
  '/style.css': ['style.css', 'text/css; charset=utf-8'],
  '/app.js': ['app.js', 'text/javascript; charset=utf-8'],
  '/momo.jpg': ['momo.jpg', 'image/jpeg']
};

export function createDemoServer(calendar = new DemoCalendar(), { wellness = new WellnessService(calendar), deviceToken = 'momo-demo', publicOrigin = '', onboarding = new OnboardingService(calendar, { publicOrigin }), allowLocalSetup = true } = {}) {
  return http.createServer(async (request, response) => {
    try {
      const host = request.headers.host || '';
      const localHost = /^(127\.0\.0\.1|localhost):\d+$/.test(host);
      const configuredOrigin = onboarding.getPublicOrigin();
      const publicHost = configuredOrigin ? new URL(configuredOrigin).host : null;
      if (!localHost && host !== publicHost) return json(response, { error: 'invalid_host' }, 403);
      const origin = request.headers.origin;
      const allowedOrigin = value => value === configuredOrigin || (localHost && value === `http://${host}`);
      if (origin && !allowedOrigin(origin)) return json(response, { error: 'invalid_origin' }, 403);
      const pathname = new URL(request.url, `http://${host}`).pathname;
      if (request.method === 'GET' && pathname === '/health') return json(response, { mode: 'demo', ready: true });
      if (request.method === 'GET' && pathname in STATIC_FILES) {
        const [filename, mime] = STATIC_FILES[pathname];
        try {
          const content = await readFile(new URL(`./public/${filename}`, import.meta.url));
          response.writeHead(200, { 'Content-Type': mime, 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'self'; img-src 'self'; style-src 'self'; script-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" });
          return response.end(content);
        } catch (error) {
          if (error.code !== 'ENOENT') throw error;
          return json(response, { error: 'setup_unavailable', message: 'Momo setup files are not installed.' }, 404);
        }
      }
      if (request.method === 'POST' && pathname === '/api/onboarding/claim') {
        if (!origin || !allowedOrigin(origin) || request.headers['x-momo-request'] !== '1') return json(response, { error: 'invalid_origin' }, 403);
        const body = await readBody(request);
        const claimed = await onboarding.claimSetup(body);
        const secure = origin.startsWith('https:') ? '; Secure' : '';
        response.setHeader('Set-Cookie', `${ONBOARDING_COOKIE}=${claimed.sessionToken}; HttpOnly; SameSite=Lax; Path=/; Max-Age=86400${secure}`);
        return json(response, { status: 'claimed', profileConfigured: claimed.profileConfigured, expiresAt: new Date(claimed.expiresAt).toISOString() });
      }
      if (pathname === '/api/profile' || pathname === '/api/demo') {
        if (!(allowLocalSetup && isLocalBrowser(request)) && !onboarding.authenticate(request.headers.cookie)) return json(response, { error: 'setup_required', message: 'Scan Momo to connect this browser.' }, 401);
        if (request.method === 'GET' && pathname === '/api/profile') return json(response, wellness.getProfile());
        if (request.method === 'POST' && pathname === '/api/profile') {
          if (!origin || !allowedOrigin(origin) || request.headers['x-momo-request'] !== '1') return json(response, { error: 'invalid_origin' }, 403);
          return json(response, await wellness.saveProfile(await readBody(request)));
        }
        if (request.method === 'GET' && pathname === '/api/demo') return json(response, { ...calendar.status(), activities: calendar.activities.length, events: calendar.allEvents().map(event => ({ ...event, start: new Date(event.start).toISOString(), end: new Date(event.end).toISOString() })), wellness: wellness.dashboard() });
        return json(response, { error: 'not_found' }, 404);
      }
      if (request.method !== 'POST' || !['/', '/api'].includes(pathname)) return json(response, { error: 'not_found' }, 404);
      const body = await readBody(request);
      if (!body || typeof body !== 'object' || Array.isArray(body)) throw new CalendarError(400, 'invalid_body', 'Invalid request.');
      // Legacy demo pairing is allowed only with fixture credentials. A private
      // runtime token must never be disclosed through the public pairing route.
      if (body.action === 'pair' && deviceToken === 'momo-demo') {
        if (body.code !== '000000') throw new CalendarError(401, 'invalid_code', 'Demo code is 000000.');
        return json(response, { token: 'momo-demo', mode: 'demo' });
      }
      if (!tokenMatches(body.token, deviceToken)) throw new CalendarError(401, 'unauthorized', 'Reconnect the latest Momo build.');
      if (body.action === 'onboarding') return json(response, await onboarding.issue());
      if (body.action === 'status') return json(response, wellness.status());
      if (body.action === 'availability') return json(response, calendar.availability());
      if (body.action === 'activities') {
        if (typeof body.slotId !== 'string') throw new CalendarError(400, 'invalid_slot', 'Choose a suggested slot.');
        return json(response, await calendar.book(body.slotId));
      }
      if (body.action === 'suggestions') return json(response, await wellness.suggestions(body));
      if (body.action === 'decide') return json(response, await wellness.decide(body));
      if (body.action === 'start') return json(response, await wellness.start(body));
      if (body.action === 'complete') return json(response, await wellness.complete(body));
      if (body.action === 'feedback') return json(response, await wellness.feedback(body));
      throw new CalendarError(400, 'invalid_action', 'Unknown calendar action.');
    } catch (error) {
      json(response, { mode: 'demo', error: error.error || 'internal_error', message: error instanceof CalendarError ? error.message : 'Momo is unavailable. Try again shortly.', httpStatus: error.httpStatus || 500 });
    }
  });
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const calendar = new DemoCalendar({ stateFile: fileURLToPath(new URL('../.local/demo-calendar.json', import.meta.url)), timeZone: process.env.MOMO_TIME_ZONE || 'America/Edmonton' });
  await calendar.load();
  const server = createDemoServer(calendar);
  server.on('error', error => { console.error(`Cannot start demo calendar: ${error.message}`); process.exitCode = 1; });
  server.listen(8787, '127.0.0.1', () => console.log('Momo DEMO calendar: http://127.0.0.1:8787 (no Google account connected)'));
}
