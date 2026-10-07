#!/usr/bin/env python3
"""An editing agent for Amud's siddur text, run by a free OpenRouter model.

    export OPENROUTER_API_KEY=sk-or-...          # or ~/.config/amud/openrouter.key
    python3 tool/corpus/agent.py models           # free models you can use right now
    python3 tool/corpus/agent.py -n ashkenaz --scope Weekday/Minchah \\
        "Mark the Rosh Chodesh additions with when=roshChodesh and add English instructions"

How it stays cheap: the model never writes Hebrew to say *where* an edit goes.
It reads compact numbered-word views and answers with the short command
language of edit.py (`tag he:3 w4..9 when=roshChodesh`), which the harness
runs against the corpus. Nothing is written until you approve the diff:

    (default)   shows the diff and asks y/N
    --propose   saves the diff as a proposal, to approve in the editor's Agent tab
    --apply     writes without asking (backups are kept; `edit.py undo` reverts)

Plain text protocol, so any model works, with or without tool calling.
"""
import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.request

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import edit  # noqa: E402
import source  # noqa: E402

BASE_URL = 'https://openrouter.ai/api/v1'
KEY_FILE = os.path.expanduser('~/.config/amud/openrouter.key')
LOGS = os.path.join(source.CORPUS, 'work', 'agent-logs')

SYSTEM = """You edit a Hebrew prayer corpus. You never retype Hebrew to say where an edit goes: you address text by segment ref and WORD NUMBER, and you answer ONLY with commands in one ``` block. The harness runs them and replies with the output. Nothing is written until a human approves the diff.

Reply format: a short plan sentence (optional) and ONE ``` block of commands, one per line. When finished, reply with the single word DONE.

{help}
Rules:
- Read before you write: `outline`, `show`, `find` first. Word numbers come from `show`/`find`; never guess them.
- Prefer addressing over text: tag/split/set. Write Hebrew only when a task needs new Hebrew, and then as little as possible.
- English you write (en=...) is the text the app shows for instructions and notes: short, plain.
- Conditions use variables (`vars roshChodesh`); circumstances the app cannot know use if_... labels (`labels`). Do not invent names.
- Instructions/notes are kinds `instruction`/`note`; a line said only on some days gets `when=`; set `role`/`voice` only where the text says so.
- A block is atomic: if a line fails, none of it is applied; fix and resend.
- Do exactly the task. Do not tidy, retag or rewrite anything else.
"""


# ---------------------------------------------------------------- OpenRouter

def api_key():
    k = os.environ.get('OPENROUTER_API_KEY', '').strip()
    if not k and os.path.isfile(KEY_FILE):
        k = open(KEY_FILE, encoding='utf-8').read().strip()
    if not k:
        raise SystemExit('No OpenRouter key. Create one at https://openrouter.ai/keys, then either\n'
                         '  export OPENROUTER_API_KEY=sk-or-...\n'
                         f'or put it in {KEY_FILE}')
    return k


def http(url, body=None, key=None, timeout=120):
    headers = {'Content-Type': 'application/json', 'HTTP-Referer': 'https://github.com/amud', 'X-Title': 'Amud corpus agent'}
    if key:
        headers['Authorization'] = 'Bearer ' + key
    req = urllib.request.Request(url, data=json.dumps(body).encode() if body is not None else None, headers=headers)
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode('utf-8'))


def free_models(base=BASE_URL):
    """Free models, biggest context first: [(id, context)]."""
    data = http(base + '/models')['data']
    out = []
    for m in data:
        p = m.get('pricing') or {}
        try:
            free = float(p.get('prompt', 1)) == 0 and float(p.get('completion', 1)) == 0
        except (TypeError, ValueError):
            free = False
        if free:
            out.append((m['id'], m.get('context_length') or 0, m.get('name', '')))
    return sorted(out, key=lambda x: -x[1])


