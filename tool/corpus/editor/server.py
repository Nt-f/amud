#!/usr/bin/env python3
"""Visual editor for Amud's siddur text (corpus/siddur, see corpus/SCHEMA.md).

    python3 tool/corpus/editor/server.py             # http://127.0.0.1:8765
    python3 tool/corpus/editor/server.py --port 9000 --no-open

Serves a single-page editor and a small JSON API over the same code the
command-line tools use (tool/corpus/source.py), so what it saves is exactly
what fmt.py writes and what it checks is exactly what validate.py checks.
Standard library only. It listens on localhost and requires a per-run token
on every API call, so other pages in your browser can't write to the corpus.
"""
import argparse
import atexit
import collections
import os as _os
import re
import signal
import time
import json
import mimetypes
import os
import secrets
import subprocess
import sys
import threading
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.dirname(HERE))
import source  # noqa: E402
import edit  # noqa: E402
import agent  # noqa: E402

STATIC = os.path.join(HERE, 'static')
FONTS = os.path.join(source.ROOT, 'assets', 'fonts')
TOKEN = secrets.token_urlsafe(16)
LOCK = threading.Lock()

COMMANDS = {
    'fmt': ([sys.executable, 'tool/corpus/fmt.py'], source.ROOT, 120),
    'validate': ([sys.executable, 'tool/corpus/validate.py'], source.ROOT, 300),
    'build': ([sys.executable, 'tool/corpus/build_assets.py'], source.ROOT, 600),
    'test': (['flutter', 'test'], os.path.join(source.ROOT, 'packages', 'siddur_engine'), 1200),
}



class AppRunner:
    """The real Flutter app, built for the web (profile) and served beside
    the editor, so the text is seen in the reader itself. The corpus asset is
    read live from assets/corpus on every request, so a save only needs the
    asset rebuilt and the page reloaded: no dev server, no hot restart (which
    does not refresh a changed asset). Code changes need `rebuild`."""

    BUILD = os.path.join(source.ROOT, 'build', 'amud-preview')

    def __init__(self, port):
        self.port = port
        self.httpd = None
        self.proc = None
        self.state = 'stopped'      # stopped | building | ready | error
        self.log = collections.deque(maxlen=400)
        self.lock = threading.Lock()

    def built(self):
        return os.path.isfile(os.path.join(self.BUILD, 'index.html'))

    def stale(self):
        """Dart code newer than the build."""
        if not self.built():
            return False
        t0 = os.stat(os.path.join(self.BUILD, 'index.html')).st_mtime
        for root in ('lib', os.path.join('packages', 'siddur_engine', 'lib')):
            for dp, _, fs in os.walk(os.path.join(source.ROOT, root)):
                if any(f.endswith('.dart') and os.stat(os.path.join(dp, f)).st_mtime > t0 for f in fs):
                    return True
        return False

    def _serve(self):
        if self.httpd:
            return
        build, root = self.BUILD, source.ROOT

        class H(BaseHTTPRequestHandler):
            def log_message(self, *a):
                pass

            def do_GET(self):
                path = urlparse(self.path).path
                rel = path.lstrip('/') or 'index.html'
                m = re.search(r'assets/assets/corpus/([\w.]+\.json\.gz)$', rel)
                if m:                       # always the latest build_assets output
                    full = os.path.join(root, 'assets', 'corpus', m.group(1))
                else:
                    full = os.path.realpath(os.path.join(build, rel))
                    if not full.startswith(os.path.realpath(build) + os.sep) or rel.endswith(('sw.js', 'flutter_service_worker.js')):
                        full = ''
                if not full or not os.path.isfile(full):
                    self.send_response(404)
                    self.send_header('Content-Length', '0')
                    self.end_headers()
                    return
                ctype = mimetypes.guess_type(full)[0] or 'application/octet-stream'
                if full.endswith('.wasm'):
                    ctype = 'application/wasm'
                with open(full, 'rb') as fh:
                    body = fh.read()
                self.send_response(200)
                self.send_header('Content-Type', ctype)
                self.send_header('Content-Length', str(len(body)))
                self.send_header('Cache-Control', 'no-store')
                self.send_header('Cross-Origin-Opener-Policy', 'same-origin')
                self.send_header('Cross-Origin-Embedder-Policy', 'credentialless')
                self.end_headers()
                self.wfile.write(body)

        self.httpd = ThreadingHTTPServer(('127.0.0.1', self.port), H)
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def start(self):
        with self.lock:
            if self.state == 'building':
                return
            if self.built():
                self._serve()
                self.state = 'ready'
                return
        self.rebuild()

    def rebuild(self):
        with self.lock:
            if self.state == 'building':
                return
            self.state = 'building'
            self.log.clear()
            self.log.append('building the app for the web (a few minutes the first time)…')
        threading.Thread(target=self._build, daemon=True).start()

    def _build(self):
        r = subprocess.run([sys.executable, 'tool/corpus/build_assets.py'], cwd=source.ROOT, capture_output=True, text=True)
        if r.returncode:
            self.state = 'error'
            self.log.extend((r.stdout + r.stderr).splitlines()[-30:])
            return
        cmd = ['flutter', 'build', 'web', '--profile', '--no-web-resources-cdn', '--no-source-maps', '--base-href', '/', '-o', self.BUILD]
        self.proc = subprocess.Popen(cmd, cwd=source.ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, start_new_session=True)
        for line in self.proc.stdout:
            line = re.sub(r'\x1b\[[0-9;?]*[A-Za-z]', '', line).rstrip()
            if line:
                self.log.append(line)
        code = self.proc.wait()
        self.proc = None
        if code == 0 and self.built():
            self._serve()
            self.state = 'ready'
        elif self.state != 'stopped':
            self.state = 'error'

    def stop(self):
        if self.proc and self.proc.poll() is None:
            try:
                _os.killpg(self.proc.pid, signal.SIGTERM)
            except ProcessLookupError:
                pass
        if self.httpd:
            self.httpd.shutdown()
            self.httpd.server_close()
            self.httpd = None
        self.state = 'stopped'

    def sync(self, nusach=None):
        """Rebuilds the asset(s); the page then reloads and reads them."""
        cmd = [sys.executable, 'tool/corpus/build_assets.py'] + ([nusach] if nusach else [])
        r = subprocess.run(cmd, cwd=source.ROOT, capture_output=True, text=True)
        return {'ok': r.returncode == 0, 'output': (r.stdout + r.stderr)[-4000:]}

    def status(self):
        return {'state': self.state, 'url': f'http://127.0.0.1:{self.port}/', 'log': list(self.log)[-25:],
                'built': self.built(), 'stale': self.stale()}


