import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import vm from 'node:vm';
const require=createRequire(import.meta.url);
const ts=require(resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const values=new Map();let failFlush=false;const copied=[];
const prefs={get:async(key,fallback)=>values.get(key)??fallback,put:async(key,value)=>values.set(key,value),flush:async()=>{if(failFlush)throw new Error('disk full');}};
const modules={
 '@kit.AbilityKit':{},'@kit.BasicServicesKit':{pasteboard:{MIMETYPE_TEXT_PLAIN:'text/plain',createData:(type,text)=>({type,text}),getSystemPasteboard:()=>({setData:async data=>copied.push(data)})}},
 '@kit.ArkData':{preferences:{getPreferences:async()=>prefs}},'@kit.AssetStoreKit':{asset:{}},
 '@kit.ArkTS':{util:{TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text);}}}},'../domain/Core':{}
};
function load(path){const exports={};const code=ts.transpileModule(readFileSync(path,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInNewContext(code,{exports,require:name=>{assert.ok(modules[name],name);return modules[name];},Error,Map,JSON});return exports;}
let count=0;async function test(name,run){await run();count++;console.log('PASS '+name);}
const {Storage}=load('entry/src/main/ets/data/Storage.ets');const storage=new Storage();await storage.init({});
await test('session bookmarks persist by server without storing transcript or draft text',async()=>{
 await storage.saveSessionPreferences('a',[{id:'s',pinned:true,archived:true,title:'Saved',directory:'/repo'}]);assert.equal((await storage.sessionPreferences('a'))[0].title,'Saved');assert.equal((await storage.sessionPreferences('b')).length,0);
 assert.deepEqual([...values.keys()],['sessionPreferences.a']);assert.ok(!values.get('sessionPreferences.a').includes('messages'));
});
await test('invalid bookmark data falls back to an empty configuration',async()=>{values.set('sessionPreferences.bad','{bad');assert.equal((await storage.sessionPreferences('bad')).length,0);values.set('sessionPreferences.bad','{}');assert.equal((await storage.sessionPreferences('bad')).length,0);});
await test('bookmark persistence reports an unavailable preferences store or failed flush',async()=>{await assert.rejects(new Storage().saveSessionPreferences('a',[]),/尚未就绪/);failFlush=true;await assert.rejects(storage.saveSessionPreferences('a',[]),/disk full/);failFlush=false;});
const {copyText}=load('entry/src/main/ets/presentation/Clipboard.ets');
await test('clipboard preserves complete code and Unicode as plain text',async()=>{const text='const value = "中文🌿";\n  keep indentation';await copyText(text);assert.equal(copied[0].type,'text/plain');assert.equal(copied[0].text,text);});
await test('copying an empty message leaves the clipboard untouched',async()=>{await copyText('');assert.equal(copied.length,1);});
await test('resetting connection metadata clears only its session position and bookmarks',async()=>{await storage.position('one','/private','s');await storage.position('two','/other','other');await storage.saveSessionPreferences('one',[{id:'s',pinned:true}]);await storage.resetServerPosition('one');assert.equal((await storage.last('one')).length,0);assert.equal((await storage.sessionPreferences('one')).length,0);assert.equal((await storage.last('two'))[1],'other');});
await test('connection metadata reset propagates missing-store and flush errors',async()=>{await assert.rejects(()=>new Storage().resetServerPosition('one'),/尚未就绪/);failFlush=true;await assert.rejects(()=>storage.resetServerPosition('one'),/disk full/);failFlush=false;});
console.log(count+' local storage/clipboard tests passed.');
