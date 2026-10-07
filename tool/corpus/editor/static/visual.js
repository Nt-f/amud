'use strict';
// The visual editor for one leaf: metadata, Hebrew and English segments,
// their parts and every tag, with formatting tools.

const uids = new WeakMap();
let UID = 0;
const uid = o => uids.get(o) || (uids.set(o, ++UID), UID);
const collapsed = new WeakSet();

function mutate(fn, o = {}) {
  const c = chunk();
  snapshot(c, null);
  fn();
  c.dirty = true;
  changed({ structural: true, tree: o.tree });
}
function touched() {
  chunk().dirty = true;
  updateTop();
  renderPreviewSoon();
  scheduleValidate(S.nusach, S.sel.chunk);
}
function setField(obj, key, val, always) {
  snapshot(chunk(), 'f:' + key + ':' + uid(obj));
  if (!always && (val === '' || val == null || val === false || (Array.isArray(val) && !val.length))) delete obj[key];
  else obj[key] = val;
  touched();
}

// ---- field builders
function wrapField(label, el, cls) { return h('div', { class: 'field ' + (cls || '') }, label ? h('label', { text: label }) : null, el); }

function fText(obj, key, o = {}) {
  const inp = h(o.area ? 'textarea' : 'input', { type: 'text', value: obj[key] ?? '', placeholder: o.placeholder || '', spellcheck: 'false', rows: o.area ? 2 : null, 'data-ref': o.ref || key, 'data-leaf-field': o.leafField });
  if (o.he) { inp.dir = 'rtl'; inp.style.fontFamily = 'var(--hebrew)'; inp.style.fontSize = '16px'; }
  const check = () => { if (o.check) { const m = o.check(inp.value); inp.classList.toggle('bad', !!m); inp.title = m || ''; if (o.hint) o.hint(inp.value, m); } };
  inp.addEventListener('input', () => { setField(obj, key, inp.value, o.always); check(); if (o.after) o.after(inp.value); });
  if (o.complete) attachComplete(inp, o.complete, o.completeMode);
  check();
  return wrapField(o.label, inp, o.cls);
}

function fSelect(obj, key, options, o = {}) {
  const sel = h('select', { 'data-ref': key }, h('option', { value: '', text: o.empty ?? '—' }), options.map(v => h('option', { value: v, text: v, selected: obj[key] === v })));
  sel.addEventListener('change', () => { setField(obj, key, sel.value); if (o.after) o.after(sel.value); });
  return wrapField(o.label, sel, o.cls);
}

function fBool(obj, key, label) {
  const cb = h('input', { type: 'checkbox', checked: obj[key] === true });
  cb.addEventListener('change', () => setField(obj, key, cb.checked ? true : false));
  return h('label', { class: 'opt', style: 'align-self:center;display:flex;gap:3px;align-items:center' }, cb, label);
}

function fRepeat(obj) {
  const inp = h('input', { type: 'number', min: 2, style: 'width:60px', value: obj.repeat ?? '' });
  inp.addEventListener('input', () => { const n = parseInt(inp.value, 10); setField(obj, 'repeat', n >= 2 ? n : undefined); inp.classList.toggle('bad', inp.value !== '' && !(n >= 2)); });
  return wrapField('repeat ×', inp);
}

function fGestures(obj) {
  const wrap = h('div', { class: 'chips' });
  S.meta.enums.gestures.forEach(g => {
    const chip = h('span', { class: 'chip' + ((obj.gestures || []).includes(g) ? ' on' : ''), text: g });
    chip.addEventListener('click', () => {
      const cur = obj.gestures || [];
      const next = cur.includes(g) ? cur.filter(x => x !== g) : [...cur, g];
      setField(obj, 'gestures', next);
      chip.classList.toggle('on');
      const sm = chip.closest('details').querySelector('summary');
      sm.textContent = 'gestures' + (next.length ? ` (${next.length})` : '');
    });
    wrap.append(chip);
  });
  const n = (obj.gestures || []).length;
  return h('details', { class: 'more', open: n > 0 }, h('summary', { text: 'gestures' + (n ? ` (${n})` : '') }), wrap);
}

