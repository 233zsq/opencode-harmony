import importlib.util,pathlib,unittest
spec=importlib.util.spec_from_file_location('entry',pathlib.Path(__file__).parents[1]/'scripts/prepare-domain-entry.py');entry=importlib.util.module_from_spec(spec);spec.loader.exec_module(entry)
SOURCE='''pid /run/opencode-harmony-tls/nginx.pid;
http {
 server {
 listen 0.0.0.0:9443 ssl;
 ssl_certificate /etc/opencode-harmony-tls/server.pem;
 ssl_certificate_key /etc/opencode-harmony-tls/server.key;
 limit_conn harmony_connections 20;
 location /api/ {
 auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;
 proxy_pass http://127.0.0.1:4097;
 proxy_buffering off;
 }
 location /client-settings/ { proxy_pass http://127.0.0.1:4098; }
 location / { return 404; }
 }
}
'''
class MigrationTest(unittest.TestCase):
 def test_preserves_both_backends_auth_and_limits(self):
  result=entry.render(SOURCE,'agent.example.com');self.assertIn('server_name agent.example.com;',result);self.assertIn('ssl default_server;',result)
  for text in ['proxy_pass http://127.0.0.1:4097;','proxy_pass http://127.0.0.1:4098;','auth_basic_user_file /etc/opencode-harmony-tls/htpasswd;','proxy_buffering off;','limit_conn harmony_connections 20;']:
   self.assertEqual(result.count(text),2)
  self.assertIn('/etc/opencode-harmony-tls/server.key;',result);self.assertIn('/etc/opencode-harmony-tls/domain/privkey.pem;',result)
 def test_rejects_shared_ports_injection_and_unknown_config(self):
  for domain in ['https://agent.example.com','agent.example.com; include x','*.example.com','127.0.0.1','a/b.example.com']:
   with self.assertRaises(ValueError):entry.render(SOURCE,domain)
  for source in [SOURCE.replace(':9443',':443'),SOURCE+'\ninclude /etc/nginx/*;\n',SOURCE.replace('4098','8080')]:
   with self.assertRaises(ValueError):entry.render(source,'agent.example.com')
if __name__=='__main__':unittest.main()
