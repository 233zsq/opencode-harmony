#!/usr/bin/env bash
set -euo pipefail
ROOT=/var/lib/opencode-harmony-root
APP=/home/ubuntu/opencode-harmony-service
UPLOAD=/home/ubuntu/.opencode-harmony-tls-upload
[ -f "$ROOT/.opencode-harmony-jail-owned" ] || exit 1
[ ! -e /etc/systemd/system/opencode-harmony-settings.service ] || { echo 'Settings service already exists; inspect before update'; exit 1; }
install -o root -g oc-harmony-agent -m 550 "$UPLOAD/mobile_settings.py" "$ROOT$APP/bin/mobile_settings.py"
cat > /etc/systemd/system/opencode-harmony-settings.service <<EOF
[Unit]
Description=OpenCode Harmony restricted mobile settings
After=opencode-harmony-agent.service
Requires=opencode-harmony-agent.service
[Service]
Type=exec
User=oc-harmony-agent
Group=oc-harmony-agent
RootDirectory=$ROOT
MountAPIVFS=yes
BindReadOnlyPaths=/usr /etc/ssl/certs
WorkingDirectory=$APP
EnvironmentFile=$ROOT$APP/server.env
ExecStart=/usr/bin/python3 -B $APP/bin/mobile_settings.py
Restart=on-failure
RestartSec=3
UMask=0077
NoNewPrivileges=yes
CapabilityBoundingSet=
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=+$APP/config
PrivateTmp=yes
PrivateDevices=yes
ProtectProc=invisible
ProcSubset=pid
RestrictSUIDSGID=yes
RestrictNamespaces=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
TasksMax=64
MemoryMax=128M
[Install]
WantedBy=multi-user.target
EOF
python3 - <<'PY'
from pathlib import Path
path=Path('/etc/opencode-harmony-tls/nginx.conf')
text=path.read_text()
assert 'location /client-settings/' not in text
location='''    location /client-settings/ {
      auth_basic 'OpenCode Harmony';
      auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;
      proxy_pass http://127.0.0.1:4098;
      proxy_http_version 1.1;
      proxy_set_header Connection '';
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto https;
      proxy_buffering off;
      client_max_body_size 64k;
    }
'''
text=text.replace('    location / { return 404; }',location+'    location / { return 404; }')
path.write_text(text)
PY
systemctl daemon-reload
systemctl enable --now opencode-harmony-settings.service
runuser -u oc-harmony-tls -- /usr/sbin/nginx -t -p /run/opencode-harmony-tls/ -c /etc/opencode-harmony-tls/nginx.conf
runuser -u oc-harmony-tls -- /usr/sbin/nginx -p /run/opencode-harmony-tls/ -c /etc/opencode-harmony-tls/nginx.conf -s reload
systemctl is-active opencode-harmony-settings.service
echo 'Restricted mobile settings service enabled without restarting Agent or shared nginx.'
