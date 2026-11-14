import http from 'node:http';
import { createHash, randomBytes, randomUUID } from 'node:crypto';
import { readFile } from 'node:fs/promises';
import { DemoCalendar, CalendarError } from './demo-calendar.mjs';
import { WellnessService, ACTIVITY_CATALOG } from './wellness-service.mjs';
import { OnboardingService } from './onboarding.mjs';
import { createDemoServer, readBody, json, tokenMatches, isLocalBrowser } from './server.mjs';

const hash = value => createHash('sha256').update(value).digest('hex');
const ADMIN_COOKIE = 'momo_admin';
const TEN_MINUTES = 600_000;
const STATIC_FILES = {
  '/admin': 'admin.html', '/admin.js': 'admin.js', '/admin.css': 'admin.css',
  '/': 'index.html', '/setup': 'index.html', '/onboard': 'index.html',
  '/app.js': 'app.js', '/style.css': 'style.css', '/momo.jpg': 'momo.jpg'
};
const cookieValue = (header, name) => typeof header === 'string' ? header.split(';').map(part => part.trim()).find(part => part.startsWith(`${name}=`))?.slice(name.length + 1) : null;
const stamp = now => new Date(now()).toISOString();

// The workspace owns identities, while each wearer retains an independent
// calendar, profile, recommendation cache, QR sessions, and feedback history.
export class MomoWorkspace {
  constructor({ initialState = null, deviceToken, adminToken = '', publicOrigin = '', provider = null, save = async () => {}, now = () => Date.now(), timeZone = 'America/Edmonton', allowLocalSetup = true } = {}) {
    if (!/^[A-Za-z0-9_-]{43}$/.test(deviceToken || '')) throw new Error('Configure a valid watch access token.');
    this.deviceToken = deviceToken;
    this.adminToken = adminToken;
    this.provider = provider;
    this.save = save;
    this.now = now;
    this.timeZone = timeZone;
    this.allowLocalSetup = allowLocalSetup;
    this.publicOrigin = '';
    this.contexts = new Map();
    this.queue = Promise.resolve();
    this.setupQueue = Promise.resolve();
    if (initialState?.schemaVersion === 2 && initialState.users && Object.keys(initialState.users).length) {
      this.state = structuredClone(initialState);
    } else {
      const id = randomUUID();
      const calendar = new DemoCalendar({ now, timeZone, initialState });
      this.state = { schemaVersion: 2, defaultUserId: id, users: { [id]: { id, createdAt: stamp(now), updatedAt: stamp(now), calendar: calendar.snapshot() } }, devices: { [hash(deviceToken)]: id }, adminSessions: [], limits: {} };
    }
    this.state.devices ||= {};
    if (!this.state.devices[hash(deviceToken)]) this.state.devices[hash(deviceToken)] = this.state.defaultUserId;
    if (publicOrigin) this.setPublicOrigin(publicOrigin);
  }

  async initialize() { await this.save(this.state); }

  setPublicOrigin(value) {
    const validator = new OnboardingService(new DemoCalendar(), { publicOrigin: value });
    this.publicOrigin = validator.getPublicOrigin();
    for (const context of this.contexts.values()) context.onboarding.setPublicOrigin(this.publicOrigin);
  }
  getPublicOrigin() { return this.publicOrigin; }

  mutate(update) {
    const result = this.queue.then(async () => {
      const next = structuredClone(this.state);
      const value = await update(next);
      await this.save(next);
      this.state = next;
      return value;
    });
    this.queue = result.catch(() => {});
    return result;
  }

  codeInUse(code) {
    const digest = hash(code);
    return Object.values(this.state.users).some(user => user.calendar.wellness?.onboarding?.capabilities?.some(item => item.codeHash === digest && !item.claimedAt && item.expiresAt > this.now()));
  }

  setupOperation(callback) {
    const result = this.setupQueue.then(callback);
    this.setupQueue = result.catch(() => {});
    return result;
  }

