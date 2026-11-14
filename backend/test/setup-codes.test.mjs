import test from 'node:test';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DemoCalendar } from '../demo-calendar.mjs';
import { OnboardingService, ONBOARDING_COOKIE } from '../onboarding.mjs';

const BASE = Date.parse('2026-11-14T17:00:00Z');
const MINUTE = 60_000;
const hash = value => createHash('sha256').update(value).digest('hex');
const keyOf = issue => new URLSearchParams(new URL(issue.url).hash.slice(1)).get('key');
const fixture = (options = {}) => {
  const calendar = new DemoCalendar({ now: () => BASE, ...options.calendar });
  const onboarding = new OnboardingService(calendar, { publicOrigin: 'https://momo.example', userId: 'user-a', generateCode: () => '0007', ...options.onboarding });
  return { calendar, onboarding };
};

test('setup issues a leading-zero code and stores only capability hashes', async () => {
  const { calendar, onboarding } = fixture();
  calendar.wellnessState.profileRevision = 4;
  const issued = await onboarding.issue();
  const key = keyOf(issued);
  assert.equal(issued.code, '0007');
  assert.equal(issued.setupUrl, 'https://momo.example/setup');
  assert.equal(issued.profileRevision, 4);
  assert.equal(issued.userId, 'user-a');
  assert.equal(Date.parse(issued.expiresAt), BASE + 10 * MINUTE);
  assert.ok(issued.qr.length > 0 && issued.qr.every(row => /^[01]+$/.test(row)));
  const capability = calendar.wellnessState.onboarding.capabilities[0];
  assert.equal(capability.codeHash, hash('0007'));
  assert.equal(capability.hash, hash(key));
  assert.equal(Object.values(capability).includes('0007'), false);
  assert.equal(Object.values(capability).includes(key), false);
  const before = calendar.snapshot();
  assert.equal(onboarding.canClaim({ code: '0007' }), true);
  assert.equal(onboarding.canClaim({ key }), true);
  assert.equal(onboarding.canClaim({ code: 7 }), false);
  assert.equal(onboarding.canClaim({ code: '0007', key }), false);
  assert.deepEqual(calendar.snapshot(), before, 'Routing lookups must not mutate persisted state.');
});

test('a code claim creates a scoped session and consumes the QR capability too', async () => {
  const { calendar, onboarding } = fixture({ calendar: { now: () => 0 } });
  const issued = await onboarding.issue();
  const claimed = await onboarding.claimCode(issued.code);
  assert.equal(claimed.userId, 'user-a');
  assert.equal(claimed.expiresAt, 24 * 60 * MINUTE);
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=${claimed.sessionToken}`), true);
  assert.equal(onboarding.canClaim({ code: issued.code }), false);
  assert.equal(onboarding.canClaim({ key: keyOf(issued) }), false);
  await assert.rejects(onboarding.claimCode(issued.code), error => error.httpStatus === 401);
  await assert.rejects(onboarding.claim(keyOf(issued)), error => error.httpStatus === 401);
  assert.equal(calendar.wellnessState.onboarding.sessions.length, 1);
});

test('legacy QR claims consume the short code and reject numeric code input', async () => {
  const { onboarding } = fixture();
  const issued = await onboarding.issue();
  const session = await onboarding.claim(keyOf(issued));
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=${session.sessionToken}`), true);
  assert.equal(onboarding.canClaim({ code: issued.code }), false);
  await assert.rejects(onboarding.claimSetup({ code: 7 }), error => error.httpStatus === 401);
  await assert.rejects(onboarding.claimSetup({ key: keyOf(issued), code: issued.code }), error => error.httpStatus === 400);
});

test('code and QR claims racing each other grant exactly one session', async () => {
  const { calendar, onboarding } = fixture();
  const issued = await onboarding.issue();
  const results = await Promise.allSettled([onboarding.claimCode(issued.code), onboarding.claim(keyOf(issued))]);
  assert.equal(results.filter(result => result.status === 'fulfilled').length, 1);
  assert.equal(calendar.wellnessState.onboarding.sessions.length, 1);
});

