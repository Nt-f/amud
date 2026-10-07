'use strict';
// Live preview: the leaf as the reader shows it, for a simulated day.

const FONTS = [['FrankRuhlLibre', 'Frank Ruhl Libre'], ['DavidLibre', 'David Libre'], ['KeterYG', 'Keter YG'], ['TaameyFrank', 'Taamey Frank'],
  ['TaameyDavid', 'Taamey David'], ['EzraSIL', 'Ezra SIL'], ['NotoSerifHebrew', 'Noto Serif Hebrew'], ['StamAshkenaz', 'Stam Ashkenaz']];

function leafConds(l) {
  const ids = new Set(l.when ? condIds(l.when) : []);
  for (const lang of ['he', 'en'])
    for (const s of ((l[lang] || {}).segs || []))
      for (const p of (s.parts || [s])) if (p.when) condIds(p.when).forEach(i => ids.add(i));
  return [...ids].filter(i => !i.startsWith('if_'));
}

function applyPvStyle() {
  const r = document.documentElement.style;
  r.setProperty('--hebrew', `"${S.pv.font}", "Frank Ruhl Libre", "Noto Serif Hebrew", serif`);
  r.setProperty('--hsize', S.pv.size + 'px');
}

function renderPreviewBar() {
  const bar = $('#previewBar');
  bar.innerHTML = '';
  const seg = (v, label) => h('button', { class: S.pv.lang === v ? 'on' : '', text: label, onclick: () => { S.pv.lang = v; store.set('pv', S.pv); renderPreviewBar(); renderPreview(); } });
  const cb = (key, label, title) => h('label', { class: 'opt', title }, h('input', { type: 'checkbox', checked: S.pv[key], onchange: e => { S.pv[key] = e.target.checked; store.set('pv', S.pv); renderPreview(); } }), label);
  bar.append(h('div', { class: 'inline' },
    seg('he', 'עברית'), seg('en', 'English'), seg('both', 'Both'), h('span', { class: 'sep' }),
    cb('applyCtx', 'Apply day', 'Evaluate each part\'s `when` against the simulated day'),
    cb('hideInactive', 'Hide inactive', 'Hidden, not dimmed (the app\'s default)'),
    cb('showTags', 'Tags', 'Show when/role/voice/gestures on each part')));
  bar.append(h('div', { class: 'inline' },
    h('select', { onchange: e => { S.pv.font = e.target.value; store.set('pv', S.pv); applyPvStyle(); } }, FONTS.map(([v, n]) => h('option', { value: v, text: n, selected: v === S.pv.font }))),
    h('input', { type: 'range', min: 14, max: 40, value: S.pv.size, title: 'Hebrew size', oninput: e => { S.pv.size = +e.target.value; store.set('pv', S.pv); applyPvStyle(); } }),
    h('select', { onchange: e => { if (e.target.value) { S.ctx = clone(PRESETS[e.target.value]); store.set('ctx', S.ctx); renderPreviewBar(); renderPreview(); } e.target.value = ''; } },
      h('option', { value: '', text: 'Day preset…' }), Object.keys(PRESETS).map(k => h('option', { value: k, text: k }))),
    h('button', { text: 'Clear day', onclick: () => { S.ctx = {}; store.set('ctx', S.ctx); renderPreviewBar(); renderPreview(); } })));

  const chip = id => {
    if (NUMERIC.has(id)) return h('label', { class: 'badge' }, id + ' ', h('input', { type: 'number', style: 'width:46px', value: S.ctx[id] || 0, oninput: e => { S.ctx[id] = +e.target.value; store.set('ctx', S.ctx); renderPreview(); } }));
    return h('span', { class: 'chip' + (S.ctx[id] ? ' on' : ''), title: (S.meta.variables[id] || {}).doc || '', text: id, onclick: e => { S.ctx[id] = !S.ctx[id]; store.set('ctx', S.ctx); e.target.classList.toggle('on', S.ctx[id]); renderPreview(); } });
  };
  const l = leaf();
  const used = l ? leafConds(l) : [];
  if (used.length) bar.append(h('div', { class: 'inline' }, h('span', { class: 'hint', text: 'Used here:' }), h('span', { class: 'chips' }, used.map(chip))));
  const det = h('details', { class: 'more' }, h('summary', { text: 'All day variables' }));
  const list = h('div', { class: 'chips' });
  const fill = q => { list.innerHTML = ''; Object.keys(S.meta.variables).filter(k => !q || k.toLowerCase().includes(q)).forEach(k => list.append(chip(k))); };
  det.append(h('input', { type: 'text', placeholder: 'filter', oninput: e => fill(e.target.value.toLowerCase()), style: 'width:100%;margin:3px 0' }), list);
  fill('');
  bar.append(det);
}

