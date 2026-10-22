import importlib.util
from pathlib import Path
import unittest
spec=importlib.util.spec_from_file_location("renderer",Path(__file__).resolve().parents[1]/"scripts/prepare-traffic-entry.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
class EntryTest(unittest.TestCase):
 def test_public_vhosts_and_thin_route(self):
  source="server {\n  server_name opencode.bigdogaaa.cn;\n  access_log off;\n  location /api/ { proxy_pass https://127.0.0.1:9443; }\n}\nserver {\n  server_name opencode.bigdogaaa.cn;\n  return 308 https://opencode.bigdogaaa.cn$request_uri;\n}\n"
  result=module.render_public(source,2,True)
  self.assertEqual(result.count("shared.jsonl app_egress;"),2)
  self.assertEqual(result.count("location /client-cache/"),1)
  self.assertNotIn("access_log off",result)
  with self.assertRaises(ValueError):module.render_public(result,2,True)
  with self.assertRaises(ValueError):module.render_public(source,3)
 def test_tls_owner_authentication_and_original_peer_filter(self):
  source="http {\n  access_log off;\n"+"auth_request /_opencode_auth;\n"*4+"    location / { return 404; }\n"*2+"}"
  result=module.render_tls(source)
  self.assertEqual(result.count("location /client-cache/"),2)
  self.assertEqual(result.count("auth_request /_opencode_auth;"),6)
  self.assertIn("map $realip_remote_addr $traffic_public",result)
  self.assertIn("if=$traffic_public",result)
  self.assertEqual(result.count('proxy_set_header Cookie "";'),2)
  with self.assertRaises(ValueError):module.render_tls(result)
 def test_logging_contains_no_request_identity_or_content(self):
  for value in [module.SHARED_FORMAT,module.DIRECT_FORMAT]:
   for forbidden in ["$request_uri","$args","$http_authorization","$http_cookie","$request_body","$remote_addr"]:
    self.assertNotIn(forbidden,value)
if __name__=="__main__":unittest.main(verbosity=2)
