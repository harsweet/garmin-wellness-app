import { randomUUID } from 'node:crypto';
import { mkdir, readFile, writeFile, rename } from 'node:fs/promises';
import path from 'node:path';

const MINUTE = 60_000;
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
  constructor({ now = () => Date.now(), timeZone = 'America/Edmonton', stateFile = null, initialState = null } = {}) {
    this.now = now;
    this.stateFile = stateFile;
    this.activities = Array.isArray(initialState?.activities) ? structuredClone(initialState.activities) : [];
    this.wellnessState = initialState?.wellness && typeof initialState.wellness === 'object' ? structuredClone(initialState.wellness) : {};
    this.slots = new Map();
    this.queue = Promise.resolve();
    this.setPreferences({ timeZone });
    const base = now();
    this.meetings = Array.isArray(initialState?.meetings) ? structuredClone(initialState.meetings).filter(event => event && typeof event.id === 'string' && Number.isFinite(event.start) && Number.isFinite(event.end) && event.end > event.start) : [
      { id: 'fixture-focus', title: 'Demo focus session', start: base - 10 * MINUTE, end: base + 10 * MINUTE },
      { id: 'fixture-team', title: 'Demo team check-in', start: base + 45 * MINUTE, end: base + 65 * MINUTE },
      { id: 'fixture-review', title: 'Demo project review', start: base + 110 * MINUTE, end: base + 140 * MINUTE }
    ];
  }

  setPreferences({ timeZone = this.timeZone || 'America/Edmonton', reminderStart = '08:00', reminderEnd = '20:00' } = {}) {
    this.timeZone = timeZone;
    this.reminderStart = reminderStart;
    this.reminderEnd = reminderEnd;
    this.clock = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit', hourCycle: 'h23' });
    this.label = new Intl.DateTimeFormat('en-US', { timeZone, weekday: 'short', hour: 'numeric', minute: '2-digit' });
  }

  async load() {
    if (!this.stateFile) return;
    try {
      const saved = JSON.parse(await readFile(this.stateFile, 'utf8'));
      if (!Array.isArray(saved.activities)) throw new Error('Invalid demo calendar state.');
      this.activities = saved.activities.filter(event => typeof event.id === 'string' && Number.isFinite(event.start) && Number.isFinite(event.end));
      this.wellnessState = saved.wellness && typeof saved.wellness === 'object' && !Array.isArray(saved.wellness) ? saved.wellness : {};
    } catch (error) {
      if (error.code !== 'ENOENT') throw error;
    }
  }

  snapshot() { return { meetings: structuredClone(this.meetings), activities: structuredClone(this.activities), wellness: structuredClone(this.wellnessState) }; }

  async persist(activities = this.activities, wellness = this.wellnessState) {
    if (!this.stateFile) return;
    await mkdir(path.dirname(this.stateFile), { recursive: true });
    const temporary = `${this.stateFile}.tmp`;
    await writeFile(temporary, JSON.stringify({ meetings: this.meetings, activities, wellness }), { mode: 0o600 });
    await rename(temporary, this.stateFile);
  }

  transact(operation) {
    const result = this.queue.then(operation);
    this.queue = result.catch(() => {});
    return result;
  }

  updateWellness(update) {
    return this.transact(async () => {
      const next = structuredClone(this.wellnessState);
      const result = update(next);
      await this.persist(this.activities, next);
      this.wellnessState = next;
      return result;
    });
  }

  status() {
    return { mode: 'demo', configured: true, connected: true, timeZone: this.timeZone, calendarName: 'Momo demo calendar' };
  }

  allEvents() { return [...this.meetings, ...this.activities].sort((a, b) => a.start - b.start); }

  isFree(start, end) {
    return !this.allEvents().some(event => start < event.end + BUFFER && end > event.start - BUFFER);
  }

  inDaytime(start, end) {
    const parts = value => Object.fromEntries(this.clock.formatToParts(new Date(value)).map(part => [part.type, part.value]));
    const minutes = text => Number(text.slice(0, 2)) * 60 + Number(text.slice(3));
    const a = parts(start), b = parts(end);
    const lo = minutes(this.reminderStart), hi = minutes(this.reminderEnd);
    const from = Number(a.hour) * 60 + Number(a.minute), to = Number(b.hour) * 60 + Number(b.minute);
    if (lo < hi) return a.year === b.year && a.month === b.month && a.day === b.day && from >= lo && to <= hi;
    // Overnight reminder windows also work for people with irregular schedules.
    return (from >= lo || from < hi) && (to > lo || to <= hi);
  }

  availability() {
    const now = this.now();
    for (const [id, slot] of this.slots) if (slot.expiresAt < now) this.slots.delete(id);
    const slots = [];
    let start = Math.ceil((now + BUFFER) / (5 * MINUTE)) * 5 * MINUTE;
    const horizon = now + 24 * 60 * MINUTE;
    while (start + 8 * MINUTE <= horizon && slots.length < 3) {
      const end = start + 8 * MINUTE;
      if (this.inDaytime(start, end) && this.isFree(start, end)) {
        const id = randomUUID(), label = this.label.format(new Date(start));
        this.slots.set(id, { id, label, start, end, expiresAt: now + 10 * MINUTE });
        slots.push({ id, label, start: new Date(start).toISOString(), end: new Date(end).toISOString(), durationMinutes: 8 });
        start += 15 * MINUTE;
      } else start += 5 * MINUTE;
    }
    return {
      ...this.status(), checkedAt: new Date(now).toISOString(),
      busyNow: this.allEvents().some(event => event.start <= now && now < event.end),
      slots, message: slots.length ? 'Your chair can survive eight minutes without you.' : 'No gaps right now. Let us check again later.'
    };
  }

  book(slotId, activity = {}) { return this.transact(() => this.createActivity(slotId, activity)); }

  async createActivity(slotId, activity = {}) {
    const existing = this.activities.find(event => event.id === slotId);
    if (existing) return this.createdReply(existing, 'already_created');
    const slot = this.slots.get(slotId);
    if (!slot || slot.expiresAt < this.now() || slot.start <= this.now()) throw new CalendarError(410, 'expired', 'That suggestion expired. Find a fresh slot.');
    const duration = activity.durationMinutes ?? 8;
    if (!Number.isInteger(duration) || duration < 1 || duration > 8) throw new CalendarError(400, 'invalid_duration', 'Choose a supported activity.');
    const end = slot.start + duration * MINUTE;
    if (!this.isFree(slot.start, end)) throw new CalendarError(409, 'conflict', 'That time is busy now. Find another slot.');
    const event = { id: slot.id, title: activity.title ? `Momo: ${activity.title}` : 'Momo: 8-minute walk', label: slot.label, start: slot.start, end, ...(activity.suggestionId ? { suggestionId: activity.suggestionId, activityId: activity.activityId, durationMinutes: duration, stepTarget: activity.stepTarget, tracking: activity.tracking } : {}) };
    const next = [...this.activities, event];
    await this.persist(next);
    this.activities = next;
    return this.createdReply(event, 'created');
  }

  createdReply(event, status) {
    return { ...this.status(), status, label: event.label, eventUrl: '', start: new Date(event.start).toISOString(), end: new Date(event.end).toISOString(), event };
  }
}
