import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import vm from 'node:vm';
const require = createRequire(import.meta.url);
const root = resolve(import.meta.dirname, '..');
const ts = require(resolve(process.env.DEVECO_STUDIO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
class Encoder { encodeInto(value) { return new TextEncoder().encode(value); } }
class Decoder { constructor() { this.decoder = new TextDecoder(); } decodeToString(value, options) { return this.decoder.decode(value, options); } }
class Base64 { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } }
const requests = [];
const httpMock = {
  RequestMethod: { GET: 'GET', POST: 'POST', DELETE: 'DELETE', PATCH: 'PATCH', PUT: 'PUT' }, HttpDataType: { STRING: 0 },
  createHttp: () => ({
    request: async (url, options) => { requests.push({ url, options }); return { responseCode: 200, result: '{"version":"2.0.29"}' }; },
    destroy() {}, on() {}, requestInStream: async (url, options) => { requests.push({ url, options }); return 200; }
  })
};
class StorageMock { async sessionPreferences() { return []; } async saveSessionPreferences() {} async init() {} async servers() { return []; } async secret() { return 'test-only'; } async last() { return []; } async position() {} async activeServer() { return ''; } async rememberServer() {} }
const modules = new Map([
  ['@kit.NetworkKit', { http: httpMock }],
  ['@kit.ArkTS', { util: { TextEncoder: Encoder, TextDecoder: Decoder, Base64Helper: Base64 } }],
  ['@kit.AbilityKit', {}], ['@kit.BasicServicesKit', {}], ['../data/Storage', { Storage: StorageMock }]
]);
function load(file, key) {
  const exports = {};
  const code = ts.transpileModule(readFileSync(resolve(root, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    if (!modules.has(name)) throw new Error('Unmocked platform dependency: ' + name);
    return modules.get(name);
  }, Observed: value => value, setTimeout: () => -1, clearTimeout() {}, setInterval: () => -1, clearInterval() {},
  console, Error, Map, Set, Date, Math, JSON });
  modules.set(key, exports);
  return exports;
}
load('entry/src/main/ets/domain/Attachments.ts', '../domain/Attachments');
const core = load('entry/src/main/ets/domain/Core.ts', '../domain/Core');
const trust = load('entry/src/main/ets/data/DedicatedTrust.ets', './DedicatedTrust');
const agentsDomain=load('entry/src/main/ets/domain/Agents.ts', '../domain/Agents');
const exportsDomain=load('entry/src/main/ets/domain/TranscriptExport.ts', '../domain/TranscriptExport');
const protocol = load('entry/src/main/ets/data/Protocol.ets', '../data/Protocol');
const { ProviderStore } = load('entry/src/main/ets/presentation/ProviderStore.ets', './ProviderStore');
const { AppStore } = load('entry/src/main/ets/presentation/AppStore.ets', 'store');
let count = 0;
async function test(name, run) { await run(); count++; console.log('PASS ' + name); }
const message = (id, text) => ({ id, role: 'assistant', text, reasoning: '', tools: [], parts: [], state: 'completed' });
const form = () => ({ id: 'frm_a', sessionID: 'ses_a', kind: 'form', title: 'Question', detail: '', fields: [], state: 'pending' });

await test('same auth is injected into HTTP and SSE', async () => {
  const api = new protocol.Protocol({ id: 'a', name: 'test', url: 'https://example.com/prefix', username: 'opencode', allowHttp: false }, 'test-only');
  await api.request('/api/info');
  const close = api.stream(() => {}, () => {}, () => {}); close();
  assert.equal(requests.at(-2).options.header.Authorization, requests.at(-1).options.header.Authorization);
  assert.equal(requests.at(-1).url, 'https://example.com/prefix/api/event');
});
await test('V2 project canonical and modelID use actual HTTP envelopes', async () => {
  const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, '');
  api.request = async path => path === '/api/project' ? [{ id: 'p', canonical: '/repo', name: 'Repo' }] :
    { data: [{ id: 'compound-id', providerID: 'provider', modelID: 'actual/model', name: 'Display', enabled: true }] };
  assert.equal((await api.projects())[0].directory, '/repo');
  assert.equal((await api.models('/repo'))[0].id, 'provider/actual/model');
});
await test('V2 assistant content parses reasoning and tools without V1 parts', async () => {
  const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, '');
  const result = api.parseMessages({ data: [{ id: 'm', type: 'assistant', time: { completed: 1 },
    content: [{ type: 'reasoning', text: 'think' }, { type: 'text', text: 'answer' },
      { type: 'tool', id: 'c', name: 'read', state: { status: 'completed', input: { path: 'a' }, content: [{ type: 'text', text: 'file' }] } }] }] });
  assert.equal(result[0].text, 'answer'); assert.equal(result[0].reasoning, 'think');
  assert.equal(result[0].tools[0].output, 'file');
});
await test('failed pending read retains card; successful empty read removes it', async () => {
  const store = new AppStore(); store.interactions = [form()];
  await store.syncInteractions({ interactions: async () => { throw new Error('network'); } }, 'ses_a', 'form', 0);
  assert.equal(store.interactions.length, 1);
  await store.syncInteractions({ interactions: async () => [] }, 'ses_a', 'form', 0);
  assert.equal(store.interactions.length, 0);
});
await test('late history after disconnect cannot contaminate another connection', async () => {
  const store = new AppStore(); store.sessionID = 'ses_old';
  let release;
  store.api = { messages: () => new Promise(resolve => { release = resolve; }), parseMessages: () => [message('old', 'old')] };
  const pending = store.sync();
  store.disconnect();
  release({ data: [] }); await pending;
  assert.equal(store.messages.length, 0); assert.equal(store.sessionID, '');
});
await test('lost send acknowledgement retains immutable message ID for retry', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.draft = 'task'; store.active = false;
  const attempts = [];
  store.api = { request: async (path, method, body) => {
    attempts.push(body);
    if (attempts.length === 1) throw new Error('lost acknowledgement');
  } };
  await store.send();
  assert.ok(store.pendingSend);
  await store.send();
  assert.equal(attempts[0].id, attempts[1].id); assert.equal(attempts[0].text, attempts[1].text);
  assert.equal(store.pendingSend, undefined);
});
await test('duplicate SSE IDs and ended snapshots do not duplicate text', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.directory = '/repo';
  const event = { id: 'evt_a', type: 'session.text.delta', location: { directory: '/repo' },
    data: { sessionID: 'ses_a', assistantMessageID: 'm', ordinal: 0, delta: 'hello' } };
  store.onFrame({ data: JSON.stringify(event) }); store.onFrame({ data: JSON.stringify(event) });
  assert.equal(store.messages[0].text, 'hello');
  store.onFrame({ data: JSON.stringify({ ...event, id: 'evt_b', type: 'session.text.ended', data: { ...event.data, text: 'hello' } }) });
  assert.equal(store.messages[0].text, 'hello');
});
await test('event from other project or session is ignored', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.directory = '/repo';
  store.onFrame({ data: JSON.stringify({ id: 'evt_other', type: 'session.text.delta', location: { directory: '/other' },
    data: { sessionID: 'ses_a', assistantMessageID: 'm', ordinal: 0, delta: 'foreign' } }) });
  assert.equal(store.messages.length, 0);
});
await test('model switching sends raw modelID, not catalog identity', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.active = false;
  let request;
  store.api = { request: async (path, method, body) => { request = body; } };
  await store.chooseModel('provider/actual/model');
  assert.deepEqual(JSON.parse(JSON.stringify(request)), { model: { id: 'actual/model', providerID: 'provider' } });
});