function condCheck(expr) {
  if (!expr.trim()) return null;
  const e = condError(expr);
  if (e) return e;
  const unknown = condIds(expr).filter(i => !(i in S.meta.variables) && !(i in S.meta.labels));
  if (unknown.length) return 'unknown: ' + unknown.join(', ') + (unknown.some(u => u.startsWith('if_')) ? ' (add the label in Reference)' : '');
  return null;
}
function fWhen(obj, label = 'when (condition)') {
  const hint = h('span', { class: 'hint' });
  const show = (v, err) => {
    if (!v.trim()) { hint.textContent = ''; return; }
    if (err) { hint.className = 'hint cond-bad'; hint.textContent = err; return; }
    const r = evalCond(v);
    hint.className = 'hint ' + (r ? 'cond-ok' : 'cond-bad');
    hint.textContent = r ? '✓ shown on the simulated day' : '✗ hidden on the simulated day';
  };
  const f = fText(obj, 'when', {
    label, cls: 'wide', placeholder: 'e.g. roshChodesh || cholHamoed', check: condCheck, hint: show, after: () => renderPreviewSoon(),
    complete: () => [...Object.entries(S.meta.variables).map(([k, v]) => [k, v.doc]), ...Object.entries(S.meta.labels)],
  });
  f.append(hint);
  show(obj.when || '', condCheck(obj.when || ''));
  return f;
}
function fNode(obj, label = 'node', required) {
  return fText(obj, 'node', {
    label, placeholder: required ? 'required' : 'leaf default', complete: () => Object.entries(S.meta.nodes).map(([k, v]) => [k, v.en]),
    check: v => (v || required) && !(v in S.meta.nodes) && !v.startsWith('x.') ? 'unknown node (nodes.json, or x.…)' : null,
  });
}

// ---- alignment: how the reader sets this line (the part's `align`)
const ALIGNS = [['', 'auto', 'Let the reader decide (by what the line is)'], ['start', '⇤ start', 'Flush to the start (right for Hebrew)'], ['center', '↔ center', 'Centered'],
  ['end', '⇥ end', 'Flush to the end (left for Hebrew)'], ['justify', '☰ justify', 'Justified']];
function alignBar(p) {
  const wrap = h('span', { class: 'alignbar', style: 'display:inline-flex;gap:0;margin-inline-start:auto' });
  const draw = () => $$('button', wrap).forEach((b, i) => b.classList.toggle('on', (p.align || '') === ALIGNS[i][0]));
  ALIGNS.forEach(([v, label, title]) => wrap.append(h('button', { text: label, title, onclick: () => { setField(p, 'align', v); draw(); renderPreviewSoon(); } })));
  draw();
  return wrap;
}

// ---- text editor with HTML tools
function textEditor(p, lang, holder) {
  const ta = h('textarea', { class: 'text' + (lang === 'he' ? ' he' : ''), dir: lang === 'he' ? 'rtl' : 'ltr', spellcheck: 'false', value: p.text ?? '', 'data-ref': 'text' });
  ta.rows = Math.max(2, Math.min(10, Math.ceil((p.text || '').length / (lang === 'he' ? 60 : 90))));
  const mini = h('div', { class: 'pvmini ' + (lang === 'he' ? 'he' : 'en'), dir: lang === 'he' ? 'rtl' : 'ltr' });
  const draw = () => { mini.innerHTML = sanitize(ta.value); const w = unbalanced(ta.value); mini.title = w ? 'unbalanced ' + w : ''; mini.style.outline = w ? '1px solid var(--warn)' : ''; };
  ta.addEventListener('input', () => { setField(p, 'text', ta.value, true); draw(); });
  holder.ta = ta;
  const edit = fn => { const s = ta.selectionStart, e = ta.selectionEnd; fn(s, e); ta.dispatchEvent(new Event('input', { bubbles: true })); ta.focus(); };
  const wrapSel = tag => edit((s, e) => { const sel = ta.value.slice(s, e); ta.setRangeText(`<${tag}>${sel}</${tag}>`, s, e, 'select'); });
  const btn = (label, title, fn) => h('button', { text: label, title, onclick: fn });
  ta.addEventListener('keydown', e => {
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && e.key === 'b') { e.preventDefault(); wrapSel('b'); }
    if ((e.ctrlKey || e.metaKey) && !e.shiftKey && !e.altKey && e.key === 'i') { e.preventDefault(); wrapSel('i'); }
  });
  const bar = h('div', { class: 'fmtbar' },
    btn('B', 'Bold: opening words (Ctrl+B)', () => wrapSel('b')), btn('small', 'Rubric', () => wrapSel('small')), btn('i', 'Italic (Ctrl+I)', () => wrapSel('i')),
    btn('sup', 'Footnote marker', () => wrapSel('sup')), btn('⏎ br', 'Line break', () => edit((s, e) => ta.setRangeText('<br>', s, e, 'end'))),
    btn('no tags', 'Remove tags in the selection (or everywhere)', () => edit((s, e) => { const all = s === e; const a = all ? 0 : s, b = all ? ta.value.length : e; ta.setRangeText(ta.value.slice(a, b).replace(/<[^>]*>/g, ''), a, b, 'end'); })),
    btn('no niqqud', 'Remove vowels and cantillation in the selection (or everywhere)', () => edit((s, e) => { const all = s === e; const a = all ? 0 : s, b = all ? ta.value.length : e; ta.setRangeText(stripHebrewMarks(ta.value.slice(a, b)), a, b, 'end'); })),
    btn('tidy ␣', 'Collapse runs of whitespace', () => edit(() => { ta.value = ta.value.replace(/[ \t\r\n]+/g, ' '); })),
    btn('fix ",', 'Straighten quotes: ” “ → "', () => edit(() => { ta.value = ta.value.replace(/[“”״]/g, '"').replace(/[‘’]/g, "'"); })));
  bar.append(alignBar(p));
  draw();
  return h('div', { class: 'texted' }, bar, ta, mini);
}
function unbalanced(html) {
  const st = []; const re = /<(\/?)([a-zA-Z][a-zA-Z0-9]*)[^>]*?(\/?)>/g; let m;
  while ((m = re.exec(html))) {
    const t = m[2].toLowerCase();
    if (['br', 'img', 'hr', 'wbr'].includes(t) || m[3]) continue;
    if (!m[1]) st.push(t); else if (st[st.length - 1] !== t) return `</${t}>`; else st.pop();
  }
  return st.length ? `<${st[st.length - 1]}>` : null;
}

