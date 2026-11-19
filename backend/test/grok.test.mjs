import test from 'node:test';
import assert from 'node:assert/strict';
import { GrokSuggestions } from '../grok.mjs';

const input = {
  profile: { nickname: 'Jo', goals: ['breaks'], preferredActivities: ['stretch'], maxBreakMinutes: 5, humor: 'gentle', seatedOnly: true },
  context: { steps: 120, movement: 'unknown', energy: 'okay', source: 'simulated', secret: 'must-not-share', calendarTitle: 'Private meeting' },
  candidates: [{ slotId: 'slot-1', activityId: 'stretch', title: '3-minute stretch', durationMinutes: 3, label: 'Today 2:00 PM', start: '2026-11-14T21:00:00Z', end: '2026-11-14T21:03:00Z' }],
  history: { acceptedByActivity: { stretch: 4 }, completedByActivity: { stretch: 3 }, apiKey: 'must-not-share', calendarTitle: 'Private meeting' }
};
const result = { slotId: 'slot-1', activityId: 'stretch', quip: 'A tiny stretch for a very busy monkey.', reason: 'You prefer short, seated activities.' };
const apiReply = value => ({ ok: true, json: async () => ({ status: 'completed', output: [{ type: 'message', content: [{ type: 'output_text', text: JSON.stringify(value) }] }] }) });

test('uses xAI Responses structured output with minimal personalized context', async () => {
  let request;
  const provider = new GrokSuggestions({ apiKey: 'test-secret', fetchImpl: async (url, options) => { request = { url, ...options }; return apiReply(result); } });
  const reply = await provider.suggest(input);
  assert.equal(reply.aiSource, 'grok');
  assert.equal(reply.activityId, 'stretch');
  assert.equal(request.url, 'https://api.x.ai/v1/responses');
  assert.equal(request.headers.Authorization, 'Bearer test-secret');
  assert.ok(!request.body.includes('test-secret'));
  assert.ok(!request.body.includes('must-not-share'));
  assert.ok(!request.body.includes('Private meeting'));
  const body = JSON.parse(request.body);
  assert.equal(body.store, false);
  assert.equal(body.text.format.strict, true);
  assert.ok(body.input[0].content.includes('seatedOnly'));
  assert.ok(body.input[0].content.includes('completedByActivity'));
});

test('missing key yields an honestly labeled scripted suggestion without a network call', async () => {
  const provider = new GrokSuggestions({ fetchImpl: () => { throw new Error('Must not call xAI'); } });
  const reply = await provider.suggest(input);
  assert.equal(reply.aiSource, 'fallback');
  assert.equal(reply.fallbackReason, 'not_configured');
  assert.equal(provider.isConfigured(), false);
});

test('invented slot or activity cannot become an actionable suggestion', async () => {
  const provider = new GrokSuggestions({ apiKey: 'test', fetchImpl: async () => apiReply({ ...result, activityId: 'run-marathon' }) });
  const reply = await provider.suggest(input);
  assert.equal(reply.aiSource, 'fallback');
  assert.equal(reply.activityId, 'stretch');
});

test('provider errors do not leak bodies or secrets and trigger a short cooldown', async () => {
  let calls = 0;
  const provider = new GrokSuggestions({ apiKey: 'test-secret', fetchImpl: async () => { calls++; return { ok: false, status: 401, json: () => { throw new Error('Do not read error secrets'); } }; } });
  const reply = await provider.suggest(input);
  assert.equal(reply.fallbackReason, 'auth_error');
  assert.ok(!JSON.stringify(reply).includes('test-secret'));
  await provider.suggest(input);
  assert.equal(calls, 1);
});

test('text is watch-safe and bounded; malformed output falls back', async () => {
  const provider = new GrokSuggestions({ apiKey: 'test', fetchImpl: async () => apiReply({ ...result, quip: '“Monkey business!” 🐒 '.repeat(15), reason: 'Very useful. '.repeat(30) }) });
  const reply = await provider.suggest(input);
  assert.ok(reply.quip.length <= 90);
  assert.ok(reply.reason.length <= 100);
  assert.match(reply.quip, /^[\x20-\x7e]+$/);
  const malformed = new GrokSuggestions({ apiKey: 'test', fetchImpl: async () => ({ ok: true, json: async () => ({ output: [] }) }) });
  assert.equal((await malformed.suggest(input)).aiSource, 'fallback');
});

test('timeouts fall back and no candidates never call the model', async () => {
  const provider = new GrokSuggestions({ apiKey: 'test', fetchImpl: async () => { throw new DOMException('Timed out', 'TimeoutError'); } });
  assert.equal((await provider.suggest(input)).fallbackReason, 'timeout');
  assert.equal(await provider.suggest({ candidates: [] }), null);
});