await test('reused ArkUI card submits current draft instead of captured old item', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.active = false;
  const stale = form();
  stale.fields = [{ key: 'choice', label: 'choice', type: 'string', required: true, options: [], values: [], text: '' }];
  store.interactions = [stale]; store.updateField(stale.id, 'choice', 'current answer');
  let body;
  store.api = { request: async (path, method, value) => { body = value; } };
  await store.reply(stale);
  assert.equal(body.answer.choice, 'current answer'); assert.equal(store.interactions.length, 0);
});
await test('polling does not reopen history cursor after last page', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.tailLoaded = true; store.cursor = '';
  store.api = { messages: async () => ({ data: [], cursor: { next: 'old-page' } }), parseMessages: () => [],
    interactions: async () => [], request: async () => ({ data: {} }) };
  await store.sync(); assert.equal(store.cursor, '');
});
await test('absence from active set does not falsely finish a retrying session', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.working = true;
  store.api = { messages: async () => ({ data: [], cursor: {} }), parseMessages: () => [],
    interactions: async () => [], request: async () => ({ data: {} }) };
  await store.sync(); assert.equal(store.working, true);
});
await test('SSE HTTP authentication failure survives early dataEnd', async () => {
  const saved = httpMock.createHttp;
  const handlers = new Map(); let failure;
  httpMock.createHttp = () => ({ on: (name, handler) => handlers.set(name, handler), destroy() {},
    requestInStream: async () => { handlers.get('dataEnd')(); return 401; } });
  try {
    const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, 'test-only');
    api.stream(() => {}, () => {}, error => { failure = error; });
    await Promise.resolve(); await Promise.resolve();
    assert.equal(failure.code, 401);
  } finally { httpMock.createHttp = saved; }
});
await test('dedicated HTTPS uses the same CA, SPKI pin and validation for HTTP and SSE', async () => {
  const api = new protocol.Protocol({ url: 'https://192.0.2.1:9443', username: 'opencode', useDedicatedTrust: true }, 'test');
  await api.request('/api/info'); const close = api.stream(() => {}, () => {}, () => {}); close();
  for (const request of requests.slice(-2)) {
    assert.equal(request.options.caData, trust.DEDICATED_CA);
    assert.equal(request.options.certificatePinning.publicKeyHash, trust.DEDICATED_SPKI);
    assert.equal(request.options.certificatePinning.hashAlgorithm, 'SHA-256');
    assert.equal(request.options.remoteValidation, 'system'); assert.equal(request.options.maxRedirects, 0);
  }
});
await test('private CA is opt-in and cannot be used over HTTP', async () => {
  assert.throws(() => new protocol.Protocol({ url: 'http://192.0.2.1', useDedicatedTrust: true }, 'test'), /HTTPS/);
  const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, 'test');
  await api.request('/api/info');
  assert.equal(requests.at(-1).options.caData, undefined); assert.equal(requests.at(-1).options.certificatePinning, undefined);
  assert.equal(requests.at(-1).options.maxRedirects, 0);
});
await test('certificate validation errors stop SSE retries and stay stopped on foreground', async () => {
  const store=new AppStore();let end,closed=0,opened=0;
  store.api={stream: (frame,data,done)=>{end=done;opened++;return ()=>{closed++;};}};
  store.openStream();end(protocol.networkError(Object.assign(new Error('raw'),{code:2300060})));
  assert.equal(store.status,'证书校验失败');assert.equal(store.retryTimer,-1);assert.equal(closed,1);
  store.setActive(false);store.setActive(true);assert.equal(opened,1);
});
await test('provider errors render the useful message without response bodies', async () => {
  const api=new protocol.Protocol({url:'https://example.com',username:'opencode'},'');
  const m=api.parseMessages({data:[{id:'m',type:'assistant',content:[],finish:'error',error:{message:'Region unavailable',response:{body:'private-response'}}}]})[0];
  assert.equal(m.state,'failed');assert.match(m.text,/Region unavailable/);assert.ok(!m.text.includes('private-response'));
});
delete httpMock.RequestMethod.PATCH; // API24 does not export the enum member.
const integration={id:'deepseek',name:'DeepSeek',connections:[{id:'cred_a',type:'credential',label:'Test',method:'key',value:{key:'must-never-appear'}}],methods:[{type:'key'},{id:'chatgpt-browser',type:'oauth',label:'Browser'}]};
function settingsApi(handler) { return {scope: d=>'location='+encodeURIComponent(d),request:async (path,method='GET',body)=>{
  if(handler) { const value=await handler(path,method,body);if(value!==undefined)return value; }
  if(path.startsWith('/api/integration?'))return {data:[integration]};
  if(path==='/api/session/active')return {data:{}};
  if(path==='/api/form'||path==='/api/permission/request')return {data:[]};
  if(path==='/client-settings/providers')return {data:[]};
  return {};
}}; }
await test('provider catalog uses safe connections and does not fetch raw credentials', async()=>{
  const calls=[];const store=new ProviderStore();store.attach(settingsApi((path)=>{calls.push(path);}),'/repo',async()=>{});await store.load();
  assert.ok(!calls.includes('/api/credential'));assert.ok(!JSON.stringify(store.entries).includes('must-never-appear'));
  assert.equal(store.entries[0].accounts[0].active,true);assert.equal(store.entries[0].methods[1].supported,false);
});
await test('native key connection sends V2 body once and clears the key',async()=>{
  const posts=[];let changed=0;const store=new ProviderStore();store.attach(settingsApi((path,method,body)=>{if(method==='POST')posts.push({path,body});}),'/repo',async()=>{changed++;});
  store.selected='deepseek';store.choose({id:'key',type:'key',supported:true,fields:[]});store.key=' fixture-key ';store.label='Work';await store.connect();
  assert.equal(posts.length,1);assert.equal(posts[0].path,'/api/integration/deepseek/connect/key?location=%2Frepo');assert.equal(posts[0].body.key,'fixture-key');assert.equal(store.key,'');assert.equal(changed,1);
});
await test('active tasks prevent global credential writes',async()=>{
  let posts=0;const store=new ProviderStore();store.attach(settingsApi((path,method)=>{if(method==='POST')posts++;if(path==='/api/session/active')return {data:{ses_a:{}}};}),'/repo',async()=>{});
  store.selected='deepseek';store.choose({id:'key',type:'key',supported:true,fields:[]});store.key='fixture';await store.connect();assert.equal(posts,0);assert.match(store.error,/任务/);
});
await test('lost key-save response refreshes connections without automatically reposting',async()=>{
  let posts=0;const store=new ProviderStore();store.attach(settingsApi((path,method)=>{if(method==='POST'){posts++;throw new Error('lost acknowledgement');}}),'/repo',async()=>{});
  store.selected='deepseek';store.choose({id:'key',type:'key',supported:true,fields:[]});store.key='fixture';await store.connect();assert.equal(posts,1);assert.equal(store.entries.length,1);assert.equal(store.key,'');
});
await test('late OAuth creation after switching servers is cancelled on old server',async()=>{
  let release,started;const gate=new Promise(resolve=>started=resolve);const oldCalls=[];
  const store=new ProviderStore();store.attach(settingsApi((path,method)=>{oldCalls.push({path,method});if(path.includes('/connect/oauth')&&method==='POST'){started();return new Promise(resolve=>release=resolve);}}),'/old',async()=>{});
  store.selected='openai';store.choose({id:'headless',type:'oauth',supported:true,fields:[]});const connecting=store.connect();await gate;
  store.attach(settingsApi(),'/new',async()=>{});release({data:{attemptID:'attempt_old',url:'https://auth.example.com',mode:'auto'}});await connecting;
  assert.equal(store.attemptID,'');assert.ok(oldCalls.some(c=>c.method==='DELETE'&&c.path.includes('attempt_old')));
});
await test('temporary OAuth polling failure keeps attempt and does not create another login',async()=>{
  const store=new ProviderStore();store.attach(settingsApi(()=>{throw new Error('offline');}),'/repo',async()=>{});store.selected='openai';store.attemptID='same-attempt';store.authStatus='pending';
  await store.poll();assert.equal(store.attemptID,'same-attempt');assert.match(store.error,/保留/);
});
await test('custom provider editing leaves saved API key absent from replacement request',async()=>{
  const writes=[];const store=new ProviderStore();store.attach(settingsApi((path,method,body)=>{if(method==='PUT')writes.push(body);}),'/repo',async()=>{});
  store.customAvailable=true;store.customID='mobile-test';store.customName='Test';store.customURL='https://api.example.com/v1';store.customModels='one,two';store.customKey='';await store.saveCustom();
  assert.equal(writes.length,1);assert.equal(writes[0].apiKey,undefined);assert.deepEqual(Array.from(writes[0].models),['one','two']);
});
await test('older history stays bounded and late live messages do not evict the viewed page',async()=>{
  const store=new AppStore();store.sessionID='ses_a';store.cursor='older';store.messages=Array.from({length:300},(_,i)=>message('old'+i,'old'));
  store.api={messages:async()=>({data:[],cursor:{next:'more'}}),parseMessages:()=>[message('earliest','page')],interactions:async()=>[],request:async()=>({data:{}})};
  await store.older();assert.equal(store.messages.length,300);assert.equal(store.messages[0].id,'earliest');assert.equal(store.readingHistory,true);
  store.onFrame({data:JSON.stringify({type:'session.text.delta',data:{sessionID:'ses_a',assistantMessageID:'new-tail',ordinal:0,delta:'live'}})});
  assert.equal(store.messages.length,300);assert.equal(store.messages[0].id,'earliest');assert.equal(store.newerAvailable,true);
  store.api.parseMessages=()=>[message('latest','now')];await store.latest();assert.equal(store.readingHistory,false);assert.equal(store.messages[0].id,'latest');
});
await test('expired OAuth receipt refreshes safe accounts and stops polling without assuming success',async()=>{
  const store=new ProviderStore();store.attach(settingsApi((path)=>{if(path.includes('/connect/oauth/'))throw new protocol.ApiError(404,'receipt expired');}),'/repo',async()=>{});
  store.selected='deepseek';store.attemptID='expired';store.authStatus='pending';await store.poll();
  assert.equal(store.attemptID,'');assert.equal(store.timer,-1);assert.equal(store.authStatus,'ended');assert.equal(store.entries.length,1);assert.match(store.notice,/核对/);
});
await test('temporary bridge failure preserves the last safe custom catalog',async()=>{
  const store=new ProviderStore();store.attach(settingsApi((path)=>{if(path==='/client-settings/providers')throw new protocol.ApiError(503,'temporary');}),'/repo',async()=>{});
  store.customAvailable=true;store.custom=[{id:'mobile-saved',name:'Saved',baseURL:'https://api.example.com',models:['one'],hasKey:true}];await store.load();
  assert.equal(store.customAvailable,true);assert.equal(store.custom[0].id,'mobile-saved');assert.match(store.error,/暂时/);
});
await test('API24 account rename sends literal PATCH without depending on the API26 enum',async()=>{
  const writes=[];const store=new ProviderStore();store.attach(settingsApi((path,method,body)=>{if(path.startsWith('/api/credential/'))writes.push({method,body});}),'/repo',async()=>{});
  store.label='Renamed';await store.account({id:'cred_a',type:'credential'},'rename');assert.equal(writes.length,1);assert.equal(writes[0].method,'PATCH');assert.equal(writes[0].body.label,'Renamed');
});
const permission = (patch='@@ -1 +1 @@\n-old\n+new\n') => ({id:'per_a',sessionID:'ses_a',kind:'permission',title:'edit',detail:'src/a.ts',fields:[],state:'pending',approval:protocol.parseApproval({action:'edit',resources:['src/a.ts'],metadata:{files:[{file:'src/a.ts',patch,status:'modified',additions:1,deletions:1}]},source:{type:'tool'}})});
await test('pending approval preview comes from request metadata rather than working tree diff',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'opencode'},'');let path;api.request=async p=>{path=p;return{data:[{id:'per_a',action:'edit',resources:['src/a.ts'],metadata:{files:[{file:'src/a.ts',patch:'-old\n+planned',status:'modified',additions:1,deletions:1}]},source:{type:'tool'}}]};};
 const p=(await api.interactions('ses_a','permission','/repo'))[0];assert.equal(p.approval.files[0].patch,'-old\n+planned');assert.equal(p.approval.source,'Agent 工具');assert.match(path,/location%5Bdirectory%5D=%2Frepo/);
});
await test('oversized approval previews explicitly block approval',async()=>{
 const parsed=protocol.parseApproval({action:'edit',resources:['a'],metadata:{files:[{file:'a',patch:'line\n'.repeat(1600)}]}});assert.equal(parsed.incomplete,true);const store=new AppStore();store.interactions=[{...permission(),approval:parsed}];assert.equal(store.canApprove('per_a'),false);
 const many=protocol.parseApproval({action:'edit',metadata:{files:Array.from({length:21},(_,i)=>({file:String(i),patch:'diff'}))}});assert.equal(many.omittedFiles,1);assert.equal(many.incomplete,true);
});
await test('preview metadata survives polling and submission-state changes',async()=>{
 const store=new AppStore();const before=permission();store.interactions=[before];store.interactionState(before.id,'submitting');assert.equal(store.interactions[0].approval,before.approval);
 await store.syncInteractions({interactions:async()=>[{...permission('updated'),title:'New scope',detail:'src/b.ts'}]},'ses_a','permission',0);assert.equal(store.interactions[0].title,'New scope');assert.equal(store.interactions[0].approval.files[0].patch,'updated');assert.equal(store.interactions[0].state,'submitting');
});
await test('failed approval read keeps cards and disables approve but permits rejection',async()=>{
 const store=new AppStore();store.active=false;store.sessionID='ses_a';store.interactions=[permission()];let posts=0;store.api={request:async()=>{posts++;},interactions:async()=>{throw new protocol.ApiError(400,'invalid metadata');}};
 await store.retryPermissions();assert.equal(store.interactions.length,1);assert.equal(store.error,'');assert.equal(store.canApprove('per_a'),false);await store.reply(store.interactions[0]);assert.equal(posts,0);await store.reply(store.interactions[0],true);assert.equal(posts,1);assert.equal(store.interactions.length,0);
});
await test('successful retry clears approval-read failure without losing pending preview',async()=>{
 const store=new AppStore();store.sessionID='ses_a';store.interactions=[permission()];store.permissionError='offline';store.api={interactions:async()=>[permission()]};await store.retryPermissions();assert.equal(store.permissionError,'');assert.equal(store.canApprove('per_a'),true);assert.equal(store.interactions[0].approval.files[0].path,'src/a.ts');
});
await test('approve rechecks exact current preview and sends once with directory scope',async()=>{
 const store=new AppStore();store.active=false;store.sessionID='ses_a';store.directory='/repo';store.interactions=[permission()];const calls=[];store.api={scope:d=>'location%5Bdirectory%5D='+encodeURIComponent(d),interactions:async()=>[permission()],request:async(path,method,body)=>calls.push({path,body})};await store.reply(store.interactions[0]);assert.equal(calls.length,1);assert.equal(calls[0].body.decision,'once');assert.match(calls[0].path,/reply\?location%5Bdirectory%5D=%2Frepo$/);assert.equal(store.interactions.length,0);
});
await test('changed or already handled approvals are never automatically approved',async()=>{
 for(const snapshot of [[permission('changed')],[]]){const store=new AppStore();store.active=false;store.sessionID='ses_a';store.interactions=[permission()];let posts=0;store.api={interactions:async()=>snapshot,request:async()=>{posts++;}};await store.reply(store.interactions[0]);assert.equal(posts,0);assert.equal(store.interactions.length,snapshot.length);assert.ok(store.error);}
});
await test('stale rendered card cannot approve a newer stored request',async()=>{
 const store=new AppStore();store.active=false;store.sessionID='ses_a';const displayed=permission('old');store.interactions=[permission('new')];let calls=0;store.api={request:async()=>{calls++;}};await store.reply(displayed);assert.equal(calls,0);assert.match(store.error,/更新/);
});
await test('lost approval acknowledgement refreshes state without duplicate POST',async()=>{
 const store=new AppStore();store.active=false;store.sessionID='ses_a';store.interactions=[permission()];let reads=0,posts=0;store.api={interactions:async()=>++reads===1?[permission()]:[],request:async()=>{posts++;throw new Error('lost acknowledgement');}};await store.reply(store.interactions[0]);assert.equal(posts,1);assert.equal(reads,2);assert.equal(store.interactions.length,0);
});
await test('late approval check cannot post after switching connections',async()=>{
 const store=new AppStore();store.active=false;store.sessionID='ses_a';store.interactions=[permission()];let release,posts=0;store.api={interactions:()=>new Promise(r=>release=r),request:async()=>{posts++;}};const pending=store.reply(store.interactions[0]);store.disconnect();release([permission()]);await pending;assert.equal(posts,0);assert.equal(store.interactions.length,0);
});
await test('older failing approval poll cannot overwrite a newer successful snapshot',async()=>{
 const store=new AppStore();store.interactions=[permission()];let reject;const older=store.syncInteractions({interactions:()=>new Promise((_,r)=>reject=r)},'ses_a','permission',0);await store.syncInteractions({interactions:async()=>[]},'ses_a','permission',0);reject(new Error('older failure'));await older;assert.equal(store.permissionError,'');assert.equal(store.interactions.length,0);
});
await test('changing session or project clears the old approval read failure',async()=>{
 const store=new AppStore();store.permissionError='old session failure';store.api={};store.openStream=()=>{};store.sync=async()=>{};
 await store.openSession({id:'ses_b',title:'B',model:''});assert.equal(store.permissionError,'');
 store.permissionError='old project failure';store.api={request:async()=>({}),sessions:async()=>[],models:async()=>[]};
 await store.selectProject('/repo-b');assert.equal(store.permissionError,'');assert.equal(store.interactions.length,0);
});
await test('history reasoning collapses when ended even while the assistant is still generating',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'opencode'},'');
 const m=api.parseMessages({data:[{id:'a',type:'assistant',content:[{type:'reasoning',text:'thought',time:{completed:1}},{type:'text',text:'answer'}]}]})[0];
 assert.equal(m.state,'streaming');assert.equal(core.reasoningInProgress(m),false);
 const active=api.parseMessages({data:[{id:'b',type:'assistant',content:[{type:'reasoning',text:'working'}]}]})[0];assert.equal(core.reasoningInProgress(active),true);
});
await test('launch opens chat and restores only the explicitly remembered server',async()=>{
 const store=new AppStore();const servers=[{id:'saved'},{id:'other'}];let connected='';store.storage={init:async()=>{},servers:async()=>servers,activeServer:async()=>'saved'};store.connect=async s=>{connected=s.id;};
 assert.equal(store.pane,'chat');await store.init({});assert.equal(connected,'saved');
});
await test('new conversations immediately appear once in sidebar history',async()=>{
 const store=new AppStore();store.connected='saved';store.directory='/repo';store.sessions=[{id:'ses_new',title:'stale'}];store.api={request:async()=>({data:{id:'ses_new',title:'New'}})};store.openSession=async()=>{};
 await store.createSession();assert.equal(store.sessions.length,1);assert.equal(store.sessions[0].title,'New');
});

