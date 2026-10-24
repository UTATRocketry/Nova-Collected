// Nova Console page. Served by nova_console.py at /web/console.js.
// Everything comes from /api/status (every 2 s); Nova.ps1 actions go through
// /api/jobs, which queues them for the runner task (docs/design/pi-orchestration.md).

let latest = null;           // the last /api/status payload
let serviceBusy = false;     // a service start/stop request is in flight
const openDetails = new Set();
const logCache = {};

// ── helpers ─────────────────────────────────────────────────────────────────

function el(tag, cls, text) {
  const n = document.createElement(tag);
  if (cls) n.className = cls;
  if (text !== undefined && text !== null) n.textContent = text;
  return n;
}

function toast(msg) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.classList.add('show');
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => t.classList.remove('show'), 4000);
}

async function copyText(text, note) {
  // navigator.clipboard needs https or localhost; operator laptops use plain http.
  try {
    await navigator.clipboard.writeText(text);
    toast(note || 'Copied');
    return;
  } catch (err) { /* fall through */ }
  const ta = document.createElement('textarea');
  ta.value = text;
  ta.style.position = 'fixed';
  ta.style.opacity = '0';
  document.body.appendChild(ta);
  ta.select();
  try { document.execCommand('copy'); toast(note || 'Copied'); }
  catch (err) { toast('Copy failed'); }
  ta.remove();
}

function cmdBlock(command, label) {
  const w = el('div', 'cmd');
  if (label) w.appendChild(el('span', 'label', label));
  w.appendChild(el('code', null, command));
  const b = el('button', null, 'Copy');
  b.onclick = () => copyText(command);
  w.appendChild(b);
  return w;
}

function row(colour, name, meta, extra) {
  const r = el('div', 'row');
  r.appendChild(el('span', 'dot ' + colour));
  r.appendChild(el('span', 'name', name));
  r.appendChild(el('span', 'meta', meta));
  if (extra && extra.length) { r.appendChild(el('span', 'spacer')); extra.forEach(e => r.appendChild(e)); }
  return r;
}

function keptDetails(key, summary, build) {
  const d = el('details');
  d.open = openDetails.has(key);
  d.appendChild(el('summary', null, summary));
  d.appendChild(build());
  d.addEventListener('toggle', () => { if (d.open) openDetails.add(key); else openDetails.delete(key); });
  return d;
}

async function postJson(url, body) {
  const resp = await fetch(url, {method: 'POST', headers: {'Content-Type': 'application/json'},
                                 body: JSON.stringify(body)});
  let data = {};
  try { data = await resp.json(); } catch (err) { /* empty */ }
  return {status: resp.status, data};
}

function runner() {
  const r = (latest && latest.runner) || {};
  return {available: !!r.available, registered: !!r.registered, readOnly: !!r.readOnly,
          passwordSet: !!r.passwordSet, active: r.active || null};
}

// ── running Nova.ps1 actions ────────────────────────────────────────────────

// Resolves to null (cancelled) or {password}.
function confirmRun(title, display, warn, needsPassword, note) {
  return new Promise(resolve => {
    const back = document.getElementById('modal-back');
    const pw = document.getElementById('modal-pw');
    const ok = document.getElementById('modal-ok');
    document.getElementById('modal-title').textContent = title;
    document.getElementById('modal-cmd').textContent = display;
    document.getElementById('modal-warn').textContent = warn || '';
    document.getElementById('modal-pw-wrap').style.display = needsPassword ? '' : 'none';
    document.getElementById('modal-note').textContent = note || '';
    pw.value = '';
    const update = () => { ok.disabled = needsPassword && !pw.value; };
    pw.oninput = update;
    update();
    const done = (answer) => { back.classList.remove('show'); pw.value = ''; resolve(answer); };
    ok.onclick = () => done({password: pw.value});
    pw.onkeydown = (e) => { if (e.key === 'Enter' && !ok.disabled) ok.click(); };
    document.getElementById('modal-cancel').onclick = () => done(null);
    back.onclick = (e) => { if (e.target === back) done(null); };
    back.classList.add('show');
    (needsPassword ? pw : ok).focus();
  });
}

