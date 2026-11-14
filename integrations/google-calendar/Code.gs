/**
 * Momo's single-owner Google Calendar bridge.
 * Deploy as a web app: execute as Me, access Anyone. Keep the deployment URL
 * private and pair the watch with setupMomo()'s short-lived code.
 */
var MOMO_SCOPES_ = ['calendar.freebusy', 'calendar.events.owned'];
var MOMO_MINUTE_ = 60000;
var MOMO_DURATION_ = 8;
var MOMO_BUFFER_ = 2;
var MOMO_SLOT_TTL_ = 10 * MOMO_MINUTE_;
var MOMO_PAIR_TTL_ = 15 * MOMO_MINUTE_;

/** Run once in the editor, authorize Google, then read the execution log. */
function setupMomo() {
  return withLockMomo_(function () {
    var now = Date.now();
    // This verifies real access before displaying a pairing code.
    busyMomo_(now, now + 24 * 60 * MOMO_MINUTE_);
    var state = loadMomo_();
    var random = parseInt(Utilities.getUuid().replace(/-/g, '').slice(0, 8), 16);
    var code = ('000000' + (random % 1000000)).slice(-6);
    state.pairing = { hash: hashMomo_(code), expiresAt: now + MOMO_PAIR_TTL_, failures: 0 };
    saveMomo_(state);
    console.log('Momo pairing code: ' + code + ' (valid for 15 minutes)');
    return { pairingCode: code, expiresAt: new Date(state.pairing.expiresAt).toISOString() };
  });
}

/** Optional owner action: remove paired-watch access; keeps calendar events. */
function disconnectMomo() {
  return withLockMomo_(function () {
    var state = loadMomo_();
    state.tokenHash = null;
    state.pairing = null;
    state.slots = {};
    saveMomo_(state);
    return { disconnected: true };
  });
}

function doGet() {
  return jsonMomo_({ name: 'Momo Calendar', message: 'Run setupMomo in the Apps Script editor, then pair your watch.', mode: 'google' });
}

function doPost(event) {
  try {
    var text = event && event.postData && event.postData.contents;
    if (typeof text !== 'string' || text.length > 16384) failMomo_(400, 'invalid_request', 'Send a small JSON request.');
    var body;
    try { body = JSON.parse(text); } catch (error) { failMomo_(400, 'invalid_json', 'The request is not valid JSON.'); }
    if (!body || typeof body !== 'object' || Array.isArray(body)) failMomo_(400, 'invalid_json', 'Send a JSON object.');
    return jsonMomo_(dispatchMomo_(body));
  } catch (error) {
    return jsonMomo_({
      error: error.momoCode || 'calendar_error',
      message: error.momoCode ? error.message : 'Momo could not reach your calendar. Please retry.',
      httpStatus: error.momoStatus || 502
    });
  }
}

function dispatchMomo_(body) {
  if (body.action === 'pair') return pairMomo_(body.code);
  var state = loadMomo_();
  if (typeof body.token !== 'string' || body.token.length !== 64 || !state.tokenHash || hashMomo_(body.token) !== state.tokenHash) {
    failMomo_(401, 'pairing_required', 'Pair your watch using the code from setupMomo.');
  }
  if (body.action === 'status') return { configured: true, connected: true, mode: 'google', timeZone: Session.getScriptTimeZone() };
  if (body.action === 'availability') return availabilityMomo_();
  if (body.action === 'activities') return createActivityMomo_(body.slotId);
  failMomo_(400, 'unknown_action', 'That calendar action is not supported.');
}

function pairMomo_(code) {
  return withLockMomo_(function () {
    var state = loadMomo_();
    var pairing = state.pairing;
    if (!pairing || pairing.expiresAt <= Date.now()) failMomo_(410, 'pairing_expired', 'Run setupMomo for a fresh pairing code.');
    if (pairing.failures >= 6) failMomo_(429, 'pairing_rate_limited', 'Too many attempts. Run setupMomo for a fresh code.');
    if (typeof code !== 'string' || !/^\d{6}$/.test(code) || hashMomo_(code) !== pairing.hash) {
      pairing.failures += 1;
      saveMomo_(state);
      failMomo_(400, 'invalid_pairing_code', 'That pairing code does not match.');
    }
    var token = Utilities.getUuid().replace(/-/g, '') + Utilities.getUuid().replace(/-/g, '');
    state.tokenHash = hashMomo_(token);
    state.pairing = null;
    saveMomo_(state);
    return { token: token, mode: 'google' };
  });
}

