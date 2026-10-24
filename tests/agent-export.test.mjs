import { ts } from './helpers/typescript.mjs';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import vm from 'node:vm';
const root = resolve(import.meta.dirname, '..');

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
class StorageMock { async modelPreferences() { return {enabled:[],favorites:[],recent:[]}; } async saveModelPreferences() {} async sessionPreferences() { return []; } async saveSessionPreferences() {} async init() {} async servers() { return []; } async secret() { return 'test-only'; } async last() { return []; } async position() {} async activeServer() { return ''; } async rememberServer() {} }
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
load('entry/src/main/ets/domain/PromptTemplates.ts', '../domain/PromptTemplates');
load('entry/src/main/ets/domain/Attachments.ts', '../domain/Attachments');
const core = load('entry/src/main/ets/domain/Core.ts', '../domain/Core');
modules.set('./Core', modules.get('../domain/Core'));
load('entry/src/main/ets/domain/ModelSelection.ts', '../domain/ModelSelection');
load('entry/src/main/ets/domain/Connections.ts', '../domain/Connections');
load('entry/src/main/ets/domain/SessionUsage.ts', '../domain/SessionUsage');
const trust = load('entry/src/main/ets/data/DedicatedTrust.ets', './DedicatedTrust');
const agentsDomain=load('entry/src/main/ets/domain/Agents.ts', '../domain/Agents');
const exportsDomain=load('entry/src/main/ets/domain/TranscriptExport.ts', '../domain/TranscriptExport');
const protocol = load('entry/src/main/ets/data/Protocol.ets', '../data/Protocol');
const { ProviderStore } = load('entry/src/main/ets/presentation/ProviderStore.ets', './ProviderStore');
load('entry/src/main/ets/domain/Notifications.ts', '../domain/Notifications');
const { AppStore } = load('entry/src/main/ets/presentation/AppStore.ets', 'store');
let count = 0;
async function test(name, run) { await run(); count++; console.log('PASS ' + name); }
const message = (id, text) => ({ id, role: 'assistant', text, reasoning: '', tools: [], parts: [], state: 'completed' });
const form = () => ({ id: 'frm_a', sessionID: 'ses_a', kind: 'form', title: 'Question', detail: '', fields: [], state: 'pending' });

