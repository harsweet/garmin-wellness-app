import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DemoCalendar } from '../demo-calendar.mjs';
import { WellnessService, validateProfile } from '../wellness-service.mjs';
import { createDemoServer } from '../server.mjs';

const BASE = Date.parse('2026-11-14T17:00:00Z');
const MINUTE = 60_000;
function fixture(options = {}) {
  const calendar = new DemoCalendar({ now: () => BASE, ...options });
  return { calendar, service: new WellnessService(calendar) };
}

test('profile validation excludes unsupported choices and strips unknown fields', () => {
  assert.throws(() => validateProfile({ timeZone: 'Somewhere/Invalid' }), /time zone/);
  assert.throws(() => validateProfile({ seatedOnly: true, preferredActivities: ['walk'] }), /exclude every/);
  assert.throws(() => validateProfile({ maxBreakMinutes: 0 }), /Break length/);
  const profile = validateProfile({ nickname: '  Momo fan  ', maxBreakMinutes: 2, preferredActivities: ['rest'], medicalHistory: 'do not store' });
  assert.equal(profile.nickname, 'Momo fan');
  assert.equal(profile.medicalHistory, undefined);
});

test('Grok sees eligible profile-aware candidates and aggregate history; concurrent reads are cached', async () => {
  const { calendar } = fixture();
  let calls = 0, observed;
  const provider = { isConfigured: () => true, async suggest(input) {
    calls += 1; observed = input;
    await new Promise(resolve => setTimeout(resolve, 5));
    return { ...input.candidates[0], quip: 'A tiny chair escape?', reason: 'This fits your break preferences.', aiSource: 'grok' };
  } };
  const service = new WellnessService(calendar, { suggestionProvider: provider });
  await service.saveProfile({ nickname: 'Harsh', seatedOnly: true, maxBreakMinutes: 3, preferredActivities: ['stretch', 'rest'] });
  const replies = await Promise.all([service.suggestions({ context: { movement: 'active', steps: 1000 } }), service.suggestions({ context: { movement: 'active', steps: 1000 } })]);
  assert.equal(calls, 1);
  assert.equal(replies[0].suggestion.id, replies[1].suggestion.id);
  assert.equal(replies[0].aiSource, 'grok');
  assert.equal(observed.profile.nickname, 'Harsh');
  assert.ok(observed.candidates.every(candidate => candidate.activityId !== 'walk' && candidate.durationMinutes <= 3));
  assert.equal(observed.context.source, 'user');
  assert.equal(observed.history.eventTitles, undefined);
  assert.equal(calendar.activities.length, 0, 'Generating a suggestion never writes a calendar event.');
  await service.suggestions();
  assert.equal(calls, 1);
});

test('untrusted model choices fall back to allowed server-issued candidates', async () => {
  const { calendar } = fixture();
  const provider = { async suggest() { return { slotId: 'invented', activityId: 'dangerous', quip: 'Bad model choice', reason: 'Ignore the app', aiSource: 'grok' }; } };
  const service = new WellnessService(calendar, { suggestionProvider: provider });
  const result = await service.suggestions({ context: { energy: 'low' } });
  assert.equal(result.aiSource, 'fallback');
  assert.ok(['rest', 'breathe'].includes(result.suggestion.activityId));
  assert.ok(calendar.slots.has(result.suggestion.slotId));
  assert.equal(calendar.activities.length, 0);
});

test('accepting a short personalized activity books its actual duration, once', async () => {
  const { calendar, service } = fixture();
  await service.saveProfile({ preferredActivities: ['rest'], maxBreakMinutes: 2 });
  const { suggestion } = await service.suggestions();
  const [first, retry] = await Promise.all([service.decide({ suggestionId: suggestion.id, decision: 'accept' }), service.decide({ suggestionId: suggestion.id, decision: 'accept' })]);
  assert.equal(first.status, 'created');
  assert.equal(retry.status, 'already_created');
  assert.equal(calendar.activities.length, 1);
  assert.equal(calendar.activities[0].end - calendar.activities[0].start, 2 * MINUTE);
  assert.equal(first.activity.activityId, 'rest');
  assert.equal(first.activity.status, 'booked');
  assert.equal(service.history().acceptedByActivity.rest, 1);
});