// Validate on the console (which returns the exact command), confirm anything
// that changes state, then queue it. Without a runner, or read-only, copy the
// command instead.
async function runAction(action, params, title) {
  const pre = await postJson('/api/jobs', {action, params, preview: true});
  if (pre.status !== 200) { toast('Not run: ' + (pre.data.message || 'HTTP ' + pre.status)); return; }
  const st = runner();
  if (!st.available) {
    copyText(pre.data.display, st.readOnly ? 'Read-only: command copied' : 'No runner: command copied');
    return;
  }
  if (st.active) { toast('Busy: ' + st.active.display); return; }
  let password = '';
  if (pre.data.changes) {
    let note = '';
    while (true) {
      const answer = await confirmRun(title, pre.data.display, pre.data.warn, pre.data.needsPassword, note);
      if (!answer) return;
      password = answer.password;
      if (!pre.data.needsPassword) break;
      // Check the password before queueing, so a typo just asks again.
      const res = await postJson('/api/jobs', {action, params, password});
      if (res.status === 401 && res.data.needsPassword) { note = res.data.message; continue; }
      return started(res);
    }
  }
  started(await postJson('/api/jobs', {action, params, password}));
}

function started(res) {
  if (res.status !== 200) {
    toast('Not run: ' + (res.data.message || 'HTTP ' + res.status));
    return;
  }
  toast('Started: ' + res.data.job.display);
  watchJob(res.data.job.id, true);
  document.getElementById('activity').scrollIntoView({behavior: 'smooth', block: 'start'});
  refresh(true);
}

function actionLabel(a) {
  const p = a.params || {};
  switch (a.action) {
    case 'use': return 'Use ' + p.Target;
    case 'deploy': return 'Deploy' + (p.Target ? ' ' + p.Target : '') + (p.AlsoDeploy ? ' + ' + p.AlsoDeploy.join(', ') : '');
    case 'promote': return 'Promote ' + p.Target;
    default: return a.action.charAt(0).toUpperCase() + a.action.slice(1);
  }
}

function actionButton(a, primary) {
  const st = runner();
  const b = el('button', primary ? 'primary' : null, st.available ? actionLabel(a) : 'Copy');
  b.title = a.display;
  b.disabled = st.available && !!st.active;
  b.onclick = () => runAction(a.action, a.params, actionLabel(a) + '?');
  return b;
}

// ── activity: a job's live log ──────────────────────────────────────────────

let watching = null;   // {id, offset, timer, announce, placeholder}

function setBadge(status) {
  const b = document.getElementById('job-badge');
  b.innerHTML = '';
  if (status) b.appendChild(el('span', 'badge ' + status, status));
}

async function pollJob() {
  if (!watching) return;
  const w = watching;
  try {
    const resp = await fetch('/api/jobs/' + w.id + '?offset=' + w.offset);
    if (resp.ok) {
      const data = await resp.json();
      if (watching !== w) return;
      const log = document.getElementById('job-log');
      const atBottom = log.scrollTop + log.clientHeight >= log.scrollHeight - 30;
      if (data.text) {
        if (w.placeholder) { log.textContent = ''; w.placeholder = false; }
        log.textContent += data.text;
      }
      w.offset = data.offset;
      const job = data.job;
      document.getElementById('job-title').textContent = job.display;
      document.getElementById('job-when').textContent = (job.requested || '').replace('T', ' ') + (job.runAs ? ' · ' + job.runAs : '');
      setBadge(job.status);
      if (job.status === 'done' || job.status === 'failed') {
        if (data.err) log.textContent += '\n--- errors ---\n' + data.err + '\n';
        if (!log.textContent.trim()) log.textContent = '(no output)';
        if (w.announce) toast(job.display + ': ' + job.status);
        watching = null;
        refresh(true);
        renderHistory();
        return;
      }
      if (job.status === 'queued' && !log.textContent) { log.textContent = 'Queued…\n'; w.placeholder = true; }
      if (atBottom) log.scrollTop = log.scrollHeight;
    }
  } catch (err) {
    // The console restarts during deploy and install; keep trying.
    document.getElementById('job-when').textContent = 'reconnecting…';
  }
  w.timer = setTimeout(pollJob, 1000);
}

function watchJob(id, announce) {
  if (watching && watching.id === id) return;
  if (watching) clearTimeout(watching.timer);
  const log = document.getElementById('job-log');
  log.style.display = '';
  log.textContent = '';
  log.dataset.id = id;
  watching = {id, offset: 0, timer: null, announce, placeholder: false};
  pollJob();
  renderHistory();
}

