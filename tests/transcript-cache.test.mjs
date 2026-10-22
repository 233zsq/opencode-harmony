import assert from 'node:assert/strict';
import {createRequire} from 'node:module';
import {readFileSync,mkdtempSync,rmSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {createHash} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import vm from 'node:vm';
const require=createRequire(import.meta.url),root=resolve(import.meta.dirname,'..');
const ts=require(resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const directory=mkdtempSync(join(root,'.test','cache-sql-'));
const databases=new Map();let clock=1,encryptedOpens=0;
class CacheDate extends Date{static now(){return clock++;}}
function wrap(db){return{
 async executeSql(sql,args=[]){if(args.length)db.prepare(sql).run(...args);else db.exec(sql);},
 async querySql(sql,args=[]){const rows=db.prepare(sql).all(...args);let index=-1;return{
  goToFirstRow(){index=0;return rows.length>0;},
  getString(column){return String(Object.values(rows[index])[column]);},
  getLong(column){return Number(Object.values(rows[index])[column]);},close(){}
 };}
};}
const modules={
 '@kit.AbilityKit':{},
 '@kit.ArkData':{relationalStore:{SecurityLevel:{S3:3},async getRdbStore(context,config){
  assert.equal(config.encrypt,true);assert.equal(config.securityLevel,3);encryptedOpens++;
  const key=context.id||'default';if(!databases.has(key))databases.set(key,new DatabaseSync(join(directory,key+'.sqlite')));
  return wrap(databases.get(key));
 }}},
 '@kit.CryptoArchitectureKit':{cryptoFramework:{createMd(algorithm){assert.equal(algorithm,'SHA256');const hash=createHash('sha256');return{
  async update(blob){hash.update(blob.data);},async digest(){return{data:new Uint8Array(hash.digest())};}
 };}}},
 '@kit.ArkTS':{util:{TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text);}}}},
 '../domain/Core':{},'../domain/Attachments':{}
};
const exports={};vm.runInNewContext(ts.transpileModule(readFileSync(join(root,'entry/src/main/ets/data/TranscriptCache.ets'),'utf8'),{
 compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}
}).outputText,{exports,require:name=>{assert.ok(modules[name],name);return modules[name];},Date:CacheDate,Map,Set,Array,Promise,JSON,Error});
const config=(username='owner',url='https://fixture.example')=>({id:'fixture',url,username});
const message=(id,text='hello',data='')=>({id,role:'user',text,reasoning:'',state:'completed',parts:[],tools:[],files:data?[{id:id+'-file-0',name:'image.png',mime:'image/png',data,size:Math.floor(data.length*.75)}]:[]});
const snapshot=(id,text='hello',data='')=>({messages:[message(id,text,data)],cursor:'older',savedAt:123});
let count=0;async function test(name,run){await run();count++;console.log('PASS '+name);}
try{
 await test('restart restores Unicode transcript, cursor and deduplicated attachments',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'restore'});
  const data=Buffer.from('fixture-image-content').toString('base64');
  await cache.save(config(),'/repo','one',snapshot('m1','中文🌿',data));
  await cache.save(config(),'/repo','two',snapshot('m2','second',data));
  const rows=databases.get('restore').prepare("SELECT COUNT(*) n FROM entries WHERE key LIKE '%:blob:%'").get();assert.equal(rows.n,1);
  const reopened=new exports.TranscriptCache();await reopened.init({id:'restore'});
  const loaded=await reopened.load(config(),'/repo','one');
  assert.equal(loaded.messages[0].text,'中文🌿');assert.equal(loaded.messages[0].files[0].data,data);assert.equal(loaded.cursor,'older');
 });
 await test('accounts, endpoints and workspaces cannot read one another cached sessions',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'isolation'});await cache.save(config(),'/repo','same',snapshot('m'));
  assert.equal(await cache.load(config('other'),'/repo','same'),undefined);
  assert.equal(await cache.load(config('owner','https://other.example'),'/repo','same'),undefined);
  assert.equal(await cache.load(config(),'/different','same'),undefined);
  assert.ok(await cache.load(config('owner','https://fixture.example/'),'/repo','same'));
 });
 await test('least recently used entries are evicted within the configured byte limit',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'lru'});cache.limit=5000;
  await cache.save(config(),'/repo','a',snapshot('a','x'.repeat(1800)));
  await cache.save(config(),'/repo','b',snapshot('b','x'.repeat(1800)));
  assert.ok(await cache.load(config(),'/repo','a'));
  await cache.save(config(),'/repo','c',snapshot('c','x'.repeat(1800)));
  assert.equal(await cache.load(config(),'/repo','b'),undefined);assert.ok(await cache.load(config(),'/repo','a'));assert.ok(await cache.size()<=5000);
 });
 await test('file cache validates SHA-256 and persists only within its owner namespace',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'files'});const data=Buffer.from('file-content').toString('base64');
  const hash=createHash('sha256').update(data).digest('hex');await cache.saveFile(config(),hash,data);
  assert.equal(await cache.file(config(),hash),data);assert.equal(await cache.file(config('other'),hash),'');
  await assert.rejects(cache.saveFile(config(),hash,'wrong'),/校验/);
 });
 await test('corrupt cached JSON is removed instead of blocking online recovery',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'corrupt'});await cache.save(config(),'/repo','a',snapshot('m'));
  databases.get('corrupt').exec("UPDATE entries SET body='{broken'");
  assert.equal(await cache.load(config(),'/repo','a'),undefined);assert.equal(await cache.size(),0);
 });
 await test('clear waits for queued writes and removes both messages and blob entries',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'clear'});
  const save=cache.save(config(),'/repo','a',snapshot('m','hello',Buffer.from('image').toString('base64')));
  const clear=cache.clear();await Promise.all([save,clear]);assert.equal(await cache.size(),0);assert.equal(await cache.load(config(),'/repo','a'),undefined);
 });
 await test('removing one account preserves other account caches',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'remove'});
  await cache.save(config(),'/repo','same',snapshot('a'));await cache.save(config('other'),'/repo','same',snapshot('b'));
  await cache.removeServer(config());assert.equal(await cache.load(config(),'/repo','same'),undefined);assert.equal((await cache.load(config('other'),'/repo','same')).messages[0].id,'b');
 });
 await test('previously opened thin-history attachment survives restart and offline restore',async()=>{
  const cache=new exports.TranscriptCache();await cache.init({id:'thin-restart'});
  const data=Buffer.from('lazy-file-offline').toString('base64'),hash=createHash('sha256').update(data).digest('hex');
  const entry=snapshot('thin');entry.messages[0].files=[{id:'thin-file-0',name:'lazy.png',mime:'image/png',data:'',size:17,remoteHash:hash,remoteMessage:'thin',remoteIndex:0}];
  await cache.save(config(),'/repo','thin',entry);await cache.saveFile(config(),hash,data);
  const reopened=new exports.TranscriptCache();await reopened.init({id:'thin-restart'});
  assert.equal((await reopened.load(config(),'/repo','thin')).messages[0].files[0].data,data);
 });
 assert.ok(encryptedOpens>=8);console.log(count+' encrypted-cache configuration and real SQLite behavior tests passed; native encryption itself requires device verification.');
}finally{
 for(const db of databases.values())db.close();
 assert.ok(resolve(directory).startsWith(resolve(root,'.test')+'\\cache-sql-')||resolve(directory).startsWith(resolve(root,'.test')+'/cache-sql-'));
 rmSync(directory,{recursive:true,force:true});
}
