#!/usr/bin/env python3
"""Test nginx proxy authentication on loopback.
Usage: proxy_auth.py /path/to/nginx [/path/to/envsubst]
"""
import base64
import http.client
import http.server
import os
from pathlib import Path
import shutil
import socket
import subprocess
import sys
import tempfile
import threading
import time

root = Path(__file__).resolve().parents[1]
nginx = str(Path(sys.argv[1]).resolve())
envsubst = sys.argv[2] if len(sys.argv) > 2 else shutil.which('envsubst')
assert envsubst, 'envsubst is required'
secret = 'internal-test-secret'
internal = 'Basic ' + base64.b64encode(('grin:' + secret).encode()).decode()
wallet = 'Basic ' + base64.b64encode(b'grin:wallet-test-key').decode()
received = []

class Upstream(http.server.BaseHTTPRequestHandler):
    def respond(self):
        self.rfile.read(int(self.headers.get('Content-Length', 0)))
        value = self.headers.get('Authorization')
        received.append((self.path, value))
        expected = wallet if self.path == '/wallet/v2/foreign' else internal
        self.send_response(200 if value == expected else 401)
        self.end_headers()
        self.wfile.write(b'{}')
    do_GET = respond
    do_POST = respond
    def log_message(self, *_):
        pass

upstream = http.server.ThreadingHTTPServer(('127.0.0.1', 0), Upstream)
threading.Thread(target=upstream.serve_forever, daemon=True).start()
try:
    with tempfile.TemporaryDirectory() as tmp:
        directory = Path(tmp)
        (directory / 'bin').mkdir()
        (directory / 'logs').mkdir()
        (directory / 'html').mkdir()
        (directory / 'html/grin-node-docker.html').write_text('dashboard')
        (directory / 'html/test.wasm').write_bytes(b'wasm')
        def script(name, text):
            p = directory / 'bin' / name
            p.write_text('#!/bin/sh\n' + text + '\n')
            p.chmod(0o755)
        script('getent', 'printf "%s trusted-proxy\\n" "$TEST_PROXY_IP"')
        script('sleep', 'exit 0')  # Only used by the entrypoint's DNS retry loop.
        script('nginx', 'exec "$TEST_NGINX" -p "$TEST_DIR/" -c "$TEST_DIR/nginx.conf" "$@"')
        (directory / 'bin/envsubst').symlink_to(Path(envsubst).resolve())
        with socket.socket() as sock:
            sock.bind(('127.0.0.1', 0))
            port = sock.getsockname()[1]
        template = (root / 'nginx.conf.template').read_text()
        template = template.replace('listen 80;', f'listen 127.0.0.1:{port};')
        template = template.replace('/usr/share/nginx/html', str(directory / 'html'))
        (directory / 'site.template').write_text(template)
        (directory / 'site.conf').write_text('old config')
        (directory / 'site.conf').chmod(0o644)
        (directory / 'nginx.conf').write_text('events {}\nhttp { access_log off; include ' + str(directory / 'site.conf') + '; }\n')
        entrypoint = (root / 'docker-entrypoint.sh').read_text()
        entrypoint = entrypoint.replace('/etc/nginx/conf.d/default.conf.template', str(directory / 'site.template'))
        entrypoint = entrypoint.replace('/etc/nginx/conf.d/default.conf', str(directory / 'site.conf'))
        (directory / 'entrypoint.sh').write_text(entrypoint)
        env = dict(os.environ, PATH=str(directory / 'bin') + ':' + os.environ['PATH'],
                   CONTROLLER_PROXY=f'127.0.0.1:{upstream.server_port}',
                   CONTROLLER_PASSWORD=secret, TRUSTED_PROXY_HOST='trusted-proxy',
                   TEST_PROXY_IP='127.0.0.1', TEST_DIR=str(directory), TEST_NGINX=nginx)
        def request(path, auth=None, extra=None, method='GET'):
            headers = dict(extra or {})
            if auth is not None:
                headers['Authorization'] = auth
            conn = http.client.HTTPConnection('127.0.0.1', port, timeout=3)
            try:
                conn.request(method, path, body=b'{}' if method == 'POST' else None, headers=headers)
                response = conn.getresponse()
                return response.status, response.read()
            finally:
                conn.close()
        for override in ({'CONTROLLER_PASSWORD': ''}, {'TRUSTED_PROXY_HOST': ''},
                         {'TRUSTED_PROXY_HOST': 'bad;host'}, {'TEST_PROXY_IP': 'not-an-ip'}):
            result = subprocess.run(['sh', str(directory / 'entrypoint.sh')], env=dict(env, **override),
                                    capture_output=True, timeout=5)
            assert result.returncode != 0, override
            assert secret.encode() not in result.stderr
        for trusted in (False, True):
            run_env = dict(env, TEST_PROXY_IP='127.0.0.1' if trusted else '127.0.0.2')
            process = subprocess.Popen(['sh', str(directory / 'entrypoint.sh')], env=run_env,
                                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            try:
                for _ in range(50):
                    if process.poll() is not None:
                        raise AssertionError(process.stderr.read().decode())
                    try:
                        request('/')
                        break
                    except ConnectionRefusedError:
                        time.sleep(0.1)
                else:
                    raise AssertionError('nginx did not start')
                if not trusted:
                    count = len(received)
                    for path in ('/', '/api/status', '/test.wasm', '/wallet/v2/foreign'):
                        assert request(path, internal, {'X-Forwarded-For': '127.0.0.2',
                                                       'X-Real-IP': '127.0.0.2'})[0] == 403, path
                    assert len(received) == count
                else:
                    assert request('/') == (200, b'dashboard')
                    assert request('/api/status')[0] == 200
                    assert received[-1] == ('/status', internal)
                    assert request('/api/status', 'Basic forged')[0] == 200
                    assert received[-1] == ('/status', internal)
                    for auth in (None, 'Basic wrong', internal, wallet):
                        assert request('/wallet/v2/foreign', auth, method='POST')[0] == (200 if auth == wallet else 401)
                        assert received[-1] == ('/wallet/v2/foreign', auth)
                    assert request('/wallet/v2/owner', wallet, method='POST')[0] == 404
                    assert request('/wallet/v2/foreign', wallet)[0] == 403
                    assert (directory / 'site.conf').stat().st_mode & 0o077 == 0
            finally:
                process.terminate()
                process.wait(timeout=5)
                process.stderr.close()
finally:
    upstream.shutdown()
    upstream.server_close()
print('Proxy auth checks passed: fail-closed startup, trusted TCP peer, header spoofing, management injection, wallet isolation.')
