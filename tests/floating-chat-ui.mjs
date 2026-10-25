// Native floating chat acceptance. Writes are limited to the selected local fixture.
import assert from 'node:assert/strict';
import {tap,find,wait,back,pause,input,layout,bounds,cmd,shot,menu,dismissKeyboard,keyboardVisible} from './native-driver.mjs';
const endpoint='http://127.0.0.1:'+(process.env.OPENCODE_FIXTURE_PORT||4210), density=Number(process.env.UI_DENSITY||3.5);
await wait('本机测试模型',45000);assert.equal(find('model-select')?.text,'本机测试模型','Select the loopback fixture first');
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const prompts=(await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length;
let lastTool='';
const phase=async name=>{const response=await fetch(endpoint+'/__test/ui-phase?phase='+name,{method:'POST'});assert.equal(response.status,200);const event=await response.json();if(name==='tool-done')lastTool=event.toolID;await pause(1700);};
function geometry(){
 const nodes=layout(),get=id=>{const n=find(id,nodes);assert.ok(n,id+' must be visible');return bounds(n);};
 const stage=get('chat-stage'),list=get('conversation-list'),heading=get('chat-heading'),title=get('conversation-title'),agent=get('agent-select'),composer=get('chat-composer'),field=get('composer-field'),status=get('chat-status'),add=get('attachment-add'),send=get(find('stop-button',nodes)?'stop-button':'send-button'),draft=get('chat-input');
 assert.ok(Math.abs(list[1]-stage[1])<=2&&Math.abs(list[3]-stage[3])<=2,'The stream must extend behind both floating surfaces');
 assert.ok(title[1]>=list[1]&&title[3]<=heading[3]&&title[2]<agent[0],'Title and Agent capsules must fit without overlap');
 assert.ok(Math.abs(composer[3]-stage[3])<=2,'Composer must stay anchored at the bottom of the chat');
 assert.ok(status[1]>=field[3]-1&&status[3]<=stage[3]+1,'Status belongs below the input, in its lower inset');
 assert.ok((composer[3]-field[3])/density<=15,'The readable status footer must remain within its compact 14vp inset');
 assert.ok(Math.abs((add[1]+add[3]-send[1]-send[3])/2)<=density,'Plus and send buttons must share a vertical center');
 assert.ok((draft[3]-draft[1])/density<=48,'Empty input must remain compact');
 return{stage,list,field,status,heading};
}
await phase('thinking');assert.match(find('chat-status')?.text||'',/生成/);const working=geometry();
await phase('answer');await phase('tool-done');assert.doesNotMatch(find('chat-status')?.text||'',/生成/);const idle=geometry();
assert.ok(Math.abs(idle.field[3]-working.field[3])<=density,'Changing task state must not lift the composer');
for(let i=0;i<3;i++){await phase('thinking');await phase('answer');await phase('tool-done');}
await wait('tool-row-'+lastTool);assert.ok(bounds(find('tool-row-'+lastTool))[3]<=bounds(find('composer-field'))[1],'The final tool result must remain fully readable above the composer');
await shot('floating-chat-dark');
let {list}=geometry();const x=Math.round((list[0]+list[2])/2);
cmd('shell','uitest uiInput swipe '+x+' '+Math.round(list[1]+220*density)+' '+x+' '+Math.round(list[3]-130*density)+' 450');await pause(650);
await wait('jump-latest');const jump=bounds(find('jump-latest')),field=bounds(find('composer-field'));assert.ok(jump[3]<field[1]&&jump[1]>list[1],'Latest action floats above input over the stream');
await shot('floating-chat-scrolled');await tap('jump-latest');await pause(700);assert.ok(!find('jump-latest'),'Returning to latest should clear the scroll action');
await tap('attachment-add');await wait('attachment-photos');await wait('attachment-files');await shot('floating-attachment-menu');await back();assert.ok(!find('attachment-photos'));assert.ok(find('chat-input'));
await input('chat-input','FLOATING_DRAFT',{keepKeyboard:true});assert.equal(find('chat-input').text,'FLOATING_DRAFT');
for(let i=0;i<6&&!keyboardVisible();i++)await pause(300);
if(keyboardVisible()){
 const nodes=layout(),skin=nodes.find(n=>n.visible!=='false'&&n.id==='SkinBgContent');
 // API26 WindowScene roots can cover the entire display; the skin bounds describe the actual keyboard surface.
 const keyboard=skin?bounds(skin):nodes.filter(n=>n.visible!=='false'&&/^keyboard(?:Panel)?[0-9]+$/.test(n.id||'')&&bounds(n)[1]>0&&bounds(n)[3]-bounds(n)[1]>200).map(bounds).sort((a,b)=>a[1]-b[1])[0];
 if(keyboard){assert.ok(bounds(find('composer-field',nodes))[3]<=keyboard[1]+2,'IME must leave the composer above its surface');console.log('PASS composer remains above the visible keyboard surface');}
 else console.log('SKIP keyboard occlusion geometry: only fullscreen keyboard scene roots are available');await shot('floating-chat-keyboard');
}else console.log('SKIP soft-keyboard geometry: emulator exposes no visible IME window after the focused draft input');
await dismissKeyboard();await input('chat-input','');await pause(600);geometry();console.log('PASS floating chat geometry, state changes, latest action, attachment menu and editable draft');
await tap('open-sidebar');await wait('sidebar-workspace');await tap('sidebar-workspace');await wait('workspace-picker');await pause(600);
let nodes=layout(),popup=bounds(find('workspace-picker',nodes)),button=bounds(find('sidebar-workspace',nodes));
assert.ok((popup[2]-popup[0])/density<=302&&(popup[3]-popup[1])/density<=330,'Workspace should remain a compact second level');
assert.ok(popup[3]<=button[1]+2*density,'Workspace opens above its sidebar entry');
for(const name of ['projects','pending','review','settings','reminders'])assert.ok(find('workspace-'+name,nodes));
await shot('floating-workspace-menu');await back();assert.ok(!find('workspace-picker'));assert.ok(find('sidebar-dismiss'),'First Back dismisses only the popup');
await tap('sidebar-workspace');await wait('workspace-picker');const screen=bounds(layout().find(n=>n.type==='root'));cmd('shell','uitest uiInput click '+(screen[2]-10)+' 500');await pause(800);assert.ok(!find('workspace-picker'));assert.ok(find('sidebar-dismiss'),'Popup outside dismissal must not click through to the drawer');
await tap('sidebar-workspace');await wait('workspace-picker');await tap('workspace-review');await wait('review-segments');assert.ok(!find('workspace-picker'));assert.ok(!find('sidebar-dismiss'));await tap('native-back');await wait('chat-input');await pause(1000);
await menu('外观');const original=layout().find(n=>n.text?.startsWith('当前外观：'))?.text.slice(5);assert.ok(['跟随系统','浅色','深色'].includes(original));
try{
 await tap('浅色');await pause(700);await tap('native-back');await wait('chat-input');await pause(1800);geometry();await shot('floating-chat-light');
 await tap('attachment-add');await wait('attachment-files');await shot('floating-attachment-light');await back();
 await tap('open-sidebar');await tap('sidebar-workspace');await wait('workspace-picker');await shot('floating-workspace-light');await back();await back();
}finally{await menu('外观');await tap(original);await pause(700);await tap('native-back');await wait('chat-input');await pause(1800);}
assert.equal(find('chat-input').text,'');assert.equal((await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length,prompts);
console.log('PASS native floating title/composer geometry, footer status without lift, plus alignment, latest action, attachment menu, editable draft, workspace bounds/dismissal/navigation, and both themes; no prompt sent.');