function availabilityMomo_() {
  return withLockMomo_(function () {
    var now = Date.now();
    var timeZone = Session.getScriptTimeZone();
    var busy = busyMomo_(now - MOMO_BUFFER_ * MOMO_MINUTE_, now + 24 * 60 * MOMO_MINUTE_ + MOMO_BUFFER_ * MOMO_MINUTE_);
    var proposed = findSlotsMomo_(now, timeZone, busy);
    var state = loadMomo_();
    var existing = Object.keys(state.slots).map(function (key) { return state.slots[key]; });
    // Bound the single Script Properties value to comfortably below its 9KB limit.
    existing = existing.filter(function (slot) { return slot.expiresAt > now; }).slice(-6);
    state.slots = {};
    existing.forEach(function (slot) { state.slots[slot.id] = slot; });
    var slots = proposed.map(function (slot) {
      var id = Utilities.getUuid().replace(/-/g, '');
      var record = {
        id: id, label: slot.label, start: slot.start, end: slot.end,
        durationMinutes: MOMO_DURATION_, eventId: 'momo' + hashMomo_(id).slice(0, 48),
        expiresAt: now + MOMO_SLOT_TTL_, status: 'proposed'
      };
      state.slots[id] = record;
      return { id: id, label: slot.label, start: slot.start, end: slot.end, durationMinutes: MOMO_DURATION_ };
    });
    saveMomo_(state);
    var busyNow = normalizeBusyMomo_(busy).some(function (range) { return range.start <= now && range.end > now; });
    return {
      connected: true, mode: 'google', checkedAt: new Date(now).toISOString(), busyNow: busyNow,
      slots: slots,
      message: slots.length ? 'I found room for a little walk.' : 'No free daytime slot in the next 24 hours.'
    };
  });
}

function createActivityMomo_(slotId) {
  return withLockMomo_(function () {
    if (typeof slotId !== 'string' || slotId.length > 80) failMomo_(400, 'invalid_slot', 'Choose a proposed activity time.');
    var state = loadMomo_();
    var slot = state.slots[slotId];
    if (!slot || !Object.prototype.hasOwnProperty.call(state.slots, slotId)) failMomo_(404, 'slot_not_found', 'Find a fresh activity time.');
    if (slot.status === 'created') return activityResultMomo_(slot, 'already_created');
    var now = Date.now();
    if (slot.expiresAt <= now || Date.parse(slot.start) <= now) failMomo_(410, 'slot_expired', 'That suggestion expired. Find a fresh time.');

    // A deterministic Google event ID makes timeout retries safe. Recover an
    // uncertain prior write before its own busy time is checked as a conflict.
    if (slot.pending) {
      var existing = googleMomo_('get', '/calendars/primary/events/' + slot.eventId, null, [404]);
      if (existing.status === 200 && existing.body.status !== 'cancelled') {
        slot.status = 'created';
        slot.eventUrl = existing.body.htmlLink || null;
        saveMomo_(state);
        return activityResultMomo_(slot, 'already_created');
      }
    }

    var start = Date.parse(slot.start);
    var end = Date.parse(slot.end);
    var busy = normalizeBusyMomo_(busyMomo_(start - MOMO_BUFFER_ * MOMO_MINUTE_, end + MOMO_BUFFER_ * MOMO_MINUTE_));
    var buffer = MOMO_BUFFER_ * MOMO_MINUTE_;
    if (busy.some(function (range) { return start < range.end + buffer && end > range.start - buffer; })) {
      failMomo_(409, 'slot_conflict', 'That time became busy. Find another opening.');
    }
    slot.pending = true;
    saveMomo_(state);
    var response = googleMomo_('post', '/calendars/primary/events?sendUpdates=none', {
      id: slot.eventId,
      summary: 'Momo: 8-minute walk',
      description: 'A little movement, with Momo. Scheduled after your confirmation.',
      start: { dateTime: slot.start, timeZone: Session.getScriptTimeZone() },
      end: { dateTime: slot.end, timeZone: Session.getScriptTimeZone() },
      transparency: 'opaque', reminders: { useDefault: true },
      extendedProperties: { private: { momoSlot: slot.id } }
    }, [409]);
    if (response.status === 409) response = googleMomo_('get', '/calendars/primary/events/' + slot.eventId);
    if (!response.body.id || response.body.status === 'cancelled') failMomo_(502, 'event_unconfirmed', 'The activity could not be confirmed. Retry the same time.');
    slot.status = 'created';
    slot.eventUrl = response.body.htmlLink || null;
    saveMomo_(state);
    return activityResultMomo_(slot, 'created');
  });
}

function activityResultMomo_(slot, status) {
  return { status: status, label: slot.label, eventUrl: slot.eventUrl || null, mode: 'google' };
}

function busyMomo_(start, end) {
  var result = googleMomo_('post', '/freeBusy', {
    timeMin: new Date(start).toISOString(), timeMax: new Date(end).toISOString(),
    timeZone: Session.getScriptTimeZone(), items: [{ id: 'primary' }]
  });
  var calendar = result.body.calendars && result.body.calendars.primary;
  if (!calendar || (calendar.errors && calendar.errors.length) || !Array.isArray(calendar.busy)) {
    failMomo_(502, 'calendar_unavailable', 'Your primary calendar availability could not be checked.');
  }
  normalizeBusyMomo_(calendar.busy); // Fail closed on malformed periods as well.
  return calendar.busy;
}

