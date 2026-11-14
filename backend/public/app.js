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
  const codeForm = $('#setup-code-form');
  const codeInput = $('#setup-code');
  const codeButton = $('#connect-code');
  const codeStatus = $('#setup-code-status');
  const localTimeZone = Intl.DateTimeFormat().resolvedOptions().timeZone || 'America/Edmonton';
  let accessReady = false;
  let initializing = false;
  let saving = false;
  let configured = false;
  let claimingCode = false;

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
        setupContent.hidden = false;
        connectionBanner.hidden = true;
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
      codeButton.textContent = 'Connect to Momo';
    }
  });

  codeInput.addEventListener('input', () => {
    codeInput.value = codeInput.value.replace(/\D/g, '').slice(0, 4);
    codeInput.removeAttribute('aria-invalid');
    codeStatus.textContent = 'Or scan the QR code on your watch.';
    codeStatus.className = 'code-status';
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
