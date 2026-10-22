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
load('entry/src/main/ets/domain/Attachments.ts', '../domain/Attachments');
const core = load('entry/src/main/ets/domain/Core.ts', '../domain/Core');
modules.set('./Core', modules.get('../domain/Core'));
load('entry/src/main/ets/domain/ModelSelection.ts', '../domain/ModelSelection');
const connections=load('entry/src/main/ets/domain/Connections.ts', '../domain/Connections');
const usageDomain=load('entry/src/main/ets/domain/SessionUsage.ts', '../domain/SessionUsage');
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

const flush=()=>new Promise(setImmediate);const gate=()=>{let resolve;return{promise:new Promise(r=>resolve=r),release:v=>resolve(v)};};
const config=(id='one',url='https://one.example')=>({id,name:id,url,username:'opencode',allowHttp:false,preferredModel:'p/m'});
function connectionStore(){
 const s=new AppStore();s.servers=[config(),config('two','https://two.example')];const saved={servers:s.servers,secrets:new Map([['one','old-secret'],['two','second-secret']]),positions:new Map([['one',['/repo','s']]]),flags:new Map([['one',[{id:'s',pinned:true}]]]),writes:[],fail:''};
 const fault=kind=>{if(saved.fail===kind){saved.fail='';throw new Error('controlled '+kind);}};
 s.storage={secret:async id=>saved.secrets.get(id)||'',saveSecret:async(id,text)=>{saved.secrets.set(id,text);saved.writes.push('secret');fault('secret');},saveServers:async rows=>{saved.servers=rows;saved.writes.push('servers');fault('servers');},last:async id=>saved.positions.get(id)||[],sessionPreferences:async id=>saved.flags.get(id)||[],resetServerPosition:async id=>{saved.positions.set(id,[]);saved.flags.set(id,[]);saved.writes.push('reset');fault('reset');},position:async(id,directory,session)=>saved.positions.set(id,[directory,session]),saveSessionPreferences:async(id,rows)=>saved.flags.set(id,rows)};
 s.connect=async row=>{s.connected=row.id;};return{s,saved};
}
await test('connection normalization catches duplicate host, default port and trailing slash while preserving path case',()=>{
 assert.equal(connections.connectionAddress('HTTPS://Example.COM:443/repo/',false),'https://example.com/repo');assert.notEqual(connections.connectionAddress('https://a/Repo',false),connections.connectionAddress('https://a/repo',false));
 assert.throws(()=>connections.prepareConnection({name:'x',url:'HTTPS://ONE.EXAMPLE:443/',username:'opencode',allowHttp:false,useDedicatedTrust:false},[config()],'new'),/已存在/);
});
await test('connection validation rejects unsafe URL, username, plaintext without opt-in and trust mismatch',()=>{
 for(const values of [{url:'https://user:pass@a'},{url:'http://a'},{url:'http://a',allowHttp:true,useDedicatedTrust:true},{username:'bad:user'},{name:'a'.repeat(81)},{url:'https://a\\secret'}])assert.throws(()=>connections.prepareConnection({name:'x',url:'https://a',username:'u',allowHttp:false,useDedicatedTrust:false,...values},[],'new'));
});
await test('editing a connection preserves its ID, password, bookmarks, position and model preference',async()=>{
 const{s,saved}=connectionStore();s.editServer(s.servers[0]);assert.equal(s.serverPassword,'');s.serverName='Renamed';assert.equal(await s.saveServer(),true);assert.equal(s.servers[0].id,'one');assert.equal(s.servers[0].name,'Renamed');assert.equal(saved.secrets.get('one'),'old-secret');assert.deepEqual(saved.positions.get('one'),['/repo','s']);assert.equal(saved.flags.get('one')[0].pinned,true);assert.equal(s.servers[0].preferredModel,'p/m');assert.equal(saved.writes.includes('secret'),false);
});
await test('new password and explicit clear are separate actions and blank edits do not delete credentials',async()=>{
 const{s,saved}=connectionStore();s.editServer(s.servers[0]);s.serverPassword='replacement';assert.equal(await s.saveServer(),true);assert.equal(saved.secrets.get('one'),'replacement');s.editServer(s.servers[0]);s.clearServerPassword=true;assert.equal(await s.saveServer(),true);assert.equal(saved.secrets.get('one'),'');s.editServer(s.servers[0]);s.clearServerPassword=true;s.serverPassword='ambiguous';assert.equal(await s.saveServer(),false);assert.equal(saved.secrets.get('one'),'');
});
await test('changing endpoint or account resets only that connection local context and keeps its identity',async()=>{
 for(const field of ['url','username']){const{s,saved}=connectionStore();s.editServer(s.servers[0]);if(field==='url')s.serverUrl='https://new.example';else s.serverUser='another';assert.equal(await s.saveServer(),true);assert.equal(s.servers[0].id,'one');assert.equal(s.servers[0].preferredModel,'');assert.deepEqual(saved.positions.get('one'),[]);assert.deepEqual(saved.flags.get('one'),[]);assert.equal(saved.secrets.get('one'),'old-secret');assert.equal(saved.secrets.get('two'),'second-secret');}
});
await test('failed credential, preferences or identity reset writes restore the original data',async()=>{
 for(const mode of ['secret','servers','reset']){const{s,saved}=connectionStore();s.editServer(s.servers[0]);s.serverUrl='https://new.example';s.serverPassword='replacement';saved.fail=mode;assert.equal(await s.saveServer(),false);assert.equal(s.servers[0].url,'https://one.example');assert.equal(saved.servers[0].url,'https://one.example');assert.equal(saved.secrets.get('one'),'old-secret');assert.deepEqual(saved.positions.get('one'),['/repo','s']);assert.equal(saved.flags.get('one')[0].pinned,true);assert.equal(s.serverSaving,false);}
});
await test('connection saving freezes click-time values and blocks duplicate submission',async()=>{
 const{s,saved}=connectionStore(),g=gate();s.editServer(s.servers[0]);s.serverName='Original';s.serverPassword='first-key';const save=s.storage.saveSecret;s.storage.saveSecret=async(...args)=>{await g.promise;return save(...args);};const run=s.saveServer();await flush();s.serverName='Later';s.serverPassword='later-key';assert.equal(await s.saveServer(),false);g.release();assert.equal(await run,true);assert.equal(s.servers[0].name,'Original');assert.equal(saved.secrets.get('one'),'first-key');
});
await test('duplicate endpoint validation writes nothing and retains the existing authenticated connection',async()=>{
 const{s,saved}=connectionStore();s.connected='one';s.serverName='Duplicate';s.serverUrl='https://ONE.example:443/';s.serverUser='opencode';s.serverPassword='should-not-write';assert.equal(await s.saveServer(),false);assert.equal(saved.writes.length,0);assert.equal(s.connected,'one');assert.equal(s.servers.length,2);
});
await test('removing a connection clears local metadata and secret, and storage failure rolls back',async()=>{
 const{s,saved}=connectionStore();assert.equal(await s.removeServer('one'),true);assert.equal(s.servers.length,1);assert.equal(saved.secrets.get('one'),'');assert.deepEqual(saved.positions.get('one'),[]);assert.equal(saved.secrets.get('two'),'second-secret');
 const second=connectionStore();second.saved.fail='servers';assert.equal(await second.s.removeServer('one'),false);assert.equal(second.s.servers.length,2);assert.equal(second.saved.secrets.get('one'),'old-secret');assert.deepEqual(second.saved.positions.get('one'),['/repo','s']);
});
function controlStore(){
 const s=new AppStore();s.connected='one';s.servers=[config()];s.directory='/repo';s.sessionID='parent';s.sessionTitle='Parent';s.active=false;s.modelID='p/m';s.models=[{id:'p/m',label:'Model',contextLimit:128000}];s.messages=[{...message('u1','First'),role:'user'},message('a1','First answer'),{...message('u2','Original question'),role:'user'},message('a2','Latest answer')];
 const parent={id:'parent',title:'Parent',location:{directory:'/repo'},model:{providerID:'p',id:'m'},outcome:'succeeded',cost:0,tokens:{input:123,output:45,reasoning:6,cache:{read:7,write:8}}};
 const data={posts:[],parent,active:false,forms:[],permissions:[],inbox:[],raw:new Map([['u2',{id:'u2',type:'user',text:'Original question',files:[{name:'sample.txt',mime:'text/plain',data:'c2FtcGxl'}]}]]),requestMode:'',lostApplied:true,reads:[],forks:0};
 const api=new protocol.Protocol(config(),'test-only');api.request=async(rawPath,method='GET',body)=>{
  const path=rawPath.split('?')[0];data.reads.push(rawPath);if(method==='POST')data.posts.push({path,body});
  if(path==='/api/session/active')return{data:data.active?{parent:{type:'running'}}:{}};
  if(path.endsWith('/form'))return{data:data.forms};if(path.endsWith('/permission'))return{data:data.permissions};if(path.endsWith('/inbox'))return{data:data.inbox};
  if(path==='/api/session/parent')return{data:data.parent};
  if(path.endsWith('/fork')){if(data.requestMode==='reject')throw new protocol.ApiError(400,'fork rejected');const child={...parent,id:'child'+(++data.forks),title:'Branch',fork:{sessionID:'parent',boundary:{type:body.before?'before':'through',messageID:body.before||'a2'}}};if(data.requestMode==='lost')throw new protocol.ApiError(503,'lost acknowledgement');return{data:child};}
  if(path.endsWith('/compact')){
   if(data.requestMode==='reject')throw new protocol.ApiError(400,'compact rejected');
   const row={id:body.id,sessionID:'parent',type:'compaction',delivery:'queue',payload:{},time:{created:1}};
   if(data.requestMode!=='lost-unapplied')data.inbox=[row];if(data.requestMode.startsWith('lost'))throw new protocol.ApiError(503,'lost acknowledgement');data.inbox=[row];return{data:row};
  }
  const exact=path.match(/\/message\/([^/?]+)$/);if(exact){const row=data.raw.get(decodeURIComponent(exact[1]));if(!row)throw new protocol.ApiError(404,'missing');return{data:row};}
  if(path.endsWith('/message'))return{data:[],cursor:{}};
  throw new Error('Unmocked request '+path);
 };s.api=api;return{s,data,api};
}
await test('fork exact protocol uses exclusive before and full history omits before',async()=>{
 const{s,data}=controlStore();const child=await s.forkSession('u2',false,'',false);assert.equal(child.parentID,'parent');assert.equal(child.forkType,'before');assert.equal(data.posts[0].path,'/api/session/parent/fork');assert.equal(JSON.stringify(data.posts[0].body),'{'+'"before":"u2"}');assert.equal(s.sessionID,'parent');assert.equal(data.posts.some(p=>p.path.endsWith('/prompt')),false);
 const full=controlStore();await full.s.forkSession('',false,'',false);assert.equal(JSON.stringify(full.data.posts[0].body),'{}');
});
await test('edit and fork keeps original draft and prepares text plus original attachments without sending',async()=>{
 const{s,data}=controlStore();s.draft='Original unsent draft';const child=await s.forkSession('u2',true,'Edited question',true);assert.ok(child);assert.equal(s.draft,'Original unsent draft');assert.equal(data.posts.length,1);await s.openSession(child);assert.equal(s.draft,'Edited question');assert.equal(s.attachments[0].name,'sample.txt');assert.equal(s.parentSessionID,'parent');await s.openSession(s.api.parseSession(data.parent));assert.equal(s.draft,'Original unsent draft');
});
await test('fork attachment exclusion is explicit and oversized or unsupported reuse is rejected before creation',async()=>{
 const{s,data}=controlStore();data.raw.get('u2').files=Array.from({length:5},()=>({name:'a.txt',mime:'text/plain',data:'YQ=='}));assert.equal(await s.forkSession('u2',true,'Edited',true),undefined);assert.equal(data.posts.length,0);const reads=data.reads.length;const child=await s.forkSession('u2',true,'Edited',false);assert.equal(data.reads.slice(reads).some(p=>p.includes('/message/u2')),false);await s.openSession(child);assert.equal(s.attachments.length,0);assert.equal(s.draft,'Edited');
});
await test('draft capacity and stale message validation fail before a fork is posted',async()=>{
 const{s,data}=controlStore();for(let i=0;i<100;i++)s.conversationMemory.save('other','/r','s'+i,'draft',undefined,[]);assert.equal(await s.forkSession('u2',true,'Edited',false),undefined);assert.equal(data.posts.length,0);const other=controlStore();assert.equal(await other.s.forkSession('missing',false,'',false),undefined);assert.equal(other.data.posts.length,0);
});
await test('fork rejected by server can retry, but uncertain creation blocks repost across session revisits until reviewed',async()=>{
 const{s,data}=controlStore();data.requestMode='reject';assert.equal(await s.forkSession('u2',false,'',false),undefined);assert.equal(s.forkUncertain,false);data.requestMode='lost';assert.equal(await s.forkSession('u2',false,'',false),undefined);assert.equal(s.forkUncertain,true);const before=data.posts.length;assert.equal(await s.forkSession('u2',false,'',false),undefined);assert.equal(data.posts.length,before);s.resetSessionControl();assert.equal(s.forkUncertain,true);s.clearForkAfterReview();data.requestMode='';assert.ok(await s.forkSession('u2',false,'',false));
});
await test('fork busy and late responses cannot redirect or contaminate another connection',async()=>{
 const{s,data,api}=controlStore(),g=gate();const request=api.request;api.request=async(p,m,b)=>{if(p.endsWith('/fork'))await g.promise;return request(p,m,b);};const run=s.forkSession('u2',true,'Edited',false);await flush();assert.equal(await s.forkSession('u2',true,'Duplicate',false),undefined);s.disconnect();g.release();await run;assert.equal(s.sessionID,'');assert.equal(s.messages.length,0);assert.equal(data.posts.length,1);assert.equal(s.forkBusy,false);
});
await test('running tasks, forms, approvals, inbox work and staged revert block fork and compaction',async()=>{
 for(const mode of ['active','form','permission','inbox','revert','pending-send'])for(const operation of ['fork','compact']){const{s,data}=controlStore();if(mode==='active')data.active=true;if(mode==='form')data.forms=[{id:'f',fields:[]}];if(mode==='permission')data.permissions=[{id:'p'}];if(mode==='inbox')data.inbox=[{id:'other',type:'user'}];if(mode==='revert')data.parent.revert={messageID:'u1'};if(mode==='pending-send')s.pendingSend={id:'unknown',sessionID:'parent',text:'task'};if(operation==='fork')await s.forkSession('u2',false,'',false);else await s.requestCompaction();assert.equal(data.posts.length,0,mode+' '+operation);}
});
await test('server usage distinguishes missing values from zero and formats USD without estimating context occupancy',()=>{
 const unknown=protocol.parseUsage({});assert.equal(unknown.input,-1);assert.equal(unknown.cost,-1);const zero=protocol.parseUsage({cost:0,tokens:{input:0,output:45,reasoning:0,cache:{read:0,write:0}}});assert.equal(zero.cost,0);assert.equal(usageDomain.costLabel(zero.cost),'$0');assert.equal(usageDomain.costLabel(0.123456),'$0.123456');assert.equal(usageDomain.costLabel(0.0000001),'<$0.000001');assert.equal(usageDomain.tokenLabel(12345),'12,345');for(const value of [-1,NaN,Infinity,'0',null])assert.equal(usageDomain.usageValue(value),-1);
});
await test('usage refresh keeps previous data on failure and ignores another connection late results',async()=>{
 const{s,data,api}=controlStore();await s.refreshUsage();assert.equal(s.usage.input,123);assert.equal(s.usage.cost,0);const request=api.request;api.request=async()=>{throw new Error('offline');};await s.refreshUsage();assert.equal(s.usage.input,123);assert.ok(s.usageError);const g=gate();api.request=async p=>p==='/api/session/parent'?g.promise:request(p);const read=s.refreshUsage();await flush();s.disconnect();g.release({data:data.parent});await read;assert.equal(s.usage.input,-1);
});
await test('compaction ack is queued, matching message determines running/completed/failed and exact reads work outside current page',async()=>{
 const{s,data}=controlStore();await s.requestCompaction();assert.equal(s.compaction.state,'queued');assert.equal(data.posts.length,1);assert.equal(data.posts[0].body.delivery,'queue');const id=s.compaction.id;data.inbox=[];for(const state of ['running','completed','failed']){data.raw.set(id,{id,type:'compaction',status:state,error:{message:'Model unavailable'}});await s.refreshUsage();assert.equal(s.compaction.state,state);}assert.match(s.compaction.error,/Model unavailable/);assert.equal(data.posts.length,1);
});
await test('lost compaction acknowledgement is reconciled by request ID without reposting',async()=>{
 const{s,data}=controlStore();data.requestMode='lost';await s.requestCompaction();assert.equal(s.compaction.state,'unknown');const id=s.compaction.id;await s.requestCompaction();assert.equal(s.compaction.state,'queued');assert.equal(s.compaction.id,id);assert.equal(data.posts.length,1);
});
await test('unapplied compaction retry reuses the original ID rather than creating another request',async()=>{
 const{s,data}=controlStore();data.requestMode='lost-unapplied';await s.requestCompaction();const id=s.compaction.id;data.requestMode='';await s.requestCompaction();assert.equal(s.compaction.state,'queued');assert.equal(s.compaction.id,id);assert.equal(data.posts.length,2);assert.equal(data.posts[0].body.id,data.posts[1].body.id);
});
await test('queued compaction blocks a second compact request and message send',async()=>{
 const{s,data}=controlStore();await s.requestCompaction();const before=data.posts.length;await s.requestCompaction();s.draft='Do not send during compaction';await s.send();assert.equal(data.posts.length,before);
});
await test('failed compaction status reads retain the known request and never imply completion or emit a new request',async()=>{
 const{s,data,api}=controlStore();await s.requestCompaction();const id=s.compaction.id;api.compactionStatus=async()=>{throw new Error('offline');};await s.refreshUsage();assert.equal(s.compaction.id,id);assert.equal(s.compaction.state,'queued');assert.ok(s.usageError);assert.equal(data.posts.length,1);
});
await test('late compaction after endpoint identity change cannot publish into the replacement connection',async()=>{
 const{s,api}=controlStore(),g=gate();const compact=api.compact.bind(api);api.compact=async(...args)=>{await g.promise;return compact(...args);};const run=s.requestCompaction();await flush();s.clearControlRecords('one');s.resetSessionControl();s.disconnect();g.release();await run;assert.equal(s.compaction.state,'');assert.equal(s.compactRecords.size,0);
});
await test('compaction conversation marker reports actual status and model context limit comes from server',async()=>{
 const{s,api}=controlStore();const messages=api.parseMessages({data:[{id:'c',type:'compaction',status:'completed'}]});assert.equal(messages[0].text,'上下文压缩已完成');const request=api.request;api.request=async p=>p.startsWith('/api/model')?{data:[{modelID:'m',providerID:'p',limit:{context:128000}}]}:request(p);assert.equal((await api.models('/repo'))[0].contextLimit,128000);
});
await test('invalid legacy addresses do not block new connections, and unexpected fork boundaries are never accepted',async()=>{
 const row=connections.prepareConnection({name:'New',url:'https://new.example',username:'opencode',allowHttp:false,useDedicatedTrust:false},[config('old','https://old\\broken')],'new');assert.equal(row.url,'https://new.example');assert.equal(connections.sameConnectionIdentity(config('old','https://old\\broken'),row),false);
 const{s,api}=controlStore();api.request=async()=>({data:{id:'child',parentID:'parent',location:{directory:'/repo'},fork:{sessionID:'parent',boundary:{type:'before',messageID:'wrong'}}}});await assert.rejects(()=>api.fork('parent','u2'),/未能确认/);
});
await test('branch source and Agent survive user renaming and server title refresh',async()=>{
 const{s,data,api}=controlStore();const session={id:'parent',title:'Parent',directory:'/repo',status:'idle',model:'p/m',agent:'build',parentID:'grandparent',forkType:'before',forkBefore:'u0'};s.sessions=[session];
 api.renameSession=async()=>{};assert.equal(await s.renameSession('parent','Renamed'),true);assert.equal(s.sessions[0].title,'Renamed');
 for(const key of ['agent','parentID','forkType','forkBefore'])assert.equal(s.sessions[0][key],session[key]);
 data.parent.title='Server title';s.active=true;await s.sync();assert.equal(s.sessions[0].title,'Server title');
 for(const key of ['agent','parentID','forkType','forkBefore'])assert.equal(s.sessions[0][key],session[key]);
});
await test('home recent sessions exclude local archives, respect pins and ignore list search/archive mode',()=>{
 const{s}=controlStore();s.sessions=Array.from({length:6},(_,i)=>({id:'s'+i,title:'Session '+i,directory:'/repo',status:'idle',model:''}));
 s.sessionPreferences=[{id:'s0',archived:true,pinned:false},{id:'s4',archived:false,pinned:true}];s.showArchived=true;s.sessionQuery='does not match';
 assert.equal(Array.from(s.recentSessions(),s=>s.id).join(','),'s4,s1,s2');assert.equal(s.showArchived,true);assert.equal(s.sessionQuery,'does not match');
 s.sessionPreferences.push({id:'old-pin',pinned:true,archived:false,title:'Pinned outside current page',directory:'/repo'});assert.equal(Array.from(s.recentSessions(),s=>s.id).join(','),'s4,old-pin,s1');
});
console.log(count+' workspace control tests passed.');
