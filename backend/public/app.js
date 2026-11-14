(() => {
  'use strict';

  const $ = selector => document.querySelector(selector);
  const form = $('#profile-form');
  const saveButton = $('#save-profile');
  const saveLabel = $('#save-label');
  const saveStatus = $('#save-status');
  const context = $('#additional-context');
  const accessNotice = $('#access-notice');
  const setupContent = $('#setup-content');
  const setupComplete = $('#setup-complete');
  const connectionBanner = $('#connection-banner');
  const localTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Edmonton';
  let accessReady = false;
  let initializing = false;
  let saving = false;
  let configured = false;

  function setSaveStatus(message, error = false) {
    saveStatus.textContent = message;
    saveStatus.className = `save-status${error ? ' error' : ''}`;
  }

  function showAccessNotice(title, message) {
    accessReady = false;
    accessNotice.hidden = false;
    $('#access-title').textContent = title;
    $('#access-message').textContent = message;
    setupContent.hidden = true;
    setupComplete.hidden = true;
  }

  function showExpiredAccess() {
    showAccessNotice('Scan a fresh code from Momo.', 'This setup link has expired or already been used. Open Momo on your watch and scan its new QR code.');
    connectionBanner.hidden = true;
  }

  function showConnectionError(message) {
    $('#connection-message').textContent = message;
    connectionBanner.hidden = false;
  }

  function updateContextCount() {
    $('#context-count').textContent = `${context.value.length} / 1000`;
  }

  function applyProfile(profile, isConfigured) {
    configured = isConfigured;
    for (const checkbox of form.querySelectorAll('input[name="goals"]')) {
      checkbox.checked = Array.isArray(profile.goals) && profile.goals.includes(checkbox.value);
    }
    context.value = typeof profile.additionalContext === 'string' ? profile.additionalContext : '';
    updateContextCount();
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
        setupContent.hidden = false;
        connectionBanner.hidden = true;
      } catch (error) {
        if ([401, 403].includes(error.status)) {
          showAccessNotice('Start with Momo on your watch.', 'Scan the QR code on your watch to choose your goals here.');
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
    const goals = [...form.querySelectorAll('input[name="goals"]:checked')].map(input => input.value);
    if (!goals.length) {
      setSaveStatus('Choose at least one goal.', true);
      form.querySelector('input[name="goals"]').focus();
      return;
    }
    if (context.value.length > 1000) {
      setSaveStatus('Keep your notes to 1,000 characters.', true);
      context.focus();
      return;
    }
    // Send just these edits so existing activity and accessibility preferences
    // remain intact. A new profile uses the phone's time zone automatically.
    const profile = { goals, additionalContext: context.value.trim(), ...(!configured ? { timeZone: localTimeZone } : {}) };
    saving = true;
    saveButton.disabled = true;
    saveLabel.textContent = 'Saving…';
    setSaveStatus('Giving Momo the important details.');
    try {
      const data = await request('/api/profile', {
        method: 'POST', headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify(profile)
      });
      applyProfile(data.profile || profile, data.configured !== false);
      setupContent.hidden = true;
      setupComplete.hidden = false;
      connectionBanner.hidden = true;
      setupComplete.focus({ preventScroll: true });
      setupComplete.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'center' });
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

  context.addEventListener('input', updateContextCount);
  form.addEventListener('input', () => {
    if (saveStatus.classList.contains('error')) setSaveStatus('You can update these anytime.');
  });
  $('#retry-connection').addEventListener('click', initializeAccess);
  $('#edit-profile').addEventListener('click', () => {
    setupComplete.hidden = true;
    setupContent.hidden = false;
    form.querySelector('input[name="goals"]').focus();
  });
  initializeAccess();
})();
