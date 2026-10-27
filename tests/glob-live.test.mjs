// Real isolated test: only one glob is auto-approved; every other tool requires an unanswered approval.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {api,scope,pause} from './live-api.mjs';
assert.equal(process.env.OPENCODE_ALLOW_MODEL_TEST,'1','Set OPENCODE_ALLOW_MODEL_TEST=1 only after authorizing this controlled model test.');
const directory=process.env.OPENCODE_GLOB_DIRECTORY;
if(!directory?.startsWith('/')||!directory.endsWith('/workspaces/mobile-acceptance'))throw new Error('Set OPENCODE_GLOB_DIRECTORY to the owned synthetic acceptance repository');
const query='?'+scope(directory);const session=(await api('/api/session','POST',{title:'glob 运行时回归',location:{directory}})).data;
writeFileSync('.test/glob-live-session.json',JSON.stringify({id:session.id,directory}));
try{
 await api('/api/session/'+session.id+query,'PATCH',{permissions:[{action:'*',resource:'*',effect:'ask'},{action:'glob',resource:'**/*.ts',effect:'allow'}]});
 await api('/api/session/'+session.id+'/model'+query,'POST',{model:{providerID:'opencode',id:'mimo-v2.6-flash-free'}});
 await api('/api/session/'+session.id+'/prompt'+query,'POST',{id:'msg_glob_'+Date.now().toString(36),text:'Call the glob tool exactly once with pattern **/*.ts and no optional arguments. Do not read files, run commands, edit files, call other tools or retry. Then finish.',delivery:'steer',resume:true});
 let tool;
 for(let i=0;i<55;i++){
   const messages=(await api('/api/session/'+session.id+'/message'+query)).data;
   tool=messages.flatMap(m=>m.content||[]).find(c=>c.type==='tool'&&c.name==='glob');
   const failure=messages.find(m=>m.type==='assistant'&&m.finish==='error');
   if(failure)throw new Error('Model failed before glob: '+(failure.error?.type||'provider')+' '+(failure.error?.message||'unknown').slice(0,220));
   if(tool&&['completed','error'].includes(tool.state.status))break;
   await pause(1000);
 }
 assert.ok(tool,'Model did not call glob within the bounded test window');
 writeFileSync('.test/glob-live-result.json',JSON.stringify(tool));
 console.log('Actual glob status='+tool.state.status+' elapsed='+(tool.time.completed-tool.time.created)+'ms'+(tool.state.error?' error='+tool.state.error.message:''));
 assert.equal(tool.state.status,'completed','The real glob tool must complete instead of timing out');
 const output=(tool.state.content||[]).map(c=>c.text||'').join('\n');assert.match(output,/greeting\.ts/);
 console.log('PASS actual OpenCode glob returns the known synthetic greeting.ts file.');
}finally{await api('/api/session/'+session.id+'/interrupt'+query,'POST').catch(()=>{});}
