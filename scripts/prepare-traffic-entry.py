"""Render bounded, aggregate-only egress logs and authenticated thin history routes."""
import re

THIN_LOCATION = """
    location /client-cache/ {
      auth_request /_opencode_auth;
      auth_request_set $account_upstream_auth $upstream_http_x_opencode_upstream_authorization;
      proxy_set_header Authorization $account_upstream_auth;
      proxy_set_header Cookie "";
      proxy_set_header Host opencode.bigdogaaa.cn;
      proxy_pass http://127.0.0.1:4099;
      proxy_http_version 1.1;
      proxy_set_header Connection "";
      proxy_buffering off;
      proxy_cache off;
      client_max_body_size 8k;
      proxy_read_timeout 30s;
    }
"""
SHARED_FORMAT = """
# Aggregate completed HTTP response bytes only. No URL, IP, cookie or authorization.
map $server_name $traffic_project {
  default other;
  opencode.bigdogaaa.cn opencode;
  fieldnotes.bigdogaaa.cn fieldnotes;
  49.232.195.47 fieldnotes;
}
log_format app_egress escape=json '{"time":"$time_iso8601","project":"$traffic_project","bytes":$bytes_sent}';
"""
DIRECT_FORMAT = """
  # Original TCP peer survives real_ip rewriting. Internal 443 -> 9443 is counted at 443 only.
  map $realip_remote_addr $traffic_public {
    default 1;
    127.0.0.1 0;
  }
  log_format app_direct escape=json '{"time":"$time_iso8601","project":"opencode","bytes":$bytes_sent}';
  access_log /var/log/opencode-egress/direct.jsonl app_direct if=$traffic_public;
"""


def render_public(source, expected_servers, thin=False):
    if "app_egress" in source or "/client-cache/" in source:
        raise ValueError("Already migrated; inspect the current configuration")
    # These known virtual hosts have exactly one server_name per public server.
    if len(re.findall(r"^\s*server_name [^;]+;", source, re.M)) != expected_servers:
        raise ValueError("Unexpected public virtual host count")
    source = re.sub(r"^\s*access_log off;\n", "\n", source, flags=re.M)
    result = re.sub(r"^(\s*)server_name ([^;]+);",
                    lambda match: match.group(0) + "\n" + match[1] +
                    "access_log /var/log/app-egress/shared.jsonl app_egress;", source, flags=re.M)
    if thin:
        anchor = "  location /api/ { proxy_pass https://127.0.0.1:9443; }"
        if result.count(anchor) != 1:
            raise ValueError("Unexpected OpenCode API gateway")
        result = result.replace(anchor, anchor + "\n  location /client-cache/ { proxy_pass https://127.0.0.1:9443; }")
    return result


def render_tls(source):
    if "/client-cache/" in source or "app_direct" in source:
        raise ValueError("Already migrated")
    anchor = "    location / { return 404; }"
    if source.count(anchor) != 2 or source.count("auth_request /_opencode_auth;") != 4:
        raise ValueError("Expected two existing owner-authenticated TLS entry points")
    if source.count("  access_log off;") != 1:
        raise ValueError("Unexpected TLS logging configuration")
    result = source.replace("  access_log off;", DIRECT_FORMAT.rstrip())
    result = result.replace(anchor, THIN_LOCATION + anchor)
    return result
