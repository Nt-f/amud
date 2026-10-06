'use strict';
// Shared state, API access and small UI helpers.

const $ = (s, r = document) => r.querySelector(s);
const $$ = (s, r = document) => [...r.querySelectorAll(s)];
function h(tag, attrs, ...kids) {
  const e = document.createElement(tag);
  for (const [k, v] of Object.entries(attrs || {})) {
    if (v === false || v == null) continue;
    if (k === 'class') e.className = v;
    else if (k === 'text') e.textContent = v;
    else if (k === 'html') e.innerHTML = v;
    else if (k.startsWith('on')) e.addEventListener(k.slice(2), v);
    else if (k === 'value') e.value = v;
    else if (k === 'checked') e.checked = !!v;
    else e.setAttribute(k, v === true ? '' : v);
  }
  for (const c of kids.flat()) if (c != null && c !== false) e.append(c.nodeType ? c : document.createTextNode(c));
  return e;
}
const esc = s => String(s).replace(/[&<>"]/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;' }[c]));
const clone = o => JSON.parse(JSON.stringify(o));
const debounce = (fn, ms) => { let t; return (...a) => { clearTimeout(t); t = setTimeout(() => fn(...a), ms); }; };
const store = {
  get(k, d) { try { const v = localStorage.getItem('amud.' + k); return v == null ? d : JSON.parse(v); } catch { return d; } },
  set(k, v) { try { localStorage.setItem('amud.' + k, JSON.stringify(v)); } catch { /* private mode */ } },
};

async function api(path, body) {
  const opts = { headers: { 'X-Token': window.TOKEN } };
  if (body !== undefined) { opts.method = 'POST'; opts.body = JSON.stringify(body); opts.headers['Content-Type'] = 'application/json'; }
  const r = await fetch(path, opts);
  let data = null;
  try { data = await r.json(); } catch { /* not json */ }
  if (!r.ok) { const e = new Error((data && data.error) || r.statusText); e.status = r.status; throw e; }
  return data;
}

function toast(msg, err) {
  const t = h('div', { class: 'toast' + (err ? ' err' : ''), text: msg });
  $('#toasts').append(t);
  setTimeout(() => t.remove(), err ? 7000 : 2600);
}

// The whole app's state. `docs[nusach]` is the loaded siddur.
const S = {
  meta: null,
  nusach: null,
  docs: {},            // nusach → {book, bookMtime, chunks:[{file, mtime, doc, dirty, past, future, problems, error?, raw?}], bookDirty, bookProblems}
  sel: { chunk: 0, leaf: 0 },
  centerTab: 'visual',
  ctx: {},             // day-context simulator: variable → value
  pv: { lang: 'both', hideInactive: true, applyCtx: true, showTags: true, font: 'FrankRuhlLibre', size: 22 },
  find: null,
  curSeg: null,        // {lang, i} focused in the visual editor
};

const D = () => S.docs[S.nusach];
const chunk = (ci = S.sel.chunk) => D().chunks[ci];
const leaf = (ci = S.sel.chunk, li = S.sel.leaf) => { const c = chunk(ci); return c && c.doc && c.doc.leaves[li]; };

// ---- history: snapshots of a whole chunk, coalesced while typing in one field
function snapshot(c, key) {
  const now = Date.now();
  if (key && c._key === key && now - c._keyT < 1500) { c._keyT = now; return; }
  c._key = key || null; c._keyT = now;
  c.past.push(JSON.stringify(c.doc));
  if (c.past.length > 80) c.past.shift();
  c.future.length = 0;
}
function undo(redo) {
  const c = chunk(); if (!c || !c.doc) return;
  const from = redo ? c.future : c.past, to = redo ? c.past : c.future;
  if (!from.length) return toast(redo ? 'Nothing to redo' : 'Nothing to undo');
  to.push(JSON.stringify(c.doc));
  c.doc = JSON.parse(from.pop());
  c._key = null;
  c.dirty = true;
  if (S.sel.leaf >= c.doc.leaves.length) S.sel.leaf = Math.max(0, c.doc.leaves.length - 1);
  changed({ structural: true, tree: true });
}

// ---- the central "something changed" hook; editor.js fills it in
let changed = () => {};
function onChanged(fn) { changed = fn; }

// ---- modal
function modal(title, body, opts = {}) {
  const m = $('#modal');
  m.innerHTML = '';
  const close = () => { m.hidden = true; m.innerHTML = ''; document.removeEventListener('keydown', esc_); if (opts.onClose) opts.onClose(); };
  const esc_ = e => { if (e.key === 'Escape') { e.stopPropagation(); close(); } };
  document.addEventListener('keydown', esc_);
  m.onmousedown = e => { if (e.target === m) close(); };
  m.append(h('div', { class: 'dlg ' + (opts.cls || '') },
    h('header', {}, h('span', { text: title }), h('span', { class: 'grow' }), h('button', { class: 'ghost', text: '✕', onclick: close })),
    h('div', { class: 'body' }, body)));
  m.hidden = false;
  return close;
}

// ---- floating menu
function menu(anchor, items) {
  $$('.menu').forEach(x => x.remove());
  const r = anchor.getBoundingClientRect();
  const m = h('div', { class: 'menu', style: `left:${Math.min(r.left, innerWidth - 220)}px;top:${r.bottom + 2}px` },
    items.map(([label, fn]) => h('div', { text: label, onclick: () => { m.remove(); fn(); } })));
  document.body.append(m);
  const off = e => { if (!m.contains(e.target)) { m.remove(); document.removeEventListener('mousedown', off, true); } };
  setTimeout(() => document.addEventListener('mousedown', off, true), 0);
}

// ---- autocomplete for identifiers in an input (conditions, nodes)
function attachComplete(input, getItems, mode) {
  let box = null, idx = 0, list = [];
  const close = () => { if (box) { box.remove(); box = null; } };
  const wordAt = () => {
    const v = input.value, p = input.selectionStart;
    if (mode === 'whole') return { s: 0, e: v.length, w: v };
    let s = p; while (s > 0 && /[\w.]/.test(v[s - 1])) s--;
    let e = p; while (e < v.length && /[\w.]/.test(v[e])) e++;
    return { s, e, w: v.slice(s, p) };
  };
  const apply = item => {
    const { s, e } = wordAt();
    input.value = input.value.slice(0, s) + item[0] + input.value.slice(e);
    const pos = s + item[0].length;
    input.setSelectionRange(pos, pos);
    close();
    input.dispatchEvent(new Event('input', { bubbles: true }));
  };
  const show = () => {
    const { w } = wordAt();
    if (!w || w.length < 1) return close();
    const lw = w.toLowerCase();
    list = getItems().filter(([k, d]) => k.toLowerCase().includes(lw) && k !== w)
      .sort((a, b) => (b[0].toLowerCase().startsWith(lw) - a[0].toLowerCase().startsWith(lw)) || a[0].length - b[0].length).slice(0, 30);
    if (!list.length) return close();
    idx = 0;
    if (!box) { box = h('div', { class: 'autocomplete' }); document.body.append(box); }
    const r = input.getBoundingClientRect();
    box.style.left = r.left + 'px'; box.style.top = r.bottom + 2 + 'px';
    box.innerHTML = '';
    list.forEach((it, i) => box.append(h('div', { class: i === idx ? 'on' : '', onmousedown: e => { e.preventDefault(); apply(it); } }, h('span', { text: it[0] }), h('small', { text: (it[1] || '').slice(0, 40) }))));
  };
  const mark = () => $$('div', box).forEach((d, i) => d.classList.toggle('on', i === idx));
  input.addEventListener('input', show);
  input.addEventListener('blur', () => setTimeout(close, 120));
  input.addEventListener('keydown', e => {
    if (!box) return;
    if (e.key === 'ArrowDown') { idx = (idx + 1) % list.length; mark(); e.preventDefault(); }
    else if (e.key === 'ArrowUp') { idx = (idx - 1 + list.length) % list.length; mark(); e.preventDefault(); }
    else if (e.key === 'Enter' || e.key === 'Tab') { apply(list[idx]); e.preventDefault(); }
    else if (e.key === 'Escape') { close(); e.stopPropagation(); }
  });
}

// ---- text helpers shared by editor and find
const NIQQUD = /[֑-ׇֽֿׁׂׅׄ]/;
function stripHebrewMarks(s) { return s.replace(/[֑-ׇֽֿׁׂׅׄ]/g, ''); }
function plainText(html) { const d = document.createElement('div'); d.innerHTML = sanitize(html || ''); return d.textContent; }

const ALLOWED = new Set(['B', 'I', 'SMALL', 'SUP', 'SUB', 'BR', 'SPAN', 'BIG', 'STRONG', 'EM', 'U', 'A', 'P', 'DIV']);
function sanitize(html) {
  const t = document.createElement('template');
  t.innerHTML = html;
  const walk = n => {
    for (const c of [...n.childNodes]) {
      if (c.nodeType === 1) {
        if (!ALLOWED.has(c.tagName)) { c.replaceWith(...c.childNodes); continue; }
        for (const a of [...c.attributes]) if (!(c.tagName === 'SPAN' && a.name === 'class')) c.removeAttribute(a.name);
        walk(c);
      } else if (c.nodeType !== 3) c.remove();
    }
  };
  walk(t.content);
  const d = document.createElement('div');
  d.append(t.content);
  return d.innerHTML;
}
