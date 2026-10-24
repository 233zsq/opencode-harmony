// API26 acceptance: a named loopback connection only, without submitting prompts.
import assert from 'node:assert/strict';
import {writeFileSync,readFileSync} from 'node:fs';
import {find,wait,tap,input,menu,back,pause,shot,cmd,layout,reveal} from './native-driver.mjs';
const title='NATIVE_PROMPT_LIBRARY_20261024',renamed=title+'_EDITED',body='REVIEW_CODE_OFFLINE_FIXTURE';
const state=async()=>await(await fetch('http://127.0.0.1:4216/__test/state')).json();
const restart=async()=>{cmd('shell','aa force-stop com.example.opencode_harmony');await pause(500);cmd('shell','aa start -b com.example.opencode_harmony -m entry -a EntryAbility');await wait('chat-input',45000);};
const rootChat=async()=>{if(find('native-back'))await back();if(find('more-functions-page'))await back();await wait('chat-input');};
const before=await state();assert.equal(before.receipts.length,0,'Use only the empty loopback fixture');
let id='';
if(process.argv[2]!=='resume'){
await rootChat();await menu('常用提示词');await wait('prompt-template-search');await input('prompt-template-search',title);
assert.ok(!layout().some(n=>n.visible!=='false'&&n.id?.startsWith('prompt-template-edit-')),'A previous fixture must be cleaned up before repeating this acceptance');
await tap('prompt-template-add');await wait('prompt-template-title');await input('prompt-template-title',title);await input('prompt-template-text',body);
await back();await wait('放弃本次编辑');await tap('继续编辑');assert.equal(find('prompt-template-text').text,body);
await shot('prompt-library-editor-native');await tap('prompt-template-save');await wait(title);
const edit=layout().find(n=>n.visible!=='false'&&n.id?.startsWith('prompt-template-edit-'));assert.ok(edit);id=edit.id.slice('prompt-template-edit-'.length);
writeFileSync('.test/prompt-library-native-record.json',JSON.stringify({id,title,renamed,body}));
await tap('prompt-template-edit-'+id);await input('prompt-template-title',renamed);await tap('prompt-template-save');await wait(renamed);
console.log('PASS native create, unsaved Back confirmation and rename');
}else{const saved=JSON.parse(readFileSync('.test/prompt-library-native-record.json','utf8'));assert.equal(saved.renamed,renamed);assert.match(saved.id,/^[a-f0-9-]{36}$/);id=saved.id;}
await restart();await menu('常用提示词');await input('prompt-template-search',body);await wait('prompt-template-edit-'+id);await wait(renamed);await shot('prompt-library-list-native');console.log('PASS native encrypted storage reopen and body search');
await rootChat();await menu('项目与会话');if(!find('session-ses_fixture')){await tap(await reveal('Harmony Fixture'));await pause(1000);}await tap(await reveal('session-ses_fixture'));await wait('chat-input');
await input('chat-input','NATIVE_KEEP_INPUT');await tap('attachment-add');await wait('attachment-prompts');await tap('attachment-prompts');await wait('prompt-template-search');await input('prompt-template-search',renamed);
await tap('prompt-template-insert-'+id);await wait('chat-input');assert.equal(find('chat-input').text,'NATIVE_KEEP_INPUT\n\n'+body);assert.equal((await state()).receipts.length,0);await shot('prompt-library-insert-native');console.log('PASS native append preserves the existing input without submitting');
await input('chat-input','');await pause(1800);await menu('常用提示词');await input('prompt-template-search',renamed);await tap('prompt-template-edit-'+id);await tap('prompt-template-delete');await wait('删除提示词');await tap('取消');assert.ok(find('prompt-template-delete'));
await tap('prompt-template-delete');await wait('删除提示词');await tap('删除');await wait('prompt-template-search');await wait('prompt-template-empty');
await restart();await menu('常用提示词');await input('prompt-template-search',renamed);await wait('prompt-template-empty');await rootChat();
assert.equal((await state()).receipts.length,0);console.log('PASS native encrypted prompt library: create, back confirmation, rename, process restart, literal body search, append without sending, delete cancellation and durable deletion; only the created fixture was removed');
