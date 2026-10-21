// Regression for editor-session/floating-material focus. Only an owned loopback fixture may be used.
import assert from 'node:assert/strict';
import {find,tap,wait,menu,back,input,pause,layout,reveal} from './native-driver.mjs';
const endpoint='http://127.0.0.1:'+(process.env.OPENCODE_FIXTURE_PORT||4210);
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
if(find('model-quick-picker'))await back();if(find('native-back'))await tap('native-back');if(find('sidebar-dismiss'))await back();
assert.equal(find('model-select')?.text,'本机测试模型');
assert.equal(find('chat-input')?.text,'','Preserve any existing draft instead of testing over it.');
const prompts=(await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length;
await menu('外观');const original=layout().find(n=>n.text?.startsWith('当前外观：'))?.text.slice(5);assert.ok(['跟随系统','浅色','深色'].includes(original));
await tap('native-back');await wait('chat-input');await pause(700);
try {
 await input('chat-input','Material focus fixture');await input('chat-input','');
 await menu('外观');await tap(original==='浅色'?'深色':'浅色');await pause(1000);await tap('native-back');await wait('chat-input');await pause(700);
 await tap('model-select');await wait('quick-model-option-fixture/fixture-coder');await pause(700);
 await back();assert.ok(!find('model-quick-picker'),'The first Back must dismiss the material after editing and changing theme.');
 await tap('open-menu');await wait('more-functions-page');
 console.log('PASS first model click, first Back and immediate navigation after native text entry and theme change.');
} finally {
 if(find('model-quick-picker'))await back();
 if(find('more-functions-page'))await tap(await reveal('外观'));
 else {if(find('native-back'))await tap('native-back');await menu('外观');}
 await tap(original);await pause(700);await tap('native-back');await wait('chat-input');await pause(700);
}
assert.equal(find('chat-input').text,'');assert.equal((await state()).receipts.filter(r=>r.path.endsWith('/prompt')).length,prompts);
console.log('PASS original appearance and empty draft preserved; no prompt sent.');
