import { createHash, randomBytes, randomInt, timingSafeEqual } from 'node:crypto';
import QRCode from 'qrcode';
import { CalendarError } from './demo-calendar.mjs';

const KEY_TTL = 10 * 60_000;
const SESSION_TTL = 24 * 60 * 60_000;
const CODE_ATTEMPT_WINDOW = 10 * 60_000;
const CODE_ATTEMPT_LIMIT = 6;
export const ONBOARDING_COOKIE = 'momo_onboarding';
const digest = value => createHash('sha256').update(value).digest('hex');
function equalHash(a, b) { return typeof a === 'string' && typeof b === 'string' && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b)); }
const active = (item, now) => item && item.claimedAt == null && Number.isFinite(item.expiresAt) && item.expiresAt > now;
function setupInput(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const hasKey = Object.hasOwn(input, 'key') && input.key !== undefined;
  const hasCode = Object.hasOwn(input, 'code') && input.code !== undefined;
  if (hasKey === hasCode) return null;
  return hasKey ? { kind: 'key', value: input.key } : { kind: 'code', value: input.code };
}

export class OnboardingService {
  constructor(calendar, { publicOrigin = '', getPublicOrigin = null, userId = null, isCodeInUse = () => false, generateCode = () => randomInt(0, 10_000).toString().padStart(4, '0') } = {}) {
    this.calendar = calendar;
    this.publicOrigin = '';
    this.originProvider = getPublicOrigin;
    this.userId = userId;
    this.isCodeInUse = isCodeInUse;
    this.generateCode = generateCode;
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
    let code;
    await this.calendar.updateWellness(state => {
      state.onboarding ||= {};
      const capabilities = (state.onboarding.capabilities || []).filter(item => active(item, this.calendar.now()));
      for (let attempt = 0; attempt < 128; attempt += 1) {
        const candidate = this.generateCode();
        if (typeof candidate !== 'string' || !/^\d{4}$/.test(candidate)) continue;
        const codeHash = digest(candidate);
        if (capabilities.some(item => equalHash(item.codeHash, codeHash)) || this.isCodeInUse(candidate)) continue;
        code = candidate;
        break;
      }
      if (!code) throw new CalendarError(503, 'setup_codes_busy', 'A setup code could not be created. Try again shortly.');
      // The short code and QR key unlock the same one-use capability. Neither
      // credential is stored in plaintext, including in persisted snapshots.
      state.onboarding.capabilities = [...capabilities, { hash: digest(key), codeHash: digest(code), expiresAt }].slice(-8);
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
    return { mode: 'demo', url, qr: rows, code, setupUrl: `${origin}/setup`, userId: this.userId, profileRevision: this.calendar.wellnessState.profileRevision || 0, expiresAt: new Date(expiresAt).toISOString(), profileConfigured: !!this.calendar.wellnessState.profile };
  }

  canClaim(input) {
    const setup = setupInput(input);
    if (!setup || typeof setup.value !== 'string') return false;
    if (!(setup.kind === 'key' ? /^[A-Za-z0-9_-]{43}$/ : /^\d{4}$/).test(setup.value)) return false;
    const hash = digest(setup.value);
    const field = setup.kind === 'key' ? 'hash' : 'codeHash';
    // Matching is read-only so the multi-user router can find the right scope.
    // It also reserves codes while an owner is temporarily rate limited.
    return !!this.calendar.wellnessState.onboarding?.capabilities?.some(item => active(item, this.calendar.now()) && equalHash(item[field], hash));
  }

  claim(key) { return this.claimSetup({ key }); }

  claimCode(code) { return this.claimSetup({ code }); }

  async claimSetup(input) {
    const setup = setupInput(input);
    if (!setup) throw new CalendarError(400, 'invalid_setup_request', 'Use the QR link or enter the four-digit code from Momo.');
    const usingCode = setup.kind === 'code';
    const validShape = typeof setup.value === 'string' && (usingCode ? /^\d{4}$/ : /^[A-Za-z0-9_-]{43}$/).test(setup.value);
    if (!usingCode && !validShape) throw new CalendarError(401, 'invalid_setup_link', 'This setup link is invalid. Scan a fresh code on Momo.');
    const hash = validShape ? digest(setup.value) : '';
    const sessionToken = randomBytes(32).toString('base64url');
    const expiresAt = this.calendar.now() + SESSION_TTL;
    const result = await this.calendar.updateWellness(state => {
      state.onboarding ||= {};
      const now = this.calendar.now();
      if (usingCode) {
        const attempts = state.onboarding.codeAttempts;
        if (attempts && attempts.resetAt > now && attempts.failures >= CODE_ATTEMPT_LIMIT) {
          return { error: 'setup_code_rate_limited', httpStatus: 429, message: 'Too many incorrect codes. Wait a few minutes or scan the QR code on Momo.' };
        }
      }
      const field = usingCode ? 'codeHash' : 'hash';
      const capability = validShape ? state.onboarding.capabilities?.find(item => equalHash(item[field], hash)) : null;
      if (!active(capability, now)) {
        if (usingCode) {
          const previous = state.onboarding.codeAttempts;
          const attempts = previous?.resetAt > now ? previous : { failures: 0, resetAt: now + CODE_ATTEMPT_WINDOW };
          attempts.failures += 1;
          state.onboarding.codeAttempts = attempts;
          return { error: attempts.failures >= CODE_ATTEMPT_LIMIT ? 'setup_code_rate_limited' : 'invalid_setup_code', httpStatus: attempts.failures >= CODE_ATTEMPT_LIMIT ? 429 : 401, message: attempts.failures >= CODE_ATTEMPT_LIMIT ? 'Too many incorrect codes. Wait a few minutes or scan the QR code on Momo.' : 'This code is invalid, expired, or already used. Open Momo for a fresh code.' };
        }
        return { error: 'expired_setup_link', httpStatus: 401, message: 'This setup link has expired or was already used. Scan a fresh code.' };
      }
      capability.claimedAt = this.calendar.now();
      if (usingCode) state.onboarding.codeAttempts = { failures: 0, resetAt: now + CODE_ATTEMPT_WINDOW };
      state.onboarding.sessions = [...(state.onboarding.sessions || []).filter(item => item.expiresAt > this.calendar.now()), { hash: digest(sessionToken), expiresAt }].slice(-16);
      return { claimed: true };
    });
    // Throw after updateWellness commits, so failed attempts survive restarts.
    if (result.error) throw new CalendarError(result.httpStatus, result.error, result.message);
    return { sessionToken, expiresAt, userId: this.userId, profileConfigured: !!this.calendar.wellnessState.profile };
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
