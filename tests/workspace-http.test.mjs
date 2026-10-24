import { ts } from './helpers/typescript.mjs';
// Real loopback HTTP integration. No cloud connection, model call or device is used.
import assert from 'node:assert/strict';
import httpServer from 'node:http';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import vm from 'node:vm';

const sessions=Array.from({length:70},(_,i)=>({id:'s'+i,title:'Conversation '+i,location:{directory:'/repo'},time:{created:1,updated:100-i}}));
sessions.push({id:'other',title:'Other project',location:{directory:'/second'},time:{created:1,updated:1}});
const forms=[{id:'q',sessionID:'s0',title:'Choose',fields:[]}];
const permissions=[{id:'p',sessionID:'other',action:'edit',resources:['sample.ts'],metadata:{workdir:'/second',files:[{file:'sample.ts',patch:'--- a/sample.ts\n+++ b/sample.ts\n@@ -1 +1 @@\n-old\n+new\n'}]}}];
const messages=new Map();const receipts=[];let loseSend=true,unauthorized=false;
const server=httpServer.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://127.0.0.1');const path=url.pathname;
 const reply=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(status===204?'':JSON.stringify(data));};
 if(unauthorized||req.headers.authorization!=='Basic '+Buffer.from('u:test-only').toString('base64'))return reply({},401);
 let text='';for await(const chunk of req)text+=chunk;const input=text?JSON.parse(text):undefined;
 if(req.method!=='GET')receipts.push({path,method:req.method,input,query:url.search});
 const directory=url.searchParams.get('location[directory]')||url.searchParams.get('directory');
 if(path==='/api/project')return reply([{id:'one',name:'One',canonical:'/repo'},{id:'two',name:'Two',canonical:'/second'}]);
 if(path==='/api/location')return reply({directory});
 if(path==='/api/model')return reply({data:[]});
 if(path==='/api/session/active')return reply({data:{other:{type:'running'}}});
 if(path==='/api/session'){
  const cursor=url.searchParams.get('cursor');const page=cursor?JSON.parse(Buffer.from(cursor,'base64url').toString()):{offset:0,directory,search:url.searchParams.get('search')||''};
  const rows=sessions.filter(s=>(!page.directory||s.location.directory===page.directory)&&s.title.includes(page.search));
  return reply({data:rows.slice(page.offset,page.offset+50),cursor:{next:page.offset+50<rows.length?Buffer.from(JSON.stringify({...page,offset:page.offset+50})).toString('base64url'):''}});
 }
 if(path==='/api/form')return reply({data:forms.filter(p=>sessions.find(s=>s.id===p.sessionID).location.directory===directory)});
 if(path==='/api/permission/request')return reply({data:permissions.filter(p=>sessions.find(s=>s.id===p.sessionID).location.directory===directory)});
 const match=path.match(/^\/api\/session\/([^/]+)(.*)$/);if(!match)return reply({},404);
 const id=decodeURIComponent(match[1]),suffix=match[2],session=sessions.find(s=>s.id===id);if(!session)return reply({},404);
 if(!suffix&&req.method==='PATCH'){session.title=input.title;return reply({},204);}
 if(!suffix)return reply({data:session});
 if(suffix==='/message')return reply({data:[...(messages.get(id)||[])].reverse(),cursor:{}});
 if(suffix==='/inbox')return reply({data:[]});
 if(suffix==='/form')return reply({data:forms.filter(p=>p.sessionID===id)});
 if(suffix==='/permission')return reply({data:permissions.filter(p=>p.sessionID===id)});
 if(suffix==='/prompt'){
  const rows=messages.get(id)||[];if(!rows.some(m=>m.id===input.id))rows.push({id:input.id,type:'user',text:input.text,time:{created:Date.now()}});messages.set(id,rows);
  if(loseSend){loseSend=false;req.socket.destroy();return;}return reply({},204);
 }
 if(suffix==='/permission/p/reply'){assert.equal(input.decision,'once');permissions.splice(0);return reply({},204);}
 return reply({},404);
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url='http://127.0.0.1:'+server.address().port;
class Encoder{encodeInto(text){return new TextEncoder().encode(text);}}class Decoder{decodeToString(value){return new TextDecoder().decode(value);}}
const modules=new Map([
 ['@kit.NetworkKit',{http:{RequestMethod:{GET:'GET',POST:'POST',DELETE:'DELETE'},HttpDataType:{STRING:0},createHttp:()=>({
  async request(url,options){const r=await fetch(url,{method:options.method,headers:options.header,body:options.extraData});return{responseCode:r.status,result:await r.text()};},
  on(){},destroy(){},requestInStream:async()=>200
 })}}],
 ['@kit.ArkTS',{util:{TextEncoder:Encoder,TextDecoder:Decoder,Base64Helper:class{encodeToStringSync(value){return Buffer.from(value).toString('base64');}}}}],
 ['@kit.AbilityKit',{}],['@kit.BasicServicesKit',{}],['../data/Storage',{Storage:class{async position(){}}}]
]);
function load(path,key){const exports={};const code=ts.transpileModule(readFileSync(path,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}}).outputText;
 vm.runInNewContext(code,{exports,require:name=>{assert.ok(modules.has(name),name);return modules.get(name);},Observed:value=>value,Error,Map,Set,Date,Math,JSON,setTimeout,clearTimeout,setInterval,clearInterval});modules.set(key,exports);return exports;}