// ---- parts
function partFields(p, lang, holder) {
  const E = S.meta.enums;
  const box = h('div');
  const heLang = lang === 'he';
  box.append(h('div', { class: 'row' },
    fSelect(p, 'kind', E.kinds, { label: heLang ? 'kind' : 'kind (optional)', empty: heLang ? '(missing)' : '—', after: v => { const b = box.closest('.part, .seg') && box.closest('.part, .seg').querySelector('[data-kindbadge]'); if (b) { b.textContent = v || ''; b.className = 'badge kind-' + v; } } }),
    fWhen(p),
    fSelect(p, 'role', E.roles, { label: 'role' }), fSelect(p, 'voice', E.voices, { label: 'voice' }), fSelect(p, 'amidah', E.amidah, { label: 'amidah' })));
  box.append(h('div', { class: 'row' },
    fBool(p, 'minyan', 'minyan'), fBool(p, 'forgot', 'if forgot'), fRepeat(p),
    fText(p, 'alt', { label: 'alt group', placeholder: 'id' }), fNode(p, 'node (override)')));
  box.append(fGestures(p));
  box.append(h('div', { class: 'row' }, fText(p, heLang ? 'en' : 'he', { label: heLang ? 'en — English shown for instructions, notes, headings, speakers' : 'he — Hebrew for an English-only instruction', cls: 'wide', area: true, he: !heLang })));
  const hasMore = ['gloss', 'cite', 'comment', 'clean', heLang ? 'he' : 'en'].some(k => p[k]);
  box.append(h('details', { class: 'more', open: hasMore }, h('summary', { text: 'gloss, cite, comment…' }),
    h('div', { class: 'row' }, fText(p, 'gloss', { label: 'gloss (one line why/when)', cls: 'wide' }), fText(p, 'cite', { label: 'cite (source)', he: true, cls: 'wide' })),
    h('div', { class: 'row' }, fText(p, 'comment', { label: 'comment (editors only, never shipped)', cls: 'wide', area: true }),
      fText(p, 'clean', { label: 'clean (tidied HTML, unused)', cls: 'wide', area: true })),
    heLang ? h('div', { class: 'row' }, fText(p, 'he', { label: 'he (rare on Hebrew parts)', cls: 'wide' })) : h('div', { class: 'row' }, fText(p, 'en', { label: 'en', cls: 'wide' }))));
  box.append(textEditor(p, lang, holder));
  return box;
}

