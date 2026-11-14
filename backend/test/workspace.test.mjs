import test from 'node:test';
import assert from 'node:assert/strict';
import { MomoWorkspace } from '../workspace.mjs';
import { ONBOARDING_COOKIE } from '../onboarding.mjs';

const TOKEN = 'x'.repeat(43);
const ORIGIN = 'https://momo.example';
const NOW = Date.parse('2026-11-14T17:00:00Z');

function workspace() {
  return new MomoWorkspace({
    deviceToken: TOKEN,
    adminToken: 'y'.repeat(43),
    publicOrigin: ORIGIN,
    allowLocalSetup: true,
    now: () => NOW,
    save: async () => {}
  });
}

async function listen(workspace, t) {
  const server = workspace.createServer();
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  return {
    base,
    async call(path, body, headers = {}) {
      const response = await fetch(`${base}${path}`, {
        method: body === undefined ? 'GET' : 'POST',
        headers: {
          ...(body === undefined ? {} : { 'Content-Type': 'application/json', Origin: base, 'X-Momo-Request': '1' }),
          ...headers
        },
        ...(body === undefined ? {} : { body: JSON.stringify(body) })
      });
      return { response, data: await response.json(), cookie: response.headers.get('set-cookie') };
    }
  };
}

test('fresh onboarding mints a new device only after the current watch is already paired', async t => {
  const { call } = await listen(workspace(), t);
  const first = await call('/', { action: 'onboarding', token: TOKEN, fresh: true });
  assert.equal(first.data.profileConfigured, false);
  assert.match(first.data.code, /^\d{4}$/);
  const again = await call('/', { action: 'onboarding', token: TOKEN, fresh: true });
  assert.equal(again.data.userId, first.data.userId);

  const key = new URLSearchParams(new URL(first.data.url).hash.slice(1)).get('key');
  const claimed = await call('/api/onboarding/claim', { key });
  assert.equal(claimed.data.status, 'claimed');
  const cookie = claimed.cookie.split(';')[0];
  assert.equal((await call('/api/profile')).response.status, 401, 'Phone setup cannot skip the watch code.');
  const saved = await call('/api/profile', { goals: ['breaks'], additionalContext: 'Desk days. Short resets.' }, { Cookie: cookie });
  assert.equal(saved.data.configured, true);

  const roster = (await call('/api/admin/users')).data;
  assert.equal(roster.users.length, 1);
  assert.equal(roster.users[0].configured, true);
  assert.equal(roster.users[0].pairingState, 'paired');
  assert.deepEqual(roster.users[0].profile.goals, ['breaks']);
  assert.equal(roster.users[0].profile.additionalContext, 'Desk days. Short resets.');

  const reuse = await call('/', { action: 'onboarding', token: TOKEN });
  assert.equal(reuse.data.userId, first.data.userId, 'Menu setup keeps this watch.');
  const minted = await call('/', { action: 'onboarding', token: TOKEN, fresh: true });
  assert.notEqual(minted.data.userId, first.data.userId);
  const after = (await call('/api/admin/users')).data;
  assert.equal(after.users.length, 2);
  assert.equal(after.activeUserId, minted.data.userId);
  const waiting = after.users.find(user => user.id === minted.data.userId);
  assert.equal(waiting.configured, false);
  assert.equal(waiting.pairingState, 'waiting');
  assert.equal(waiting.activeWatch, true);
});

test('claimed setup stores ratings on the paired device the phone connected to', async t => {
  const { call } = await listen(workspace(), t);
  const issued = await call('/', { action: 'onboarding', token: TOKEN });
  const claimed = await call('/api/onboarding/claim', { code: issued.data.code });
  const cookie = claimed.cookie.split(';')[0];
  await call('/api/profile', { goals: ['move', 'breaks'], additionalContext: 'Prefer walking.' }, { Cookie: cookie });
  const suggestion = (await call('/', { action: 'suggestions', token: TOKEN })).data.suggestion;
  const accepted = await call('/', { action: 'decide', token: TOKEN, suggestionId: suggestion.id, decision: 'accept' });
  const activityId = accepted.data.activity.id;
  await call('/', { action: 'start', token: TOKEN, activityId });
  await call('/', { action: 'complete', token: TOKEN, activityId, source: 'self_report', elapsedSeconds: 120, steps: 0 });
  await call('/', { action: 'feedback', token: TOKEN, activityId, helpful: 'yes' });
  const roster = (await call('/api/admin/users')).data.users[0];
  assert.equal(roster.counts.accepted, 1);
  assert.equal(roster.counts.completed, 1);
  assert.equal(roster.counts.helpful, 1);
  assert.ok(roster.preferences.some(item => item.helpful >= 1));
  assert.equal(cookie.startsWith(`${ONBOARDING_COOKIE}=`), true);
});
