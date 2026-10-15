// Run against tests/fake-server.mjs over an HDC reverse port; never invokes an Agent.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
const hdc=resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/toolchains/hdc.exe');
const target=process.env.HDC_TARGET||'127.0.0.1:5555';const port=Number(process.env.OPENCODE_FIXTURE_PORT||4210);
assert.ok(Number.isInteger(port)&&port>1024&&port<65536);
const endpoint='http://127.0.0.1:'+port;mkdirSync('.test',{recursive:true});
const cmd=(...args)=>execFileSync(hdc,['-t',target,...args],{encoding:'utf8',timeout:25000});const pause=ms=>new Promise(r=>setTimeout(r,ms));
function flatten(n){return[n.attributes,...(n.children||[]).flatMap(flatten)];}
function layout(){cmd('shell','uitest dumpLayout -p /data/local/tmp/opencode-ui.json');cmd('file','recv','/data/local/tmp/opencode-ui.json',resolve('.test/'+(process.env.OPENCODE_UI_TAG||'')+'ui-layout.json'));return flatten(JSON.parse(readFileSync('.test/'+(process.env.OPENCODE_UI_TAG||'')+'ui-layout.json','utf8')));}
const bounds=n=>n.bounds.match(/-?\d+/g).map(Number);const find=q=>layout().find(n=>n.id===q||n.text===q);
async function click(q){await clickNode(find(q));}
async function clickNode(n){assert.ok(n,'UI control missing');const b=bounds(n);cmd('shell','uitest uiInput click '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));await pause(300);}
async function reveal(q){
 for(let i=0;i<16;i++){
  const all=layout(),root=bounds(all[0]),h=root[3],w=root[2],n=all.find(n=>n.id===q||n.text===q),b=n&&bounds(n);
  const list=all.find(n=>n.id==='conversation-list');const chatControl=/^(choice-|field-|interaction-|approval-)/.test(q)&&list;
  const scroll=all.find(n=>n.type==='Scroll');const viewport=chatControl?bounds(list):scroll?bounds(scroll):[0,230,w,h-50];
  if(n&&n.visible!=='false'&&b[1]>viewport[1]+30&&b[3]<viewport[3]-20&&b[3]-b[1]>(q.startsWith('choice-')?35:8))return n;
  const up=n?b[1]<=viewport[1]+30:i>=3;
  const from=Math.round(viewport[1]+(viewport[3]-viewport[1])*(up?.35:.7)),to=Math.round(viewport[1]+(viewport[3]-viewport[1])*(up?.7:.35));
  cmd('shell','uitest uiInput swipe '+Math.round(w*.5)+' '+from+' '+Math.round(w*.5)+' '+to+' 450');await pause(250);
 }
 throw new Error('Control not visible: '+q);
}
async function input(q,text){assert.ok(!text.includes("'"));await reveal(q);await click(q);cmd('shell','uitest uiInput keyEvent 2072 2017');cmd('shell','uitest uiInput keyEvent 2055');cmd('shell',"uitest uiInput text '"+text+"'");await pause(300);if(layout().some(n=>n.bundleName==='com.huawei.hmos.inputmethod')){cmd('shell','uitest uiInput keyEvent Back');await pause(300);}}
async function shot(name){cmd('shell','snapshot_display -f /data/local/tmp/opencode-ui.jpeg');cmd('file','recv','/data/local/tmp/opencode-ui.jpeg',resolve('.test/'+(process.env.OPENCODE_UI_TAG||'')+name+'.jpeg'));}
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const control=async path=>{const r=await fetch(endpoint+'/__test/'+path,{method:'POST'});assert.equal(r.status,200);return await r.json();};
const mode=process.argv[2];
if(mode==='home'){
 assert.ok(find('chat-input'));assert.ok(find('open-sidebar'));assert.ok(!find('server-url'));await shot('ui-home');console.log('PASS chat is the home screen; connection form is separate.');
}else if(mode==='sidebar'){
 if(!find('session-search'))await click('open-sidebar');assert.ok(find('session-search'));assert.ok(find('nav-connections'));assert.ok(find('nav-review'));await shot('ui-sidebar');await click('close-sidebar');console.log('PASS sidebar has history, projects, and management.');
}else if(mode==='thinking'){
 const test=await control('ui-phase?phase=thinking');writeFileSync('.test/ui-case.json',JSON.stringify(test));await pause(1800);assert.ok(find('reasoning-content-'+test.id));await shot('ui-thinking');
 await control('ui-phase?phase=answer');await pause(1800);assert.ok(!find('reasoning-content-'+test.id));assert.ok(find('reasoning-toggle-'+test.id));assert.ok(!find('tool-details'));assert.ok(find('tool-row-'+test.toolID));await shot('ui-answer');console.log('PASS thinking expands live, collapses at reasoning end, tools stay compact.');
}else if(mode==='details'){
 const test=JSON.parse(readFileSync('.test/ui-case.json','utf8'));
 await click('reasoning-toggle-'+test.id);assert.ok(find('reasoning-content-'+test.id));await click('reasoning-toggle-'+test.id);assert.ok(!find('reasoning-content-'+test.id));
 await click('tool-row-'+test.toolID);assert.ok(find('tool-request'));assert.ok(find('tool-response'));await shot('ui-tool-running');
 await control('ui-phase?phase=tool-done');await pause(1800);assert.ok((find('tool-response').text||'').includes('verified sample only'));await shot('ui-tool-completed');cmd('shell','uitest uiInput keyEvent Back');await pause(400);console.log('PASS independent reasoning toggle and live tool sheet updates.');
}else if(mode==='menu'){
 await click('open-menu');await click('menu-connections');await pause(700);await reveal('server-url');assert.ok(find('server-url'));await shot('ui-connections');await click('back-chat');assert.ok(find('chat-input'));console.log('PASS management navigation returns to the conversation.');
}else if(mode==='question'){
 if(!(await state()).forms.length){await input('chat-input','test question');await click('send-button');await pause(8500);}
 for(const id of ['choice-approach-minimal','choice-areas-chat','choice-areas-diff']){const item=await reveal(id);if(item.checked!=='true')await clickNode(item);}
 await input('field-note','native UI verified');await reveal('interaction-submit-frm_fixture');await click('interaction-submit-frm_fixture');await pause(800);const s=await state();assert.equal(s.forms.length,0);const reply=s.receipts.findLast(r=>r.path.includes('/form/')&&r.path.endsWith('/reply'));assert.deepEqual(reply.input.answer,{approach:'minimal',areas:['chat','diff'],note:'native UI verified'});await shot('ui-question');console.log('PASS native single/multiple/text answer values after UI refactor.');
}else if(mode==='reconnect-model-files'){
 await control('disconnect');let recovered=false;for(let i=0;i<20;i++){await pause(600);if((await state()).streams>0){recovered=true;break;}}assert.ok(recovered,'Native SSE did not reconnect');
 await click('open-menu');await click('menu-connections');await pause(600);assert.ok(find('实时连接'));await click('back-chat');
 await click('model-select');await click('模型切换测试');await pause(700);assert.equal((await state()).receipts.findLast(r=>r.path.endsWith('/model')).input.model.id,'fixture-second');
 await click('open-menu');await click('menu-review');await pause(600);assert.ok(layout().some(n=>(n.text||'').includes('+const platform = "HarmonyOS"')));await click('文件浏览');await click('README.md');await pause(700);assert.ok(layout().some(n=>(n.text||'').includes('用于验证文件读取')));await shot('ui-flow-files');await click('back-chat');console.log('PASS native SSE reconnect, exact model ID, working Diff and file browser.');
}else if(mode==='timeline'){
 await control('timeline');await click('open-menu');await click('menu-review');await pause(800);await click('review-timeline');await pause(1300);
 assert.ok(find('turn-turn_b'));assert.ok(find('turn-turn_a'));assert.ok(!find('turn-steer_b'));
 await reveal('+TASK_B_ONLY');assert.ok(find('+TASK_B_ONLY'));await reveal('turn-turn_a');await click('turn-turn_a');await pause(800);await reveal('+TASK_A_ONLY');assert.ok(find('+TASK_A_ONLY'));assert.ok(!find('+TASK_B_ONLY'));await shot('ui-timeline');
 await reveal('turn-turn_b');await click('turn-turn_b');await pause(700);await reveal('+TASK_B_ONLY');assert.ok(find('+TASK_B_ONLY'));assert.ok(!find('+TASK_A_ONLY'));await click('back-chat');console.log('PASS native task grouping and same-file Diff refresh in both directions.');
}else if(mode==='providers-live'){
 if(find('back-chat'))await click('back-chat');await click('open-menu');await click('menu-settings');await pause(1500);await click('providers-native');await click('quick-opencode');await reveal('provider-key');assert.ok(find('provider-key'));
 await reveal('providers-models');await click('providers-models');await input('model-catalog-search','mimo');assert.ok(layout().some(n=>(n.text||'').includes('opencode/mimo-v2.6-flash-free')));await shot('ui-real-mimo-catalog');
 await reveal('providers-custom');await click('providers-custom');await click('custom-new');await input('custom-id','mobile-ui-validation');await input('custom-name','Local format check');await input('custom-url','https://api.example.com/v1/chat/completions');await input('custom-models','test');await reveal('custom-save');await click('custom-save');await reveal('providers-custom');assert.ok(layout().some(n=>(n.text||'').includes('Base URL')));await shot('ui-real-custom-validation');await click('custom-new');await click('back-chat');console.log('PASS API24 real provider catalog, MiMo search, key form and local channel validation; no credential writes.');
}else if(mode==='providers'){
 await click('open-menu');await click('menu-settings');await pause(1000);assert.ok(find('providers-models'));await click('providers-native');await click('quick-deepseek');await reveal('provider-key');assert.ok(find('provider-key'));await shot('ui-provider-key');
 await reveal('providers-models');await click('providers-models');await pause(400);assert.ok(find('model-catalog-search'));assert.ok(layout().some(n=>n.text==='fixture/fixture-coder'));await shot('ui-model-catalog');
 await reveal('providers-custom');await click('providers-custom');await input('custom-id','mobile-test');await input('custom-name','Native UI');await input('custom-url','https://api.example.com/v1/chat/completions');await input('custom-models','one');await reveal('custom-save');await click('custom-save');await reveal('providers-custom');assert.ok(layout().some(n=>(n.text||'').includes('Base URL')));await shot('ui-provider-validation');
 await click('custom-new');assert.equal(find('custom-id').text,'');await click('back-chat');console.log('PASS native provider tabs, key form, model catalog and local validation.');
}else if(mode==='shot'){await shot(process.argv[3]||'ui-current');}
else if(mode==='click'){await click(process.argv[3]);}
else if(mode==='reveal'){await reveal(process.argv[3]);}
else if(mode==='input'){await input(process.argv[3],process.argv[4]);}
else if(mode==='texts'){console.log(layout().map(n=>n.text).filter(Boolean).join(' | '));}
else throw new Error('Use home, sidebar, thinking, details, menu, shot, click, texts');