await test('timeline merges steering prompts using server idle boundaries and protects a partial first turn',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'opencode'},'');
 const entries=api.parseTimeline({data:[{id:'idle2',type:'idle',outcome:'succeeded'},{id:'u3',type:'user',text:'Next'},{id:'idle1',type:'idle',outcome:'failed'},{id:'u2',type:'user',text:'Steer'},{id:'u1',type:'user',text:'Start'}]});
 const turns=core.groupTurns(entries,true);assert.equal(turns.length,2);assert.equal(turns[0].id,'u3');assert.equal(turns[0].state,'completed');assert.equal(turns[1].prompts,2);assert.equal(turns[1].partial,true);assert.equal(turns[1].state,'failed');
 assert.equal(core.groupTurns(entries,false)[1].partial,false);
});
await test('turn diff requests include selected prompt and location and same-file changes get new render keys',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'opencode'},'');let path;api.request=async p=>{path=p;return{data:[{file:'same.ts',patch:'+new'}]};};
 const diffs=await api.turnDiff('ses_a','/repo space','msg_a');assert.match(path,/from=msg_a/);assert.match(path,/location%5Bdirectory%5D=%2Frepo%20space/);assert.equal(diffs[0].patch,'+new');assert.notEqual(core.diffKey(diffs[0]),core.diffKey({path:'same.ts',patch:'+old'}));
});
await test('out-of-order task selection cannot display another tasks patch',async()=>{
 const store=new AppStore();store.sessionID='ses_a';store.directory='/repo';let resolveA;store.api={turnDiff:async(_,__,id)=>id==='a'?new Promise(r=>resolveA=r):[{path:'same.ts',patch:'+B'}]};
 const a=store.selectTurn({id:'a'});await store.selectTurn({id:'b'});resolveA([{path:'same.ts',patch:'+A'}]);await a;assert.equal(store.turnID,'b');assert.equal(store.turnDiffs[0].patch,'+B');assert.equal(store.turnBusy,false);
 store.api.turnDiff=async()=>{throw new Error('offline');};await store.selectTurn({id:'c'});assert.equal(store.turnDiffs.length,0);assert.equal(store.turnLoaded,false);assert.equal(store.turnError,'offline');
});
await test('timeline paging repairs partial boundary and ignores disconnected reads',async()=>{
 const store=new AppStore();store.sessionID='s';store.api={messages:async(_,cursor)=>cursor?{data:[{id:'u1',type:'user',text:'Start'},{id:'idle0',type:'idle'}]}:{data:[{id:'idle1',type:'idle'},{id:'u2',type:'user',text:'Steer'}],cursor:{next:'older'}},parseTimeline:protocol.Protocol.prototype.parseTimeline,turnDiff:async()=>[]};
 await store.loadTimeline();assert.equal(store.turns[0].partial,true);assert.equal(store.turnID,'');await store.loadTimeline(true);assert.equal(store.turns.length,1);assert.equal(store.turns[0].id,'u1');assert.equal(store.turns[0].prompts,2);assert.equal(store.turns[0].partial,false);
 let release;store.api.messages=()=>new Promise(r=>release=r);const read=store.loadTimeline();store.disconnect();release({data:[{id:'x',type:'user'}]});await read;assert.equal(store.turns.length,0);assert.equal(store.timelineBusy,false);
});

