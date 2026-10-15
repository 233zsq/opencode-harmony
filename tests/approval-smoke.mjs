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
function layout(){cmd('shell','uitest dumpLayout -p /data/local/tmp/opencode-approval.json');cmd('file','recv','/data/local/tmp/opencode-approval.json',resolve('.test/approval-layout.json'));return flatten(JSON.parse(readFileSync('.test/approval-layout.json','utf8')));}
const bounds=n=>n.bounds.match(/-?\d+/g).map(Number);const find=q=>layout().find(n=>n.id===q||n.text===q);
async function click(q){await clickNode(find(q));}
async function clickNode(n){assert.ok(n,'UI control missing');const b=bounds(n);cmd('shell','uitest uiInput click '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));await pause(300);}
async function reveal(q){for(let i=0;i<14;i++){const all=layout(),h=bounds(all[0])[3],w=bounds(all[0])[2],n=all.find(n=>n.id===q||n.text===q),b=n&&bounds(n);if(n&&n.visible!=='false'&&b[1]>300&&b[3]<h-(/server-|connect-button|dedicated-trust|allow-http/.test(q)?150:480))return;const up=n&&b[1]<300;cmd('shell','uitest uiInput swipe '+Math.round(w*.5)+' '+Math.round(h*(up?.4:.7))+' '+Math.round(w*.5)+' '+Math.round(h*(up?.7:.4))+' 450');await pause(250);}throw new Error('Control not visible: '+q);}
async function input(q,text){assert.ok(!text.includes("'"));await reveal(q);await click(q);cmd('shell','uitest uiInput keyEvent 2072 2017');cmd('shell','uitest uiInput keyEvent 2055');cmd('shell',"uitest uiInput text '"+text+"'");await pause(300);if(layout().some(n=>n.bundleName==='com.huawei.hmos.inputmethod')){cmd('shell','uitest uiInput keyEvent Back');await pause(300);}}
async function shot(name){cmd('shell','snapshot_display -f /data/local/tmp/opencode-approval.jpeg');cmd('file','recv','/data/local/tmp/opencode-approval.jpeg',resolve('.test/'+name+'.jpeg'));}
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const control=async path=>{const r=await fetch(endpoint+'/__test/'+path,{method:'POST'});assert.equal(r.status,200);};
const mode=process.argv[2];
if(mode==='connect'){
 if(!find('server-url')){await click('open-menu');await click('menu-connections');}await input('server-url',endpoint);await input('server-password','local-test');
 await reveal('dedicated-trust');if(find('dedicated-trust').checked==='true')await click('dedicated-trust');
 await reveal('allow-http');if(find('allow-http').checked!=='true')await click('allow-http');
 await reveal('connect-button');await click('connect-button');await pause(1500);
 await click('open-menu');await click('menu-projects');await pause(500);await click('Harmony Fixture');await pause(900);await click('new-session');await pause(1100);assert.ok(find('chat-input'));console.log('PASS native fixture session connected.');
}else if(mode==='preview'){
 const before=await state();writeFileSync('.test/approval-fixture-baseline.json',JSON.stringify({writes:before.receipts.filter(r=>r.path.includes('/permission/')&&r.path.endsWith('/reply')).length}));await control('approval');await pause(1800);await reveal('approval-file-src/example.ets');
 await reveal('+const platform = "HarmonyOS NEXT";');assert.ok(layout().some(n=>n.text==='+const platform = "HarmonyOS NEXT";'));await reveal('approval-file-src/example.ets');await click('approval-file-src/example.ets');
 assert.ok(!layout().some(n=>n.text==='+const platform = "HarmonyOS NEXT";'));await click('approval-file-src/example.ets');
 await reveal('+const platform = "HarmonyOS NEXT";');assert.ok(layout().some(n=>n.text==='+const platform = "HarmonyOS NEXT";'));await shot('approval-fixture-preview');console.log('PASS native pending patch, file expand and collapse.');
}else if(mode==='failure'){
 await control('permission-read-failure?enabled=1');await pause(6500);await reveal('interaction-submit-per_fixture');
 assert.ok(find('interaction-card-per_fixture'));assert.equal(find('interaction-submit-per_fixture').enabled,'false');assert.equal(find('interaction-reject-per_fixture').enabled,'true');assert.ok(find('permission-sync-error'));await shot('approval-fixture-failure');console.log('PASS read failure retains card, disables approve, and permits reject.');
}else if(mode==='recover'){
 await reveal('permission-retry');const retry=find('permission-retry');await control('permission-read-failure?enabled=0');await clickNode(retry);await pause(900);
 assert.ok(!find('permission-sync-error'));assert.equal(find('interaction-submit-per_fixture').enabled,'true');const s=await state();assert.equal(s.permissions.length,1);assert.equal(s.receipts.filter(r=>r.path.includes('/permission/')&&r.path.endsWith('/reply')).length,JSON.parse(readFileSync('.test/approval-fixture-baseline.json','utf8')).writes);await shot('approval-fixture-recovered');console.log('PASS native manual refresh restores approval without posting a decision.');
}else if(mode==='approve'){
 await reveal('interaction-submit-per_fixture');await click('interaction-submit-per_fixture');await pause(1100);
 const s=await state(),writes=s.receipts.filter(r=>r.path.includes('/permission/')&&r.path.endsWith('/reply'));assert.equal(s.permissions.length,0);assert.equal(writes.length,JSON.parse(readFileSync('.test/approval-fixture-baseline.json','utf8')).writes+1);assert.equal(writes.at(-1).input.decision,'once');assert.equal(new URLSearchParams(writes.at(-1).query).get('location[directory]'),'/workspace/harmony-fixture');await shot('approval-fixture-approved');console.log('PASS native once approval is scoped and posted exactly once.');
}else throw new Error('Use connect, preview, failure, recover, or approve');