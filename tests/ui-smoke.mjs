// Run against tests/fake-server.mjs over an HDC reverse port; never invokes an Agent.
import assert from 'node:assert/strict';
import {find as nativeFind} from './native-driver.mjs';
import {execFileSync} from 'node:child_process';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
const hdc=resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/toolchains/hdc.exe');
const target=process.env.HDC_TARGET||'127.0.0.1:5555';const port=Number(process.env.OPENCODE_FIXTURE_PORT||4210);
assert.ok(Number.isInteger(port)&&port>1024&&port<65536);
const endpoint='http://127.0.0.1:'+port;mkdirSync('.test',{recursive:true});
const cmd=(...args)=>execFileSync(hdc,['-t',target,...args],{encoding:'utf8',timeout:25000});const pause=ms=>new Promise(r=>setTimeout(r,ms));
function flatten(n,parentId='',viewportBounds=''){
 const viewport=['Scroll','List'].includes(n.attributes.type)?n.attributes.bounds:viewportBounds;
 return[{...n.attributes,parentId,viewportBounds:viewport},...(n.children||[]).flatMap(c=>flatten(c,n.attributes.id,viewport))];
}
function layout(){cmd('shell','uitest dumpLayout -p /data/local/tmp/opencode-ui.json');cmd('file','recv','/data/local/tmp/opencode-ui.json',resolve('.test/'+(process.env.OPENCODE_UI_TAG||'')+'ui-layout.json'));return flatten(JSON.parse(readFileSync('.test/'+(process.env.OPENCODE_UI_TAG||'')+'ui-layout.json','utf8')));}
const aliases={'native-back':'__NavdestinationField__BackButton__Back__native-destination','open-menu':'__NavigationField__NavigationMenu__MenuItem2__native-navigation','menu-projects':'项目与会话','menu-review':'代码审查','menu-settings':'模型与接入','menu-connections':'服务器连接','menu-sync':'同步当前对话','appearance-menu':'外观'};
const bounds=n=>n.bounds.match(/-?\d+/g).map(Number);
const matches=(n,q)=>n.visible!=='false'&&(n.id===q||n.text===q||(aliases[q]&&(n.id===aliases[q]||n.text===aliases[q]))||(q==='back-chat'&&n.id==='native-destination')||(q==='open-sidebar'&&n.parentId==='native-sidebar-container'&&n.type==='Button'));
const find=q=>layout().find(n=>matches(n,q));
async function waitFor(q){const end=Date.now()+12000;while(Date.now()<end){const n=find(q);if(n)return n;await pause(250);}throw new Error('UI control did not appear: '+q);}
async function click(q){
 if(q==='back-chat'){
  assert.ok(find(q),'Native destination missing');cmd('shell','uitest uiInput keyEvent Back');
  const end=Date.now()+12000;
  while(Date.now()<end){
   await pause(350);const nodes=layout();
   if(!nodes.some(n=>matches(n,'back-chat'))&&nodes.some(n=>matches(n,'open-menu'))){await pause(500);return;}
  }
  throw new Error('Native navigation did not finish returning to chat');
 }
 await clickNode(await waitFor(q));
}
async function clickNode(n){assert.ok(n,'UI control missing');const b=bounds(n);cmd('shell','uitest uiInput click '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));await pause(300);}
async function reveal(q){
 for(let i=0;i<16;i++){
  const all=layout(),root=bounds(all[0]),h=root[3],w=root[2],n=all.find(n=>n.id===q||n.text===q),b=n&&bounds(n);
  const list=all.find(n=>n.id==='conversation-list'&&n.visible!=='false');const chatControl=/^(choice-|field-|interaction-|approval-|reasoning-|tool-row-)/.test(q)&&list;
  const scroll=all.find(n=>n.type==='Scroll'&&n.visible!=='false');
  const viewport=n?.viewportBounds?bounds({bounds:n.viewportBounds}):chatControl?bounds(list):n?[0,230,w,h-50]:scroll?bounds(scroll):[0,230,w,h-50];
  const tall=b&&b[3]-b[1]>=viewport[3]-viewport[1]-32;
  if(n&&n.visible!=='false'&&b[1]>=viewport[1]+(tall?0:8)&&b[3]<=viewport[3]+1&&b[3]-b[1]>(q.startsWith('choice-')?35:8))return n;
  const up=n?b[1]<=viewport[1]+30:i>=3;
  const from=Math.round(viewport[1]+(viewport[3]-viewport[1])*(up?.35:.7)),to=Math.round(viewport[1]+(viewport[3]-viewport[1])*(up?.7:.35));
  cmd('shell','uitest uiInput swipe '+Math.round(w*.5)+' '+from+' '+Math.round(w*.5)+' '+to+' 450');await pause(250);
 }
 throw new Error('Control not visible: '+q);
}
async function input(q,text){assert.ok(!text.includes("'"));await reveal(q);await click(q);await pause(900);cmd('shell','uitest uiInput keyEvent 2072 2017');await pause(150);cmd('shell','uitest uiInput keyEvent 2055');await pause(150);cmd('shell',"uitest uiInput text '"+text+"'");await pause(300);if(nativeFind('SkinBgContent')){cmd('shell','uitest uiInput keyEvent Back');await pause(300);}}
async function shot(name){cmd('shell','snapshot_display -f /data/local/tmp/opencode-ui.jpeg');cmd('file','recv','/data/local/tmp/opencode-ui.jpeg',resolve('.test/'+(process.env.OPENCODE_UI_TAG||'')+name+'.jpeg'));}
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const control=async path=>{const r=await fetch(endpoint+'/__test/'+path,{method:'POST'});assert.equal(r.status,200);return await r.json();};
const mode=process.argv[2];
if(mode==='home'){
 assert.ok(find('chat-input'));assert.ok(find('open-sidebar'));assert.ok(!find('server-url'));await shot('ui-home');console.log('PASS chat is the home screen; connection form is separate.');
}else if(mode==='sidebar'){
 if(!find('session-search'))await click('open-sidebar');await waitFor('session-search');assert.ok(find('session-search'));assert.ok(find('nav-connections'));assert.ok(find('nav-review'));await shot('ui-sidebar');await click('close-sidebar');await click('open-sidebar');await waitFor('session-search');cmd('shell','uitest uiInput keyEvent Back');await pause(650);assert.ok(find('open-menu'));assert.ok(!find('session-search'));console.log('PASS native sidebar history, management, close button and system-back dismissal.');
}else if(mode==='thinking'){
 const test=await control('ui-phase?phase=thinking');writeFileSync('.test/ui-case.json',JSON.stringify(test));await pause(1800);assert.ok(find('reasoning-content-'+test.id));await shot('ui-thinking');
 await control('ui-phase?phase=answer');await pause(1800);assert.ok(!find('reasoning-content-'+test.id));assert.ok(find('reasoning-toggle-'+test.id));assert.ok(!find('tool-details'));assert.ok(find('tool-row-'+test.toolID));await shot('ui-answer');console.log('PASS thinking expands live, collapses at reasoning end, tools stay compact.');
}else if(mode==='details'){
 const test=JSON.parse(readFileSync('.test/ui-case.json','utf8'));
 await click('reasoning-toggle-'+test.id);assert.ok(find('reasoning-content-'+test.id));await click('reasoning-toggle-'+test.id);assert.ok(!find('reasoning-content-'+test.id));
 await click('tool-row-'+test.toolID);assert.ok(find('tool-request'));assert.ok(find('tool-response'));await shot('ui-tool-running');
 await control('ui-phase?phase=tool-done');await pause(1800);assert.ok((find('tool-response').text||'').includes('verified sample only'));await shot('ui-tool-completed');cmd('shell','uitest uiInput keyEvent Back');await pause(400);console.log('PASS independent reasoning toggle and live tool sheet updates.');
}else if(mode==='menu'){
 await click('open-menu');await click('menu-connections');await pause(700);await reveal('server-url');assert.ok(find('server-url'));assert.ok(!find('open-sidebar'),'Sidebar control covers destination back button');await shot('ui-connections');await click('native-back');await pause(1500);assert.ok(find('chat-input'));console.log('PASS management navigation returns with the native back button unobstructed.');
}else if(mode==='question'){
 if(!(await state()).forms.length){await input('chat-input','test question');await click('send-button');await pause(8500);}
 for(const id of ['choice-approach-minimal','choice-areas-chat','choice-areas-diff']){const item=await reveal(id);if(item.checked!=='true')await clickNode(item);}
 await input('field-note','native UI verified');await reveal('interaction-submit-frm_fixture');await click('interaction-submit-frm_fixture');await pause(800);const s=await state();assert.equal(s.forms.length,0);const reply=s.receipts.findLast(r=>r.path.includes('/form/')&&r.path.endsWith('/reply'));assert.deepEqual(reply.input.answer,{approach:'minimal',areas:['chat','diff'],note:'native UI verified'});await shot('ui-question');console.log('PASS native single/multiple/text answer values after UI refactor.');
}else if(mode==='reconnect-model-files'){
 await control('disconnect');let recovered=false;for(let i=0;i<20;i++){await pause(600);if((await state()).streams>0){recovered=true;break;}}assert.ok(recovered,'Native SSE did not reconnect');
 await click('open-menu');await click('menu-connections');await pause(600);assert.ok(find('实时连接'));await click('back-chat');
 await click('model-select');await click('模型切换测试');await pause(700);assert.equal((await state()).receipts.findLast(r=>r.path.endsWith('/model')).input.model.id,'fixture-second');
 await click('open-menu');await click('menu-review');await pause(600);await click('Git Diff');assert.ok(layout().some(n=>(n.text||'').includes('+const platform = "HarmonyOS"')));await click('文件浏览');await click('README.md');await pause(700);assert.ok(layout().some(n=>(n.text||'').includes('用于验证文件读取')));await shot('ui-flow-files');await click('back-chat');console.log('PASS native SSE reconnect, exact model ID, working Diff and file browser.');
}else if(mode==='timeline'){
 await control('timeline');await click('open-menu');await click('menu-review');await pause(800);await click('会话修改');await click('刷新');await pause(1300);
 assert.ok(find('turn-turn_b'));assert.ok(find('turn-turn_a'));assert.ok(!find('turn-steer_b'));
 await reveal('+TASK_B_ONLY');assert.ok(find('+TASK_B_ONLY'));await reveal('turn-turn_a');await click('turn-turn_a');await pause(800);await reveal('+TASK_A_ONLY');assert.ok(find('+TASK_A_ONLY'));assert.ok(!find('+TASK_B_ONLY'));await shot('ui-timeline');
 await reveal('turn-turn_b');await click('turn-turn_b');await pause(700);await reveal('+TASK_B_ONLY');assert.ok(find('+TASK_B_ONLY'));assert.ok(!find('+TASK_A_ONLY'));await click('back-chat');console.log('PASS native task grouping and same-file Diff refresh in both directions.');
}else if(mode==='providers-live'){
 if(find('back-chat'))await click('back-chat');await click('open-menu');await click('menu-settings');await pause(1500);await click('提供商');await click('quick-opencode');await reveal('provider-key');assert.ok(find('provider-key'));
 await reveal('模型目录');await click('模型目录');await input('model-catalog-search','mimo');assert.ok(layout().some(n=>(n.text||'').includes('opencode/mimo-v2.6-flash-free')));await shot('ui-real-mimo-catalog');
 await reveal('兼容渠道');await click('兼容渠道');await click('custom-new');await input('custom-id','mobile-ui-validation');await input('custom-name','Local format check');await input('custom-url','https://api.example.com/v1/chat/completions');await input('custom-models','test');await reveal('custom-save');await click('custom-save');await reveal('兼容渠道');assert.ok(layout().some(n=>(n.text||'').includes('Base URL')));await shot('ui-real-custom-validation');await click('custom-new');await click('back-chat');console.log('PASS API24 real provider catalog, MiMo search, key form and local channel validation; no credential writes.');
}else if(mode==='providers'){
 await click('open-menu');await click('menu-settings');await pause(1000);assert.ok(find('模型目录'));await click('提供商');await click('quick-deepseek');await reveal('provider-key');assert.ok(find('provider-key'));await shot('ui-provider-key');
 await reveal('模型目录');await click('模型目录');await pause(400);assert.ok(find('model-catalog-search'));assert.ok(layout().some(n=>n.text==='fixture/fixture-coder'));await shot('ui-model-catalog');
 await reveal('兼容渠道');await click('兼容渠道');await input('custom-id','mobile-test');await input('custom-name','Native UI');await input('custom-url','https://api.example.com/v1/chat/completions');await input('custom-models','one');await reveal('custom-save');await click('custom-save');await reveal('兼容渠道');assert.ok(layout().some(n=>(n.text||'').includes('Base URL')));await shot('ui-provider-validation');
 await click('custom-new');assert.equal(find('custom-id').text,'');await click('back-chat');console.log('PASS native provider tabs, key form, model catalog and local validation.');
}else if(mode==='native-new'){
 const before=(await state()).receipts.filter(r=>r.path==='/api/session'&&r.method==='POST').length;
 await click('__NavigationField__NavigationMenu__MenuItem1__native-navigation');await pause(1000);assert.ok(find('chat-input'));
 assert.equal((await state()).receipts.filter(r=>r.path==='/api/session'&&r.method==='POST').length,before+1);console.log('PASS native title menu creates exactly one conversation.');
 }else if(mode==='appearance'){
 const all=layout();const ids=['open-sidebar','model-select','__NavigationField__NavigationMenu__MenuItem1__native-navigation','__NavigationField__NavigationMenu__MenuItem2__native-navigation'];
 const titleControls=ids.map(q=>all.find(n=>matches(n,q))).filter(Boolean).map(bounds).sort((a,b)=>a[0]-b[0]);
 for(let i=1;i<titleControls.length;i++)assert.ok(titleControls[i-1][2]<=titleControls[i][0],'Title controls overlap');
 for(const theme of ['dark','light','system']){
  await click('open-menu');await click('appearance-menu');await click({dark:'深色',light:'浅色',system:'跟随系统'}[theme]);await pause(1200);await shot('native-'+theme);await click('back-chat');
  if(theme==='dark'){
   cmd('shell','aa force-stop com.example.opencode_harmony');await pause(800);cmd('shell','aa start -b com.example.opencode_harmony -m entry -a EntryAbility');await pause(4500);
   await click('open-menu');await click('appearance-menu');assert.ok(find('当前外观：深色'),'Appearance did not persist');await click('back-chat');
   await click('open-menu');await click('menu-review');await pause(700);assert.ok(find('review-segments'));await click('会话修改');await pause(700);await shot('native-dark-review');await click('back-chat');
  }
 }
 console.log('PASS non-overlapping native title, all app themes, persisted dark mode, review segments and native back.');
 await click('chat-input');await pause(1300);const keyboardLayout=layout();
 const keyboard=keyboardLayout.filter(n=>n.bundleName==='com.huawei.hmos.inputmethod'&&n.type==='WindowScene').map(bounds).find(b=>b[3]-b[1]>300);
 if(keyboard){const input=keyboardLayout.find(n=>n.id==='chat-input'),send=keyboardLayout.find(n=>n.id==='send-button');assert.ok(input&&send);assert.ok(bounds(input)[3]<=keyboard[1]&&bounds(send)[3]<=keyboard[1],'Composer overlaps keyboard');await shot('native-keyboard');cmd('shell','uitest uiInput keyEvent Back');await pause(450);console.log('PASS composer remains above visible soft keyboard.');}
 else console.log('SKIP soft keyboard avoidance: no soft keyboard window is shown by this device during UI automation.');
}else if(mode==='shot'){await shot(process.argv[3]||'ui-current');}
else if(mode==='click'){await click(process.argv[3]);}
else if(mode==='reveal'){await reveal(process.argv[3]);}
else if(mode==='input'){await input(process.argv[3],process.argv[4]);}
else if(mode==='texts'){console.log(layout().map(n=>n.text).filter(Boolean).join(' | '));}
else throw new Error('Use home, sidebar, thinking, details, menu, shot, click, texts');
