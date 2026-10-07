'use strict';
// Find and replace across the corpus: Hebrew-aware (niqqud and cantillation
// ignored, HTML tags ignored), regex, whole word, scoped by field.

const FIND_FIELDS = [
  ['heText', 'Hebrew text'], ['enText', 'English text'], ['partEn', 'Instruction/note English (en)'], ['partHe', 'Hebrew gloss (he)'],
  ['when', 'Conditions (when)'], ['comment', 'Comments'], ['gloss', 'Gloss / cite'], ['node', 'Nodes'], ['ref', 'Refs'], ['leaf', 'Leaf path and title'],
];
const FIND_DEFAULT = {
  query: '', repl: '', regex: false, matchCase: false, word: false, marks: true, tags: true,
  scope: 'siddur', fields: ['heText', 'enText', 'partEn'], kind: '', role: '', onlyWhen: false,
  results: [], cur: -1, active: false, truncated: false,
};
function initFind() { S.find = Object.assign(clone(FIND_DEFAULT), store.get('find', {}), { results: [], cur: -1, active: false, truncated: false }); }

const isSkippedMark = c => NIQQUD.test(c);

// A normalized copy of `s` plus a map from its indexes to the original's.
function normalize(s, o, html) {
  let out = '', map = [], inTag = false;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (html && o.tags) {
      if (c === '<' && /^<\/?[a-zA-Z]/.test(s.slice(i, i + 3))) inTag = true;
      if (inTag) { if (c === '>') inTag = false; continue; }
    }
    if (o.marks && isSkippedMark(c)) continue;
    const lc = o.matchCase ? c : c.toLowerCase();
    for (let k = 0; k < lc.length; k++) { out += lc[k]; map.push(i); }
  }
  map.push(s.length);
  return { str: out, map };
}

function buildRegex(o) {
  let q = o.query;
  if (!q) return null;
  if (o.marks) q = stripHebrewMarks(q);
  if (!o.matchCase) q = q.toLowerCase();
  let src = o.regex ? q : q.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  if (o.word) src = `(?<![\\p{L}\\p{N}])(?:${src})(?![\\p{L}\\p{N}])`;
  return new RegExp(src, 'gu');
}

// Matches in one string: [{start,end,text}] in original coordinates
function matchesIn(s, re, o, html) {
  if (!s) return [];
  const { str, map } = normalize(s, o, html);
  const out = [];
  re.lastIndex = 0;
  let m;
  while ((m = re.exec(str))) {
    if (!m[0].length) { re.lastIndex++; continue; }
    const start = map[m.index];
    let end = map[m.index + m[0].length - 1] + 1;
    while (end < s.length && o.marks && isSkippedMark(s[end])) end++;
    out.push({ start, end, norm: m[0], m });
    if (out.length > 500) break;
  }
  return out;
}

// Every searchable field of a leaf: {loc, get(), set(v), html}
function* leafTargets(l, ci, li, o) {
  const F = new Set(o.fields);
  if (F.has('leaf')) {
    for (const k of ['path', 'title']) if (typeof l[k] === 'string') yield { loc: { ci, li, leafField: k }, get: () => l[k], set: v => { l[k] = v; }, html: false, label: 'leaf ' + k };
  }
  if (F.has('comment') && l.comment) yield { loc: { ci, li, leafField: 'comment' }, get: () => l.comment, set: v => { l.comment = v; }, html: false, label: 'leaf comment' };
  if (F.has('when') && l.when) yield { loc: { ci, li, leafField: 'when' }, get: () => l.when, set: v => { l.when = v; }, html: false, label: 'leaf when' };
  for (const lang of ['he', 'en']) {
    const segs = ((l[lang] || {}).segs) || [];
    for (let si = 0; si < segs.length; si++) {
      const s = segs[si];
      const partList = s.parts ? s.parts.map((p, pi) => [p, pi]) : [[s, null]];
      if (F.has('ref')) yield { loc: { ci, li, lang, si, pi: null, field: 'ref' }, get: () => s.ref, set: v => { s.ref = v; }, html: false, label: `${lang}:${s.ref} ref`, seg: s };
      for (const [p, pi] of partList) {
        if (o.kind && (p.kind || '') !== o.kind) continue;
        if (o.role && (p.role || '') !== o.role) continue;
        if (o.onlyWhen && !p.when) continue;
        const add = (field, html, label) => ({ loc: { ci, li, lang, si, pi, field }, get: () => p[field], set: v => { p[field] = v; }, html, label: `${lang}:${s.ref}${pi != null ? '.' + (pi + 1) : ''} ${label}`, seg: s, part: p });
        if (F.has(lang === 'he' ? 'heText' : 'enText') && typeof p.text === 'string') yield add('text', true, 'text');
        if (F.has('partEn') && typeof p.en === 'string') yield add('en', true, 'en');
        if (F.has('partHe') && typeof p.he === 'string') yield add('he', true, 'he');
        if (F.has('when') && p.when) yield add('when', false, 'when');
        if (F.has('comment') && p.comment) yield add('comment', false, 'comment');
        if (F.has('gloss')) { if (p.gloss) yield add('gloss', false, 'gloss'); if (p.cite) yield add('cite', false, 'cite'); }
        if (F.has('node') && p.node) yield add('node', false, 'node');
      }
    }
  }
}