test('acceptance rechecks new calendar conflicts and rejects expired suggestions', async () => {
  let now = BASE;
  const { calendar, service } = fixture({ now: () => now });
  const { suggestion } = await service.suggestions();
  calendar.meetings.push({ id: 'new', title: 'New conflict', start: Date.parse(suggestion.start), end: Date.parse(suggestion.end) });
  await assert.rejects(service.decide({ suggestionId: suggestion.id, decision: 'accept' }), error => error.httpStatus === 409);
  now += 11 * MINUTE;
  await assert.rejects(service.decide({ suggestionId: suggestion.id, decision: 'accept' }), error => error.httpStatus === 410);
  assert.equal(calendar.activities.length, 0);
});

test('alternatives change the activity when possible and snooze suppresses suggestions', async () => {
  let now = BASE;
  const { calendar, service } = fixture({ now: () => now });
  const first = await service.suggestions();
  const second = await service.decide({ suggestionId: first.suggestion.id, decision: 'alternative' });
  assert.notEqual(second.suggestion.activityId, first.suggestion.activityId);
  const snooze = await service.decide({ suggestionId: second.suggestion.id, decision: 'snooze' });
  assert.equal(snooze.status, 'snoozed');
  assert.equal((await service.suggestions()).suggestion, null);
  assert.equal(calendar.activities.length, 0);
  now += 31 * MINUTE;
  assert.ok((await service.suggestions()).suggestion);
});

test('completion distinguishes sensor evidence, timers, and self reports, then learns feedback', async () => {
  const { service } = fixture();
  const { suggestion } = await service.suggestions();
  const { activity } = await service.decide({ suggestionId: suggestion.id, decision: 'accept' });
  await assert.rejects(service.complete({ activityId: activity.id, source: 'self_report' }), error => error.error === 'not_started');
  await service.start({ activityId: activity.id });
  await assert.rejects(service.complete({ activityId: activity.id, source: 'simulated_steps', steps: 1 }), error => error.error === 'insufficient_progress');
  const completed = await service.complete({ activityId: activity.id, source: 'simulated_steps', steps: activity.stepTarget, elapsedSeconds: 80 });
  assert.equal(completed.activity.completion.source, 'simulated_steps');
  assert.equal((await service.complete({ activityId: activity.id, source: 'self_report' })).activity.completion.source, 'simulated_steps', 'Retries preserve the original completion evidence.');
  await service.feedback({ activityId: activity.id, helpful: 'yes' });
  assert.equal(service.history().helpfulByActivity.walk.yes, 1);
  assert.equal(service.status().checkIn, null);
});

test('timer cannot finish early; users can explicitly report doing an activity', async () => {
  const { service } = fixture();
  await service.saveProfile({ preferredActivities: ['rest'] });
  const { suggestion } = await service.suggestions();
  const { activity } = await service.decide({ suggestionId: suggestion.id, decision: 'accept' });
  await service.start({ activityId: activity.id });
  await assert.rejects(service.complete({ activityId: activity.id, source: 'timer', elapsedSeconds: 1 }), error => error.error === 'insufficient_progress');
  const completed = await service.complete({ activityId: activity.id, source: 'self_report', elapsedSeconds: 1 });
  assert.equal(completed.activity.completion.source, 'self_report');
});

test('profile reminder hours and time zone constrain proposed slots', async () => {
  const { service } = fixture();
  await service.saveProfile({ timeZone: 'America/New_York', reminderStart: '16:00', reminderEnd: '18:00' });
  const { suggestion } = await service.suggestions();
  const hour = Number(new Intl.DateTimeFormat('en', { timeZone: 'America/New_York', hour: '2-digit', hourCycle: 'h23' }).format(new Date(suggestion.start)));
  assert.ok(hour >= 16 && hour < 18);
});