async function renderHistory() {
  let data;
  try { data = await (await fetch('/api/jobs')).json(); } catch (err) { return; }
  const box = document.getElementById('history');
  box.innerHTML = '';
  const shown = document.getElementById('job-log').dataset.id || '';
  for (const j of data.jobs || []) {
    const it = el('div', 'item' + (j.id === shown ? ' sel' : ''));
    it.appendChild(el('span', 'when', (j.requested || '').replace('T', ' ')));
    it.appendChild(el('span', 'mono', j.display));
    it.appendChild(el('span', 'badge ' + j.status, j.status));
    it.onclick = () => watchJob(j.id, false);
    box.appendChild(it);
  }
}

// ── action forms ────────────────────────────────────────────────────────────
// Labels are the Nova.ps1 flag names; docs/deployment/commands.md explains them.

const FORMS = [
  {action: 'get-changes', title: 'Get Changes', fields: [
    {name: 'Ref', type: 'text', placeholder: 'current branch', list: ['dev', 'main']},
    {name: 'PiRef', label: 'Pi Ref', type: 'text', placeholder: 'current branch', list: ['dev', 'main']},
    {name: 'Only', type: 'checks', options: ['backend', 'frontend']},
    {name: 'Offline', type: 'bool'},
    {name: 'SkipPi', label: 'Skip Pis', type: 'bool'}]},
  {action: 'pin', title: 'Pin', fields: [
    {name: 'Test', type: 'text', required: true},
    {name: 'Notes', type: 'textarea'},
    {name: 'Firmware', type: 'text'},
    {name: 'SkipPi', label: 'Skip Pis', type: 'bool'}]},
  {action: 'promote', title: 'Promote', fields: [
    {name: 'Target', label: 'Release', type: 'select', source: 'unpromoted', required: true}]},
  {action: 'deploy', title: 'Deploy', danger: true, fields: [
    {name: 'Target', label: 'Release', type: 'select', source: 'deployable'},
    {name: 'AlsoDeploy', label: 'Also Deploy', type: 'checks', source: 'alsoDeploy'},
    {name: 'WithConfig', label: 'With Config', type: 'bool'},
    {name: 'AllowPrerelease', label: 'Allow Prerelease', type: 'bool'},
    {name: 'SkipPi', label: 'Skip Pis', type: 'bool'}]},
  {action: 'publish', title: 'Publish', fields: [
    {name: 'DryRun', label: 'Dry Run', type: 'bool', checked: true}]},
];

const ADVANCED_FORMS = [
  {action: 'hotfix', title: 'Hotfix', danger: true, fields: [
    {name: 'Name', type: 'text', required: true, placeholder: 'igniter-delay'},
    {name: 'Test', type: 'text', required: true},
    {name: 'Notes', type: 'textarea'},
    {name: 'SkipPi', label: 'Skip Pis', type: 'bool'}]},
  {action: 'install', title: 'Install', danger: true, fields: [
    {name: 'Env', type: 'select', options: ['prod', 'dev'], required: true},
    {name: 'Only', type: 'checks', options: ['backend', 'frontend', 'fas', 'console']},
    {name: 'Offline', type: 'bool'}]},
];

const formInputs = {};   // action -> {field name: element}

function addCheck(box, value) {
  const lab = el('label', 'check');
  const cb = el('input'); cb.type = 'checkbox'; cb.value = value;
  lab.append(cb, document.createTextNode(value));
  box.appendChild(lab);
}

