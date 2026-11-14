import { randomUUID } from 'node:crypto';
import { CalendarError } from './demo-calendar.mjs';

const MINUTE = 60_000;
export const ACTIVITY_CATALOG = Object.freeze([
  { activityId: 'walk', title: '8-minute walk', durationMinutes: 8, stepTarget: 160, tracking: 'steps' },
  { activityId: 'stretch', title: '3-minute gentle stretch', durationMinutes: 3, stepTarget: 0, tracking: 'timer' },
  { activityId: 'breathe', title: '2-minute breathing break', durationMinutes: 2, stepTarget: 0, tracking: 'timer' },
  { activityId: 'rest', title: '2-minute quiet rest', durationMinutes: 2, stepTarget: 0, tracking: 'timer' }
]);
export const DEFAULT_PROFILE = Object.freeze({ nickname: '', additionalContext: '', timeZone: 'America/Edmonton', goals: ['move', 'outside', 'breaks'], preferredActivities: ['walk', 'stretch', 'breathe', 'rest'], maxBreakMinutes: 8, reminderStart: '08:00', reminderEnd: '20:00', humor: 'playful', seatedOnly: false });
const text = (value, max) => typeof value === 'string' ? value.normalize('NFKC').replace(/[^\x20-\x7e]/g, ' ').replace(/\s+/g, ' ').trim().slice(0, max) : '';
const invalid = message => { throw new CalendarError(400, 'invalid_profile', message); };

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
  if (!ACTIVITY_CATALOG.some(activity => profile.preferredActivities.includes(activity.activityId) && activity.durationMinutes <= profile.maxBreakMinutes && (!profile.seatedOnly || activity.activityId !== 'walk'))) invalid('These preferences exclude every activity. Choose a shorter activity or increase break length.');
  return profile;
}

const integerIn = (value, min, max) => Number.isInteger(value) && value >= min && value <= max ? value : null;
const numberIn = (value, min, max) => Number.isFinite(value) && value >= min && value <= max ? Math.round(value * 10) / 10 : null;

export function normalizeReading(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) return null;
  return {
    source: ['watch', 'simulated', 'unavailable'].includes(input.source) ? input.source : 'unavailable',
    steps: integerIn(input.steps, 0, 200_000),
    stepGoal: integerIn(input.stepGoal, 1, 200_000),
    calories: integerIn(input.calories, 0, 20_000),
    distanceMeters: numberIn(input.distanceMeters, 0, 200_000),
    floorsClimbed: integerIn(input.floorsClimbed, 0, 10_000),
    floorsDescended: integerIn(input.floorsDescended, 0, 10_000),
    activeMinutes: integerIn(input.activeMinutes, 0, 1_440),
    moderateMinutes: integerIn(input.moderateMinutes, 0, 1_440),
    vigorousMinutes: integerIn(input.vigorousMinutes, 0, 1_440),
    heartRate: integerIn(input.heartRate, 30, 220),
    restingHeartRate: integerIn(input.restingHeartRate, 30, 120),
    bodyBattery: integerIn(input.bodyBattery, 0, 100),
    stress: integerIn(input.stress, 0, 100),
    spo2: integerIn(input.spo2, 50, 100),
    respiration: integerIn(input.respiration, 4, 60),
    elevationMeters: numberIn(input.elevationMeters, -500, 9_000),
    pressureHpa: numberIn(input.pressureHpa, 300, 1_100),
    temperatureC: numberIn(input.temperatureC, -40, 60),
    timeToRecoveryHours: integerIn(input.timeToRecoveryHours, 0, 240),
    moveBarLevel: integerIn(input.moveBarLevel, 0, 5)
  };
}

export function deriveMood(reading, timeZone = 'UTC', now = Date.now()) {
  const votes = [];
  if (reading?.bodyBattery != null) votes.push({ id: 'bodyBattery', label: 'Body battery', value: reading.bodyBattery, vote: reading.bodyBattery < 30 ? -1 : reading.bodyBattery > 60 ? 1 : 0 });
  if (reading?.stress != null) votes.push({ id: 'stress', label: 'Stress', value: reading.stress, vote: reading.stress >= 75 ? -1 : reading.stress < 25 ? 1 : 0 });
  if (reading?.steps != null && reading.stepGoal) {
    const progress = reading.steps / reading.stepGoal;
    let hour = 12;
    try { hour = Number(new Intl.DateTimeFormat('en', { timeZone, hour: '2-digit', hourCycle: 'h23' }).format(new Date(now))); } catch { hour = 12; }
    if (progress >= 0.75) votes.push({ id: 'steps', label: 'Step progress', value: Math.round(progress * 100), vote: 1 });
    else if (hour >= 14 && progress < 0.25) votes.push({ id: 'steps', label: 'Step progress', value: Math.round(progress * 100), vote: -1 });
  }
  const sum = votes.reduce((total, item) => total + item.vote, 0);
  const face = !votes.length || sum === 0 ? 'average' : sum < 0 ? 'sad' : 'happy';
  const phase = face === 'sad' ? 0 : face === 'happy' ? 2 : 1;
  const summary = !votes.length ? 'Not enough of a reading yet. Middle face for now.' : face === 'sad' ? 'A slower check-in. The sleepy face fits.' : face === 'happy' ? 'A brighter check-in. The happy face fits.' : 'A mixed check-in. The middle face fits.';
  return { face, phase, title: ['SLOW DAY', "JUST CHILLIN'", 'MAIN CHARACTER'][phase], summary, votes };
}