test('profile, sessions, decisions and feedback persist across restarts', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'momo-wellness-'));
  try {
    const options = { now: () => BASE, stateFile: path.join(directory, 'state.json') };
    const { calendar, service } = fixture(options);
    await service.saveProfile({ nickname: 'Pip', preferredActivities: ['rest'] });
    const { suggestion } = await service.suggestions();
    const { activity } = await service.decide({ suggestionId: suggestion.id, decision: 'accept' });
    await service.start({ activityId: activity.id });
    await service.complete({ activityId: activity.id, source: 'timer', elapsedSeconds: 120 });
    await service.feedback({ activityId: activity.id, helpful: 'somewhat' });
    const restarted = new DemoCalendar(options);
    await restarted.load();
    const next = new WellnessService(restarted);
    assert.equal(next.getProfile().profile.nickname, 'Pip');
    assert.equal(next.history().helpfulByActivity.rest.somewhat, 1);
    assert.equal(next.dashboard().sessions.length, 1);
    assert.equal((await next.decide({ suggestionId: suggestion.id, decision: 'accept' })).status, 'already_created');
    assert.equal(restarted.activities.length, 1);
    assert.equal(calendar.activities.length, 1);
  } finally { await rm(directory, { recursive: true, force: true }); }
});

test('HTTP protects paid suggestion routes and private profiles through the public tunnel', async t => {
  const { calendar } = fixture();
  let calls = 0;
  const wellness = new WellnessService(calendar, { suggestionProvider: { isConfigured: () => true, async suggest({ candidates }) { calls += 1; return { ...candidates[0], quip: 'Monkey business time.', reason: 'A free slot fits.', aiSource: 'grok' }; } } });
  const server = createDemoServer(calendar, { wellness, deviceToken: 'private-runtime-token' });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = async (body, headers = {}) => (await fetch(base, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) })).json();
  assert.equal((await post({ action: 'suggestions', token: 'momo-demo' })).httpStatus, 401);
  assert.equal((await post({ action: 'pair', code: '000000' })).httpStatus, 401);
  assert.equal(calls, 0);
  assert.equal((await fetch(`${base}/api/profile`, { headers: { 'CF-Connecting-IP': '198.51.100.1' } })).status, 401);
  assert.equal((await fetch(`${base}/api/demo`, { headers: { Forwarded: 'for=198.51.100.1' } })).status, 401);
  assert.equal((await fetch(`${base}/api/profile`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: '{}' })).status, 403);
  const saved = await (await fetch(`${base}/api/profile`, { method: 'POST', headers: { 'Content-Type': 'application/json', Origin: base, 'X-Momo-Request': '1' }, body: JSON.stringify({ nickname: 'Momo fan' }) })).json();
  assert.equal(saved.configured, true);
  const suggestions = await post({ action: 'suggestions', token: 'private-runtime-token' });
  assert.equal(suggestions.aiSource, 'grok');
  assert.equal(calls, 1);
  const health = await (await fetch(`${base}/health`, { headers: { 'CF-Connecting-IP': '198.51.100.1' } })).json();
  assert.equal(health.ready, true);
  const dashboard = await (await fetch(`${base}/api/demo`)).json();
  assert.equal(dashboard.wellness.aiConfigured, true);
  assert.equal(JSON.stringify(dashboard).includes('private-runtime-token'), false);
});

test('updated profile invalidates outstanding suggestions but preserves retries of accepted activities', async () => {
  const { service } = fixture();
  assert.equal(validateProfile({ humor: 'spicy' }).humor, 'cheeky');
  const old = await service.suggestions();
  await service.saveProfile({ seatedOnly: true, preferredActivities: ['rest'] });
  await assert.rejects(service.decide({ suggestionId: old.suggestion.id, decision: 'accept' }), error => error.error === 'preferences_changed');
  const fresh = await service.suggestions();
  assert.equal(fresh.suggestion.activityId, 'rest');
  await service.decide({ suggestionId: fresh.suggestion.id, decision: 'accept' });
  await service.saveProfile({ preferredActivities: ['breathe'] });
  assert.equal((await service.decide({ suggestionId: fresh.suggestion.id, decision: 'accept' })).status, 'already_created');
});

test('movement and energy changes invalidate cached suggestions without repeated paid calls', async () => {
  const { calendar } = fixture();
  let calls = 0;
  const provider = { async suggest({ candidates }) { calls += 1; return { ...candidates.find(candidate => candidate.activityId === 'walk'), quip: 'A short escape?', reason: 'An available calendar gap.', aiSource: 'grok' }; } };
  const service = new WellnessService(calendar, { suggestionProvider: provider });
  const first = await service.suggestions({ context: { movement: 'unknown', energy: 'unknown' } });
  assert.equal(first.suggestion.activityId, 'walk');
  const next = await service.suggestions({ context: { movement: 'active', energy: 'low' } });
  assert.notEqual(next.suggestion.id, first.suggestion.id);
  assert.ok(['rest', 'breathe'].includes(next.suggestion.activityId));
  assert.equal(next.aiSource, 'fallback');
  assert.equal(calls, 1, 'Rapid changes use an appropriate local fallback rather than charging repeatedly.');
  assert.equal((await service.suggestions({ context: { movement: 'active', energy: 'low', steps: 1001 } })).suggestion.id, next.suggestion.id);
});

