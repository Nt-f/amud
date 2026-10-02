"""Optional same-origin Web Push scheduling service. No accounts or names stored.

A random bearer token owns each subscription. Reminder payloads are stored until
sent or deleted. VAPID keys and persistent SQLite path come from the environment.
"""
import hashlib
import ipaddress
import json
import os
import secrets
import sqlite3
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

DB_PATH = os.environ.get('PUSH_DB', '/data/push.sqlite')
PUBLIC_KEY = os.environ.get('VAPID_PUBLIC_KEY', '')
PRIVATE_KEY = os.environ.get('VAPID_PRIVATE_KEY', '')
CONTACT = os.environ.get('VAPID_CONTACT', 'mailto:admin@amud.page')
ORIGIN = os.environ.get('PUSH_PUBLIC_ORIGIN', 'https://amud.page')
TRUSTED_PROXIES = tuple(ipaddress.ip_network(value.strip())
                        for value in os.environ.get('PUSH_TRUSTED_PROXIES', '').split(',')
                        if value.strip())
MAX_BYTES = 128 * 1024
HOSTS = ('fcm.googleapis.com', 'updates.push.services.mozilla.com', 'web.push.apple.com')


def client_address(peer, forwarded, trusted_proxies=None):
    """Only the explicitly trusted nginx peer may supply a single client IP."""
    address = ipaddress.ip_address(peer)
    networks = TRUSTED_PROXIES if trusted_proxies is None else trusted_proxies
    if any(address in network for network in networks):
        if not forwarded:
            raise ValueError('Missing proxy client address')
        return str(ipaddress.ip_address(forwarded))
    return str(address)


def connection():
    db = sqlite3.connect(DB_PATH, timeout=15)
    db.execute('PRAGMA foreign_keys=ON')
    return db


def initialize():
    with connection() as db:
        db.execute('PRAGMA journal_mode=WAL')
        db.executescript('''
          CREATE TABLE IF NOT EXISTS subscriptions (
            id TEXT PRIMARY KEY, token_hash TEXT NOT NULL, endpoint TEXT UNIQUE NOT NULL,
            subscription TEXT NOT NULL, updated INTEGER NOT NULL
          );
          CREATE TABLE IF NOT EXISTS notifications (
            owner TEXT NOT NULL REFERENCES subscriptions(id) ON DELETE CASCADE,
            id INTEGER NOT NULL, fire_at INTEGER NOT NULL, payload TEXT NOT NULL,
            retry_at INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(owner,id)
          );
          CREATE INDEX IF NOT EXISTS due ON notifications(fire_at,retry_at);
        ''')


def validate_subscription(value):
    if not isinstance(value, dict):
        raise ValueError('Invalid subscription')
    endpoint = value.get('endpoint', '')
    uri = urlparse(endpoint)
    # Push endpoints are external network targets, so restrict them to known
    # browser services instead of allowing arbitrary server-side fetches.
    if uri.scheme != 'https' or uri.hostname not in HOSTS or uri.port not in (None, 443) or uri.username or len(endpoint) > 4096:
        raise ValueError('Unsupported push endpoint')
    keys = value.get('keys', {})
    if not isinstance(keys, dict) or not all(isinstance(keys.get(k), str) and 8 <= len(keys[k]) <= 256 for k in ('p256dh', 'auth')):
        raise ValueError('Invalid subscription keys')
    return {'endpoint': endpoint, 'keys': {k: keys[k] for k in ('p256dh', 'auth')}}


def validate_plan(value, now=None):
    now = int(time.time() * 1000) if now is None else now
    if not isinstance(value, list) or len(value) > 200:
        raise ValueError('Invalid reminder plan')
    result = []
    seen = set()
    for item in value:
        if not isinstance(item, dict) or type(item.get('id')) is not int or type(item.get('fireAt')) is not int:
            raise ValueError('Invalid reminder')
        if item['id'] in seen:
            raise ValueError('Duplicate reminder')
        seen.add(item['id'])
        if item['fireAt'] <= now:
            continue
        if item['fireAt'] > now + 370 * 86400000:
            raise ValueError('Reminder is too far ahead')
        title, body, route = (item.get(k, '') for k in ('title', 'body', 'route'))
        if not isinstance(title, str) or not isinstance(body, str) or len(title) > 256 or len(body) > 2048:
            raise ValueError('Invalid reminder text')
        if not isinstance(route, str) or not route.startswith('/') or route.startswith('//') or '\\' in route or len(route) > 2048:
            raise ValueError('Invalid reminder route')
        result.append((item['id'], item['fireAt'], json.dumps({'id': item['id'], 'title': title, 'body': body, 'route': route})))
    return result


def replace_plan(db, owner, plan):
    db.execute('DELETE FROM notifications WHERE owner=?', (owner,))
    db.executemany('INSERT INTO notifications(owner,id,fire_at,payload) VALUES(?,?,?,?)', [(owner, *item) for item in plan])
    db.execute('UPDATE subscriptions SET updated=? WHERE id=?', (int(time.time()), owner))


