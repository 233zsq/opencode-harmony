"""Run on Linux with Nginx. Everything binds to loopback with fixture-only secrets."""
import base64
import hashlib
import http.server
import importlib.util
import json
import os
import pathlib
import secrets
import shutil
import socket
import subprocess
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from wsgiref.simple_server import WSGIRequestHandler, make_server

ROOT = pathlib.Path(__file__).resolve().parents[1]

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

account = load("proxy_account", ROOT / "server/account/app.py")
renderer = load("account_renderer", ROOT / "scripts/prepare-account-entry.py")
traffic_renderer = load("traffic_renderer", ROOT / "scripts/prepare-traffic-entry.py")

def port():
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]

class Quiet(WSGIRequestHandler):
    def log_message(self, *_): pass

class ProxyTest(unittest.TestCase):
    @unittest.skipUnless(shutil.which("nginx") or pathlib.Path("/usr/sbin/nginx").exists(), "Linux Nginx required")
    def test_real_nginx_auth_subrequest_and_upstream_rewrite(self):
        with tempfile.TemporaryDirectory() as directory:
            root = pathlib.Path(directory)
            secret = "fixture-upstream-" + secrets.token_hex(32)
            expected = "Basic " + base64.b64encode(("opencode:" + secret).encode()).decode()
            app = account.create_app({
                "TESTING": True, "DATABASE": str(root / "fixture.sqlite3"),
                "PUBLIC_ORIGIN": "https://opencode.bigdogaaa.cn",
                "UPSTREAM_PASSWORD": secret, "RATE_SECRET": secrets.token_hex(32),
                "HISTORY_FETCH": lambda _: {"data": []},
            })
            token = secrets.token_urlsafe(32)
            with app.account_db() as db:
                db.executemany("INSERT INTO metadata VALUES(?,?)", [
                    ("setup_hash", hashlib.sha256(token.encode()).hexdigest()),
                    ("setup_expires", str(int(time.time()) + 300))])
            auth = make_server("127.0.0.1", 0, app, handler_class=Quiet)
            class Upstream(http.server.BaseHTTPRequestHandler):
                def log_message(self, *_): pass
                def do_GET(self):
                    ok = self.headers.get("Authorization") == expected and not self.headers.get("Cookie")
                    body = json.dumps({"ok": ok}).encode()
                    self.send_response(200 if ok else 403)
                    self.send_header("Content-Type", "application/json")
                    self.send_header("Content-Length", str(len(body)))
                    self.end_headers()
                    self.wfile.write(body)
            backend = http.server.HTTPServer(("127.0.0.1", 0), Upstream)
            threading.Thread(target=auth.serve_forever, daemon=True).start()
            threading.Thread(target=backend.serve_forever, daemon=True).start()
            front = port()
            auth_location = renderer.AUTH_LOCATION.replace("127.0.0.1:4099", "127.0.0.1:" + str(auth.server_port))
            location = """
                location /api/ {
                  auth_request /_opencode_auth;
                  auth_request_set $account_upstream_auth $upstream_http_x_opencode_upstream_authorization;
                  proxy_set_header Authorization $account_upstream_auth;
                  proxy_set_header Cookie "";
                  proxy_pass http://127.0.0.1:BACKEND;
                }
            """.replace("BACKEND", str(backend.server_port))
            location += traffic_renderer.THIN_LOCATION.replace("127.0.0.1:4099", "127.0.0.1:" + str(auth.server_port))
            config = root / "nginx.conf"
            config.write_text("""
                pid PATH/nginx.pid;
                error_log stderr warn;
                events { worker_connections 32; }
                http {
                  access_log off;
                  client_body_temp_path PATH/body;
                  proxy_temp_path PATH/proxy;
                  server {
                    listen 127.0.0.1:FRONT;
                    AUTH
                    LOCATION
                    location / { return 404; }
                  }
                }
            """.replace("PATH", str(root)).replace("FRONT", str(front))
               .replace("AUTH", auth_location).replace("LOCATION", location))
            binary = shutil.which("nginx") or "/usr/sbin/nginx"
            process = subprocess.Popen([binary, "-p", str(root) + "/", "-c", str(config),
                                        "-g", "daemon off;"], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
            def get(path, header="", cookie=""):
                request = urllib.request.Request("http://127.0.0.1:" + str(front) + path,
                    headers={"Authorization": header, "Cookie": cookie,
                             "X-OpenCode-Upstream-Authorization": expected})
                try:
                    response = urllib.request.urlopen(request, timeout=3)
                except urllib.error.HTTPError as error:
                    response = error
                with response:
                    return response.status, response.read()
            try:
                for _ in range(50):
                    try:
                        initial = get("/api/probe", expected)
                        break
                    except OSError:
                        time.sleep(.05)
                self.assertEqual(initial[0], 200)
                client = app.test_client()
                origin = "https://opencode.bigdogaaa.cn"
                csrf = client.get("/auth/status", base_url=origin).json["csrf"]
                password = "proxy-fixture-password-strong"
                response = client.post("/auth/setup", base_url=origin,
                    json={"username": "proxy-owner", "password": password, "confirmation": password},
                    headers={"Origin": origin, "X-CSRF-Token": csrf, "X-Setup-Token": token})
                self.assertEqual(response.status_code, 200)
                new = "Basic " + base64.b64encode(("proxy-owner:" + password).encode()).decode()
                self.assertEqual(get("/api/probe", new)[0], 200)
                self.assertEqual(get("/api/probe", expected)[0], 401)
                self.assertEqual(get("/api/probe")[0], 401)
                cookie = client.get_cookie(account.COOKIE, domain="opencode.bigdogaaa.cn").value
                self.assertEqual(get("/api/probe", cookie=account.COOKIE + "=" + cookie)[0], 401)
                self.assertEqual(get("/_opencode_auth", new)[0], 404)
                self.assertEqual(get("/client-cache/capabilities", new)[0], 200)
                self.assertEqual(json.loads(get("/client-cache/session/ses_fixture/message", new)[1]), {"data": []})
                for header in ["", expected]:
                    self.assertEqual(get("/client-cache/capabilities", header)[0], 401)
                self.assertEqual(get("/client-cache/capabilities", cookie=account.COOKIE + "=" + cookie)[0], 401)
            finally:
                process.terminate()
                process.communicate(timeout=5)
                auth.shutdown(); backend.shutdown()
                auth.server_close(); backend.server_close()

if __name__ == "__main__":
    unittest.main(verbosity=2)