function googleMomo_(method, path, body, allowedStatuses) {
  var response;
  try {
    var options = {
      method: method, muteHttpExceptions: true,
      headers: { Authorization: 'Bearer ' + ScriptApp.getOAuthToken() }
    };
    if (body) { options.contentType = 'application/json'; options.payload = JSON.stringify(body); }
    response = UrlFetchApp.fetch('https://www.googleapis.com/calendar/v3' + path, options);
  } catch (error) {
    failMomo_(502, 'google_unavailable', 'Google Calendar could not be reached. Please retry.');
  }
  var status = response.getResponseCode();
  var data;
  try { data = JSON.parse(response.getContentText()); } catch (error) { data = {}; }
  if (status >= 200 && status < 300) return { status: status, body: data };
  if (allowedStatuses && allowedStatuses.indexOf(status) >= 0) return { status: status, body: data };
  if (status === 401 || status === 403) failMomo_(403, 'google_permission_required', 'Calendar access was denied. Run setupMomo and check the Calendar API service.');
  failMomo_(502, 'google_calendar_error', 'Google Calendar could not complete the request. Please retry.');
}

function normalizeBusyMomo_(busy) {
  if (!Array.isArray(busy)) failMomo_(502, 'calendar_unavailable', 'Calendar availability could not be checked.');
  var ranges = busy.map(function (range) {
    var start = Date.parse(range.start), end = Date.parse(range.end);
    if (!isFinite(start) || !isFinite(end) || end <= start) failMomo_(502, 'calendar_unavailable', 'Calendar returned an invalid busy period.');
    return { start: start, end: end };
  }).sort(function (a, b) { return a.start - b.start; });
  var merged = [];
  ranges.forEach(function (range) {
    var previous = merged[merged.length - 1];
    if (previous && range.start <= previous.end) previous.end = Math.max(previous.end, range.end);
    else merged.push(range);
  });
  return merged;
}

function findSlotsMomo_(now, timeZone, busy) {
  var ranges = normalizeBusyMomo_(busy);
  var buffer = MOMO_BUFFER_ * MOMO_MINUTE_;
  var duration = MOMO_DURATION_ * MOMO_MINUTE_;
  var cursor = Math.ceil((now + buffer) / (5 * MOMO_MINUTE_)) * 5 * MOMO_MINUTE_;
  var horizon = now + 24 * 60 * MOMO_MINUTE_;
  var slots = [];
  var today = Utilities.formatDate(new Date(now), timeZone, 'yyyy-MM-dd');
  while (cursor + duration <= horizon && slots.length < 3) {
    var start = new Date(cursor), end = new Date(cursor + duration);
    var startDay = Utilities.formatDate(start, timeZone, 'yyyy-MM-dd');
    var endDay = Utilities.formatDate(end, timeZone, 'yyyy-MM-dd');
    var startHour = Number(Utilities.formatDate(start, timeZone, 'HH'));
    var endHour = Number(Utilities.formatDate(end, timeZone, 'HH'));
    var endMinute = Number(Utilities.formatDate(end, timeZone, 'mm'));
    var daytime = startDay === endDay && startHour >= 8 && (endHour < 20 || (endHour === 20 && endMinute === 0));
    var blocked = ranges.some(function (range) { return cursor < range.end + buffer && cursor + duration > range.start - buffer; });
    if (daytime && !blocked) {
      slots.push({
        start: start.toISOString(), end: end.toISOString(), durationMinutes: MOMO_DURATION_,
        label: (startDay === today ? 'Today ' : 'Tomorrow ') + Utilities.formatDate(start, timeZone, 'h:mm a')
      });
      cursor = Math.ceil((cursor + duration + buffer) / (5 * MOMO_MINUTE_)) * 5 * MOMO_MINUTE_;
    } else cursor += 5 * MOMO_MINUTE_;
  }
  return slots;
}

function loadMomo_() {
  var value = PropertiesService.getScriptProperties().getProperty('momoState');
  if (!value) return { slots: {}, pairing: null, tokenHash: null };
  try {
    var state = JSON.parse(value);
    if (!state.slots || typeof state.slots !== 'object') throw new Error('Invalid state');
    return state;
  } catch (error) { failMomo_(500, 'setup_required', 'Run setupMomo in the Apps Script editor.'); }
}

function saveMomo_(state) {
  PropertiesService.getScriptProperties().setProperty('momoState', JSON.stringify(state));
}

function withLockMomo_(callback) {
  var lock = LockService.getScriptLock();
  if (!lock.tryLock(10000)) failMomo_(503, 'calendar_busy', 'Momo is finishing another action. Please retry.');
  try { return callback(); } finally { lock.releaseLock(); }
}

function hashMomo_(value) {
  return Utilities.computeDigest(Utilities.DigestAlgorithm.SHA_256, value, Utilities.Charset.UTF_8)
    .map(function (byte) { return ('0' + ((byte + 256) % 256).toString(16)).slice(-2); }).join('');
}

function failMomo_(status, code, message) {
  var error = new Error(message);
  error.momoStatus = status;
  error.momoCode = code;
  throw error;
}

function jsonMomo_(body) {
  return ContentService.createTextOutput(JSON.stringify(body)).setMimeType(ContentService.MimeType.JSON);
}