function buildForm(spec) {
  const card = el('div', 'card');
  card.appendChild(el('h3', null, spec.title));
  const inputs = {};
  for (const f of spec.fields) {
    const label = (f.label || f.name) + (f.required ? ' *' : '');
    if (f.type === 'bool') {
      const lab = el('label', 'check');
      const cb = el('input'); cb.type = 'checkbox'; cb.checked = !!f.checked;
      lab.append(cb, document.createTextNode(label));
      card.appendChild(lab);
      inputs[f.name] = cb;
      continue;
    }
    const lab = el('label', 'field');
    lab.appendChild(document.createTextNode(label));
    let input;
    if (f.type === 'checks') {
      input = el('div', 'checks');
      input.dataset.source = f.source || '';
      (f.options || []).forEach(o => addCheck(input, o));
    } else if (f.type === 'select') {
      input = el('select');
      input.dataset.source = f.source || '';
      (f.options || []).forEach(o => { const op = el('option', null, o); op.value = o; input.appendChild(op); });
    } else {
      input = f.type === 'textarea' ? el('textarea') : el('input');
      if (f.type !== 'textarea') input.type = 'text';
      input.placeholder = f.placeholder || '';
      if (f.list) {
        const dl = el('datalist');
        dl.id = 'list-' + spec.action + '-' + f.name;
        f.list.forEach(v => { const op = el('option'); op.value = v; dl.appendChild(op); });
        card.appendChild(dl);
        input.setAttribute('list', dl.id);
      }
    }
    lab.appendChild(input);
    card.appendChild(lab);
    inputs[f.name] = input;
  }
  const go = el('div', 'go');
  const btn = el('button', 'big ' + (spec.danger ? 'danger' : 'primary'), spec.title);
  btn.dataset.form = spec.action;
  btn.onclick = () => submitForm(spec);
  go.appendChild(btn);
  card.appendChild(go);
  formInputs[spec.action] = inputs;
  return card;
}

function submitForm(spec) {
  const inputs = formInputs[spec.action];
  const params = {};
  for (const f of spec.fields) {
    const n = inputs[f.name];
    if (f.type === 'bool') { if (n.checked) params[f.name] = true; continue; }
    if (f.type === 'checks') {
      const vals = [...n.querySelectorAll('input:checked')].map(c => c.value);
      if (vals.length) params[f.name] = vals;
      continue;
    }
    const v = (n.value || '').trim();
    if (f.required && !v) { toast((f.label || f.name) + ' is required'); n.focus(); return; }
    if (v) params[f.name] = v;
  }
  if (spec.action === 'deploy' && params.Target) {
    const t = ((latest && latest.forms.tags) || []).find(x => x.tag === params.Target);
    if (t && !t.stable && !params.AllowPrerelease) { toast(params.Target + ' isn\'t stable: tick Allow Prerelease'); return; }
  }
  runAction(spec.action, params, spec.title + '?');
}

// Refill a dropdown without losing what's chosen.
function fillSelect(sel, options) {
  const key = JSON.stringify(options);
  if (sel.dataset.key === key) return;
  const keep = sel.value;
  sel.innerHTML = '';
  for (const [value, label] of options) { const op = el('option', null, label); op.value = value; sel.appendChild(op); }
  if (options.some(o => o[0] === keep)) sel.value = keep;
  sel.dataset.key = key;
}

function updateActions(data) {
  const forms = data.forms || {tags: [], alsoDeploy: []};
  const tags = forms.tags || [];
  for (const sel of document.querySelectorAll('select[data-source]')) {
    if (sel.dataset.source === 'unpromoted') {
      const opts = tags.filter(t => !t.stable).map(t => [t.tag, t.tag + (t.test ? ' - ' + t.test : '')]);
      fillSelect(sel, opts.length ? opts : [['', 'none']]);
    } else if (sel.dataset.source === 'deployable') {
      fillSelect(sel, [['', 'newest stable' + (forms.latestStable ? ' (' + forms.latestStable + ')' : '')]].concat(
        tags.map(t => [t.tag, t.tag + (t.stable ? '' : ' (prerelease)') + (t.test ? ' - ' + t.test : '')])));
    }
  }
  for (const box of document.querySelectorAll('.checks[data-source="alsoDeploy"]')) {
    const key = JSON.stringify(forms.alsoDeploy || []);
    if (box.dataset.key === key) continue;
    box.innerHTML = '';
    (forms.alsoDeploy || []).forEach(n => addCheck(box, n));
    if (!(forms.alsoDeploy || []).length) box.appendChild(el('span', 'hint', 'none'));
    box.dataset.key = key;
  }

  const st = runner();
  const notice = document.getElementById('runner-notice');
  notice.innerHTML = '';
  if (st.readOnly) {
    notice.appendChild(el('div', 'notice', 'Read-only: buttons copy the command.'));
  } else if (!st.registered) {
    const n = el('div', 'notice', 'No runner: buttons copy the command. Set it up once (elevated):');
    n.appendChild(cmdBlock('.\\ops\\Nova.ps1 console-runner'));
    notice.appendChild(n);
  } else if (!st.passwordSet) {
    const n = el('div', 'notice', 'No admin password configured: only Status, Doctor and dry runs will run. Reinstall the console:');
    n.appendChild(cmdBlock('.\\ops\\Nova.ps1 install -Env prod -Only console'));
    notice.appendChild(n);
  }
  // One action at a time.
  for (const b of document.querySelectorAll('button[data-form], button[data-run], #stack-switch button')) {
    b.disabled = st.available && !!st.active;
  }
  for (const b of document.querySelectorAll('button[data-form]')) {
    const spec = FORMS.concat(ADVANCED_FORMS).find(s => s.action === b.dataset.form);
    b.textContent = st.available ? spec.title : 'Copy';
  }
  for (const b of document.querySelectorAll('#stack-switch button')) {
    b.classList.toggle('on', b.dataset.env === data.liveStack);
  }
  document.getElementById('live-busy').textContent = st.active ? 'Running: ' + st.active.display : '';
  if (st.active && !watching) watchJob(st.active.id, false);
}