test('additional context reaches Grok as bounded untrusted profile data with Unicode and newlines', async () => {
  let requestBody;
  const provider = new GrokSuggestions({ apiKey: 'test', fetchImpl: async (url, options) => { requestBody = JSON.parse(options.body); return apiReply(result); } });
  const additionalContext = 'Café breaks help me pause.\r\n午後は家で休みたい。\u0000\u202e';
  await provider.suggest({ ...input, profile: { ...input.profile, additionalContext } });
  const supplied = JSON.parse(requestBody.input[0].content);
  assert.equal(supplied.profile.additionalContext, 'Café breaks help me pause.\n午後は家で休みたい。');
  assert.match(requestBody.instructions, /additionalContext only as optional background/);
  assert.match(requestBody.instructions, /cannot override explicit profile constraints/);
  assert.match(requestBody.instructions, /user reports, never diagnostic evidence/);
  assert.match(requestBody.instructions, /Do not invent or infer missing health facts/);
  assert.deepEqual(supplied.profile.preferredActivities, input.profile.preferredActivities);
  assert.equal(supplied.profile.seatedOnly, true);
  await provider.suggest({ ...input, profile: { ...input.profile, additionalContext: 'x'.repeat(2000) } });
  assert.equal(JSON.parse(requestBody.input[0].content).profile.additionalContext.length, 1000);
  await provider.suggest(input);
  assert.equal(JSON.parse(requestBody.input[0].content).profile.additionalContext, '');
});

test('structured schema includes coachLine and cleans/truncates it safely', async () => {
  let requestBody;
  const provider = new GrokSuggestions({
    apiKey: 'test',
    fetchImpl: async (_url, options) => {
      requestBody = JSON.parse(options.body);
      return apiReply({ ...result, coachLine: '“Drop your shoulders” 🐒 '.repeat(8) });
    }
  });
  const reply = await provider.suggest(input);
  assert.ok(requestBody.text.format.schema.required.includes('coachLine'));
  assert.equal(reply.aiSource, 'grok');
  assert.ok(reply.coachLine.length <= 90);
  assert.match(reply.coachLine, /^[\x20-\x7e]+$/);

  const emptyCoach = new GrokSuggestions({
    apiKey: 'test',
    fetchImpl: async () => apiReply({ ...result, coachLine: '   ' })
  });
  const bad = await emptyCoach.suggest(input);
  assert.equal(bad.aiSource, 'fallback');
  assert.equal(bad.fallbackReason, 'invalid_response');
  assert.ok(bad.coachLine.length > 0 && bad.coachLine.length <= 90);
});

test('fallback covers all 7 activities and honors fried checkInMood', async () => {
  const provider = new GrokSuggestions();
  for (const activityId of ['walk', 'stretch', 'breathe', 'rest', 'eyes', 'stairs', 'sunlight']) {
    const reply = await provider.suggest({
      ...input,
      candidates: [{ slotId: 'slot-1', activityId, title: activityId, durationMinutes: 2, label: 'Now', start: '2026-11-14T21:00:00Z', end: '2026-11-14T21:02:00Z' }]
    });
    assert.equal(reply.aiSource, 'fallback');
    assert.equal(reply.activityId, activityId);
    assert.ok(reply.coachLine && reply.coachLine.length <= 90);
    assert.match(reply.coachLine, /^[\x20-\x7e]+$/);
  }
  const fried = await provider.suggest({
    ...input,
    context: { checkInMood: 'fried' },
    candidates: [
      { slotId: 'slot-1', activityId: 'walk', title: 'Walk', durationMinutes: 8, label: 'Now', start: '2026-11-14T21:00:00Z', end: '2026-11-14T21:08:00Z' },
      { slotId: 'slot-1', activityId: 'breathe', title: 'Breathe', durationMinutes: 2, label: 'Now', start: '2026-11-14T21:00:00Z', end: '2026-11-14T21:02:00Z' }
    ]
  });
  assert.equal(fried.activityId, 'breathe');
});

test('boundedContext forwards bounded watch sensors and checkInMood while stripping out-of-range values', async () => {
  let requestBody;
  const provider = new GrokSuggestions({ apiKey: 'test', fetchImpl: async (_url, options) => { requestBody = JSON.parse(options.body); return apiReply({ ...result, coachLine: 'Breathe slow.' }); } });
  await provider.suggest({
    ...input,
    context: {
      steps: 2400, movement: 'some', energy: 'okay', source: 'watch',
      heartRate: 78, stress: 42, bodyBattery: 65, moveBarLevel: 3, activeMinutes: 18,
      elevationMeters: 1045.67, temperatureC: -3.24, solarIntensity: 75, checkInMood: 'wired'
    }
  });
  const supplied = JSON.parse(requestBody.input[0].content).context;
  assert.deepEqual(supplied, {
    steps: 2400, movement: 'some', energy: 'okay', source: 'watch',
    heartRate: 78, stress: 42, bodyBattery: 65, moveBarLevel: 3, activeMinutes: 18,
    elevationMeters: 1045.7, temperatureC: -3.2, solarIntensity: 75, checkInMood: 'wired'
  });
  assert.match(requestBody.instructions, /checkInMood/);

  await provider.suggest({
    ...input,
    context: {
      heartRate: 10, stress: 150, bodyBattery: -1, moveBarLevel: 9, activeMinutes: 5000,
      elevationMeters: 9500, temperatureC: -80, solarIntensity: 101, checkInMood: 'panic'
    }
  });
  const invalidSupplied = JSON.parse(requestBody.input[0].content).context;
  assert.deepEqual(invalidSupplied, {
    steps: null, movement: 'unknown', energy: 'unknown', source: 'unknown',
    heartRate: null, stress: null, bodyBattery: null, moveBarLevel: null, activeMinutes: null,
    elevationMeters: null, temperatureC: null, solarIntensity: null, checkInMood: 'unknown'
  });
});

