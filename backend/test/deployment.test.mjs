import test from 'node:test';
import assert from 'node:assert/strict';
import http from 'node:http';
import { createVercelHandler } from '../../api/index.mjs';
import { RedisStateStore } from '../redis-store.mjs';

class MemoryStore {
  state = null;
  queue = Promise.resolve();
  withLock(callback) {
    const action = this.queue.then(() => callback({ load: async () => structuredClone(this.state), save: async value => { this.state = structuredClone(value); } }));
    this.queue = action.catch(() => {});
    return action;
  }
}

const env = { MOMO_DEVICE_TOKEN: 'x'.repeat(43), MOMO_PUBLIC_URL: 'https://momo.vercel.app' };

test('serverless cold starts preserve QR onboarding, profiles, and accepted activities', async t => {
  const store = new MemoryStore();
  // Recreate the handler on every request, like repeated cold starts.
  const server = http.createServer(async (request, response) => {
    if (request.method === 'POST') {
      let raw = '';
      for await (const chunk of request) raw += chunk;
      request.body = JSON.parse(raw);
    }
    return createVercelHandler({ env, store })(request, response);
  });
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  async function call(route, body, cookie, auth = true) {
    const response = await fetch(`${base}/api/index?momoPath=${encodeURIComponent(route)}`, {
      method: body ? 'POST' : 'GET',
      headers: { Host: 'momo.vercel.app', ...(body ? { Origin: 'https://momo.vercel.app', 'X-Momo-Request': '1', 'Content-Type': 'application/json' } : {}), ...(cookie ? { Cookie: cookie } : {}) },
      ...(body ? { body: JSON.stringify(auth && body.action ? { ...body, token: env.MOMO_DEVICE_TOKEN } : body) } : {})
    });
    return { response, data: await response.json() };
  }
  assert.equal((await call('/api/profile')).response.status, 401, 'Cloud profiles never use a loopback bypass.');
  const issued = (await call('/', { action: 'onboarding' })).data;
  assert.ok(issued.url.startsWith('https://momo.vercel.app/onboard#key='));
  assert.ok(issued.qr.length > 20);
  const key = new URLSearchParams(new URL(issued.url).hash.slice(1)).get('key');
  const claimed = await call('/api/onboarding/claim', { key });
  assert.equal(claimed.data.status, 'claimed');
  const cookie = claimed.response.headers.get('set-cookie').split(';')[0];
  assert.match(claimed.response.headers.get('set-cookie'), /HttpOnly/);
  const profile = (await call('/api/profile', null, cookie)).data.profile;
  const saved = await call('/api/profile', { ...profile, nickname: 'Ari', preferredActivities: ['rest'], maxBreakMinutes: 2 }, cookie);
  assert.equal(saved.data.configured, true);
  assert.equal((await call('/', { action: 'status' })).data.profileConfigured, true);
  const suggestion = (await call('/', { action: 'suggestions' })).data.suggestion;
  assert.equal(suggestion.activityId, 'rest');
  const accepted = (await call('/', { action: 'decide', suggestionId: suggestion.id, decision: 'accept' })).data;
  assert.equal(accepted.status, 'created');
  const repeated = (await call('/', { action: 'decide', suggestionId: suggestion.id, decision: 'accept' })).data;
  assert.equal(repeated.status, 'already_created');
  assert.equal(store.state.users[store.state.defaultUserId].calendar.activities.length, 1);
  assert.equal((await call('/api/profile', null, cookie)).data.profile.nickname, 'Ari');
  const denied = await call('/', { action: 'suggestions' }, cookie, false);
  assert.equal(denied.data.httpStatus, 401, 'A phone session cannot invoke the AI or act as the watch.');
});

test('cloud deployment fails closed when persistent storage or device token is missing', async t => {
  const handler = createVercelHandler({ env: {} });
  const server = http.createServer(handler);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const response = await fetch(`http://127.0.0.1:${server.address().port}/health`);
  assert.equal(response.status, 503);
  assert.equal((await response.json()).error, 'service_unavailable');
});

test('Redis writes require the active lock and release only their own lease', async () => {
  const commands = [];
  const store = new RedisStateStore({ url: 'https://example.upstash.io', token: 'private-test-token', fetchImpl: async (_url, options) => {
    const command = JSON.parse(options.body);
    commands.push(command);
    const result = command[0] === 'SET' ? 'OK' : command[0] === 'GET' ? null : 1;
    return { ok: true, json: async () => ({ result }) };
  } });
  await store.withLock(async lease => { assert.equal(await lease.load(), null); await lease.save({ activities: [] }); });
  assert.deepEqual(commands[0].slice(-3), ['NX', 'PX', '45000']);
  assert.equal(commands.filter(command => command[0] === 'EVAL').length, 2);
  assert.ok(commands.filter(command => command[0] === 'EVAL').every(command => command[1].includes("redis.call('get',KEYS[1]) == ARGV[1]")));
});