test('codes and QR links expire at ten minutes while cookies last twenty-four hours', async () => {
  let now = BASE;
  const { onboarding } = fixture({ calendar: { now: () => now } });
  const issued = await onboarding.issue();
  now += 10 * MINUTE;
  assert.equal(onboarding.canClaim({ code: issued.code }), false);
  assert.equal(onboarding.canClaim({ key: keyOf(issued) }), false);
  await assert.rejects(onboarding.claimCode(issued.code), error => error.httpStatus === 401);
  await assert.rejects(onboarding.claim(keyOf(issued)), error => error.httpStatus === 401);
  const fresh = await onboarding.issue();
  const session = await onboarding.claimCode(fresh.code);
  now += 24 * 60 * MINUTE;
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=${session.sessionToken}`), false);
});

test('failed-code limits persist across restarts and leave the QR route available', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'momo-setup-'));
  let now = BASE;
  const stateFile = path.join(directory, 'calendar.json');
  try {
    const { calendar, onboarding } = fixture({ calendar: { now: () => now, stateFile } });
    const issued = await onboarding.issue();
    for (let attempt = 0; attempt < 5; attempt += 1) {
      await assert.rejects(onboarding.claimCode('9999'), error => error.httpStatus === 401);
    }
    await assert.rejects(onboarding.claimCode('9999'), error => error.httpStatus === 429);
    const restarted = new DemoCalendar({ now: () => now, stateFile });
    await restarted.load();
    const loaded = new OnboardingService(restarted, { publicOrigin: 'https://momo.example', userId: 'user-a', generateCode: () => '0007' });
    assert.equal(restarted.wellnessState.onboarding.codeAttempts.failures, 6);
    assert.equal(loaded.canClaim({ code: issued.code }), true, 'A read-only match still identifies the rate-limited owner.');
    await assert.rejects(loaded.claimCode(issued.code), error => error.httpStatus === 429);
    const qr = await loaded.claim(keyOf(issued));
    assert.equal(loaded.authenticate(`${ONBOARDING_COOKIE}=${qr.sessionToken}`), true);
    now += 10 * MINUTE + 1;
    const fresh = await loaded.issue();
    await loaded.claimCode(fresh.code);
    assert.equal(restarted.wellnessState.onboarding.codeAttempts.failures, 0);
    assert.equal(calendar.wellnessState.onboarding.codeAttempts.failures, 6);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('active codes stay unique within a user and through the workspace callback', async () => {
  const a = fixture();
  const first = await a.onboarding.issue();
  const sequence = ['0007', '0008', '0008', '0009'];
  const b = fixture({ onboarding: { userId: 'user-b', generateCode: () => sequence.shift(), isCodeInUse: code => a.onboarding.canClaim({ code }) } });
  const second = await b.onboarding.issue();
  const third = await b.onboarding.issue();
  assert.equal(first.code, '0007');
  assert.equal(second.code, '0008');
  assert.equal(third.code, '0009');
  assert.equal(second.userId, 'user-b');
  assert.equal(a.onboarding.canClaim({ code: second.code }), false);
});

test('an exhausted active-code namespace fails closed without persisting a credential', async () => {
  const { calendar, onboarding } = fixture({ onboarding: { isCodeInUse: () => true } });
  await assert.rejects(onboarding.issue(), error => error.httpStatus === 503);
  assert.equal(calendar.wellnessState.onboarding, undefined);
});

test('QR capabilities issued before short-code support still work', async () => {
  const key = 'a'.repeat(43);
  const { onboarding } = fixture({ calendar: { initialState: { wellness: { onboarding: { capabilities: [{ hash: hash(key), expiresAt: BASE + MINUTE }] } } } } });
  assert.equal(onboarding.canClaim({ key }), true);
  assert.equal(onboarding.canClaim({ code: '0007' }), false);
  const claimed = await onboarding.claim(key);
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=${claimed.sessionToken}`), true);
});
