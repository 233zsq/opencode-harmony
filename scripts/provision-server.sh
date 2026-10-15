#!/usr/bin/env bash
set -euo pipefail
umask 077
ROOT="$HOME/opencode-harmony-service"
SOURCE="$HOME/.opencode/bin/opencode"
UNIT="$HOME/.config/systemd/user/opencode-harmony.service"
PORT=4097
if [ -e "$ROOT" ] && [ ! -f "$ROOT/.opencode-harmony-owned" ]; then echo "Unowned service directory" >&2; exit 1; fi
if [ -e "$UNIT" ]; then echo "Unit already exists; inspect before changing" >&2; exit 1; fi
VERSION="$("$SOURCE" --version)"
if [ "$VERSION" != "opencode v2.0.29" ] && [ "$VERSION" != "2.0.29" ]; then echo "Unverified version: $VERSION" >&2; exit 1; fi
if ss -ltnH | awk '{print $4}' | grep -Eq ":$PORT$"; then echo "Port occupied" >&2; exit 1; fi
mkdir -p "$ROOT"/{bin,home,config/opencode,data/opencode,state,cache,tmp,workspaces/demo}
touch "$ROOT/.opencode-harmony-owned"
ss -ltnH | awk '{print $4}' | sort > "$ROOT/listeners-before.txt"
cp "$SOURCE" "$ROOT/bin/opencode-v2.0.29"
cmp --silent "$SOURCE" "$ROOT/bin/opencode-v2.0.29"
python3 - "$ROOT" <<'PY'
import pathlib,secrets,sys
root=pathlib.Path(sys.argv[1])
paths={"HOME":root/"home","XDG_CONFIG_HOME":root/"config","XDG_DATA_HOME":root/"data","XDG_STATE_HOME":root/"state","XDG_CACHE_HOME":root/"cache","TMPDIR":root/"tmp","OPENCODE_DB":root/"data/opencode/opencode.db"}
lines=[f'{key}={value}' for key,value in paths.items()]
lines+=["OPENCODE_DISABLE_AUTOUPDATE=1","OPENCODE_CONFIG_PROJECT_DISABLE=1","OPENCODE_PASSWORD="+secrets.token_urlsafe(36)]
file=root/"server.env";file.write_text("\n".join(lines)+"\n");file.chmod(0o600)
(root/"workspaces/demo/README.md").write_text("# OpenCode Harmony dedicated workspace\n\nThis workspace belongs only to the HarmonyOS client integration.\n")
PY
git -C "$ROOT/workspaces/demo" init -q
git -C "$ROOT/workspaces/demo" -c user.name='OpenCode Harmony' -c user.email='opencode-harmony@localhost' add README.md
git -C "$ROOT/workspaces/demo" -c user.name='OpenCode Harmony' -c user.email='opencode-harmony@localhost' commit -qm 'chore: 初始化独立联调工作区'
mkdir -p "$(dirname "$UNIT")"
cat > "$UNIT" <<EOF
[Unit]
Description=OpenCode Harmony Dedicated Instance
[Service]
Type=simple
WorkingDirectory=$ROOT/workspaces/demo
EnvironmentFile=$ROOT/server.env
ExecStart=$ROOT/bin/opencode-v2.0.29 serve --hostname 127.0.0.1 --port $PORT
Restart=on-failure
RestartSec=3
UMask=0077
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=$ROOT
PrivateTmp=yes
RestrictSUIDSGID=yes
InaccessiblePaths=$HOME/.ssh
[Install]
WantedBy=default.target
EOF
systemctl --user daemon-reload
systemctl --user enable --now opencode-harmony.service
for attempt in $(seq 1 30); do
if python3 - "$ROOT" "$PORT" <<'PY'
import base64,json,pathlib,sys,urllib.request
root=pathlib.Path(sys.argv[1]);env=dict(line.split("=",1) for line in (root/"server.env").read_text().splitlines())
request=urllib.request.Request("http://127.0.0.1:"+sys.argv[2]+"/api/info")
request.add_header("Authorization","Basic "+base64.b64encode(("opencode:"+env["OPENCODE_PASSWORD"]).encode()).decode())
try:
 with urllib.request.urlopen(request,timeout=2) as result: info=json.load(result)
 assert info["version"]=="2.0.29"
 print("Dedicated API ready: v"+info["version"])
except Exception: sys.exit(1)
PY
then break;fi
sleep 1
done
systemctl --user is-active --quiet opencode-harmony.service
python3 - "$ROOT" "$PORT" <<'PY'
import base64,json,pathlib,sys,urllib.request
root=pathlib.Path(sys.argv[1]);env=dict(line.split("=",1) for line in (root/"server.env").read_text().splitlines())
header={"Authorization":"Basic "+base64.b64encode(("opencode:"+env["OPENCODE_PASSWORD"]).encode()).decode()}
with urllib.request.urlopen(urllib.request.Request("http://127.0.0.1:"+sys.argv[2]+"/api/info",headers=header),timeout=5) as r: print("Verified API version:",json.load(r)["version"])
print("Credentials saved privately; not printed.")
PY
systemctl --user show opencode-harmony.service -p NoNewPrivileges -p ProtectSystem -p ProtectHome -p ReadWritePaths -p MainPID
echo 'Any disappeared listener addresses:'
comm -23 "$ROOT/listeners-before.txt" <(ss -ltnH | awk '{print $4}' | sort)

exit 0