// Hebrew/English HTML of one part, for the preview
function pvPart(p, lang, ctxOn) {
  const active = !ctxOn || evalCond(p.when) !== false;
  if (!active && S.pv.hideInactive) return null;
  const kind = p.kind || 'prayer';
  const tags = [];
  if (S.pv.showTags) {
    if (p.when) tags.push(h('span', { class: 'badge', title: p.when }, 'when ' + p.when));
    if (p.alt) tags.push(h('span', { class: 'badge', text: 'alt ' + p.alt }));
    if (p.role && p.role !== 'individual') tags.push(h('span', { class: 'badge', text: p.role.replace(/_/g, ' ') }));
    if (p.voice) tags.push(h('span', { class: 'badge', text: p.voice }));
    if (p.align) tags.push(h('span', { class: 'badge', text: 'align ' + p.align }));
    if (p.amidah) tags.push(h('span', { class: 'badge', text: 'amidah: ' + p.amidah }));
    if (p.minyan) tags.push(h('span', { class: 'badge', text: 'minyan' }));
    if (p.repeat) tags.push(h('span', { class: 'badge', text: '×' + p.repeat }));
    (p.gestures || []).forEach(g => tags.push(h('span', { class: 'badge', text: '↯ ' + g })));
    if (p.node) tags.push(h('span', { class: 'badge', text: p.node }));
    if (p.forgot) tags.push(h('span', { class: 'badge', text: 'if forgot' }));
    if (kind !== 'prayer' && lang === 'he') tags.unshift(h('span', { class: 'badge kind-' + kind, text: kind }));
  }
  const html = sanitize(p.text || '');
  let el;
  if (lang === 'en') {
    el = h('span', { class: 'pv-en en-only', html });
  } else if (kind === 'instruction') {
    el = h('span', { class: 'pv-instr', html: p.en ? esc(p.en) : html });
    if (!p.en) el.classList.add('he');
  } else if (kind === 'note') {
    el = h('span', { class: 'pv-note' + (p.forgot ? ' forgot' : ''), html: (p.en ? esc(p.en) : html) }, p.cite ? h('span', { class: 'cite', text: p.cite }) : null);
  } else if (kind === 'commentary') {
    el = h('span', { class: 'pv-comm', html: p.en ? esc(p.en) : html });
  } else if (kind === 'speaker') {
    el = h('span', { class: 'pv-speaker', html });
  } else if (kind === 'heading') {
    el = h('span', { class: 'pv-line heading', html });
  } else if (p.role === 'congregation') {
    el = h('span', { class: 'pv-cong' }, h('span', { class: 'lab', text: 'Cong.' }), h('span', { html }));
  } else {
    el = h('span', { class: 'pv-part', html });
  }
  if (!active) el.classList.add('inactive');
  const wrap = h('span', { class: 'pv-wrap' });
  if (tags.length) wrap.append(h('span', { class: 'pv-tags', style: 'display:flex' }, tags));
  wrap.append(el);
  if (p.gloss && S.pv.showTags) wrap.append(h('span', { class: 'pv-comm', text: p.gloss }));
  return wrap;
}

function renderPreview(keepScroll = true) {
  const box = $('#preview');
  const top = box.scrollTop;
  box.innerHTML = '';
  const l = leaf();
  if (!l) { box.append(h('div', { class: 'pv-empty', text: 'Pick a leaf in the book.' })); return; }
  const ctxOn = S.pv.applyCtx;
  const root = h('div', { class: 'pv-leaf' });
  root.append(h('div', { class: 'pv-title', text: l.title || l.path.split('/').pop() }), h('div', { class: 'pv-path', text: l.path }));
  if (l.when) {
    const ok = evalCond(l.when);
    root.append(h('div', { class: 'pv-path pv-cond', text: `leaf when ${l.when}` + (ctxOn && ok === false ? ' — not today' : '') }));
  }
  const he = ((l.he || {}).segs) || [], en = ((l.en || {}).segs) || [];
  const mode = S.pv.lang;
  const attach = {};          // he ref → [en seg index]
  if (mode === 'both') {
    let host = he.length ? he[0].ref : null;
    en.forEach((s, i) => {
      const t = (s.translates || []).find(r => he.some(x => x.ref === r));
      if (t) host = t;
      if (host != null) (attach[host] = attach[host] || []).push(i);
    });
  }
  const segEl = (s, lang, i) => {
    const parts = (s.parts || [s]);
    const rendered = parts.map(p => pvPart(p, lang, ctxOn)).filter(Boolean);
    if (!rendered.length) return null;
    const cls = 'pv-seg' + (S.curSeg && S.curSeg.lang === lang && S.curSeg.i === i ? ' cur' : '');
    const d = h('div', { class: cls, 'data-lang': lang, 'data-i': i, onclick: () => focusSeg(lang, i) });
    d.append(h('span', { class: 'refno', text: s.ref }));
    const body = h('div', { class: lang === 'he' ? 'pv-he' : 'pv-en' });
    const al = (parts[0] || {}).align;
    if (al) body.style.textAlign = al === 'justify' ? 'justify' : al;
    rendered.forEach(r => body.append(r));
    d.append(body);
    return d;
  };
  if (mode !== 'en') {
    he.forEach((s, i) => {
      const e = segEl(s, 'he', i);
      if (e) root.append(e);
      if (mode === 'both') (attach[s.ref] || []).forEach(j => { const ee = segEl(en[j], 'en', j); if (ee) root.append(ee); });
    });
    if (!he.length && mode === 'both') en.forEach((s, j) => { const ee = segEl(s, 'en', j); if (ee) root.append(ee); });
  } else {
    en.forEach((s, j) => { const ee = segEl(s, 'en', j); if (ee) root.append(ee); });
  }
  if (root.children.length <= 2 + (l.when ? 1 : 0)) root.append(h('div', { class: 'pv-empty', text: ctxOn && S.pv.hideInactive ? 'Nothing is shown for this day (see "Apply day").' : 'No text.' }));
  box.append(root);
  if (typeof highlightFindIn === 'function') highlightFindIn(box);
  if (keepScroll) box.scrollTop = top;
}

function scrollPreviewTo(lang, i) {
  const el = $(`#preview .pv-seg[data-lang="${lang}"][data-i="${i}"]`);
  $$('#preview .pv-seg.cur').forEach(x => x.classList.remove('cur'));
  if (el) { el.classList.add('cur'); el.scrollIntoView({ block: 'center', behavior: 'smooth' }); }
}
