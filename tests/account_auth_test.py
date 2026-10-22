"""Isolated fixtures only. No production users, passwords, sessions or database."""
import base64
import concurrent.futures
import hashlib
import importlib.util
import pathlib
import secrets
import sqlite3
import sys
import tempfile
import time
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("owner_account", ROOT / "server/account/app.py")
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)

ORIGIN = "https://owner.example.com"
PASSWORD = "isolated-fixture-password-strong"
UPSTREAM = "isolated-upstream-" + "x" * 48
OWNER = "fixture-owner"


def basic(username, password):
    return "Basic " + base64.b64encode((username + ":" + password).encode()).decode()


class AccountTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.app = module.create_app({
            "TESTING": True, "DATABASE": self.directory.name + "/account.sqlite3",
            "PUBLIC_ORIGIN": ORIGIN, "TRUSTED_HOSTS": ["owner.example.com"],
            "UPSTREAM_PASSWORD": UPSTREAM, "RATE_SECRET": "fixture-rate-" + "r" * 48,
            "LOGIN_LIMIT": 4, "BASIC_CACHE_SECONDS": 60,
        })
        self.client = self.app.test_client()
        self.token = secrets.token_urlsafe(32)
        with self.app.account_db() as connection:
            connection.executemany("INSERT INTO metadata VALUES(?,?)", [
                ("setup_hash", hashlib.sha256(self.token.encode()).hexdigest()),
                ("setup_expires", str(int(time.time()) + 3600))])
        self.csrf = self.client.get("/auth/status", base_url=ORIGIN).json["csrf"]

    def tearDown(self):
        self.directory.cleanup()

    def post(self, path, data, client=None, csrf=None, token=None, origin=ORIGIN):
        return (client or self.client).post(path, base_url=ORIGIN, json=data, headers={
            "Origin": origin, "X-CSRF-Token": self.csrf if csrf is None else csrf,
            "X-Setup-Token": self.token if token is None else token,
            "X-Client-IP": "192.0.2.10",
        })

    def create_owner(self):
        response = self.post("/auth/setup", {
            "username": OWNER, "password": PASSWORD, "confirmation": PASSWORD})
        self.assertEqual(response.status_code, 200)
        self.csrf = response.json["csrf"]
        return response

    def check(self, header="", client=None, ip="192.0.2.10"):
        return (client or self.client).get("/internal/check", base_url=ORIGIN,
            headers={"Authorization": header, "X-Client-IP": ip},
            environ_overrides={"REMOTE_ADDR": "127.0.0.1"})

    def test_only_hashed_password_token_and_session_at_rest(self):
        self.create_owner()
        with self.app.account_db() as connection:
            row = connection.execute("SELECT * FROM owner").fetchone()
            self.assertTrue(row["password_hash"].startswith("$argon2id$v=19$m=65536,t=3,p=1$"))
            self.assertNotIn(PASSWORD, row["password_hash"])
            self.assertTrue(module.PASSWORD_HASHER.verify(row["password_hash"], PASSWORD))
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM metadata").fetchone()[0], 0)
            sessions = list(connection.execute("SELECT * FROM sessions"))
        cookie = self.client.get_cookie(module.COOKIE, domain="owner.example.com")
        self.assertNotIn(cookie.value, str([tuple(row) for row in sessions]))
        raw = pathlib.Path(self.app.config["DATABASE"]).read_bytes()
        self.assertNotIn(PASSWORD.encode(), raw)
        self.assertNotIn(self.token.encode(), raw)

    def test_single_use_setup_and_no_public_registration(self):
        self.assertEqual(self.post("/auth/setup", {}, token="wrong").status_code, 403)
        self.create_owner()
        self.assertEqual(self.post("/auth/setup", {
            "username": "attacker", "password": PASSWORD, "confirmation": PASSWORD}).status_code, 404)
        self.assertEqual(self.client.get("/setup", base_url=ORIGIN).location, "/login")
        for path in ["/register", "/auth/register", "/signup"]:
            self.assertEqual(self.client.get(path, base_url=ORIGIN).status_code, 404)

    def test_csrf_origin_body_limits_and_methods(self):
        data = {"username": OWNER, "password": PASSWORD, "confirmation": PASSWORD}
        self.assertEqual(self.post("/auth/setup", data, csrf="wrong").status_code, 403)
        self.assertEqual(self.post("/auth/setup", data, origin="https://evil.example.com").status_code, 403)
        self.assertEqual(self.client.get("/auth/setup", base_url=ORIGIN).status_code, 405)
        self.assertEqual(self.client.post("/auth/setup", base_url=ORIGIN,
            data="x" * 9000, content_type="application/json",
            headers={"Origin": ORIGIN, "X-CSRF-Token": self.csrf}).status_code, 413)

    def test_expired_setup_token_fails_closed(self):
        with self.app.account_db() as connection:
            connection.execute("UPDATE metadata SET value='1' WHERE key='setup_expires'")
        self.assertEqual(self.post("/auth/setup", {
            "username": OWNER, "password": PASSWORD, "confirmation": PASSWORD}).status_code, 403)

    def test_password_and_username_validation(self):
        for username, password, confirmation in [
            ("a:b", PASSWORD, PASSWORD), ("ab", PASSWORD, PASSWORD),
            ("x" * 33, PASSWORD, PASSWORD), (OWNER, "short", "short"),
            (OWNER, "p" * 129, "p" * 129), (OWNER, PASSWORD, "different"),
            (OWNER, "line\nbreak-is-wrong", "line\nbreak-is-wrong")]:
            self.assertEqual(self.post("/auth/setup", {
                "username": username, "password": password, "confirmation": confirmation}).status_code, 400)

    def test_session_rotation_logout_and_expiration(self):
        anonymous = self.client.get_cookie(module.COOKIE, domain="owner.example.com").value
        response = self.create_owner()
        authenticated = self.client.get_cookie(module.COOKIE, domain="owner.example.com").value
        self.assertNotEqual(anonymous, authenticated)
        header = response.headers["Set-Cookie"]
        for flag in ["Secure", "HttpOnly", "SameSite=Strict", "Path=/"]:
            self.assertIn(flag, header)
        self.assertNotIn("Domain=", header)
        self.assertEqual(self.client.get("/", base_url=ORIGIN).status_code, 200)
        self.assertEqual(self.post("/auth/logout", {}).status_code, 200)
        self.assertEqual(self.client.get("/", base_url=ORIGIN).location, "/login")
        # A copied session cannot be replayed after server-side logout.
        other = self.app.test_client()
        other.set_cookie(module.COOKIE, authenticated, domain="owner.example.com")
        self.assertEqual(other.get("/", base_url=ORIGIN).location, "/login")

    def test_login_and_uniform_errors(self):
        self.create_owner()
        self.post("/auth/logout", {})
        self.csrf = self.client.get("/auth/status", base_url=ORIGIN).json["csrf"]
        for username, password in [(OWNER, "wrong-strong-password"),
                                   ("unknown-user", PASSWORD)]:
            response = self.post("/auth/login", {"username": username, "password": password})
            self.assertEqual(response.status_code, 401)
            self.assertEqual(response.json, {"error": "账号或密码不正确"})
        self.assertEqual(self.post("/auth/login", {"username": OWNER, "password": PASSWORD}).status_code, 200)

    def test_legacy_disabled_and_new_mobile_basic_works(self):
        legacy = basic("opencode", UPSTREAM)
        self.assertEqual(self.check(legacy).status_code, 204)
        self.create_owner()
        self.assertEqual(self.check(legacy).status_code, 401)
        response = self.check(basic(OWNER, PASSWORD), ip="192.0.2.11")
        self.assertEqual(response.status_code, 204)
        self.assertEqual(response.headers["X-OpenCode-Upstream-Authorization"], legacy)
        self.assertEqual(self.check(basic(OWNER, PASSWORD), ip="192.0.2.11").status_code, 204)
        for header in ["", "Bearer wrong", "Basic invalid", basic(OWNER, "wrong-password")]:
            self.assertEqual(self.check(header, ip="192.0.2.12").status_code, 401)

    def test_browser_cookie_never_authenticates_mobile_api(self):
        self.create_owner()
        self.assertEqual(self.check().status_code, 401)

    def test_login_rate_limit_survives_process_recreation(self):
        self.create_owner()
        for _ in range(4):
            self.assertEqual(self.post("/auth/login", {"username": OWNER, "password": "bad-password-value"}).status_code, 401)
        response = self.post("/auth/login", {"username": OWNER, "password": PASSWORD})
        self.assertEqual(response.status_code, 429)
        self.assertIn("Retry-After", response.headers)
        recreated = module.create_app(dict(self.app.config))
        other = recreated.test_client()
        csrf = other.get("/auth/status", base_url=ORIGIN).json["csrf"]
        response = other.post("/auth/login", base_url=ORIGIN,
            json={"username": OWNER, "password": PASSWORD},
            headers={"Origin": ORIGIN, "X-CSRF-Token": csrf, "X-Client-IP": "192.0.2.10"})
        self.assertEqual(response.status_code, 429)

    def test_basic_auth_cache_does_not_rehash_each_api_call(self):
        self.create_owner()
        header = basic(OWNER, PASSWORD)
        self.assertEqual(self.check(header).status_code, 204)
        original = module.PASSWORD_HASHER
        class NoVerify:
            def verify(self, *_):
                raise AssertionError("Cache miss caused an extra Argon2 operation")
        module.PASSWORD_HASHER = NoVerify()
        try:
            self.assertEqual(self.check(header).status_code, 204)
        finally:
            module.PASSWORD_HASHER = original

    def test_security_headers_unknown_hosts_and_external_internal_route(self):
        response = self.client.get("/login", base_url=ORIGIN)
        self.assertIn("frame-ancestors 'none'", response.headers["Content-Security-Policy"])
        self.assertEqual(response.headers["Referrer-Policy"], "no-referrer")
        self.assertIn("no-store", response.headers["Cache-Control"])
        self.assertEqual(self.client.get("/login", base_url="https://evil.example").status_code, 400)
        self.assertEqual(self.client.get("/internal/check", base_url=ORIGIN,
            environ_overrides={"REMOTE_ADDR": "192.0.2.1"}).status_code, 404)

    def test_racing_claims_only_create_one_owner(self):
        clients = [self.app.test_client(), self.app.test_client()]
        csrf = [client.get("/auth/status", base_url=ORIGIN).json["csrf"] for client in clients]
        def submit(index):
            return self.post("/auth/setup", {"username": "owner-" + str(index),
                "password": PASSWORD, "confirmation": PASSWORD},
                client=clients[index], csrf=csrf[index]).status_code
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            statuses = list(pool.map(submit, range(2)))
        self.assertEqual(sorted(statuses), [200, 404])
        with self.app.account_db() as connection:
            self.assertEqual(connection.execute("SELECT COUNT(*) FROM owner").fetchone()[0], 1)

if __name__ == "__main__":
    unittest.main(verbosity=2)
