import datetime as dt
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
spec=importlib.util.spec_from_file_location("traffic",Path(__file__).resolve().parents[1]/"server/traffic_summary.py")
module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module)
NOW=dt.datetime(2026,10,22,17,0,tzinfo=module.TZ)
class TrafficTest(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name);self.log=self.root/"shared.jsonl";self.state=self.root/"state"
 def tearDown(self):self.temp.cleanup()
 def line(self,amount=100,project="opencode",time="2026-10-22T17:00:00+08:00"):
  return json.dumps({"time":time,"project":project,"bytes":amount})+"\n"
 def run_summary(self):return module.aggregate(self.state,[self.log],NOW)
 def test_incremental_idempotent_and_project_isolation(self):
  self.log.write_text(self.line()+self.line(200,"fieldnotes"));first=self.run_summary();second=self.run_summary()
  self.assertEqual(first["http_bytes"],300);self.assertEqual(second["http_bytes"],300)
  with self.log.open("a") as f:f.write(self.line(50))
  third=self.run_summary();self.assertEqual(third["projects"]["opencode"]["bytes"],150)
 def test_rotated_inode_is_drained_once_and_new_file_counted(self):
  self.log.write_text(self.line());self.run_summary()
  with self.log.open("a") as f:f.write(self.line(20))
  self.log.rename(self.root/"shared.jsonl.1");self.log.write_text(self.line(30))
  result=self.run_summary();self.assertEqual(result["http_bytes"],150);self.assertEqual(self.run_summary()["http_bytes"],150)
 def test_partial_record_is_retried_without_loss_or_double_counting(self):
  text=self.line(123);self.log.write_text(text[:20]);self.assertEqual(self.run_summary()["http_bytes"],0)
  with self.log.open("a") as f:f.write(text[20:])
  self.assertEqual(self.run_summary()["http_bytes"],123)
 def test_invalid_records_and_other_months_do_not_pollute_current_month(self):
  self.log.write_text("not-json\n"+self.line(-1)+self.line(500,"unknown")+self.line(1000,time="2026-09-30T16:00:00+00:00")+self.line(20,time="2026-09-30T15:59:59+00:00"))
  # 16:00 UTC is midnight on Oct 1 in China.
  self.assertEqual(self.run_summary()["http_bytes"],1000)
 def test_published_summary_has_only_aggregate_counters(self):
  self.log.write_text(self.line());result=self.run_summary()
  self.assertEqual(json.loads((self.state/"public.json").read_text()),result)
  text=json.dumps(result);self.assertNotIn("Authorization",text);self.assertNotIn("http://",text);self.assertNotIn("username",text)
  self.assertEqual(result["quota_gb"],500)
if __name__=="__main__":unittest.main(verbosity=2)
