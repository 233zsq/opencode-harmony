"""Thin history and private traffic page fixtures; never use production credentials."""
import base64
import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
spec=importlib.util.spec_from_file_location("cache_account",Path(__file__).resolve().parents[1]/"server/account/app.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
ORIGIN="https://opencode.bigdogaaa.cn"
SECRET="fixture-internal-"+"x"*48
HEADER="Basic "+base64.b64encode(("opencode:"+SECRET).encode()).decode()
DATA=base64.b64encode(b"fixture-only-image").decode()
HASH=hashlib.sha256(DATA.encode()).hexdigest()

class CacheTest(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.paths=[]
  self.message={"id":"msg_test","type":"user","content":"fixture text · 中文",
                "files":[{"name":"fixture.png","mime":"image/png","data":DATA}]}
  def fetch(path):
   self.paths.append(path)
   return copy.deepcopy({"data":self.message} if "/message/msg_test" in path else {"data":[self.message],"cursor":"next-fixture"})
  self.app=module.create_app({"TESTING":True,"DATABASE":str(self.root/"account.sqlite3"),
   "PUBLIC_ORIGIN":ORIGIN,"UPSTREAM_PASSWORD":SECRET,"RATE_SECRET":"fixture-rate-"+"r"*48,
   "HISTORY_FETCH":fetch,"TRAFFIC_SUMMARY":str(self.root/"public.json")})
  self.client=self.app.test_client()
 def tearDown(self):self.temp.cleanup()
 def get(self,path,header=HEADER,remote="127.0.0.1"):
  return self.client.get(path,base_url=ORIGIN,headers={"Authorization":header},environ_overrides={"REMOTE_ADDR":remote})
 def test_history_requires_injected_internal_auth_and_loopback(self):
  for header,remote in [("","127.0.0.1"),("Basic invalid","127.0.0.1"),(HEADER,"192.0.2.1")]:
   self.assertEqual(self.get("/client-cache/capabilities",header,remote).status_code,403)
  self.assertEqual(self.get("/client-cache/capabilities").json,{"data":{"version":1}})
  self.assertEqual(self.paths,[])
 def test_thin_history_keeps_text_cursor_and_hash_without_inline_image(self):
  response=self.get("/client-cache/session/ses_test/message?limit=30&order=desc")
  self.assertEqual(response.status_code,200);result=response.json
  self.assertEqual(result["cursor"],"next-fixture");self.assertEqual(result["data"][0]["content"],"fixture text · 中文")
  self.assertIn("中文",response.get_data(as_text=True))
  file=result["data"][0]["files"][0]
  self.assertEqual(file["data"],"");self.assertEqual(file["sha256"],HASH);self.assertEqual(file["size"],18)
  self.assertNotIn(DATA,response.get_data(as_text=True))
 def test_lazy_file_validates_hash_and_index(self):
  url="/client-cache/session/ses_test/message/msg_test/file/0?sha256="
  self.assertEqual(self.get(url+HASH).json["data"]["data"],DATA)
  self.assertEqual(self.get(url+"0"*64).status_code,409)
  self.assertEqual(self.get(url+"bad").status_code,400)
  self.assertEqual(self.get(url.replace("/0?","/4?")+HASH).status_code,400)
  self.message["id"]="msg_other"
  self.assertEqual(self.get(url+HASH).status_code,404)
 def test_untrusted_paths_and_query_never_reach_upstream(self):
  for path in ["/client-cache/session/ses%3Atest/message","/client-cache/session/ses_test/message?limit=1000",
   "/client-cache/session/ses_test/message?limit=30&limit=1","/client-cache/session/ses_test/message?url=http://evil",
   "/client-cache/session/ses_test/message?order=asc","/client-cache/session/ses_test/message?cursor="+"x"*2049,
   "/client-cache/session/ses_test/message/msg_test/file/0?sha256="+HASH+"&sha256="+"0"*64]:
   self.assertEqual(self.get(path).status_code,400,path)
  self.assertEqual(self.paths,[])
 def test_invalid_upstream_and_oversized_attachment_fail_safely(self):
  self.app.config["HISTORY_FETCH"]=lambda _:{"data":{}}
  self.assertEqual(self.get("/client-cache/session/ses_test/message").status_code,502)
  self.app.config["HISTORY_FETCH"]=lambda _:{"data":None}
  self.assertEqual(self.get("/client-cache/session/ses_test/message/msg_test/file/0?sha256="+HASH).status_code,502)
 def test_traffic_is_owner_session_only_with_safe_unavailable_state(self):
  self.assertEqual(self.get("/auth/traffic").status_code,401)
  raw="f"*43
  with self.app.account_db() as db:
   import time
   db.execute("INSERT INTO sessions VALUES(?,?,?,?,?)",(hashlib.sha256(raw.encode()).hexdigest(),"fixture-owner","csrf",int(time.time()),int(time.time())+300))
  self.client.set_cookie(module.COOKIE,raw,domain="opencode.bigdogaaa.cn")
  self.assertFalse(self.get("/auth/traffic").json["data"]["available"])
  sample={"version":1,"available":True,"http_bytes":123,"projects":{"opencode":{"bytes":123,"requests":1}}}
  (self.root/"public.json").write_text(json.dumps(sample))
  self.assertEqual(self.get("/auth/traffic").json["data"],sample)
if __name__=="__main__":unittest.main(verbosity=2)
