import { randomUUID } from 'node:crypto';
import { CalendarError } from './demo-calendar.mjs';

const MINUTE = 60_000;
export const ACTIVITY_CATALOG = Object.freeze([
  { activityId: 'walk', title: '8-minute walk', durationMinutes: 8, stepTarget: 160, tracking: 'steps' },
  { activityId: 'stretch', title: '3-minute gentle stretch', durationMinutes: 3, stepTarget: 0, tracking: 'timer' },
  { activityId: 'breathe', title: '2-minute breathing break', durationMinutes: 2, stepTarget: 0, tracking: 'timer' },
  { activityId: 'rest', title: '2-minute quiet rest', durationMinutes: 2, stepTarget: 0, tracking: 'timer' },
  { activityId: 'eyes', title: '2-minute eye reset', durationMinutes: 2, stepTarget: 0, tracking: 'timer' },
  { activityId: 'stairs', title: '4-minute stair climb', durationMinutes: 4, stepTarget: 80, tracking: 'steps' },
  { activityId: 'sunlight', title: '5-minute sunlight break', durationMinutes: 5, stepTarget: 60, tracking: 'steps' }
]);
const STANDING_ACTIVITIES = new Set(['walk', 'stairs', 'sunlight']);
const FALLBACK_COPY = Object.freeze({
  walk: {
    quip: 'Your chair can handle a brief separation.',
    coachLine: 'Swing your arms and look at something farther away than your screen.'
  },
  stretch: {
    quip: 'Time to unfold from your keyboard shape.',
    coachLine: 'Drop your shoulders, roll your neck, and reach up like a tall monkey.'
  },
  breathe: {
    quip: 'The calendar can hold its breath. You do not have to.',
    coachLine: 'Inhale 4, hold 4, exhale 4. Your inbox can wait.'
  },
  rest: {
    quip: 'Tiny pause. Even monkeys have a power-saving mode.',
    coachLine: 'Rest your hands, soften your jaw, and let your shoulders drop.'
  },
  eyes: {
    quip: 'Your eyeballs deserve a tiny vacation from pixels.',
    coachLine: 'Look 20 feet away for 20 seconds and blink slowly.'
  },
  stairs: {
    quip: 'Gravity is offering a free mini workout right nearby.',
    coachLine: 'Take the stairs at a steady pace and feel your legs wake up.'
  },
  sunlight: {
    quip: 'Step outside and photosynthesize for five minutes.',
    coachLine: 'Step into natural light, take three easy breaths, and look at the sky.'
  }
});
const ACTIVITY_PLURAL_LABELS = Object.freeze({
  walk: 'Walks',
  stretch: 'Stretches',
  breathe: 'Breathing breaks',
  rest: 'Quiet rests',
  eyes: 'Eye resets',
  stairs: 'Stair climbs',
  sunlight: 'Sunlight breaks'
});
export const DEFAULT_PROFILE = Object.freeze({ nickname: '', additionalContext: '', timeZone: 'America/Edmonton', goals: ['move', 'outside', 'breaks'], preferredActivities: ['walk', 'stretch', 'breathe', 'rest', 'eyes', 'stairs', 'sunlight'], maxBreakMinutes: 8, reminderStart: '08:00', reminderEnd: '20:00', humor: 'playful', seatedOnly: false });
const text = (value, max) => typeof value === 'string' ? value.normalize('NFKC').replace(/[^\x20-\x7e]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max) : '';
const invalid = message => { throw new CalendarError(400, 'invalid_profile', message); };
const boundedInt = (value, min, max) => Number.isInteger(value) && value >= min && value <= max ? value : null;
const boundedFloat = (value, min, max) => {
  if (typeof value !== 'number' || !Number.isFinite(value) || value < min || value > max) return null;
  const rounded = Math.round(value * 10) / 10;
  return Object.is(rounded, -0) ? 0 : rounded;
};