function partCard(l, lang, seg, pi) {
  const p = seg.parts[pi];
  const holder = {};
  const head = h('div', { class: 'phead' },
    h('b', { text: `Part ${pi + 1}` }), h('span', { class: 'badge kind-' + (p.kind || ''), 'data-kindbadge': '', text: p.kind || '' }),
    h('span', { class: 'grow' }),
    h('button', { class: 'ghost', text: '↑', title: 'Move up', disabled: pi === 0, onclick: () => mutate(() => { seg.parts.splice(pi - 1, 0, seg.parts.splice(pi, 1)[0]); }) }),
    h('button', { class: 'ghost', text: '↓', title: 'Move down', disabled: pi === seg.parts.length - 1, onclick: () => mutate(() => { seg.parts.splice(pi + 1, 0, seg.parts.splice(pi, 1)[0]); }) }),
    h('button', { class: 'ghost', text: '⧉', title: 'Duplicate', onclick: () => mutate(() => { seg.parts.splice(pi + 1, 0, clone(p)); }) }),
    h('button', { class: 'ghost', text: '✂ split', title: 'Split this part at the text cursor', onclick: () => splitPart(seg, pi, holder.ta.selectionStart) }),
    h('button', { class: 'ghost', text: '⇥ merge', title: 'Merge with the next part (joins the text)', disabled: pi === seg.parts.length - 1, onclick: () => mutate(() => { const n = seg.parts.splice(pi + 1, 1)[0]; p.text = (p.text || '') + (n.text || ''); }) }),
    h('button', { class: 'ghost danger', text: '✕', title: 'Delete part', disabled: seg.parts.length === 1, onclick: () => mutate(() => { seg.parts.splice(pi, 1); }) }));
  return h('div', { class: 'part', 'data-pi': pi }, head, partFields(p, lang, holder));
}

function splitPart(seg, pi, pos) {
  mutate(() => {
    if (!seg.parts) {
      const { ref, translates, ...rest } = seg;
      for (const k of Object.keys(seg)) delete seg[k];
      seg.ref = ref; if (translates) seg.translates = translates; seg.parts = [rest]; pi = 0;
    }
    const p = seg.parts[pi];
    const t = p.text || '';
    const a = clone(p), b = clone(p);
    a.text = t.slice(0, pos); b.text = t.slice(pos);
    seg.parts.splice(pi, 1, a, b);
  });
}

function toParts(seg) {
  mutate(() => {
    const { ref, translates, ...rest } = seg;
    for (const k of Object.keys(seg)) delete seg[k];
    seg.ref = ref; if (translates) seg.translates = translates; seg.parts = [rest];
  });
}
function fromParts(seg) {
  mutate(() => { const p = seg.parts[0]; delete seg.parts; Object.assign(seg, p); });
}

// ---- segments
function nextRef(segs) {
  const used = new Set(segs.map(s => s.ref));
  const nums = segs.map(s => parseInt(s.ref, 10)).filter(n => !isNaN(n));
  let n = (nums.length ? Math.max(...nums) : 0) + 1;
  while (used.has(String(n))) n++;
  return String(n);
}
function newSeg(lang, segs, kind) {
  const s = { ref: nextRef(segs) };
  if (lang === 'he') { s.kind = kind || 'prayer'; s.text = ''; if (kind && kind !== 'prayer') s.en = ''; if (!s.en) delete s.en; }
  else { s.translates = []; s.text = ''; }
  return s;
}
function addSeg(l, lang, index, kind) {
  mutate(() => {
    if (!l[lang]) l[lang] = { version: firstVersion(lang), segs: [] };
    const segs = l[lang].segs;
    const s = newSeg(lang, segs, kind);
    if (lang === 'en' && index > 0) { /* translate the Hebrew seg that the previous English one did, next */ }
    segs.splice(index, 0, s);
    S.pendingFocus = { lang, si: index };
  });
}
function firstVersion(lang) {
  const here = (leaf() || {})[lang];
  if (here && here.version) return here.version;
  return Object.keys((D().book.sources || {})[lang] || {})[0] || 'Amud';
}
function delSeg(l, lang, si) {
  const s = l[lang].segs[si];
  if (!confirm(`Delete segment ${lang}:${s.ref}?`)) return;
  mutate(() => {
    l[lang].segs.splice(si, 1);
    if (lang === 'he') for (const e of ((l.en || {}).segs || [])) if (e.translates) e.translates = e.translates.filter(r => r !== s.ref);
  });
}
function renameRef(l, lang, seg, oldRef, newRef) {
  if (lang === 'he') for (const e of ((l.en || {}).segs || [])) if (e.translates) e.translates = e.translates.map(r => r === oldRef ? newRef : r);
}

