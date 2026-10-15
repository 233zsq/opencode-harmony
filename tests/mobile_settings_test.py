import concurrent.futures
import importlib.util
import json
import os
import pathlib
import stat
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from unittest.mock import patch

source = os.environ.get('MOBILE_SETTINGS_SOURCE', str(pathlib.Path(__file__).parents[1] / 'server/mobile_settings.py'))
spec = importlib.util.spec_from_file_location('mobile_settings', source)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)

class SettingsTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='harmony-settings-test-')
        self.addCleanup(self.tmp.cleanup)
        folder = pathlib.Path(self.tmp.name)
        self.addCleanup(patch.stopall)
        patch.object(module, 'CONFIG_DIR', folder).start()
        patch.object(module, 'CONFIG_FILE', folder / 'opencode.json').start()
        patch.object(module, 'require_idle', lambda: None).start()
        patch.dict(os.environ, {'OPENCODE_PASSWORD': 'fixture-only-' + 'x' * 48}).start()
        original_dns = module.socket.getaddrinfo
        def fixture_dns(host, *args, **kwargs):
            return original_dns(host, *args, **kwargs) if host == '127.0.0.1' else [(2, 1, 6, '', ('93.184.216.34', 443))]
        patch.object(module.socket, 'getaddrinfo', side_effect=fixture_dns).start()

    def value(self, **extra):
        return {'id': 'mobile-test', 'name': 'Test', 'baseURL': 'https://api.example.com/v1', 'models': ['model-a'], 'apiKey': 'fixture-private-key', **extra}

    def test_fixed_package_and_key_preservation(self):
        value = module.validate_input('mobile-test', self.value(), {})
        self.assertEqual(value['package'], '@opencode/ai/providers/openai-compatible')
        saved = module.validate_input('mobile-test', {k:v for k,v in self.value().items() if k != 'apiKey'}, value)
        self.assertEqual(saved['settings']['apiKey'], 'fixture-private-key')

    def test_builtins_and_arbitrary_fields_rejected(self):
        for identifier in ['openai', '../opencode', 'mobile-../x']:
            with self.assertRaises(module.Invalid): module.validate_input(identifier, self.value(), {})
        with self.assertRaises(module.Invalid): module.validate_input('mobile-test', self.value(path='/tmp/x'), {})
        with self.assertRaises(module.Invalid): module.validate_input('mobile-test', self.value(package='malicious'), {})

    def test_interpolation_rejected_in_all_text_inputs(self):
        for key in ['name', 'baseURL', 'apiKey']:
            with self.assertRaises(module.Invalid): module.validate_input('mobile-test', self.value(**{key:'{file:/tmp/secret}'}), {})
        with self.assertRaises(module.Invalid): module.validate_input('mobile-test', self.value(models=['{env:KEY}']), {})

    def test_url_must_be_public_https_without_credentials(self):
        for url in ['http://api.example.com', 'https://user:pass@api.example.com', 'https://api.example.com?key=x', 'https://api.example.com#x']:
            with self.assertRaises(module.Invalid): module.validate_base_url(url)
        for address in ['127.0.0.1', '10.0.0.1', '169.254.169.254', '::1']:
            with patch.object(module.socket, 'getaddrinfo', return_value=[(2,1,6,'',(address,443))]):
                with self.assertRaises(module.Invalid): module.validate_base_url('https://api.example.com')

    def test_model_ids_and_duplicates_rejected(self):
        for models in [[], ['bad model'], ['a','a'], ['../model with spaces'], ['a'] * 101]:
            with self.assertRaises(module.Invalid): module.validate_input('mobile-test', self.value(models=models), {})

    def test_public_response_does_not_include_keys(self):
        config={'providers':{'mobile-test':module.validate_input('mobile-test',self.value(),{}),'openai':{'settings':{'apiKey':'other-secret'}}}}
        text=json.dumps(module.public_rows(config));self.assertNotIn('fixture-private-key',text);self.assertNotIn('other-secret',text)
        self.assertTrue(module.public_rows(config)[0]['hasKey'])

    def test_atomic_write_permissions_and_unrelated_fields(self):
        config={'username':'keep','providers':{'openai':{'name':'untouched'}}}
        module.atomic_write(config);self.assertEqual(module.read_config(),config)
        self.assertEqual(stat.S_IMODE(module.CONFIG_FILE.stat().st_mode),0o600)

    def test_failed_replace_preserves_original_and_removes_temporary(self):
        module.atomic_write({'username':'old'})
        with patch.object(module.os,'replace',side_effect=OSError('fixture failure')):
            with self.assertRaises(OSError):module.atomic_write({'username':'new'})
        self.assertEqual(module.read_config(),{'username':'old'})
        self.assertFalse(list(module.CONFIG_DIR.glob('.mobile-provider-*')))

    def test_jsonc_and_symlinks_are_not_overwritten(self):
        (module.CONFIG_DIR/'opencode.jsonc').write_text('{}')
        with self.assertRaises(module.Invalid):module.read_config()
        (module.CONFIG_DIR/'opencode.jsonc').unlink();target=module.CONFIG_DIR/'fixture.json';target.write_text('{}')
        module.CONFIG_FILE.symlink_to(target)
        with self.assertRaises(module.Invalid):module.read_config()

    def server(self):
        server=module.ThreadingHTTPServer(('127.0.0.1',0),module.Handler)
        thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
        self.addCleanup(server.server_close);self.addCleanup(server.shutdown)
        return 'http://127.0.0.1:'+str(server.server_port)

    def request(self,base,path,method='GET',body=None,auth=True):
        headers={'Authorization':module.auth_header()} if auth else {}
        if body is not None:headers['Content-Type']='application/json'
        request=urllib.request.Request(base+path,data=None if body is None else json.dumps(body).encode(),headers=headers,method=method)
        try:
            with urllib.request.urlopen(request,timeout=5) as r:return r.status,json.load(r)
        except urllib.error.HTTPError as e:
            with e:return e.code,json.load(e)

    def test_http_auth_busy_guard_and_redacted_crud(self):
        base=self.server();path='/client-settings/providers/mobile-test'
        self.assertEqual(self.request(base,'/client-settings/providers',auth=False)[0],401)
        with patch.object(module,'require_idle',side_effect=module.Busy('fixture busy')):
            self.assertEqual(self.request(base,path,'PUT',self.value())[0],409)
        self.assertFalse(module.CONFIG_FILE.exists())
        self.assertEqual(self.request(base,path,'PUT',self.value())[0],200)
        status,body=self.request(base,'/client-settings/providers');self.assertEqual(status,200)
        self.assertNotIn('fixture-private-key',json.dumps(body));self.assertTrue(body['data'][0]['hasKey'])
        self.assertEqual(self.request(base,path,'DELETE')[0],200)
        self.assertEqual(self.request(base,'/client-settings/providers')[1]['data'],[])

    def test_concurrent_edits_preserve_both_providers(self):
        base=self.server()
        def save(identifier):return self.request(base,'/client-settings/providers/'+identifier,'PUT',self.value(id=identifier))[0]
        with concurrent.futures.ThreadPoolExecutor(2) as pool:self.assertEqual(list(pool.map(save,['mobile-one','mobile-two'])),[200,200])
        self.assertEqual(set(module.read_config()['providers']),{'mobile-one','mobile-two'})

if __name__=='__main__':unittest.main(verbosity=2)