class Chat:
    def __init__(self, model, base=BASE_URL, key=None, max_tokens=4000, log=print):
        self.model, self.base, self.key, self.max_tokens, self.log = model, base, key, max_tokens, log
        self.prompt_tokens = self.completion_tokens = 0
        self.calls = 0

    def complete(self, messages):
        """One reply. Reasoning models spend the token budget thinking before they
        answer, so ask for little reasoning and, if the reply is cut off before it holds
        a command block, try again with a bigger budget."""
        budget = self.max_tokens
        for _ in range(3):
            text, cut = self._once(messages, budget)
            if not cut or BLOCK.search(text) or re.search(r'\bDONE\b', text):
                return text
            budget *= 2
            self.log(f'  (reply cut off at the token limit; retrying with {budget})')
        return text

    def _once(self, messages, budget):
        body = {'model': self.model, 'messages': messages, 'temperature': 0, 'max_tokens': budget, 'reasoning': {'effort': 'low'}}
        delay = 5
        for attempt in range(6):
            try:
                r = http(self.base + '/chat/completions', body, self.key)
            except urllib.error.HTTPError as e:
                detail = e.read().decode('utf-8', 'replace')[:300]
                if e.code in (429, 502, 503, 504) and attempt < 5:
                    wait = float(e.headers.get('Retry-After') or delay)
                    self.log(f'  (HTTP {e.code}, waiting {wait:.0f}s)')
                    time.sleep(min(wait, 60))
                    delay = min(delay * 2, 60)
                    continue
                hint = ' Enable free-model endpoints at https://openrouter.ai/settings/privacy.' if e.code == 404 else ''
                raise RuntimeError(f'HTTP {e.code} from {self.model}: {detail}.{hint}')
            except urllib.error.URLError as e:
                raise RuntimeError(f'cannot reach {self.base}: {e.reason}')
            if 'error' in r and 'choices' not in r:
                err = r['error']
                text = str(err.get('message', '')).lower()
                transient = str(err.get('code')) in ('429', '500', '502', '503', '504', '529') or any(w in text for w in ('overloaded', 'temporarily', 'try again', 'rate limit', 'upstream'))
                if attempt < 5 and transient:
                    self.log(f'  (busy: {text[:60]}; waiting {delay}s)')
                    time.sleep(delay)
                    delay = min(delay * 2, 60)
                    continue
                raise RuntimeError(f'{self.model}: {err.get("message", err)}')
            u = r.get('usage') or {}
            self.prompt_tokens += u.get('prompt_tokens', 0)
            self.completion_tokens += u.get('completion_tokens', 0)
            self.calls += 1
            choice = r['choices'][0]
            msg = choice.get('message') or {}
            return (msg.get('content') or '').strip(), choice.get('finish_reason') == 'length'
        raise RuntimeError('rate limited too many times')


# ---------------------------------------------------------------- the loop

BLOCK = re.compile(r'```[a-zA-Z]*\n(.*?)```', re.S)


def commands_in(reply):
    blocks = BLOCK.findall(reply)
    return [l for b in blocks for l in b.splitlines() if l.strip()]


def clip(text, n=3500):
    return text if len(text) <= n else text[:n] + f'\n… [{len(text) - n} more characters: narrow the request]'


def view(messages, keep=6):
    """The conversation to send: old command output collapsed, so the
    context (and the bill) stays flat however long the session runs."""
    head, rest = messages[:2], messages[2:]
    out = list(head)
    for i, m in enumerate(rest):
        if m['role'] == 'user' and i < len(rest) - keep:
            first = m['content'].split('\n', 1)[0]
            out.append({'role': 'user', 'content': first[:120] + ' [output omitted]'})
        else:
            out.append(m)
    return out


def run_agent(task, nusach='ashkenaz', scope=None, chat=None, session=None, max_steps=25, log=print, extra=''):
    s = session or edit.Session(nusach)
    s.scope = scope
    s.load(nusach)
    if scope and scope.startswith('='):
        s.leaf = s.find_leaf(scope[1:])      # one leaf: it is already selected, no `@` needed
    sys_msg = SYSTEM.format(help=edit.HELP)
    where = scope[1:] if scope and scope.startswith('=') else scope
    intro = f'Siddur: {nusach}.' + (f' Work only in: {where}' + (' (already selected).' if scope.startswith('=') else '.') if where else '') + f'\n\nTask: {task}' + (f'\n\n{extra}' if extra else '')
    messages = [{'role': 'system', 'content': sys_msg}, {'role': 'user', 'content': intro}]
    transcript = [f'# {task}\n', f'siddur {nusach}, scope {scope}\n']
    fails = 0
    done = False
    for step in range(1, max_steps + 1):
        reply = chat.complete(view(messages))
        messages.append({'role': 'assistant', 'content': reply})
        transcript.append(f'\n## step {step}\n{reply}\n')
        cmds = commands_in(reply)
        if not cmds:
            if re.search(r'\bDONE\b', reply):
                done = True
                break
            fails += 1
            if fails >= 3:
                log('The model stopped answering in the command format.')
                break
            messages.append({'role': 'user', 'content': 'Reply with ONE ``` block of commands, or the single word DONE.'})
            continue
        log(f'[{step}] ' + ' | '.join(c.strip() for c in cmds)[:200])
        out, err, _ = edit.run_block(s, [c for c in cmds if c.strip() not in ('apply', 'done', 'DONE')])
        if err:
            fails += 1
            result = 'ERROR ' + err
            log('    ' + err[:200])
        else:
            fails = 0
            result = clip('\n'.join(out) or 'ok')
        if any(c.strip().lower() in ('done', 'apply') for c in cmds) and not err:
            done = True
        transcript.append(f'\n→\n{result}\n')
        if done:
            break
        if fails >= 4:
            log('Too many failed attempts in a row; stopping.')
            break
        messages.append({'role': 'user', 'content': result})
    else:
        log(f'Stopped after {max_steps} steps.')
    return s, transcript, done


def save_log(transcript):
    os.makedirs(LOGS, exist_ok=True)
    p = os.path.join(LOGS, time.strftime('%Y%m%d-%H%M%S') + '.md')
    with open(p, 'w', encoding='utf-8') as fh:
        fh.write(''.join(transcript))
    return p


