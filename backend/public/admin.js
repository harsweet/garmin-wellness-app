(() => {
  'use strict';
  const $ = selector => document.querySelector(selector);
  const goalNames = { move: 'Movement', outside: 'Time outside', breaks: 'Better breaks' };
  const activityNames = { walk: 'Walk', stretch: 'Gentle stretch', breathe: 'Breathing break', rest: 'Quiet rest' };
  const pairingLabels = { paired: 'Paired', waiting: 'Waiting for a phone', finishing: 'Code claimed — save goals', idle: 'Not paired yet' };
  let users = [];
  let selectedId = null;
  let setupUserId = null;
  let authenticated = false;
  let loading = false;
  let actionPending = false;

  function text(tag, content, className = '') {
    const node = document.createElement(tag);
    node.textContent = content;
    if (className) node.className = className;
    return node;
  }

  function status(message, error = false) {
    $('#status').textContent = message;
    $('#status').className = `status${error ? ' error' : ''}`;
  }

  function date(value) {
    const parsed = new Date(value);
    return Number.isFinite(parsed.getTime()) ? parsed.toLocaleString(undefined, { month: 'short', day: 'numeric', hour: 'numeric', minute: '2-digit' }) : '';
  }

  async function api(path, body) {
    const response = await fetch(path, {
      method: body === undefined ? 'GET' : 'POST',
      credentials: 'same-origin',
      cache: 'no-store',
      signal: AbortSignal.timeout(12000),
      ...(body === undefined ? {} : { headers: { 'Content-Type': 'application/json', 'X-Momo-Request': '1' }, body: JSON.stringify(body) })
    });
    const data = await response.json();
    if (!response.ok || data.error) throw Object.assign(new Error(data.message || 'The watch room could not be loaded.'), { status: data.httpStatus || response.status });
    return data;
  }

  function showLogin() {
    authenticated = false;
    $('#login').hidden = false;
    $('#workspace').hidden = true;
    $('#admin-actions').hidden = true;
    $('#new-setup').hidden = true;
  }

  function visibleUsers() {
    const search = $('#search').value.trim().toLowerCase();
    return users.filter(user => {
      const live = user.configured || user.activeWatch || user.pairingState === 'waiting' || user.pairingState === 'finishing';
      if (!live) return false;
      const haystack = `${user.label} ${(user.profile.goals || []).map(goal => goalNames[goal]).join(' ')} ${user.profile.additionalContext || ''}`.toLowerCase();
      return haystack.includes(search);
    });
  }

  function pairingCopy(user) {
    if (user.configured) return user.profile.additionalContext || 'No extra notes yet.';
    if (user.pairingState === 'waiting') return 'Scan the QR on Momo, or type the four-digit code at the setup page.';
    if (user.pairingState === 'finishing') return 'This phone claimed the code. Save goals to finish pairing.';
    return 'Open Momo on the watch to start pairing.';
  }

  function listUsers() {
    const visible = visibleUsers();
    const paired = users.filter(user => user.configured).length;
    $('#roster-summary').textContent = users.length
      ? `${paired} paired · ${visible.length} showing`
      : 'Your devices will appear here.';
    if (!visible.length) {
      const empty = text('p', '', 'empty');
      empty.append(text('strong', 'No watches in the room yet.'), document.createTextNode('Open Momo — it starts on setup — or pair another watch from here.'));
      $('#user-list').replaceChildren(empty);
      return;
    }
    $('#user-list').replaceChildren(...visible.map(user => {
      const card = document.createElement('article');
      card.className = `device${user.id === selectedId ? ' selected' : ''}${user.activeWatch ? ' active' : ''}`;
      card.setAttribute('role', 'listitem');
      const top = document.createElement('div');
      top.className = 'device-top';
      const number = text('span', user.label.replace(/\D/g, '').padStart(2, '0') || '01', 'device-number');
      const identity = document.createElement('div');
      identity.append(text('h3', user.label, 'device-title'), text('p', user.id.slice(0, 8), 'device-id'));
      const state = document.createElement('div');
      state.className = 'device-state';
      const badge = text('span', pairingLabels[user.pairingState] || user.pairingState, `badge${user.configured ? ' paired' : ''}`);
      state.append(badge);
      if (user.activeWatch) state.append(text('span', 'This simulator', 'badge lamp'));
      top.append(number, identity, state);

      const body = document.createElement('div');
      body.className = 'device-body';
      const goals = document.createElement('div');
      goals.append(text('h3', 'Goals'));
      const tags = document.createElement('div');
      tags.className = 'tags';
      const savedGoals = user.configured ? (user.profile.goals || []) : [];
      if (savedGoals.length) tags.append(...savedGoals.map(goal => text('span', goalNames[goal] || goal, 'tag')));
      else tags.append(text('span', user.configured ? 'No goals saved' : 'Waiting to pair', 'tag'));
      goals.append(tags);
      const notes = document.createElement('div');
      notes.append(text('h3', 'Context'), text('p', pairingCopy(user), user.configured ? 'context' : 'pending-note'));
      body.append(goals, notes);

      const bottom = document.createElement('div');
      bottom.className = 'device-bottom';
      const stats = document.createElement('dl');
      stats.className = 'device-stats';
      for (const [label, value, extra] of [
        ['Completed', user.counts.completed || 0, ''],
        ['Accepted', user.counts.accepted || 0, ''],
        ['Snoozed', user.counts.snoozed || 0, ''],
        ['Helpful', user.counts.helpful || 0, 'feedback-yes'],
        ['Not helpful', user.counts.notHelpful || 0, 'feedback-no']
      ]) {
        const row = document.createElement('div');
        if (extra) row.className = extra;
        row.append(text('dt', label), text('dd', String(value)));
        stats.append(row);
      }
      const actions = document.createElement('div');
      actions.className = 'device-actions';
      const open = text('button', 'See activity', 'button quiet');
      open.type = 'button';
      open.addEventListener('click', event => {
        event.stopPropagation();
        selectedId = user.id;
        listUsers();
        renderUser();
        $('#user-detail').scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
      });
      actions.append(open);
      if (!user.activeWatch) {
        const assign = text('button', 'Show on this simulator', 'button quiet');
        assign.type = 'button';
        assign.addEventListener('click', event => {
          event.stopPropagation();
          assignWatch(user.id);
        });
        actions.append(assign);
      }
      bottom.append(stats, actions);
      card.append(top, body, bottom);
      card.addEventListener('click', () => {
        selectedId = user.id;
        listUsers();
        renderUser();
      });
      return card;
    }));
  }

  function sensorValue(reading, key) {
    const value = reading?.[key];
    return value === null || value === undefined ? '—' : String(value);
  }

  function renderCheckin(user) {
    const mood = user.mood;
    const reading = user.reading;
    const face = mood?.face || '';
    $('#mood-face').textContent = face === 'sad' ? 'Sad' : face === 'happy' ? 'Happy' : face === 'average' ? 'Average' : 'No reading';
    $('#mood-face').className = `badge${face ? ` ${face}` : ''}`;
    $('#mood-summary').textContent = mood?.summary || 'Waiting for the watch to send a sensor check-in.';
    const rows = [['Steps', reading?.steps != null && reading?.stepGoal ? `${reading.steps} / ${reading.stepGoal}` : sensorValue(reading, 'steps')], ['Calories', sensorValue(reading, 'calories')], ['Distance m', sensorValue(reading, 'distanceMeters')], ['Active min', sensorValue(reading, 'activeMinutes')], ['Moderate min', sensorValue(reading, 'moderateMinutes')], ['Vigorous min', sensorValue(reading, 'vigorousMinutes')], ['Floors up', sensorValue(reading, 'floorsClimbed')], ['Floors down', sensorValue(reading, 'floorsDescended')], ['Heart rate', sensorValue(reading, 'heartRate')], ['Resting HR', sensorValue(reading, 'restingHeartRate')], ['Body battery', sensorValue(reading, 'bodyBattery')], ['Stress', sensorValue(reading, 'stress')], ['SpO2', sensorValue(reading, 'spo2')], ['Breaths', sensorValue(reading, 'respiration')], ['Move bar', sensorValue(reading, 'moveBarLevel')], ['Elevation m', sensorValue(reading, 'elevationMeters')], ['Pressure hPa', sensorValue(reading, 'pressureHpa')], ['Temp C', sensorValue(reading, 'temperatureC')], ['Recovery h', sensorValue(reading, 'timeToRecoveryHours')]];
    $('#sensor-grid').replaceChildren(...rows.map(([label, value]) => {
      const cell = text('div', '');
      cell.append(text('span', label), text('strong', value));
      return cell;
    }));
    const votes = Array.isArray(mood?.votes) && mood.votes.length ? mood.votes.map(item => `${item.label} ${item.value} (${item.vote > 0 ? '+' : ''}${item.vote})`).join(' · ') : 'No face vote yet.';
    $('#mood-meta').textContent = reading?.at ? `${reading.source === 'watch' ? 'Watch' : reading.source === 'simulated' ? 'Simulated' : 'No'} reading · ${date(reading.at)} · ${votes}` : votes;
  }

  function renderUser() {
    const user = users.find(item => item.id === selectedId);
    $('#user-detail').hidden = !user;
    if (!user) return;
    renderCheckin(user);
    $('#wearer-id').textContent = user.id.slice(0, 8);
    $('#wearer-title').textContent = user.label;
    $('#wearer-state').textContent = user.activeWatch ? 'This simulator' : pairingLabels[user.pairingState];
    $('#wearer-state').className = `badge${user.configured ? ' paired' : user.activeWatch ? ' lamp' : ''}`;
    $('#wearer-updated').textContent = `Updated ${date(user.updatedAt)}`;
    $('#assign-watch').hidden = user.activeWatch;
    $('#preference-rows').replaceChildren(...user.preferences.map(item => {
      const row = document.createElement('tr');
      for (const value of [activityNames[item.activityId] || item.title, item.accepted, item.completed, item.helpful, item.somewhat, item.notHelpful, item.snoozed]) {
        row.append(text('td', String(value)));
      }
      return row;
    }));
    const events = user.decisions.map(item => ({
      at: item.at,
      title: `${({ accept: 'Accepted', snooze: 'Snoozed', alternative: 'Asked for another idea after' })[item.decision] || item.decision} · ${activityNames[item.activityId] || item.activityId}`,
      note: item.start ? `Proposed for ${date(item.start)}` : ''
    }));
    for (const session of user.sessions) {
      if (session.status === 'completed') {
        events.push({
          at: session.completedAt,
          title: `Completed · ${session.title}`,
          note: ({ simulated_steps: 'Simulator step data', simulated_timer: 'Simulated timer', steps: 'Watch step data', timer: 'Foreground timer', self_report: 'Self-reported completion' })[session.completion?.source] || 'Completion recorded'
        });
      }
      if (session.feedback) {
        events.push({
          at: session.feedback.at,
          title: `${({ yes: 'Found helpful', somewhat: 'Somewhat helpful', no: 'Not helpful' })[session.feedback.helpful]} · ${session.title}`,
          note: 'Saved for the next suggestion.'
        });
      }
    }
    events.sort((a, b) => Date.parse(b.at) - Date.parse(a.at));
    $('#history-count').textContent = `${events.length} recorded`;
    $('#history-list').replaceChildren(...events.slice(0, 30).map(event => {
      const row = document.createElement('li');
      const details = document.createElement('div');
      details.append(text('div', event.title, 'event-title'), text('div', event.note, 'event-note'));
      row.append(details, text('time', date(event.at), 'event-date'));
      return row;
    }));
    if (!events.length) $('#history-list').append(text('li', 'No activity yet. Accepts, snoozes, and ratings show up here as this watch uses Momo.', 'empty'));
  }

  function renderSetup(user) {
    setupUserId = user.id;
    selectedId = user.id;
    $('#new-setup-title').textContent = `${user.label} is on the watch.`;
    $('#setup-pairing-state').textContent = pairingLabels[user.pairingState] || 'Waiting for a phone';
    $('#setup-instruction').textContent = 'Open Momo on that watch. The QR and four-digit code show there. Scan the QR, or type the code on the phone setup page.';
    $('#setup-assign-watch').hidden = user.activeWatch;
    $('#new-setup').hidden = false;
    $('#new-setup').focus({ preventScroll: true });
    $('#new-setup').scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' });
  }

  function refreshSetupBanner() {
    if ($('#new-setup').hidden || !setupUserId) return;
    const user = users.find(item => item.id === setupUserId);
    if (!user) return;
    $('#setup-pairing-state').textContent = pairingLabels[user.pairingState] || 'Waiting for a phone';
    if (user.configured) {
      $('#new-setup-title').textContent = `${user.label} is paired.`;
      $('#setup-instruction').textContent = 'Goals are saved. Completions and ratings will land on this watch’s row.';
    }
  }

  async function refresh() {
    if (loading || !authenticated) return;
    loading = true;
    try {
      const data = await api('/api/admin/users');
      users = data.users;
      const visible = visibleUsers();
      if (!users.some(user => user.id === selectedId)) selectedId = data.activeUserId && visible.some(user => user.id === data.activeUserId) ? data.activeUserId : visible[0]?.id;
      listUsers();
      renderUser();
      refreshSetupBanner();
      $('#workspace').hidden = false;
      $('#admin-actions').hidden = false;
      $('#login').hidden = true;
      $('#last-updated').textContent = `Updated ${date(data.generatedAt)} · refreshes every 10 seconds`;
      status('Live watch room. Each paired device keeps its own goals, context, and ratings.');
    } catch (error) {
      if ([401, 403].includes(error.status)) showLogin();
      status(error.message, true);
    } finally {
      loading = false;
    }
  }

  async function assignWatch(id) {
    if (!id || actionPending) return;
    actionPending = true;
    try {
      await api(`/api/admin/users/${id}/assign`, {});
      await refresh();
      status('This simulator now uses that watch. Reopen Momo to see its setup.');
    } catch (error) {
      status(error.message, true);
    } finally {
      actionPending = false;
    }
  }

  $('#login-form').addEventListener('submit', async event => {
    event.preventDefault();
    $('#login-button').disabled = true;
    const token = $('#admin-key').value.trim();
    $('#admin-key').value = '';
    try {
      await api('/api/admin/login', { token });
      authenticated = true;
      await refresh();
    } catch (error) {
      status(error.message, true);
    } finally {
      $('#login-button').disabled = false;
    }
  });

  $('#new-user').addEventListener('click', async () => {
    if (actionPending) return;
    actionPending = true;
    $('#new-user').disabled = true;
    try {
      const data = await api('/api/admin/users', {});
      selectedId = data.user.id;
      await refresh();
      renderSetup(data.user);
      status(`${data.user.label} is waiting. The QR and four-digit code are on the watch.`);
    } catch (error) {
      status(error.message, true);
    } finally {
      actionPending = false;
      $('#new-user').disabled = false;
    }
  });

  $('#assign-watch').addEventListener('click', () => assignWatch(selectedId));
  $('#setup-assign-watch').addEventListener('click', () => assignWatch(setupUserId));
  $('#logout').addEventListener('click', async () => {
    try {
      await api('/api/admin/logout', {});
      showLogin();
      status('Signed out.');
    } catch (error) {
      status(error.message, true);
    }
  });
  $('#close-setup').addEventListener('click', () => {
    $('#new-setup').hidden = true;
    setupUserId = null;
  });
  $('#refresh').addEventListener('click', refresh);
  $('#search').addEventListener('input', listUsers);
  document.addEventListener('visibilitychange', () => { if (!document.hidden) refresh(); });

  (async () => {
    try {
      const session = await api('/api/admin/session');
      $('#logout').hidden = session.local;
      if (!session.authenticated) {
        showLogin();
        status('Private watch room. Sign in to see paired devices.');
        return;
      }
      authenticated = true;
      await refresh();
    } catch (error) {
      showLogin();
      status(error.message, true);
    }
  })();
  setInterval(() => { if (!document.hidden && !actionPending) refresh(); }, 10000);
})();
