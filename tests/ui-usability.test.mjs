import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';
import {ts} from './helpers/typescript.mjs';

const index=readFileSync('entry/src/main/ets/pages/Index.ets','utf8');
const storeSource=readFileSync('entry/src/main/ets/presentation/AppStore.ets','utf8');
function method(source,name){
 const start=source.match(new RegExp('^  (?:private )?(?:async )?'+name+'\\(','m'));
 assert.ok(start,'Actual method '+name);
 const remaining=source.slice(start.index),line=remaining.split('\n')[0];
 if(line.trimEnd().endsWith('}'))return line;
 const end=remaining.match(/^  }/m);assert.ok(end,'End of '+name);return remaining.slice(0,end.index+end[0].length);
}
const compile=source=>ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
const colors={success:'green',danger:'red',warning:'amber',muted:'gray'};
const sidebar=index.slice(index.indexOf('  sidebar(width: number)'),index.indexOf('  attachmentPopup()'));
const indicator=sidebar.match(/StatusLed\(\{ color: (.*?) \}\)/);assert.ok(indicator);
const handlers=['connectionColor','chatStatus','composerStatusAction','composerActionLabel','performComposerStatusAction',
 'canSearchHistory','searchServerHistory','clearHistorySearch','historySearchChanged'].map(name=>method(index,name)).join('\n');
const exports={};
vm.runInNewContext(compile('export class Page {\n'+handlers+'\n indicatorColor() { return '+indicator[1]+'; }\n}\n'+
 'export class Store {\n'+method(storeSource,'refreshSessions')+'\n}'),{exports,C:colors,Map,Array,Error});
const settle=async()=>{for(let i=0;i<16;i++)await Promise.resolve();};
const gate=()=>{let release;return{promise:new Promise(r=>release=r),release};};
const sessions=[{id:'a',title:'Alpha task'},{id:'b',title:'Beta task'},{id:'c',title:'Alpha notes'}];
const pageFor=query=>({sessions:sessions.filter(s=>s.title.toLowerCase().includes(query.toLowerCase())),cursor:''});
function fixture(){
 const requests=[],calls={sync:0,keyboard:0,navigation:[],failures:[]};
 const store=new exports.Store();
 Object.assign(store,{connected:'test-only',status:'实时连接',directory:'/test-only',online:true,cacheRestored:false,
  sessions:sessions.slice(),sessionQuery:'',sessionCursor:'',sessionsBusy:false,sessionsError:'',sessionsEpoch:0,
  pendingSend:undefined,modelUncertain:false,agentUncertain:false,interactions:[],working:false,interrupting:false,draftNotice:'',busy:false,
  canSendMessages:()=>store.online,sync:()=>{calls.sync++;},fail:error=>calls.failures.push(error.message),
  send:()=>{throw Error('A status control must never send a prompt');}});
 store.api={async sessionPage(directory,cursor,query){requests.push({directory,cursor,query});return pageFor(query);}};
 const page=new exports.Page();
 Object.assign(page,{store,pickingAttachments:false,quietNotice:'',sessionSearch:'',historySearching:false,historySearchEpoch:0,
  historySearchQuery:'',historySearchScope:'',dismissKeyboard:()=>{calls.keyboard++;},navigate:name=>calls.navigation.push(name)});
 return{page,store,requests,calls};
}
let count=0;
async function check(name,run){await run();count++;console.log('PASS '+name);}