class Handler(BaseHTTPRequestHandler):
    registrations = {}
    quota_lock = threading.Lock()

    def log_message(self, *_):
        pass  # Subscription endpoints and bearer tokens never enter logs.

    def reply(self, status, value=None):
        body = b'' if value is None else json.dumps(value).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def authorized(self, db, owner):
        token = self.headers.get('Authorization', '').removeprefix('Bearer ')
        row = db.execute('SELECT token_hash FROM subscriptions WHERE id=?', (owner,)).fetchone()
        return bool(row and token and secrets.compare_digest(row[0], hashlib.sha256(token.encode()).hexdigest()))

    def do_GET(self):
        if self.path == '/config':
            self.reply(200 if PUBLIC_KEY and PRIVATE_KEY else 503, {'publicKey': PUBLIC_KEY} if PUBLIC_KEY and PRIVATE_KEY else {'error': 'Push is not configured'})
        else:
            self.reply(404)

    def mutate(self, method):
        if self.headers.get('Origin') != ORIGIN:
            self.reply(403); return
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if length < 0 or length > MAX_BYTES:
                self.reply(413); return
            payload = json.loads(self.rfile.read(length)) if length else {}
            if not isinstance(payload, dict):
                raise ValueError('Invalid body')
            with connection() as db:
                if self.path == '/subscriptions' and method == 'POST':
                    subscription = validate_subscription(payload.get('subscription'))
                    plan = validate_plan(payload.get('plan', []))
                    existing = db.execute('SELECT id FROM subscriptions WHERE endpoint=?', (subscription['endpoint'],)).fetchone()
                    if existing:
                        if not self.authorized(db, existing[0]):
                            self.reply(409); return
                        owner = existing[0]
                        token = self.headers['Authorization'].removeprefix('Bearer ')
                    else:
                        with self.quota_lock:
                            address = client_address(self.client_address[0], self.headers.get('X-Amud-Client-IP'))
                            now = time.time()
                            recent = [t for t in self.registrations.get(address, []) if t > now - 3600]
                            if len(recent) >= 10:
                                self.reply(429); return
                            self.registrations[address] = [*recent, now]
                        if db.execute('SELECT COUNT(*) FROM subscriptions').fetchone()[0] >= 10000:
                            self.reply(503); return
                        owner, token = secrets.token_urlsafe(18), secrets.token_urlsafe(32)
                        db.execute('INSERT INTO subscriptions VALUES(?,?,?,?,?)', (owner, hashlib.sha256(token.encode()).hexdigest(), subscription['endpoint'], json.dumps(subscription), int(time.time())))
                    replace_plan(db, owner, plan)
                    self.reply(200, {'id': owner, 'token': token})
                elif self.path.startswith('/subscriptions/'):
                    owner = self.path.removeprefix('/subscriptions/')
                    if not self.authorized(db, owner):
                        self.reply(403); return
                    if method == 'PUT':
                        replace_plan(db, owner, validate_plan(payload.get('plan')))
                        self.reply(200, {'ok': True})
                    elif method == 'DELETE':
                        db.execute('DELETE FROM subscriptions WHERE id=?', (owner,))
                        self.reply(204)
                    else:
                        self.reply(405)
                else:
                    self.reply(404)
        except (ValueError, TypeError, KeyError):
            self.reply(400, {'error': 'Invalid request'})

    def do_POST(self): self.mutate('POST')
    def do_PUT(self): self.mutate('PUT')
    def do_DELETE(self): self.mutate('DELETE')


def deliver():
    from pywebpush import webpush, WebPushException
    while True:
        now = int(time.time() * 1000)
        with connection() as db:
            db.execute('DELETE FROM notifications WHERE fire_at < ?', (now - 600000,))
            db.execute('DELETE FROM subscriptions WHERE updated < ?', (int(time.time()) - 400 * 86400,))
            rows = db.execute('SELECT n.owner,n.id,n.payload,s.subscription FROM notifications n JOIN subscriptions s ON s.id=n.owner WHERE n.fire_at <= ? AND n.retry_at <= ? LIMIT 100', (now, now)).fetchall()
        for owner, nid, payload, subscription in rows:
            try:
                webpush(json.loads(subscription), payload, vapid_private_key=PRIVATE_KEY,
                        vapid_claims={'sub': CONTACT}, ttl=600, timeout=10)
                with connection() as db:
                    db.execute('DELETE FROM notifications WHERE owner=? AND id=?', (owner, nid))
            except WebPushException as error:
                with connection() as db:
                    if error.response is not None and error.response.status_code in (404, 410):
                        db.execute('DELETE FROM subscriptions WHERE id=?', (owner,))
                    else:
                        db.execute('UPDATE notifications SET retry_at=? WHERE owner=? AND id=?', (now + 60000, owner, nid))
            except Exception:
                with connection() as db:
                    db.execute('UPDATE notifications SET retry_at=? WHERE owner=? AND id=?', (now + 60000, owner, nid))
        time.sleep(15)


if __name__ == '__main__':
    initialize()
    if PUBLIC_KEY and PRIVATE_KEY:
        threading.Thread(target=deliver, daemon=True).start()
    ThreadingHTTPServer(('0.0.0.0', 8080), Handler).serve_forever()
