"""Restricted provider settings for the dedicated OpenCode instance; not a file API."""
import base64
import fcntl
import hmac
import ipaddress
import json
import os
import pathlib
import re
import socket
import tempfile
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlsplit

CONFIG_DIR = pathlib.Path(os.environ.get('XDG_CONFIG_HOME', '/nonexistent')) / 'opencode'
CONFIG_FILE = CONFIG_DIR / 'opencode.json'
PACKAGE = '@opencode/ai/providers/openai-compatible'
IDENTIFIER = re.compile(r'mobile-[a-z0-9][a-z0-9-]{0,47}\Z')
MODEL = re.compile(r'[A-Za-z0-9_./:~+-]{1,160}\Z')
LOCK = threading.RLock()

class Invalid(ValueError):
    pass

class Busy(Exception):
    pass

def clean(value, maximum=4096):
    if not isinstance(value, str) or len(value) > maximum or any(ord(c) < 32 for c in value):
        raise Invalid('字段格式不正确')
    if re.search(r'\{(?:env|file):', value, re.I):
        raise Invalid('配置中不允许环境变量或文件插值')
    return value.strip()

def validate_base_url(value):
    value = clean(value, 2048).rstrip('/')
    parts = urlsplit(value)
    if parts.scheme != 'https' or not parts.hostname or parts.username or parts.password or parts.query or parts.fragment:
        raise Invalid('Base URL 必须是无认证参数的 HTTPS 地址')
    try:
        addresses = socket.getaddrinfo(parts.hostname, parts.port or 443, type=socket.SOCK_STREAM)
        if not addresses or any(not ipaddress.ip_address(a[4][0]).is_global for a in addresses):
            raise Invalid('渠道必须使用公网地址')
    except (OSError, ValueError):
        raise Invalid('无法验证渠道公网地址') from None
    return value

def validate_input(provider_id, data, previous):
    if not IDENTIFIER.fullmatch(provider_id) or not isinstance(data, dict):
        raise Invalid('只允许管理 mobile- 开头的渠道')
    if set(data) - {'id', 'name', 'baseURL', 'models', 'apiKey'} or data.get('id', provider_id) != provider_id:
        raise Invalid('包含不支持的设置字段')
    models = data.get('models')
    if not isinstance(models, list) or not 1 <= len(models) <= 100 or any(not isinstance(m, str) or not MODEL.fullmatch(m) for m in models):
        raise Invalid('请填写有效模型 ID，最多100个')
    if len(set(models)) != len(models):
        raise Invalid('模型 ID 不能重复')
    name = clean(data.get('name', ''), 128)
    if not name:
        raise Invalid('请填写渠道名称')
    key = clean(data['apiKey']) if 'apiKey' in data else clean(previous.get('settings', {}).get('apiKey', ''))
    if not isinstance(key, str):
        raise Invalid('已有密钥格式不支持编辑')
    return {'name': name, 'package': PACKAGE,
            'settings': {'baseURL': validate_base_url(data.get('baseURL')), 'apiKey': key},
            'models': {m: {'name': m} for m in models}}

def read_config():
    if CONFIG_FILE.is_symlink():
        raise Invalid('不支持符号链接配置')
    if not CONFIG_FILE.exists():
        if (CONFIG_DIR / 'opencode.jsonc').exists():
            raise Invalid('已有 JSONC 配置，请先在服务器规范化配置文件')
        return {}
    if CONFIG_FILE.stat().st_size > 2 * 1024 * 1024:
        raise Invalid('配置文件过大')
    try:
        value = json.loads(CONFIG_FILE.read_text('utf-8'))
    except (ValueError, UnicodeError):
        raise Invalid('已有配置不是标准 JSON，未修改原文件') from None
    if not isinstance(value, dict) or not isinstance(value.get('providers', {}), dict):
        raise Invalid('已有配置结构不支持编辑')
    return value

def public_rows(config):
    output = []
    for provider_id, value in config.get('providers', {}).items():
        if not IDENTIFIER.fullmatch(provider_id) or not isinstance(value, dict):
            continue
        settings = value.get('settings', {})
        if not isinstance(settings, dict):
            continue
        output.append({'id': provider_id, 'name': str(value.get('name', provider_id)),
                       'baseURL': str(settings.get('baseURL', '')), 'models': list(value.get('models', {})),
                       'hasKey': bool(settings.get('apiKey'))})
    return output