await check('actual sidebar indicator shows authentication and certificate failures in red despite retained connection identity',()=>{
 const{page,store}=fixture();store.online=false;
 for(const status of ['认证失败','证书校验失败','连接失败']){store.status=status;assert.equal(page.indicatorColor(),'red');}
});
await check('green requires both verified connection status and an available authenticated channel',()=>{
 const{page,store}=fixture();
 for(const status of ['已连接','实时连接']){store.status=status;assert.equal(page.indicatorColor(),'green');store.online=false;assert.equal(page.indicatorColor(),'gray');store.online=true;}
 store.connected='';assert.equal(page.indicatorColor(),'gray');
});
await check('reconnecting, offline and paused states stay distinct from healthy and failed connections',()=>{
 const{page,store}=fixture();
 for(const status of ['正在连接','重新连接中','离线缓存','后台暂停连接']){store.status=status;assert.equal(page.indicatorColor(),'amber');}
 store.status='实时连接';store.cacheRestored=true;assert.equal(page.indicatorColor(),'amber');
 store.status='认证失败';assert.equal(page.indicatorColor(),'red');store.cacheRestored=false;store.status='未知状态';assert.equal(page.indicatorColor(),'gray');
});
await check('send reconciliation takes precedence over other actions and reads state without posting a prompt',()=>{
 const{page,store,calls}=fixture();store.pendingSend={id:'test-only'};store.interactions=[{}];page.quietNotice='Task complete';
 assert.equal(page.composerStatusAction(),'sync');assert.equal(page.composerActionLabel(),'同步核对');assert.equal(page.chatStatus(),'发送结果待核对');
 page.performComposerStatusAction();assert.equal(calls.sync,1);assert.equal(calls.navigation.length,0);assert.equal(page.quietNotice,'Task complete');
});
await check('busy reconciliation is blocked and model verification uses the existing synchronization path',()=>{
 const{page,store,calls}=fixture();store.modelUncertain=true;store.busy=true;page.performComposerStatusAction();assert.equal(calls.sync,0);
 store.busy=false;assert.equal(page.composerActionLabel(),'核对模型');page.performComposerStatusAction();assert.equal(calls.sync,1);
});
await check('pending action opens the pending center and dismiss action changes only its own notice',()=>{
 const{page,store,calls}=fixture();store.interactions=[{},{}];page.quietNotice='Task complete';
 assert.equal(page.composerActionLabel(),'待处理 2');page.performComposerStatusAction();assert.deepEqual(calls.navigation,['pending']);assert.equal(page.quietNotice,'Task complete');
 store.interactions=[];assert.equal(page.composerActionLabel(),'收起提示');page.performComposerStatusAction();assert.equal(page.quietNotice,'');assert.equal(calls.sync,0);
});
await check('a retained recovery prompt cannot synchronize through a blocked authenticated channel',()=>{
 const{page,store,calls}=fixture();store.pendingSend={id:'test-only'};store.online=false;store.status='认证失败';
 page.performComposerStatusAction();assert.equal(calls.sync,0);assert.equal(store.pendingSend.id,'test-only');
 store.online=true;page.performComposerStatusAction();assert.equal(calls.sync,1);
});
await check('an obscuring status never dispatches an unrelated hidden action',()=>{
 for(const state of [{cacheRestored:true},{interrupting:true},{agentUncertain:true},{working:true},{draftNotice:'Restored draft'}]){
  const{page,store,calls}=fixture();Object.assign(store,state);page.quietNotice='Task complete';assert.equal(page.composerStatusAction(),'');page.performComposerStatusAction();assert.equal(page.quietNotice,'Task complete');assert.equal(calls.sync,0);
 }
 const{page,store}=fixture();page.pickingAttachments=true;store.pendingSend={};assert.equal(page.composerStatusAction(),'');
});
await check('typing and clearing a local filter perform no network requests',async()=>{
 const{page,requests}=fixture();page.historySearchChanged('Alpha');assert.equal(page.sessionSearch,'Alpha');page.clearHistorySearch();await settle();
 assert.equal(page.sessionSearch,'');assert.equal(requests.length,0);
});
await check('explicit server searches use the bounded query and the actual store updates its scope',async()=>{
 const{page,store,requests}=fixture();await page.searchServerHistory('  Alpha  ');
 assert.equal(requests[0].query,'Alpha');assert.equal(store.sessionQuery,'Alpha');assert.equal(Array.from(store.sessions,s=>s.id).join(','),'a,c');assert.equal(page.historySearching,false);
 await page.searchServerHistory('x'.repeat(250));assert.equal(requests[1].query.length,200);
});
await check('clearing the input exits active server search and reloads the unfiltered history',async()=>{
 const{page,store,requests}=fixture();page.sessionSearch='Alpha';await page.searchServerHistory('Alpha');page.historySearchChanged('');await settle();
 assert.equal(requests.length,2);assert.equal(requests[1].query,'');assert.equal(store.sessionQuery,'');assert.equal(store.sessions.length,3);assert.equal(page.sessionSearch,'');
});
await check('failed history reset retains its visible server scope and can be retried',async()=>{
 const{page,store}=fixture();await page.searchServerHistory('Alpha');const api=store.api;
 store.api={async sessionPage(){throw Error('Local test failure');}};page.clearHistorySearch();await settle();
 assert.equal(store.sessionQuery,'Alpha');assert.equal(store.sessions.length,2);assert.equal(store.sessionsError,'Local test failure');assert.equal(page.historySearching,false);
 store.api=api;page.clearHistorySearch();await settle();assert.equal(store.sessionQuery,'');assert.equal(store.sessions.length,3);assert.equal(store.sessionsError,'');
});
await check('a delayed server search cannot overwrite a completed clear request',async()=>{
 const{page,store}=fixture();const old=gate();store.api.sessionPage=async(_d,_c,q)=>q==='Alpha'?old.promise:pageFor(q);
 page.sessionSearch='Alpha';const searching=page.searchServerHistory('Alpha');page.historySearchChanged('');await settle();
 assert.equal(page.historySearching,false);assert.equal(store.sessions.length,3);old.release(pageFor('Alpha'));await searching;
 assert.equal(store.sessionQuery,'');assert.equal(store.sessions.length,3);assert.equal(page.historySearching,false);
});
await check('completion of an older request does not hide a still-pending history reset',async()=>{
 const{page,store}=fixture();const old=gate(),reset=gate();store.api.sessionPage=async(_d,_c,q)=>q==='Alpha'?old.promise:reset.promise;
 const searching=page.searchServerHistory('Alpha');page.clearHistorySearch();old.release(pageFor('Alpha'));await searching;
 assert.equal(page.historySearching,true);reset.release(pageFor(''));await settle();assert.equal(page.historySearching,false);assert.equal(store.sessionQuery,'');
});
await check('repeated submit and repeated clear are coalesced while their requests are pending',async()=>{
 const{page,store,requests}=fixture();const old=gate(),reset=gate();store.api.sessionPage=async(d,c,q)=>{requests.push({query:q});return q==='Alpha'?old.promise:reset.promise;};
 const searching=page.searchServerHistory('Alpha');await page.searchServerHistory('Alpha');assert.equal(requests.length,1);
 page.clearHistorySearch();page.clearHistorySearch();assert.equal(requests.length,2);reset.release(pageFor(''));old.release(pageFor('Alpha'));await searching;await settle();assert.equal(store.sessions.length,3);
});
await check('offline or missing workspace never starts a server search, including on clear',async()=>{
 for(const state of [{online:false},{directory:''}]){
  const{page,store,requests}=fixture();Object.assign(store,state);store.sessionQuery='Alpha';page.sessionSearch='Alpha';
  await page.searchServerHistory('Beta');page.clearHistorySearch();await settle();assert.equal(requests.length,0);assert.equal(store.sessionQuery,'Alpha');assert.equal(page.sessionSearch,'');
 }
});
await check('identical queries in a different workspace do not share an in-flight request',async()=>{
 const{page,store,requests}=fixture();const old=gate();store.api.sessionPage=async(d,c,q)=>{requests.push({directory:d});return d==='/test-only'?old.promise:pageFor(q);};
 const searching=page.searchServerHistory('Alpha');store.directory='/second-test-workspace';await page.searchServerHistory('Alpha');
 assert.equal(requests.length,2);old.release(pageFor('Beta'));await searching;assert.equal(Array.from(store.sessions,s=>s.id).join(','),'a,c');
});
console.log(count+' actual UI handler and history-store usability checks passed; touch geometry and rendering require device acceptance.');