function sanitizeVitals(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  const out = {};
  if (Number.isInteger(input.startHr) && input.startHr >= 30 && input.startHr <= 240) out.startHr = input.startHr;
  if (Number.isInteger(input.endHr) && input.endHr >= 30 && input.endHr <= 240) out.endHr = input.endHr;
  if (Number.isInteger(input.startStress) && input.startStress >= 0 && input.startStress <= 100) out.startStress = input.startStress;
  if (Number.isInteger(input.endStress) && input.endStress >= 0 && input.endStress <= 100) out.endStress = input.endStress;
  const elevation = boundedFloat(input.elevationGain, 0, 5000);
  if (elevation !== null) out.elevationGain = elevation;
  return Object.keys(out).length ? out : null;
}

function localDayKey(ms, timeZone) {
  const parts = new Intl.DateTimeFormat('en-CA', { timeZone, year: 'numeric', month: '2-digit', day: '2-digit' }).formatToParts(new Date(ms));
  const map = Object.fromEntries(parts.map(part => [part.type, part.value]));
  return `${map.year}-${map.month}-${map.day}`;
}

function prevDayKey(dayKey) {
  const [year, month, day] = dayKey.split('-').map(Number);
  return new Date(Date.UTC(year, month - 1, day) - 86_400_000).toISOString().slice(0, 10);
}

export function validateProfile(input, defaults = DEFAULT_PROFILE) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) invalid('Provide a profile object.');
  const merged = { ...DEFAULT_PROFILE, ...defaults, ...input };
  if (typeof merged.nickname !== 'string' || merged.nickname.length > 32) invalid('Nickname must be 32 characters or fewer.');
  if (typeof merged.additionalContext !== 'string' || merged.additionalContext.length > 1000) invalid('Additional context must be text up to 1000 characters.');
  const additionalContext = merged.additionalContext.normalize('NFC').replace(/\r\n?/g, '\n').replace(/[\u0000-\u0008\u000B\u000C\u000E-\u001F\u007F-\u009F\u202A-\u202E\u2066-\u2069\uFEFF]/g, '').trim();
  if (additionalContext.length > 1000) invalid('Additional context must be text up to 1000 characters.');
  try { new Intl.DateTimeFormat('en', { timeZone: merged.timeZone }).format(); } catch { invalid('Choose a valid IANA time zone.'); }
  if (!Array.isArray(merged.goals) || !merged.goals.length || merged.goals.some(goal => !['move', 'outside', 'breaks'].includes(goal))) invalid('Choose at least one supported wellness goal.');
  if (!Array.isArray(merged.preferredActivities) || !merged.preferredActivities.length || merged.preferredActivities.some(activity => !ACTIVITY_CATALOG.some(item => item.activityId === activity))) invalid('Choose at least one supported activity.');
  if (!Number.isInteger(merged.maxBreakMinutes) || merged.maxBreakMinutes < 2 || merged.maxBreakMinutes > 30) invalid('Break length must be between 2 and 30 minutes.');
  if (![merged.reminderStart, merged.reminderEnd].every(value => typeof value === 'string' && /^(?:[01]\d|2[0-3]):[0-5]\d$/.test(value)) || merged.reminderStart === merged.reminderEnd) invalid('Choose different valid reminder start and end times.');
  if (merged.humor === 'spicy') merged.humor = 'cheeky';
  if (!['gentle', 'playful', 'cheeky'].includes(merged.humor)) invalid('Choose gentle, playful, or cheeky humor.');
  if (typeof merged.seatedOnly !== 'boolean') invalid('Seated-only preference must be true or false.');
  const profile = { nickname: text(merged.nickname, 32), additionalContext, timeZone: merged.timeZone, goals: [...new Set(merged.goals)], preferredActivities: [...new Set(merged.preferredActivities)], maxBreakMinutes: merged.maxBreakMinutes, reminderStart: merged.reminderStart, reminderEnd: merged.reminderEnd, humor: merged.humor, seatedOnly: merged.seatedOnly };
  if (!ACTIVITY_CATALOG.some(activity => profile.preferredActivities.includes(activity.activityId) && activity.durationMinutes <= profile.maxBreakMinutes && (!profile.seatedOnly || !STANDING_ACTIVITIES.has(activity.activityId)))) invalid('These preferences exclude every activity. Choose a shorter activity or increase break length.');
  return profile;
}

