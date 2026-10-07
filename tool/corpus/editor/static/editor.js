'use strict';
// App shell: loading, saving, the book tree, raw tabs, problems, reference,
// build commands and shortcuts.

const openNodes = {};     // nusach → Set of expanded tree paths
let treeMode = store.get('treeMode', 'path');
let treeFilter = '';

// ---------- loading
async function loadSiddur(n) {
  const d = await api('/api/siddur?nusach=' + encodeURIComponent(n));
  d.chunks.forEach(c => { c.dirty = false; c.past = []; c.future = []; c.problems = []; });
  d.bookDirty = false; d.bookProblems = [];
  S.docs[n] = d;
  openNodes[n] = openNodes[n] || new Set();
  d.chunks.forEach((c, ci) => scheduleValidate(n, ci, 60 * ci));
  return d;
}

async function selectNusach(n, keepPath) {
  const prevPath = keepPath === false ? null : (leaf() || {}).path;
  if (!S.docs[n]) await loadSiddur(n);
  S.nusach = n;
  $('#nusach').value = n;
  S.sel = { chunk: 0, leaf: 0 };
  S.curSeg = null;
  if (prevPath) {
    const hit = flatLeaves().find(x => x.l.path === prevPath);
    if (hit) S.sel = { chunk: hit.ci, leaf: hit.li };
  }
  store.set('last', { n, path: (leaf() || {}).path });
  renderAll();
}

function selectLeaf(ci, li, quiet) {
  S.sel = { chunk: ci, leaf: li };
  S.curSeg = null;
  const l = leaf();
  store.set('last', { n: S.nusach, path: l && l.path });
  if (quiet) { renderVisual(); renderPreviewBar(); renderPreview(false); renderTree(); updateCrumb(); renderRaw(); return; }
  showCenterTab(S.centerTab === 'book' || S.centerTab === 'file' ? 'visual' : S.centerTab);
  renderAll();
  $('#visual').scrollTop = 0;
  $('#preview').scrollTop = 0;
}

function renderAll() {
  renderTree(); renderVisual(); renderPreviewBar(); renderPreview(false); renderRaw(); renderFileRaw(); renderBookInfo();
  renderProblems(); updateTop(); updateCrumb();
}

function updateCrumb() {
  const l = leaf();
  $('#leafCrumb').textContent = l ? l.path : '';
  $('#leafCrumb').className = 'muted';
}

onChanged(o => {
  o = o || {};
  if (o.tree) renderTree();
  if (o.structural) {
    renderVisual(); renderPreviewBar(); renderRaw(); renderFileRaw();
  }
  renderPreview();
  updateTop();
  updateCrumb();
  scheduleValidate(S.nusach, S.sel.chunk);
});

const renderPreviewSoon = debounce(() => renderPreview(), 200);

// ---------- validation
const vTimers = {};
function scheduleValidate(n, ci, delay = 700) {
  const key = n + '|' + ci;
  clearTimeout(vTimers[key]);
  vTimers[key] = setTimeout(() => validateChunk(n, ci), delay);
}
async function validateChunk(n, ci) {
  const d = S.docs[n]; if (!d) return;
  const c = d.chunks[ci]; if (!c || !c.doc) return;
  c.validating = true;
  try {
    const r = await api('/api/validate', { nusach: n, file: c.file, doc: c.doc, book: d.book });
    c.problems = r.items;
    d.bookProblems = r.book;
  } catch (e) { /* server restarting; try later */ }
  c.validating = false;
  if (n === S.nusach) { if (ci === S.sel.chunk) { if ($('#leafProblems')) renderLeafProblems(); refreshSegBadges(); } renderTree(true); renderProblems(); updateTop(); }
}
function refreshSegBadges() { /* badges refresh on the next structural render */ }

function problemCount(d = D()) {
  let e = 0, w = 0;
  d.chunks.forEach(c => (c.problems || []).forEach(p => p.level === 'error' ? e++ : w++));
  (d.bookProblems || []).forEach(p => p.level === 'error' ? e++ : w++);
  return { e, w };
}

// ---------- top bar
function updateTop() {
  const d = D(); if (!d) return;
  let dirty = 0;
  Object.values(S.docs).forEach(x => { dirty += x.chunks.filter(c => c.dirty).length + (x.bookDirty ? 1 : 0); });
  $('#dirtyCount').textContent = dirty ? String(dirty) : '';
  const c = chunk();
  $('#btnSave').classList.toggle('primary', !!(c && c.dirty));
  $('#btnSave').textContent = c && c.dirty ? 'Save ●' : 'Save';
  $('#btnUndo').disabled = !(c && c.past.length);
  $('#btnRedo').disabled = !(c && c.future.length);
  const { e, w } = problemCount(d);
  $('#probCount').textContent = e + w ? (e ? e : '') + (w ? (e ? '/' : '') + w : '') : '';
  $('#probCount').style.color = e ? 'var(--err)' : 'var(--warn)';
  document.title = (dirty ? '● ' : '') + 'Amud Corpus Editor — ' + S.nusach;
}