await test('custom configuration rejects full endpoints, duplicate models and unsafe text before any request',async()=>{
 const store=new ProviderStore();let calls=0;store.attach({request:async()=>{calls++;}},'/repo',async()=>{});store.customAvailable=true;store.customID='mobile-valid';store.customName='Example';store.customURL='https://api.example.com/v1/chat/completions';store.customModels='one';await store.saveCustom();assert.equal(calls,0);assert.match(store.error,/Base URL/);
 store.customURL='https://api.example.com/v1';store.customModels='one，one';await store.saveCustom();assert.equal(calls,0);assert.match(store.error,/重复/);
 store.customModels='one';store.customKey='{file:/secret}';await store.saveCustom();assert.equal(calls,0);assert.match(store.error,/普通文本/);
});
await test('new channel and server changes clear prior editor values and never carry a saved key',async()=>{
 const store=new ProviderStore();store.editCustom({id:'mobile-old',name:'Old',baseURL:'https://old.example.com/v1',models:['old'],hasKey:true});assert.equal(store.editingID,'mobile-old');assert.equal(store.customKey,'');store.customKey='test-only';store.newCustom();assert.equal(store.customID,'');assert.equal(store.customKey,'');assert.equal(store.editingID,'');
 store.customName='Old';store.attach(undefined,'/new',async()=>{});assert.equal(store.customName,'');assert.equal(store.catalog.length,0);
});
await test('provider quick entry selects the server declared key form and catalog search remains bounded',async()=>{
 const store=new ProviderStore();store.entries=[{id:'deepseek',name:'DeepSeek',methods:[{id:'key',type:'key',supported:true,fields:[]}],accounts:[]}];store.quickSelect('deepseek');assert.equal(store.selected,'deepseek');assert.equal(store.methodType,'key');
 store.catalog=Array.from({length:100},(_,i)=>({id:'p/mimo-'+i,label:'MiMo '+i}));store.modelSearch='mimo';assert.equal(store.modelMatches().length,100);assert.equal(store.visibleModels().length,60);store.modelSearch='not present';assert.equal(store.visibleModels().length,0);
});

