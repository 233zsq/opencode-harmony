// Loopback-only native reproduction of provider row/form/submit identity.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {tap,wait,find,reveal,menu,input,back,layout,shot,pause,bounds} from './native-driver.mjs';
const endpoint='http://127.0.0.1:4210';
if(find('SkinBgContent'))await back();
if(!find('model-select'))await back();
assert.equal(find('model-select')?.text,'本机测试模型','Refusing to edit credentials outside the local fixture.');
const baseline=(await(await fetch(endpoint+'/__test/state')).json()).receipts.filter(r=>r.path.includes('/integration/')&&r.path.endsWith('/connect/key')).length;
const roots=()=>JSON.parse(readFileSync('.test/complete-ui.json','utf8'));
function authCard(){
 let result;const visit=n=>{if(n.children?.some(c=>c.attributes.id==='provider-label')&&n.attributes.visible!=='false'&&bounds(n.attributes)[0]>=0)result=n;for(const c of n.children||[])visit(c);};
 const all=roots();for(const n of Array.isArray(all)?all:[all])visit(n);return result;
}
const dismissKeyboard=async()=>{if(find('SkinBgContent'))await back();};
await menu('项目与会话');await tap('Harmony Fixture');await pause(650);await tap(await reveal('session-ses_fixture'));await wait('chat-input');
await menu('模型与接入');await tap('quick-deepseek');
if(process.argv[2]!=='repro'){await tap(await reveal('auth-method-key'));await input('provider-key','fixture-deepseek-key');await dismissKeyboard();}
await input('provider-search','Xiao');await dismissKeyboard();await tap(await reveal('provider-xiaomi'));layout();
const card=authCard();assert.ok(card,'Provider configuration card missing');const title=card.children.find(c=>c.attributes.type==='Text')?.attributes.text;
await shot('provider-selection-reproduction');assert.equal(title,'Xiaomi','Selected Xiaomi row must show Xiaomi authentication form, never DeepSeek.');
assert.ok(!find('provider-key')||find('provider-key').text==='','Previous provider key must be cleared');
if(process.argv[2]==='repro'){console.log('PASS minimal provider form reproduction.');process.exit(0);}
await tap(await reveal('auth-method-key'));await input('provider-label','Fixture Xiaomi');await input('provider-key','fixture-xiaomi-key');await dismissKeyboard();await tap(await reveal('provider-connect'));await pause(800);
const receipts=(await(await fetch(endpoint+'/__test/state')).json()).receipts.filter(r=>r.path.includes('/integration/')&&r.path.endsWith('/connect/key'));
assert.equal(receipts.length,baseline+1);assert.equal(receipts.at(-1).path,'/api/integration/xiaomi/connect/key');assert.equal(receipts.at(-1).input.key,'fixture-xiaomi-key');await shot('provider-selection-fixed');console.log('PASS Xiaomi selection, visible form, cleared previous key and exact one Xiaomi credential request.');