function setStatus(msg, err) { const s = $('#status'); s.textContent = msg; s.className = err ? 'err' : ''; }

// ---------- saving
async function saveChunk(n, ci, force) {
  const d = S.docs[n], c = d.chunks[ci];
  if (!c.doc) return toast(`${c.file} isn't valid JSON — fix it in the Raw file tab`, true);
  try {
    const r = await api('/api/save', { nusach: n, file: c.file, doc: c.doc, mtime: c.mtime, force });
    c.mtime = r.mtime; c.dirty = false;
    return true;
  } catch (e) {
    if (e.status === 409 && !force) {
      if (confirm(`${c.file} was changed on disk since you loaded it.\n\nOverwrite it with your version?`)) return saveChunk(n, ci, true);
      return false;
    }
    toast('Save failed: ' + e.message, true);
    return false;
  }
}
async function saveBook(n, force) {
  const d = S.docs[n];
  try {
    const r = await api('/api/save_book', { nusach: n, book: d.book, mtime: d.bookMtime, force });
    d.bookMtime = r.mtime; d.bookDirty = false; return true;
  } catch (e) {
    if (e.status === 409 && !force && confirm('book.json changed on disk. Overwrite with your version?')) return saveBook(n, true);
    toast('Save failed: ' + e.message, true); return false;
  }
}
async function saveCurrent() {
  const c = chunk(); const d = D();
  let n = 0;
  if (c.dirty && await saveChunk(S.nusach, S.sel.chunk)) n++;
  if (d.bookDirty && await saveBook(S.nusach)) n++;
  if (n) toast('Saved ' + c.file); else if (!c.dirty && !d.bookDirty) toast('Nothing to save');
  afterSave();
}
async function saveAll() {
  let n = 0;
  for (const [name, d] of Object.entries(S.docs)) {
    for (let ci = 0; ci < d.chunks.length; ci++) if (d.chunks[ci].dirty && await saveChunk(name, ci)) n++;
    if (d.bookDirty && await saveBook(name)) n++;
  }
  toast(n ? `Saved ${n} file(s)` : 'Nothing to save');
  afterSave();
  return n;
}
function afterSave() {
  afterSaveSync();
  updateTop(); renderTree(true);
  const { e, w } = problemCount();
  setStatus(e ? `${e} problem(s) — the build will refuse these` : w ? `${w} warning(s)` : 'No problems', !!e);
}

// ---------- tree
function buildTree(d) {
  const root = { name: '', path: '', kids: new Map(), leaf: null, count: 0 };
  d.chunks.forEach((c, ci) => c.doc && c.doc.leaves.forEach((l, li) => {
    let n = root; const parts = (l.path || '').split('/'); let acc = '';
    n.count++;
    for (const p of parts) {
      acc = acc ? acc + '/' + p : p;
      if (!n.kids.has(p)) n.kids.set(p, { name: p, path: acc, kids: new Map(), leaf: null, count: 0 });
      n = n.kids.get(p); n.count++;
    }
    n.leaf = { ci, li, l };
  }));
  return root;
}

function leafState(ci, li) {
  const c = D().chunks[ci];
  const ps = (c.problems || []).filter(p => p.leaf === li);
  return ps.some(p => p.level === 'error') ? 'err' : ps.length ? 'warn' : '';
}

