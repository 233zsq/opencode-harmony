"""Render a reviewable SNI candidate. Never installs certificates or reloads services."""
import argparse, pathlib, re

def render(source, domain):
    domain=domain.lower().rstrip('.')
    if len(domain)>253 or not re.fullmatch(r'(?:[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?\.)+[a-z]{2,63}',domain):
        raise ValueError('Use an ASCII DNS name, without scheme, port, wildcard or path')
    # This is intentionally a narrow migration for the already-owned, single-server entry.
    if re.search(r'^\s*include\s',source,re.M) or len(re.findall(r'\bserver\s*\{',source))!=1:
        raise ValueError('Inspect unexpected includes/multiple servers manually')
    required=['pid /run/opencode-harmony-tls/nginx.pid;', 'proxy_pass http://127.0.0.1:4097;',
              'proxy_pass http://127.0.0.1:4098;', 'auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;',
              'ssl_certificate /etc/opencode-harmony-tls/server.pem;', 'ssl_certificate_key /etc/opencode-harmony-tls/server.key;']
    if any(item not in source for item in required):
        raise ValueError('Source is not the expected dedicated TLS/settings configuration')
    if re.findall(r'\blisten\s+([^;]+);',source)!=['0.0.0.0:9443 ssl']:
        raise ValueError('Unexpected listener; no shared ports may be changed')
    start=re.search(r'\bserver\s*\{',source).start();opened=source.index('{',start);depth=1;end=opened+1
    # Known configuration has no braces in strings/comments; fail closed if that changes.
    if re.search(r'[\x22\x27#][^\n]*[{}]',source):raise ValueError('Ambiguous braces in source')
    while end<len(source) and depth:
        depth+=(source[end]=='{')-(source[end]=='}');end+=1
    if depth:raise ValueError('Unbalanced server block')
    original=source[start:end]
    clone=re.sub(r'^\s*server_name\s+[^;]+;\n?', '', original, flags=re.M)
    clone=clone.replace('server {','server {\n    server_name '+domain+';',1)
    clone=clone.replace('/etc/opencode-harmony-tls/server.pem','/etc/opencode-harmony-tls/domain/fullchain.pem')
    clone=clone.replace('/etc/opencode-harmony-tls/server.key','/etc/opencode-harmony-tls/domain/privkey.pem')
    original=original.replace('listen 0.0.0.0:9443 ssl;','listen 0.0.0.0:9443 ssl default_server;')
    return source[:start]+original+'\n  '+clone+source[end:]

def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('domain');parser.add_argument('--source',type=pathlib.Path,required=True);parser.add_argument('--output',type=pathlib.Path,required=True);args=parser.parse_args()
    if args.source.resolve()==args.output.resolve():parser.error('Output must differ from the live source')
    value=render(args.source.read_text(encoding='utf-8'),args.domain)
    with args.output.open('x',encoding='utf-8',newline='\n') as handle:handle.write(value)
    print('Candidate created only; verify certificate, DNS, nginx -t and rollback before activation.')
if __name__=='__main__':main()