async function scopeLeaves(o) {
  const out = [];
  const nus = o.scope === 'all' ? S.meta.nusachim : [S.nusach];
  for (const n of nus) {
    if (!S.docs[n]) await loadSiddur(n);
    const d = S.docs[n];
    d.chunks.forEach((c, ci) => {
      if (!c.doc) return;
      if (o.scope === 'file' && !(n === S.nusach && ci === S.sel.chunk)) return;
      c.doc.leaves.forEach((l, li) => {
        if (o.scope === 'leaf' && !(n === S.nusach && ci === S.sel.chunk && li === S.sel.leaf)) return;
        out.push({ n, ci, li, l });
      });
    });
  }
  return out;
}

async function runFind(keepCur) {
  const o = S.find;
  store.set('find', { ...o, results: undefined, cur: undefined, active: undefined });
  o.results = []; o.truncated = false;
  let re;
  try { re = buildRegex(o); } catch (e) { $('#findInfo').textContent = 'Bad pattern: ' + e.message; $('#findInfo').className = 'cond-bad'; renderResults(); return; }
  $('#findInfo').className = 'hint';
  if (!re) { $('#findInfo').textContent = ''; o.cur = -1; renderResults(); refreshHighlights(); return; }
  const leaves = await scopeLeaves(o);
  outer:
  for (const { n, ci, li, l } of leaves) {
    for (const t of leafTargets(l, ci, li, o)) {
      const v = t.get();
      if (typeof v !== 'string') continue;
      for (const m of matchesIn(v, re, o, t.html)) {
        const a = Math.max(0, m.start - 28), b = Math.min(v.length, m.end + 28);
        o.results.push({ n, ci, li, path: l.path, title: l.title, loc: t.loc, label: t.label, start: m.start, end: m.end, orig: v.slice(m.start, m.end), norm: m.norm, ctx: t.html ? [v.slice(a, m.start).replace(/<[^>]*>/g, ''), v.slice(m.start, m.end).replace(/<[^>]*>/g, ''), v.slice(m.end, b).replace(/<[^>]*>/g, '')] : [v.slice(a, m.start), v.slice(m.start, m.end), v.slice(m.end, b)], hebrew: t.loc.lang === 'he' && t.loc.field === 'text' });
        if (o.results.length >= 3000) { o.truncated = true; break outer; }
      }
    }
  }
  o.cur = keepCur != null && keepCur < o.results.length ? keepCur : (o.results.length ? 0 : -1);
  renderResults();
  refreshHighlights();
}

function replacementFor(hit) {
  const o = S.find;
  if (!o.regex) return o.repl;
  try { const re = new RegExp(buildRegex({ ...o, word: false }).source, 'u' + (o.matchCase ? '' : 'i')); const m = re.exec(hit.norm); if (m) return hit.norm.replace(re, o.repl); } catch { /* fall through */ }
  return o.repl;
}

