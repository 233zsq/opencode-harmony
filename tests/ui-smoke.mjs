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
async function reveal(q){for(let i=0;i<14;i++){const all=layout(),h=bounds(all[0])[3],w=bounds(all[0])[2],n=all.find(n=>n.id===q||n.text===q),b=n&&bounds(n);if(n&&n.visible!=='false'&&b[1]>300&&b[3]<h-150)return;const up=n&&b[1]<300;cmd('shell','uitest uiInput swipe '+Math.round(w*.5)+' '+Math.round(h*(up?.4:.7))+' '+Math.round(w*.5)+' '+Math.round(h*(up?.7:.4))+' 450');await pause(250);}throw new Error('Control not visible: '+q);}
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
}else if(mode==='shot'){await shot(process.argv[3]||'ui-current');}
else if(mode==='click'){await click(process.argv[3]);}
else if(mode==='input'){await input(process.argv[3],process.argv[4]);}
else if(mode==='texts'){console.log(layout().map(n=>n.text).filter(Boolean).join(' | '));}
else throw new Error('Use home, sidebar, thinking, details, menu, shot, click, texts');
