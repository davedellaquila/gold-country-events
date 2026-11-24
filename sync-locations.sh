#!/usr/bin/env bash
# sync-locations.sh — publish the Places page to its own repo, byte-identical.
#
# locations.html in THIS repo (gold-country-events) is the single source of
# truth for the Places of the Gold Country page. It serves at two addresses:
#   - https://events.fiddletowngazette.com/locations.html   (this repo)
#   - https://locations.fiddletowngazette.com/              (gold-country-locations repo)
# Run this after ANY change to locations.html or the places icon assets.
# It copies the page + assets into davedellaquila/gold-country-locations via
# the GitHub Contents API and verifies every copied file is byte-identical,
# so the two copies cannot drift. Requires: gh (authenticated), python3.
set -euo pipefail
cd "$(dirname "$0")"
REPO="davedellaquila/gold-country-locations"
python3 - <<'EOF'
import subprocess, base64, json, hashlib, sys
REPO = 'davedellaquila/gold-country-locations'
PAIRS = [('locations.html', 'index.html'),
         ('icon-places.svg', 'icon-places.svg'),
         ('places-favicon.ico', 'places-favicon.ico'),
         ('places-favicon-16.png', 'places-favicon-16.png'),
         ('places-favicon-32.png', 'places-favicon-32.png'),
         ('places-apple-touch-icon.png', 'places-apple-touch-icon.png'),
         ('places-icon-192.png', 'places-icon-192.png'),
         ('places-icon-512.png', 'places-icon-512.png'),
         ('places.webmanifest', 'places.webmanifest')]

def gh(*args, inp=None):
    p = subprocess.run(['gh', 'api', *args], input=inp, capture_output=True)
    if p.returncode != 0:
        raise SystemExit(f"gh api {' '.join(args)} failed: {p.stderr.decode()[:300]}")
    return p.stdout

def remote_sha(path):
    out = gh(f'repos/{REPO}/contents/{path}', '--jq', '.sha')
    return out.decode().strip()

def remote_bytes(path):
    out = gh(f'repos/{REPO}/contents/{path}')
    return base64.b64decode(json.loads(out)['content'])

changed = 0
for src, dst in PAIRS:
    data = open(src, 'rb').read()
    try:
        cur = remote_bytes(dst)
    except SystemExit:
        cur = None
    if cur == data:
        print(f'  = {dst} (unchanged)')
        continue
    body = {'message': f'Sync {dst} from gold-country-events (single source)', 'content': base64.b64encode(data).decode()}
    if cur is not None:
        body['sha'] = remote_sha(dst)
    gh('-X', 'PUT', f'repos/{REPO}/contents/{dst}', '--input', '-', inp=json.dumps(body).encode())
    back = remote_bytes(dst)
    assert hashlib.sha256(back).hexdigest() == hashlib.sha256(data).hexdigest(), f'BYTE MISMATCH on {dst}'
    print(f'  -> {dst} (synced + verified, {len(data)} bytes)')
    changed += 1
print(f'sync-locations: done ({changed} file(s) updated)')
EOF