  context(id) {
    if (this.contexts.has(id)) return this.contexts.get(id);
    const record = this.state.users[id];
    if (!record) throw new CalendarError(404, 'unknown_user', 'That wearer was not found.');
    const calendar = new DemoCalendar({ now: this.now, timeZone: this.timeZone, initialState: record.calendar });
    calendar.persist = async (activities = calendar.activities, wellness = calendar.wellnessState) => {
      const snapshot = { ...calendar.snapshot(), activities, wellness };
      await this.mutate(state => { state.users[id].calendar = structuredClone(snapshot); state.users[id].updatedAt = stamp(this.now); });
    };
    const wellness = new WellnessService(calendar, { suggestionProvider: this.provider });
    wellness.userId = id;
    const onboarding = new OnboardingService(calendar, { publicOrigin: this.publicOrigin, userId: id, isCodeInUse: code => this.codeInUse(code) });
    const context = { calendar, wellness, onboarding };
    this.contexts.set(id, context);
    return context;
  }

  activeUserId() { return this.state.devices[hash(this.deviceToken)]; }
  watchUser(token) { return typeof token === 'string' && /^[A-Za-z0-9_-]{43}$/.test(token) ? this.state.devices[hash(token)] : null; }
  phoneUser(cookie) { return Object.keys(this.state.users).find(id => this.context(id).onboarding.authenticate(cookie)) || null; }
  setupUser(body) { return Object.keys(this.state.users).find(id => this.context(id).onboarding.canClaim(body)) || null; }

  async createUser() {
    const id = randomUUID();
    const deviceToken = randomBytes(32).toString('base64url');
    const calendar = new DemoCalendar({ now: this.now, timeZone: this.timeZone });
    await this.mutate(state => {
      if (Object.keys(state.users).length >= 200) throw new CalendarError(409, 'user_limit', 'This demo workspace supports up to 200 wearers.');
      state.users[id] = { id, createdAt: stamp(this.now), updatedAt: stamp(this.now), calendar: calendar.snapshot() };
      state.devices[hash(deviceToken)] = id;
    });
    return { user: this.userView(id), deviceToken, setup: await this.context(id).onboarding.issue() };
  }

  onboardWatch(token, fresh) {
    const wantsNewDevice = fresh === true || fresh === 1 || fresh === 'true';
    return this.setupOperation(async () => {
      const id = this.watchUser(token);
      if (!id) throw new CalendarError(401, 'unauthorized', 'Reconnect the latest Momo build.');
      if (wantsNewDevice && this.context(id).wellness.dashboard().profileConfigured) {
        const created = await this.createUser();
        await this.assignWatch(created.user.id, token);
        return created.setup;
      }
      return this.context(id).onboarding.issue();
    });
  }

  async assignWatch(id, token = this.deviceToken) {
    if (!this.state.users[id]) throw new CalendarError(404, 'unknown_user', 'That wearer was not found.');
    await this.mutate(state => { state.devices[hash(token)] = id; });
    return { userId: id };
  }

  userView(id) {
    const record = this.state.users[id];
    const { wellness, calendar } = this.context(id);
    const dashboard = wellness.dashboard();
    const decisions = calendar.wellnessState.decisions || [];
    const sessions = dashboard.sessions;
    const counts = { accepted: decisions.filter(item => item.decision === 'accept').length, completed: sessions.filter(item => item.status === 'completed').length, helpful: sessions.filter(item => item.feedback?.helpful === 'yes').length, somewhat: sessions.filter(item => item.feedback?.helpful === 'somewhat').length, notHelpful: sessions.filter(item => item.feedback?.helpful === 'no').length, snoozed: decisions.filter(item => item.decision === 'snooze').length, alternatives: decisions.filter(item => item.decision === 'alternative').length, simulated: sessions.filter(item => item.status === 'completed' && item.completion?.source?.startsWith('simulated')).length };
    const history = wellness.history();
    const preferences = ACTIVITY_CATALOG.map(activity => ({ activityId: activity.activityId, title: activity.title, accepted: history.acceptedByActivity[activity.activityId] || 0, completed: history.completedByActivity[activity.activityId] || 0, helpful: history.helpfulByActivity[activity.activityId]?.yes || 0, somewhat: history.helpfulByActivity[activity.activityId]?.somewhat || 0, notHelpful: history.helpfulByActivity[activity.activityId]?.no || 0, snoozed: history.snoozedByActivity[activity.activityId] || 0 }));
    const capabilities = calendar.wellnessState.onboarding?.capabilities || [];
    const pending = capabilities.filter(item => !item.claimedAt && item.expiresAt > this.now());
    const pairingExpiresAt = pending.length ? new Date(Math.max(...pending.map(item => item.expiresAt))).toISOString() : null;
    const pairingState = dashboard.profileConfigured ? 'paired' : pairingExpiresAt ? 'waiting' : (calendar.wellnessState.onboarding?.sessions || []).some(item => item.expiresAt > this.now()) ? 'finishing' : 'idle';
    return { pairingState, pairingExpiresAt, id, label: `Watch ${Object.keys(this.state.users).indexOf(id) + 1}`, createdAt: record.createdAt, updatedAt: record.updatedAt, configured: dashboard.profileConfigured, activeWatch: this.activeUserId() === id, profile: dashboard.profile, counts, preferences, sessions, decisions: decisions.slice(-200), suggestions: (calendar.wellnessState.suggestions || []).slice(-15).map(({ id, activityId, title, start, quip, reason, aiSource }) => ({ id, activityId, title, start, quip, reason, aiSource })) };
  }

