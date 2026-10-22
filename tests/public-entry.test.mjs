import https from 'node:https';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash, X509Certificate, timingSafeEqual } from 'node:crypto';
import { resolve } from 'node:path';
const root=resolve(import.meta.dirname,'..');
const url=process.env.OPENCODE_TEST_URL;
if(!url?.startsWith('https://'))throw new Error('Set OPENCODE_TEST_URL to the dedicated HTTPS endpoint');
const ca=readFileSync(resolve(root,'.server-access/tls/ca.pem'),'utf8');
const pin=JSON.parse(readFileSync(resolve(root,'.server-access/tls/public-trust.json'),'utf8')).pin;
// Owner credentials may be injected for this run without persisting the new password.
const env=process.env.OPENCODE_TEST_PASSWORD ? {} : Object.fromEntries(readFileSync(resolve(root,'.server-access/server.env'),'utf8').trim().split(/\r?\n/).map(line=>{const i=line.indexOf('=');return [line.slice(0,i),line.slice(i+1)];}));
const username=process.env.OPENCODE_TEST_USERNAME||env.OPENCODE_USERNAME||'opencode';
const passwordValue=process.env.OPENCODE_TEST_PASSWORD||env.OPENCODE_PASSWORD;
if(!passwordValue||username.includes(':'))throw new Error('Supply the current owner credentials privately');
const auth='Basic '+Buffer.from(username+':'+passwordValue).toString('base64');
function request(path, {authenticated=false, password, trust=true, badName=false, expectedPin=pin, sse=false, headers={}, method='GET'}={}) {
  return new Promise((resolve,reject)=>{
    const options={agent:false, ca:trust?ca:undefined, method, headers:{...headers}};
    if(authenticated)options.headers.Authorization=auth;
    if(password)options.headers.Authorization='Basic '+Buffer.from(username+':'+password).toString('base64');
    if(badName)options.servername='wrong-host.invalid';
    const task=https.request(url+path,options,res=>{
      const cert=res.socket.getPeerCertificate();const key=new X509Certificate(cert.raw).publicKey.export({type:'spki',format:'der'});
      const actual=createHash('sha256').update(key).digest();const expected=Buffer.from(expectedPin,'base64');
      if(actual.length!==expected.length||!timingSafeEqual(actual,expected)){task.destroy();reject(new Error('PIN_MISMATCH'));return;}
      let body='';res.on('data',chunk=>{body+=chunk; if(sse&&body.includes('\n\n')){resolve({code:res.statusCode,type:res.headers['content-type'],body});task.destroy();}});
      res.on('end',()=>resolve({code:res.statusCode,type:res.headers['content-type'],body}));
    });
    task.setTimeout(12000,()=>task.destroy(new Error('CONNECT_TIMEOUT')));task.on('error',reject);task.end();
  });
}
try {
  assert.equal((await request('/api/info')).code,401); console.log('PASS unauthenticated request is denied');
  assert.equal((await request('/api/info',{password:'deliberately-wrong'})).code,401);console.log('PASS wrong password is denied');
  assert.equal((await request('/client-settings/providers')).code,401);console.log('PASS unauthenticated settings catalog is denied');
  const settings=await request('/client-settings/providers',{authenticated:true});assert.equal(settings.code,200);
  for(const provider of JSON.parse(settings.body).data)assert.deepEqual(Object.keys(provider).sort(),['baseURL','hasKey','id','models','name']);console.log('PASS authenticated settings catalog exposes only redacted fields');
  const info=await request('/api/info',{authenticated:true});assert.equal(info.code,200);assert.equal(JSON.parse(info.body).version,'2.0.29');console.log('PASS certificate, SPKI and authenticated API version');
  await assert.rejects(request('/api/info',{trust:false}));console.log('PASS unknown CA is rejected');
  await assert.rejects(request('/api/info',{badName:true}), /Hostname\/IP|altnames|does not match/i);console.log('PASS incorrect hostname is rejected');
  await assert.rejects(request('/api/info',{expectedPin:Buffer.alloc(32).toString('base64')}), /PIN_MISMATCH/);console.log('PASS incorrect SPKI is rejected');
  assert.equal((await request('/',{authenticated:true})).code,404);console.log('PASS web UI is not publicly exposed');
  assert.equal((await request('/api/test',{method:'POST',headers:{'Content-Length':3*1024*1024}})).code,413);console.log('PASS oversized request body is rejected');
  const event=await request('/api/event',{authenticated:true,sse:true});assert.equal(event.code,200);assert.match(event.type,/text\/event-stream/);console.log('PASS real SSE streams through HTTPS');
  const responses=await Promise.all(Array.from({length:70},()=>request('/api/info')));assert.ok(responses.some(r=>r.code===429));assert.ok(responses.every(r=>r.code===401||r.code===429));console.log('PASS burst traffic is throttled with HTTP 429');
} catch(error) { console.error('Public entry test failed:',error.code||error.message);process.exitCode=1; }
