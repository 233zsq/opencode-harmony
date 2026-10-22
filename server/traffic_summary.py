"""Aggregate minimal Nginx egress counters. Never consume URLs, IPs or auth data."""
import argparse
import datetime as dt
import fcntl
import json
import os
from pathlib import Path
import sqlite3
import tempfile

TZ = dt.timezone(dt.timedelta(hours=8))
PROJECTS = ("opencode", "fieldnotes", "other")


def aggregate(state, logs, now=None):
    now = now or dt.datetime.now(TZ)
    state = Path(state)
    state.mkdir(parents=True, exist_ok=True, mode=0o750)
    with (state / "summary.lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        db = sqlite3.connect(state / "counters.sqlite3")
        os.chmod(state / "counters.sqlite3", 0o600)
        try:
            db.executescript("""
                CREATE TABLE IF NOT EXISTS metadata (key TEXT PRIMARY KEY,value TEXT NOT NULL);
                CREATE TABLE IF NOT EXISTS positions (inode TEXT PRIMARY KEY,offset INTEGER NOT NULL);
                CREATE TABLE IF NOT EXISTS totals (
                    month TEXT NOT NULL,project TEXT NOT NULL,bytes INTEGER NOT NULL,requests INTEGER NOT NULL,
                    PRIMARY KEY(month,project));
            """)
            db.execute("INSERT OR IGNORE INTO metadata VALUES('started_at',?)", (now.isoformat(),))
            db.commit()
            db.execute("BEGIN IMMEDIATE")
            files = []
            for source in logs:
                path = Path(source)
                files.extend(path.parent.glob(path.name + "*"))
            seen = set()
            for path in sorted(files):
                if not path.is_file() or path.is_symlink() or path.suffix == ".gz":
                    continue
                with path.open("rb") as stream:
                    # Bind offsets to the opened inode even if logrotate renames the path now.
                    stat = os.fstat(stream.fileno())
                    identity = str(stat.st_dev) + ":" + str(stat.st_ino)
                    if identity in seen:
                        continue
                    seen.add(identity)
                    row = db.execute("SELECT offset FROM positions WHERE inode=?", (identity,)).fetchone()
                    offset = row[0] if row and row[0] <= stat.st_size else 0
                    stream.seek(offset)
                    while True:
                        start = stream.tell()
                        line = stream.readline(16385)
                        if not line:
                            break
                        if not line.endswith(b"\n"):
                            # A partial in-progress record must be retried at the next run.
                            if len(line) <= 16384:
                                stream.seek(start)
                                break
                            while line and not line.endswith(b"\n"):
                                line = stream.readline(16385)
                            offset = stream.tell()
                            continue
                        offset = stream.tell()
                        try:
                            value = json.loads(line)
                            project, amount = value["project"], value["bytes"]
                            timestamp = dt.datetime.fromisoformat(value["time"])
                            if timestamp.tzinfo is None or project not in PROJECTS or type(amount) is not int or not 0 <= amount <= 2**50:
                                continue
                            month = timestamp.astimezone(TZ).strftime("%Y-%m")
                        except (KeyError, TypeError, ValueError):
                            continue
                        db.execute("""
                            INSERT INTO totals VALUES(?,?,?,1) ON CONFLICT(month,project)
                            DO UPDATE SET bytes=totals.bytes+excluded.bytes,requests=totals.requests+1
                        """, (month, project, amount))
                    # Do not advance beyond a partially written line.
                    offset = stream.tell()
                db.execute("INSERT OR REPLACE INTO positions VALUES(?,?)", (identity, offset))
            # Forget removed/compressed files, bounding cursors and limiting inode reuse risks.
            for (identity,) in db.execute("SELECT inode FROM positions").fetchall():
                if identity not in seen:
                    db.execute("DELETE FROM positions WHERE inode=?", (identity,))
            db.commit()
            month = now.astimezone(TZ).strftime("%Y-%m")
            projects = {name: {"bytes": 0, "requests": 0} for name in PROJECTS}
            for project, amount, requests in db.execute("SELECT project,bytes,requests FROM totals WHERE month=?", (month,)):
                projects[project] = {"bytes": amount, "requests": requests}
            started = db.execute("SELECT value FROM metadata WHERE key='started_at'").fetchone()[0]
            summary = {"version": 1, "available": True, "month": month, "started_at": started,
                       "updated_at": now.isoformat(), "projects": projects,
                       "http_bytes": sum(row["bytes"] for row in projects.values()),
                       "basis": "completed_http_responses", "quota_gb": 500}
            descriptor, temporary = tempfile.mkstemp(prefix=".summary-", dir=state)
            try:
                os.fchmod(descriptor, 0o640)
                with os.fdopen(descriptor, "w", encoding="utf8") as handle:
                    json.dump(summary, handle, ensure_ascii=False)
                    handle.flush()
                    os.fsync(handle.fileno())
                os.replace(temporary, state / "public.json")
                directory = os.open(state, os.O_RDONLY | os.O_DIRECTORY)
                try:
                    os.fsync(directory)
                finally:
                    os.close(directory)
            finally:
                if os.path.exists(temporary):
                    os.unlink(temporary)
            return summary
        finally:
            db.close()


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--state", default="/var/lib/opencode-traffic")
    parser.add_argument("--log", action="append", default=None)
    args = parser.parse_args()
    summary = aggregate(args.state, args.log or [
        "/var/log/app-egress/shared.jsonl", "/var/log/opencode-egress/direct.jsonl"])
    print(json.dumps({"month": summary["month"], "http_bytes": summary["http_bytes"]}))
