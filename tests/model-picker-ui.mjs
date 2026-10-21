// Native model picking against tests/fake-server.mjs; never invokes an external model.
import assert from 'node:assert/strict';import{tap,find,wait,input,back,menu,pause,layout,shot,reveal}from'./native-driver.mjs';
const endpoint='http://127.0.0.1:'+(process.env.OPENCODE_FIXTURE_PORT||4210);const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
if(find('SkinBgContent'))await back();if(!find('model-select'))await back();assert.equal(find('model-select')?.text,'本机测试模型','Refusing to switch models outside the local fixture.');
const dismiss=async()=>{if(find('SkinBgContent'))await back();};
const posts=async()=>(await state()).receipts.filter(r=>r.path.endsWith('/model')&&r.method==='POST');
const baseline=(await posts()).length;
await tap('model-select');await wait('model-picker');await wait('native-back');await wait('已显示 40/77');await tap('model-more');await wait('已显示 77/77');
await input('model-search','fixture-extra model-074');await dismiss();await wait('model-option-fixture-extra/model-074');await shot('model-picker-search');await tap('model-option-fixture-extra/model-074');await wait('测试模型074');
let changes=await posts();assert.equal(changes.length,baseline+1);assert.deepEqual(changes.at(-1).input,{model:{id:'model-074',providerID:'fixture-extra'}});assert.ok(!find('model-picker'));
await tap('model-select');await input('model-search','fixture-second');await dismiss();await fetch(endpoint+'/__test/model-failure?enabled=1',{method:'POST'});await tap('model-option-fixture/fixture-second');await wait('model-switch-error');assert.ok(find('model-picker'));await shot('model-picker-rejected');
await fetch(endpoint+'/__test/model-failure?enabled=0',{method:'POST'});await tap('model-option-fixture/fixture-second');await wait('模型切换测试');assert.ok(!find('model-picker'));
const accepted=(await posts()).length;await tap('model-select');await tap('model-option-fixture/fixture-second');assert.equal((await posts()).length,accepted,'Tapping the current model must not issue another switch');
await tap('model-select');await input('model-search','not-a-server-model');await dismiss();await wait('model-no-results');assert.equal((await posts()).length,accepted);await shot('model-picker-empty');
await tap('model-manage');await wait('provider-search');await back();await tap('model-select');await input('model-search','fixture-coder');await dismiss();await tap('model-option-fixture/fixture-coder');await wait('本机测试模型');
assert.equal((await posts()).length,baseline+4);console.log('PASS native 77-model pagination, channel/ID search, exact selection, failure retry, no-op current selection, empty search and configuration shortcut.');