def atomic_write(config):
    CONFIG_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
    fd, temporary = tempfile.mkstemp(prefix='.mobile-provider-', dir=CONFIG_DIR)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'w', encoding='utf-8') as handle:
            json.dump(config, handle, ensure_ascii=False, indent=2)
            handle.write('\n'); handle.flush(); os.fsync(handle.fileno())
        os.replace(temporary, CONFIG_FILE)
        directory_fd = os.open(CONFIG_DIR, os.O_RDONLY | os.O_DIRECTORY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)

def auth_header():
    password = os.environ.get('OPENCODE_PASSWORD', '')
    if len(password) < 40:
        raise RuntimeError('Dedicated strong password required')
    return 'Basic ' + base64.b64encode(('opencode:' + password).encode()).decode()

def require_idle():
    headers = {'Authorization': auth_header(), 'Accept': 'application/json'}
    try:
        values = []
        for path in ['/api/session/active', '/api/form', '/api/permission/request']:
            with urllib.request.urlopen(urllib.request.Request('http://127.0.0.1:4097' + path, headers=headers), timeout=5) as response:
                value = json.load(response)
                values.append(value.get('data', value) if isinstance(value, dict) else value)
        if any(values):
            raise Busy('有运行中的任务或待处理交互，请先结束任务')
    except urllib.error.URLError:
        raise Busy('无法确认 Agent 空闲状态，暂不修改设置') from None

class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def reply(self, status, value):
        data = json.dumps(value, ensure_ascii=False).encode()
        self.send_response(status)
        self.send_header('Content-Type', 'application/json; charset=utf-8')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers(); self.wfile.write(data)

    def do_GET(self): self.handle_request()
    def do_PUT(self): self.handle_request()
    def do_DELETE(self): self.handle_request()

    def handle_request(self):
        if not hmac.compare_digest(self.headers.get('Authorization', ''), auth_header()):
            return self.reply(401, {'error': '认证失败'})
        path = urlsplit(self.path).path
        prefix = '/client-settings/providers'
        if path != prefix and not path.startswith(prefix + '/'):
            return self.reply(404, {'error': '接口不存在'})
        try:
            with LOCK:
                CONFIG_DIR.mkdir(parents=True, exist_ok=True, mode=0o700)
                with (CONFIG_DIR / '.mobile-settings.lock').open('a') as lock:
                    fcntl.flock(lock, fcntl.LOCK_EX)
                    config = read_config()
                    if self.command == 'GET' and path == prefix:
                        return self.reply(200, {'data': public_rows(config)})
                    provider_id = path[len(prefix) + 1:]
                    if not IDENTIFIER.fullmatch(provider_id):
                        raise Invalid('只允许管理 mobile- 开头的渠道')
                    require_idle()
                    providers = config.setdefault('providers', {})
                    if self.command == 'PUT':
                        length = int(self.headers.get('Content-Length', '0'))
                        if not 0 < length <= 65536:
                            return self.reply(413, {'error': '请求体过大或为空'})
                        data = json.loads(self.rfile.read(length))
                        providers[provider_id] = validate_input(provider_id, data, providers.get(provider_id, {}))
                    elif self.command == 'DELETE':
                        providers.pop(provider_id, None)
                    else:
                        return self.reply(405, {'error': '不支持的操作'})
                    atomic_write(config)
                    self.reply(200, {'data': public_rows(config)})
        except Busy as error:
            self.reply(409, {'error': str(error)})
        except (Invalid, ValueError, TypeError):
            self.reply(400, {'error': '设置校验失败：仅支持公网HTTPS、mobile-渠道、有效模型ID及纯文本凭据'})
        except Exception:
            self.reply(500, {'error': '设置保存结果未确认，请刷新查看'})

if __name__ == '__main__':
    auth_header()
    ThreadingHTTPServer(('127.0.0.1', 4098), Handler).serve_forever()
