"""First deployment of the single-owner gateway. Run as root after isolated tests.

Refuses drifted configs or existing state. Secrets stay in server-owned directories.
The one-time setup token itself is generated privately on the operator's computer;
only its SHA-256 digest is supplied in the staging setup-request.json.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import re
import secrets
import shlex
import shutil
import signal
import sqlite3
import subprocess
import time
import urllib.request

STAGE = Path("/home/ubuntu/.opencode-account-stage-20261022")
BACKUP = Path("/var/backups/opencode-account-20261022")
BASE = Path("/opt/opencode-account")
RELEASE = BASE / "releases/20261022"
FRONT = Path("/etc/nginx/conf.d/opencode-harmony.conf")
TLS = Path("/etc/opencode-harmony-tls/nginx.conf")
STATE = Path("/var/lib/opencode-account")
ETC = Path("/etc/opencode-account")
UNIT = Path("/etc/systemd/system/opencode-account.service")
FRONT_SHA = "15e39b48cae0bf1a8e3487d2786830c6c585de27724888e4c64e155db32a280b"
TLS_SHA = "7456d34c742b844c2f6a96a85f42279e6b382a018148957a3c2caba26de37afe"

def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def write(path, data, mode=0o600, uid=0, gid=0):
    path.write_text(data)
    os.chmod(path, mode)
    os.chown(path, uid, gid)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def atomic(path, text, mode=0o640, gid=0):
    temporary = path.with_name(path.name + ".account-next")
    write(temporary, text, mode, 0, gid)
    os.replace(temporary, path)

def main():
    assert os.geteuid() == 0
    assert sha(FRONT) == FRONT_SHA and sha(TLS) == TLS_SHA, "Entry config drift; inspect first"
    assert not UNIT.exists() and not STATE.exists() and not ETC.exists() and not BACKUP.exists()
    bootstrap = json.loads((STAGE / "setup-request.json").read_text())
    assert re.fullmatch(r"[a-f0-9]{64}", bootstrap["hash"])
    assert time.time() + 3600 < bootstrap["expires"] < time.time() + 25 * 3600
    spec = importlib.util.spec_from_file_location("account_entry", STAGE / "scripts/prepare-account-entry.py")
    renderer = importlib.util.module_from_spec(spec); spec.loader.exec_module(renderer)
    original_front, original_tls = FRONT.read_text(), TLS.read_text()
    new_front, new_tls = renderer.render_front(original_front), renderer.render_tls(original_tls)
    try:
        pwd.getpwnam("oc-account")
    except KeyError:
        run("useradd", "--system", "--home-dir", "/nonexistent", "--shell", "/usr/sbin/nologin", "oc-account")
    account = pwd.getpwnam("oc-account")
    tls_account = pwd.getpwnam("oc-harmony-tls")
    BACKUP.mkdir(mode=0o700)
    write(BACKUP / "front.before.conf", original_front)
    write(BACKUP / "tls.before.conf", original_tls)
    for name, path in [("front.before.htpasswd", Path("/etc/nginx/opencode-harmony.htpasswd")),
                       ("tls.before.htpasswd", Path("/etc/opencode-harmony-tls/htpasswd"))]:
        write(BACKUP / name, path.read_text())
    other = {str(path): sha(path) for path in [
        Path("/etc/nginx/nginx.conf"), Path("/etc/nginx/conf.d/fieldnotes.conf"),
        Path("/etc/nginx/sites-available/campus-review"),
        Path("/etc/nginx/sites-available/mobile-cloud-backend"),
    ]}
    write(BACKUP / "other-configs.json", json.dumps(other))
    RELEASE.parent.mkdir(exist_ok=True)
    shutil.copytree(STAGE / "server/account", RELEASE, ignore=shutil.ignore_patterns("__pycache__"))
    for root, dirs, names in os.walk(RELEASE):
        os.chmod(root, 0o755)
        for name in names:
            os.chmod(Path(root) / name, 0o644)
    (BASE / "current").symlink_to(RELEASE, target_is_directory=True)
    STATE.mkdir(mode=0o700)
    os.chown(STATE, account.pw_uid, account.pw_gid)
    ETC.mkdir(mode=0o750)
    os.chown(ETC, 0, account.pw_gid)
    original_env = Path("/var/lib/opencode-harmony-root/home/ubuntu/opencode-harmony-service/server.env")
    values = {}
    for line in original_env.read_text().splitlines():
        if line.startswith("OPENCODE_PASSWORD="):
            value = shlex.split(line.split("=", 1)[1])
            assert len(value) == 1 and len(value[0]) >= 40
            values["OPENCODE_PASSWORD"] = value[0]
    assert "OPENCODE_PASSWORD" in values
    values.update(ACCOUNT_RATE_SECRET=secrets.token_hex(32),
                  ACCOUNT_DATABASE=str(STATE / "account.sqlite3"),
                  ACCOUNT_ORIGIN="https://opencode.bigdogaaa.cn")
    write(ETC / "service.env", "\n".join(key + "=" + json.dumps(value) for key, value in values.items()) + "\n",
          0o640, 0, account.pw_gid)
    code = ("from app import production_app; app=production_app(); "
            "db=app.account_db(); c=db.__enter__(); "
            "c.executemany('INSERT INTO metadata VALUES(?,?)',"
            + repr([("setup_hash", bootstrap["hash"]), ("setup_expires", str(bootstrap["expires"]))]) +
            "); db.__exit__(None,None,None)")
    subprocess.run(["runuser", "-u", "oc-account", "--", str(BASE / "venv/bin/python"), "-B", "-c", code],
        cwd=RELEASE, env={**os.environ, **values}, check=True, stdout=subprocess.DEVNULL)
    # Check both candidate Nginx configs before any active config changes.
    candidate_tls = Path("/etc/opencode-harmony-tls/account.candidate.conf")
    write(candidate_tls, new_tls, 0o640, 0, tls_account.pw_gid)
    run("runuser", "-u", "oc-harmony-tls", "--", "/usr/sbin/nginx", "-t",
        "-p", "/run/opencode-harmony-tls/", "-c", str(candidate_tls))
    main_text = Path("/etc/nginx/nginx.conf").read_text()
    assert main_text.count("include /etc/nginx/conf.d/*.conf;") == 1
    front_candidate = BACKUP / "front.candidate.conf"
    write(front_candidate, new_front)
    includes = [str(path) if path != FRONT else str(front_candidate)
                for path in sorted(Path("/etc/nginx/conf.d").glob("*.conf"))]
    candidate_main = BACKUP / "nginx.test.conf"
    write(candidate_main, main_text.replace("include /etc/nginx/conf.d/*.conf;",
        "\n".join("include " + path + ";" for path in includes)))
    run("/usr/sbin/nginx", "-t", "-c", str(candidate_main))
    write(UNIT, (RELEASE / "opencode-account.service").read_text(), 0o644)
    run("systemctl", "daemon-reload")
    run("systemctl", "enable", "--now", "opencode-account.service")
    for retry in range(40):
        try:
            probe = urllib.request.Request("http://127.0.0.1:4099/health",
                headers={"Host": "opencode.bigdogaaa.cn"})
            with urllib.request.urlopen(probe, timeout=2) as response:
                assert response.status == 200
            break
        except OSError:
            if retry == 39: raise
            time.sleep(.2)
    switched = False
    try:
        atomic(TLS, new_tls, gid=tls_account.pw_gid)
        atomic(FRONT, new_front, mode=0o644)
        run("/usr/sbin/nginx", "-t")
        run("runuser", "-u", "oc-harmony-tls", "--", "/usr/sbin/nginx", "-t",
            "-p", "/run/opencode-harmony-tls/", "-c", str(TLS))
        run("runuser", "-u", "oc-harmony-tls", "--", "/usr/sbin/nginx",
            "-p", "/run/opencode-harmony-tls/", "-c", str(TLS), "-s", "reload")
        run("systemctl", "kill", "--kill-whom=main", "--signal=HUP", "nginx.service")
        switched = True
        assert all(sha(Path(path)) == digest for path, digest in other.items()), "Unrelated config drift"
        write(BACKUP / "deployed.json", json.dumps({
            "front": sha(FRONT), "tls": sha(TLS), "release": str(RELEASE),
            "setup_expires": bootstrap["expires"], "other_configs_unchanged": True}, indent=2))
    finally:
        candidate_tls.unlink(missing_ok=True)
        if not switched:
            atomic(TLS, original_tls, gid=tls_account.pw_gid)
            atomic(FRONT, original_front, mode=0o644)
            run("runuser", "-u", "oc-harmony-tls", "--", "/usr/sbin/nginx",
                "-p", "/run/opencode-harmony-tls/", "-c", str(TLS), "-s", "reload")
            run("systemctl", "kill", "--kill-whom=main", "--signal=HUP", "nginx.service")
    print(json.dumps({"deployed": True, "setup_expires": bootstrap["expires"],
                      "registration_open": False, "other_projects_changed": False}))

if __name__ == "__main__":
    main()
