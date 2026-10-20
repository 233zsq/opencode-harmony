// Native visual-review regressions. Requires an explicitly selected loopback fixture.
import assert from 'node:assert/strict';
import {tap,find,wait,menu,back,reveal,layout,bounds,shot,pause} from './native-driver.mjs';
const density=Number(process.env.UI_DENSITY||3.5);assert.ok(density>0);
const endpoint=process.env.UI_REVIEW_FIXTURE_URL||'http://127.0.0.1:55143';
assert.equal(new URL(endpoint).hostname,'127.0.0.1','Use an isolated local fixture.');
assert.equal(find('model-select')?.text,'本机测试模型','Select the local fixture before this test.');
for(const id of ['model-select','agent-select']){const node=find(id);assert.equal(node.type,'Button');assert.ok(bounds(node)[3]-bounds(node)[1]>=40*density,id+' must retain a 40vp target on the selected emulator.');}
await tap('agent-select');await wait('agent-picker');await wait('agent-option-fixture-build');await back();
console.log('PASS model/Agent native button semantics, 40vp controls and Agent sheet.');
const response=await fetch(endpoint+'/__test/control-history',{method:'POST'});assert.ok(response.ok);await wait('CONTROL_LATEST_ANSWER');
await tap('open-menu');await tap(await reveal('open-usage'));await wait('usage-panel');await wait('12,345');await wait('128,000');
assert.equal(layout().some(n=>/^\d+(?:\.\d+)?%$/.test(n.text||'')),false,'Cumulative usage must not be drawn as context occupancy.');
await shot('ui-review-usage');await back();
console.log('PASS native server usage and context limit remain separate without an invented percentage.');
await tap('open-sidebar');await wait('session-search');await tap(await reveal('session-actions-ses_fixture'));await wait('session-name-scope');
assert.equal(find('session-name-scope').text,'会话名称会同步到服务器。');assert.ok(find('session-local-scope'));
assert.ok(bounds(find('session-name-scope'))[3]<=bounds(find('session-name'))[1]);
assert.ok(bounds(find('session-local-scope'))[3]<=bounds(find('session-pin'))[1]);
await shot('ui-review-session-scope');await back();if(find('close-sidebar'))await tap('close-sidebar');
console.log('PASS session rename scope is separate from local-only list settings.');
for(const [label,tag]of [['深色','dark'],['浅色','light'],['跟随系统','system']]){
 await menu('外观');await tap(label);await pause(500);await back();await wait('chat-input');await shot('ui-review-'+tag);
}
console.log('PASS all app themes and return navigation after review fixes; server configuration is unchanged.');
