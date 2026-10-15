#!/usr/bin/env bash
# One-time migration of this application's instance. Does not reload shared nginx.
set -euo pipefail
umask 077
SOURCE=/home/ubuntu/opencode-harmony-service
JAIL=/var/lib/opencode-harmony-root
DATA="$JAIL$SOURCE"
TLS=/etc/opencode-harmony-tls
UPLOAD=/home/ubuntu/.opencode-harmony-tls-upload
AGENT=oc-harmony-agent
PROXY=oc-harmony-tls
[ "$(id -u)" = 0 ] || { echo 'Run with sudo' >&2; exit 1; }
[ -f "$SOURCE/.opencode-harmony-owned" ] || exit 1
if [ "${1:-}" = --resume ]; then
  [ -f "$JAIL/.opencode-harmony-jail-owned" ] && [ ! -e "$TLS" ] || exit 1
else
  [ ! -e "$JAIL" ] && [ ! -e "$TLS" ] || { echo 'Existing target: inspect instead of overwriting' >&2; exit 1; }
  getent passwd "$AGENT" >/dev/null && exit 1
  getent passwd "$PROXY" >/dev/null && exit 1
fi
[ -f "$UPLOAD/server.pem" ] && [ -f "$UPLOAD/server.key" ] && [ -f "$UPLOAD/ca.pem" ] || exit 1
if ss -ltnH | awk '{print $4}' | grep -Eq ':9443$'; then echo 'TLS port occupied' >&2; exit 1; fi
OLD_NGINX_PID=$(systemctl show nginx -p MainPID --value)
find /etc/nginx -type f -exec sha256sum '{}' + | sort > "$UPLOAD/nginx-before.sha256"
ss -ltnH | awk '{print $4}' | sort > "$UPLOAD/listeners-before.txt"
openssl verify -CAfile "$UPLOAD/ca.pem" "$UPLOAD/server.pem"
if [ "${1:-}" != --resume ]; then
  useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$AGENT"
  useradd --system --no-create-home --home-dir /nonexistent --shell /usr/sbin/nologin "$PROXY"
  mkdir -p "$JAIL"; touch "$JAIL/.opencode-harmony-jail-owned"
fi
old_service() { runuser -u ubuntu -- env XDG_RUNTIME_DIR=/run/user/1000 systemctl --user "$@" opencode-harmony.service; }
rollback() {
  code=$?
  if [ "$code" != 0 ]; then
    systemctl disable --now opencode-harmony-tls.service opencode-harmony-agent.service 2>/dev/null || true
    old_service enable || true
    old_service start || true
    echo 'Migration failed; original dedicated instance restarted. Public entry stopped.' >&2
  fi
  exit "$code"
}
trap rollback EXIT
old_service stop
mkdir -p "$DATA" "$JAIL"/{usr,etc/ssl/certs,proc,dev,run,tmp,home/ubuntu}
cp -a "$SOURCE/." "$DATA/"
chown -R "$AGENT:$AGENT" "$DATA"
chmod 755 "$JAIL" "$JAIL/home" "$JAIL/home/ubuntu" "$JAIL/tmp"
chmod 1777 "$JAIL/tmp"
ln -sfn usr/bin "$JAIL/bin"
ln -sfn usr/sbin "$JAIL/sbin"
ln -sfn usr/lib "$JAIL/lib"
ln -sfn usr/lib64 "$JAIL/lib64"
cp -L /etc/resolv.conf "$JAIL/etc/resolv.conf"
printf '127.0.0.1 localhost\n::1 localhost\n' > "$JAIL/etc/hosts"
printf 'passwd: files\ngroup: files\nshadow: files\nhosts: files dns\nnetworks: files\n' > "$JAIL/etc/nsswitch.conf"
getent passwd root "$AGENT" > "$JAIL/etc/passwd"
getent group root "$AGENT" > "$JAIL/etc/group"
chmod 755 "$JAIL/etc" "$JAIL/etc/ssl" "$JAIL/etc/ssl/certs"
chmod 644 "$JAIL/etc/resolv.conf" "$JAIL/etc/hosts" "$JAIL/etc/nsswitch.conf" "$JAIL/etc/passwd" "$JAIL/etc/group"
cat > /etc/systemd/system/opencode-harmony-agent.service <<EOF
[Unit]
Description=OpenCode Harmony isolated agent
After=network-online.target
Wants=network-online.target
[Service]
Type=simple
User=$AGENT
Group=$AGENT
RootDirectory=$JAIL
MountAPIVFS=yes
BindReadOnlyPaths=/usr /etc/ssl/certs
WorkingDirectory=$SOURCE/workspaces/demo
EnvironmentFile=$DATA/server.env
ExecStart=$SOURCE/bin/opencode-v2.0.29 serve --hostname 127.0.0.1 --port 4097
Restart=on-failure
RestartSec=3
UMask=0077
NoNewPrivileges=yes
CapabilityBoundingSet=
ProtectSystem=strict
ProtectHome=read-only
ReadWritePaths=+$SOURCE
PrivateTmp=yes
PrivateDevices=yes
ProtectProc=invisible
ProcSubset=pid
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectKernelLogs=yes
ProtectControlGroups=yes
ProtectClock=yes
ProtectHostname=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
RestrictAddressFamilies=AF_UNIX AF_INET AF_INET6
LockPersonality=yes
TasksMax=256
CPUQuota=200%
OOMScoreAdjust=500
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start opencode-harmony-agent.service
for attempt in $(seq 1 20); do
  if curl -s --max-time 2 -o /dev/null -w '%{http_code}' http://127.0.0.1:4097/api/info | grep -q 401; then break; fi
  sleep 1
