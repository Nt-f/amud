'use strict';
// The Agent tab: run the editing agent (a free OpenRouter model, via
// tool/corpus/agent.py), read its log, and review what it proposes as a diff
// to approve or reject. Nothing reaches the corpus until you approve.

const AG = { tasks: null, each: store.get('agentEach', false), status: { running: false, log: [], hasKey: true }, proposals: [], models: null, model: store.get('agentModel', 'auto'), task: '', scope: '', timer: null };

async function pollAgent() {
  clearTimeout(AG.timer);
  try {
    AG.status = await api('/api/agent');
    const p = await api('/api/proposals');
    const was = AG.proposals.filter(x => x.status === 'pending').length;
    AG.proposals = p.proposals;
    const pend = AG.proposals.filter(x => x.status === 'pending').length;
    $('#propCount').textContent = pend ? String(pend) : '';
    if (!$('#paneAgent').hidden) renderAgent(true);
    if (was !== pend && pend > was) toast('The agent has a proposal to review');
  } catch { /* server restarting */ }
  AG.timer = setTimeout(pollAgent, AG.status.running ? 1500 : 6000);
}

async function loadAgentTasks() {
  try { AG.tasks = (await api('/api/agent/tasks')).tasks; renderAgent(); } catch { AG.tasks = []; }
}

async function loadAgentModels() {
  try { AG.models = (await api('/api/agent/models')).models; renderAgent(); }
  catch (e) { toast(e.message, true); }
}

function diffEl(text) {
  const pre = h('pre', { class: 'diff' });
  text.split('\n').forEach(l => {
    const c = l.trimStart().startsWith('+ ') ? 'add' : l.trimStart().startsWith('- ') ? 'del' : 'hd';
    pre.append(h('div', { class: c }, l));
  });
  return pre;
}

async function decide(p, action) {
  try {
    const r = await api('/api/proposal', { id: p.id, action });
    toast(r.message);
    await pollAgent();
    if (action === 'approve') pollDisk();
  } catch (e) { toast(e.message, true); }
}