function segProblems(lang, ref) {
  const c = chunk();
  return (c.problems || []).filter(p => p.leaf === S.sel.leaf && new RegExp(`(^| )${lang}:${ref.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}( |:)`).test(p.msg));
}

function segCard(l, lang, seg, si) {
  const segs = l[lang].segs;
  const isOpen = !collapsed.has(seg);
  const refInp = h('input', { type: 'text', value: seg.ref, style: 'width:56px', title: 'ref: unique within this leaf and language', spellcheck: 'false' });
  let oldRef = seg.ref;
  refInp.addEventListener('input', () => {
    const v = refInp.value, dup = segs.some(s => s !== seg && s.ref === v);
    refInp.classList.toggle('bad', dup || !v);
    if (!v) return;
    snapshot(chunk(), 'ref:' + uid(seg));
    renameRef(l, lang, seg, oldRef, v); oldRef = v; seg.ref = v; touched();
  });
  const probs = segProblems(lang, seg.ref);
  const kinds = [...new Set((seg.parts || [seg]).map(p => p.kind).filter(Boolean))];
  const summary = (seg.parts || [seg]).map(p => plainText(p.text || '')).join(' ').slice(0, 70);
  const head = h('header', {},
    h('button', { class: 'ghost', text: isOpen ? '▾' : '▸', title: 'Collapse / expand', onclick: () => { if (isOpen) collapsed.add(seg); else collapsed.delete(seg); renderVisual(); } }),
    h('b', { text: lang === 'he' ? 'he' : 'en' }), refInp,
    kinds.map(k => h('span', { class: 'badge kind-' + k, text: k })),
    seg.parts ? h('span', { class: 'badge', text: seg.parts.length + ' parts' }) : null,
    probs.length ? h('span', { class: 'badge ' + (probs.some(p => p.level === 'error') ? 'err' : 'warn'), title: probs.map(p => p.msg).join('\n'), text: '! ' + probs.length }) : null,
    !isOpen ? h('span', { class: lang === 'he' ? 'he muted' : 'muted', style: 'overflow:hidden;white-space:nowrap;text-overflow:ellipsis;max-width:40%', text: summary }) : null,
    h('span', { class: 'grow' }),
    h('button', { class: 'ghost', text: '↑', title: 'Move up', disabled: si === 0, onclick: () => mutate(() => { segs.splice(si - 1, 0, segs.splice(si, 1)[0]); S.pendingFocus = { lang, si: si - 1, noFocus: true }; }) }),
    h('button', { class: 'ghost', text: '↓', title: 'Move down', disabled: si === segs.length - 1, onclick: () => mutate(() => { segs.splice(si + 1, 0, segs.splice(si, 1)[0]); S.pendingFocus = { lang, si: si + 1, noFocus: true }; }) }),
    h('button', { class: 'ghost', text: '⧉', title: 'Duplicate (new ref)', onclick: () => mutate(() => { const c = clone(seg); c.ref = nextRef(segs); segs.splice(si + 1, 0, c); S.pendingFocus = { lang, si: si + 1 }; }) }),
    h('button', { class: 'ghost', text: '＋', title: 'Insert a segment after this', onclick: e => menu(e.target, lang === 'he'
      ? S.meta.enums.kinds.map(k => [`+ ${k}`, () => addSeg(l, lang, si + 1, k)]) : [['+ English segment', () => addSeg(l, lang, si + 1)]]) }),
    h('button', { class: 'ghost danger', text: '✕', title: 'Delete segment', onclick: () => delSeg(l, lang, si) }));
  const body = h('div', { class: 'body' });
  if (isOpen) {
    if (lang === 'en') {
      const he = ((l.he || {}).segs || []).map(s => s.ref);
      const tr = seg.translates || [];
      body.append(h('div', { class: 'row' }, h('span', { class: 'hint', text: 'translates:' }), h('span', { class: 'chips' },
        he.map(r => h('span', { class: 'chip' + (tr.includes(r) ? ' on' : ''), text: r, onclick: e => {
          snapshot(chunk(), 'tr:' + uid(seg));
          const cur = seg.translates || [];
          // keep the Hebrew book order
          const next = cur.includes(r) ? cur.filter(x => x !== r) : he.filter(x => cur.includes(x) || x === r);
          seg.translates = next; e.target.classList.toggle('on'); touched();
        } })),
        tr.filter(r => !he.includes(r)).map(r => h('span', { class: 'chip on bad', title: 'No such Hebrew ref', text: r + '?' })))));
    }
    if (seg.parts) {
      seg.parts.forEach((_, pi) => body.append(partCard(l, lang, seg, pi)));
      body.append(h('div', { class: 'addbar' },
        h('button', { text: '+ part', onclick: () => mutate(() => { seg.parts.push(lang === 'he' ? { kind: 'prayer', text: '' } : { text: '' }); }) }),
        seg.parts.length === 1 ? h('button', { text: 'Merge into a plain segment', onclick: () => fromParts(seg) }) : null));
    } else {
      const holder = {};
      body.append(partFields(seg, lang, holder));
      body.append(h('div', { class: 'addbar' },
        h('button', { text: '✂ Split into parts at cursor', title: 'Parts have their own tags and run together on one line', onclick: () => splitPart(seg, 0, holder.ta.selectionStart) }),
        h('button', { text: 'Convert to parts', onclick: () => toParts(seg) })));
    }
  }
  const card = h('div', { class: `card seg ${lang}-seg`, 'data-lang': lang, 'data-si': si }, head, isOpen ? body : null);
  card.addEventListener('focusin', () => {
    if (S.curSeg && S.curSeg.lang === lang && S.curSeg.i === si) return;
    S.curSeg = { lang, i: si };
    scrollPreviewTo(lang, si);
  });
  return card;
}