load('entry/src/main/ets/domain/MessageBookmarks.ts', '../domain/MessageBookmarks');
load('entry/src/main/ets/domain/PromptTemplates.ts', '../domain/PromptTemplates');
load('entry/src/main/ets/domain/Attachments.ts','../domain/Attachments');load('entry/src/main/ets/domain/Core.ts','../domain/Core');
modules.set('./Core', modules.get('../domain/Core'));
load('entry/src/main/ets/domain/ModelSelection.ts', '../domain/ModelSelection');
load('entry/src/main/ets/domain/Connections.ts', '../domain/Connections');
load('entry/src/main/ets/domain/SessionUsage.ts', '../domain/SessionUsage');load('entry/src/main/ets/data/DedicatedTrust.ets','./DedicatedTrust');
load('entry/src/main/ets/domain/Agents.ts', '../domain/Agents');
load('entry/src/main/ets/domain/TranscriptExport.ts', '../domain/TranscriptExport');
const {Protocol}=load('entry/src/main/ets/data/Protocol.ets','../data/Protocol');load('entry/src/main/ets/presentation/ProviderStore.ets','./ProviderStore');
load('entry/src/main/ets/domain/Notifications.ts','../domain/Notifications');
const {AppStore}=load('entry/src/main/ets/presentation/AppStore.ets','store');const api=new Protocol({url,username:'u',allowHttp:true},'test-only');
const store=new AppStore();store.api=api;store.connected='loopback';store.directory='/repo';store.projects=await api.projects();
let count=0;async function test(name,run){await run();count++;console.log('PASS '+name);}
try{
 await test('HTTP session pages load beyond the first 50 and search the complete server list',async()=>{
  await store.refreshSessions();assert.equal(store.sessions.length,50);assert.ok(store.sessionCursor);await store.refreshSessions(true);assert.equal(store.sessions.length,70);
  await store.refreshSessions(false,'Conversation 69');assert.equal(store.sessions.length,1);assert.equal(store.sessions[0].id,'s69');await store.refreshSessions(false,'');
 });
 await test('HTTP rename changes only the named session using API24-compatible PATCH',async()=>{
  assert.equal(await store.renameSession('s0','Renamed'),true);assert.equal(sessions[0].title,'Renamed');assert.equal(sessions[1].title,'Conversation 1');assert.equal(receipts.at(-1).method,'PATCH');
 });
 await test('lost send acknowledgement is recovered from history after switching projects without reposting',async()=>{
  await store.openSession(api.parseSession(sessions[0]));store.draft='Loopback test only';await store.send();assert.ok(store.pendingSend);const id=store.pendingSend.id;
  await store.openSession(api.parseSession(sessions.at(-1)));store.draft='Other unsent text';await store.openSession(api.parseSession(sessions[0]));
  assert.equal(store.pendingSend,undefined);assert.equal(store.draft,'');assert.ok(store.messages.some(m=>m.id===id));assert.equal(receipts.filter(r=>r.path.endsWith('/prompt')).length,1);
 });
 await test('HTTP pending center includes questions and approvals from different projects',async()=>{
  await store.refreshPending(true);assert.equal(store.pendingItems.length,2);assert.equal(store.sessionLabel('other'),'等待审批');assert.equal(receipts.filter(r=>r.path.includes('/reply')).length,0);
 });
 await test('opening a cross-project approval refreshes its preview and posts exactly one scoped decision',async()=>{
  const item=store.pendingItems.find(p=>p.kind==='permission');await store.openPending(item);assert.equal(store.directory,'/second');assert.equal(store.sessionID,'other');assert.equal(store.draft,'Other unsent text');
  const approval=store.interactions.find(p=>p.kind==='permission');assert.ok(approval.approval.files.length);await store.reply(approval);await store.refreshPending(true);
  const posts=receipts.filter(r=>r.path.endsWith('/permission/p/reply'));assert.equal(posts.length,1);assert.match(posts[0].query,/location%5Bdirectory%5D=%2Fsecond/);assert.equal(store.pendingItems.filter(p=>p.kind==='permission').length,0);
 });
 await test('HTTP authentication failure stops recovery instead of silently clearing pending state',async()=>{
  unauthorized=true;await store.refreshPending(true);assert.equal(store.status,'认证失败');assert.equal(store.networkBlocked,true);assert.ok(store.pendingItems.every(p=>p.stale));
 });
 console.log(count+' loopback HTTP integration tests passed.');
}finally{store.disconnect();await new Promise(resolve=>server.close(resolve));}
