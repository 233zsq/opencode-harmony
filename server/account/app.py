"""Private, single-owner web login and Basic-auth gateway for OpenCode.

Run behind the supplied loopback-only Nginx configuration. Never expose Gunicorn.
The mobile API accepts Basic credentials, not browser session cookies.
"""
import base64
import hashlib
import hmac
import json
import urllib.request
import urllib.error
import urllib.parse
import os
import re
import secrets
import sqlite3
import threading
import time
from contextlib import contextmanager
from pathlib import Path

from argon2 import PasswordHasher, Type
from argon2.exceptions import VerificationError, InvalidHashError
from flask import Flask, abort, g, jsonify, redirect, render_template, request

COOKIE = "__Host-oc_session"
USERNAME = re.compile(r"[A-Za-z0-9][A-Za-z0-9_.-]{2,31}\Z")
PASSWORD_HASHER = PasswordHasher(time_cost=3, memory_cost=65536, parallelism=1,
                                 hash_len=32, salt_len=16, type=Type.ID)
HASH_SLOTS = threading.BoundedSemaphore(2)


def create_app(config=None):
    app = Flask(__name__, root_path=str(Path(__file__).resolve().parent), static_url_path="/assets")
    app.config.update(
        DATABASE=os.environ.get("ACCOUNT_DATABASE", "/var/lib/opencode-account/account.sqlite3"),
        PUBLIC_ORIGIN=os.environ.get("ACCOUNT_ORIGIN", "https://opencode.bigdogaaa.cn"),
        UPSTREAM_PASSWORD=os.environ.get("OPENCODE_PASSWORD", ""),
        RATE_SECRET=os.environ.get("ACCOUNT_RATE_SECRET", ""),
        TRUSTED_HOSTS=["opencode.bigdogaaa.cn"],
        MAX_CONTENT_LENGTH=8192,
        SESSION_SECONDS=12 * 3600,
        PREAUTH_SECONDS=20 * 60,
        LOGIN_LIMIT=8,
        RATE_SECONDS=15 * 60,
        BASIC_CACHE_SECONDS=60,
    )
    if config:
        app.config.update(config)
    app.json.ensure_ascii = False
    if len(app.config["UPSTREAM_PASSWORD"]) < 40 or len(app.config["RATE_SECRET"]) < 40:
        raise RuntimeError("Private upstream credential and rate key required")
    if not app.config["PUBLIC_ORIGIN"].startswith("https://"):
        raise RuntimeError("HTTPS origin required")
    upstream = "Basic " + base64.b64encode(
        ("opencode:" + app.config["UPSTREAM_PASSWORD"]).encode()).decode()
    rate_key = app.config["RATE_SECRET"].encode()
    cache_key = secrets.token_bytes(32)
    cache, cache_lock = {}, threading.Lock()

    @contextmanager
    def db():
        connection = sqlite3.connect(app.config["DATABASE"], timeout=5, isolation_level=None)
        connection.row_factory = sqlite3.Row
        try:
            yield connection
        finally:
            connection.close()

    def initialize():
        path = Path(app.config["DATABASE"])
        path.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
        with db() as connection:
            connection.executescript("""
                PRAGMA journal_mode=WAL;
                CREATE TABLE IF NOT EXISTS owner (
                    id INTEGER PRIMARY KEY CHECK (id=1), username TEXT NOT NULL UNIQUE,
                    password_hash TEXT NOT NULL, created INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS sessions (
                    token_hash TEXT PRIMARY KEY, username TEXT, csrf TEXT NOT NULL,
                    created INTEGER NOT NULL, expires INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS attempts (
                    key TEXT PRIMARY KEY, started INTEGER NOT NULL, failures INTEGER NOT NULL);
            """)
        os.chmod(path, 0o600)

    initialize()
    app.account_db = db

    def owner():
        with db() as connection:
            return connection.execute("SELECT * FROM owner WHERE id=1").fetchone()

    def digest(token):
        return hashlib.sha256(token.encode()).hexdigest()

    def now():
        return int(time.time())

    def attempt_key():
        # Nginx overwrites this header; the application only listens on loopback.
        address = request.headers.get("X-Client-IP", request.remote_addr or "")
        return hmac.new(rate_key, ("login:" + address).encode(), hashlib.sha256).hexdigest()

    def blocked():
        with db() as connection:
            row = connection.execute("SELECT * FROM attempts WHERE key=?", (attempt_key(),)).fetchone()
        return bool(row and now() - row["started"] < app.config["RATE_SECONDS"]
                    and row["failures"] >= app.config["LOGIN_LIMIT"])

    def failure():
        stamp = now()
        with db() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("DELETE FROM attempts WHERE started < ?",
                               (stamp - app.config["RATE_SECONDS"],))
            # Global row bound; never evict live rate limits to make room for new IPs.
            count = connection.execute("SELECT COUNT(*) FROM attempts").fetchone()[0]
            if count >= 10000 and not connection.execute(
                    "SELECT 1 FROM attempts WHERE key=?", (attempt_key(),)).fetchone():
                connection.rollback()
                abort(429)
            connection.execute("""
                INSERT INTO attempts(key,started,failures) VALUES(?,?,1)
                ON CONFLICT(key) DO UPDATE SET failures=failures+1
            """, (attempt_key(), stamp))
            connection.commit()

    def clear_failures():
        with db() as connection:
            connection.execute("DELETE FROM attempts WHERE key=?", (attempt_key(),))

    def verify_password(encoded, password):
        if not HASH_SLOTS.acquire(blocking=False):
            abort(503)
        try:
            try:
                return PASSWORD_HASHER.verify(encoded, password)
            except (VerificationError, InvalidHashError):
                return False
        finally:
            HASH_SLOTS.release()

    def hash_password(password):
        if not HASH_SLOTS.acquire(blocking=False):
            abort(503)
        try:
            return PASSWORD_HASHER.hash(password)
        finally:
            HASH_SLOTS.release()

    def credentials(value):
        if not value.startswith("Basic ") or len(value) > 2048:
            return None
        try:
            raw = base64.b64decode(value[6:], validate=True).decode("utf-8")
            username, password = raw.split(":", 1)
        except (ValueError, UnicodeError):
            return None
        if not USERNAME.fullmatch(username) or not 1 <= len(password) <= 128:
            return None
        return username, password

    def lookup_session():
        value = request.cookies.get(COOKIE, "")
        if not re.fullmatch(r"[A-Za-z0-9_-]{43}", value):
            return None
        with db() as connection:
            return connection.execute(
                "SELECT * FROM sessions WHERE token_hash=? AND expires>?",
                (digest(value), now())).fetchone()

    def new_session(username=None):
        value, csrf, stamp = secrets.token_urlsafe(32), secrets.token_urlsafe(32), now()
        seconds = app.config["SESSION_SECONDS"] if username else app.config["PREAUTH_SECONDS"]
        with db() as connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("DELETE FROM sessions WHERE expires <= ?", (stamp,))
            previous = request.cookies.get(COOKIE, "")
            if previous:
                connection.execute("DELETE FROM sessions WHERE token_hash=?", (digest(previous),))
            if connection.execute("SELECT COUNT(*) FROM sessions").fetchone()[0] >= 10000:
                connection.rollback()
                abort(503)
            connection.execute("INSERT INTO sessions VALUES(?,?,?,?,?)",
                               (digest(value), username, csrf, stamp, stamp + seconds))
            connection.commit()
        g.new_cookie = (value, seconds)
        return {"username": username, "csrf": csrf}

    def require_form():
        if request.headers.get("Origin") != app.config["PUBLIC_ORIGIN"]:
            abort(403)
        if request.mimetype != "application/json":
            abort(415)
        session = lookup_session()
        csrf = request.headers.get("X-CSRF-Token", "")
        if not session or not csrf or not hmac.compare_digest(session["csrf"], csrf):
            abort(403)
        return session

    def input_credentials(data):
        username, password = data.get("username"), data.get("password")
        if not isinstance(username, str) or not USERNAME.fullmatch(username):
            return None
        if not isinstance(password, str) or not 12 <= len(password) <= 128:
            return None
        if not password.strip() or any(ord(char) < 32 or ord(char) == 127 for char in password):
            return None
        return username, password

    @app.before_request
    def limit_body():
        if request.content_length and request.content_length > app.config["MAX_CONTENT_LENGTH"]:
            abort(413)

    @app.after_request
    def headers(response):
        response.headers.update({
            "Cache-Control": "no-store, max-age=0",
            "Pragma": "no-cache",
            "X-Content-Type-Options": "nosniff",
            "X-Frame-Options": "DENY",
            "Referrer-Policy": "no-referrer",
            "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
            "Content-Security-Policy": "default-src 'none'; script-src 'self'; style-src 'self'; "
                "connect-src 'self'; img-src 'self'; font-src 'self'; frame-ancestors 'none'; "
                "base-uri 'none'; form-action 'self'",
        })
        if getattr(g, "new_cookie", None):
            value, seconds = g.new_cookie
            response.set_cookie(COOKIE, value, max_age=seconds, secure=True,
                                httponly=True, samesite="Strict", path="/")
        if getattr(g, "clear_cookie", False):
            response.delete_cookie(COOKIE, secure=True, httponly=True, samesite="Strict", path="/")
        return response

    @app.errorhandler(400)
    @app.errorhandler(403)
    @app.errorhandler(404)
    @app.errorhandler(405)
    @app.errorhandler(413)
    @app.errorhandler(415)
    @app.errorhandler(429)
    @app.errorhandler(503)
    @app.errorhandler(502)
    def safe_error(error):
        messages = {400: "请求格式不正确", 403: "验证已失效，请刷新页面重试",
                    404: "页面不存在", 405: "请求方式不支持", 413: "请求内容过大",
                    415: "请求格式不支持", 429: "尝试次数较多，请稍后再试",
                    503: "服务繁忙，请稍后重试"}
        response = jsonify(error=messages.get(error.code, "请求失败"))
        response.status_code = error.code
        if error.code in (429, 503):
            response.headers["Retry-After"] = str(app.config["RATE_SECONDS"] if error.code == 429 else 5)
        return response

    def require_history_proxy():
        # Both public entry points authenticate the owner before injecting this header.
        header = request.headers.get("Authorization", "")
        if request.remote_addr != "127.0.0.1" or not hmac.compare_digest(header.encode(), upstream.encode()):
            abort(403)

    def history_get(path):
        fetch = app.config.get("HISTORY_FETCH")
        if fetch is not None:
            return fetch(path)
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args):
                return None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        try:
            upstream_request = urllib.request.Request("http://127.0.0.1:4097" + path,
                headers={"Authorization": upstream, "Accept": "application/json"})
            with opener.open(upstream_request, timeout=10) as response:
                body = response.read(4 * 1048576 + 1)
            if len(body) > 4 * 1048576:
                abort(413)
            return json.loads(body)
        except urllib.error.HTTPError as error:
            abort(404 if error.code == 404 else 502)
        except (OSError, ValueError):
            abort(502)

    def history_rows(value):
        return value.get("data", []) if isinstance(value, dict) else value

    def history_id(value):
        if not re.fullmatch(r"[A-Za-z0-9_-]{1,160}", value):
            abort(400)
        return value

    @app.get("/client-cache/capabilities")
    def history_capabilities():
        require_history_proxy()
        return jsonify(data={"version": 1})

    @app.get("/client-cache/session/<session_id>/message")
    def thin_history(session_id):
        require_history_proxy()
        history_id(session_id)
        if set(request.args) - {"limit", "order", "cursor"} or any(len(v) != 1 for _, v in request.args.lists()):
            abort(400)
        limit = request.args.get("limit", "30")
        cursor = request.args.get("cursor", "")
        if limit not in ("1", "30") or len(cursor) > 2048 or request.args.get("order", "desc") != "desc":
            abort(400)
        query = urllib.parse.urlencode({"limit": limit, **({"cursor": cursor} if cursor else {"order": "desc"})})
        payload = history_get("/api/session/" + session_id + "/message?" + query)
        messages = history_rows(payload)
        if not isinstance(messages, list):
            abort(502)
        for message in messages:
            if not isinstance(message, dict):
                abort(502)
            files = message.get("files", [])
            if not isinstance(files, list):
                message["files"] = []
                continue
            stripped = []
            for file in files[:4]:
                if not isinstance(file, dict):
                    continue
                data = file.get("data", "")
                row = {"name": str(file.get("name", ""))[:160], "mime": str(file.get("mime", ""))[:120], "data": ""}
                if isinstance(data, str) and 0 < len(data) <= 1500000 and re.fullmatch(r"[A-Za-z0-9+/]*={0,2}", data) and len(data) % 4 == 0:
                    row["sha256"] = hashlib.sha256(data.encode()).hexdigest()
                    row["size"] = len(data) * 3 // 4 - (2 if data.endswith("==") else 1 if data.endswith("=") else 0)
                else:
                    row["error"] = "附件超出预览范围或类型不支持"
                stripped.append(row)
            message["files"] = stripped
        return jsonify(payload)

    @app.get("/client-cache/session/<session_id>/message/<message_id>/file/<int:index>")
    def history_file(session_id, message_id, index):
        require_history_proxy()
        history_id(session_id); history_id(message_id)
        if set(request.args) != {"sha256"} or len(request.args.getlist("sha256")) != 1:
            abort(400)
        expected = request.args.get("sha256", "")
        if not 0 <= index < 4 or not re.fullmatch(r"[a-f0-9]{64}", expected):
            abort(400)
        payload = history_get("/api/session/" + session_id + "/message/" + message_id)
        message = payload.get("data", {}) if isinstance(payload, dict) else {}
        if not isinstance(message, dict):
            abort(502)
        files = message.get("files", [])
        if message.get("id") != message_id or not isinstance(files, list) or index >= len(files):
            abort(404)
        file = files[index]
        data = file.get("data", "") if isinstance(file, dict) else ""
        if not isinstance(data, str) or not 0 < len(data) <= 1500000:
            abort(413)
        if hashlib.sha256(data.encode()).hexdigest() != expected:
            return jsonify(error="附件已变化，请刷新会话后重试"), 409
        return jsonify(data={"data": data, "sha256": expected, "name": str(file.get("name", ""))[:160],
                             "mime": str(file.get("mime", ""))[:120]})

    @app.get("/health")
    def health():
        return jsonify(status="ok")

    @app.get("/")
    def home():
        session = lookup_session()
        if not session or not session["username"]:
            return redirect("/login", code=302)
        return render_template("account.html", mode="home", username=session["username"])

    @app.get("/login")
    def login_page():
        session = lookup_session()
        if session and session["username"]:
            return redirect("/", code=302)
        return render_template("account.html", mode="login")

    @app.get("/setup")
    def setup_page():
        if owner():
            return redirect("/login", code=302)
        return render_template("account.html", mode="setup")

    @app.get("/auth/status")
    def status():
        session = lookup_session() or new_session()
        return jsonify(initialized=owner() is not None, username=session["username"],
                       csrf=session["csrf"])

    @app.post("/auth/setup")
    def setup():
        require_form()
        if owner():
            abort(404)
        if blocked():
            abort(429)
        token = request.headers.get("X-Setup-Token", "")
        with db() as connection:
            metadata = dict(connection.execute("SELECT key,value FROM metadata"))
        expected, expires = metadata.get("setup_hash", ""), int(metadata.get("setup_expires", "0"))
        if not token or len(token) > 128 or not expected or expires <= now() or not hmac.compare_digest(expected, digest(token)):
            failure()
            return jsonify(error="专属链接无效或已到期，请联系服务器所有者"), 403
        data = request.get_json()
        if not isinstance(data, dict):
            abort(400)
        pair = input_credentials(data)
        if not pair or data.get("confirmation") != pair[1]:
            return jsonify(error="账号需为3–32位英文、数字或._-；密码需为12–128位，且两次一致"), 400
        username, password = pair
        encoded = hash_password(password)
        with db() as connection:
            connection.execute("BEGIN IMMEDIATE")
            # Serialize claim, token consumption and revocation of anonymous sessions.
            if connection.execute("SELECT 1 FROM owner").fetchone():
                connection.rollback()
                abort(404)
            current = dict(connection.execute("SELECT key,value FROM metadata"))
            if current.get("setup_hash") != expected or int(current.get("setup_expires", "0")) <= now():
                connection.rollback()
                abort(403)
            connection.execute("INSERT INTO owner VALUES(1,?,?,?)", (username, encoded, now()))
            connection.execute("DELETE FROM metadata WHERE key IN ('setup_hash','setup_expires')")
            connection.execute("DELETE FROM sessions")
            connection.commit()
        with cache_lock:
            cache.clear()
        clear_failures()
        session = new_session(username)
        return jsonify(ok=True, username=username, csrf=session["csrf"])

    @app.post("/auth/login")
    def login():
        require_form()
        if blocked():
            abort(429)
        data = request.get_json()
        if not isinstance(data, dict):
            abort(400)
        pair = input_credentials(data)
        row = owner()
        if not pair or not row:
            failure()
            return jsonify(error="账号或密码不正确"), 401
        username, password = pair
        # Run the expensive verifier even for an unknown username.
        matched = verify_password(row["password_hash"], password)
        if not matched or not hmac.compare_digest(row["username"], username):
            failure()
            return jsonify(error="账号或密码不正确"), 401
        clear_failures()
        session = new_session(username)
        return jsonify(ok=True, csrf=session["csrf"])

    @app.get("/auth/traffic")
    def traffic():
        session = lookup_session()
        if not session or not session["username"]:
            return jsonify(error="请先登录"), 401
        path = Path(app.config.get("TRAFFIC_SUMMARY", "/var/lib/opencode-traffic/public.json"))
        try:
            if path.stat().st_size > 65536:
                abort(503)
            summary = json.loads(path.read_text())
            return jsonify(data=summary)
        except (OSError, ValueError):
            return jsonify(data={"available": False})

    @app.post("/auth/logout")
    def logout():
        session = require_form()
        with db() as connection:
            connection.execute("DELETE FROM sessions WHERE token_hash=?", (session["token_hash"],))
        g.clear_cookie = True
        return jsonify(ok=True)

    @app.route("/internal/check", methods=["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"])
    def internal_check():
        # This route is additionally internal-only in both Nginx entry points.
        if request.remote_addr != "127.0.0.1":
            abort(404)
        header = request.headers.get("Authorization", "")
        row = owner()
        authorized = False
        if row is None:
            # Transition only: one-owner initialization permanently disables this branch.
            authorized = bool(header and hmac.compare_digest(header.encode(), upstream.encode()))
        else:
            fingerprint = hmac.new(cache_key, header.encode(), hashlib.sha256).digest()
            with cache_lock:
                cached = cache.get(fingerprint)
            if cached and cached[0] > time.monotonic() and cached[1] == row["created"]:
                authorized = True
            else:
                if blocked():
                    return "", 401, {"WWW-Authenticate": 'Basic realm="OpenCode", charset="UTF-8"'}
                pair = credentials(header)
                if pair:
                    matched = verify_password(row["password_hash"], pair[1])
                    authorized = bool(matched and hmac.compare_digest(row["username"], pair[0]))
                if authorized:
                    with cache_lock:
                        if len(cache) >= 64:
                            cache.clear()
                        cache[fingerprint] = (time.monotonic() + app.config["BASIC_CACHE_SECONDS"], row["created"])
                    clear_failures()
                elif header:
                    failure()
        if not authorized:
            return "", 401, {"WWW-Authenticate": 'Basic realm="OpenCode", charset="UTF-8"'}
        return "", 204, {"X-OpenCode-Upstream-Authorization": upstream}

    return app


def production_app():
    return create_app()
