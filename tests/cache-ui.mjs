// API26 emulator; only the named loopback fixture, no production writes or Agent prompts.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {tap,find,wait,back,pause,input,layout,bounds,shot,menu,reveal} from './native-driver.mjs';
const endpoint='http://127.0.0.1:4216',mode=process.argv[2]||'connect';
const state=async()=>await(await fetch(endpoint+'/__test/state')).json();
const marker='NATIVE_CACHE_PERSISTENCE_FIXTURE';
if(mode==='connect'||mode==='thin'){
 if(find('native-back'))await tap('native-back');
 await menu('服务器连接');
 if(mode==='thin'){
  const name=await reveal(endpoint),b=bounds(name),nodes=layout();
  const profile=nodes.find(n=>n.id?.startsWith('server-profile-')&&bounds(n)[1]<=b[1]&&bounds(n)[3]>=b[3]);
  assert.ok(profile);await tap(await reveal('connect-server-'+profile.id.slice('server-profile-'.length)));
 }else{
  await tap(await reveal('add-server'));
  for(const [id,value] of [['server-name','缓存隔离验收'],['server-url',endpoint],['server-user','opencode'],['server-password','local-test']])await input(id,value);
  let allow=await reveal('allow-http');if(allow.checked!=='true')await tap(allow);
  await tap(await reveal('connect-button'));
 }
 await wait('chat-input',45000);
 if(!find(marker)){
  await menu('项目与会话');await tap(await reveal('Harmony Fixture'));await pause(1500);
  await tap(await reveal('session-ses_fixture'));
 }
 await wait(marker,45000);
 if(mode==='thin'){
  assert.equal((await state()).cacheFileReads,0,'Opening history must not download attachment bodies');
  await tap(await reveal('attachment-open-cache_native_user-file-0'));await wait('attachment-preview-text');
  assert.ok(find('attachment-preview-text').text.startsWith('x'));await back();
  assert.equal((await state()).cacheFileReads,1,'First preview downloads exactly one file');
 }
 await pause(2000);const before=(await state()).historyReads.length;await pause(16000);
 assert.equal((await state()).historyReads.length,before,'Healthy idle SSE must not refetch full history every 5 seconds');
 await menu('存储与流量');
 assert.ok(!find('cache-notice')?.text?.includes('不可用'));
 const size=find('cache-size')?.text;assert.ok(parseFloat(size)>0.1,'Native encrypted RDB must contain fixture attachments');
 await shot('cache-encrypted-native');writeFileSync('.test/cache-native-proof.json',JSON.stringify({size,before,idleFullReads:0}));
 await tap('native-back');console.log('PASS native encrypted cache writes and 16-second idle without repeated full history');
}else if(mode==='offline'){
 await wait(marker,45000);
 assert.ok(layout().some(n=>n.text?.includes('本机缓存')||n.text==='离线缓存'),'Offline content must be labeled as cached');
 await shot('cache-native-offline');
 await tap(await reveal('attachment-open-cache_native_user-file-0'));await wait('attachment-preview-text');
 assert.ok(find('attachment-preview-text').text.startsWith('x'),'Previously opened attachment must survive offline restart');await back();
 await menu('存储与流量');assert.ok(parseFloat(find('cache-size')?.text)>0.1);
 await tap('clear-local-cache');await wait('清理');await tap('取消');
 assert.ok(parseFloat(find('cache-size')?.text)>0.1,'Cancel must retain cached content');
 await tap('clear-local-cache');await tap('清理');await wait('已清空本机缓存，服务器历史仍然保留');
 assert.equal(find('cache-size')?.text,'0.0 MB / 200 MB');await shot('cache-native-cleared');
 console.log('PASS native restart + offline cache recovery, cancellation, encrypted DB clear/vacuum');
}else if(mode==='empty'){
 await pause(15000);
 assert.ok(!find(marker),'Cleared cache must not return after another process restart');
 await menu('存储与流量');assert.equal(find('cache-size')?.text,'0.0 MB / 200 MB');
 console.log('PASS cleared native cache remains empty after restart');
}else if(mode==='cleanup'){
 if(find('native-back'))await tap('native-back');await menu('服务器连接');
 const item=await reveal(endpoint),b=bounds(item),nodes=layout();
 const profile=nodes.find(n=>n.id?.startsWith('server-profile-')&&bounds(n)[1]<=b[1]&&bounds(n)[3]>=b[3]);
 assert.ok(profile,'Remove only the named loopback fixture');
 const before=nodes.filter(n=>n.id?.startsWith('server-profile-')).map(n=>n.id);
 await tap(await reveal('remove-server-'+profile.id.slice('server-profile-'.length)));
 await wait('移除连接');await tap('移除');await pause(1000);
 const after=layout().filter(n=>n.id?.startsWith('server-profile-')).map(n=>n.id);
 assert.ok(!after.includes(profile.id));assert.deepEqual(after.sort(),before.filter(id=>id!==profile.id).sort());
 console.log('PASS temporary fixture profile removed; existing server profiles preserved');
}