  adminData() {
    const users = Object.keys(this.state.users).map(id => this.userView(id));
    const totals = users.reduce((sum, user) => { for (const key of Object.keys(user.counts)) sum[key] = (sum[key] || 0) + user.counts[key]; return sum; }, { users: users.length, configured: users.filter(user => user.configured).length });
    return { mode: 'demo', activeUserId: this.activeUserId(), users, totals, generatedAt: stamp(this.now) };
  }

  adminAuthenticated(request) {
    if (this.allowLocalSetup && isLocalBrowser(request)) return true;
    const token = cookieValue(request.headers.cookie, ADMIN_COOKIE);
    return !!token && /^[A-Za-z0-9_-]{43}$/.test(token) && (this.state.adminSessions || []).some(session => session.expiresAt > this.now() && tokenMatches(session.hash, hash(token)));
  }

  async limit(request, kind, maximum = 6) {
    const supplied = request.headers['cf-connecting-ip'] || request.headers['x-forwarded-for'] || request.socket.remoteAddress || 'unknown';
    const client = hash(`${this.deviceToken}:${String(supplied).slice(0, 200)}`);
    await this.mutate(state => {
      const key = `${kind}:${client}`;
      state.limits ||= {};
      for (const [id, record] of Object.entries(state.limits)) if (record.until <= this.now()) delete state.limits[id];
      const record = state.limits[key] ||= { count: 0, until: this.now() + TEN_MINUTES };
      if (record.count >= maximum) throw new CalendarError(429, 'rate_limited', 'Too many attempts. Please wait a few minutes before trying again.');
      record.count += 1;
      if (kind === 'code') {
        const global = state.limits['code:all'] ||= { count: 0, until: this.now() + TEN_MINUTES };
        if (global.count >= 60) throw new CalendarError(429, 'rate_limited', 'Setup is busy. Please try again shortly.');
        global.count += 1;
      }
    });
  }

  async loginAdmin(token, request, response) {
    await this.limit(request, 'admin');
    if (!this.adminToken || !tokenMatches(token, this.adminToken)) return json(response, { error: 'unauthorized', message: 'That admin access key did not match.' }, 401);
    const session = randomBytes(32).toString('base64url');
    const expiresAt = this.now() + 24 * 60 * 60_000;
    await this.mutate(state => { state.adminSessions = [...(state.adminSessions || []).filter(item => item.expiresAt > this.now()), { hash: hash(session), expiresAt }].slice(-8); });
    response.setHeader('Set-Cookie', `${ADMIN_COOKIE}=${session}; HttpOnly; SameSite=Strict; Path=/; Max-Age=86400${request.headers.origin?.startsWith('https:') ? '; Secure' : ''}`);
    return json(response, { authenticated: true });
  }

  async delegate(id, request, response, deviceToken = this.deviceToken) {
    const { calendar, wellness, onboarding } = this.context(id);
    // Phone setup always claims a device, even on the local development computer.
    const server = createDemoServer(calendar, { wellness, onboarding, deviceToken, allowLocalSetup: false });
    return server.listeners('request')[0](request, response);
  }