function renderAgent(soft) {
  const box = $('#paneAgent');
  if (soft && box.querySelector('#agTask') && document.activeElement && box.contains(document.activeElement) && document.activeElement.id === 'agTask') {
    renderAgentLists(); return;
  }
  const keep = box.scrollTop;
  box.innerHTML = '';
  const st = AG.status;
  const l = leaf();
  const task = h('textarea', { id: 'agTask', placeholder: 'What should the agent do?  e.g. “Mark the Rosh Chodesh additions in Musaf with when=roshChodesh and add English instructions.”', value: AG.task, oninput: e => { AG.task = e.target.value; } });
  if (AG.tasks === null) loadAgentTasks();
  const preset = h('select', { onchange: e => { const t = (AG.tasks || []).find(x => x.name === e.target.value); if (t) { AG.task = t.text; if (t.name === 'format') { AG.each = true; store.set('agentEach', true); } renderAgent(); } } },
    h('option', { value: '', text: 'Task presets…' }), (AG.tasks || []).map(t => h('option', { value: t.name, text: t.name })));
  const each = h('label', { class: 'opt', title: 'One short session per leaf that `lint` flags (clean leaves cost nothing), each ending in its own proposal. The scope is then a path prefix.' },
    h('input', { type: 'checkbox', checked: AG.each, onchange: e => { AG.each = e.target.checked; store.set('agentEach', AG.each); } }), 'formatter mode: each leaf that needs work');
  const scope = h('input', { type: 'text', placeholder: 'scope: only leaves whose path contains…', value: AG.scope, oninput: e => { AG.scope = e.target.value; }, spellcheck: 'false' });
  const modelSel = h('select', { onchange: e => { AG.model = e.target.value; store.set('agentModel', AG.model); } },
    h('option', { value: 'auto', text: 'auto: the biggest free model' }),
    (AG.models || []).map(m => h('option', { value: m.id, text: `${m.id} (${Math.round(m.context / 1000)}k)`, selected: m.id === AG.model })));
  if (AG.model !== 'auto' && !(AG.models || []).some(m => m.id === AG.model)) modelSel.append(h('option', { value: AG.model, text: AG.model, selected: true }));
  const keyIn = h('input', { type: 'password', placeholder: 'OpenRouter key (sk-or-…)', style: 'flex:1' });
  const form = h('div', { class: 'agentform' },
    h('div', { class: 'hint', text: 'A free OpenRouter model edits by address and word number, so it never retypes Hebrew. You approve the diff before anything is written.' }),
    preset, task, each,
    h('div', { class: 'row', style: 'margin:0' }, scope, h('button', { text: 'this leaf', title: 'Limit to the open leaf', onclick: () => { AG.scope = l ? l.path : ''; renderAgent(); } })),
    h('div', { class: 'row', style: 'margin:0' }, modelSel, h('button', { text: 'refresh models', onclick: loadAgentModels })),
    st.hasKey ? null : h('div', { class: 'row', style: 'margin:0' }, keyIn, h('button', { text: 'Save key', onclick: async () => { try { AG.status = await api('/api/agent/key', { key: keyIn.value }); toast('Key saved to ~/.config/amud/openrouter.key'); renderAgent(); } catch (e) { toast(e.message, true); } } })),
    h('div', { class: 'row', style: 'margin:0' },
      st.running ? h('button', { class: 'danger', text: 'Stop', onclick: async () => { AG.status = await api('/api/agent/stop', {}); renderAgent(); } })
        : h('button', { class: 'primary', text: 'Run the agent', disabled: !st.hasKey, onclick: async () => {
          if (!AG.task.trim()) return toast('Say what to do', true);
          try { AG.status = await api('/api/agent/start', { task: AG.task, nusach: S.nusach, scope: AG.scope, model: AG.model, each: AG.each }); pollAgent(); renderAgent(); } catch (e) { toast(e.message, true); }
        } }),
      h('span', { class: 'hint', text: `siddur: ${S.nusach}` })));
  box.append(form, h('div', { id: 'agLists' }));
  renderAgentLists();
  box.scrollTop = keep;
}

function renderAgentLists() {
  const box = $('#agLists');
  if (!box) return;
  box.innerHTML = '';
  const st = AG.status;
  if (st.log.length) box.append(h('details', { class: 'more', open: st.running, style: 'margin:6px 8px' }, h('summary', { text: st.running ? 'Running…' : `Last run (${st.code === 0 ? 'finished' : 'exit ' + st.code})` }),
    h('pre', { class: 'diff', style: 'max-height:200px' }, st.log.join('\n'))));
  const pend = AG.proposals.filter(p => p.status === 'pending');
  const rest = AG.proposals.filter(p => p.status !== 'pending').slice(0, 5);
  if (!pend.length && !st.running) box.append(h('div', { class: 'pv-empty', style: 'margin:20px 8px', text: 'No proposals waiting.' }));
  [...pend, ...rest].forEach(p => {
    const card = h('div', { class: 'card prop' },
      h('header', {}, h('b', { text: p.status === 'pending' ? 'Proposal' : p.status }), h('span', { class: 'badge', text: p.nusach }),
        h('span', { class: 'meta', text: new Date(p.created * 1000).toLocaleTimeString() }), h('span', { class: 'grow' }),
        p.status === 'pending' ? [
          h('button', { class: 'primary', text: 'Approve', disabled: (p.errors || []).length > 0, onclick: () => decide(p, 'approve') }),
          h('button', { class: 'danger', text: 'Reject', onclick: () => decide(p, 'reject') })] : null),
      h('div', { class: 'body' },
        h('div', { class: 'meta', text: p.task }),
        (p.errors || []).length ? h('div', { class: 'cond-bad', text: p.errors.join('\n') }) : null,
        diffEl(p.diff), h('div', { class: 'meta', text: 'files: ' + p.files.join(', ') })));
    box.append(card);
  });
}