export function normalizeContext(input = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) input = {};
  return {
    steps: Number.isInteger(input.steps) && input.steps >= 0 && input.steps <= 200_000 ? input.steps : null,
    movement: ['low', 'some', 'active', 'unknown'].includes(input.movement) ? input.movement : 'unknown',
    energy: ['low', 'okay', 'high', 'unknown'].includes(input.energy) ? input.energy : 'unknown',
    source: ['simulated', 'watch', 'user'].includes(input.source) ? input.source : 'user',
    heartRate: boundedInt(input.heartRate, 30, 240),
    stress: boundedInt(input.stress, 0, 100),
    bodyBattery: boundedInt(input.bodyBattery, 0, 100),
    moveBarLevel: boundedInt(input.moveBarLevel, 0, 5),
    activeMinutes: boundedInt(input.activeMinutes, 0, 1440),
    elevationMeters: boundedFloat(input.elevationMeters, -500, 9000),
    temperatureC: boundedFloat(input.temperatureC, -40, 70),
    solarIntensity: boundedInt(input.solarIntensity, 0, 100),
    checkInMood: ['fried', 'okay', 'wired', 'unknown'].includes(input.checkInMood) ? input.checkInMood : 'unknown'
  };
}

function fallback(candidates, context) {
  const choice = candidates[0];
  const copy = FALLBACK_COPY[choice.activityId] || FALLBACK_COPY.rest;
  return {
    slotId: choice.slotId,
    activityId: choice.activityId,
    aiSource: 'fallback',
    quip: copy.quip,
    reason: context.movement === 'active' || context.checkInMood === 'fried' ? 'You reported recent effort or feeling fried, so a quieter break fits.' : 'This activity fits your preferences and a free calendar slot.',
    coachLine: copy.coachLine
  };
}

export class WellnessService {
  constructor(calendar, { suggestionProvider = null } = {}) {
    this.calendar = calendar;
    this.suggestionProvider = suggestionProvider;
    const stored = calendar.wellnessState;
    let saved = null;
    try { if (stored.profile) saved = validateProfile(stored.profile); } catch {}
    this.profile = saved || validateProfile({ timeZone: calendar.timeZone });
    this.profileConfigured = !!saved;
    this.calendar.setPreferences(this.profile);
    this.cached = null;
    this.inflight = null;
    this.version = 0;
    this.queue = Promise.resolve();
    this.lastAiSource = stored.lastAiSource === 'grok' ? 'grok' : 'fallback';
    this.profileRevision = stored.profileRevision || 0;
    this.lastContext = stored.lastContext ? normalizeContext(stored.lastContext) : null;
    this.latestContextFingerprint = '';
    this.lastProviderCallAt = Number.isFinite(stored.lastProviderCallAt) ? Math.min(stored.lastProviderCallAt, calendar.now()) : null;
    for (const suggestion of stored.suggestions || []) {
      if (suggestion.expiresAt > calendar.now()) calendar.slots.set(suggestion.slotId, { id: suggestion.slotId, label: suggestion.label, start: Date.parse(suggestion.start), end: Date.parse(suggestion.start) + 8 * MINUTE, expiresAt: suggestion.expiresAt });
    }
    const cached = stored.recommendationCache;
    if (cached && cached.profileRevision === this.profileRevision && Number.isFinite(cached.until) && cached.until > calendar.now() && typeof cached.fingerprint === 'string' && cached.response?.suggestion?.expiresAt > calendar.now()) {
      const suggestion = cached.response.suggestion;
      const persisted = (stored.suggestions || []).some(item => item.id === suggestion.id && item.profileRevision === this.profileRevision);
      if (persisted && calendar.isFree(Date.parse(suggestion.start), Date.parse(suggestion.end))) this.cached = structuredClone(cached);
    }
  }

