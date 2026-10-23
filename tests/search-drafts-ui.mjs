// API26 native acceptance against the named loopback fixture only; no real Agent prompts.
import assert from 'node:assert/strict';
import {find,wait,tap,input,menu,back,pause,shot,cmd} from './native-driver.mjs';
const mode=process.argv[2]||'search';
const draft='NATIVE_ENCRYPTED_TEXT_DRAFT_20261023';
async function restart(){cmd('shell','aa force-stop com.example.opencode_harmony');await pause(600);cmd('shell','aa start -b com.example.opencode_harmony -m entry -a EntryAbility');await wait('chat-input',45000);}
if(mode==='search'){
 await menu('查找对话');await wait('conversation-search-input');await input('conversation-search-input','NATIVE_CACHE');
 await wait('search-hit-cache_native_user');assert.ok(find('conversation-search-count').text.includes('1 条匹配'));
 await tap('助手回复');await wait('conversation-search-empty');assert.ok(find('conversation-search-count').text.includes('0 条匹配'));
 await tap('全部');await wait('search-hit-cache_native_user');await shot('conversation-search-native');
 await tap('search-hit-cache_native_user');await wait('conversation-list');assert.ok(find('NATIVE_CACHE_PERSISTENCE_FIXTURE'));await shot('conversation-search-location');
 console.log('PASS native search, author filter, result count and message-context navigation');
}else if(mode==='paging'){
 await fetch('http://127.0.0.1:4216/__test/export-history',{method:'POST'});if(find('native-back'))await back();await menu('项目与会话');await tap('session-ses_fixture');await wait('chat-input');await pause(1000);
 await menu('查找对话');await wait('search-earlier');await wait('已加载 30 条 · 0 条匹配');
 const before=await(await fetch('http://127.0.0.1:4216/__test/state')).json();await tap('search-earlier');await wait('已加载 60 条 · 0 条匹配');
 const after=await(await fetch('http://127.0.0.1:4216/__test/state')).json();assert.equal(after.historyReads.length-before.historyReads.length,1);assert.equal(after.cacheFileReads,before.cacheFileReads);
 await input('conversation-search-input','EXPORT_ENTRY_310');await wait('search-hit-export_310');await tap('search-hit-export_310');await wait('EXPORT_ENTRY_310');
 assert.equal(after.receipts.length,0);await shot('conversation-search-earlier-native');console.log('PASS native explicit single-page history search, no attachment downloads or prompt submissions');
}else if(mode==='draft'){
 await input('chat-input',draft);await pause(1800);await restart();await wait(draft,45000);assert.equal(find('chat-input').text,draft);await shot('text-draft-native-restart');
 console.log('PASS native encrypted text draft survives an actual process restart without sending');
}else if(mode==='offline'){
 await restart();await wait(draft,45000);assert.equal(find('chat-input').text,draft);assert.ok(find('chat-status').text.includes('缓存'));await shot('text-draft-native-offline');
 console.log('PASS native text draft and cached transcript recover after an offline process restart');
}else if(mode==='clear'){
 await input('chat-input','');await pause(1800);await restart();await pause(2000);assert.equal(find('chat-input').text,'');
 console.log('PASS deleting text removes the persistent draft across process restarts');
}