test('late AI results cannot repopulate the cache after a profile change', async () => {
  const { calendar } = fixture();
  let resolveProvider;
  const provider = { suggest(input) { return new Promise(resolve => { resolveProvider = () => resolve({ ...input.candidates[0], quip: 'Late suggestion.', reason: 'Old preferences.', aiSource: 'grok' }); }); } };
  const service = new WellnessService(calendar, { suggestionProvider: provider });
  const old = service.suggestions().catch(error => error);
  await service.saveProfile({ seatedOnly: true, preferredActivities: ['rest'] });
  const fresh = await service.suggestions();
  resolveProvider();
  assert.equal((await old).error, 'preferences_changed');
  assert.equal((await service.suggestions()).suggestion.id, fresh.suggestion.id);
  assert.equal(fresh.suggestion.activityId, 'rest');
});

test('profile change between suggestion persistence and cache update is rejected', async () => {
  const { calendar, service } = fixture();
  const update = calendar.updateWellness.bind(calendar);
  let first = true;
  calendar.updateWellness = async callback => {
    const result = await update(callback);
    if (first) {
      first = false;
      await service.saveProfile({ seatedOnly: true, preferredActivities: ['rest'] });
    }
    return result;
  };
  await assert.rejects(service.suggestions(), error => error.error === 'preferences_changed');
  assert.equal((await service.suggestions()).suggestion.activityId, 'rest');
});

test('recorded feedback changes fallback activity ranking', async () => {
  const { service } = fixture();
  await service.saveProfile({ goals: ['breaks'], preferredActivities: ['walk', 'rest'] });
  const first = await service.suggestions();
  assert.equal(first.suggestion.activityId, 'walk');
  const { activity } = await service.decide({ suggestionId: first.suggestion.id, decision: 'accept' });
  await service.start({ activityId: activity.id });
  await service.complete({ activityId: activity.id, source: 'self_report' });
  await service.feedback({ activityId: activity.id, helpful: 'no' });
  assert.equal((await service.suggestions()).suggestion.activityId, 'rest');
});

test('QR setup capabilities are one-time, expire, and persist only hashes', async () => {
  const { OnboardingService, ONBOARDING_COOKIE } = await import('../onboarding.mjs');
  let now = BASE;
  const calendar = new DemoCalendar({ now: () => now });
  const onboarding = new OnboardingService(calendar, { publicOrigin: 'https://momo.example' });
  const issued = await onboarding.issue();
  const url = new URL(issued.url);
  assert.equal(url.pathname, '/onboard');
  assert.equal(url.search, '');
  const key = new URLSearchParams(url.hash.slice(1)).get('key');
  assert.equal(key.length, 43);
  assert.ok(issued.qr.length >= 21 && issued.qr.every(row => row.length === issued.qr.length && /^[01]+$/.test(row)));
  assert.equal(JSON.stringify(calendar.snapshot()).includes(key), false);
  const [first, replay] = await Promise.allSettled([onboarding.claim(key), onboarding.claim(key)]);
  assert.equal(first.status, 'fulfilled');
  assert.equal(replay.status, 'rejected');
  const token = first.value.sessionToken;
  assert.equal(JSON.stringify(calendar.snapshot()).includes(token), false);
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=${token}`), true);
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=invalid`), false);
  const restarted = new DemoCalendar({ now: () => now, initialState: calendar.snapshot() });
  assert.equal(new OnboardingService(restarted).authenticate(`${ONBOARDING_COOKIE}=${token}`), true);
  const expired = await onboarding.issue();
  const expiredKey = new URLSearchParams(new URL(expired.url).hash.slice(1)).get('key');
  now += 11 * MINUTE;
  await assert.rejects(onboarding.claim(expiredKey), error => error.httpStatus === 401);
  now += 24 * 60 * MINUTE;
  assert.equal(onboarding.authenticate(`${ONBOARDING_COOKIE}=${token}`), false);
});

