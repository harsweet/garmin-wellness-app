import { randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import path from 'node:path';

const MINUTE = 60_000;
const WALK = 8 * MINUTE;
const BUFFER = 2 * MINUTE;

export class CalendarError extends Error {
  constructor(httpStatus, error, message) {
    super(message);
    this.httpStatus = httpStatus;
    this.error = error;
  }
}

// A deliberately local fixture calendar. This module never calls Google.
export class DemoCalendar {
  constructor({ now = () => Date.now(), timeZone = 'America/Edmonton', stateFile = null } = {}) {
    this.now = now;
    this.timeZone = timeZone;
    this.stateFile = stateFile;
    this.activities = [];
    this.slots = new Map();
    this.queue = Promise.resolve();
    this.clock = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
    this.label = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', hour: 'numeric', minute: '2-digit' });
    const base = now();
    this.meetings = [
      { id: 'fixture-focus', title: 'Demo focus session', start: base - 10 * MINUTE, end: base + 10 * MINUTE },
      { id: 'fixture-team', title: 'Demo team check-in', start: base + 45 * MINUTE, end: base + 65 * MINUTE },
      { id: 'fixture-review', title: 'Demo project review', start: base + 110 * MINUTE, end: base + 140 * MINUTE }
    ];
  }

  async load() {
    if (!this.stateFile) return;
    try {
      const saved = JSON.parse(await readFile(this.stateFile, 'utf8'));
      if (!Array.isArray(saved.activities)) throw new Error('Invalid demo calendar state.');
      this.activities = saved.activities.filter(event => typeof event.id === 'string' && Number.isFinite(event.start) && Number.isFinite(event.end));
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }

  status() {
    return { mode: 'demo', configured: true, connected: true, timeZone: this.timeZone, calendarName: 'Momo demo calendar' };
  }

  allEvents() {
    return [...this.meetings, ...this.activities].sort((a, b) => a.start - b.start);
  }

  isFree(start, end) {
    return !this.allEvents().some(event => start < event.end + BUFFER && end > event.start - BUFFER);
  }

  inDaytime(start, end) {
    const parts = value => Object.fromEntries(this.clock.formatToParts(new Date(value)).map(part => [part.type, part.value]));
    const a = parts(start);
    const b = parts(end);
    return a.year === b.year && a.month === b.month && a.day === b.day && Number(a.hour) >= 8 && Number(b.hour) < 20;
  }

  availability() {
    const now = this.now();
    for (const [id, slot] of this.slots) if (slot.expiresAt < now) this.slots.delete(id);
    const slots = [];
    let start = Math.ceil((now + BUFFER) / (5 * MINUTE)) * 5 * MINUTE;
    const horizon = now + 24 * 60 * MINUTE;
    while (start + WALK <= horizon && slots.length < 3) {
      const end = start + WALK;
      if (this.inDaytime(start, end) && this.isFree(start, end)) {
        const id = randomUUID();
        const label = this.label.format(new Date(start));
        this.slots.set(id, { id, label, start, end, expiresAt: now + 10 * MINUTE });
        slots.push({ id, label, start: new Date(start).toISOString(), end: new Date(end).toISOString(), durationMinutes: 8 });
        start += 15 * MINUTE;
      } else {
        start += 5 * MINUTE;
      }
    }
    return {
      ...this.status(), checkedAt: new Date(now).toISOString(),
      busyNow: this.allEvents().some(event => event.start <= now && now < event.end),
      slots, message: slots.length ? 'Your chair can survive eight minutes without you.' : 'No gaps right now. Let us check again later.'
    };
  }

  // Serialize writes: repeated taps or uncertain network retries cannot duplicate a walk.
  book(slotId) {
    const operation = this.queue.then(() => this.createActivity(slotId));
    this.queue = operation.catch(() => {});
    return operation;
  }

  async createActivity(slotId) {
    const existing = this.activities.find(event => event.id === slotId);
    if (existing) return this.createdReply(existing, 'already_created');
    const slot = this.slots.get(slotId);
    if (!slot || slot.expiresAt < this.now() || slot.start <= this.now()) {
      throw new CalendarError(410, 'expired', 'That suggestion expired. Find a fresh slot.');
    }
    if (!this.isFree(slot.start, slot.end)) {
      throw new CalendarError(409, 'conflict', 'That time is busy now. Find another slot.');
    }
    const event = { id: slot.id, title: 'Momo: 8-minute walk', label: slot.label, start: slot.start, end: slot.end };
    const next = [...this.activities, event];
    // Commit to disk before acknowledging the write, and use an atomic replacement.
    if (this.stateFile) {
      await mkdir(path.dirname(this.stateFile), { recursive: true });
      const temporary = `${this.stateFile}.tmp`;
      await writeFile(temporary, JSON.stringify({ activities: next }), { mode: 0o600 });
      await rename(temporary, this.stateFile);
    }
    this.activities = next;
    return this.createdReply(event, 'created');
  }

  createdReply(event, status) {
    return { ...this.status(), status, label: event.label, eventUrl: '', start: new Date(event.start).toISOString(), end: new Date(event.end).toISOString() };
  }
}
