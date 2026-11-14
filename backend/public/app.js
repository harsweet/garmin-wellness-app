(() => {
  'use strict';

  const form = document.querySelector('#profile-form');
  const saveButton = document.querySelector('#save-profile');
  const saveLabel = document.querySelector('#save-label');
  const saveStatus = document.querySelector('#save-status');
  const connectionBanner = document.querySelector('#connection-banner');
  const connectionMessage = document.querySelector('#connection-message');
  const profileBadge = document.querySelector('#profile-badge');
  const accessNotice = document.querySelector('#access-notice');
  const accessTitle = document.querySelector('#access-title');
  const accessMessage = document.querySelector('#access-message');
  const setupContent = document.querySelector('#setup-content');
  const dashboardContent = document.querySelector('#dashboard-content');
  const setupComplete = document.querySelector('#setup-complete');
  let profileLoaded = false;
  let accessReady = false;
  let initializing = false;
  let polling = false;
  let saving = false;
  let profileDirty = false;

  const defaultProfile = {
    nickname: '',
    timeZone: Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Edmonton',
    goals: ['move', 'outside', 'breaks'],
    preferredActivities: ['walk', 'stretch', 'breathe', 'rest'],
    maxBreakMinutes: 8,
    reminderStart: '08:00',
    reminderEnd: '20:00',
    humor: 'playful',
    seatedOnly: false
  };

  function setSaveStatus(message, kind = '') {
    saveStatus.textContent = message;
    saveStatus.className = `save-status${kind ? ` ${kind}` : ''}`;
  }

  function showConnectionError(message) {
    connectionMessage.textContent = message;
    connectionBanner.hidden = false;
  }

  function showAccessNotice(title, message) {
    accessReady = false;
    accessNotice.hidden = false;
    accessTitle.textContent = title;
    accessMessage.textContent = message;
    setupContent.hidden = true;
    dashboardContent.hidden = true;
    setupComplete.hidden = true;
    document.querySelector('#ai-label').textContent = 'Connect your watch';
  }

  function showExpiredAccess() {
    showAccessNotice('Open Momo for a fresh code.', 'This setup link may have expired or already been used. Open Momo on your watch and scan its new QR code.');
    connectionBanner.hidden = true;
  }

  function showAuthenticatedContent() {
    accessReady = true;
    accessNotice.hidden = true;
    setupContent.hidden = false;
    dashboardContent.hidden = false;
    connectionBanner.hidden = true;
  }

  function showSetupComplete(focus = false) {
    setupComplete.hidden = false;
    if (focus) {
      setupComplete.focus({ preventScroll: true });
      setupComplete.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'center' });
    }
  }

  function apiError(message, status) {
    const error = new Error(message);
    error.status = status;
    return error;
  }

  async function request(url, options = {}) {
    const response = await fetch(url, {
      credentials: 'same-origin',
      cache: 'no-store',
      signal: AbortSignal.timeout(10_000),
      ...options
    });
    let data;
    try { data = await response.json(); } catch {
      throw apiError('Momo’s service returned an incomplete reply. Please try again.', response.status);
    }
    if (!response.ok || data.error) {
      throw apiError(typeof data.message === 'string' ? data.message : 'Momo’s service is unavailable. Please try again.', data.httpStatus || response.status);
    }
    return data;
  }

  function applyProfile(profile, configured) {
    const values = { ...defaultProfile, ...profile };
    form.elements.nickname.value = values.nickname;
    form.elements.timeZone.value = values.timeZone;
    form.elements.maxBreakMinutes.value = String(values.maxBreakMinutes);
    form.elements.reminderStart.value = values.reminderStart;
    form.elements.reminderEnd.value = values.reminderEnd;
    form.elements.humor.value = values.humor;
    form.elements.seatedOnly.checked = values.seatedOnly === true;
    for (const checkbox of form.querySelectorAll('input[name="goals"]')) {
      checkbox.checked = Array.isArray(values.goals) && values.goals.includes(checkbox.value);
    }
    for (const checkbox of form.querySelectorAll('input[name="preferredActivities"]')) {
      checkbox.checked = Array.isArray(values.preferredActivities) && values.preferredActivities.includes(checkbox.value);
    }
    updateProfileBadge(configured);
  }

  function updateProfileBadge(configured) {
    profileBadge.textContent = configured ? 'Preferences saved' : 'Quick setup';
    profileBadge.classList.toggle('saved', Boolean(configured));
    saveLabel.textContent = configured ? 'Update my preferences' : 'Save my preferences';
  }

  function readProfile() {
    const data = new FormData(form);
    return {
      nickname: String(data.get('nickname') || '').trim(),
      timeZone: String(data.get('timeZone') || '').trim(),
      goals: data.getAll('goals'),
      preferredActivities: data.getAll('preferredActivities'),
      maxBreakMinutes: Number(data.get('maxBreakMinutes')),
      reminderStart: String(data.get('reminderStart') || ''),
      reminderEnd: String(data.get('reminderEnd') || ''),
      humor: String(data.get('humor') || 'playful'),
      seatedOnly: data.get('seatedOnly') === 'on'
    };
  }

  function validateProfile(profile) {
    if (profile.goals.length === 0) {
      form.querySelector('input[name="goals"]').focus();
      return 'Choose at least one thing you’d like more of.';
    }
    if (profile.preferredActivities.length === 0) {
      form.querySelector('input[name="preferredActivities"]').focus();
      return 'Choose at least one kind of break you’re up for.';
    }
    const durations = { walk: 8, stretch: 3, breathe: 2, rest: 2 };
    if (!profile.preferredActivities.some(activity => durations[activity] <= profile.maxBreakMinutes && (!profile.seatedOnly || activity !== 'walk'))) {
      form.elements.maxBreakMinutes.focus();
      return 'Choose a break that fits your time and seating preferences, or allow a little more time.';
    }
    try { new Intl.DateTimeFormat(undefined, { timeZone: profile.timeZone }); } catch {
      form.elements.timeZone.focus();
      return 'Choose a valid time zone, such as America/Edmonton.';
    }
    if (profile.reminderEnd <= profile.reminderStart) {
      form.elements.reminderEnd.focus();
      return 'Choose an end time after your start time.';
    }
    return '';
  }

  function dateValue(value) {
    if (value == null || value === '') return null;
    const date = new Date(value);
    return Number.isFinite(date.getTime()) ? date : null;
  }

  function formatDate(value, timeZone, options) {
    const date = dateValue(value);
    if (!date) return '';
    try { return new Intl.DateTimeFormat(undefined, { timeZone, ...options }).format(date); } catch {
      return new Intl.DateTimeFormat(undefined, options).format(date);
    }
  }

  function emptyList(list, message) {
    const item = document.createElement('li');
    item.className = 'empty-state';
    item.textContent = message;
    list.replaceChildren(item);
  }

  function renderEvents(events, timeZone) {
    const list = document.querySelector('#events');
    const valid = Array.isArray(events) ? events.filter(event => dateValue(event.start) && dateValue(event.end)) : [];
    if (valid.length === 0) {
      emptyList(list, 'Nothing booked here yet. Momo will keep an eye out for a little room.');
      return;
    }
    const rows = valid.slice().sort((a, b) => new Date(a.start) - new Date(b.start)).map(event => {
      const row = document.createElement('li');
      row.className = 'agenda-item';
      if (typeof event.title === 'string' && event.title.toLowerCase().startsWith('momo')) row.classList.add('momo-event');
      const details = document.createElement('div');
      details.className = 'agenda-details';
      const marker = document.createElement('span');
      marker.className = 'event-marker';
      marker.setAttribute('aria-hidden', 'true');
      const description = document.createElement('div');
      const title = document.createElement('span');
      title.className = 'event-title';
      title.textContent = event.title || 'Demo event';
      const date = document.createElement('span');
      date.className = 'event-date';
      date.textContent = formatDate(event.start, timeZone, { weekday: 'short', month: 'short', day: 'numeric' });
      description.append(title, date);
      details.append(marker, description);
      const time = document.createElement('span');
      time.className = 'event-time';
      time.textContent = `${formatDate(event.start, timeZone, { hour: 'numeric', minute: '2-digit' })} – ${formatDate(event.end, timeZone, { hour: 'numeric', minute: '2-digit' })}`;
      row.append(details, time);
      return row;
    });
    list.replaceChildren(...rows);
  }

  function renderSessions(sessions, timeZone) {
    const list = document.querySelector('#sessions');
    const values = Array.isArray(sessions) ? sessions : [];
    const completed = values.filter(session => session.status === 'completed');
    document.querySelector('#completed-count').textContent = String(completed.length);
    if (values.length === 0) {
      emptyList(list, 'No breaks yet. Your first small win starts on the watch.');
      return;
    }
    const newest = values.slice().sort((a, b) => {
      const aDate = dateValue(a.completedAt || a.startedAt || a.start || a.createdAt);
      const bDate = dateValue(b.completedAt || b.startedAt || b.start || b.createdAt);
      return (bDate?.getTime() || 0) - (aDate?.getTime() || 0);
    }).slice(0, 6);
    const rows = newest.map(session => {
      const done = session.status === 'completed';
      const row = document.createElement('li');
      row.className = 'win-item';
      const icon = document.createElement('span');
      icon.className = `win-symbol${done ? '' : ' pending'}`;
      icon.textContent = done ? '✓' : '·';
      icon.setAttribute('aria-hidden', 'true');
      const details = document.createElement('div');
      details.className = 'win-details';
      const title = document.createElement('strong');
      title.textContent = session.title || 'A little break';
      const subtitle = document.createElement('small');
      const status = done ? 'Completed' : session.status === 'running' ? 'In progress' : 'Scheduled';
      const when = formatDate(session.completedAt || session.startedAt || session.start, timeZone, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
      subtitle.textContent = when ? `${status} · ${when}` : status;
      details.append(title, subtitle);
      const helpful = session.feedback?.helpful || session.helpful;
      const feedback = { yes: 'Helpful', somewhat: 'Somewhat helpful', no: 'Not helpful' }[helpful];
      if (feedback) {
        const tag = document.createElement('span');
        tag.className = 'feedback-tag';
        tag.textContent = feedback;
        details.append(tag);
      }
      row.append(icon, details);
      return row;
    });
    list.replaceChildren(...rows);
  }

  function renderAiStatus(wellness) {
    const label = document.querySelector('#ai-label');
    const dot = document.querySelector('#ai-badge .status-dot');
    const description = document.querySelector('#ai-description');
    const source = wellness.aiSource || '';
    const configured = wellness.aiConfigured === true;
    dot.classList.toggle('mint', source === 'grok');
    dot.classList.toggle('amber', source === 'fallback' || !configured);
    if (source === 'grok') {
      label.textContent = 'Suggestions: Grok';
      description.textContent = 'Grok made the latest suggestion using your preferences and the demo calendar. Momo still asks before adding a break.';
    } else if (configured && source !== 'fallback') {
      label.textContent = 'Grok configured';
      description.textContent = 'Grok is configured for your next watch suggestion. A scripted suggestion is available if it can’t respond.';
    } else if (configured) {
      label.textContent = 'Scripted fallback';
      description.textContent = 'Grok is configured, but the latest request used a scripted suggestion. Your preferences still guide the available activities.';
    } else {
      label.textContent = 'Scripted suggestions';
      description.replaceChildren();
      const first = document.createTextNode('For Grok suggestions, add ');
      const variable = document.createElement('code');
      variable.textContent = 'XAI_API_KEY';
      const last = document.createTextNode(' to .env and restart the service. Your key stays on the backend.');
      description.append(first, variable, last);
    }
  }

  function renderDashboard(data) {
    const wellness = data.wellness || data;
    const timeZone = wellness.profile?.timeZone || data.timeZone || defaultProfile.timeZone;
    document.querySelector('#calendar-zone').textContent = `Times in ${timeZone.replaceAll('_', ' ')}`;
    renderEvents(data.events, timeZone);
    renderSessions(wellness.sessions || data.sessions, timeZone);
    renderAiStatus(wellness);
    if (typeof wellness.profileConfigured === 'boolean') updateProfileBadge(wellness.profileConfigured);
  }

  async function refreshDashboard() {
    if (polling || !accessReady) return;
    polling = true;
    try {
      const data = await request('/api/demo');
      renderDashboard(data);
      connectionBanner.hidden = true;
    } catch (error) {
      if (error.status === 401 || error.status === 403) showExpiredAccess();
      else showConnectionError('Momo’s service is offline. Check that it’s running, then try again.');
    } finally {
      polling = false;
    }
  }

  async function loadProfile() {
    if (profileLoaded && accessReady) return true;
    try {
      const data = await request('/api/profile');
      const configured = data.configured === true;
      const profile = configured ? (data.profile || {}) : { ...(data.profile || {}), timeZone: defaultProfile.timeZone };
      if (!profileDirty) applyProfile(profile, configured);
      else updateProfileBadge(configured);
      profileLoaded = true;
      showAuthenticatedContent();
      if (configured && location.pathname === '/onboard') showSetupComplete();
      return true;
    } catch (error) {
      if (error.status === 401 || error.status === 403) {
        showAccessNotice('Scan Momo’s QR code to get started.', 'Open Momo on your watch for a fresh code, then scan it with your phone.');
        connectionBanner.hidden = true;
      } else {
        showAccessNotice('Momo is having trouble connecting.', 'Keep Momo open on your watch. Check that the service is running, then try again.');
        showConnectionError('Your preferences couldn’t be loaded.');
      }
      return false;
    }
  }

  async function initializeAccess() {
    if (initializing) return;
    initializing = true;
    try {
      const key = new URLSearchParams(location.hash.slice(1)).get('key');
      if (key) {
        showAccessNotice('Connecting your phone to Momo…', 'This will only take a moment.');
        try {
          await request('/api/onboarding/claim', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' },
            body: JSON.stringify({ key })
          });
          // The fragment is never included in page requests or referrers. Remove
          // it only once the one-time capability has become a browser session.
          history.replaceState(null, '', `${location.pathname}${location.search}`);
        } catch (error) {
          if ([400, 401, 403, 404, 410, 429].includes(error.status)) showExpiredAccess();
          else {
            showAccessNotice('Momo is having trouble connecting.', 'Keep your watch nearby and check that the service is running, then try again.');
            showConnectionError('The setup connection couldn’t be completed.');
          }
          return;
        }
      }
      if (await loadProfile()) await refreshDashboard();
    } finally {
      initializing = false;
    }
  }

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (saving || !accessReady) return;
    const profile = readProfile();
    const error = validateProfile(profile);
    if (error) { setSaveStatus(error, 'error'); return; }
    saving = true;
    saveButton.disabled = true;
    saveLabel.textContent = 'Saving your preferences…';
    setSaveStatus('Giving Momo the important details.');
    try {
      const data = await request('/api/profile', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' },
        body: JSON.stringify(profile)
      });
      applyProfile(data.profile || profile, data.configured !== false);
      profileLoaded = true;
      profileDirty = false;
      setSaveStatus('Saved. Your next suggestion will use these preferences.', 'success');
      showSetupComplete(true);
      await refreshDashboard();
    } catch (failure) {
      if (failure.status === 401 || failure.status === 403) {
        showExpiredAccess();
        return;
      }
      saveLabel.textContent = profileBadge.classList.contains('saved') ? 'Update my preferences' : 'Save my preferences';
      setSaveStatus(failure.message, 'error');
    } finally {
      saving = false;
      saveButton.disabled = false;
    }
  });

  document.querySelector('#retry-connection').addEventListener('click', async () => {
    if (accessReady) await refreshDashboard();
    else await initializeAccess();
  });
  form.addEventListener('input', () => {
    profileDirty = true;
    if (saveStatus.classList.contains('success')) setSaveStatus('You have a few new preferences to save.');
  });
  document.addEventListener('visibilitychange', () => {
    if (!document.hidden && accessReady) refreshDashboard();
  });

  try {
    const zones = Intl.supportedValuesOf('timeZone');
    const list = document.querySelector('#time-zones');
    list.replaceChildren(...zones.map(zone => {
      const option = document.createElement('option');
      option.value = zone;
      return option;
    }));
  } catch {}

  applyProfile(defaultProfile, false);
  initializeAccess();
  setInterval(() => { if (!document.hidden && accessReady) refreshDashboard(); }, 5000);
})();