function setupActions() {
  FORMS.forEach(s => document.getElementById('cards').appendChild(buildForm(s)));
  ADVANCED_FORMS.forEach(s => document.getElementById('cards-advanced').appendChild(buildForm(s)));
  for (const b of document.querySelectorAll('button[data-run]')) {
    b.onclick = () => runAction(b.dataset.run, {}, b.textContent + '?');
  }
  for (const b of document.querySelectorAll('#stack-switch button')) {
    b.onclick = () => {
      if (latest && latest.liveStack === b.dataset.env) { toast(b.dataset.env + ' is already live'); return; }
      runAction('use', {Target: b.dataset.env}, 'Use ' + b.dataset.env + '?');
    };
  }
}

// ── status ──────────────────────────────────────────────────────────────────

async function serviceAct(service, action) {
  if (serviceBusy) return;
  serviceBusy = true;
  toast(action + ' ' + service + '…');
  try {
    const res = await postJson('/api/action', {service, action});
    toast(res.data.ok ? service + ': ' + res.data.message : 'Failed: ' + res.data.message);
  } catch (err) {
    toast('Request failed: ' + err);
  } finally {
    serviceBusy = false;
    refresh(true);
  }
}

function serviceButtons(svc) {
  if (runner().readOnly) return [];
  const mk = (label, action) => {
    const b = el('button', null, label);
    b.onclick = () => serviceAct(svc.service, action);
    b.disabled = svc.state === 'NOT_INSTALLED';
    return b;
  };
  return [mk('Start', 'start'), mk('Stop', 'stop'), mk('Restart', 'restart')];
}

function logBlock(svc) {
  const key = 'log:' + svc.service;
  const d = el('details');
  d.open = openDetails.has(key);
  d.appendChild(el('summary', null, 'logs'));
  const pre = el('pre', null, logCache[svc.service] || 'loading…');
  d.appendChild(pre);
  // Also fires for a details re-opened by a refresh, so an open log stays live.
  d.addEventListener('toggle', async () => {
    if (!d.open) { openDetails.delete(key); return; }
    openDetails.add(key);
    try {
      logCache[svc.service] = await (await fetch('/api/logs?service=' + encodeURIComponent(svc.service))).text();
    } catch (err) {
      logCache[svc.service] = '(could not load the log: ' + err + ')';
    }
    pre.textContent = logCache[svc.service];
    pre.scrollTop = pre.scrollHeight;
  });
  return d;
}

function renderLive(data) {
  const live = data.liveStack;
  document.getElementById('live').className = 'live ' + (live || 'none');
  document.getElementById('live-text').textContent =
    live === 'prod' ? 'PROD' : live === 'dev' ? 'DEV' : 'Nothing is live';
  const v = data.version || {};
  let text = '';
  if (live === 'prod') text = v.release || 'unknown release';
  else if (live === 'dev') text = (v.commits || []).map(c => c.name + ' ' + c.commit).join(' · ');
  document.getElementById('live-version').textContent = text;
}

function renderNext(items) {
  const wrap = document.getElementById('next');
  wrap.innerHTML = '';
  if (!items.length) { wrap.appendChild(el('div', 'step ok', 'Nothing to do.')); return; }
  for (const s of items) {
    const box = el('div', 'step');
    box.appendChild(el('span', 'dot ' + s.level));
    const text = el('div', 'text', s.text);
    box.appendChild(text);
    if (s.action) box.appendChild(actionButton(s.action, s.level !== 'info'));
    else text.appendChild(cmdBlock(s.command, s.where === 'Pi' ? 'On the Pi' : null));
    wrap.appendChild(box);
  }
}