export function normalizeContext(input = {}) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) input = {};
  const reading = normalizeReading(input.reading);
  const context = {
    steps: Number.isInteger(input.steps) && input.steps >= 0 && input.steps <= 200_000 ? input.steps : reading?.steps ?? null,
    movement: ['low', 'some', 'active', 'unknown'].includes(input.movement) ? input.movement : 'unknown',
    energy: ['low', 'okay', 'high', 'unknown'].includes(input.energy) ? input.energy : 'unknown',
    source: ['simulated', 'watch', 'user'].includes(input.source) ? input.source : 'user'
  };
  if (reading) {
    if (context.movement === 'unknown' && reading.moveBarLevel != null) context.movement = reading.moveBarLevel >= 3 ? 'low' : reading.moveBarLevel === 0 ? 'active' : 'some';
    if (context.energy === 'unknown' && reading.bodyBattery != null) context.energy = reading.bodyBattery < 30 ? 'low' : reading.bodyBattery <= 60 ? 'okay' : 'high';
    context.reading = reading;
  }
  return context;
}

function fallback(candidates, context) {
  const choice = candidates[0];
  return { slotId: choice.slotId, activityId: choice.activityId, aiSource: 'fallback', quip: choice.activityId === 'rest' ? 'Tiny pause. Even monkeys have a power-saving mode.' : choice.activityId === 'walk' ? 'Your chair can handle a brief separation.' : 'A tiny reset. No heroic montage required.', reason: context.movement === 'active' ? 'You reported recent movement, so a quieter break may fit.' : 'This activity fits your preferences and a free calendar slot.' };
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

  status() {
    return { ...this.calendar.status(), profileConfigured: this.profileConfigured, profileRevision: this.profileRevision, userId: this.userId || null, aiConfigured: !!this.suggestionProvider?.isConfigured?.(), aiSource: this.lastAiSource, checkIn: this.checkIn(), snoozedUntil: this.calendar.wellnessState.snoozedUntil || null, mood: this.calendar.wellnessState.lastMood || null };
  }

  rememberReading(reading, context) {
    const mood = deriveMood(reading, this.profile.timeZone, this.calendar.now());
    const stored = { ...reading, at: new Date(this.calendar.now()).toISOString() };
    return this.calendar.updateWellness(state => { state.lastReading = stored; state.lastMood = mood; if (context) state.lastContext = context; }).then(() => ({ mood, reading: stored }));
  }

  sensors({ reading } = {}) {
    return this.operation(async () => {
      const context = normalizeContext({ ...(reading && typeof reading === 'object' ? { source: reading.source } : {}), reading });
      if (!context.reading) throw new CalendarError(400, 'invalid_reading', 'Provide a sensor reading.');
      this.lastContext = context;
      return { ...this.status(), ...(await this.rememberReading(context.reading, context)) };
    });
  }

  dashboard() {
    return { ...this.status(), profile: this.getProfile().profile, sessions: Object.values(this.calendar.wellnessState.sessions || {}).sort((a, b) => Date.parse(b.createdAt) - Date.parse(a.createdAt)), decisions: (this.calendar.wellnessState.decisions || []).slice(-30) };
  }

  candidates(availability, context, excluded) {
    let catalog = ACTIVITY_CATALOG.filter(activity => this.profile.preferredActivities.includes(activity.activityId) && activity.durationMinutes <= this.profile.maxBreakMinutes && (!this.profile.seatedOnly || activity.activityId !== 'walk'));
    if (excluded && catalog.some(activity => activity.activityId !== excluded)) catalog = catalog.filter(activity => activity.activityId !== excluded);
    const history = this.history();
    const score = activity => {
      const helpful = history.helpfulByActivity[activity.activityId] || {};
      let value = (helpful.yes || 0) * 3 + (helpful.somewhat || 0) - (helpful.no || 0) * 3 + (history.completedByActivity[activity.activityId] || 0) - (history.snoozedByActivity[activity.activityId] || 0);
      if (context.movement === 'active' || context.energy === 'low') value += ['rest', 'breathe'].includes(activity.activityId) ? 5 : -3;
      if (this.profile.goals.includes('outside') && activity.activityId === 'walk') value += 2;
      return value;
    };
    catalog.sort((a, b) => score(b) - score(a));
    return availability.slots.flatMap(slot => catalog.map(activity => ({ ...activity, slotId: slot.id, label: slot.label, start: slot.start, end: new Date(Date.parse(slot.start) + activity.durationMinutes * MINUTE).toISOString() })));
  }

  suggestions(options = {}) {
    if (options.context?.reading && !options._readingSaved) {
      const context = normalizeContext(options.context);
      this.lastContext = context;
      return this.rememberReading(context.reading, context).then(() => this.suggestions({ ...options, context, _readingSaved: true }));
    }
    const now = this.calendar.now();
    const pending = this.checkIn();
    if (pending) return Promise.resolve({ ...this.status(), status: 'check_in', suggestion: null, checkIn: structuredClone(pending), message: pending.status === 'completed' ? 'Did your last break help?' : 'Your little escape is ready to resume.' });
    const context = normalizeContext(options.context === undefined ? this.lastContext || {} : options.context);
    this.lastContext = context;
    // Avoid charging for insignificant changes in the daily step counter while
    // still responding immediately to movement/energy/provenance changes.
    const fingerprint = JSON.stringify({ movement: context.movement, energy: context.energy, source: context.source });
    this.latestContextFingerprint = fingerprint;
    const snoozedUntil = this.calendar.wellnessState.snoozedUntil;
    if (snoozedUntil && Date.parse(snoozedUntil) > now) return Promise.resolve({ ...this.status(), suggestion: null, status: 'snoozed', message: 'Momo is giving you some room. Check back after your snooze.' });
    if (!options.excludeSuggestionId && this.cached && this.cached.until > now && this.cached.fingerprint === fingerprint) return Promise.resolve({ ...structuredClone(this.cached.response), mood: this.calendar.wellnessState.lastMood || null });
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
    const suggestion = { ...chosen, id: randomUUID(), profileRevision: revision, quip: text(generated.quip, 96), reason: text(generated.reason, 140), expiresAt: this.calendar.now() + 10 * MINUTE, aiSource: generated.aiSource === 'grok' ? 'grok' : 'fallback' };
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
          activity = state.sessions[event.id] ||= { id: event.id, activityId: suggestion.activityId, title: suggestion.title, durationMinutes: suggestion.durationMinutes, label: event.label, start: new Date(event.start).toISOString(), end: new Date(event.end).toISOString(), stepTarget: suggestion.stepTarget, tracking: suggestion.tracking, status: 'booked', createdAt: new Date(this.calendar.now()).toISOString(), feedback: null };
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

  complete({ activityId, source, steps = 0, elapsedSeconds = 0 } = {}) {
    return this.operation(async () => {
      if (!['simulated_steps', 'simulated_timer', 'steps', 'timer', 'self_report'].includes(source) || !Number.isFinite(steps) || steps < 0 || steps > 200_000 || !Number.isFinite(elapsedSeconds) || elapsedSeconds < 0 || elapsedSeconds > 86_400) throw new CalendarError(400, 'invalid_progress', 'Provide valid activity progress.');
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
        activity.completion = { source, steps: Math.round(steps), elapsedSeconds: Math.round(elapsedSeconds) };
      });
      this.invalidate();
      return { ...this.status(), status: 'completed', activity: structuredClone(activity), celebration: source === 'self_report' ? 'A little time for you. Nicely done.' : 'Chair escape complete. Tiny victory dance!' };
    });
  }

  feedback({ activityId, helpful } = {}) {
    return this.operation(async () => {
      if (!['yes', 'somewhat', 'no'].includes(helpful)) throw new CalendarError(400, 'invalid_feedback', 'Choose yes, somewhat, or no.');
      await this.calendar.updateWellness(state => {
        state.recommendationCache = null;
        const activity = state.sessions?.[activityId];
        if (!activity || activity.status !== 'completed') throw new CalendarError(409, 'not_completed', 'Finish the activity before rating it.');
        activity.feedback = { helpful, at: new Date(this.calendar.now()).toISOString() };
      });
      this.invalidate();
      return { ...this.status(), status: 'recorded', message: helpful === 'no' ? 'Noted. We can try a different kind of break next time.' : 'Noted. More of what works for you.' };
    });
  }
}
