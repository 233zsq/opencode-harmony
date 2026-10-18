// Explicit opt-in: one synthetic attachment prompt through the dedicated built-in free MiMo provider.
import assert from 'node:assert/strict';
import {readFileSync,writeFileSync} from 'node:fs';
import {api,pause} from './live-api.mjs';
assert.equal(process.env.OPENCODE_ALLOW_MODEL_TEST,'1','Set OPENCODE_ALLOW_MODEL_TEST=1 only after authorizing this controlled model test.');
const projects=await api('/api/project');const directory=projects.find(p=>p.canonical?.endsWith('/workspaces/mobile-acceptance'))?.canonical;assert.ok(directory,'Dedicated acceptance workspace missing');
const session=(await api('/api/session','POST',{title:'HarmonyOS 附件验收',location:{directory}})).data;assert.ok(session.id);
const record={sessionID:session.id,directory,promptID:'msg_attachment_'+Date.now().toString(36),state:'created'};writeFileSync('.test/live-attachments.json',JSON.stringify(record,null,2));
try{
 await api('/api/session/'+session.id+'/model','POST',{model:{providerID:'opencode',id:'mimo-v2.6-flash-free'}});
 const files=[{uri:'data:image/png;base64,'+readFileSync('.test/content-fixtures/harmony-sample.png').toString('base64'),name:'harmony-sample.png'},{uri:'data:text/plain;base64,'+readFileSync('.test/content-fixtures/harmony-sample.txt').toString('base64'),name:'harmony-sample.txt'}];
 await api('/api/session/'+session.id+'/prompt','POST',{id:record.promptID,text:'这是鸿蒙客户端附件接收验收。请不要调用工具或修改文件，只回答两项：图片左侧和右侧各是什么颜色？文本附件的第一行是什么？',files,delivery:'steer',resume:true});
 let completed;
 for(let i=0;i<60;i++){
  await pause(1500);const page=await api('/api/session/'+session.id+'/message?limit=30&order=desc');
  const user=page.data.find(m=>m.id===record.promptID);if(user){assert.equal(user.files.length,2);record.acceptedFiles=user.files.map(f=>({name:f.name,mime:f.mime}));}
  const replies=page.data.filter(m=>m.type==='assistant');if(replies.some(m=>m.content?.some(c=>c.type==='tool')))throw new Error('Unexpected tool request during attachment validation');
  completed=replies.find(m=>m.time?.completed);if(completed)break;
 }
 assert.ok(completed,'MiMo attachment response timed out');if(completed.error)throw new Error('MiMo returned a model error');
 const answer=completed.content.filter(c=>c.type==='text').map(c=>c.text).join('\n');assert.match(answer,/红|red/i);assert.match(answer,/蓝|blue/i);assert.ok(answer.includes('HARMONY_ATTACHMENT_FIXTURE'));
 record.state='passed';record.answer=answer;writeFileSync('.test/live-attachments.json',JSON.stringify(record,null,2));console.log('PASS official free MiMo understood the synthetic image colors and exact first line of the UTF-8 attachment; no tools called.');
}catch(error){record.state='failed';writeFileSync('.test/live-attachments.json',JSON.stringify(record,null,2));await api('/api/session/'+session.id+'/interrupt','POST').catch(()=>{});throw error;}
