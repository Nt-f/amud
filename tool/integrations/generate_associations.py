#!/usr/bin/env python3
"""Generate verified-link files using real release signing identities.

Example: python3 tool/integrations/generate_associations.py \
  --android-fingerprint AA:BB:... --apple-team-id ABCDE12345
"""
import argparse
import json
import re
from pathlib import Path

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--android-fingerprint', action='append', required=True)
parser.add_argument('--apple-team-id', required=True)
parser.add_argument('--output', type=Path, default=Path('landing/.well-known'))
args = parser.parse_args()
if not all(re.fullmatch(r'(?:[0-9A-Fa-f]{2}:){31}[0-9A-Fa-f]{2}', f) for f in args.android_fingerprint):
    parser.error('Each release SHA-256 fingerprint must contain 32 colon-separated bytes.')
if not re.fullmatch(r'[A-Z0-9]{10}', args.apple_team_id):
    parser.error('Apple team ID must contain ten uppercase letters or digits.')
args.output.mkdir(parents=True, exist_ok=True)
(args.output / 'assetlinks.json').write_text(json.dumps([{'relation': ['delegate_permission/common.handle_all_urls'],
 'target': {'namespace': 'android_app', 'package_name': 'page.amud', 'sha256_cert_fingerprints': [f.upper() for f in args.android_fingerprint]}}], indent=2) + '\n')
(args.output / 'apple-app-site-association').write_text(json.dumps({'applinks': {'apps': [], 'details': [
 {'appID': args.apple_team_id + '.page.amud', 'paths': ['/app/*']}] }}, indent=2) + '\n')
print('Generated assetlinks.json and apple-app-site-association in', args.output)