  async handle(request, response) {
    try {
      const host = request.headers.host || '';
      const localHost = /^(127\.0\.0\.1|localhost):\d+$/.test(host);
      if (!localHost && (!this.publicOrigin || host !== new URL(this.publicOrigin).host)) return json(response, { error: 'invalid_host' }, 403);
      const origin = request.headers.origin;
      const allowedOrigin = value => value === this.publicOrigin || (localHost && value === `http://${host}`);
      if (origin && !allowedOrigin(origin)) return json(response, { error: 'invalid_origin' }, 403);
      const pathname = new URL(request.url, `http://${host}`).pathname;
      if (request.method === 'GET' && Object.hasOwn(STATIC_FILES, pathname)) {
        const filename = STATIC_FILES[pathname];
        const content = await readFile(new URL(`./public/${filename}`, import.meta.url));
        response.writeHead(200, { 'Content-Type': filename.endsWith('.js') ? 'text/javascript; charset=utf-8' : filename.endsWith('.css') ? 'text/css; charset=utf-8' : filename.endsWith('.jpg') ? 'image/jpeg' : 'text/html; charset=utf-8', 'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Content-Security-Policy': "default-src 'self'; script-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src 'self' https://fonts.gstatic.com; img-src 'self'; connect-src 'self'; frame-ancestors 'none'; base-uri 'none'; form-action 'self'" });
        return response.end(content);
      }
      if (request.method === 'POST') request.body = await readBody(request);
      if (pathname.startsWith('/api/admin/')) {
        if (request.method === 'POST' && (!origin || !allowedOrigin(origin) || request.headers['x-momo-request'] !== '1')) return json(response, { error: 'invalid_origin' }, 403);
        if (pathname === '/api/admin/login' && request.method === 'POST') return await this.loginAdmin(request.body?.token, request, response);
        const authenticated = this.adminAuthenticated(request);
        if (pathname === '/api/admin/session' && request.method === 'GET') return json(response, { authenticated, local: this.allowLocalSetup && isLocalBrowser(request) });
        if (!authenticated) return json(response, { error: 'admin_required', message: 'Sign in with your admin access key.' }, 401);
        if (pathname === '/api/admin/users' && request.method === 'GET') return json(response, this.adminData());
        if (pathname === '/api/admin/users' && request.method === 'POST') return json(response, await this.setupOperation(() => this.createUser()), 201);
        const match = pathname.match(/^\/api\/admin\/users\/([a-f0-9-]{36})\/assign$/);
        if (match && request.method === 'POST') return json(response, await this.assignWatch(match[1]));
        if (pathname === '/api/admin/logout' && request.method === 'POST') {
          const session = cookieValue(request.headers.cookie, ADMIN_COOKIE);
          if (session) await this.mutate(state => { state.adminSessions = (state.adminSessions || []).filter(item => item.hash !== hash(session)); });
          response.setHeader('Set-Cookie', `${ADMIN_COOKIE}=; HttpOnly; SameSite=Strict; Path=/; Max-Age=0`);
          return json(response, { authenticated: false });
        }
        return json(response, { error: 'not_found' }, 404);
      }
      if (pathname === '/api/onboarding/claim' && request.method === 'POST') {
        if (!origin || !allowedOrigin(origin) || request.headers['x-momo-request'] !== '1') return json(response, { error: 'invalid_origin' }, 403);
        if (request.body?.code !== undefined) await this.limit(request, 'code');
        const id = this.setupUser(request.body);
        if (!id) return json(response, { error: 'invalid_setup', message: 'That code or setup link is invalid, expired, or already used. Get a fresh one from Momo.' }, 401);
        return await this.delegate(id, request, response);
      }
      if (request.method === 'POST' && ['/', '/api'].includes(pathname)) {
        const id = this.watchUser(request.body?.token);
        if (!id) return json(response, { mode: 'demo', error: 'unauthorized', message: 'Reconnect the latest Momo build.', httpStatus: 401 });
        if (request.body.action === 'onboarding') return json(response, await this.onboardWatch(request.body.token, request.body.fresh));
        return await this.delegate(id, request, response, request.body.token);
      }
      const id = this.phoneUser(request.headers.cookie) || this.activeUserId();
      return await this.delegate(id, request, response);
    } catch (error) {
      return json(response, { error: error.error || 'unavailable', message: error instanceof CalendarError ? error.message : 'Momo is unavailable. Please try again.', httpStatus: error.httpStatus || 503 }, error instanceof CalendarError ? error.httpStatus : 503);
    }
  }

  createServer() { return http.createServer((request, response) => this.handle(request, response)); }
}
