import assert from 'node:assert/strict';
import {spawnSync} from 'node:child_process';
import {testEndpoint,liveCredentials,liveConfig,tlsFixture} from './helpers/live-config.mjs';
const fixture={OPENCODE_TEST_URL:'https://fixture.example.test:9443/',
 OPENCODE_TEST_USERNAME:'fixture-owner',OPENCODE_TEST_PASSWORD:'fixture-password:中文'};
const pin=Buffer.alloc(32,1).toString('base64');
let count=0;
function test(name,run){run();count++;console.log('PASS '+name);}

test('every real target and credential is explicit, with no legacy environment fallback',()=>{
 for(const name of Object.keys(fixture)){
  const env={...fixture,OPENCODE_PASSWORD:'legacy-fixture',OPENCODE_USERNAME:'legacy-owner'};delete env[name];
  assert.throws(()=>liveConfig(env),new RegExp(name));
 }
});
test('invalid URLs cannot carry credentials or select plaintext transport',()=>{
 for(const value of ['http://fixture.example.test','https://owner:fixture-secret@fixture.example.test',
  'https://fixture.example.test?key=fixture-secret','https://fixture.example.test#fixture-secret',
  'https://fixture.example.test?','https://fixture.example.test#','invalid fixture-secret']){
  assert.throws(()=>testEndpoint({...fixture,OPENCODE_TEST_URL:value}),error=>
   error.message.includes('OPENCODE_TEST_URL')&&!error.message.includes('fixture-secret'));
 }
});
test('URL prefixes and explicit ports remain usable',()=>{
 assert.equal(testEndpoint(fixture),'https://fixture.example.test:9443');
 assert.equal(testEndpoint({...fixture,OPENCODE_TEST_URL:'https://fixture.example.test/prefix/'}),'https://fixture.example.test/prefix');
});
test('owner Basic preserves UTF-8 passwords and embedded colons',()=>{
 const config=liveConfig(fixture);
 assert.equal(Buffer.from(config.auth.slice(6),'base64').toString(),fixture.OPENCODE_TEST_USERNAME+':'+fixture.OPENCODE_TEST_PASSWORD);
});
test('unsafe usernames and password controls fail with no credential values',()=>{
 for(const username of [' ', 'fixture:owner', 'fixture\nowner'])assert.throws(()=>liveCredentials({...fixture,OPENCODE_TEST_USERNAME:username}),/OPENCODE_TEST_USERNAME/);
 assert.throws(()=>liveCredentials({...fixture,OPENCODE_TEST_PASSWORD:'sensitive-fixture\nvalue'}),error=>
  error.message.includes('OPENCODE_TEST_PASSWORD')&&!error.message.includes('sensitive-fixture'));
});
test('system trust does not read any local credential or certificate file',()=>{
 const config=liveConfig(fixture,{readText:()=>{throw new Error('Unexpected file read');}});
 assert.equal(config.ca,undefined);assert.equal(config.pin,undefined);
});
test('dedicated CA requires an explicit pin before reading the certificate',()=>{
 let reads=0;
 assert.throws(()=>liveConfig({...fixture,OPENCODE_TEST_CA_FILE:'fixture-ca.pem'},{readText:()=>{reads++;}}),/OPENCODE_TEST_PIN/);
 assert.equal(reads,0);
});
test('dedicated trust reads only the named CA',()=>{
 const reads=[];
 const config=liveConfig({...fixture,OPENCODE_TEST_CA_FILE:'fixture-ca.pem',OPENCODE_TEST_PIN:pin},
  {readText:(path,encoding)=>{reads.push([path,encoding]);return 'fixture-ca';}});
 assert.deepEqual(reads,[['fixture-ca.pem','utf8']]);assert.equal(config.ca,'fixture-ca');assert.equal(config.pin,pin);
});
test('a public certificate may also have an explicit pin',()=>{
 assert.equal(liveConfig({...fixture,OPENCODE_TEST_PIN:pin}).pin,pin);
});
test('invalid pins are rejected before local file access',()=>{
 for(const value of ['not-a-pin',Buffer.alloc(31).toString('base64'),Buffer.alloc(33).toString('base64'),pin.slice(0,-2)+'B=']){
  assert.throws(()=>liveConfig({...fixture,OPENCODE_TEST_PIN:value},{readText:()=>assert.fail('Unexpected read')}),/OPENCODE_TEST_PIN/);
 }
});
test('certificate read errors do not expose private paths',()=>{
 assert.throws(()=>liveConfig({...fixture,OPENCODE_TEST_CA_FILE:'private-fixture-path',OPENCODE_TEST_PIN:pin},
  {readText:()=>{throw new Error('private-fixture-path');}}),error=>
   error.message==='Unable to read OPENCODE_TEST_CA_FILE');
});
test('negative TLS fixture validates both explicit filenames before any read',()=>{
 let reads=0;
 assert.throws(()=>tlsFixture({OPENCODE_TLS_FIXTURE_KEY_FILE:'fixture.key'},{readText:()=>{reads++;}}),/OPENCODE_TLS_FIXTURE_CERT_FILE/);
 assert.equal(reads,0);
 const files=[];
 const result=tlsFixture({OPENCODE_TLS_FIXTURE_KEY_FILE:'fixture.key',OPENCODE_TLS_FIXTURE_CERT_FILE:'fixture.pem'},
  {readText:path=>{files.push(path);return 'synthetic';}});
 assert.deepEqual(files,['fixture.key','fixture.pem']);assert.equal(result.key,'synthetic');
});

function child(code,extra={}) {
 const env={...process.env};
 for(const name of Object.keys(env))if(name.startsWith('OPENCODE_'))delete env[name];
 Object.assign(env,extra);
 return spawnSync(process.execPath,['--input-type=module','-e',code],{cwd:import.meta.dirname+'/..',env,encoding:'utf8',timeout:5000});
}
test('real API import fails before network use when credentials are absent',()=>{
 const result=child("await import('./tests/live-api.mjs')",{OPENCODE_TEST_URL:fixture.OPENCODE_TEST_URL});
 assert.notEqual(result.status,0);assert.match(result.stderr,/OPENCODE_TEST_USERNAME/);
 assert.doesNotMatch(result.stderr,/ENOENT|server\.env/);
});
test('real API uses owner credentials and standard TLS without an operation directory',()=>{
 const result=child("const {options,endpoint}=await import('./tests/live-api.mjs'); const o=options(); if(endpoint!=='https://fixture.example.test:9443'||Buffer.from(o.headers.Authorization.slice(6),'base64').toString()!=='fixture-owner:fixture-password:中文'||o.ca!==undefined||o.checkServerIdentity!==undefined||o.rejectUnauthorized!==true)process.exit(2)",fixture);
 assert.equal(result.status,0,result.stderr);
});
test('negative TLS server has no implicit private key source',()=>{
 const result=child("await import('./tests/wrong-tls-server.mjs')");
 assert.notEqual(result.status,0);assert.match(result.stderr,/OPENCODE_TLS_FIXTURE_KEY_FILE/);
 assert.doesNotMatch(result.stderr,/ENOENT|wrong\.key/);
});
test('glob and emulator model modes require opt-in before external work',()=>{
 for(const code of ["await import('./tests/glob-live.test.mjs')",
  "process.argv[2]='live-send';await import('./tests/emulator-smoke.mjs')"]){
  const result=child(code,fixture);assert.notEqual(result.status,0);assert.match(result.stderr,/OPENCODE_ALLOW_MODEL_TEST/);
 }
});
console.log(count+' live configuration tests passed. No real service or device used.');