function renderTree(soft) {
  const pane = $('#paneTree');
  const d = D(); if (!d) return;
  const scroll = pane.querySelector('.treebox') ? pane.querySelector('.treebox').scrollTop : 0;
  if (!pane.querySelector('.tools') || !soft && false) {
    pane.innerHTML = '';
    const f = h('input', { type: 'text', placeholder: 'Filter leaves (path or Hebrew title)', value: treeFilter, oninput: e => { treeFilter = e.target.value; renderTree(true); } });
    pane.append(h('div', { class: 'tools' }, f,
      h('button', { id: 'btnMode', title: 'Group by path, or in file (book) order', onclick: () => { treeMode = treeMode === 'path' ? 'file' : 'path'; store.set('treeMode', treeMode); renderTree(true); } }),
      h('button', { text: '⊟', title: 'Collapse all', onclick: () => { openNodes[S.nusach].clear(); renderTree(true); } })),
      h('div', { class: 'treebox', style: 'overflow:auto;position:absolute;inset:40px 0 0 0' }));
    pane.style.position = 'relative';
  }
  $('#btnMode').textContent = treeMode === 'path' ? 'By path' : 'By file';
  const box = $('.treebox', pane);
  box.innerHTML = '';
  const q = treeFilter.trim().toLowerCase();
  const open = openNodes[S.nusach];
  const sec = d.book.sections || {};
  const match = l => !q || l.path.toLowerCase().includes(q) || (l.title || '').includes(treeFilter.trim());
  const row = (depth, label, he, o) => {
    const el = h('div', { class: 'node' + (o.sel ? ' sel' : ''), style: `padding-inline-start:${6 + depth * 14}px`, title: o.title || '', onclick: o.click },
      h('span', { class: 'tw', text: o.tw || '' }), h('span', { class: 'label', text: label }), he ? h('span', { class: 'he', text: he }) : null,
      h('span', { class: 'leafline' }, o.dirty ? h('span', { class: 'dot dirty', title: 'unsaved' }) : null, o.state ? h('span', { class: 'dot ' + o.state, title: o.state === 'err' ? 'has errors' : 'has warnings' }) : null),
      o.count != null ? h('span', { class: 'count', text: o.count }) : null);
    if (o.sel) el.setAttribute('data-sel', '1');
    box.append(el);
  };
  const leafRow = (depth, ci, li, l, label) => row(depth, label ?? l.path.split('/').pop(), l.title && l.title !== l.path.split('/').pop() ? l.title : '', {
    sel: ci === S.sel.chunk && li === S.sel.leaf, dirty: false, state: leafState(ci, li), title: l.path, click: () => selectLeaf(ci, li),
  });
  if (treeMode === 'path') {
    const walk = (n, depth) => {
      for (const k of n.kids.values()) {
        const hasKids = k.kids.size > 0;
        const visible = !q || [...allLeaves(k)].some(x => match(x.l));
        if (!visible) continue;
        const isOpen = open.has(k.path) || !!q;
        if (k.leaf && !hasKids) { if (match(k.leaf.l)) leafRow(depth, k.leaf.ci, k.leaf.li, k.leaf.l, k.name); continue; }
        row(depth, k.name, sec[k.path] || '', { tw: isOpen ? '▾' : '▸', count: k.count, title: k.path, click: () => { if (open.has(k.path)) open.delete(k.path); else open.add(k.path); renderTree(true); } });
        if (isOpen) { if (k.leaf && match(k.leaf.l)) leafRow(depth + 1, k.leaf.ci, k.leaf.li, k.leaf.l, '(this section’s text)'); walk(k, depth + 1); }
      }
    };
    walk(buildTree(d), 0);
  } else {
    d.chunks.forEach((c, ci) => {
      const key = 'file:' + c.file;
      const isOpen = open.has(key) || !!q;
      const hits = c.doc ? c.doc.leaves.map((l, li) => ({ l, li })).filter(x => match(x.l)) : [];
      if (q && !hits.length) return;
      row(0, c.file.replace(/\.json$/, ''), '', { tw: isOpen ? '▾' : '▸', count: c.doc ? c.doc.leaves.length : '!', dirty: c.dirty, state: !c.doc ? 'err' : '', title: c.doc ? c.doc.chunk : c.error, click: () => { if (open.has(key)) open.delete(key); else open.add(key); renderTree(true); } });
      if (isOpen) hits.forEach(x => leafRow(1, ci, x.li, x.l, x.l.path));
    });
  }
  box.scrollTop = scroll;
  const selEl = $('[data-sel]', box);
  if (selEl && !soft) selEl.scrollIntoView({ block: 'nearest' });
}
function* allLeaves(n) { if (n.leaf) yield n.leaf; for (const k of n.kids.values()) yield* allLeaves(k); }

function revealInTree() {
  const l = leaf(); if (!l) return;
  treeFilter = ''; const f = $('#paneTree input'); if (f) f.value = '';
  showLeftTab('tree');
  const parts = l.path.split('/'); let acc = '';
  parts.slice(0, -1).forEach(p => { acc = acc ? acc + '/' + p : p; openNodes[S.nusach].add(acc); });
  openNodes[S.nusach].add('file:' + chunk().file);
  renderTree();
  const el = $('#paneTree [data-sel]'); if (el) el.scrollIntoView({ block: 'center' });
}