const workspaceSession=(id,title=id,directory='/repo')=>({id,title,directory,status:'idle',model:''});
const pendingItem=(id,sessionID='s',directory='/repo',kind='permission')=>({id,sessionID,directory,kind,title:'Pending '+id,sessionTitle:'',stale:false});
await test('session protocol encodes paging/search and literal PATCH with title-only body',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'u'},'');const calls=[];api.request=async(path,method,body)=>{calls.push({path,method,body});return{data:[{id:'a',title:'A',location:{directory:'/repo'},time:{archived:1}}],cursor:{next:'next page'}};};
 const first=await api.sessionPage('/repo space','','a&b');assert.equal(first.cursor,'next page');assert.equal(first.sessions[0].archived,true);assert.match(calls[0].path,/search=a%26b/);assert.match(calls[0].path,/directory=%2Frepo%20space/);
 await api.sessionPage('/repo','next page','ignored');assert.match(calls[1].path,/cursor=next%20page/);assert.ok(!calls[1].path.includes('search='));
 await api.renameSession('a/b','New');assert.equal(calls[2].path,'/api/session/a%2Fb');assert.equal(calls[2].method,'PATCH');assert.equal(JSON.stringify(calls[2].body),'{'+'"title":"New"}');
});
await test('global pending protocol uses location-scoped V2 form and permission routes',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'u'},'');const paths=[];api.request=async path=>{paths.push(path);return{data:[{id:'p',sessionID:'s',action:'edit'}]};};
 assert.equal((await api.pending('/repo space','form'))[0].kind,'form');await api.pending('/repo space','permission');
 assert.equal(paths[0],'/api/form?location%5Bdirectory%5D=%2Frepo%20space');assert.equal(paths[1],'/api/permission/request?location%5Bdirectory%5D=%2Frepo%20space');
});
await test('switching conversations restores unsent text and the same uncertain prompt ID',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.active=false;store.api={};
 await store.openSession(workspaceSession('a'));store.draft='draft A';store.pendingSend={id:'prompt-a',sessionID:'a',text:'draft A'};
 await store.openSession(workspaceSession('b'));assert.equal(store.draft,'');store.draft='draft B';
 await store.openSession(workspaceSession('a'));assert.equal(store.draft,'draft A');assert.equal(store.pendingSend.id,'prompt-a');
 store.disconnect();store.connected='two';store.directory='/repo';store.api={};await store.openSession(workspaceSession('a'));assert.equal(store.draft,'');assert.equal(store.pendingSend,undefined);
});
await test('a late send acknowledgement cannot clear another conversations draft or leave it busy',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.active=false;store.sessionID='a';store.draft='A';let release;
 store.api={request:()=>new Promise(r=>release=r)};const send=store.send();await store.openSession(workspaceSession('b'));store.draft='B';release({});await send;
 assert.equal(store.sessionID,'b');assert.equal(store.draft,'B');assert.equal(store.busy,false);await store.openSession(workspaceSession('a'));assert.equal(store.pendingSend.text,'A');
});
await test('local archive/pin saves no API mutations and failed preferences retain visible state',async()=>{
 const store=new AppStore();store.connected='one';let saved;store.api={request:()=>{throw new Error('Unexpected API write');}};store.storage={saveSessionPreferences:async(server,flags)=>{saved={server,flags};}};
 await store.setSessionPreference('s',true,true);assert.equal(saved.server,'one');assert.equal(store.isArchived('s'),true);assert.equal(store.isPinned('s'),true);
 store.storage.saveSessionPreferences=async()=>{throw new Error('disk full');};await store.setSessionPreference('s',false,false);assert.equal(store.isArchived('s'),true);assert.match(store.error,/disk full/);
});
await test('session rename validates input and ignores a late response from another server',async()=>{
 const store=new AppStore();store.connected='one';store.sessionID='a';store.sessionTitle='Old';store.sessions=[workspaceSession('a','Old')];let calls=0,release;
 store.api={renameSession:()=>{calls++;return new Promise(r=>release=r);}};assert.equal(await store.renameSession('a','  '),false);assert.equal(calls,0);
 const write=store.renameSession('a','New');store.disconnect();store.connected='two';store.sessionTitle='Other';release();assert.equal(await write,false);assert.equal(store.sessionTitle,'Other');
});
await test('successful rename updates current title, sidebar row and pending context',async()=>{
 const store=new AppStore();store.sessionID='s';store.sessionTitle='Old';store.sessions=[workspaceSession('s','Old')];store.pendingItems=[pendingItem('p')];store.api={renameSession:async()=>{}};
 assert.equal(await store.renameSession('s',' New '),true);assert.equal(store.sessionTitle,'New');assert.equal(store.sessions[0].title,'New');assert.equal(store.pendingItems[0].sessionTitle,'New');
});
await test('session pagination deduplicates and a new search invalidates an older page',async()=>{
 const store=new AppStore();store.directory='/repo';let release;store.api={sessionPage:async(_,cursor,search)=>cursor?new Promise(r=>release=r):{sessions:[workspaceSession(search||'a')],cursor:'older'}};
 await store.refreshSessions();const older=store.refreshSessions(true);await store.refreshSessions(false,'found');release({sessions:[workspaceSession('old')],cursor:''});await older;
 assert.equal(store.sessions[0].id,'found');assert.equal(store.sessionQuery,'found');assert.equal(store.sessionsBusy,false);
 store.api.sessionPage=async()=>({sessions:[workspaceSession('found'),workspaceSession('next')],cursor:''});await store.refreshSessions(true);assert.equal(store.sessions.length,2);
});
await test('session list errors keep prior rows and a disconnected read cannot repopulate them',async()=>{
 const store=new AppStore();store.directory='/repo';store.sessions=[workspaceSession('kept')];store.api={sessionPage:async()=>{throw new Error('offline');}};
 await store.refreshSessions();assert.equal(store.sessions[0].id,'kept');assert.match(store.sessionsError,/offline/);
 let release;store.api.sessionPage=()=>new Promise(r=>release=r);const read=store.refreshSessions();store.disconnect();release({sessions:[workspaceSession('late')],cursor:''});await read;assert.equal(store.sessions.length,0);assert.equal(store.sessionsBusy,false);
});
await test('pending center reads all known projects once and distinguishes questions from approvals',async()=>{
 const store=new AppStore();store.directory='/repo';store.projects=[{directory:'/repo'},{directory:'/second'}];const calls=[];
 store.api={request:async()=>({data:{}}),pending:async(dir,kind)=>{calls.push(dir+kind);return[pendingItem(dir+kind,'s',dir,kind)];}};await store.refreshPending();assert.equal(calls.length,4);assert.equal(store.pendingItems.length,4);assert.equal(new Set(calls).size,4);assert.equal(store.pendingBusy,false);
});
await test('one failing pending scope retains stale items while successful empty scopes clear theirs',async()=>{
 const store=new AppStore();store.directory='/repo';store.pendingItems=[pendingItem('p'),pendingItem('q','s','/repo','form')];store.api={request:async()=>({data:{}}),pending:async(_,kind)=>{if(kind==='permission')throw new Error('offline');return[];}};
 await store.refreshPending();assert.equal(store.pendingItems.length,1);assert.equal(store.pendingItems[0].id,'p');assert.equal(store.pendingItems[0].stale,true);assert.match(store.pendingError,/审批/);
 store.api.pending=async()=>[];await store.refreshPending();assert.equal(store.pendingItems.length,0);assert.equal(store.pendingError,'');
});
await test('newer pending refresh wins and old-server results never enter the active connection',async()=>{
 const store=new AppStore();store.directory='/repo';let releases=[];store.api={request:async()=>({data:{}}),pending:()=>new Promise(r=>releases.push(r))};const old=store.refreshPending();
 const oldReleases=releases;store.api.pending=async()=>[pendingItem('new')];await store.refreshPending(true);oldReleases.forEach(r=>r([pendingItem('old')]));await old;assert.equal(store.pendingItems[0].id,'new');
 releases=[];store.api.pending=()=>new Promise(r=>releases.push(r));const read=store.refreshPending();store.disconnect();releases.forEach(r=>r([pendingItem('late')]));await read;assert.equal(store.pendingItems.length,0);
});
await test('pending collection caps request concurrency and reports its project bound',async()=>{
 const store=new AppStore();store.projects=Array.from({length:70},(_,i)=>({directory:'/p'+i}));let concurrent=0,max=0,calls=0;
 store.api={request:async()=>({data:{}}),pending:async()=>{calls++;max=Math.max(max,++concurrent);await Promise.resolve();concurrent--;return[];}};await store.refreshPending();assert.equal(calls,128);assert.ok(max<=6);assert.match(store.pendingError,/上限/);
});
await test('authentication failure in pending stops reconnects and preserves uncertainty',async()=>{
 const store=new AppStore();store.directory='/repo';store.pendingItems=[pendingItem('p')];store.api={request:async()=>({data:{}}),pending:async()=>{throw new protocol.ApiError(401,'Unauthorized');}};
 await store.refreshPending();assert.equal(store.networkBlocked,true);assert.equal(store.status,'认证失败');assert.equal(store.pendingItems[0].stale,true);assert.equal(store.pendingBusy,false);assert.ok(store.pendingError);
});
await test('opening a pending item resolves its real project and performs no answer or approval writes',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.sessionID='old';store.active=false;const calls=[];
 store.api={session:async()=>workspaceSession('target','Target','/second'),scope:dir=>dir,request:async(path,method)=>{calls.push({path,method});return{};},sessionPage:async()=>({sessions:[],cursor:''}),models:async()=>[]};
 await store.openPending(pendingItem('p','target','/second'));assert.equal(store.directory,'/second');assert.equal(store.sessionID,'target');assert.equal(store.pane,'chat');assert.ok(calls.every(c=>!c.method||c.method==='GET'));assert.equal(store.busy,false);
});
await test('expired pending and late navigation requests never open another sessions content',async()=>{
 const store=new AppStore();store.connected='one';store.sessionID='current';store.api={session:async()=>{throw new protocol.ApiError(404,'gone');}};await store.openPending(pendingItem('p'));assert.equal(store.sessionID,'current');
 let release;store.api.session=()=>new Promise(r=>release=r);const open=store.openPending(pendingItem('p'));store.disconnect();store.connected='two';store.sessionID='other';release(workspaceSession('stale'));await open;assert.equal(store.sessionID,'other');
});
await test('callbacks from a replaced stream cannot append text or change connection state',async()=>{
 const store=new AppStore();store.sessionID='s';const callbacks=[];store.api={stream:(frame,data,end)=>{callbacks.push({frame,data,end});return()=>{};}};
 store.openStream();store.openStream();callbacks[0].frame({data:JSON.stringify({type:'session.text.delta',data:{sessionID:'s',assistantMessageID:'old',ordinal:0,delta:'bad'}})});callbacks[0].end(new protocol.ApiError(401,'old'));assert.equal(store.messages.length,0);assert.equal(store.networkBlocked,false);
 callbacks[1].frame({data:JSON.stringify({type:'session.text.delta',data:{sessionID:'s',assistantMessageID:'new',ordinal:0,delta:'ok'}})});assert.equal(store.messages[0].text,'ok');store.setActive(false);store.setActive(true);callbacks[1].frame({data:JSON.stringify({type:'session.text.delta',data:{sessionID:'s',assistantMessageID:'new',ordinal:0,delta:'late'}})});assert.equal(store.messages[0].text,'ok');
});

