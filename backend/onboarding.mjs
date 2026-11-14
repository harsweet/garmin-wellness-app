import { createHash, randomBytes, timingSafeEqual } from 'node:crypto';
import QRCode from 'qrcode';
import { CalendarError } from './demo-calendar.mjs';

const KEY_TTL = 10 * 60_000;
const SESSION_TTL = 24 * 60 * 60_000;
export const ONBOARDING_COOKIE = 'momo_onboarding';
const digest = value => createHash('sha256').update(value).digest('hex');
function equalHash(a, b) { return typeof a === 'string' && typeof b === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b)); }

export class OnboardingService {
  constructor(calendar, { publicOrigin = '', getPublicOrigin = null } = {}) {
    this.calendar = calendar;
    this.publicOrigin = '';
    this.originProvider = getPublicOrigin;
    if (publicOrigin) this.setPublicOrigin(publicOrigin);
  }

  setPublicOrigin(value) {
    const url = new URL(value);
    const local = ['localhost', '127.0.0.1'].includes(url.hostname);
    if ((url.protocol !== 'https:' && !(local && url.protocol === 'http:')) || url.username || url.password || url.search || url.hash || url.pathname !== '/') throw new Error('Use an HTTPS public origin for onboarding.');
    this.publicOrigin = url.origin;
  }

  getPublicOrigin() {
    const supplied = this.originProvider?.();
    if (supplied && supplied !== this.publicOrigin) this.setPublicOrigin(supplied);
    return this.publicOrigin;
  }

  async issue() {
    const origin = this.getPublicOrigin();
    if (!origin) throw new CalendarError(503, 'onboarding_not_ready', 'Phone setup is starting. Try again shortly.');
    const key = randomBytes(32).toString('base64url');
    const expiresAt = this.calendar.now() + KEY_TTL;
    await this.calendar.updateWellness(state => {
      state.onboarding ||= {};
      state.onboarding.capabilities = [...(state.onboarding.capabilities || []).filter(item => item.expiresAt > this.calendar.now() && !item.claimedAt), { hash: digest(key), expiresAt }].slice(-8);
      state.onboarding.sessions = (state.onboarding.sessions || []).filter(item => item.expiresAt > this.calendar.now());
    });
    // The capability lives in the fragment, never in the GET URL or Referer.
    const url = `${origin}/onboard#key=${key}`;
    const qr = QRCode.create(url, { errorCorrectionLevel: 'M' });
    const rows = [];
    for (let row = 0; row < qr.modules.size; row += 1) {
      let bits = '';
      for (let column = 0; column < qr.modules.size; column += 1) bits += qr.modules.get(row, column) ? '1' : '0';
      rows.push(bits);
    }
    return { mode: 'demo', url, qr: rows, expiresAt: new Date(expiresAt).toISOString(), profileConfigured: !!this.calendar.wellnessState.profile };
  }

  async claim(key) {
    if (typeof key !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(key)) throw new CalendarError(401, 'invalid_setup_link', 'This setup link is invalid. Scan a fresh code on Momo.');
    const hash = digest(key);
    const sessionToken = randomBytes(32).toString('base64url');
    const expiresAt = this.calendar.now() + SESSION_TTL;
    await this.calendar.updateWellness(state => {
      const capability = state.onboarding?.capabilities?.find(item => equalHash(item.hash, hash));
      if (!capability || capability.claimedAt || capability.expiresAt <= this.calendar.now()) throw new CalendarError(401, 'expired_setup_link', 'This setup link has expired or was already used. Scan a fresh code.');
      capability.claimedAt = this.calendar.now();
      state.onboarding.sessions = [...(state.onboarding.sessions || []).filter(item => item.expiresAt > this.calendar.now()), { hash: digest(sessionToken), expiresAt }].slice(-16);
    });
    return { sessionToken, expiresAt, profileConfigured: !!this.calendar.wellnessState.profile };
  }

  authenticate(cookieHeader) {
    if (typeof cookieHeader !== 'string') return false;
    const match = cookieHeader.split(';').map(part => part.trim()).find(part => part.startsWith(`${ONBOARDING_COOKIE}=`));
    if (!match) return false;
    const token = match.slice(ONBOARDING_COOKIE.length + 1);
    if (!/^[A-Za-z0-9_-]{43}$/.test(token)) return false;
    const hash = digest(token);
    return !!this.calendar.wellnessState.onboarding?.sessions?.some(session => session.expiresAt > this.calendar.now() && equalHash(session.hash, hash));
  }
}