done
systemctl is-active --quiet opencode-harmony-agent.service
install -d -o root -g "$PROXY" -m 750 "$TLS"
install -o root -g "$PROXY" -m 640 "$UPLOAD/server.key" "$TLS/server.key"
install -o root -g "$PROXY" -m 640 "$UPLOAD/server.pem" "$TLS/server.pem"
install -o root -g "$PROXY" -m 640 "$UPLOAD/ca.pem" "$TLS/ca.pem"
python3 - "$DATA/server.env" "$TLS/htpasswd" <<'PY'
import pathlib,subprocess,sys
values=dict(line.split('=',1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines())
password=values['OPENCODE_PASSWORD']
assert len(password)>=40
hashed=subprocess.run(['openssl','passwd','-6','-stdin'],input=password+'\n',capture_output=True,text=True,check=True).stdout.strip()
pathlib.Path(sys.argv[2]).write_text('opencode:'+hashed+'\n')
PY
chown root:"$PROXY" "$TLS/htpasswd"
chmod 640 "$TLS/htpasswd"
cat > "$TLS/nginx.conf" <<'NGINX'
worker_processes 1;
pid /run/opencode-harmony-tls/nginx.pid;
error_log stderr warn;
events { worker_connections 256; }
http {
  access_log off;
  server_tokens off;
  client_body_temp_path /run/opencode-harmony-tls/body;
  proxy_temp_path /run/opencode-harmony-tls/proxy;
  client_max_body_size 2m;
  client_header_timeout 10s;
  client_body_timeout 15s;
  keepalive_timeout 30s;
  send_timeout 60s;
  limit_req_zone $binary_remote_addr zone=harmony_requests:1m rate=10r/s;
  limit_conn_zone $binary_remote_addr zone=harmony_connections:1m;
  server {
    listen 0.0.0.0:9443 ssl;
    ssl_certificate /etc/opencode-harmony-tls/server.pem;
    ssl_certificate_key /etc/opencode-harmony-tls/server.key;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:harmony_tls:1m;
    ssl_session_tickets off;
    limit_req zone=harmony_requests burst=40 nodelay;
    limit_req_status 429;
    limit_conn harmony_connections 20;
    limit_conn_status 429;
    add_header X-Content-Type-Options nosniff always;
    add_header Cache-Control no-store always;
    location /api/ {
      auth_basic 'OpenCode Harmony';
      auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;
      proxy_pass http://127.0.0.1:4097;
      proxy_http_version 1.1;
      proxy_set_header Connection '';
      proxy_set_header Host $host;
      proxy_set_header X-Forwarded-For $remote_addr;
      proxy_set_header X-Forwarded-Proto https;
      proxy_buffering off;
      proxy_request_buffering off;
      proxy_cache off;
      proxy_read_timeout 90s;
      proxy_send_timeout 30s;
    }
    location / { return 404; }
  }
}
NGINX
chown root:"$PROXY" "$TLS/nginx.conf"
chmod 640 "$TLS/nginx.conf"
cat > /etc/systemd/system/opencode-harmony-tls.service <<EOF
[Unit]
Description=OpenCode Harmony private TLS entry
After=network-online.target opencode-harmony-agent.service
Requires=opencode-harmony-agent.service
[Service]
Type=simple
User=$PROXY
Group=$PROXY
RuntimeDirectory=opencode-harmony-tls
RuntimeDirectoryMode=0700
ExecStartPre=/usr/sbin/nginx -t -p /run/opencode-harmony-tls/ -c $TLS/nginx.conf
ExecStart=/usr/sbin/nginx -p /run/opencode-harmony-tls/ -c $TLS/nginx.conf -g 'daemon off;'
Restart=on-failure
RestartSec=3
UMask=0077
NoNewPrivileges=yes
CapabilityBoundingSet=
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectProc=invisible
ProcSubset=pid
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictNamespaces=yes
RestrictAddressFamilies=AF_INET AF_UNIX
[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl start opencode-harmony-tls.service
systemctl is-active --quiet opencode-harmony-tls.service
python3 - "$DATA/server.env" <<'PY'
import base64,http.client,json,pathlib,socket,ssl,sys,time
values=dict(line.split('=',1) for line in pathlib.Path(sys.argv[1]).read_text().splitlines())
auth='Basic '+base64.b64encode(('opencode:'+values['OPENCODE_PASSWORD']).encode()).decode()
context=ssl.create_default_context(cafile='/etc/opencode-harmony-tls/ca.pem')
for attempt in range(15):
 try:
  c=http.client.HTTPSConnection('127.0.0.1',9443,context=context,timeout=3)
  c.request('GET','/api/project',headers={'Authorization':auth})
  r=c.getresponse();body=r.read();c.close()
  assert r.status==200 and isinstance(json.loads(body),list)
  break
 except Exception:
  if attempt==14: raise
  time.sleep(1)
print('TLS certificate/hostname, authentication and isolated project API verified.')
PY
systemctl enable opencode-harmony-agent.service opencode-harmony-tls.service
old_service disable
find /etc/nginx -type f -exec sha256sum '{}' + | sort > "$UPLOAD/nginx-after.sha256"
cmp "$UPLOAD/nginx-before.sha256" "$UPLOAD/nginx-after.sha256"
[ "$OLD_NGINX_PID" = "$(systemctl show nginx -p MainPID --value)" ]
echo 'Missing pre-existing listener addresses (must be empty):'
comm -23 "$UPLOAD/listeners-before.txt" <(ss -ltnH | awk '{print $4}' | sort)
[ -z "$(comm -23 "$UPLOAD/listeners-before.txt" <(ss -ltnH | awk '{print $4}' | sort))" ]
trap - EXIT
echo 'Isolated agent and independent TLS service ready. Shared nginx files and master PID unchanged.'