class AgentRun:
    """One run of tool/corpus/agent.py at a time, its output kept for the editor."""

    def __init__(self):
        self.proc = None
        self.log = collections.deque(maxlen=300)
        self.started = None
        self.task = ''
        self.code = None

    def start(self, task, nusach, scope, model, each=False):
        if self.proc and self.proc.poll() is None:
            raise Fail(409, 'the agent is already running')
        cmd = [sys.executable, '-u', os.path.join(os.path.dirname(HERE), 'agent.py'), '--propose', '-n', nusach]
        if each:
            cmd += ['--each', scope or '']
        elif scope:
            cmd += ['--scope', scope]
        if model and model != 'auto':
            cmd += ['--model', model]
        cmd.append(task)
        self.log.clear()
        self.task, self.code, self.started = task, None, time.time()
        self.proc = subprocess.Popen(cmd, cwd=source.ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
        threading.Thread(target=self._pump, daemon=True).start()

    def _pump(self):
        for line in self.proc.stdout:
            self.log.append(line.rstrip())
        self.code = self.proc.wait()

    def stop(self):
        if self.proc and self.proc.poll() is None:
            self.proc.terminate()

    def status(self):
        return {'running': bool(self.proc and self.proc.poll() is None), 'code': self.code, 'task': self.task,
                'log': list(self.log), 'hasKey': bool(os.environ.get('OPENROUTER_API_KEY') or os.path.isfile(agent.KEY_FILE))}


AGENT = AgentRun()

APP = None


class Fail(Exception):
    def __init__(self, status, message, **extra):
        super().__init__(message)
        self.status, self.extra = status, extra


def nusach_dir(n):
    if n not in source.nusachim():
        raise Fail(404, f'no siddur {n!r}')
    return os.path.join(source.SIDDUR, n)


def chunk_path(n, name):
    if os.path.basename(name) != name or not name.endswith('.json') or name == 'book.json':
        raise Fail(400, f'bad file name {name!r}')
    p = os.path.join(nusach_dir(n), name)
    if not os.path.isfile(p):
        raise Fail(404, f'no file {name!r}')
    return p


def mtime(p):
    return os.stat(p).st_mtime_ns // 1000  # microseconds: exact in a JS number


def read_json(p):
    with open(p, encoding='utf-8') as f:
        return json.load(f)


def atomic_write(p, text):
    tmp = p + '.editor-tmp'
    with open(tmp, 'w', encoding='utf-8') as f:
        f.write(text)
    os.replace(tmp, p)


def reference():
    return {
        'nusachim': source.nusachim(),
        'variables': read_json(os.path.join(source.CORPUS, 'variables.json')),
        'nodes': read_json(os.path.join(source.CORPUS, 'nodes.json')),
        'labels': source.labels(),
        'enums': {
            'kinds': sorted(source.KINDS), 'roles': sorted(source.ROLES), 'voices': sorted(source.VOICES),
            'amidah': sorted(source.AMIDAH), 'services': sorted(source.SERVICES),
            'gestures': sorted(source.GESTURES),
        },
        'fields': {'part': source.PART_FIELDS, 'seg': source.SEG_FIELDS, 'leaf': source.LEAF_FIELDS},
        'fonts': sorted(f for f in os.listdir(FONTS) if f.lower().endswith(('.ttf', '.otf'))) if os.path.isdir(FONTS) else [],
    }


def load_siddur(n):
    d = nusach_dir(n)
    book_p = os.path.join(d, 'book.json')
    chunks = []
    for p in source.files(n):
        try:
            chunks.append({'file': os.path.basename(p), 'mtime': mtime(p), 'doc': read_json(p)})
        except json.JSONDecodeError as e:
            chunks.append({'file': os.path.basename(p), 'mtime': mtime(p), 'doc': None,
                           'error': f'not valid JSON: {e}', 'raw': open(p, encoding='utf-8').read()})
    return {'book': read_json(book_p), 'bookMtime': mtime(book_p), 'chunks': chunks}


def mtimes(n):
    d = nusach_dir(n)
    out = {os.path.basename(p): mtime(p) for p in source.files(n)}
    out['book.json'] = mtime(os.path.join(d, 'book.json'))
    return out


def validate_chunk(n, name, doc, book):
    """Problems per leaf: [{leaf, level, msg}] and the book's own."""
    known = source.VARIABLES | set(source.labels())
    seen, others = {}, []
    for p in source.files(n):
        fn = os.path.basename(p)
        if fn == name:
            continue
        try:
            d = read_json(p)
        except json.JSONDecodeError:
            continue
        others.append((p, d))
        for leaf in d.get('leaves', []):
            if 'path' in leaf:
                seen[leaf['path']] = p
    path = os.path.join(nusach_dir(n), name)
    out = []
    if not isinstance(doc, dict):
        return {'items': [{'leaf': -1, 'level': 'error', 'msg': 'the file is not a JSON object'}], 'book': []}
    for k in ('book', 'chunk'):
        if k not in doc:
            out.append({'leaf': -1, 'level': 'error', 'msg': f'missing {k!r}'})
    for i, leaf in enumerate(doc.get('leaves', [])):
        sub = {'book': doc.get('book'), 'chunk': doc.get('chunk'), 'leaves': [leaf]}
        errs, warns = source.check_file(path, sub, known, seen)
        out += [{'leaf': i, 'level': 'error', 'msg': m} for m in errs if not m.startswith("missing 'leaves'")]
        out += [{'leaf': i, 'level': 'warning', 'msg': m} for m in warns]
    book_items = []
    if book:
        chunks = others + [(path, doc)]
        e, w = source.check_book(book, chunks)
        book_items = [{'level': 'error', 'msg': m} for m in e] + [{'level': 'warning', 'msg': m} for m in w]
    return {'items': out, 'book': book_items}


def run_command(name):
    if name not in COMMANDS:
        raise Fail(400, f'unknown command {name!r}')
    cmd, cwd, timeout = COMMANDS[name]
    try:
        r = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True, timeout=timeout)
    except FileNotFoundError:
        return {'ok': False, 'output': f'{cmd[0]}: not found on PATH'}
    except subprocess.TimeoutExpired:
        return {'ok': False, 'output': f'timed out after {timeout}s'}
    return {'ok': r.returncode == 0, 'output': (r.stdout + r.stderr)[-20000:], 'code': r.returncode}