const {selectableAgents}=agentsDomain;
const {TranscriptExporter,utf8Length,exportFilename}=exportsDomain;
const agent=(id='build',extra={})=>({id,name:id==='build'?'实施':'规划',description:'server description',mode:'primary',hidden:false,model:'p/'+id,...extra});
const options={id:'s',title:'测试会话',format:'markdown',tools:false};
const item=(id,extra={})=>({...message(id,'entry '+id),...extra});
const reader=(pages,boundary='last')=>({exportBoundary:async()=>boundary,exportPage:async(s,c)=>pages[Number(c)||0]});
const page=(messages,cursor='')=>({messages,ids:messages.map(m=>m.id),cursor});
const flush=()=>new Promise(setImmediate);
const gate=()=>{let release;return{promise:new Promise(r=>release=r),release:value=>release(value)};};
await test('Agent list excludes hidden subagents and unknown modes, deduplicates IDs and searches all terms',()=>{
 const list=[agent(),agent('plan',{mode:'all'}),agent('hidden',{hidden:true}),agent('sub',{mode:'subagent'}),agent('bad',{mode:'future'}),agent()];
 assert.equal(selectableAgents(list).map(a=>a.id).join(','),'build,plan');assert.equal(selectableAgents(list,'规划 server')[0].id,'plan');assert.equal(selectableAgents(list,'missing').length,0);
});
await test('Agent protocol projects safe fields and includes encoded project scope',async()=>{
 const api=new protocol.Protocol({url:'https://example.com'},'');let query;api.request=async path=>{query=path;return{data:[{...agent(),system:'INTERNAL',request:{secret:1},permissions:['*']},agent('sub',{mode:'subagent'})]};};
 const rows=await api.agents('/repo 中文');assert.match(query,/location%5Bdirectory%5D=%2Frepo%20/);assert.equal(rows.length,1);assert.equal(rows[0].name,'实施');assert.equal(JSON.stringify(rows).includes('INTERNAL'),false);
});
await test('export uses full ascending pagination beyond the 300-message screen and fixes an initial snapshot boundary',async()=>{
 const messages=Array.from({length:365},(_,i)=>item('m'+i));const reads=[];
 const api={exportBoundary:async()=> 'm359',exportPage:async(s,c)=>{reads.push(c);const offset=Number(c)||0;return page(messages.slice(offset,offset+30),String(offset+30));}};
 const progress=[];const doc=await new TranscriptExporter().prepare(api,options,n=>progress.push(n));assert.equal(doc.count,360);assert.match(doc.text,/entry m0\n/);assert.match(doc.text,/entry m359/);assert.equal(doc.text.includes('entry m360'),false);assert.equal(reads.length,12);assert.equal(progress.at(-1),360);
});
await test('exports deduplicate IDs and omit private reasoning, internal messages, attachment URI and base64',async()=>{
 const a=item('first',{role:'user',files:[{name:'metadata.txt',mime:'text/plain',size:7,data:'PRIVATE_BASE64',uri:'file://PHONE_PRIVATE'}]});
 const doc=await new TranscriptExporter().prepare(reader([page([a,item('internal',{role:'system',text:'PRIVATE_SYSTEM'}),a,item('think',{text:'',reasoning:'PRIVATE_THOUGHT'}),item('last')])]),options,()=>{});
 assert.equal(doc.count,2);for(const secret of ['PRIVATE_BASE64','PHONE_PRIVATE','PRIVATE_SYSTEM','PRIVATE_THOUGHT'])assert.equal(doc.text.includes(secret),false);assert.match(doc.text,/metadata.txt/);
});
await test('tool details are opt-in and Markdown fences cannot be closed by tool output',async()=>{
 const tool=item('last',{tools:[{name:'read',status:'completed',input:'{"path":"a"}',output:'TOOL_SECRET\n```\nmore'}]});
 const api=reader([page([tool])]);const plain=await new TranscriptExporter().prepare(api,options,()=>{});assert.equal(plain.text.includes('TOOL_SECRET'),false);
 const detailed=await new TranscriptExporter().prepare(api,{...options,tools:true},()=>{});assert.match(detailed.text,/````\nTOOL_SECRET\n```\nmore\n````/);
 const txt=await new TranscriptExporter().prepare(api,{...options,format:'text',tools:true},()=>{});assert.ok(txt.name.endsWith('.txt'));assert.match(txt.text,/【助手】/);
});
await test('failed, repeated or prematurely ended pagination never returns a partial document',async()=>{
 for(const api of [reader([page([item('a')])]),reader([page([item('a')],'1'),page([item('b')],'1')]),{exportBoundary:async()=>'last',exportPage:async()=>{throw new Error('offline');}}])await assert.rejects(()=>new TranscriptExporter().prepare(api,options,()=>{}));
});
await test('cancellation while awaiting a page prevents progress and subsequent requests',async()=>{
 const g=gate();let reads=0,progress=0;const job=new TranscriptExporter(),run=job.prepare({exportBoundary:async()=>'last',exportPage:async()=>{reads++;return g.promise;}},options,()=>progress++);await flush();job.cancel();g.release(page([item('last')]));await assert.rejects(()=>run,/取消/);assert.equal(reads,1);assert.equal(progress,0);
});
await test('UTF-8 size and filename sanitizing enforce native export boundaries',async()=>{
 assert.equal(utf8Length('中文🌿a'),Buffer.byteLength('中文🌿a'));assert.equal(exportFilename('../a:*?','text'),'.._a___.txt');
 await assert.rejects(()=>new TranscriptExporter().prepare(reader([page([item('last',{text:'中'.repeat(2796203)})])]),options,()=>{}),/8 MB/);
});
await test('message, page and empty-history limits produce explicit outcomes',async()=>{
 await assert.rejects(()=>new TranscriptExporter().prepare(reader([page(Array.from({length:10001},(_,i)=>item(i===10000?'last':String(i))))]),options,()=>{}),/10000/);
 let reads=0;await assert.rejects(()=>new TranscriptExporter().prepare({exportBoundary:async()=>'never',exportPage:async()=>page([item(String(++reads))],String(reads))},options,()=>{}),/2000/);assert.equal(reads,2000);
 const doc=await new TranscriptExporter().prepare({exportBoundary:async()=>'',exportPage:async()=>{throw new Error('should not read');}},options,()=>{});assert.equal(doc.count,0);
});
await test('export protocol keeps ascending order, opaque cursor and raw idle boundary IDs',async()=>{
 const api=new protocol.Protocol({url:'https://example.com'},'');const paths=[];api.request=async path=>{paths.push(path);return{data:[{id:'one',type:'user',text:'first'},{id:'two',type:'assistant',content:[{type:'text',text:'second'}]},{id:'idle',type:'idle'}],cursor:{next:'opaque+/='}};};
 const first=await api.exportPage('a/b','');assert.equal(first.messages.map(m=>m.id).join(','),'one,two');assert.equal(first.ids.join(','),'one,two,idle');await api.exportPage('a/b',first.cursor);assert.match(paths[0],/a%2Fb\/message\?limit=30&order=asc/);assert.match(paths[1],/cursor=opaque%2B%2F%3D/);assert.equal(paths[1].includes('order='),false);
});
await test('large export page falls back to one message while authentication failures never retry',async()=>{
 const api=new protocol.Protocol({url:'https://example.com'},'');let reads=0;api.request=async p=>{reads++;if(p.includes('limit=30'))throw new Error('large');return{data:[{id:'last',type:'user',text:'ok'}]};};assert.equal((await api.exportPage('s','')).messages.length,1);assert.equal(reads,2);
 reads=0;api.request=async()=>{reads++;throw new protocol.ApiError(401,'auth');};await assert.rejects(()=>api.exportPage('s',''));assert.equal(reads,1);
 api.request=async()=>({data:[{type:'user'}]});await assert.rejects(()=>api.exportBoundary('s'),/缺少/);
});
const agentStore=()=>{const s=new AppStore();s.sessionID='s';s.directory='/repo';s.agents=[agent(),agent('plan')];s.agentID='build';s.modelID='p/build';let chosen='build';const posts=[];
 s.api={request:async(path,method,body)=>{if(method==='POST'){posts.push({path,body});chosen=body.agent;}return{data:{}};},interactions:async()=>[],session:async()=>({id:'s',agent:chosen,model:'p/'+chosen}),agents:async()=>s.agents};return{s,posts};};
await test('Agent switch posts exactly the selected ID, confirms server state and reads its model',async()=>{
 const{s,posts}=agentStore();assert.equal(await s.chooseAgent('plan'),true);assert.equal(s.agentID,'plan');assert.equal(s.modelID,'p/plan');assert.equal(JSON.stringify(posts),JSON.stringify([{path:'/api/session/s/agent',body:{agent:'plan'}}]));assert.equal(await s.chooseAgent('plan'),true);assert.equal(posts.length,1);
});
await test('unknown Agent and current or freshly reported running tasks and interactions block writes',async()=>{
 for(const mode of ['unknown','working','pending-send','form','fresh-running','fresh-form','fresh-permission']){const{s,posts}=agentStore();if(mode==='working')s.working=true;if(mode==='pending-send')s.pendingSend={id:'unknown',sessionID:'s',text:'task'};if(mode==='form')s.interactions=[form()];if(mode==='fresh-running')s.api.request=async()=>({data:{s:{type:'running'}}});if(mode.startsWith('fresh-')&&mode!=='fresh-running')s.api.interactions=async(id,kind)=>kind===mode.slice(6)?[form()]:[];assert.equal(await s.chooseAgent(mode==='unknown'?'hidden':'plan'),false);assert.equal(posts.length,0,mode);}
});
await test('Agent rejection retains current selection and allows deliberate retry',async()=>{
 const{s,posts}=agentStore();const request=s.api.request;s.api.request=async(p,m,b)=>{if(m==='POST')throw new protocol.ApiError(400,'Unsupported');return request(p,m,b);};assert.equal(await s.chooseAgent('plan'),false);assert.equal(s.agentID,'build');assert.equal(s.agentUncertain,false);s.api.request=request;assert.equal(await s.chooseAgent('plan'),true);assert.equal(posts.length,1);
});
await test('lost Agent acknowledgement requires readback and never automatically reposts',async()=>{
 const{s}=agentStore();let writes=0;s.api.request=async(p,m)=>{if(m==='POST'){writes++;throw new protocol.ApiError(503,'lost');}return{data:{}};};s.api.session=async()=>({id:'s',agent:'plan',model:'p/plan'});assert.equal(await s.chooseAgent('plan'),false);assert.equal(s.agentUncertain,true);assert.equal(await s.chooseAgent('plan'),false);assert.equal(writes,1);await s.refreshAgentState();assert.equal(s.agentID,'plan');assert.equal(s.agentUncertain,false);assert.equal(writes,1);
});
await test('failed authoritative read retains uncertainty and requires a successful manual refresh',async()=>{
 const{s}=agentStore();s.api.session=async()=>{throw new Error('lost read');};assert.equal(await s.chooseAgent('plan'),false);assert.equal(s.agentUncertain,true);await s.refreshAgentState();assert.equal(s.agentUncertain,true);assert.equal(s.agentLoading,false);
});
await test('in-flight Agent change blocks duplicate switches, sends and model changes',async()=>{
 const{s,posts}=agentStore(),g=gate();const original=s.api.request;s.api.request=async(p,m,b)=>{if(m==='POST')await g.promise;return original(p,m,b);};const run=s.chooseAgent('plan');await flush();assert.equal(await s.chooseAgent('plan'),false);s.draft='do not send';await s.send();await s.chooseModel('p/other');assert.equal(posts.length,0);g.release();assert.equal(await run,true);assert.equal(posts.length,1);
});
await test('late Agent confirmation after disconnect cannot change another conversation',async()=>{
 const{s}=agentStore(),g=gate();s.api.session=async()=>g.promise;const run=s.chooseAgent('plan');await flush();s.disconnect();g.release({id:'s',agent:'plan',model:'p/plan'});assert.equal(await run,false);assert.equal(s.agentID,'');
});
await test('older sync cannot roll back an Agent confirmed while its detail read was in flight',async()=>{
 const{s}=agentStore(),g=gate();s.api.messages=async()=>({data:[]});s.api.parseMessages=()=>[];const original=s.api.request;s.api.request=async(p,m,b)=>{if(p==='/api/session/s'&&!m)return g.promise;return original(p,m,b);};const run=s.sync();await flush();assert.equal(await s.chooseAgent('plan'),true);g.release({data:{id:'s',agent:'build',model:{id:'build',providerID:'p'}}});await run;assert.equal(s.agentID,'plan');assert.equal(s.modelID,'p/plan');
});
await test('export cancellation and project disconnect reject late progress and release the busy state',async()=>{
 for(const action of ['cancel','disconnect']){const{s}=agentStore(),g=gate();s.api.exportBoundary=async()=>'last';s.api.exportPage=async()=>g.promise;const run=s.prepareExport('text',false);await flush();if(action==='cancel')s.cancelExport();else s.disconnect();g.release(page([item('last')]));assert.equal(await run,undefined);assert.equal(s.exporting,false);assert.equal(s.exportCount,0);}
});
await test('new export after cancellation owns its progress even when the old request completes later',async()=>{
 const{s}=agentStore(),g=gate();s.api.exportBoundary=async()=>'last';s.api.exportPage=async()=>g.promise;const old=s.prepareExport('text',false);await flush();s.cancelExport();s.api.exportPage=async()=>page([item('last')]);const doc=await s.prepareExport('text',false);assert.equal(doc.count,1);g.release(page([item('last')]));await old;assert.equal(s.exportCount,1);assert.equal(s.exportError,'');
});
await test('opening another session releases a stale Agent catalog loading flag and changes export scope',async()=>{
 const{s}=agentStore(),g=gate();s.active=false;s.api.agents=async()=>g.promise;const before=s.exportScope();const read=s.loadAgents();assert.equal(s.agentLoading,true);await s.openSession({id:'other',title:'Other',directory:'/repo',model:'p/build'});assert.equal(s.agentLoading,false);assert.notEqual(s.exportScope(),before);g.release([agent('stale')]);await read;assert.equal(s.agentLoading,false);assert.equal(s.agents.some(a=>a.id==='stale'),false);
});
await test('export pages preserve every attachment metadata entry without retaining inline bytes and reject missing message IDs',async()=>{
 const api=new protocol.Protocol({url:'https://example.com'},'');api.request=async()=>({data:[{id:'user',type:'user',text:'hello',files:Array.from({length:6},(_,i)=>({name:'file'+i+'.txt',mime:'text/plain',data:'YQ=='}))}]});const result=await api.exportPage('s','');assert.equal(result.messages[0].files.length,6);assert.ok(result.messages[0].files.every(f=>f.data===''&&f.size===1));api.request=async()=>({data:[{type:'user',text:'missing'}]});await assert.rejects(()=>api.exportPage('s',''),/缺少/);
});
console.log(count+' Agent/export tests passed.');