await test('pinned or archived bookmarks remain visible after the server first-page window changes',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.sessions=[workspaceSession('old','Saved title')];
 await store.setSessionPreference('old',true,true);store.sessions=[];store.showArchived=true;assert.equal(store.sessionRows()[0].id,'old');assert.equal(store.sessionRows()[0].title,'Saved title');
 store.directory='/other';assert.equal(store.sessionRows().length,0);
});
await test('running sidebar state is restored before receiving any text deltas',async()=>{
 const store=new AppStore();store.directory='/repo';store.api={request:async()=>({data:{already_running:{type:'running'}}}),pending:async()=>[]};
 await store.refreshPending();assert.equal(store.sessionLabel('already_running'),'运行中');
 store.api.request=async()=>{throw new Error('offline');};await store.refreshPending();assert.equal(store.sessionLabel('already_running'),'运行状态待确认');assert.match(store.pendingError,/运行/);
});
await test('same-server reconnect invalidates an older local preference write callback',async()=>{
 const store=new AppStore();store.connected='one';let release;store.storage={saveSessionPreferences:()=>new Promise(r=>release=r)};const write=store.setSessionPreference('old',true,false);
 store.disconnect();store.connected='one';store.sessionPreferences=[{id:'new',pinned:true,archived:false}];release();await write;assert.equal(store.sessionPreferences[0].id,'new');assert.equal(store.sessionPreferenceBusy,false);
});