def git_diff(n, name):
    p = chunk_path(n, name) if name != 'book.json' else os.path.join(nusach_dir(n), 'book.json')
    r = subprocess.run(['git', 'diff', '--no-color', '-U1', '--', p], cwd=source.ROOT, capture_output=True, text=True)
    return r.stdout or '(no changes against git)'


# Handlers: (nusach-relative) pure functions of the request's JSON.

def api_get(path, q):
    if path == '/api/meta':
        return reference()
    if path == '/api/siddur':
        return load_siddur(q['nusach'][0])
    if path == '/api/app':
        return APP.status()
    if path == '/api/agent':
        return AGENT.status()
    if path == '/api/agent/tasks':
        d = os.path.join(os.path.dirname(HERE), 'agent_tasks')
        out = []
        for f in sorted(os.listdir(d)) if os.path.isdir(d) else []:
            if f.endswith('.md'):
                with open(os.path.join(d, f), encoding='utf-8') as fh:
                    out.append({'name': f[:-3].replace('_', ' '), 'text': fh.read().strip()})
        return {'tasks': out}
    if path == '/api/agent/models':
        try:
            return {'models': [{'id': m, 'context': c} for m, c, _ in agent.free_models()]}
        except Exception as e:
            raise Fail(502, f'could not list models: {e}')
    if path == '/api/proposals':
        return {'proposals': [{k: v for k, v in d.items() if k != 'files'} | {'files': sorted(d['files'])} for d in edit.list_proposals(None)[:30]]}
    if path == '/api/mtimes':
        return mtimes(q['nusach'][0])
    if path == '/api/diff':
        return {'diff': git_diff(q['nusach'][0], q['file'][0])}
    raise Fail(404, 'no such endpoint')


