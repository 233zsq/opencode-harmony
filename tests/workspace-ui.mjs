// Uses workspace-server.mjs only. All decisions and prompts go to a loopback fixture.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {tap,find,input,reveal,wait,menu,back,pause,cmd,shot,layout} from './native-driver.mjs';
const endpoint='http://127.0.0.1:'+(process.env.OPENCODE_FIXTURE_PORT||4212);
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const control=async(path,body={})=>{const r=await fetch(endpoint+'/__test/'+path,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(body)});assert.equal(r.status,200);};
const mode=process.argv[2];
assert.equal(find('model-select')?.text,'Fixture vision','Select the loopback workspace fixture before running native acceptance; refusing to act on a real server.');
async function openA(){await menu('项目与会话');await tap('Harmony Fixture');await pause(700);await tap(await reveal('session-s_a'));await wait('chat-input');}
async function pending(kind,id){await menu('待办中心');await tap('pending-refresh');await tap(await reveal('pending-open-'+kind+'-'+id));await wait('chat-input');}
if(mode==='attachments'){
 await openA();const cards=layout().filter(n=>n.id?.startsWith('attachment-remove-att_'));assert.equal(cards.length,2,'Select the synthetic image and text in the system file picker first');
 const baseline=(await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length;await input('chat-input','');await tap('send-button');await pause(1500);
 const posts=(await state()).receipts.filter(r=>r.path.endsWith('/prompt'));assert.equal(posts.length,baseline+1);const files=posts.at(-1).input.files;assert.equal(files.length,2);assert.ok(files.some(f=>f.uri.startsWith('data:image/jpeg;base64,')));const text=files.find(f=>f.name==='harmony-sample.txt');assert.ok(Buffer.from(text.uri.split(',')[1],'base64').toString().includes('中文与 emoji 🌿'));assert.ok(files.every(f=>!f.uri.startsWith('file:')));assert.ok(!layout().some(n=>n.id?.startsWith('attachment-remove-att_')));await shot('workspace-attachments-sent');console.log('PASS native image compression, UTF-8 file selection, draft restoration and one exact inline attachment request.');
}else if(mode==='bookmarks'){
 await menu('项目与会话');await tap('Harmony Fixture');await tap(await reveal('session-actions-s_a'));await input('session-name','Workspace A renamed');await tap('session-rename');await pause(900);
 assert.equal((await state()).sessions.find(s=>s.id==='s_a').title,'Workspace A renamed');await tap('session-actions-s_a');await tap('session-pin');await wait('取消置顶');await tap('session-archive');await wait('移回最近会话');await back();await tap('sessions-archived');await wait('session-s_a');await shot('workspace-archived');
 cmd('shell','aa force-stop com.example.opencode_harmony');await pause(600);cmd('shell','aa start -b com.example.opencode_harmony -m entry -a EntryAbility');await pause(1800);cmd('shell','aa start -b com.example.opencode_harmony -m entry -a EntryAbility');await pause(1500);
 if(find('native-destination'))await back();
 await tap('open-sidebar');await tap('history-filter');await tap('history-archived');await wait('sidebar-session-s_a');await tap('session-actions-s_a');await wait('取消置顶');await wait('移回最近会话');await tap('session-archive');await wait('归档到本机列表');await tap('session-pin');await wait('置顶会话');await back();await tap('history-filter');await tap('history-recent');await tap('sidebar-session-s_a');await shot('workspace-bookmarks-restored');console.log('PASS native rename, pin/archive persistence across restart, and restore to recents.');
}else if(mode==='questions-pending'){
 const attachmentCount=layout().filter(n=>n.id?.startsWith('attachment-remove-att_')).length;
 await openA();for(const id of ['choice-choice-minimal','choice-areas-chat','choice-areas-diff']){const n=await reveal(id);if(n.checked!=='true')await tap(n);}
 await input('field-note','draft survives project switches');await input('chat-input','Unsent A draft');
 await pending('permission','p_b');await reveal('approval-file-sample.ts');assert.ok(find('approval-file-sample.ts'));assert.ok(!((await state()).receipts.some(r=>r.path.endsWith('/permission/p_b/reply'))));
 await pending('form','q_a');assert.equal(find('chat-input').text,'Unsent A draft');if(attachmentCount)assert.equal(layout().filter(n=>n.id?.startsWith('attachment-remove-att_')).length,attachmentCount);await reveal('field-note');assert.equal(find('field-note').text,'draft survives project switches');for(const id of ['choice-choice-minimal','choice-areas-chat','choice-areas-diff']){const n=await reveal(id);assert.equal(n.checked,'true');}
 await tap(await reveal('interaction-submit-q_a'));await pause(900);const answer=(await state()).receipts.findLast(r=>r.path.endsWith('/form/q_a/reply')).input.answer;assert.deepEqual(answer,{choice:'minimal',areas:['chat','diff'],note:'draft survives project switches'});await input('chat-input','');
 await pending('permission','p_b');await tap(await reveal('interaction-submit-p_b'));await pause(1000);const posts=(await state()).receipts.filter(r=>r.path.endsWith('/permission/p_b/reply'));assert.equal(posts.length,1);assert.equal(posts[0].input.decision,'once');assert.equal(new URLSearchParams(posts[0].query).get('location[directory]'),'/workspace/second-fixture');await shot('workspace-pending-complete');console.log('PASS native cross-project Question/approval routing, answer and chat draft restoration, exact answer values and one scoped approval.');
}else if(mode==='recovery'){
 await openA();const baseline=(await state()).prompts.length,postBaseline=(await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length;await control('send-lost');await input('chat-input','Native recovery fixture');await tap('send-button');await wait('verify-send');assert.equal(find('chat-input').enabled,'false');const before=await state();assert.equal(before.prompts.length,baseline+1);await control('reveal-send');await tap('verify-send');await pause(1400);assert.equal(find('chat-input').text,'');assert.ok(!find('verify-send'));const after=await state();assert.equal(after.receipts.filter(r=>r.path.endsWith('/prompt')).length,postBaseline+1);
 await control('disconnect');let online=false;for(let i=0;i<20;i++){await pause(500);if((await state()).streams){online=true;break;}}assert.ok(online,'SSE did not reconnect');
 await control('running');await menu('同步当前对话');await wait('stop-button');cmd('shell','uitest uiInput keyEvent Home');await pause(1000);cmd('shell','aa start -b com.example.opencode_harmony -m entry -a EntryAbility');await wait('stop-button');await tap('stop-button');await pause(800);assert.equal((await state()).receipts.filter(r=>r.path.endsWith('/interrupt')).length,1);await shot('workspace-recovery');console.log('PASS native unknown-send recovery without repost, SSE reconnect, foreground task recovery and single stop.');
 }else if(mode==='copy'){
 const promptID=(await state()).prompts.at(-1);assert.ok(promptID,'Run the recovery scenario first');await openA();
 if(find('SkinBgContent'))await back();
 for(let i=0;i<8&&!find('copy-message-reply_'+promptID);i++){cmd('shell','uitest uiInput swipe 640 2100 640 800 6000');await pause(200);}
 await tap(await reveal('copy-message-reply_'+promptID));await input('chat-input','');await tap('chat-input');cmd('shell','uitest uiInput keyEvent 2072 2038');await pause(600);
 assert.equal(find('chat-input').text,'Synthetic reply accepted. No model was called.');await input('chat-input','');console.log('PASS native reply copied through system clipboard and pasted exactly; test draft cleared.');
}else if(mode==='performance'){
 if(find('SkinBgContent'))await back();await control('load');const start=Date.now();await openA();await wait('copy-message-long_00999');const syncMs=Date.now()-start;
 for(let page=0;page<10;page++){
  for(let i=0;i<5&&!find('older-messages');i++){cmd('shell','uitest uiInput swipe 640 850 640 2200 18000');await pause(250);}
  await tap(await reveal('older-messages'));await pause(250);console.log('Loaded native earlier page '+(page+1));
 }
 const reads=(await state()).reads.filter(r=>r.id==='s_a'&&r.cursor);assert.ok(new Set(reads.map(r=>r.cursor)).size>=10,'Native earlier-message pages did not load');
 const swipes=[];for(let i=0;i<5;i++){const t=Date.now();cmd('shell','uitest uiInput swipe 640 900 640 1700 6000');const nodes=layout();assert.ok(find('chat-input',nodes));swipes.push(Date.now()-t);}await shot('workspace-long-history');
 const diffStart=Date.now();await menu('代码审查');await tap(await reveal('diff-more-sample.ts'));await pause(450);const more=layout().find(n=>n.id==='diff-more-sample.ts');assert.ok(more?.text.includes('240/1500'),'Diff did not expand in bounded batches');const diffMs=Date.now()-diffStart;await shot('workspace-large-diff');await back();
 const pid=cmd('shell','pidof com.example.opencode_harmony').trim().split(/\s+/)[0];assert.match(pid,/^\d+$/);const memory=cmd('shell','hidumper --mem '+pid);assert.match(memory,/PSS|Pss|TOTAL|Total/);writeFileSync('.test/workspace-device-memory.txt',memory);
 writeFileSync('.test/workspace-device-performance.json',JSON.stringify({device:process.env.HDC_TARGET||'127.0.0.1:5555',openHistoryRoundTripMs:syncMs,distinctEarlierCursors:new Set(reads.map(r=>r.cursor)).size,scrollRoundTripMs:swipes,diffExpandRoundTripMs:diffMs,scope:'1000 synthetic messages, 10 earlier-page reads and bounded 300-message window; 10000-line source Diff previews 1500 and initially renders 120. HDC round trips are not frame times.'},null,2));console.log('PASS native paged long history, bounded Diff expansion, scrolling and memory capture; timings include UI automation.');
}else if(mode==='large-attachments'){
 await control('large-attachments');await openA();await wait('message-user-payload_9');const reads=(await state()).reads.filter(r=>r.id==='s_a');assert.ok(reads.some(r=>r.limit==='30'));assert.ok(reads.some(r=>r.limit==='1'));await shot('workspace-large-attachment-history');console.log('PASS native oversized attachment history automatically recovers through single-message pages.');
}else throw new Error('Use bookmarks, questions-pending, recovery, copy, performance');