await test('Question field drafts survive a conversation switch and restore only still-existing fields',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.active=false;store.api={};await store.openSession(workspaceSession('a'));
 const field={key:'name',label:'Name',type:'string',required:true,options:[],values:[],text:'typed answer'};store.interactions=[{...form(),sessionID:'a',fields:[field]}];
 await store.openSession(workspaceSession('b'));await store.openSession(workspaceSession('a'));assert.equal(store.interactions.length,0);
 await store.syncInteractions({interactions:async()=>[{...form(),sessionID:'a',fields:[{...field,text:''}]}]},'a','form',store.generation);assert.equal(store.interactions[0].fields[0].text,'typed answer');
});
await test('renaming a bookmarked conversation persists its display name for the next launch',async()=>{
 const store=new AppStore();store.connected='one';store.sessionPreferences=[{id:'s',pinned:true,archived:true,directory:'/repo',title:'Old'}];let saved;
 store.storage={saveSessionPreferences:async(_,flags)=>{saved=flags;}};store.api={renameSession:async()=>{}};assert.equal(await store.renameSession('s','New'),true);assert.equal(saved[0].title,'New');
});
await test('directly opening a session in another location switches scope before fetching its history',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/first';store.active=false;const paths=[];
 store.api={request:async path=>{paths.push(path);return{};},scope:dir=>dir,sessionPage:async()=>({sessions:[],cursor:''}),models:async()=>[]};await store.openSession(workspaceSession('s','Second','/second'));
 assert.equal(store.directory,'/second');assert.equal(store.sessionID,'s');assert.equal(paths[0],'/api/location?/second');
});

await test('unarchiving an older bookmarked session returns it to recent rows immediately',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.sessionPreferences=[{id:'old',pinned:false,archived:true,directory:'/repo',title:'Old'}];
 await store.setSessionPreference('old',false,false);assert.equal(store.sessionRows()[0].id,'old');assert.equal(store.isArchived('old'),false);
});
await test('definitively rejected prompts become editable while uncertain sends retain their original ID',async()=>{
 const store=new AppStore();store.connected='one';store.directory='/repo';store.sessionID='s';store.draft='invalid';store.api={request:async()=>{throw new protocol.ApiError(400,'invalid request');}};
 await store.send();assert.equal(store.pendingSend,undefined);assert.equal(store.draft,'invalid');assert.ok(!store.error.includes('待核对'));
 store.api.request=async()=>{throw new Error('socket closed');};await store.send();const id=store.pendingSend.id;await store.send();assert.equal(store.pendingSend.id,id);
});
await test('duplicate stop taps submit only one interrupt and release the control after completion',async()=>{
 const store=new AppStore();store.sessionID='s';store.active=false;let release,calls=0;store.api={request:()=>{calls++;return new Promise(r=>release=r);}};
 const first=store.interrupt();await store.interrupt();assert.equal(calls,1);assert.equal(store.interrupting,true);release({});await first;assert.equal(store.interrupting,false);
});

