// Native navigation and reading-layout acceptance against an explicitly selected loopback fixture.
import assert from 'node:assert/strict';
import {tap,find,wait,reveal,back,menu,pause,shot,layout,bounds} from './native-driver.mjs';
const endpoint='http://127.0.0.1:'+(process.env.OPENCODE_FIXTURE_PORT||4210);
const control=async path=>{const response=await fetch(endpoint+'/__test/'+path,{method:'POST'});assert.equal(response.status,200);return response.json();};
if(find('SkinBgContent'))await back();
assert.equal(find('model-select')?.text,'本机测试模型','Select the local fixture first.');
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const writes=(await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length;
await tap('model-select');await wait('model-quick-picker');await pause(700);await tap('model-show-all');await wait('model-picker');await wait('native-back');await shot('luminous-models');await tap('native-back');await wait('chat-input');await pause(700);
await tap('agent-select');await wait('agent-picker');await wait('native-back');await shot('luminous-agents');await tap('native-back');await wait('chat-input');await pause(700);
await tap('open-menu');await wait('more-functions-page');await wait('native-back');await shot('luminous-more');
for(const [id,panel]of[['open-usage','usage-panel'],['open-fork','fork-panel'],['open-export','export-panel']]){
 await tap(await reveal(id));await wait(panel);await wait('native-back');await tap('native-back');await wait('more-functions-page');
}
await back();await wait('chat-input');
const test=await control('ui-phase?phase=thinking');await pause(1800);await wait('reasoning-content-'+test.id);
await control('ui-phase?phase=answer');await pause(1800);await wait('reasoning-toggle-'+test.id);assert.ok(!find('reasoning-content-'+test.id));
await tap(await reveal('tool-row-'+test.toolID));await wait('native-back');await wait('tool-request');await wait('tool-response');
await control('ui-phase?phase=tool-done');await pause(1800);assert.match(find('tool-response').text,/verified sample only/);await shot('luminous-tool');await back();
await shot('luminous-chat');
await tap('open-sidebar');await wait('close-sidebar');await shot('luminous-sidebar');await back();
await menu('外观');const appearance=find('外观')&&layout().find(n=>n.text?.startsWith('当前外观：'))?.text;
const original=appearance?.slice(5);assert.ok(['跟随系统','浅色','深色'].includes(original),'Original appearance must be readable.');
try{
 await tap('深色');await pause(700);await back();await tap('model-select');await wait('model-quick-picker');await pause(700);await tap('model-show-all');await wait('model-picker');await shot('luminous-dark-models');await back();
 await menu('外观');await tap('浅色');await pause(700);await back();
 await tap('model-select');await wait('model-quick-picker');await pause(700);await shot('harmony-light-popup');await back();
 await tap('open-sidebar');await wait('history-sidebar');await shot('harmony-light-sidebar');await back();
 await tap('open-menu');await wait('more-functions-page');await shot('harmony-light-more');await back();
}finally{await menu('外观');await tap(original);await back();}
assert.equal((await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length,writes,'UI inspection must not submit a prompt.');
console.log('PASS native model/Agent/usage/fork/export/tool destinations, parent return, thinking collapse, live tool update, sidebar and both themes; no prompt submitted.');
