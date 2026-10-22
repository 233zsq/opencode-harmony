"""Render only OpenCode's two Nginx entry configs. No credentials in output."""
import re

AUTH_LOCATION = """
    location = /_opencode_auth {
      internal;
      proxy_pass http://127.0.0.1:4099/internal/check;
      proxy_pass_request_body off;
      proxy_set_header Content-Length "";
      proxy_set_header Host opencode.bigdogaaa.cn;
      proxy_set_header Authorization $http_authorization;
      proxy_set_header X-Client-IP $remote_addr;
      proxy_set_header Cookie "";
    }
"""


def render_tls(source):
    if source.count("auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;") != 4:
        raise ValueError("Unexpected original authentication configuration")
    if "127.0.0.1:4099" in source or source.count("    location / { return 404; }") != 2:
        raise ValueError("Already migrated or unknown config")
    expected = """      auth_basic 'OpenCode Harmony';
      auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;"""
    replacement = """      auth_request /_opencode_auth;
      auth_request_set $account_upstream_auth $upstream_http_x_opencode_upstream_authorization;
      proxy_set_header Authorization $account_upstream_auth;
      proxy_set_header Cookie "";"""
    if source.count(expected) != 4:
        raise ValueError("Original blocks differ")
    result = source.replace(expected, replacement)
    result = result.replace("    location / { return 404; }", AUTH_LOCATION + "    location / { return 404; }")
    if result.count("auth_request /_opencode_auth;") != 4:
        raise ValueError("Incomplete migration")
    return result


def render_front(source):
    expected = """  auth_basic "OpenCode Harmony";
  auth_basic_user_file /etc/nginx/opencode-harmony.htpasswd;
"""
    if source.count(expected) != 1 or source.count("location / { proxy_pass https://127.0.0.1:9443; }") != 1:
        raise ValueError("Unexpected front configuration")
    result = source.replace(expected, "")
    result = result.replace("location / { proxy_pass https://127.0.0.1:9443; }", """location = /internal/check { return 404; }
  location = /_opencode_auth { return 404; }
  location = /health { return 404; }
  location / {
    proxy_pass http://127.0.0.1:4099;
    proxy_set_header Host opencode.bigdogaaa.cn;
    proxy_set_header Authorization "";
    proxy_set_header X-Client-IP $remote_addr;
    proxy_set_header X-Forwarded-Proto https;
    client_max_body_size 8k;
  }""")
    return result