function piDetails(p) {
  const box = el('div');
  const facts = el('table', 'kv');
  for (const [k, v] of [['Address', p.ip], ['Hostname', p.hostname || '?'], ['Binary', p.target || '?'],
                        ['Prod release', p.release || '?'], ['Last report', p.ageText]]) {
    const tr = el('tr');
    tr.appendChild(el('td', null, k));
    tr.appendChild(el('td', 'mono', v));
    facts.appendChild(tr);
  }
  box.appendChild(facts);
  const wrap = el('div', 'table-wrap');
  const t = el('table');
  const head = el('tr');
  ['', 'Service', 'Checkout', 'Backend', 'Last upload'].forEach(h => head.appendChild(el('th', null, h)));
  t.appendChild(head);
  for (const env of ['prod', 'dev']) {
    const i = p.instances[env];
    if (!i) continue;
    const tr = el('tr');
    tr.appendChild(el('td', null, env));
    tr.appendChild(el('td', null, (i.state || '?') + (i.enabled === 'enabled' ? ', on boot' : '')));
    let co = (i.commit || '-------') + ' ' + (i.branch || '');
    if (i.dirty) co += ' +' + i.dirty + ' uncommitted';
    if (i.built === false) co += ' (not built)';
    tr.appendChild(el('td', 'mono', co));
    let be = 'no settings';
    if (i.configured) {
      be = i.backend || '?';
      if (i.health) be += i.health.ok ? ' ok' : ' unreachable';
      if (i.expected && i.backend !== i.expected) be += ' (should be ' + i.expected + ')';
    }
    tr.appendChild(el('td', 'mono', be));
    const up = i.lastUpload;
    tr.appendChild(el('td', null, up ? (up.ok ? 'OK ' : 'FAILED ') + (up.time || '') : '-'));
    t.appendChild(tr);
  }
  wrap.appendChild(t);
  box.appendChild(wrap);
  return box;
}

function renderPis(pis, hosts) {
  const wrap = document.getElementById('pis');
  wrap.innerHTML = '';
  if (!pis.length) {
    // An older console.json: ping only.
    for (const h of hosts) {
      wrap.appendChild(row(h.ping.state === 'ok' ? 'green' : 'red', h.name, h.ip + ' · ' + h.ping.state + ' ' + h.ping.detail));
    }
    return;
  }
  for (const p of pis) {
    let meta = p.runningLabel;
    if (p.commit) meta += ' · ' + p.commit + ' ' + (p.branch || '');
    if (p.running && p.instances[p.running]) {
      const i = p.instances[p.running];
      meta += ' · ' + (i.backend || '?') + (i.health ? (i.health.ok ? '' : ' unreachable') : '');
    }
    meta += ' · ping ' + (p.ping.state === 'ok' ? p.ping.detail : 'no reply') + ' · reported ' + p.ageText;
    wrap.appendChild(row(p.overall, p.name + (p.pinned ? ' (pinned)' : ''), meta));
    if (p.flags.length) {
      const f = el('div', 'flags');
      for (const x of p.flags) {
        const line = el('div', 'flag lvl-' + x.level);
        line.appendChild(el('span', null, x.text));
        if (x.action) line.appendChild(actionButton(x.action, false));
        f.appendChild(line);
        if (x.fix && !x.action) f.appendChild(cmdBlock(x.fix, x.where === 'Pi' ? 'On the Pi' : null));
      }
      wrap.appendChild(f);
    }
    if (p.reported) wrap.appendChild(keptDetails('pi:' + p.name, 'details', () => piDetails(p)));
  }
}