function langSection(l, lang) {
  const sec = h('div');
  const name = lang === 'he' ? 'Hebrew' : 'English';
  const t = l[lang];
  const sources = Object.keys((D().book.sources || {})[lang] || {});
  const dl = h('datalist', { id: 'dl-' + lang }, sources.map(s => h('option', { value: s })));
  sec.append(h('div', { class: 'langhead' }, h('span', { text: name }), t ? h('span', { class: 'badge', text: t.segs.length + ' segments' }) : null,
    t ? h('button', { class: 'ghost', text: 'collapse all', onclick: () => { t.segs.forEach(s => collapsed.add(s)); renderVisual(); } }) : null,
    t ? h('button', { class: 'ghost', text: 'expand all', onclick: () => { t.segs.forEach(s => collapsed.delete(s)); renderVisual(); } }) : null));
  if (!t) {
    sec.append(h('button', { text: `+ Add ${name} text`, onclick: () => addSeg(l, lang, 0, lang === 'he' ? 'prayer' : undefined) }));
    return sec;
  }
  const ver = h('input', { type: 'text', list: 'dl-' + lang, value: t.version, style: 'width:100%', spellcheck: 'false' });
  ver.addEventListener('input', () => { snapshot(chunk(), 'ver:' + lang); t.version = ver.value; ver.classList.toggle('bad', !sources.includes(ver.value)); ver.title = sources.includes(ver.value) ? '' : 'Not in book.json sources'; touched(); });
  ver.classList.toggle('bad', !sources.includes(t.version));
  sec.append(dl, h('div', { class: 'row' }, wrapField(`${name} version (credited; must be in book.json sources)`, ver, 'wide'),
    h('button', { class: 'danger', text: `Remove ${name}`, onclick: () => { if (confirm(`Remove all ${name} text of this leaf?`)) mutate(() => { delete l[lang]; }); } })));
  t.segs.forEach((s, i) => sec.append(segCard(l, lang, s, i)));
  sec.append(h('div', { class: 'addbar' },
    lang === 'he' ? S.meta.enums.kinds.map(k => h('button', { text: '+ ' + k, onclick: () => addSeg(l, lang, t.segs.length, k) })) : h('button', { text: '+ English segment', onclick: () => addSeg(l, lang, t.segs.length) })));
  return sec;
}

// ---- leaf level
function leafMeta(l) {
  const E = S.meta.enums;
  return h('div', { class: 'card' },
    h('header', {}, h('b', { text: 'Leaf' }), h('span', { class: 'hint', text: 'path is unique in the siddur; rules, units.json and shortcuts refer to it' })),
    h('div', { class: 'body' },
      h('div', { class: 'row' },
        fText(l, 'path', { label: 'path', cls: 'wide', always: true, leafField: 'path', check: v => !v ? 'required' : (pathTaken(v) ? 'another leaf has this path' : null), after: () => { renderTree(); updateCrumb(); renderPreviewSoon(); } }),
        fText(l, 'title', { label: 'title (Hebrew)', he: true, cls: 'wide', leafField: 'title', after: () => renderPreviewSoon() })),
      h('div', { class: 'row' }, fNode(l, 'node (default for segments)', true), fSelect(l, 'service', E.services, { label: 'service' }), fWhen(l, 'when (whole leaf)')),
      h('div', { class: 'row' }, fText(l, 'comment', { label: 'comment (editors only)', cls: 'wide', area: true, leafField: 'comment' }))));
}
function pathTaken(p) {
  const cur = leaf();
  return D().chunks.some(c => c.doc && c.doc.leaves.some(l => l !== cur && l.path === p));
}