def run_each(a, task, key, models):
    """Formatter mode: a short session for every leaf that `lint` flags, each
    ending in its own proposal. Clean leaves cost nothing."""
    s0 = edit.Session(a.nusach)
    s0.scope = a.each
    todo = []
    for _, _, lf in s0.leaves():
        s0.leaf = ('', '', lf)
        lint = edit.cmd_lint(s0, [])
        if lint != 'clean':
            todo.append((lf['path'], lint))
    print(f'{len(todo)} leaf(s) under {a.each!r} need work' + (f' (doing the first {a.max_leaves})' if len(todo) > a.max_leaves else ''))
    chat = Chat(models[0], a.base_url, key)
    made = 0
    for k, (path, lint) in enumerate(todo[:a.max_leaves], 1):
        print(f'\n[{k}/{min(len(todo), a.max_leaves)}] {path}')
        s = edit.Session(a.nusach)
        try:
            s, transcript, done = run_agent(task, a.nusach, '=' + path, chat, session=s, max_steps=a.max_steps,
                                            extra='lint says:\n' + lint[:2500])
        except RuntimeError as e:
            print(f'  skipped this leaf: {e}')
            continue
        save_log(transcript)
        if not s.touched:
            print('  no changes')
            continue
        errs, _ = edit.validate_touched(s)
        if errs:
            print('  skipped, new problems:\n   ' + '\n   '.join(errs[:4]))
            continue
        if a.apply:
            print('  ' + edit.commit(s, True))
        else:
            prop = edit.make_proposal(s, task=f'{task.splitlines()[0][:60]} — {path}', name=time.strftime('%Y%m%d-%H%M%S') + f'-{k:02d}')
            made += 1
            print(f'  proposal {prop["id"]}')
    print(f'\ntokens: {chat.prompt_tokens} in, {chat.completion_tokens} out over {chat.calls} call(s)')
    if made:
        print(f'{made} proposal(s) to review in the editor (Agent tab).')
    return 0


def main(argv):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0], formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument('task', nargs='*', help='what to do (or: models)')
    ap.add_argument('-n', '--nusach', default='ashkenaz')
    ap.add_argument('--scope', help='only leaves whose path contains this')
    ap.add_argument('--task-file', help='read the task from a file (tool/corpus/agent_tasks/*.md)')
    ap.add_argument('--each', metavar='PREFIX', help='one session per leaf under PREFIX that `lint` says needs work; one proposal per leaf')
    ap.add_argument('--max-leaves', type=int, default=25, help='most leaves --each will work on in one run')
    ap.add_argument('--model', default=os.environ.get('AMUD_AGENT_MODEL', 'auto'), help='an OpenRouter model id, or auto for the biggest free one')
    ap.add_argument('--base-url', default=os.environ.get('OPENROUTER_BASE_URL', BASE_URL))
    ap.add_argument('--max-steps', type=int, default=25)
    ap.add_argument('--propose', action='store_true', help='save the result as a proposal for the editor')
    ap.add_argument('--apply', action='store_true', help='write without asking')
    a = ap.parse_args(argv)

    if a.task == ['models']:
        for mid, ctx, name in free_models(a.base_url):
            print(f'{mid}  ({ctx // 1000}k context)  {name}')
        return 0
    task = ' '.join(a.task)
    if a.task_file:
        with open(a.task_file, encoding='utf-8') as fh:
            task = (task + '\n' + fh.read()).strip()
    if not task:
        ap.error('say what to do (or --task-file), or `models`')
    key = api_key() if 'openrouter.ai' in a.base_url else (os.environ.get('OPENROUTER_API_KEY') or 'test')
    models = [a.model]
    if a.model == 'auto':
        models = [m for m, _, _ in free_models(a.base_url)][:4]
        if not models:
            raise SystemExit('no free models listed right now; pass --model')
        print('free models to try:', ', '.join(models))
    if a.each:
        return run_each(a, task, key, models)
    last = None
    for model in models:
        chat = Chat(model, a.base_url, key)
        print(f'model: {model}')
        try:
            s, transcript, done = run_agent(task, a.nusach, a.scope, chat, max_steps=a.max_steps)
            break
        except RuntimeError as e:
            last = e
            print(f'  {e}')
    else:
        raise SystemExit(f'no model worked: {last}')
    print(f'tokens: {chat.prompt_tokens} in, {chat.completion_tokens} out over {chat.calls} call(s)  (log: {os.path.relpath(save_log(transcript), source.ROOT)})')
    if not s.touched:
        print('The agent made no changes.')
        return 0
    errs, _ = edit.validate_touched(s)
    print()
    print(edit.diff_text(s, color=sys.stdout.isatty()))
    if errs:
        print('\nNOT applied: new problems:\n' + '\n'.join(errs[:12]))
        return 1
    if a.propose or (not a.apply and not sys.stdin.isatty()):
        prop = edit.make_proposal(s, task=task, ops=[])
        print(f'\nProposal {prop["id"]} saved. Review it in the editor (Agent tab), or: python3 tool/corpus/edit.py approve {prop["id"]}')
        return 0
    if not a.apply and input('\nApply these changes? [y/N] ').strip().lower() != 'y':
        print('discarded')
        return 0
    print(edit.commit(s, True))
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