function renderReleases(rel) {
  const wrap = document.getElementById('releases');
  wrap.innerHTML = '';
  if (!rel || !rel.available) { wrap.appendChild(el('p', 'hint', 'None yet.')); return; }
  const tw = el('div', 'table-wrap');
  const t = el('table');
  const head = el('tr');
  ['Release', 'Pinned', 'Test', 'novaGround', 'Ran with'].forEach(h => head.appendChild(el('th', null, h)));
  t.appendChild(head);
  for (const r of rel.releases) {
    const tr = el('tr');
    const tag = el('td', 'mono', r.tag);
    if (r.prod) tag.appendChild(el('span', 'badge prod', 'prod'));
    if (r.stable) tag.appendChild(el('span', 'badge stable', 'stable'));
    if (r.kind === 'hotfix') tag.appendChild(el('span', 'badge hotfix', 'hotfix'));
    tr.appendChild(tag);
    tr.appendChild(el('td', null, r.created));
    tr.appendChild(el('td', null, r.test || ''));
    tr.appendChild(el('td', 'mono', r.novaGround));
    const ran = el('td');
    if (!r.ranWith.length) ran.appendChild(el('span', 'hint', '-'));
    for (const w of r.ranWith) {
      const line = el('div', w.commit && !w.matches ? 'differs' : null);
      line.textContent = w.commit
        ? w.name + ' ' + w.commit + ' ' + (w.branch || '') + (w.matches ? '' : ' (differs)') + (w.dirty ? ' +uncommitted' : '')
        : w.name + ': ' + (w.note || 'not recorded');
      ran.appendChild(line);
    }
    tr.appendChild(ran);
    t.appendChild(tr);
  }
  tw.appendChild(t);
  wrap.appendChild(tw);
}

const COPY_COMMANDS = [
  ['On a Pi', [
    ['Status', './nova-pi.sh status'],
    ['Follow log', 'journalctl -u novaGround@prod -f'],
    ['Failed uploads', 'journalctl -u novaGround@prod | grep UPLOAD'],
    ['Switch this Pi', 'sudo ./nova-pi.sh use prod'],
    ['Install', 'sudo ./nova-pi.sh install --name NovaGround --target novaGround'],
    ['Bench run', './run.sh --env dev']]],
  ['On the ops PC (elevated)', [
    ['Follow log', '.\\ops\\Nova.ps1 logs -Env prod -Only backend -Follow'],
    ['Set up runner', '.\\ops\\Nova.ps1 console-runner']]],
];

function renderCommands() {
  const wrap = document.getElementById('commands');
  for (const [where, commands] of COPY_COMMANDS) {
    const group = el('div', 'copy-group');
    group.appendChild(el('div', 'hint', where));
    for (const [label, command] of commands) group.appendChild(cmdBlock(command, label));
    wrap.appendChild(group);
  }
}

function render(data) {
  latest = data;
  document.getElementById('clock').textContent = 'updated ' + data.time;
  document.getElementById('server').textContent = data.server;
  document.body.classList.remove('stale');

  renderLive(data);
  updateActions(data);

  const links = document.getElementById('links');
  links.innerHTML = '';
  for (const [env, url] of Object.entries(data.uiUrls || {})) {
    const a = el('a', null, 'novaOps UI (' + env + ')');
    a.href = url;
    a.target = '_blank';
    links.appendChild(a);
  }

  const b = data.broker;
  const bColour = b.state === 'RUNNING' && b.port.state === 'ok' ? 'green' : b.state === 'RUNNING' ? 'amber' : 'red';
  const bWrap = document.getElementById('broker');
  bWrap.innerHTML = '';
  bWrap.appendChild(row(bColour, b.service || 'mosquitto',
      b.state + ' · ' + b.endpoint + ' · ' + b.port.state + ' ' + b.port.detail,
      serviceButtons({service: b.service, state: b.state})));

  const wrap = document.getElementById('services');
  wrap.innerHTML = '';
  let currentEnv = null;
  for (const svc of data.services) {
    if (svc.env !== currentEnv) {
      currentEnv = svc.env;
      wrap.appendChild(el('h2', null, currentEnv + (currentEnv === data.liveStack ? ' (live)' : '')));
    }
    const meta = svc.state + (svc.health.detail ? ' · ' + svc.health.detail : '');
    wrap.appendChild(row(svc.overall === 'red' && svc.state === 'NOT_INSTALLED' ? 'grey' : svc.overall,
                         svc.component, meta, serviceButtons(svc)));
    wrap.appendChild(logBlock(svc));
  }

  renderPis(data.pis || [], data.hosts || []);
  renderReleases(data.releases);
  renderNext(data.suggestions || []);
}

async function refresh(force) {
  try {
    render(await (await fetch('/api/status' + (force ? '?force=1' : ''))).json());
  } catch (err) {
    document.getElementById('clock').textContent = 'console unreachable';
    document.body.classList.add('stale');
  }
}

setupActions();
renderCommands();
refresh(true).then(renderHistory);
setInterval(() => { if (!serviceBusy) refresh(false); }, 2000);