  operation(callback) {
    const result = this.queue.then(callback);
    this.queue = result.catch(() => {});
    return result;
  }

  getProfile() { return { profile: structuredClone(this.profile), configured: this.profileConfigured, profileRevision: this.profileRevision, userId: this.userId || null }; }

  saveProfile(input) {
    return this.operation(async () => {
      const profile = validateProfile(input, this.profile);
      const revision = this.profileRevision + 1;
      await this.calendar.updateWellness(state => { state.profile = profile; state.profileRevision = revision; state.recommendationCache = null; });
      this.profile = profile;
      this.profileRevision = revision;
      this.profileConfigured = true;
      this.calendar.setPreferences(profile);
      this.invalidate();
      return this.getProfile();
    });
  }

  invalidate() { this.version += 1; this.cached = null; this.inflight = null; }

  history() {
    const state = this.calendar.wellnessState;
    const result = { acceptedByActivity: {}, completedByActivity: {}, helpfulByActivity: {}, acceptedByHour: {}, snoozedByActivity: {} };
    for (const decision of state.decisions || []) {
      const target = decision.decision === 'accept' ? result.acceptedByActivity : decision.decision === 'snooze' ? result.snoozedByActivity : null;
      if (target) target[decision.activityId] = (target[decision.activityId] || 0) + 1;
      if (decision.decision === 'accept' && decision.start) {
        const hour = new Intl.DateTimeFormat('en', { timeZone: this.profile.timeZone, hour: '2-digit', hourCycle: 'h23' }).format(new Date(decision.start));
        result.acceptedByHour[hour] = (result.acceptedByHour[hour] || 0) + 1;
      }
    }
    for (const session of Object.values(state.sessions || {})) {
      if (session.status === 'completed') result.completedByActivity[session.activityId] = (result.completedByActivity[session.activityId] || 0) + 1;
      if (session.feedback) {
        const counts = result.helpfulByActivity[session.activityId] ||= { yes: 0, somewhat: 0, no: 0 };
        counts[session.feedback.helpful] += 1;
      }
    }
    return result;
  }