async function replaceHits(hits) {
  if (!hits.length) return 0;
  const o = S.find;
  const byTarget = new Map();
  for (const h_ of hits) {
    const k = `${h_.n}|${h_.ci}|${h_.li}|${JSON.stringify(h_.loc)}`;
    (byTarget.get(k) || byTarget.set(k, []).get(k)).push(h_);
  }
  let n = 0;
  const touched = new Set();
  for (const group of byTarget.values()) {
    const g0 = group[0];
    const c = S.docs[g0.n].chunks[g0.ci];
    const l = c.doc.leaves[g0.li];
    const t = [...leafTargets(l, g0.ci, g0.li, { ...o, fields: FIND_FIELDS.map(f => f[0]), kind: '', role: '', onlyWhen: false })].find(t => JSON.stringify(t.loc) === JSON.stringify(g0.loc));
    if (!t) continue;
    let v = t.get();
    if (!touched.has(c)) { snapshot(c, null); touched.add(c); }
    for (const hh of group.sort((a, b) => b.start - a.start)) {
      if (v.slice(hh.start, hh.end) !== hh.orig) continue; // text changed since the search
      v = v.slice(0, hh.start) + replacementFor(hh) + v.slice(hh.end);
      n++;
    }
    t.set(v);
  }
  for (const c of touched) { c.dirty = true; }
  changed({ structural: true, tree: true });
  for (const c of touched) { const ci = S.docs[S.nusach].chunks.indexOf(c); if (ci >= 0) scheduleValidate(S.nusach, ci); }
  return n;
}

async function replaceCurrent() {
  const o = S.find, hit = o.results[o.cur];
  if (!hit) return;
  const cur = o.cur;
  const n = await replaceHits([hit]);
  await runFind(cur);
  if (!n) toast('That text changed; searched again');
}
async function replaceAll() {
  const o = S.find;
  if (!o.results.length) return;
  if (!o.repl && !confirm(`Delete ${o.results.length} match(es) (the replacement is empty)?`)) return;
  const count = o.results.length;
  if (o.scope === 'all' || count > 50) if (!confirm(`Replace ${count} match(es) in ${o.scope === 'all' ? 'every siddur' : 'this ' + (o.scope === 'siddur' ? 'siddur' : o.scope)}? Undo works per file.`)) return;
  const n = await replaceHits(o.results.slice());
  toast(`Replaced ${n} of ${count}`);
  await runFind();
}

function findStep(d) {
  const o = S.find;
  if (!o.results.length) return;
  o.cur = (o.cur + d + o.results.length) % o.results.length;
  renderResults(true);
  openHit(o.results[o.cur]);
}

async function openHit(hit) {
  if (hit.n !== S.nusach) await selectNusach(hit.n);
  await gotoLoc(hit.ci, hit.li, hit.loc, hit);
}

