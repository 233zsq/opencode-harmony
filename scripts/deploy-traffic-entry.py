"""One-time, drift-checked cache/traffic deployment. Run as root after isolated tests.

Does not change owner credentials, account data, certificates or Agent processes.
All original configuration is backed up before atomic replacement.
"""
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import pwd
import shutil
import sqlite3
import stat
import subprocess
import time
import urllib.request

STAGE = Path("/home/ubuntu/.opencode-traffic-stage-20261022")
BACKUP = Path("/var/backups/opencode-traffic-20261022")
BASE = Path("/opt/opencode-account")
RELEASE = BASE / "releases/20261022-traffic"
FRONT = Path("/etc/nginx/conf.d/opencode-harmony.conf")
TLS = Path("/etc/opencode-harmony-tls/nginx.conf")
SHARED_FORMAT = Path("/etc/nginx/conf.d/00-app-egress.conf")
EXPECTED = {
 str(FRONT): "71123371e4988b584d8a783b509987d7542cbe69fb969f740b0522619eb95ac1",
 str(TLS): "335583cf6f4b626ae34dfbb9e213d971fbbf4b1cb4fb68c676d2d890e0496a4b",
 "/etc/nginx/conf.d/fieldnotes.conf": "9c5fab4d560c862d84da126e2f6648da6d33e95b69c1e916210d4115de310b88",
 "/etc/nginx/sites-available/mobile-cloud-backend": "01aba87f04800b9fba2daf756d558de8448997ecd96e576989f366b3da0c0e4f",
 "/etc/nginx/sites-available/campus-review": "8e37eb6668e223766dd65afa9cdb71bfccdb38cab405a205e17a6fca902afc94",
}
TLS_DROP = Path("/etc/systemd/system/opencode-harmony-tls.service.d/traffic.conf")
ACCOUNT_DROP = Path("/etc/systemd/system/opencode-account.service.d/traffic.conf")
UNIT = Path("/etc/systemd/system/opencode-traffic.service")
TIMER = Path("/etc/systemd/system/opencode-traffic.timer")
ROTATION = Path("/etc/logrotate.d/app-egress")

def run(*args):
    return subprocess.run(args, check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def put(path, text, mode=0o644, uid=0, gid=0):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)
    os.chmod(path, mode)
    os.chown(path, uid, gid)

def atomic(path, text, mode=0o644, uid=0, gid=0):
    temporary = path.with_name(path.name + ".traffic-next")
    put(temporary, text, mode, uid, gid)
    os.replace(temporary, path)

def pid(name):
    return run("systemctl", "show", "-p", "MainPID", "--value", name).stdout.decode().strip()

def owner_fingerprint():
    with sqlite3.connect("file:/var/lib/opencode-account/account.sqlite3?mode=ro", uri=True) as db:
        rows = db.execute("SELECT username,password_hash,created FROM owner").fetchall()
        assert len(rows) == 1, "Owner must already be initialized"
        assert db.execute("SELECT COUNT(*) FROM metadata WHERE key='setup_hash'").fetchone()[0] == 0
        return hashlib.sha256(repr(rows).encode()).hexdigest()

def healthy_account():
    for retry in range(40):
        try:
            request = urllib.request.Request("http://127.0.0.1:4099/health", headers={"Host":"opencode.bigdogaaa.cn"})
            with urllib.request.urlopen(request, timeout=2) as response:
                if response.status == 200:
                    return
        except OSError:
            pass
        time.sleep(.25)
    raise RuntimeError("Account service did not become healthy")