await test('authentication-blocked sync never makes follow-up automatic history requests',async()=>{
 const store=new AppStore();store.sessionID='s';store.networkBlocked=true;store.syncAgain=true;let calls=0;store.api={messages:async()=>{calls++;return{};}};
 await store.sync();store.queueSync();assert.equal(calls,0);assert.equal(store.refreshTimer,-1);
});
await test('a pending snapshot started before background suspension cannot overwrite foreground state',async()=>{
 const store=new AppStore();store.directory='/repo';const releases=[];store.api={request:async()=>({data:{}}),pending:()=>new Promise(r=>releases.push(r))};const read=store.refreshPending();
 await Promise.resolve();await Promise.resolve();store.setActive(false);store.pendingItems=[pendingItem('kept')];releases.forEach(r=>r([pendingItem('late')]));await read;assert.equal(store.pendingItems[0].id,'kept');assert.equal(store.pendingBusy,false);
});

await test('attachment-only prompts send exact inline bytes and clear only after acceptance',async()=>{
 const store=new AppStore();store.sessionID='s';store.active=false;store.attachments=[{id:'a',name:'readme.txt',mime:'text/plain',data:'YQ==',size:1,uri:'file://phone.txt'}];let body;
 store.api={request:async(p,m,b)=>{body=b;}};await store.send();assert.equal(body.text,'');assert.equal(body.files[0].uri,'data:text/plain;base64,YQ==');assert.equal(body.files[0].name,'readme.txt');assert.equal(store.attachments.length,0);
});
await test('an unknown attachment send retries the original immutable bytes with the same ID',async()=>{
 const store=new AppStore();store.sessionID='s';store.active=false;store.attachments=[{id:'a',name:'a.txt',mime:'text/plain',data:'YQ==',size:1}];const attempts=[];
 store.api={request:async(p,m,b)=>{attempts.push(b);if(attempts.length===1)throw new Error('lost');}};await store.send();store.attachments[0].data='Yg==';await store.send();assert.equal(attempts[0].id,attempts[1].id);assert.equal(attempts[1].files[0].uri,'data:text/plain;base64,YQ==');
});
await test('unsupported image models and failed attachment reads never submit a prompt',async()=>{
 const store=new AppStore();store.sessionID='s';store.active=false;let writes=0;store.api={request:async()=>writes++};
 store.attachments=[{id:'a',name:'a.jpg',mime:'image/jpeg',data:'YQ==',size:1}];await store.send();assert.equal(writes,0);assert.match(store.error,/图片/);
 store.attachments=[{id:'a',name:'a.txt',mime:'text/plain',data:'',size:0,error:'read failure'}];await store.send();assert.equal(writes,0);assert.equal(store.attachments.length,1);
});
await test('history includes image and file metadata and explicit model input capabilities',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'u'},'');const m=api.parseMessages({data:[{id:'u',type:'user',text:'',files:[{name:'a.png',mime:'image/png',data:'YQ=='}]}]})[0];assert.equal(m.files[0].name,'a.png');assert.equal(m.files[0].data,'YQ==');
 api.request=async()=>({data:[{providerID:'p',modelID:'m',name:'M',capabilities:{input:['text','image']}}]});assert.equal(JSON.stringify((await api.models('/r'))[0].input),'["text","image"]');
});

await test('oversized attachment history falls back to bounded single-message pages and preserves cursors',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'u'},'');const paths=[];
 api.request=async path=>{paths.push(path);const u=new URL('https://example.com'+path);if(u.searchParams.get('limit')==='30')throw new Error('response too large');const i=Number(u.searchParams.get('cursor')||0);return{data:[{id:'m'+i,type:'user',text:'entry'}],cursor:{next:i<15?String(i+1):''}};};
 const r=await api.messages('s');assert.equal(r.data.length,8);assert.equal(r.cursor.next,'8');assert.equal(paths.filter(p=>p.includes('limit=30')).length,1);await api.messages('s','8');assert.equal(paths.filter(p=>p.includes('limit=30')).length,1);
});
await test('authentication errors do not retry as compact history reads',async()=>{
 const api=new protocol.Protocol({url:'https://example.com',username:'u'},'');let reads=0;api.request=async()=>{reads++;throw new protocol.ApiError(401,'authentication');};await assert.rejects(()=>api.messages('s'));assert.equal(reads,1);
});
await test('unknown send is confirmed by exact message lookup when it falls outside the current history page',async()=>{
 const store=new AppStore();store.sessionID='s';store.pendingSend={id:'accepted',sessionID:'s',text:'task'};store.draft='task';store.error='socket closed。发送结果待核对，重试将使用同一消息 ID';store.api={messages:async()=>({data:[]}),parseMessages:()=>[],interactions:async()=>[],request:async path=>path.endsWith('/message/accepted')?{data:{id:'accepted',type:'user'}}:path.endsWith('/inbox')?{data:[]}:{data:{}}};await store.sync();assert.equal(store.pendingSend,undefined);assert.equal(store.draft,'');assert.equal(store.error,'');
});
await test('provider selection with identical method IDs resolves the new provider and clears the previous key',async()=>{
 const store=new ProviderStore();const method={id:'key',type:'key',supported:true,fields:[]};
 const writes=[];store.attach(settingsApi((p,m,b)=>{if(m==='POST')writes.push({p,b});}),'/repo',async()=>{});
 store.entries=[{id:'deepseek',name:'DeepSeek',methods:[method],accounts:[]},{id:'xiaomi',name:'Xiaomi',methods:[method],accounts:[]}];
 store.select(store.entries[0]);store.choose(method);store.key='fixture-old-key';store.select(store.entries[1]);assert.equal(store.current().name,'Xiaomi');assert.equal(store.key,'');assert.equal(store.methodType,'');
 store.choose(method);store.key='fixture-new-key';await store.connect();assert.equal(writes[0].p,'/api/integration/xiaomi/connect/key?location=%2Frepo');
});
await test('credential submission freezes key and account label before asynchronous idle checks',async()=>{
 let release,signal;const gate=new Promise(r=>signal=r);const writes=[];const store=new ProviderStore();
 store.attach(settingsApi((p,m,b)=>{if(p==='/api/session/active'){signal();return new Promise(r=>release=r);}if(m==='POST')writes.push(b);}),'/repo',async()=>{});
 store.selected='xiaomi';store.choose({id:'key',type:'key',supported:true,fields:[]});store.key='fixture-original';store.label='Original';const save=store.connect();await gate;store.key='fixture-later';store.label='Later';release({data:{}});await save;
 assert.equal(writes[0].key,'fixture-original');assert.equal(writes[0].label,'Original');
});
await test('a successful model switch clears previous errors while a rejected switch retains the current model',async()=>{
 const store=new AppStore();store.sessionID='s';store.active=false;store.modelID='p/old';store.error='Old error';store.api={request:async()=>({})};await store.chooseModel('p/new');assert.equal(store.modelID,'p/new');assert.equal(store.error,'');
 store.api.request=async()=>{throw new protocol.ApiError(400,'Unsupported model');};await store.chooseModel('p/bad');assert.equal(store.modelID,'p/new');assert.match(store.error,/Unsupported/);
});
console.log(count + ' adapter/state tests passed.');
