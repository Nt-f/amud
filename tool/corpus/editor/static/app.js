'use strict';
// The real Flutter app (a web build of this checkout), served beside the
// editor. The server reads the corpus asset live from disk, so after a save
// the asset is rebuilt and the page reloaded: it always shows what a
// release would. Nothing here re-implements the reader.

const APPV = { status: { state: 'stopped', log: [], url: '', built: false, stale: false }, auto: store.get('autoSync', true), phone: store.get('phone', true), syncing: false, timer: null, showLog: false };

function showRightTab(t) {
  $$('#rightTabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === t));
  $('#previewWrap').hidden = t !== 'preview';
  $('#appPane').hidden = t !== 'app';
  store.set('rightTab', t);
  if (t === 'app') { renderApp(); pollApp(); } else renderPreview();
}

async function pollApp() {
  clearTimeout(APPV.timer);
  try { APPV.status = await api('/api/app'); } catch { return; }
  updateAppDot();
  if (!$('#appPane').hidden) renderApp(true);
  if (APPV.status.state === 'building' || !$('#appPane').hidden) APPV.timer = setTimeout(pollApp, APPV.status.state === 'building' ? 1500 : 5000);
}

function updateAppDot() { const d = $('#appDot'); if (d) d.className = 'dot ' + APPV.status.state; }

async function appCall(what) {
  try { APPV.status = await api('/api/app/' + what, {}); } catch (e) { return toast(e.message, true); }
  renderApp(); pollApp();
}
function reloadFrame() { const f = $('#appStage iframe'); if (f) f.src = APPV.status.url + '?t=' + Date.now(); }

// Rebuild the asset, then reload the page. `quiet` for the automatic call after a save.
async function appSync(quiet) {
  if (APPV.status.state !== 'ready' || APPV.syncing) { if (!quiet) toast('The app isn\'t running'); return; }
  APPV.syncing = true; updateAppBar();
  try {
    const r = await api('/api/app/sync', { nusach: S.nusach });
    if (!r.ok) showOutput('Could not build the asset — the app still shows the last good build', r.output, false);
    else { reloadFrame(); if (!quiet) toast('App reloaded'); }
  } catch (e) { toast('Sync failed: ' + e.message, true); }
  APPV.syncing = false; updateAppBar();
}
const appSyncSoon = debounce(() => appSync(true), 600);
function afterSaveSync() { if (APPV.auto && APPV.status.state === 'ready') appSyncSoon(); }
async function saveAndSync() { await saveAll(); await appSync(false); }

function renderApp(soft) {
  const box = $('#appPane');
  if (soft && $('#appBar')) { updateAppBar(); return; }
  box.innerHTML = '';
  box.append(h('div', { id: 'appBar' }), h('div', { id: 'appStage', class: APPV.phone ? 'phone' : '' }), h('div', { id: 'appLog', hidden: !APPV.showLog }));
  updateAppBar();
}

function updateAppBar() {
  const st = APPV.status, bar = $('#appBar');
  if (!bar) return;
  const building = st.state === 'building', ready = st.state === 'ready';
  bar.innerHTML = '';
  bar.append(...[
    ready ? h('button', { text: 'Stop', onclick: () => appCall('stop') }) : building ? null : h('button', { class: 'primary', text: st.state === 'error' ? 'Retry' : st.built ? 'Show the app' : 'Build & show the app', onclick: () => appCall('start') }),
    h('span', { class: 'badge ' + (st.state === 'error' ? 'err' : building || st.stale ? 'warn' : ''), text: APPV.syncing ? 'rebuilding the asset…' : building ? 'building (a few minutes the first time)…' : st.stale && ready ? 'ready · Dart code changed since the build' : st.state }),
    ready ? h('button', { text: 'Save & sync', disabled: APPV.syncing, title: 'Save every change, rebuild the corpus asset and reload the app', onclick: saveAndSync }) : null,
    ready ? h('button', { text: 'Reload', onclick: reloadFrame }) : null,
    !building && (st.stale || st.built) ? h('button', { text: 'Rebuild app', title: 'Recompile after changing Dart code', onclick: () => appCall('rebuild') }) : null,
    h('label', { class: 'opt', title: 'After each save, rebuild the asset and reload the app' }, h('input', { type: 'checkbox', checked: APPV.auto, onchange: e => { APPV.auto = e.target.checked; store.set('autoSync', APPV.auto); } }), 'sync on save'),
    h('label', { class: 'opt' }, h('input', { type: 'checkbox', checked: APPV.phone, onchange: e => { APPV.phone = e.target.checked; store.set('phone', APPV.phone); $('#appStage').classList.toggle('phone', APPV.phone); } }), 'phone width'),
    ready ? h('a', { href: st.url, target: '_blank', rel: 'noopener', text: 'open in tab' }) : null,
    h('button', { class: 'ghost', text: 'log', onclick: () => { APPV.showLog = !APPV.showLog; $('#appLog').hidden = !APPV.showLog; } })].filter(Boolean));
  const log = $('#appLog');
  if (log) { log.hidden = !APPV.showLog; log.textContent = (st.log || []).join('\n'); log.scrollTop = log.scrollHeight; }
  const stage = $('#appStage');
  if (!stage) return;
  const frame = stage.querySelector('iframe');
  if (ready && !frame) { stage.innerHTML = ''; stage.append(h('iframe', { src: st.url, title: 'Amud app' })); }
  else if (!ready && (frame || !stage.children.length)) {
    stage.innerHTML = '';
    stage.append(h('div', { class: 'msg' }, building ? 'Compiling the app… it will appear here.' : [
      h('p', { text: 'The real Flutter app, beside the editor.' }),
      h('p', { class: 'hint', text: 'A web build of this checkout, so it reads the corpus exactly as a release does. After a save the corpus asset is rebuilt and the app reloads.' })]));
  }
}
