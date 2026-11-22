#!/usr/bin/env python3
"""Exercise GA4 login with an entirely fake OAuth provider; print modes, never credential content."""
import json
import os
from pathlib import Path
import sys
import tempfile
from types import SimpleNamespace
from unittest.mock import patch
from urllib.parse import parse_qs, urlsplit

root = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(root / 'tools/telemetry'))
import ga4
state = {}
class FakeServer:
    def __init__(self, bind, handler):
        self.handler = handler
        self.timeout = None
    def __enter__(self):
        return self
    def __exit__(self, *args):
        return False
    def handle_request(self):
        self.handler.do_GET(SimpleNamespace(path='/?state=' + state['value'] + '&code=synthetic',
            send_response=lambda *a: None, end_headers=lambda: None, send_header=lambda *a: None,
            wfile=SimpleNamespace(write=lambda *a: None)))
def open_browser(url):
    state['value'] = parse_qs(urlsplit(url).query)['state'][0]
    return True
with tempfile.TemporaryDirectory(prefix='ga4-login-mode-', dir=os.environ["OPENRC_AUDIT_TMP"]) as d:
    base = Path(d)
    client = base / 'client.json'
    client.write_text(json.dumps({'installed': {'client_id': 'synthetic', 'client_secret': 'synthetic'}}))
    target = base / 'new-config-dir' / 'ga4-user.json'
    old = os.umask(0o022)
    try:
        with patch('http.server.HTTPServer', FakeServer), patch('webbrowser.open', open_browser), patch('builtins.print'):
            ga4.login(client, target, 'http://localhost:8085/', http=lambda *a, **kw: {'refresh_token': 'synthetic'})
    finally:
        os.umask(old)
    filemode = target.stat().st_mode & 0o777
    dirmode = target.parent.stat().st_mode & 0o777
    print(f'new configuration directory mode: {dirmode:04o}')
    print(f'credential file mode: {filemode:04o}')
    assert filemode == 0o644 and dirmode == 0o755