  checkIn() {
    return Object.values(this.calendar.wellnessState.sessions || {}).filter(session => session.status !== 'completed' || !session.feedback).sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt))[0] || null;
  }

  insights() {
    const sessions = Object.values(this.calendar.wellnessState.sessions || {});
    let totalCompleted = 0;
    let totalHelpful = 0;
    const completedDays = new Set();
    const byId = new Map();

    const ensure = (activityId, fallbackTitle) => {
      if (!byId.has(activityId)) {
        const catalogItem = ACTIVITY_CATALOG.find(item => item.activityId === activityId);
        byId.set(activityId, {
          activityId,
          title: catalogItem?.title || fallbackTitle || activityId,
          completed: 0,
          helpful: 0,
          somewhat: 0,
          notHelpful: 0,
          helpRate: 0
        });
      }
      return byId.get(activityId);
    };

    for (const session of sessions) {
      const entry = ensure(session.activityId, session.title);
      if (session.status === 'completed') {
        totalCompleted += 1;
        entry.completed += 1;
        const ts = Date.parse(session.completedAt || session.createdAt);
        if (Number.isFinite(ts)) completedDays.add(localDayKey(ts, this.profile.timeZone));
      }
      if (session.feedback) {
        if (session.feedback.helpful === 'yes') {
          totalHelpful += 1;
          entry.helpful += 1;
        } else if (session.feedback.helpful === 'somewhat') {
          entry.somewhat += 1;
        } else if (session.feedback.helpful === 'no') {
          entry.notHelpful += 1;
        }
      }
    }

    const byActivity = [];
    for (const entry of byId.values()) {
      const rated = entry.helpful + entry.somewhat + entry.notHelpful;
      if (entry.completed === 0 && rated === 0) continue;
      entry.helpRate = rated > 0 ? Math.round(((entry.helpful + 0.5 * entry.somewhat) / rated) * 100) : 0;
      byActivity.push(entry);
    }
    byActivity.sort((a, b) => b.helpRate - a.helpRate || b.completed - a.completed);

    const top = byActivity[0] || null;
    const topActivity = top
      ? { activityId: top.activityId, title: top.title, completed: top.completed, helpful: top.helpful, helpRate: top.helpRate }
      : null;

    let streakDays = 0;
    if (completedDays.size > 0) {
      const today = localDayKey(this.calendar.now(), this.profile.timeZone);
      const yesterday = prevDayKey(today);
      let cursor = completedDays.has(today) ? today : completedDays.has(yesterday) ? yesterday : null;
      while (cursor && completedDays.has(cursor)) {
        streakDays += 1;
        cursor = prevDayKey(cursor);
      }
    }

    return { totalCompleted, totalHelpful, streakDays, topActivity, byActivity };
  }

  status() {
    return { ...this.calendar.status(), profileConfigured: this.profileConfigured, profileRevision: this.profileRevision, userId: this.userId || null, aiConfigured: !!this.suggestionProvider?.isConfigured?.(), aiSource: this.lastAiSource, checkIn: this.checkIn(), snoozedUntil: this.calendar.wellnessState.snoozedUntil || null, insights: this.insights() };
  }

  dashboard() {
    return { ...this.status(), profile: this.getProfile().profile, sessions: Object.values(this.calendar.wellnessState.sessions || {}).sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt)), decisions: (this.calendar.wellnessState.decisions || []).slice(-30) };
  }

  candidates(availability, context, excluded) {
    let catalog = ACTIVITY_CATALOG.filter(activity => this.profile.preferredActivities.includes(activity.activityId) && activity.durationMinutes <= this.profile.maxBreakMinutes && (!this.profile.seatedOnly || !STANDING_ACTIVITIES.has(activity.activityId)));
    if (excluded && catalog.some(activity => activity.activityId !== excluded)) catalog = catalog.filter(activity => activity.activityId !== excluded);
    const history = this.history();
    const score = activity => {
      const helpful = history.helpfulByActivity[activity.activityId] || {};
      let value = (helpful.yes || 0) * 3 + (helpful.somewhat || 0) - (helpful.no || 0) * 3 + (history.completedByActivity[activity.activityId] || 0) - (history.snoozedByActivity[activity.activityId] || 0);
      if (context.movement === 'active' || context.energy === 'low' || context.checkInMood === 'fried') {
        if (['rest', 'breathe'].includes(activity.activityId)) value += 5;
        else if (activity.activityId === 'eyes') value += 2;
        else if (STANDING_ACTIVITIES.has(activity.activityId)) value -= 3;
      }
      if (context.checkInMood === 'wired' && ['breathe', 'walk', 'stairs'].includes(activity.activityId)) value += 2;
      if (this.profile.goals.includes('outside') && activity.activityId === 'walk') value += 2;
      if (Number.isInteger(context.solarIntensity) && context.solarIntensity >= 20 && this.profile.goals.includes('outside') && activity.activityId === 'sunlight') value += 1;
      if (Number.isInteger(context.moveBarLevel) && context.moveBarLevel >= 3 && ['walk', 'stretch', 'stairs'].includes(activity.activityId)) value += 1;
      return value;
    };
    catalog.sort((a, b) => score(b) - score(a));
    return availability.slots.flatMap(slot => catalog.map(activity => ({ ...activity, slotId: slot.id, label: slot.label, start: slot.start, end: new Date(Date.parse(slot.start) + activity.durationMinutes * MINUTE).toISOString() })));
  }

  suggestions(options = {}) {
    const now = this.calendar.now();
    const pending = this.checkIn();
    if (pending) return Promise.resolve({ ...this.status(), status: 'check_in', suggestion: null, checkIn: structuredClone(pending), message: pending.status === 'completed' ? 'Did your last break help?' : 'Your little escape is ready to resume.' });
    const context = normalizeContext(options.context === undefined ? this.lastContext || {} : options.context);
    this.lastContext = context;
    // Avoid charging for insignificant changes in the daily step or vital counters
    // while still responding immediately to movement/energy/mood/provenance changes.
    const fingerprint = JSON.stringify({ movement: context.movement, energy: context.energy, source: context.source, checkInMood: context.checkInMood });
    this.latestContextFingerprint = fingerprint;
    const snoozedUntil = this.calendar.wellnessState.snoozedUntil;
    if (snoozedUntil && Date.parse(snoozedUntil) > now) return Promise.resolve({ ...this.status(), suggestion: null, status: 'snoozed', message: 'Momo is giving you some room. Check back after your snooze.' });
    if (!options.excludeSuggestionId && this.cached && this.cached.until > now && this.cached.fingerprint === fingerprint) return Promise.resolve(structuredClone(this.cached.response));
    if (this.inflight && !options.excludeSuggestionId && this.inflight.fingerprint === fingerprint) return this.inflight.promise;
    const request = this.generateSuggestion({ ...options, context, fingerprint });
    if (!options.excludeSuggestionId) {
      const inflight = { fingerprint, promise: request };
      this.inflight = inflight;
      request.finally(() => { if (this.inflight === inflight) this.inflight = null; }).catch(() => {});
    }
    return request;
  }

  async generateSuggestion({ context: input, excludeSuggestionId, fingerprint } = {}) {
    const version = this.version;
    const revision = this.profileRevision;
    const context = normalizeContext(input);
    const availability = this.calendar.availability();
    const prior = (this.calendar.wellnessState.suggestions || []).find(item => item.id === excludeSuggestionId);
    const candidates = this.candidates(availability, context, prior?.activityId);
    if (!candidates.length) return { ...this.status(), suggestion: null, status: 'empty', busyNow: availability.busyNow, message: 'No matching break fits right now.' };
    let generated;
    try {
      if (this.suggestionProvider && (this.lastProviderCallAt === null || this.calendar.now() - this.lastProviderCallAt >= 5000)) {
        this.lastProviderCallAt = this.calendar.now();
        generated = await this.suggestionProvider.suggest({ profile: this.getProfile().profile, context, candidates: structuredClone(candidates), history: this.history() });
      } else generated = fallback(candidates, context);
    } catch { generated = fallback(candidates, context); }
    let chosen = candidates.find(candidate => candidate.slotId === generated?.slotId && candidate.activityId === generated?.activityId);
    if (!chosen || !text(generated?.quip, 96) || !text(generated?.reason, 140)) {
      generated = fallback(candidates, context);
      chosen = candidates[0];
    }
    if (this.version !== version) throw new CalendarError(409, 'preferences_changed', 'Your preferences changed. Ask Momo again.');
    const defaultCoachLine = (FALLBACK_COPY[chosen.activityId] || FALLBACK_COPY.rest).coachLine;
    const coachLine = text(generated?.coachLine, 90) || defaultCoachLine;
    const suggestion = { ...chosen, id: randomUUID(), profileRevision: revision, quip: text(generated.quip, 96), reason: text(generated.reason, 140), coachLine, expiresAt: this.calendar.now() + 10 * MINUTE, aiSource: generated.aiSource === 'grok' ? 'grok' : 'fallback' };
    const response = { ...this.status(), busyNow: availability.busyNow, suggestion, aiSource: suggestion.aiSource };
    const cached = { until: this.calendar.now() + MINUTE, response, fingerprint, profileRevision: revision };
    await this.calendar.updateWellness(state => {
      if (this.version !== version || (state.profileRevision || 0) !== revision) throw new CalendarError(409, 'preferences_changed', 'Your preferences changed. Ask Momo again.');
      state.suggestions = [...(state.suggestions || []).filter(item => item.expiresAt > this.calendar.now()), suggestion].slice(-50);
      state.lastProviderCallAt = this.lastProviderCallAt;
      if (this.latestContextFingerprint === fingerprint) {
        state.recommendationCache = cached;
        state.lastContext = context;
        state.lastAiSource = suggestion.aiSource;
      }
    });
    if (this.version !== version || this.profileRevision !== revision) throw new CalendarError(409, 'preferences_changed', 'Your preferences changed. Ask Momo again.');
    if (this.latestContextFingerprint === fingerprint) {
      this.lastAiSource = suggestion.aiSource;
      this.cached = cached;
    }
    return structuredClone(response);
  }

  decide({ suggestionId, decision } = {}) {
    if (!['accept', 'snooze', 'alternative'].includes(decision) || typeof suggestionId !== 'string') throw new CalendarError(400, 'invalid_decision', 'Choose accept, snooze, or alternative.');
    return this.operation(async () => {
      const suggestion = (this.calendar.wellnessState.suggestions || []).find(item => item.id === suggestionId);
      if (!suggestion) throw new CalendarError(410, 'expired', 'Find a fresh suggestion.');
      if (decision === 'accept') {
        const existing = this.calendar.activities.find(event => event.suggestionId === suggestionId);
        if (!existing && (suggestion.profileRevision || 0) !== this.profileRevision) throw new CalendarError(409, 'preferences_changed', 'Your preferences changed. Find a fresh suggestion.');
        if (!existing && suggestion.expiresAt < this.calendar.now()) throw new CalendarError(410, 'expired', 'Find a fresh suggestion.');
        const reply = existing ? this.calendar.createdReply(existing, 'already_created') : await this.calendar.book(suggestion.slotId, { ...suggestion, suggestionId: suggestion.id });
        const event = reply.event;
        let activity;
        await this.calendar.updateWellness(state => {
          state.recommendationCache = null;
          state.sessions ||= {};
          const fallbackCoach = (FALLBACK_COPY[suggestion.activityId] || FALLBACK_COPY.rest).coachLine;
          activity = state.sessions[event.id] ||= { id: event.id, activityId: suggestion.activityId, title: suggestion.title, durationMinutes: suggestion.durationMinutes, label: event.label, start: new Date(event.start).toISOString(), end: new Date(event.end).toISOString(), stepTarget: suggestion.stepTarget, tracking: suggestion.tracking, coachLine: suggestion.coachLine || fallbackCoach, status: 'booked', createdAt: new Date(this.calendar.now()).toISOString(), feedback: null };
          state.decisions ||= [];
          if (!state.decisions.some(item => item.suggestionId === suggestionId && item.decision === 'accept')) state.decisions.push({ suggestionId, decision, activityId: suggestion.activityId, start: suggestion.start, at: new Date(this.calendar.now()).toISOString() });
          state.decisions = state.decisions.slice(-200);
        });
        this.invalidate();
        return { ...this.status(), status: reply.status, label: reply.label, eventUrl: '', activity: structuredClone(activity) };
      }
      await this.calendar.updateWellness(state => {
        state.recommendationCache = null;
        state.decisions = [...(state.decisions || []), { suggestionId, decision, activityId: suggestion.activityId, start: suggestion.start, at: new Date(this.calendar.now()).toISOString() }].slice(-200);
        if (decision === 'snooze') state.snoozedUntil = new Date(this.calendar.now() + 30 * MINUTE).toISOString();
      });
      this.invalidate();
      if (decision === 'snooze') return { ...this.status(), status: 'snoozed' };
      return this.suggestions({ excludeSuggestionId: suggestionId });
    });
  }

  start({ activityId } = {}) {
    return this.operation(async () => {
      let activity;
      await this.calendar.updateWellness(state => {
        state.recommendationCache = null;
        activity = state.sessions?.[activityId];
        if (!activity) throw new CalendarError(404, 'unknown_activity', 'Choose a booked activity.');
        if (activity.status === 'booked') { activity.status = 'running'; activity.startedAt = new Date(this.calendar.now()).toISOString(); }
      });
      return { ...this.status(), status: activity.status, activity: structuredClone(activity) };
    });
  }

  complete({ activityId, source, steps = 0, elapsedSeconds = 0, vitals = null } = {}) {
    return this.operation(async () => {
      if (!['simulated_steps', 'simulated_timer', 'steps', 'timer', 'self_report'].includes(source) || !Number.isFinite(steps) || steps < 0 || steps > 200_000 || !Number.isFinite(elapsedSeconds) || elapsedSeconds < 0 || elapsedSeconds > 86_400) throw new CalendarError(400, 'invalid_progress', 'Provide valid activity progress.');
      const sanitizedVitals = sanitizeVitals(vitals);
      let activity;
      await this.calendar.updateWellness(state => {
        state.recommendationCache = null;
        activity = state.sessions?.[activityId];
        if (!activity) throw new CalendarError(404, 'unknown_activity', 'Choose a booked activity.');
        if (activity.status === 'completed') return;
        if (activity.status !== 'running') throw new CalendarError(409, 'not_started', 'Start the activity first.');
        if (['steps', 'simulated_steps'].includes(source) && (activity.tracking !== 'steps' || steps < activity.stepTarget)) throw new CalendarError(400, 'insufficient_progress', 'Keep going, or report completion yourself.');
        if (['timer', 'simulated_timer'].includes(source) && elapsedSeconds < activity.durationMinutes * 60) throw new CalendarError(400, 'insufficient_progress', 'The activity timer is still running.');
        activity.status = 'completed';
        activity.completedAt = new Date(this.calendar.now()).toISOString();
        activity.completion = {
          source,
          steps: Math.round(steps),
          elapsedSeconds: Math.round(elapsedSeconds),
          ...(sanitizedVitals ? { vitals: sanitizedVitals } : {})
        };
      });
      this.invalidate();
      return { ...this.status(), status: 'completed', activity: structuredClone(activity), celebration: source === 'self_report' ? 'A little time for you. Nicely done.' : 'Chair escape complete. Tiny victory dance!' };
    });
  }

  feedback({ activityId, helpful } = {}) {
    return this.operation(async () => {
      if (!['yes', 'somewhat', 'no'].includes(helpful)) throw new CalendarError(400, 'invalid_feedback', 'Choose yes, somewhat, or no.');
      let sessionActivityId;
      await this.calendar.updateWellness(state => {
        state.recommendationCache = null;
        const activity = state.sessions?.[activityId];
        if (!activity || activity.status !== 'completed') throw new CalendarError(409, 'not_completed', 'Finish the activity before rating it.');
        activity.feedback = { helpful, at: new Date(this.calendar.now()).toISOString() };
        sessionActivityId = activity.activityId;
      });
      this.invalidate();
      const insights = this.insights();
      const stats = insights.byActivity.find(item => item.activityId === sessionActivityId);
      const label = ACTIVITY_PLURAL_LABELS[sessionActivityId] || 'Breaks';
      const rated = stats ? stats.helpful + stats.somewhat + stats.notHelpful : 0;
      let message;
      if (helpful === 'no') {
        message = 'Noted. We will try a different break next time.';
      } else if (helpful === 'yes' && stats) {
        message = `${label} helped ${stats.helpful} of ${rated} times. Case filed!`;
      } else if (stats && stats.helpful > 0) {
        message = `${label} helped ${stats.helpful} of ${rated} times (${stats.somewhat} partial).`;
      } else if (stats) {
        message = `${label} partly helped (${stats.somewhat} of ${rated}). Noted!`;
      } else {
        message = 'Noted. More of what works for you.';
      }
      return { ...this.status(), status: 'recorded', message: text(message, 110), insights };
    });
  }
}
