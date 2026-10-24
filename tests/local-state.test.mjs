import { ts } from './helpers/typescript.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import vm from 'node:vm';

const values=new Map();let failFlush=false;const copied=[];
const prefs={get:async(key,fallback)=>values.get(key)??fallback,put:async(key,value)=>values.set(key,value),flush:async()=>{if(failFlush)throw new Error('disk full');}};
const modules={
 '@kit.AbilityKit':{},'@kit.BasicServicesKit':{pasteboard:{MIMETYPE_TEXT_PLAIN:'text/plain',createData:(type,text)=>({type,text}),getSystemPasteboard:()=>({setData:async data=>copied.push(data)})}},
 '@kit.ArkData':{preferences:{getPreferences:async()=>prefs}},'@kit.AssetStoreKit':{asset:{}},
 '@kit.ArkTS':{util:{TextEncoder:class{encodeInto(text){return new TextEncoder().encode(text);}}}},'../domain/Core':{}
};
function load(path){const exports={};const code=ts.transpileModule(readFileSync(path,'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;vm.runInNewContext(code,{exports,require:name=>{assert.ok(modules[name],name);return modules[name];},Error,Map,JSON});return exports;}
let count=0;async function test(name,run){await run();count++;console.log('PASS '+name);}
modules['../domain/ModelSelection']=load('entry/src/main/ets/domain/ModelSelection.ts');
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

await test('model enablement, favorites and history remain isolated by server and survive reload',async()=>{
 const p={enabled:['p/a','p/b'],favorites:['p/a'],recent:['p/b','p/a']};await storage.saveModelPreferences('model-a',p);
 assert.deepEqual(JSON.parse(JSON.stringify(await storage.modelPreferences('model-a'))),p);assert.equal((await storage.modelPreferences('model-b')).enabled.length,0);
 const again=new Storage();await again.init({});assert.equal((await again.modelPreferences('model-a')).recent[0],'p/b');
});
await test('failed model preference flush restores the previous readable value',async()=>{
 const before=values.get('modelPreferences.model-a');failFlush=true;await assert.rejects(storage.saveModelPreferences('model-a',{enabled:['p/new'],favorites:[],recent:[]}),/disk full/);failFlush=false;
 assert.equal(values.get('modelPreferences.model-a'),before);assert.equal((await storage.modelPreferences('model-a')).enabled[0],'p/a');
});
await test('invalid or absent model preferences start empty without touching other settings',async()=>{
 values.set('modelPreferences.invalid','{bad');assert.equal((await storage.modelPreferences('invalid')).favorites.length,0);
 assert.equal((await storage.modelPreferences('never-seen')).enabled.length,0);await assert.rejects(new Storage().modelPreferences('x'),/尚未就绪/);
});
console.log(count+' local storage/clipboard tests passed.');
