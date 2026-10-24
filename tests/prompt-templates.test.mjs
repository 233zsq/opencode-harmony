import {ts} from './helpers/typescript.mjs';
import assert from 'node:assert/strict';
import {readFileSync,mkdtempSync,mkdirSync,rmSync} from 'node:fs';
import {resolve,join} from 'node:path';
import {randomUUID} from 'node:crypto';
import {DatabaseSync} from 'node:sqlite';
import vm from 'node:vm';
const root=resolve(import.meta.dirname,'..');mkdirSync(join(root,'.test'),{recursive:true});
const directory=mkdtempSync(join(root,'.test','prompt-library-'));
const databases=new Map();let failWrite=false,failOpen=false,opens=0;
const modules=new Map([
 ['@kit.AbilityKit',{}],['@kit.ArkTS',{util:{generateRandomUUID:()=>randomUUID()}}],
 ['@kit.ArkData',{relationalStore:{SecurityLevel:{S3:3},async getRdbStore(context,config){
  assert.equal(config.encrypt,true);assert.equal(config.securityLevel,3);assert.equal(config.name,'opencode_prompt_templates_v1.db');opens++;
  if(failOpen)throw Error('keystore unavailable');
  const key=context.id||'default';if(!databases.has(key))databases.set(key,new DatabaseSync(join(directory,key+'.sqlite')));const db=databases.get(key);
  return {async executeSql(sql,args=[]){if(failWrite&&sql.startsWith('INSERT'))throw Error('disk full');if(args.length)db.prepare(sql).run(...args);else db.exec(sql);},
   async querySql(sql,args=[]){const values=db.prepare(sql).all(...args);let index=-1;return{goToFirstRow(){index=0;return values.length>0;},getString(i){return String(Object.values(values[index])[i]);},close(){}};}};
 }}}]
]);
function load(path,key){const exports={};vm.runInNewContext(ts.transpileModule(readFileSync(join(root,path),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022,experimentalDecorators:true}}).outputText,{exports,require:name=>{assert.ok(modules.has(name),name);return modules.get(name);},Observed:value=>value,Error,Date,Array,Map,Set,Promise,JSON,Number});modules.set(key,exports);return exports;}
const domain=load('entry/src/main/ets/domain/PromptTemplates.ts','../domain/PromptTemplates');
const {PromptTemplateStorage}=load('entry/src/main/ets/data/PromptTemplateStorage.ets','../data/PromptTemplateStorage');
const {PromptTemplateStore}=load('entry/src/main/ets/presentation/PromptTemplateStore.ets','store');
const item=(id='one',title='Review',text='检查代码😀',updated=1)=>({id,title,text,updated});
let count=0;const test=async(name,run)=>{await run();count++;console.log('PASS '+name);};
const memory=(items=[])=>({items,async load(){return this.items;},async save(next){this.items=JSON.parse(JSON.stringify(next));}});
const gate=()=>{let release;return{promise:new Promise(r=>release=r),release:v=>release(v)};};
try{
 await test('literal title and body search supports Chinese and case without regex evaluation',async()=>{const items=[item(),item('two','[a.b]','Other')];assert.equal(domain.findPromptTemplates(items,'检查')[0].id,'one');assert.equal(domain.findPromptTemplates(items,'review').length,1);assert.equal(domain.findPromptTemplates(items,'[a.b]').length,1);assert.equal(domain.findPromptTemplates(items,'NO MATCH').length,0);});
 await test('library validation bounds every record, rejects duplicates and malformed JSON, and copies data',async()=>{
  const values=[item()];const parsed=domain.parsePromptTemplates(JSON.stringify(values));parsed[0].text='changed';assert.equal(values[0].text,'检查代码😀');
  for(const bad of ['{broken','{}',JSON.stringify([item(),item()]),JSON.stringify([item('bad/id')]),JSON.stringify([item('a',' ','ok')]),JSON.stringify([item('a','x'.repeat(61),'ok')]),JSON.stringify([item('a','ok',' ')]),JSON.stringify([item('a','ok','x'.repeat(20001))]),JSON.stringify([item('a','ok','x',-1)]),JSON.stringify(Array.from({length:51},(_,i)=>item('p'+i)))])assert.throws(()=>domain.parsePromptTemplates(bad));
 });
 await test('append preserves literal whitespace and refuses overflow instead of truncating',async()=>{assert.equal(domain.appendPromptTemplate('before',' after '),'before\n\n after ');assert.equal(domain.appendPromptTemplate('','x'.repeat(20000)).length,20000);assert.throws(()=>domain.appendPromptTemplate('x'.repeat(19999),'extra'),/20000/);assert.throws(()=>domain.appendPromptTemplate('','  '));});
 await test('create, rename, search and delete persist only after successful writes',async()=>{
  const port=memory(),store=new PromptTemplateStore(port);await store.load();store.edit();store.title='  Check  ';store.text='  Body\n😀  ';assert.equal(store.changed(),true);assert.equal(await store.save(),true);assert.equal(store.items[0].title,'Check');const id=store.items[0].id;
  store.edit(store.items[0]);store.title='New';assert.equal(await store.save(),true);assert.equal(store.items.length,1);assert.equal(store.items[0].id,id);assert.equal(store.items[0].text,'  Body\n😀  ');
  assert.equal(await store.remove(id),true);assert.equal(store.items.length,0);assert.equal(port.items.length,0);
 });
 await test('a failed read cannot turn an unread library into an empty overwrite',async()=>{let saves=0;const store=new PromptTemplateStore({async load(){throw Error('unavailable');},async save(){saves++;}});await store.load();store.edit();store.title='try';store.text='body';assert.equal(store.ready,false);assert.equal(store.editing,false);assert.equal(await store.save(),false);assert.equal(saves,0);});
 await test('failed saves retain the previous collection and the complete unsaved editor',async()=>{const port=memory([item()]);const store=new PromptTemplateStore(port);await store.load();port.save=async()=>{throw Error('full');};store.edit(store.items[0]);store.text='new private text';assert.equal(await store.save(),false);assert.equal(store.items[0].text,'检查代码😀');assert.equal(store.text,'new private text');assert.equal(store.editing,true);assert.equal(store.saving,false);assert.ok(store.error);});
 await test('failed deletion preserves the authored entry',async()=>{const port=memory([item()]);const store=new PromptTemplateStore(port);await store.load();port.save=async()=>{throw Error('full');};assert.equal(await store.remove('one'),false);assert.equal(store.items.length,1);});
 await test('concurrent save and delete taps are blocked while a snapshot is committing',async()=>{const port=memory([item()]);const store=new PromptTemplateStore(port);await store.load();const pending=gate();let calls=0;port.save=async()=>{calls++;await pending.promise;};store.edit();store.title='Second';store.text='body';const save=store.save();assert.equal(store.saving,true);assert.equal(await store.save(),false);assert.equal(await store.remove('one'),false);store.cancel();assert.equal(store.editing,true);pending.release();assert.equal(await save,true);assert.equal(calls,1);assert.equal(store.items.length,2);});
 await test('capacity prevents new entries but allows edits and deletion',async()=>{const store=new PromptTemplateStore(memory(Array.from({length:50},(_,i)=>item('p'+i))));await store.load();store.edit();store.title='extra';store.text='body';assert.equal(await store.save(),false);store.edit(store.items[0]);store.title='renamed';assert.equal(await store.save(),true);assert.equal(store.items.length,50);assert.equal(await store.remove(store.items[0].id),true);});
 await test('cancel keeps the saved entry and reopening restores its original text',async()=>{const store=new PromptTemplateStore(memory([item()]));await store.load();store.edit(store.items[0]);assert.equal(store.changed(),false);store.text='unsaved';store.cancel();assert.equal(store.editing,false);store.edit(store.items[0]);assert.equal(store.text,'检查代码😀');});
 await test('native adapter requires encrypted S3 storage and survives a real SQLite reopen',async()=>{const storage=new PromptTemplateStorage();storage.attach({id:'restart'});await storage.save([item('one','本机提示词','Private\n中文😀')]);const reopened=new PromptTemplateStorage();reopened.attach({id:'restart'});assert.equal((await reopened.load())[0].text,'Private\n中文😀');assert.ok(opens>=2);});
 await test('queued writes capture immutable values and SQL content is parameterized',async()=>{const storage=new PromptTemplateStorage();storage.attach({id:'snapshot'});const items=[item('one',"Quotes '","'); DELETE FROM library; --")];const saving=storage.save(items);items[0].text='mutated';await saving;assert.equal((await storage.load())[0].text,"'); DELETE FROM library; --");});
 await test('SQLite write failure preserves the last durable collection and subsequent retry succeeds',async()=>{const storage=new PromptTemplateStorage();storage.attach({id:'atomic'});await storage.save([item()]);failWrite=true;await assert.rejects(storage.save([item('two')]));failWrite=false;assert.equal((await storage.load())[0].id,'one');await storage.save([item('two')]);assert.equal((await storage.load())[0].id,'two');});
 await test('corrupt durable data is reported and retained for recovery rather than silently erased',async()=>{const storage=new PromptTemplateStorage();storage.attach({id:'corrupt'});await storage.save([item()]);databases.get('corrupt').prepare('UPDATE library SET body=?').run('{broken');await assert.rejects(storage.load());assert.equal(databases.get('corrupt').prepare('SELECT body FROM library').get().body,'{broken');});
 await test('encryption initialization failure can be retried and has no plaintext fallback',async()=>{const storage=new PromptTemplateStorage();await assert.rejects(storage.load());storage.attach({id:'retry'});failOpen=true;await assert.rejects(storage.load());failOpen=false;assert.equal((await storage.load()).length,0);});
 console.log(count+' prompt template behavior and real SQLite tests passed; native encryption requires device acceptance.');
}finally{for(const db of databases.values())db.close();const target=resolve(directory),base=resolve(root,'.test');assert.ok(target.startsWith(base+'/prompt-library-')||target.startsWith(base+'\\prompt-library-'));rmSync(target,{recursive:true,force:true});}
