"""Revokes the Apple Development certificates earlier CI runs left behind.

Each App Store archive runs on a fresh Mac with no certificate, so Xcode
(-allowProvisioningUpdates with the API key) creates a new development
certificate for it, and nothing removed them. At the account's limit the
archive fails with "Your account has reached the maximum number of
certificates". Certificates Xcode creates through the API are named
"Created via API"; only those are revoked, never one made in Xcode on a
Mac. Revoking a development certificate doesn't affect apps on the App
Store or TestFlight.

Reads ASC_KEY_PATH, ASC_KEY_ID and ASC_ISSUER_ID from the environment.
"""
import json
import os
import sys
import time
import urllib.request

import jwt

API = 'https://api.appstoreconnect.apple.com/v1'
DEVELOPMENT = {'DEVELOPMENT', 'IOS_DEVELOPMENT'}


def token():
    key = open(os.environ['ASC_KEY_PATH']).read()
    now = int(time.time())
    return jwt.encode(
        {'iss': os.environ['ASC_ISSUER_ID'], 'iat': now, 'exp': now + 600, 'aud': 'appstoreconnect-v1'},
        key, algorithm='ES256', headers={'kid': os.environ['ASC_KEY_ID'], 'typ': 'JWT'})


def call(method, url, auth):
    req = urllib.request.Request(url, method=method, headers={'Authorization': f'Bearer {auth}'})
    with urllib.request.urlopen(req) as r:
        body = r.read()
        return json.loads(body) if body else None


def main():
    auth = token()
    certs = call('GET', f'{API}/certificates?limit=200', auth)['data']
    revoked = 0
    for c in certs:
        a = c['attributes']
        ci = a.get('certificateType') in DEVELOPMENT and 'Created via API' in (a.get('name') or '')
        print(f"{'revoke' if ci else 'keep  '} {a.get('certificateType')} {a.get('name')!r} expires {a.get('expirationDate')}")
        if ci:
            call('DELETE', f"{API}/certificates/{c['id']}", auth)
            revoked += 1
    print(f'{revoked} development certificate(s) from CI revoked, {len(certs) - revoked} kept')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:  # The archive reports the real failure, if any.
        print(f'Could not clean up certificates: {e}', file=sys.stderr)