function leafToolbar(l) {
  const c = chunk();
  const ci = S.sel.chunk, li = S.sel.leaf;
  return h('div', { class: 'addbar', style: 'align-items:center' },
    h('button', { text: '◀', title: 'Previous leaf (Alt+↑)', onclick: () => stepLeaf(-1) }), h('button', { text: '▶', title: 'Next leaf (Alt+↓)', onclick: () => stepLeaf(1) }),
    h('button', { text: 'Leaf ▾', onclick: e => menu(e.target, [
      ['New leaf after this…', () => newLeaf(false)], ['Duplicate leaf…', () => newLeaf(true)], ['Delete leaf', deleteLeaf],
      ['Move up in the file', () => moveLeaf(-1)], ['Move down in the file', () => moveLeaf(1)],
      ...D().chunks.map((x, i) => [`Move to end of ${x.file}`, () => moveLeafTo(i)]).filter((_, i) => i !== ci),
    ]) }),
    h('button', { text: 'Show in tree', onclick: () => revealInTree() }),
    h('span', { class: 'hint', text: `${c.file} · leaf ${li + 1} of ${c.doc.leaves.length}` }));
}

function stepLeaf(d) {
  const flat = flatLeaves();
  const i = flat.findIndex(x => x.ci === S.sel.chunk && x.li === S.sel.leaf);
  const n = flat[i + d];
  if (n) selectLeaf(n.ci, n.li);
}
function flatLeaves() {
  const out = [];
  D().chunks.forEach((c, ci) => c.doc && c.doc.leaves.forEach((l, li) => out.push({ ci, li, l })));
  return out;
}

function newLeaf(dup) {
  const l = leaf();
  const path = prompt(dup ? 'Path of the copy:' : 'Path of the new leaf (its last part is its English title):', dup ? l.path + ' copy' : l.path.split('/').slice(0, -1).join('/') + '/New leaf');
  if (!path) return;
  if (pathTaken(path) && path !== '') { if (D().chunks.some(c => c.doc && c.doc.leaves.some(x => x.path === path))) return toast('That path is already used', true); }
  const li = S.sel.leaf;
  mutate(() => {
    let n;
    if (dup) { n = clone(l); n.path = path; }
    else {
      n = { path, title: path.split('/').pop(), node: l.node, ...(l.service ? { service: l.service } : {}),
        he: { version: firstVersion('he'), segs: [{ ref: '1', kind: 'prayer', text: '' }] } };
    }
    chunk().doc.leaves.splice(li + 1, 0, n);
    S.sel.leaf = li + 1;
  }, { tree: true });
}
function deleteLeaf() {
  const l = leaf();
  if (!confirm(`Delete the leaf "${l.path}" and all its text?`)) return;
  const c = chunk();
  mutate(() => { c.doc.leaves.splice(S.sel.leaf, 1); S.sel.leaf = Math.max(0, Math.min(S.sel.leaf, c.doc.leaves.length - 1)); }, { tree: true });
}
function moveLeaf(d) {
  const c = chunk(), ls = c.doc.leaves, i = S.sel.leaf;
  if (i + d < 0 || i + d >= ls.length) return toast('Already at the edge of the file');
  mutate(() => { ls.splice(i + d, 0, ls.splice(i, 1)[0]); S.sel.leaf = i + d; }, { tree: true });
}
function moveLeafTo(ci) {
  const src = chunk(), dst = D().chunks[ci], i = S.sel.leaf;
  if (!dst.doc) return toast('That file is not valid JSON', true);
  snapshot(dst, null);
  mutate(() => { const [x] = src.doc.leaves.splice(i, 1); dst.doc.leaves.push(x); dst.dirty = true; S.sel = { chunk: ci, leaf: dst.doc.leaves.length - 1 }; }, { tree: true });
  scheduleValidate(S.nusach, S.sel.chunk);
}