test('phone onboarding grants profile access without granting watch or model access', async t => {
  const { OnboardingService } = await import('../onboarding.mjs');
  const { calendar } = fixture();
  let paidCalls = 0;
  const wellness = new WellnessService(calendar, { suggestionProvider: { isConfigured: () => true, async suggest() { paidCalls += 1; throw new Error('Must not be called'); } } });
  const onboarding = new OnboardingService(calendar, { publicOrigin: 'https://momo.example' });
  const server = createDemoServer(calendar, { wellness, onboarding, deviceToken: 'watch-only-private-token' });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const forwarded = { 'CF-Connecting-IP': '198.51.100.1' };
  const watch = async body => (await fetch(base, { method: 'POST', headers: { 'Content-Type': 'application/json', ...forwarded }, body: JSON.stringify(body) })).json();
  assert.equal((await fetch(`${base}/api/profile`, { headers: forwarded })).status, 401);
  const issued = await watch({ action: 'onboarding', token: 'watch-only-private-token' });
  const key = new URLSearchParams(new URL(issued.url).hash.slice(1)).get('key');
  const claim = await fetch(`${base}/api/onboarding/claim`, { method: 'POST', headers: { ...forwarded, Origin: 'https://momo.example', 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify({ key }) });
  const claimed = await claim.json();
  assert.equal(claimed.status, 'claimed');
  assert.equal(claimed.sessionToken, undefined);
  const cookie = claim.headers.get('set-cookie');
  assert.match(cookie, /HttpOnly/);
  assert.match(cookie, /Secure/);
  assert.match(cookie, /SameSite=Lax/);
  const session = cookie.split(';')[0];
  const profile = await fetch(`${base}/api/profile`, { headers: { ...forwarded, Cookie: session } });
  assert.equal(profile.status, 200);
  const saved = await (await fetch(`${base}/api/profile`, { method: 'POST', headers: { ...forwarded, Cookie: session, Origin: 'https://momo.example', 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify({ nickname: 'Phone user' }) })).json();
  assert.equal(saved.profile.nickname, 'Phone user');
  assert.equal((await fetch(`${base}/api/demo`, { headers: { ...forwarded, Cookie: session } })).status, 200);
  const forbidden = await watch({ action: 'suggestions' });
  assert.equal(forbidden.httpStatus, 401);
  assert.equal(paidCalls, 0);
  const cookieOnly = await (await fetch(base, { method: 'POST', headers: { ...forwarded, Cookie: session, Origin: 'https://momo.example', 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify({ action: 'suggestions' }) })).json();
  assert.equal(cookieOnly.httpStatus, 401);
  assert.equal(paidCalls, 0);
  assert.equal((await fetch(`${base}/api/profile`, { method: 'POST', headers: { ...forwarded, Cookie: session, Origin: 'https://attacker.example', 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: '{}' })).status, 403);
});

test('serverless snapshots preserve fixture meetings instead of creating a new busy period', () => {
  const original = new DemoCalendar({ now: () => BASE });
  const snapshot = original.snapshot();
  const later = new DemoCalendar({ now: () => BASE + 30 * MINUTE, initialState: snapshot });
  assert.deepEqual(later.meetings, original.meetings);
  assert.equal(later.availability().busyNow, false, 'The original focus block has finished.');
  assert.deepEqual(later.snapshot().meetings, snapshot.meetings);
  assert.deepEqual(new DemoCalendar({ initialState: { meetings: [], activities: [], wellness: {} } }).meetings, []);
});

test('cold starts reuse recommendation cache, context and AI metadata without another paid call', async () => {
  let now = BASE, calls = 0;
  const provider = { isConfigured: () => true, async suggest({ candidates }) { calls += 1; return { ...candidates[0], quip: 'A little escape?', reason: 'This fits your time.', aiSource: 'grok' }; } };
  const calendar = new DemoCalendar({ now: () => now });
  const service = new WellnessService(calendar, { suggestionProvider: provider });
  const first = await service.suggestions({ context: { movement: 'some', energy: 'okay', source: 'simulated' } });
  const snapshot = calendar.snapshot();
  assert.equal(snapshot.wellness.lastProviderCallAt, BASE);
  assert.equal(snapshot.wellness.lastAiSource, 'grok');
  assert.equal(snapshot.wellness.lastContext.movement, 'some');
  now += 1000;
  const restarted = new DemoCalendar({ now: () => now, initialState: snapshot });
  const next = new WellnessService(restarted, { suggestionProvider: provider });
  assert.equal(next.status().aiSource, 'grok');
  const cached = await next.suggestions();
  assert.equal(cached.suggestion.id, first.suggestion.id);
  assert.equal(calls, 1);
  now += MINUTE;
  assert.notEqual((await next.suggestions()).suggestion.id, first.suggestion.id);
  assert.equal(calls, 2);
});

test('provider cooldown survives cold starts while changed context gets a fresh local suggestion', async () => {
  let now = BASE, calls = 0;
  const provider = { async suggest({ candidates }) { calls += 1; return { ...candidates.find(candidate => candidate.activityId === 'walk'), quip: 'A little escape?', reason: 'A free slot fits.', aiSource: 'grok' }; } };
  const calendar = new DemoCalendar({ now: () => now });
  const service = new WellnessService(calendar, { suggestionProvider: provider });
  const first = await service.suggestions({ context: { movement: 'unknown' } });
  now += 1000;
  const restarted = new DemoCalendar({ now: () => now, initialState: calendar.snapshot() });
  const next = new WellnessService(restarted, { suggestionProvider: provider });
  const changed = await next.suggestions({ context: { movement: 'active', energy: 'low' } });
  assert.notEqual(changed.suggestion.id, first.suggestion.id);
  assert.ok(['rest', 'breathe'].includes(changed.suggestion.activityId));
  assert.equal(changed.aiSource, 'fallback');
  assert.equal(calls, 1);
});

test('profile changes and decisions clear persisted recommendation caches', async () => {
  const { calendar, service } = fixture();
  await service.suggestions();
  assert.ok(calendar.wellnessState.recommendationCache);
  await service.saveProfile({ preferredActivities: ['rest'] });
  assert.equal(calendar.wellnessState.recommendationCache, null);
  const fresh = await service.suggestions();
  assert.ok(calendar.wellnessState.recommendationCache);
  await service.decide({ suggestionId: fresh.suggestion.id, decision: 'snooze' });
  assert.equal(calendar.wellnessState.recommendationCache, null);
  const restarted = new WellnessService(new DemoCalendar({ now: () => BASE, initialState: calendar.snapshot() }));
  assert.equal((await restarted.suggestions()).status, 'snoozed');
});

test('pending check-ins prevent new model calls across booked, running and awaiting-feedback cold starts', async () => {
  let now = BASE, calls = 0;
  const provider = { isConfigured: () => true, async suggest({ candidates }) { calls += 1; return { ...candidates[0], quip: 'Tiny rest time.', reason: 'A gap fits your preferences.', aiSource: 'grok' }; } };
  let calendar = new DemoCalendar({ now: () => now });
  let service = new WellnessService(calendar, { suggestionProvider: provider });
  const restart = () => {
    calendar = new DemoCalendar({ now: () => now, initialState: calendar.snapshot() });
    service = new WellnessService(calendar, { suggestionProvider: provider });
  };
  await service.saveProfile({ preferredActivities: ['rest'] });
  const { suggestion } = await service.suggestions();
  const { activity } = await service.decide({ suggestionId: suggestion.id, decision: 'accept' });
  assert.equal(calendar.wellnessState.recommendationCache, null);
  restart();
  const booked = await service.suggestions({ context: { movement: 'active' } });
  assert.equal(booked.status, 'check_in');
  assert.equal(booked.suggestion, null);
  assert.equal(booked.checkIn.status, 'booked');
  await service.start({ activityId: activity.id });
  restart();
  assert.equal((await service.suggestions()).checkIn.status, 'running');
  await service.complete({ activityId: activity.id, source: 'self_report' });
  restart();
  assert.equal((await service.suggestions()).checkIn.status, 'completed');
  assert.equal(calls, 1);
  await service.feedback({ activityId: activity.id, helpful: 'yes' });
  assert.equal(calendar.wellnessState.recommendationCache, null);
  now += 6000;
  restart();
  const next = await service.suggestions();
  assert.ok(next.suggestion);
  assert.equal(next.checkIn, null);
  assert.equal(calls, 2);
});