def main():
    assert os.geteuid() == 0
    for path, expected in EXPECTED.items():
        assert sha(Path(path)) == expected, "Configuration drift: " + path
    for path in [BACKUP, RELEASE, SHARED_FORMAT, TLS_DROP, ACCOUNT_DROP, UNIT, TIMER, ROTATION]:
        assert not path.exists(), "Existing migration artifact: " + str(path)
    old_release = (BASE / "current").resolve()
    account_before = owner_fingerprint()
    untouched_services = ["opencode-harmony-agent.service", "opencode-harmony-settings.service",
                          "mobile-cloud-backend.service", "campus-review.service"]
    process_before = {name: pid(name) for name in untouched_services}
    spec = importlib.util.spec_from_file_location("traffic_entry", STAGE / "scripts/prepare-traffic-entry.py")
    renderer = importlib.util.module_from_spec(spec); spec.loader.exec_module(renderer)
    originals = {Path(path): (Path(path).read_text(), Path(path).stat()) for path in EXPECTED}
    changed = {
        FRONT: renderer.render_public(originals[FRONT][0], 2, True),
        TLS: renderer.render_tls(originals[TLS][0]),
    }
    for name, count in [("fieldnotes.conf", 2), ("mobile-cloud-backend", 2), ("campus-review", 1)]:
        path = next(path for path in originals if path.name == name)
        changed[path] = renderer.render_public(originals[path][0], count)
    BACKUP.mkdir(mode=0o700)
    for index, (path, (text, metadata)) in enumerate(originals.items()):
        put(BACKUP / (str(index) + ".before.conf"), text, 0o600)
    put(BACKUP / "manifest.json", json.dumps({"source":EXPECTED,"old_release":str(old_release),
        "services":process_before,"owner_fingerprint":account_before}), 0o600)
    try:
        traffic = pwd.getpwnam("oc-traffic")
    except KeyError:
        run("useradd", "--system", "--user-group", "--home-dir", "/nonexistent",
            "--shell", "/usr/sbin/nologin", "oc-traffic")
        traffic = pwd.getpwnam("oc-traffic")
    tls_user = pwd.getpwnam("oc-harmony-tls")
    for directory, filename, uid, mode in [
        (Path("/var/log/app-egress"),"shared.jsonl",0,0o750),
        (Path("/var/log/opencode-egress"),"direct.jsonl",tls_user.pw_uid,0o2750)]:
        directory.mkdir(mode=mode, exist_ok=True)
        os.chown(directory,uid,traffic.pw_gid);os.chmod(directory,mode)
        file=directory/filename
        if not file.exists():put(file,"",0o640,uid,traffic.pw_gid)
    # Stage a new immutable code release; never copy production state or environment.
    shutil.copytree(STAGE / "server/account", RELEASE, ignore=shutil.ignore_patterns("__pycache__"))
    for directory, dirs, names in os.walk(RELEASE):
        os.chmod(directory,0o755)
        for name in names:os.chmod(Path(directory)/name,0o644)
    put(BASE / "traffic_summary.py",(STAGE/"server/traffic_summary.py").read_text(),0o755)

    # Test candidates while all live entry files are still unchanged.
    tls_candidate=TLS.with_name("traffic.candidate.conf")
    put(tls_candidate,changed[TLS],0o640,0,tls_user.pw_gid)
    try:
        run("runuser","-u","oc-harmony-tls","--","/usr/sbin/nginx","-t",
            "-p","/run/opencode-harmony-tls/","-c",str(tls_candidate))
        candidates={}
        for index,(path,text) in enumerate(changed.items()):
            if path==TLS:continue
            candidate=BACKUP/(str(index)+".candidate.conf")
            put(candidate,text,0o600);candidates[path.resolve()]=candidate
        format_candidate=BACKUP/"format.candidate.conf";put(format_candidate,renderer.SHARED_FORMAT,0o600)
        main_source=Path("/etc/nginx/nginx.conf").read_text()
        for include, paths in [
            ("include /etc/nginx/conf.d/*.conf;",sorted(Path("/etc/nginx/conf.d").glob("*.conf"))),
            ("include /etc/nginx/sites-enabled/*;",sorted(Path("/etc/nginx/sites-enabled").glob("*")))]:
            assert main_source.count(include)==1,"Unexpected Nginx includes"
            listing=[str(candidates.get(path.resolve(),path)) for path in paths]
            if "conf.d" in include:listing.insert(0,str(format_candidate))
            main_source=main_source.replace(include,"\n".join("include "+path+";" for path in listing))
        main_candidate=BACKUP/"nginx.test.conf";put(main_candidate,main_source,0o600)
        run("/usr/sbin/nginx","-t","-c",str(main_candidate))
    finally:
        tls_candidate.unlink(missing_ok=True)

    put(TLS_DROP,"[Service]\nReadWritePaths=/var/log/opencode-egress\n")
    put(ACCOUNT_DROP,"[Service]\nSupplementaryGroups=oc-traffic\n")
    put(UNIT,(STAGE/"server/opencode-traffic.service").read_text())
    put(TIMER,(STAGE/"server/opencode-traffic.timer").read_text())
    put(ROTATION,"""/var/log/app-egress/shared.jsonl {
  daily
  maxsize 10M
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 0640 root oc-traffic
  sharedscripts
  postrotate
    /bin/systemctl kill --kill-whom=main --signal=USR1 nginx.service >/dev/null 2>&1 || true
  endscript
}
/var/log/opencode-egress/direct.jsonl {
  daily
  maxsize 10M
  rotate 14
  compress
  delaycompress
  missingok
  notifempty
  create 0640 oc-harmony-tls oc-traffic
  sharedscripts
  postrotate
    /bin/systemctl kill --kill-whom=main --signal=USR1 opencode-harmony-tls.service >/dev/null 2>&1 || true
  endscript
}
""")
    activated=False
    try:
        for path,text in changed.items():
            metadata=originals[path][1]
            atomic(path,text,stat.S_IMODE(metadata.st_mode),metadata.st_uid,metadata.st_gid)
        atomic(SHARED_FORMAT,renderer.SHARED_FORMAT)
        temporary=BASE/"current.traffic-next";temporary.symlink_to(RELEASE,target_is_directory=True)
        os.replace(temporary,BASE/"current")
        run("/usr/sbin/nginx","-t")
        run("systemctl","daemon-reload")
        run("systemctl","restart","opencode-account.service")
        healthy_account()
        # One short TLS-gateway restart applies its additional writable log directory.
        run("systemctl","restart","opencode-harmony-tls.service")
        run("systemctl","kill","--kill-whom=main","--signal=HUP","nginx.service")
        run("systemctl","start","opencode-traffic.service")
        run("systemctl","enable","--now","opencode-traffic.timer")
        assert owner_fingerprint()==account_before,"Owner credentials changed"
        assert all(pid(name)==value for name,value in process_before.items()),"Unrelated service restarted"
        assert all(run("systemctl","is-active",name).stdout.strip()==b"active"
                   for name in ["opencode-account.service","opencode-harmony-tls.service","nginx.service","opencode-traffic.timer"])
        activated=True
        put(BACKUP/"deployed.json",json.dumps({"release":str(RELEASE),
            "configs":{str(path):sha(path) for path in changed},"owner_unchanged":True,
            "other_processes_unchanged":True}),0o600)
    finally:
        if not activated:
            # Restore only this migration, never the obsolete pre-owner-auth gateway.
            run("systemctl","disable","--now","opencode-traffic.timer")
            for path,(text,metadata) in originals.items():
                atomic(path,text,stat.S_IMODE(metadata.st_mode),metadata.st_uid,metadata.st_gid)
            for path in [SHARED_FORMAT,TLS_DROP,ACCOUNT_DROP]:path.unlink(missing_ok=True)
            temporary=BASE/"current.traffic-rollback";temporary.symlink_to(old_release,target_is_directory=True)
            os.replace(temporary,BASE/"current")
            run("systemctl","daemon-reload")
            run("systemctl","restart","opencode-account.service","opencode-harmony-tls.service")
            run("systemctl","kill","--kill-whom=main","--signal=HUP","nginx.service")
    print(json.dumps({"deployed":True,"owner_unchanged":True,"other_processes_unchanged":True,
                      "traffic_basis":"completed HTTP responses since activation"}))

if __name__=="__main__":main()