function renderFindPane() {
  const o = S.find, p = $('#paneFind');
  p.innerHTML = '';
  const q = h('input', { type: 'text', id: 'findQ', placeholder: 'Find…  (Enter next, Shift+Enter previous)', value: o.query, spellcheck: 'false' });
  const r = h('input', { type: 'text', id: 'findR', placeholder: 'Replace with…' + (o.regex ? '  ($1 for groups)' : ''), value: o.repl, spellcheck: 'false' });
  const go = debounce(() => runFind(), 160);
  q.addEventListener('input', () => { o.query = q.value; go(); });
  q.addEventListener('keydown', e => { if (e.key === 'Enter') { e.preventDefault(); findStep(e.shiftKey ? -1 : 1); } });
  r.addEventListener('input', () => { o.repl = r.value; store.set('find', { ...o, results: undefined, cur: undefined, active: undefined }); });
  const opt = (key, label, title) => h('label', { class: 'opt', title }, h('input', { type: 'checkbox', checked: o[key], onchange: e => { o[key] = e.target.checked; if (key === 'regex') renderFindPane(); runFind(); } }), label);
  const sel = (key, items) => h('select', { onchange: e => { o[key] = e.target.value; runFind(); } }, items.map(([v, n]) => h('option', { value: v, text: n, selected: o[key] === v })));
  const fields = h('details', { class: 'more' }, h('summary', { text: `Search in: ${o.fields.length} field kind(s)` }),
    h('div', { style: 'display:grid;grid-template-columns:1fr 1fr;gap:2px 8px' }, FIND_FIELDS.map(([k, n]) => h('label', { class: 'opt' }, h('input', { type: 'checkbox', checked: o.fields.includes(k), onchange: e => { o.fields = e.target.checked ? [...o.fields, k] : o.fields.filter(x => x !== k); $('summary', fields).textContent = `Search in: ${o.fields.length} field kind(s)`; runFind(); } }), n))));
  const E = S.meta.enums;
  p.append(h('div', { class: 'findform' },
    h('div', { class: 'inline' }, q, h('button', { text: '▲', title: 'Previous', onclick: () => findStep(-1) }), h('button', { text: '▼', title: 'Next', onclick: () => findStep(1) })),
    h('div', { class: 'inline' }, r, h('button', { text: 'Replace', onclick: replaceCurrent }), h('button', { text: 'All', title: 'Replace every match', onclick: replaceAll })),
    h('div', { class: 'inline' },
      opt('matchCase', 'Aa', 'Match case (English)'), opt('regex', '.*', 'Regular expression'), opt('word', 'Word', 'Whole word'),
      opt('marks', 'Ignore niqqud', 'Ignore vowels and cantillation marks, in the text and in your query'), opt('tags', 'Ignore tags', 'Look through <b>, <small> and other tags')),
    h('div', { class: 'inline' }, sel('scope', [['leaf', 'This leaf'], ['file', 'This file'], ['siddur', 'This siddur'], ['all', 'All 5 siddurim']]),
      sel('kind', [['', 'any kind'], ...E.kinds.map(k => [k, k])]), sel('role', [['', 'any role'], ...E.roles.map(k => [k, k])]), opt('onlyWhen', 'has when', 'Only parts with a condition')),
    fields,
    h('div', { id: 'findInfo', class: 'hint' })));
  p.append(h('div', { id: 'findResults', class: 'results' }));
  renderResults();
}

function renderResults(keepScroll) {
  const o = S.find, box = $('#findResults');
  if (!box) return;
  const info = $('#findInfo');
  if (info && info.className !== 'cond-bad') info.textContent = o.query ? `${o.results.length}${o.truncated ? '+' : ''} match(es)` + (o.cur >= 0 ? ` — ${o.cur + 1} of ${o.results.length}` : '') : '';
  const prevScroll = box.scrollTop;
  box.innerHTML = '';
  let last = null;
  o.results.forEach((r, i) => {
    const key = r.n + '|' + r.ci + '|' + r.li;
    if (key !== last) {
      last = key;
      box.append(h('div', { class: 'grp', title: r.path, onclick: () => openHit(r), text: (o.scope === 'all' ? `[${r.n}] ` : '') + r.path }));
    }
    const ctx = h('div', { class: 'ctx' + (r.hebrew ? ' he' : '') }, r.ctx[0], h('mark', { text: r.ctx[1] }), r.ctx[2]);
    box.append(h('div', { class: 'hit' + (i === o.cur ? ' sel' : ''), 'data-i': i, onclick: () => { o.cur = i; renderResults(true); openHit(r); } },
      h('div', { class: 'meta' }, h('span', { text: r.label })), ctx));
  });
  if (keepScroll) { const sel = $('.hit.sel', box); if (sel) sel.scrollIntoView({ block: 'nearest' }); else box.scrollTop = prevScroll; }
}

// Marks matches in the rendered preview
function highlightFindIn(root) {
  const o = S.find;
  if (!o || !o.active || !o.query) return;
  let re;
  try { re = buildRegex(o); } catch { return; }
  if (!re) return;
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const nodes = [];
  while (walker.nextNode()) nodes.push(walker.currentNode);
  for (const tn of nodes) {
    const ms = matchesIn(tn.data, re, { ...o, tags: false }, false);
    for (const m of ms.reverse()) {
      const r = document.createRange();
      r.setStart(tn, m.start); r.setEnd(tn, m.end);
      const mk = document.createElement('mark');
      try { r.surroundContents(mk); } catch { /* spans elements */ }
    }
  }
}
function refreshHighlights() { if (typeof renderPreview === 'function' && S.nusach) renderPreview(); }
