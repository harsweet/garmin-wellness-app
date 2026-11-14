import test from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import path from 'node:path';
import { DemoCalendar } from '../demo-calendar.mjs';
import { createDemoServer } from '../server.mjs';

const BASE = Date.parse('2026-11-14T17:00:00Z'); // 10am in Edmonton.
const MINUTE = 60_000;

test('suggestions respect meetings, buffers, daytime, and 8-minute duration', () => {
  const calendar = new DemoCalendar({ now: () => BASE });
  const availability = calendar.availability();
  assert.equal(availability.mode, 'demo');
  assert.equal(availability.busyNow, true);
  assert.equal(availability.slots.length, 3);
  assert.equal(calendar.activities.length, 0, 'Finding a slot must never book anything.');
  for (const slot of availability.slots) {
    const start = Date.parse(slot.start);
    const end = Date.parse(slot.end);
    assert.equal(end - start, 8 * MINUTE);
    assert.ok(calendar.inDaytime(start, end));
    assert.ok(calendar.isFree(start, end));
  }
});

test('concurrent confirmations and retries create only one walk', async () => {
  const calendar = new DemoCalendar({ now: () => BASE });
  const slot = calendar.availability().slots[0];
  const replies = await Promise.all([calendar.book(slot.id), calendar.book(slot.id), calendar.book(slot.id)]);
  assert.deepEqual(replies.map(reply => reply.status), ['created', 'already_created', 'already_created']);
  assert.equal(calendar.activities.length, 1);
  assert.equal(calendar.isFree(Date.parse(slot.start), Date.parse(slot.end)), false);
});

test('booking rechecks conflicts and rejects expired or invented slots', async () => {
  let now = BASE;
  const calendar = new DemoCalendar({ now: () => now });
  const [slot, expiring] = calendar.availability().slots;
  calendar.meetings.push({ id: 'new', title: 'New demo meeting', start: Date.parse(slot.start), end: Date.parse(slot.end) });
  await assert.rejects(calendar.book(slot.id), error => error.httpStatus === 409);
  now += 11 * MINUTE;
  await assert.rejects(calendar.book(expiring.id), error => error.httpStatus === 410);
  await assert.rejects(calendar.book('invented'), error => error.httpStatus === 410);
  assert.equal(calendar.activities.length, 0);
});

test('saved demo walks survive restart and remain idempotent', async () => {
  const directory = await mkdtemp(path.join(tmpdir(), 'momo-demo-'));
  try {
    const options = { now: () => BASE, stateFile: path.join(directory, 'calendar.json') };
    const calendar = new DemoCalendar(options);
    const slot = calendar.availability().slots[0];
    await calendar.book(slot.id);
    const restarted = new DemoCalendar(options);
    await restarted.load();
    assert.equal(restarted.activities.length, 1);
    assert.equal((await restarted.book(slot.id)).status, 'already_created');
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
});

test('daytime scheduling handles a timezone with daylight saving changes', () => {
  const now = Date.parse('2026-11-01T05:30:00Z');
  const calendar = new DemoCalendar({ now: () => now, timeZone: 'America/New_York' });
  calendar.meetings = [];
  const slots = calendar.availability().slots;
  assert.equal(slots.length, 3);
  assert.ok(slots.every(slot => calendar.inDaytime(Date.parse(slot.start), Date.parse(slot.end))));
  assert.ok(slots.every(slot => Date.parse(slot.start) > now));
});

test('actual HTTP contract supports watch requests and calendar page updates', async t => {
  const calendar = new DemoCalendar({ now: () => BASE });
  const server = createDemoServer(calendar);
  await new Promise(resolve => server.listen(0, '127.0.0.1', resolve));
  t.after(() => new Promise(resolve => server.close(resolve)));
  const base = `http://127.0.0.1:${server.address().port}`;
  const post = async body => (await fetch(base, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(body) })).json();
  assert.equal((await post({ action: 'availability' })).httpStatus, 401);
  const availability = await post({ action: 'availability', token: 'momo-demo' });
  assert.equal(availability.slots.length, 3);
  const reply = await post({ action: 'activities', token: 'momo-demo', slotId: availability.slots[0].id });
  assert.equal(reply.status, 'created');
  const events = await (await fetch(`${base}/api/demo`)).json();
  assert.equal(events.activities, 1);
  assert.ok(events.events.some(event => event.title === 'Momo: 8-minute walk'));
  assert.match(await (await fetch(base)).text(), /Momo demo calendar/);
  const crossOrigin = await fetch(base, { method: 'POST', headers: { Origin: 'https://unrelated.example' }, body: '{}' });
  assert.equal(crossOrigin.status, 403);
});
