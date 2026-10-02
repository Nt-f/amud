import ipaddress
import json
import threading
from http.client import HTTPConnection
from http.server import ThreadingHTTPServer
from unittest.mock import patch
import tempfile
import unittest
from pathlib import Path
import server


class PushPlanTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        server.DB_PATH = str(Path(self.temp.name) / 'push.sqlite')
        server.initialize()

    def item(self, **changes):
        return dict(id=1001, fireAt=2000, title='Reminder', body='Body', route='/pray/omer', **changes)

    def test_forwarded_addresses_require_a_trusted_peer_and_single_valid_ip(self):
        trusted = [ipaddress.ip_network('172.30.86.2/32')]
        self.assertEqual(server.client_address('172.30.86.2', '203.0.113.1', trusted), '203.0.113.1')
        self.assertEqual(server.client_address('172.30.86.2', '2001:db8::1', trusted), '2001:db8::1')
        self.assertEqual(server.client_address('203.0.113.2', '203.0.113.1', trusted), '203.0.113.2')
        for header in (None, 'invalid', '203.0.113.1, 203.0.113.2', '203.0.113.1:80'):
            with self.assertRaises(ValueError):
                server.client_address('172.30.86.2', header, trusted)

    def test_proxy_registration_quota_is_per_browser(self):
        httpd = ThreadingHTTPServer(('127.0.0.1', 0), server.Handler)
        worker = threading.Thread(target=httpd.serve_forever, daemon=True)
        worker.start()
        self.addCleanup(httpd.server_close)
        self.addCleanup(worker.join)
        self.addCleanup(httpd.shutdown)
        server.Handler.registrations = {}
        with patch.object(server, 'TRUSTED_PROXIES', (ipaddress.ip_network('127.0.0.1/32'),)):
            for index in range(12):
                body = json.dumps({'subscription': {'endpoint': f'https://fcm.googleapis.com/push/{index}',
                    'keys': {'p256dh': 'a' * 80, 'auth': 'b' * 24}}, 'plan': []})
                client = HTTPConnection(*httpd.server_address)
                try:
                    client.request('POST', '/subscriptions', body, headers={
                        'Origin': server.ORIGIN, 'Content-Type': 'application/json',
                        'X-Amud-Client-IP': '203.0.113.1' if index < 11 else '203.0.113.2'})
                    response = client.getresponse()
                    self.assertEqual(response.status, 429 if index == 10 else 200)
                    response.read()
                finally:
                    client.close()

    def test_expired_items_are_not_replayed(self):
        self.assertEqual(server.validate_plan([self.item()], now=3000), [])

    def test_routes_and_endpoints_cannot_target_external_servers(self):
        for route in ('//evil.example', 'https://evil.example', '/\\evil'):
            with self.assertRaises(ValueError):
                server.validate_plan([{**self.item(), 'route': route}], now=1000)
        with self.assertRaises(ValueError):
            server.validate_subscription({'endpoint': 'https://127.0.0.1/private', 'keys': {'p256dh': 'a' * 80, 'auth': 'b' * 24}})

    def test_replace_and_delete_cancel_old_reminders(self):
        with server.connection() as db:
            db.execute('INSERT INTO subscriptions VALUES(?,?,?,?,?)', ('owner', 'hash', 'endpoint', '{}', 1))
            server.replace_plan(db, 'owner', server.validate_plan([self.item()], now=1000))
            self.assertEqual(db.execute('SELECT COUNT(*) FROM notifications').fetchone()[0], 1)
            server.replace_plan(db, 'owner', [])
            self.assertEqual(db.execute('SELECT COUNT(*) FROM notifications').fetchone()[0], 0)
            server.replace_plan(db, 'owner', server.validate_plan([self.item()], now=1000))
            db.execute('DELETE FROM subscriptions WHERE id=?', ('owner',))
            self.assertEqual(db.execute('SELECT COUNT(*) FROM notifications').fetchone()[0], 0)

    def test_duplicate_ids_and_plans_beyond_a_year_are_rejected(self):
        with self.assertRaises(ValueError):
            server.validate_plan([self.item(), self.item()], now=1000)
        with self.assertRaises(ValueError):
            server.validate_plan([{**self.item(), 'fireAt': 371 * 86400000}], now=1000)


if __name__ == '__main__':
    unittest.main()