def api_post(path, body):
    if path == '/api/validate':
        return validate_chunk(body['nusach'], body['file'], body['doc'], body.get('book'))
    if path == '/api/validate_all':
        _, chunks, errs, warns = source.load(body['nusach'])
        return {'errors': errs, 'warnings': warns}
    if path == '/api/dumps':
        return {'text': source.dumps(body['doc'])}
    if path == '/api/condition':
        e = source.check_condition(body['expr'], source.VARIABLES | set(source.labels()))
        return {'error': e}
    if path == '/api/save':
        p = chunk_path(body['nusach'], body['file'])
        with LOCK:
            if not body.get('force') and mtime(p) != body['mtime']:
                raise Fail(409, f'{body["file"]} changed on disk since it was loaded')
            doc = body['doc']
            if not isinstance(doc, dict) or not isinstance(doc.get('leaves'), list):
                raise Fail(400, 'not a chunk file (needs book, chunk, leaves)')
            atomic_write(p, source.dumps(doc))
            return {'mtime': mtime(p)}
    if path == '/api/save_raw':
        p = chunk_path(body['nusach'], body['file'])
        with LOCK:
            if not body.get('force') and mtime(p) != body['mtime']:
                raise Fail(409, f'{body["file"]} changed on disk since it was loaded')
            try:
                json.loads(body['raw'])
            except json.JSONDecodeError as e:
                raise Fail(400, f'not valid JSON: {e}')
            atomic_write(p, body['raw'])
            return {'mtime': mtime(p)}
    if path == '/api/save_book':
        p = os.path.join(nusach_dir(body['nusach']), 'book.json')
        with LOCK:
            if not body.get('force') and mtime(p) != body['mtime']:
                raise Fail(409, 'book.json changed on disk since it was loaded')
            atomic_write(p, json.dumps(body['book'], ensure_ascii=False, indent=2) + '\n')
            return {'mtime': mtime(p)}
    if path == '/api/label':
        p = os.path.join(source.CORPUS, 'labels.json')
        key, label = body['key'], body['label']
        if not key.startswith('if_') or not key.replace('_', '').isalnum():
            raise Fail(400, 'a label key looks like if_something')
        with LOCK:
            labels = read_json(p)
            labels[key] = label
            atomic_write(p, json.dumps(dict(sorted(labels.items())), ensure_ascii=False, indent=2) + '\n')
        return {'labels': labels}
    if path == '/api/node':
        p = os.path.join(source.CORPUS, 'nodes.json')
        with LOCK:
            nodes = read_json(p)
            nodes[body['key']] = {'en': body['en'], 'he': body['he']}
            atomic_write(p, json.dumps(nodes, ensure_ascii=False, indent=1))
        return {'nodes': nodes}
    if path == '/api/agent/start':
        AGENT.start(body['task'], body['nusach'], body.get('scope'), body.get('model'), bool(body.get('each')))
        return AGENT.status()
    if path == '/api/agent/stop':
        AGENT.stop()
        return AGENT.status()
    if path == '/api/agent/key':
        key = body['key'].strip()
        if not key.startswith('sk-or-') or len(key) < 20:
            raise Fail(400, 'an OpenRouter key looks like sk-or-…')
        os.makedirs(os.path.dirname(agent.KEY_FILE), exist_ok=True)
        fd = os.open(agent.KEY_FILE, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
        with os.fdopen(fd, 'w') as fh:
            fh.write(key)
        return AGENT.status()
    if path == '/api/proposal':
        try:
            msg = edit.apply_proposal(body['id'], reject=body['action'] == 'reject')
        except edit.EditError as e:
            raise Fail(409, str(e))
        return {'message': msg}
    if path == '/api/app/start':
        APP.start()
        return APP.status()
    if path == '/api/app/stop':
        APP.stop()
        return APP.status()
    if path == '/api/app/rebuild':
        APP.rebuild()
        return APP.status()
    if path == '/api/app/sync':
        r = APP.sync(body.get('nusach'))
        return {**r, **APP.status()}
    if path == '/api/run':
        return run_command(body['cmd'])
    raise Fail(404, 'no such endpoint')


class Handler(BaseHTTPRequestHandler):
    server_version = 'AmudEditor'

    def log_message(self, fmt, *args):
        if '/api/mtimes' not in (args[0] if args else ''):
            sys.stderr.write('%s\n' % (fmt % args))

    def send(self, status, body, ctype='application/json; charset=utf-8', extra=None):
        if isinstance(body, (dict, list)):
            body = json.dumps(body, ensure_ascii=False).encode('utf-8')
        elif isinstance(body, str):
            body = body.encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Content-Length', str(len(body)))
        self.send_header('Cache-Control', 'no-store')
        for k, v in (extra or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def file(self, root, rel):
        p = os.path.realpath(os.path.join(root, rel))
        if not p.startswith(os.path.realpath(root) + os.sep) or not os.path.isfile(p):
            return self.send(404, {'error': 'not found'})
        ctype = mimetypes.guess_type(p)[0] or 'application/octet-stream'
        with open(p, 'rb') as f:
            self.send(200, f.read(), ctype)

    def authorized(self):
        return secrets.compare_digest(self.headers.get('X-Token', ''), TOKEN) and \
            self.headers.get('Host', '').split(':')[0] in ('127.0.0.1', 'localhost')

    def dispatch(self, fn):
        try:
            if not self.authorized():
                raise Fail(403, 'bad token')
            self.send(200, fn())
        except Fail as e:
            self.send(e.status, {'error': str(e), **e.extra})
        except KeyError as e:
            self.send(400, {'error': f'missing {e}'})
        except Exception as e:  # report instead of dropping the connection
            self.send(500, {'error': f'{type(e).__name__}: {e}'})

    def do_GET(self):
        u = urlparse(self.path)
        if u.path == '/':
            with open(os.path.join(STATIC, 'index.html'), encoding='utf-8') as f:
                return self.send(200, f.read().replace('__TOKEN__', TOKEN), 'text/html; charset=utf-8')
        if u.path.startswith('/static/'):
            return self.file(STATIC, u.path[len('/static/'):])
        if u.path.startswith('/fonts/'):
            return self.file(FONTS, u.path[len('/fonts/'):])
        if u.path.startswith('/api/'):
            return self.dispatch(lambda: api_get(u.path, parse_qs(u.query)))
        self.send(404, {'error': 'not found'})

    def do_POST(self):
        u = urlparse(self.path)
        n = int(self.headers.get('Content-Length') or 0)
        raw = self.rfile.read(n)

        def go():
            try:
                body = json.loads(raw or b'{}')
            except json.JSONDecodeError:
                raise Fail(400, 'bad JSON body')
            return api_post(u.path, body)
        self.dispatch(go)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--port', type=int, default=8765)
    ap.add_argument('--no-open', action='store_true')
    ap.add_argument('--app-port', type=int, default=8766, help='port of the Flutter app preview')
    a = ap.parse_args()
    global APP
    APP = AppRunner(a.app_port)
    atexit.register(APP.stop)
    atexit.register(AGENT.stop)
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    srv = ThreadingHTTPServer(('127.0.0.1', a.port), Handler)
    url = f'http://127.0.0.1:{a.port}/'
    print(f'Amud corpus editor: {url}  (Ctrl+C to stop)')
    if not a.no_open:
        threading.Timer(0.5, lambda: webbrowser.open(url)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        print()


if __name__ == '__main__':
    main()