function renderLeafProblems() {
  const box = $('#leafProblems');
  if (!box) return;
  box.innerHTML = '';
  const c = chunk();
  const mine = (c.problems || []).filter(p => p.leaf === S.sel.leaf);
  if (!mine.length) { box.append(h('div', { class: 'hint cond-ok', text: c.validating ? 'Checking…' : '✓ No problems in this leaf' })); return; }
  mine.forEach(p => box.append(h('div', { class: 'prob ' + p.level, onclick: () => jumpProblem(p) }, h('span', { class: 'lvl', text: p.level === 'error' ? '✕' : '!' }), h('span', { text: p.msg }))));
}

function jumpProblem(p) {
  const m = /(he|en):(\S+?)(?: part (\d+))?[: ]/.exec(p.msg);
  if (!m) return;
  const segs = ((leaf() || {})[m[1]] || {}).segs || [];
  const si = segs.findIndex(s => s.ref === m[2]);
  if (si >= 0) gotoLoc(S.sel.chunk, S.sel.leaf, { lang: m[1], si, pi: m[3] ? +m[3] - 1 : null, field: 'text' });
}

function renderVisual() {
  const box = $('#visual');
  const top = box.scrollTop;
  box.innerHTML = '';
  const c = D() && chunk();
  if (!c) return;
  if (!c.doc) { box.append(h('div', { class: 'pv-empty' }, h('p', { text: c.error }), h('p', { text: 'Fix it in the "Raw file" tab.' }))); return; }
  const l = leaf();
  if (!l) { box.append(h('div', { class: 'pv-empty', text: 'Pick a leaf in the book (left).' })); return; }
  box.append(leafToolbar(l), h('div', { id: 'leafProblems' }), leafMeta(l), langSection(l, 'he'), langSection(l, 'en'));
  renderLeafProblems();
  box.scrollTop = top;
  const pf = S.pendingFocus;
  if (pf) {
    S.pendingFocus = null;
    const card = $(`.seg[data-lang="${pf.lang}"][data-si="${pf.si}"]`, box);
    if (card) {
      card.scrollIntoView({ block: 'center' });
      card.classList.add('flash'); setTimeout(() => card.classList.remove('flash'), 900);
      if (!pf.noFocus) { const ta = $('textarea.text', card); if (ta) ta.focus(); }
    }
  }
}

// Jump to a place (from Find, problems or the preview) and select the text
async function gotoLoc(ci, li, loc, hit) {
  if (S.sel.chunk !== ci || S.sel.leaf !== li) selectLeaf(ci, li, true);
  showCenterTab('visual');
  const box = $('#visual');
  let el = null;
  if (loc.leafField) el = $(`[data-leaf-field="${loc.leafField}"]`, box);
  else {
    const card = $(`.seg[data-lang="${loc.lang}"][data-si="${loc.si}"]`, box);
    if (card) {
      if (collapsed.has(((leaf()[loc.lang] || {}).segs || [])[loc.si])) { collapsed.delete(leaf()[loc.lang].segs[loc.si]); renderVisual(); return gotoLoc(ci, li, loc, hit); }
      const scope = loc.pi != null ? $(`.part[data-pi="${loc.pi}"]`, card) || card : card;
      el = $(`[data-ref="${loc.field}"]`, scope) || $('textarea.text', scope);
      card.classList.add('flash'); setTimeout(() => card.classList.remove('flash'), 900);
      card.scrollIntoView({ block: 'center' });
      S.curSeg = { lang: loc.lang, i: loc.si };
      scrollPreviewTo(loc.lang, loc.si);
    }
  }
  if (el) {
    const keep = document.activeElement && document.activeElement.id === 'findQ';
    if (el.closest('details')) el.closest('details').open = true;
    if (!keep) el.focus({ preventScroll: true });
    if (hit && typeof el.setSelectionRange === 'function') { try { el.setSelectionRange(hit.start, hit.end); } catch { /* not a text field */ } }
  }
}
function focusSeg(lang, i) {
  S.curSeg = { lang, i };
  const card = $(`#visual .seg[data-lang="${lang}"][data-si="${i}"]`);
  if (card) { card.scrollIntoView({ block: 'center', behavior: 'smooth' }); card.classList.add('flash'); setTimeout(() => card.classList.remove('flash'), 900); const ta = $('textarea.text', card); if (ta) ta.focus({ preventScroll: true }); }
  scrollPreviewTo(lang, i);
}