// ---------- tabs
function showLeftTab(t) {
  $$('#leftTabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === t));
  ['tree', 'find', 'problems', 'agent', 'ref'].forEach(x => { $('#pane' + x[0].toUpperCase() + x.slice(1)).hidden = x !== t; });
  S.find.active = t === 'find';
  if (t === 'find') { renderPreview(); const q = $('#findQ'); if (q) { q.focus(); q.select(); } }
  else renderPreview();
  if (t === 'problems') renderProblems();
  if (t === 'agent') renderAgent();
}
function showCenterTab(t) {
  S.centerTab = t;
  $$('#centerTabs button').forEach(b => b.classList.toggle('on', b.dataset.tab === t));
  $('#visual').hidden = t !== 'visual'; $('#raw').hidden = t !== 'raw'; $('#file').hidden = t !== 'file'; $('#bookInfo').hidden = t !== 'book';
  if (t === 'raw') renderRaw();
  if (t === 'file') renderFileRaw();
  if (t === 'book') renderBookInfo();
}

// ---------- raw leaf
function jsonErrorPos(text, e) {
  const m = /position (\d+)/.exec(e.message);
  if (!m) return e.message;
  const pos = +m[1], before = text.slice(0, pos);
  return `${e.message.replace(/ in JSON at position \d+.*/, '')} (line ${before.split('\n').length}, column ${pos - before.lastIndexOf('\n')})`;
}
function rawEditor(getText, onApply, opts = {}) {
  const ta = h('textarea', { class: 'code', spellcheck: 'false', value: getText() });
  const msg = h('span', { class: 'hint' });
  const check = () => { try { JSON.parse(ta.value); msg.className = 'hint cond-ok'; msg.textContent = '✓ valid JSON'; ta.classList.remove('bad'); return true; } catch (e) { msg.className = 'hint cond-bad'; msg.textContent = jsonErrorPos(ta.value, e); ta.classList.add('bad'); return false; } };
  const apply = () => { if (!check()) return toast('Fix the JSON first', true); onApply(JSON.parse(ta.value), ta.value); };
  ta.addEventListener('input', check);
  ta.addEventListener('keydown', e => {
    if (e.key === 'Tab') { e.preventDefault(); ta.setRangeText('  ', ta.selectionStart, ta.selectionEnd, 'end'); check(); }
    if ((e.ctrlKey || e.metaKey) && e.key === 'Enter') { e.preventDefault(); apply(); }
  });
  const bar = h('div', { class: 'rawbar' },
    h('button', { class: 'primary', text: 'Apply  (Ctrl+Enter)', onclick: apply }),
    h('button', { text: 'Reset', onclick: () => { ta.value = getText(); check(); } }),
    h('button', { text: 'Pretty-print', onclick: () => { try { ta.value = JSON.stringify(JSON.parse(ta.value), null, 2); check(); } catch { check(); } } }),
    h('button', { text: 'Go to line…', onclick: () => { const n = parseInt(prompt('Line number'), 10); if (n > 0) { const lines = ta.value.split('\n'); const pos = lines.slice(0, n - 1).join('\n').length + (n > 1 ? 1 : 0); ta.focus(); ta.setSelectionRange(pos, pos + (lines[n - 1] || '').length); ta.scrollTop = (n - 5) * 19; } } }),
    msg, ...(opts.extra || []));
  check();
  return h('div', { class: 'rawwrap' }, bar, ta);
}

function renderRaw() {
  const box = $('#raw');
  if (box.hidden && S.centerTab !== 'raw') return;
  box.innerHTML = '';
  box.classList.add('fill');
  const l = leaf();
  if (!l) { box.append(h('div', { class: 'pv-empty', text: 'No leaf selected.' })); return; }
  box.append(rawEditor(() => JSON.stringify(l, null, 2), parsed => {
    if (!parsed || typeof parsed !== 'object' || Array.isArray(parsed)) return toast('A leaf is a JSON object', true);
    mutate(() => { const ls = chunk().doc.leaves; ls[S.sel.leaf] = parsed; }, { tree: true });
    toast('Leaf updated');
  }));
}

// ---------- raw file
let rawFileText = null;
async function renderFileRaw() {
  const box = $('#file');
  if (box.hidden && S.centerTab !== 'file') return;
  box.classList.add('fill');
  const c = chunk();
  box.innerHTML = '';
  let text;
  if (!c.doc) text = c.raw;
  else { try { text = (await api('/api/dumps', { doc: c.doc })).text; } catch { text = JSON.stringify(c.doc, null, 2); } }
  box.innerHTML = '';
  box.append(h('div', { class: 'hint', text: `${c.file} — the file as it will be saved (canonical layout). Applying replaces the whole file in the editor; save it to write to disk.` }),
    rawEditor(() => text, parsed => {
      snapshot(c, null);
      c.doc = parsed; c.error = null; c.dirty = true;
      S.sel.leaf = Math.min(S.sel.leaf, Math.max(0, (parsed.leaves || []).length - 1));
      changed({ structural: true, tree: true });
      toast('File updated (unsaved)');
    }));
}

// ---------- book info
function renderBookInfo() {
  const box = $('#bookInfo');
  if (box.hidden && S.centerTab !== 'book') return;
  box.innerHTML = '';
  const d = D(), b = d.book;
  const dirty = () => { d.bookDirty = true; updateTop(); scheduleValidate(S.nusach, S.sel.chunk); };
  const f = (key, label, he) => wrapField(label, h('input', { type: 'text', value: b[key] || '', dir: he ? 'rtl' : 'ltr', oninput: e => { b[key] = e.target.value; dirty(); } }), 'wide');
  box.append(h('div', { class: 'card' }, h('header', {}, h('b', { text: 'book.json' }), h('span', { class: 'hint', text: 'title is the book’s name in the app: don’t change it' })),
    h('div', { class: 'body' }, h('div', { class: 'row' }, f('title', 'title'), f('heTitle', 'heTitle', true)))));
  const paths = new Set(Object.keys(b.sections || {}));
  d.chunks.forEach(c => c.doc && c.doc.leaves.forEach(l => { const p = l.path.split('/'); for (let i = 1; i < p.length; i++) paths.add(p.slice(0, i).join('/')); }));
  const tbl = h('table', { class: 'sections' });
  [...paths].sort((x, y) => x.localeCompare(y)).forEach(p => {
    const inp = h('input', { type: 'text', dir: 'rtl', style: 'font-family:var(--hebrew);font-size:16px', value: (b.sections || {})[p] || '', oninput: e => { b.sections = b.sections || {}; if (e.target.value) b.sections[p] = e.target.value; else delete b.sections[p]; inp.classList.toggle('bad', !e.target.value); dirty(); } });
    inp.classList.toggle('bad', !(b.sections || {})[p]);
    tbl.append(h('tr', {}, h('td', { text: p, style: 'direction:ltr;white-space:nowrap' }), h('td', {}, inp)));
  });
  box.append(h('div', { class: 'card' }, h('header', {}, h('b', { text: 'Sections' }), h('span', { class: 'hint', text: 'Hebrew titles of every section path (red: missing)' })), h('div', { class: 'body' }, tbl)));
  const src = rawEditor(() => JSON.stringify(b.sources || {}, null, 2), parsed => { b.sources = parsed; dirty(); toast('Sources updated'); renderBookInfo(); renderVisual(); });
  src.style.height = '260px';
  box.append(h('div', { class: 'card' }, h('header', {}, h('b', { text: 'Sources' }), h('span', { class: 'hint', text: 'Every leaf’s version must be listed here, with its license' })), h('div', { class: 'body' }, src)));
  if (d.bookProblems && d.bookProblems.length) box.prepend(h('div', { class: 'card' }, h('div', { class: 'body' }, d.bookProblems.map(p => h('div', { class: 'prob ' + p.level }, h('span', { class: 'lvl', text: p.level === 'error' ? '✕' : '!' }), h('span', { text: p.msg }))))));
}

// ---------- problems
function renderProblems() {
  const box = $('#paneProblems');
  if (box.hidden) return;
  const d = D();
  box.innerHTML = '';
  box.append(h('div', { class: 'tools' }, h('button', { text: 'Re-check everything', onclick: async () => { for (let ci = 0; ci < d.chunks.length; ci++) await validateChunk(S.nusach, ci); toast('Checked'); } }),
    h('span', { class: 'hint', text: 'Errors stop the build; warnings (e.g. unbalanced HTML from Sefaria) don’t.' })));
  let any = false;
  (d.bookProblems || []).forEach(p => { any = true; box.append(h('div', { class: 'prob ' + p.level, onclick: () => showCenterTab('book') }, h('span', { class: 'lvl', text: p.level === 'error' ? '✕' : '!' }), h('span', { text: p.msg }))); });
  d.chunks.forEach((c, ci) => (c.problems || []).forEach(p => {
    any = true;
    const l = p.leaf >= 0 && c.doc ? c.doc.leaves[p.leaf] : null;
    box.append(h('div', { class: 'prob ' + p.level, onclick: () => { if (l) { selectLeaf(ci, p.leaf); jumpProblem(p); } } },
      h('span', { class: 'lvl', text: p.level === 'error' ? '✕' : '!' }), h('div', {}, h('div', { text: p.msg }), h('div', { class: 'hint', text: c.file + (l ? ' · ' + l.path : '') }))));
  }));
  if (!any) box.append(h('div', { class: 'pv-empty', text: '✓ No problems in ' + S.nusach }));
}

// ---------- reference
let lastRef = null;
document.addEventListener('focusin', e => { if (e.target.matches && e.target.matches('input[data-ref], textarea[data-ref]')) lastRef = e.target; });
function insertInto(kind, text) {
  const el = lastRef && document.contains(lastRef) && lastRef.dataset.ref === kind ? lastRef : null;
  if (!el) { navigator.clipboard && navigator.clipboard.writeText(text); return toast(`Copied ${text} (focus a ${kind} field first to insert)`); }
  const s = el.selectionStart, e = el.selectionEnd;
  if (kind === 'node') { el.value = text; } else el.setRangeText(text, s, e, 'end');
  el.dispatchEvent(new Event('input', { bubbles: true }));
  el.focus();
}
function renderRef() {
  const box = $('#paneRef');
  box.innerHTML = '';
  const q = h('input', { type: 'text', placeholder: 'Filter variables, nodes, labels…' });
  box.append(h('div', { class: 'tools' }, q));
  const list = h('div');
  box.append(list);
  const draw = () => {
    const f = q.value.toLowerCase(); list.innerHTML = '';
    const sect = (title, entries, kind, extra) => {
      const rows = entries.filter(([k, d]) => !f || k.toLowerCase().includes(f) || (d || '').toLowerCase().includes(f));
      if (!rows.length && !extra) return;
      list.append(h('div', { class: 'refhead', text: `${title} (${rows.length})` }));
      if (extra) list.append(extra);
      rows.forEach(([k, d, cls]) => list.append(h('div', { class: 'refrow ' + (cls || ''), title: 'Click to insert into the focused ' + kind + ' field', onclick: () => insertInto(kind, k) }, h('code', { text: k }), h('span', { text: d || '' }))));
    };
    sect('Conditions: variables', Object.entries(S.meta.variables).map(([k, v]) => [k, v.doc + (v.proposed ? ' (proposed: not computed by the engine yet)' : ''), v.proposed ? 'proposed' : '']), 'when');
    const add = h('div', { class: 'tools' }, h('button', { text: '+ New personal circumstance (if_…)', onclick: async () => {
      let key = prompt('Key, like if_atBrit'); if (!key) return;
      if (!key.startsWith('if_')) key = 'if_' + key;
      const label = prompt('Label shown to the reader, like "At a brit milah"'); if (!label) return;
      try { const r = await api('/api/label', { key, label }); S.meta.labels = r.labels; toast('Added ' + key); draw(); } catch (e) { toast(e.message, true); }
    } }));
    sect('Conditions: personal circumstances', Object.entries(S.meta.labels), 'when', add);
    sect('Graph nodes', Object.entries(S.meta.nodes).map(([k, v]) => [k, `${v.en} · ${v.he}`]), 'node');
  };
  q.addEventListener('input', draw);
  draw();
}

// ---------- go to
function openGoto() {
  const input = h('input', { type: 'text', placeholder: 'Go to leaf: path or Hebrew title…' });
  const list = h('div', { class: 'list' });
  const wrap = h('div', { class: 'goto' }, input, list);
  let items = [], idx = 0;
  const flat = flatLeaves();
  const draw = () => {
    const toks = input.value.toLowerCase().split(/\s+/).filter(Boolean);
    items = flat.filter(x => { const hay = (x.l.path + ' ' + (x.l.title || '')).toLowerCase(); return toks.every(t => hay.includes(t)); }).slice(0, 80);
    idx = Math.min(idx, Math.max(0, items.length - 1));
    list.innerHTML = '';
    items.forEach((x, i) => list.append(h('div', { class: 'it' + (i === idx ? ' on' : ''), onclick: () => go(x) }, h('span', { text: x.l.path }), h('span', { class: 'he muted', text: x.l.title || '' }))));
  };
  const go = x => { close(); selectLeaf(x.ci, x.li); revealInTree(); };
  input.addEventListener('input', () => { idx = 0; draw(); });
  input.addEventListener('keydown', e => {
    if (e.key === 'ArrowDown') { idx = Math.min(items.length - 1, idx + 1); draw(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { idx = Math.max(0, idx - 1); draw(); e.preventDefault(); }
    else if (e.key === 'Enter' && items[idx]) go(items[idx]);
  });
  const close = modal('Go to leaf', wrap, { cls: 'goto' });
  draw(); input.focus();
}

// ---------- build, diff, help
function showOutput(title, text, ok) {
  const pre = h('pre', {});
  text.split('\n').forEach(line => pre.append(h('div', { class: /error|problem\(s\)|FAILED|Traceback/i.test(line) && !/ 0 problem/.test(line) ? 'cond-bad' : '', text: line })));
  modal(title + (ok === false ? ' — failed' : ok ? ' — ok' : ''), pre);
}
async function runCmd(cmd, label) {
  if (Object.values(S.docs).some(d => d.chunks.some(c => c.dirty) || d.bookDirty)) {
    if (!confirm('Save all changes first? (The command runs on the files on disk.)')) return;
    await saveAll();
  }
  setStatus(`Running ${label}…`);
  try {
    const r = await api('/api/run', { cmd });
    setStatus(r.ok ? `${label}: ok` : `${label}: failed`, !r.ok);
    showOutput(label, r.output || '(no output)', r.ok);
  } catch (e) { setStatus(label + ' failed', true); toast(e.message, true); }
}
async function showDiff() {
  const c = chunk();
  if (c.dirty) toast('Showing the saved file; save to include your latest edits');
  try {
    const r = await api(`/api/diff?nusach=${S.nusach}&file=${encodeURIComponent(c.file)}`);
    const pre = h('pre', {});
    r.diff.split('\n').forEach(line => pre.append(h('div', { class: line.startsWith('+') ? 'diffadd' : line.startsWith('-') ? 'diffdel' : line.startsWith('@@') ? 'diffhunk' : '', text: line.slice(0, 400) })));
    modal('git diff — ' + c.file, pre);
  } catch (e) { toast(e.message, true); }
}
function showHelp() {
  const rows = [['Ctrl+S', 'Save this file'], ['Ctrl+Shift+S', 'Save every changed file'], ['Ctrl+Z / Ctrl+Shift+Z', 'Undo / redo (per file; outside text fields)'], ['Ctrl+Shift+F', 'Find and replace'],
    ['Enter / Shift+Enter', 'Next / previous match (in the find box)'], ['F3 / Shift+F3', 'Next / previous match'], ['Ctrl+P', 'Go to leaf'], ['Alt+↑ / Alt+↓', 'Previous / next leaf'], ['Ctrl+\\', 'Show / hide the preview'],
    ['Ctrl+B / Ctrl+I', 'Bold / italic the selection in a text box'], ['Ctrl+Enter', 'Apply the raw editor']];
  modal('Shortcuts', h('table', {}, rows.map(([k, v]) => h('tr', {}, h('td', {}, h('kbd', { text: k })), h('td', { style: 'padding-left:14px', text: v })))));
}

// ---------- external changes
let driftShown = '';
async function pollDisk() {
  if (!S.nusach || document.hidden) return;
  try {
    const m = await api('/api/mtimes?nusach=' + S.nusach);
    const d = D();
    const changedFiles = d.chunks.filter(c => m[c.file] != null && m[c.file] !== c.mtime);
    const bookChanged = m['book.json'] !== d.bookMtime;
    if (!changedFiles.length && !bookChanged) { $('#banner').hidden = true; driftShown = ''; return; }
    // Unedited files are simply reloaded; edited ones ask.
    const clean = changedFiles.filter(c => !c.dirty), edited = changedFiles.filter(c => c.dirty);
    if (clean.length || (bookChanged && !d.bookDirty)) {
      const fresh = await api('/api/siddur?nusach=' + S.nusach);
      clean.forEach(c => { const f = fresh.chunks.find(x => x.file === c.file); if (f) { c.doc = f.doc; c.mtime = f.mtime; c.error = f.error; c.raw = f.raw; c.past = []; c.future = []; scheduleValidate(S.nusach, d.chunks.indexOf(c), 50); } });
      if (bookChanged && !d.bookDirty) { d.book = fresh.book; d.bookMtime = fresh.bookMtime; }
      const cur = chunk();
      if (S.sel.leaf >= (cur.doc ? cur.doc.leaves.length : 0)) S.sel.leaf = Math.max(0, (cur.doc ? cur.doc.leaves.length : 1) - 1);
      renderAll();
      toast(`Reloaded from disk: ${clean.map(c => c.file).join(', ') || 'book.json'}`);
      afterSaveSync();
    }
    if (edited.length || (bookChanged && d.bookDirty)) {
      const names = edited.map(c => c.file).join(', ') || 'book.json';
      if (driftShown !== names) {
        driftShown = names;
        const b = $('#banner'); b.hidden = false; b.innerHTML = '';
        b.append(h('span', { text: `Changed on disk while you have unsaved edits: ${names}.` }),
          h('button', { text: 'Reload from disk (discard mine)', onclick: async () => { const fresh = await api('/api/siddur?nusach=' + S.nusach); edited.forEach(c => { const f = fresh.chunks.find(x => x.file === c.file); Object.assign(c, { doc: f.doc, mtime: f.mtime, dirty: false, past: [], future: [] }); }); if (bookChanged) { d.book = fresh.book; d.bookMtime = fresh.bookMtime; d.bookDirty = false; } b.hidden = true; driftShown = ''; renderAll(); } }),
          h('button', { text: 'Keep mine (saving will ask)', onclick: () => { b.hidden = true; } }));
      }
    }
  } catch { /* server stopped */ }
}

// ---------- layout
function wireGutters() {
  const drag = (g, el, side) => g.addEventListener('mousedown', e => {
    e.preventDefault(); g.classList.add('drag');
    const x0 = e.clientX, w0 = el.getBoundingClientRect().width;
    const mv = ev => { const w = side === 'l' ? w0 + ev.clientX - x0 : w0 - (ev.clientX - x0); el.style.width = Math.max(180, Math.min(innerWidth - 400, w)) + 'px'; };
    const up = () => { g.classList.remove('drag'); document.removeEventListener('mousemove', mv); document.removeEventListener('mouseup', up); store.set('w' + side, el.style.width); };
    document.addEventListener('mousemove', mv); document.addEventListener('mouseup', up);
  });
  drag($('#gutterL'), $('#left'), 'l'); drag($('#gutterR'), $('#right'), 'r');
  const wl = store.get('wl'), wr = store.get('wr');
  if (wl) $('#left').style.width = wl; if (wr) $('#right').style.width = wr;
}
function applyTheme(t) {
  if (t) document.documentElement.setAttribute('data-theme', t); else document.documentElement.removeAttribute('data-theme');
}
function togglePreview() { document.body.classList.toggle('nopreview'); store.set('nopreview', document.body.classList.contains('nopreview')); }

// ---------- init
function isTextTarget(t) { return t && (t.tagName === 'TEXTAREA' || (t.tagName === 'INPUT' && !['checkbox', 'range', 'button'].includes(t.type))); }

async function init() {
  S.meta = await api('/api/meta');
  Object.assign(S.pv, store.get('pv', {}));
  S.ctx = store.get('ctx', clone(PRESETS['Ordinary weekday (Shacharit)']));
  initFind();
  applyPvStyle();
  applyTheme(store.get('theme', null));
  if (store.get('nopreview', false)) document.body.classList.add('nopreview');
  const sel = $('#nusach');
  S.meta.nusachim.forEach(n => sel.append(h('option', { value: n, text: n })));
  sel.addEventListener('change', () => selectNusach(sel.value));
  $$('#leftTabs button').forEach(b => b.addEventListener('click', () => showLeftTab(b.dataset.tab)));
  $$('#centerTabs button').forEach(b => b.addEventListener('click', () => showCenterTab(b.dataset.tab)));
  $('#btnUndo').onclick = () => undo(false); $('#btnRedo').onclick = () => undo(true);
  $('#btnSave').onclick = saveCurrent; $('#btnSaveAll').onclick = saveAll; $('#btnDiff').onclick = showDiff;
  $('#btnFind').onclick = () => { showLeftTab('find'); };
  $('#btnGoto').onclick = openGoto; $('#btnHelp').onclick = showHelp; $('#btnPreview').onclick = togglePreview;
  $('#btnTheme').onclick = () => { const cur = store.get('theme', null); const next = cur === null ? 'light' : cur === 'light' ? 'dark' : null; store.set('theme', next); applyTheme(next); toast('Theme: ' + (next || 'system')); };
  $('#btnRun').onclick = e => menu(e.target, [
    ['Format files (fmt.py)', () => runCmd('fmt', 'fmt')], ['Validate every siddur', () => runCmd('validate', 'validate')],
    ['Build app assets (build_assets.py)', () => runCmd('build', 'build assets')], ['Engine tests (flutter test)', () => runCmd('test', 'engine tests')]]);
  wireGutters();
  $$('#rightTabs button').forEach(b => b.addEventListener('click', () => showRightTab(b.dataset.tab)));
  renderFindPane(); renderRef();

  const last = store.get('last', null);
  const first = last && S.meta.nusachim.includes(last.n) ? last.n : S.meta.nusachim[0];
  setStatus('Loading ' + first + '…');
  await loadSiddur(first);
  S.nusach = first; sel.value = first;
  if (last && last.path) { const hit = flatLeaves().find(x => x.l.path === last.path); if (hit) S.sel = { chunk: hit.ci, leaf: hit.li }; }
  const hit0 = leaf();
  if (!hit0) { const f = flatLeaves()[0]; if (f) S.sel = { chunk: f.ci, leaf: f.li }; }
  renderAll();
  revealInTree();
  setStatus('');
  pollAgent();
  api('/api/app').then(s => { APPV.status = s; updateAppDot(); if (store.get('rightTab', 'preview') === 'app') showRightTab('app'); }).catch(() => {});
  setInterval(pollDisk, 4000);
  window.addEventListener('beforeunload', e => { if (Object.values(S.docs).some(d => d.chunks.some(c => c.dirty) || d.bookDirty)) { e.preventDefault(); e.returnValue = ''; } });
  window.addEventListener('keydown', e => {
    const mod = e.ctrlKey || e.metaKey;
    const k = e.key.toLowerCase();
    if (mod && k === 's') { e.preventDefault(); e.shiftKey ? saveAll() : saveCurrent(); }
    else if (mod && e.shiftKey && k === 'f') { e.preventDefault(); const sel = String(window.getSelection()).trim(); if (sel && !sel.includes('\n')) { S.find.query = sel; } showLeftTab('find'); renderFindPane(); showLeftTab('find'); runFind(); }
    else if (mod && k === 'p') { e.preventDefault(); openGoto(); }
    else if (mod && e.key === '\\') { e.preventDefault(); togglePreview(); }
    else if (mod && (k === 'z' || k === 'y') && !isTextTarget(e.target)) { e.preventDefault(); undo(k === 'y' || e.shiftKey); }
    else if (e.altKey && e.key === 'ArrowUp') { e.preventDefault(); stepLeaf(-1); }
    else if (e.altKey && e.key === 'ArrowDown') { e.preventDefault(); stepLeaf(1); }
    else if (e.key === 'F3') { e.preventDefault(); findStep(e.shiftKey ? -1 : 1); }
  });
  window.__ready = true;
}

init().catch(e => { document.body.prepend(h('pre', { style: 'color:red;padding:20px', text: 'Failed to start: ' + (e && e.stack || e) })); window.__error = String(e && e.stack || e); });
