(() => {
  'use strict';

  const $ = selector => document.querySelector(selector);
  const form = $('#profile-form');
  const nicknameInput = $('#nickname');
  const seatedOnlyInput = $('#seated-only');
  const reminderStartInput = $('#reminder-start');
  const reminderEndInput = $('#reminder-end');
  const hoursSummary = $('#hours-summary');
  const breakHoursDetails = $('#break-hours');
  const activityHint = $('#activity-hint');
  const saveButton = $('#save-profile');
  const saveLabel = $('#save-label');
  const saveStatus = $('#save-status');
  const cancelEditButton = $('#cancel-edit');
  const context = $('#additional-context');
  const accessNotice = $('#access-notice');
  const setupContent = $('#setup-content');
  const setupComplete = $('#setup-complete');
  const pairedHeading = $('#paired-heading');
  const connectionBanner = $('#connection-banner');
  const codeForm = $('#setup-code-form');
  const codeInput = $('#setup-code');
  const codeButton = $('#connect-code');
  const codeStatus = $('#setup-code-status');
  const refreshReceiptsButton = $('#refresh-receipts');
  const receiptsStatus = $('#receipts-status');
  const receiptStats = $('#receipt-stats');
  const helpsBlock = $('#helps-block');
  const helpsList = $('#helps-list');
  const recentBlock = $('#recent-block');
  const receiptsList = $('#receipts-list');
  const localTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Edmonton';

  const ACTIVITY_META = {
    walk: { title: 'Walk', minutes: 8, standing: true },
    stretch: { title: 'Stretch', minutes: 3, standing: false },
    breathe: { title: 'Breathe', minutes: 2, standing: false },
    rest: { title: 'Quiet rest', minutes: 2, standing: false },
    eyes: { title: 'Eye reset', minutes: 2, standing: false },
    stairs: { title: 'Stairs', minutes: 4, standing: true },
    sunlight: { title: 'Sunlight', minutes: 5, standing: true }
  };
  const LENGTH_PILLS = [2, 5, 8, 15];
  const TIME_PATTERN = /^(?:[01]\d|2[0-3]):[0-5]\d$/;

  let accessReady = false;
  let initializing = false;
  let saving = false;
  let configured = false;
  let claimingCode = false;
  let loadingInsights = false;

  function el(tag, className = '', content = '') {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (content) node.textContent = content;
    return node;
  }

  function setSaveStatus(message, error = false) {
    saveStatus.textContent = message;
    saveStatus.className = `save-status${error ? ' error' : ''}`;
  }

  function showAccessNotice(title, message, allowCode = true) {
    accessReady = false;
    accessNotice.hidden = false;
    $('#access-title').textContent = title;
    $('#access-message').textContent = message;
    setupContent.hidden = true;
    setupComplete.hidden = true;
    codeForm.hidden = !allowCode;
  }

  function showExpiredAccess() {
    showAccessNotice('Let’s try a fresh code.', 'This link may have expired or already been used. Open Momo on your watch for a new QR code or four-digit code.');
    connectionBanner.hidden = true;
  }

  function showConnectionError(message) {
    $('#connection-message').textContent = message;
    connectionBanner.hidden = false;
  }

  function updateContextCount() {
    $('#context-count').textContent = `${context.value.length} / 1000`;
  }

  function selectedMaxBreakMinutes() {
    const checked = form.querySelector('input[name="maxBreakMinutes"]:checked');
    const parsed = checked ? Number(checked.value) : 8;
    return Number.isInteger(parsed) ? parsed : 8;
  }

  function selectedHumor() {
    const checked = form.querySelector('input[name="humor"]:checked');
    return checked ? checked.value : 'playful';
  }

  function updateHoursSummary() {
    const start = TIME_PATTERN.test(reminderStartInput.value) ? reminderStartInput.value : '08:00';
    const end = TIME_PATTERN.test(reminderEndInput.value) ? reminderEndInput.value : '20:00';
    hoursSummary.textContent = `${start} – ${end}`;
  }

  function syncActivityConstraints() {
    const maxMinutes = selectedMaxBreakMinutes();
    const seatedOnly = seatedOnlyInput.checked;
    const chips = [...form.querySelectorAll('.activity-chip')];
    let excludedCount = 0;
    let eligibleCheckedCount = 0;

    for (const chip of chips) {
      const checkbox = chip.querySelector('input[name="preferredActivities"]');
      const note = chip.querySelector('.chip-note');
      const id = chip.dataset.activity;
      const meta = ACTIVITY_META[id] || { minutes: Number(chip.dataset.minutes) || 2, standing: chip.dataset.standing === 'true' };
      const needsStanding = seatedOnly && meta.standing;
      const tooLong = meta.minutes > maxMinutes;
      const excluded = needsStanding || tooLong;

      checkbox.disabled = excluded;
      chip.classList.toggle('is-excluded', excluded);
      if (note) {
        note.textContent = needsStanding ? 'Standing' : tooLong ? `>${maxMinutes}m` : '';
      }
      if (excluded) excludedCount += 1;
      else if (checkbox.checked) eligibleCheckedCount += 1;
    }

    if (eligibleCheckedCount === 0) {
      activityHint.textContent = 'Pick at least one available break type above.';
      activityHint.className = 'field-hint error';
    } else if (excludedCount > 0) {
      activityHint.textContent = 'Dimmed break types are paused by your seated or break-length setting.';
      activityHint.className = 'field-hint';
    } else {
      activityHint.textContent = 'Momo picks from your checked break types.';
      activityHint.className = 'field-hint';
    }
  }

  function applyProfile(profile, isConfigured) {
    configured = isConfigured;
    const nickname = typeof profile.nickname === 'string' ? profile.nickname.trim() : '';
    nicknameInput.value = nickname;
    pairedHeading.textContent = nickname ? `You’re paired, ${nickname}.` : 'You’re paired.';

    for (const checkbox of form.querySelectorAll('input[name="goals"]')) {
      checkbox.checked = Array.isArray(profile.goals) && profile.goals.includes(checkbox.value);
    }

    const rawHumor = profile.humor === 'spicy' ? 'cheeky' : profile.humor;
    const humor = ['gentle', 'playful', 'cheeky'].includes(rawHumor) ? rawHumor : 'playful';
    for (const radio of form.querySelectorAll('input[name="humor"]')) {
      radio.checked = radio.value === humor;
    }

    const rawMax = Number.isInteger(profile.maxBreakMinutes) ? profile.maxBreakMinutes : 8;
    const matchedMax = LENGTH_PILLS.includes(rawMax)
      ? rawMax
      : LENGTH_PILLS.reduce((best, value) => Math.abs(value - rawMax) < Math.abs(best - rawMax) ? value : best, 8);
    for (const radio of form.querySelectorAll('input[name="maxBreakMinutes"]')) {
      radio.checked = Number(radio.value) === matchedMax;
    }

    seatedOnlyInput.checked = profile.seatedOnly === true;

    const preferred = Array.isArray(profile.preferredActivities) && profile.preferredActivities.length
      ? profile.preferredActivities
      : Object.keys(ACTIVITY_META);
    for (const checkbox of form.querySelectorAll('input[name="preferredActivities"]')) {
      checkbox.checked = preferred.includes(checkbox.value);
    }

    reminderStartInput.value = TIME_PATTERN.test(profile.reminderStart) ? profile.reminderStart : '08:00';
    reminderEndInput.value = TIME_PATTERN.test(profile.reminderEnd) ? profile.reminderEnd : '20:00';
    updateHoursSummary();
    syncActivityConstraints();

    context.value = typeof profile.additionalContext === 'string' ? profile.additionalContext : '';
    updateContextCount();
    cancelEditButton.hidden = !configured;
  }

  function formatDateTime(value) {
    const parsed = new Date(value);
    if (!Number.isFinite(parsed.getTime())) return '';
    return parsed.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' });
  }

  function formatDuration(session) {
    const elapsed = session.completion?.elapsedSeconds;
    if (Number.isFinite(elapsed) && elapsed > 0) {
      if (elapsed < 60) return `${Math.round(elapsed)}s`;
      return `${Math.round(elapsed / 60)}m`;
    }
    if (Number.isFinite(session.durationMinutes) && session.durationMinutes > 0) {
      return `${session.durationMinutes}m`;
    }
    return '';
  }

  function percentFromRate(rate, helpful, completed) {
    if (typeof rate === 'number' && Number.isFinite(rate)) {
      if (rate > 1) return Math.max(0, Math.min(100, Math.round(rate)));
      if (rate > 0 && rate <= 1 && !(rate === 1 && helpful === 0 && completed > 1)) {
        return Math.max(0, Math.min(100, Math.round(rate * 100)));
      }
    }
    return completed > 0 ? Math.max(0, Math.min(100, Math.round((helpful / completed) * 100))) : 0;
  }

  function renderInsights(data) {
    const insights = data?.insights || {};
    const recentSessions = Array.isArray(data?.recentSessions) ? data.recentSessions : [];
    const totalCompleted = Number(insights.totalCompleted) || 0;
    const totalHelpful = Number(insights.totalHelpful) || 0;
    const streakDays = Number(insights.streakDays) || 0;

    $('#stat-completed').textContent = String(totalCompleted);
    $('#stat-streak').textContent = `${streakDays}d`;
    $('#stat-helpful').textContent = totalCompleted > 0 ? `${Math.round((totalHelpful / totalCompleted) * 100)}%` : '—';
    receiptStats.hidden = false;

    const byActivity = Array.isArray(insights.byActivity)
      ? insights.byActivity.filter(item => (item.completed || 0) > 0)
      : [];

    if (byActivity.length) {
      helpsList.replaceChildren(...byActivity.map(item => {
        const row = el('li', 'helps-row');
        const meta = el('div', 'helps-meta');
        const name = item.title || ACTIVITY_META[item.activityId]?.title || item.activityId;
        const pct = percentFromRate(item.helpRate, item.helpful || 0, item.completed || 0);
        meta.append(
          el('strong', '', name),
          el('span', '', `${item.completed} done · ${pct}% helpful`)
        );
        const progress = document.createElement('progress');
        progress.className = 'insight-bar';
        progress.max = 100;
        progress.value = pct;
        progress.setAttribute('aria-label', `${name}: ${pct}% helpful`);
        row.append(meta, progress);
        return row;
      }));
      helpsBlock.hidden = false;
    } else {
      helpsList.replaceChildren();
      helpsBlock.hidden = true;
    }

    const completedOrRated = recentSessions
      .filter(item => item && (item.status === 'completed' || item.feedback || item.completion))
      .slice(0, 10);

    if (completedOrRated.length) {
      receiptsList.replaceChildren(...completedOrRated.map(session => {
        const item = el('li', 'receipt-item');
        const top = el('div', 'receipt-top');
        const title = session.title || ACTIVITY_META[session.activityId]?.title || session.activityId || 'Break';
        top.append(
          el('span', 'receipt-title', title),
          el('time', 'receipt-time', formatDateTime(session.completedAt || session.createdAt))
        );

        const chips = el('div', 'receipt-chips');
        const durationLabel = formatDuration(session);
        if (durationLabel) chips.append(el('span', 'receipt-chip', durationLabel));
        if (Number.isFinite(session.completion?.steps) && session.completion.steps > 0) {
          chips.append(el('span', 'receipt-chip', `${session.completion.steps} steps`));
        }

        const helpful = session.feedback?.helpful;
        if (helpful === 'yes') chips.append(el('span', 'receipt-chip helpful-yes', 'Helpful'));
        else if (helpful === 'somewhat') chips.append(el('span', 'receipt-chip helpful-somewhat', 'Somewhat'));
        else if (helpful === 'no') chips.append(el('span', 'receipt-chip helpful-no', 'Not helpful'));
        else chips.append(el('span', 'receipt-chip', 'Unrated'));

        const vitals = session.completion?.vitals;
        if (vitals && typeof vitals === 'object') {
          if (vitals.startHr != null && vitals.endHr != null) {
            chips.append(el('span', 'receipt-chip vital', `HR ${vitals.startHr} → ${vitals.endHr}`));
          }
          if (vitals.startStress != null && vitals.endStress != null) {
            chips.append(el('span', 'receipt-chip vital', `Stress ${vitals.startStress} → ${vitals.endStress}`));
          }
          if (Number.isFinite(vitals.elevationGain) && vitals.elevationGain > 0) {
            chips.append(el('span', 'receipt-chip vital', `+${vitals.elevationGain}m climb`));
          }
        }

        item.append(top, chips);
        return item;
      }));
      recentBlock.hidden = false;
    } else {
      receiptsList.replaceChildren();
      recentBlock.hidden = true;
    }

    if (totalCompleted === 0 && !completedOrRated.length) {
      receiptsStatus.textContent = 'No completed breaks yet. Accept a break on Momo and your receipts, streaks, and vitals will land here.';
      receiptsStatus.className = 'receipts-status';
      receiptsStatus.hidden = false;
    } else {
      receiptsStatus.textContent = '';
      receiptsStatus.hidden = true;
    }
  }

  async function loadInsights() {
    if (loadingInsights || !accessReady) return;
    loadingInsights = true;
    refreshReceiptsButton.disabled = true;
    refreshReceiptsButton.textContent = 'Refreshing…';
    if (receiptStats.hidden && recentBlock.hidden) {
      receiptsStatus.textContent = 'Checking your break receipts…';
      receiptsStatus.className = 'receipts-status';
      receiptsStatus.hidden = false;
    }
    try {
      const data = await request('/api/insights');
      renderInsights(data);
    } catch {
      receiptsStatus.textContent = 'Couldn’t load break receipts right now. Try refreshing in a moment.';
      receiptsStatus.className = 'receipts-status error';
      receiptsStatus.hidden = false;
    } finally {
      loadingInsights = false;
      refreshReceiptsButton.disabled = false;
      refreshReceiptsButton.textContent = 'Refresh';
    }
  }

  function showPairedView({ scroll = false } = {}) {
    setupContent.hidden = true;
    setupComplete.hidden = false;
    connectionBanner.hidden = true;
    if (scroll) {
      setupComplete.focus({ preventScroll: true });
      setupComplete.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'center' });
    }
    loadInsights();
  }

  function showEditView({ focus = true } = {}) {
    setupComplete.hidden = true;
    setupContent.hidden = false;
    cancelEditButton.hidden = !configured;
    if (focus) {
      form.querySelector('input[name="goals"]').focus();
    }
  }

  async function request(url, options = {}) {
    const response = await fetch(url, {
      credentials: 'same-origin', cache: 'no-store', signal: AbortSignal.timeout(10_000), ...options
    });
    let data;
    try { data = await response.json(); } catch {
      throw Object.assign(new Error('Momo’s service returned an incomplete reply. Please try again.'), { status: response.status });
    }
    if (!response.ok || data.error) {
      throw Object.assign(new Error(typeof data.message === 'string' ? data.message : 'Momo is unavailable. Please try again.'), { status: data.httpStatus || response.status });
    }
    return data;
  }

  async function initializeAccess() {
    if (initializing) return;
    initializing = true;
    try {
      const key = new URLSearchParams(location.hash.slice(1)).get('key');
      if (key) {
        showAccessNotice('Connecting to Momo…', 'Getting your goals ready.', false);
        try {
          await request('/api/onboarding/claim', {
            method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify({ key })
          });
          history.replaceState(null, '', `${location.pathname}${location.search}`);
        } catch (error) {
          if ([400, 401, 403, 404, 410, 429].includes(error.status)) showExpiredAccess();
          else {
            showAccessNotice('Couldn’t connect to Momo.', 'Keep Momo open on your watch and try again.');
            showConnectionError('Your setup connection couldn’t be completed.');
          }
          return;
        }
      }
      try {
        const data = await request('/api/profile');
        applyProfile(data.profile || {}, data.configured === true);
        accessReady = true;
        accessNotice.hidden = true;
        connectionBanner.hidden = true;
        if (configured) showPairedView();
        else showEditView({ focus: false });
      } catch (error) {
        if ([401, 403].includes(error.status)) {
          showAccessNotice('A little hello from your watch.', 'Enter Momo’s four-digit setup code below, or scan the QR code on your watch.');
          connectionBanner.hidden = true;
        } else {
          showAccessNotice('Couldn’t connect to Momo.', 'Your goals couldn’t be loaded. Please try again.');
          showConnectionError('Momo’s service is having trouble connecting.');
        }
      }
    } finally {
      initializing = false;
    }
  }

  form.addEventListener('submit', async event => {
    event.preventDefault();
    if (saving || !accessReady) return;

    const nickname = nicknameInput.value.trim();
    if (nickname.length > 32) {
      setSaveStatus('Keep your nickname to 32 characters or fewer.', true);
      nicknameInput.focus();
      return;
    }

    const goals = [...form.querySelectorAll('input[name="goals"]:checked')].map(input => input.value);
    if (!goals.length) {
      setSaveStatus('Choose at least one goal.', true);
      form.querySelector('input[name="goals"]').focus();
      return;
    }

    const preferredActivities = [...form.querySelectorAll('input[name="preferredActivities"]:checked:not(:disabled)')].map(input => input.value);
    if (!preferredActivities.length) {
      setSaveStatus('Pick at least one break type that fits your seated and break-length settings.', true);
      const firstEligible = form.querySelector('input[name="preferredActivities"]:not(:disabled)');
      if (firstEligible) firstEligible.focus();
      return;
    }

    const reminderStart = reminderStartInput.value;
    const reminderEnd = reminderEndInput.value;
    if (!TIME_PATTERN.test(reminderStart) || !TIME_PATTERN.test(reminderEnd) || reminderStart === reminderEnd) {
      breakHoursDetails.open = true;
      setSaveStatus('Choose different start and end break hours.', true);
      reminderEndInput.focus();
      return;
    }

    if (context.value.length > 1000) {
      setSaveStatus('Keep your notes to 1,000 characters.', true);
      context.focus();
      return;
    }

    const profile = {
      nickname,
      goals,
      humor: selectedHumor(),
      maxBreakMinutes: selectedMaxBreakMinutes(),
      seatedOnly: seatedOnlyInput.checked,
      preferredActivities,
      reminderStart,
      reminderEnd,
      additionalContext: context.value.trim(),
      ...(!configured ? { timeZone: localTimeZone } : {})
    };

    saving = true;
    saveButton.disabled = true;
    saveLabel.textContent = 'Saving…';
    setSaveStatus('Giving Momo the important details.');
    try {
      const data = await request('/api/profile', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify(profile)
      });
      applyProfile(data.profile || profile, data.configured !== false);
      showPairedView({ scroll: true });
      setSaveStatus('You can update these anytime.');
    } catch (error) {
      if ([401, 403].includes(error.status)) showExpiredAccess();
      else setSaveStatus(error.message, true);
    } finally {
      saving = false;
      saveButton.disabled = false;
      saveLabel.textContent = 'Save & return to watch';
    }
  });

  codeForm.addEventListener('submit', async event => {
    event.preventDefault();
    if (claimingCode || initializing) return;
    const code = codeInput.value.trim();
    if (!/^\d{4}$/.test(code)) {
      codeStatus.textContent = 'Enter all four digits shown on Momo.';
      codeStatus.className = 'code-status error';
      codeInput.setAttribute('aria-invalid', 'true');
      codeInput.focus();
      return;
    }
    claimingCode = true;
    codeButton.disabled = true;
    codeButton.textContent = 'Connecting…';
    codeStatus.textContent = 'Finding your little sidekick.';
    codeStatus.className = 'code-status';
    try {
      await request('/api/onboarding/claim', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify({ code })
      });
      // A successful claim exchanges the one-use code for an HttpOnly session.
      // Any old QR fragment can now be removed, without retaining either code.
      history.replaceState(null, '', `${location.pathname}${location.search}`);
      codeInput.value = '';
      await initializeAccess();
    } catch (error) {
      codeStatus.textContent = error.status === 429
        ? 'Too many tries. Wait a few minutes, or scan Momo’s QR code.'
        : [400, 401, 403, 410].includes(error.status)
          ? 'That code didn’t work. Open Momo for a fresh one.'
          : 'Momo couldn’t connect. Please try again.';
      codeStatus.className = 'code-status error';
      codeInput.setAttribute('aria-invalid', 'true');
      codeInput.focus();
    } finally {
      claimingCode = false;
      codeButton.disabled = false;
      codeButton.textContent = 'Connect this watch';
    }
  });

  codeInput.addEventListener('input', () => {
    codeInput.value = codeInput.value.replace(/\D/g, '').slice(0, 4);
    codeInput.removeAttribute('aria-invalid');
    codeStatus.textContent = 'Or scan the QR on the watch instead.';
    codeStatus.className = 'code-status';
  });

  context.addEventListener('input', updateContextCount);
  seatedOnlyInput.addEventListener('change', syncActivityConstraints);
  for (const radio of form.querySelectorAll('input[name="maxBreakMinutes"]')) {
    radio.addEventListener('change', syncActivityConstraints);
  }
  for (const checkbox of form.querySelectorAll('input[name="preferredActivities"]')) {
    checkbox.addEventListener('change', syncActivityConstraints);
  }
  reminderStartInput.addEventListener('input', updateHoursSummary);
  reminderEndInput.addEventListener('input', updateHoursSummary);

  form.addEventListener('input', () => {
    if (saveStatus.classList.contains('error')) setSaveStatus('You can update these anytime.');
  });
  form.addEventListener('change', () => {
    if (saveStatus.classList.contains('error')) setSaveStatus('You can update these anytime.');
  });

  $('#retry-connection').addEventListener('click', initializeAccess);
  $('#edit-profile').addEventListener('click', () => showEditView({ focus: true }));
  cancelEditButton.addEventListener('click', () => showPairedView({ scroll: false }));
  refreshReceiptsButton.addEventListener('click', loadInsights);

  initializeAccess();
})();
