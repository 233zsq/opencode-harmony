import { ts } from './helpers/typescript.mjs';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';import{resolve}from'node:path';
const code=ts.transpileModule(readFileSync('entry/src/main/ets/domain/ModelSelection.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const{matchingModels,modelInputs,quickModels,emptyModelPreferences,normalizeModelPreferences,enabledModels,favoriteModels,recentModels,setModelEnabled,setModelFavorite,rememberModel,variantLabel}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
let count=0;function test(name,run){run();count++;console.log('PASS '+name);}
const models=[{id:'opencode/mimo-flash',label:'MiMo Flash'},{id:'xiaomi/mimo-flash',label:'MiMo Flash',input:['text','image']},{id:'custom/reasoner',label:'中文推理',input:['text','pdf']}];
test('channel and model tokens identify the correct one among identical display names',()=>{assert.deepEqual(matchingModels(models,'XIAOMI flash').map(m=>m.id),['xiaomi/mimo-flash']);assert.equal(matchingModels(models,'中文')[0].id,'custom/reasoner');assert.equal(matchingModels(models,'missing').length,0);});
test('current model is first for empty search without reordering the source catalog',()=>{const snapshot=models.slice();assert.equal(matchingModels(models,' ','custom/reasoner')[0].id,'custom/reasoner');assert.deepEqual(models,snapshot);assert.equal(matchingModels(models,'flash','custom/reasoner').length,2);});
test('duplicate identities are omitted and search covers models beyond the initial page',()=>{const catalog=Array.from({length:2500},(_,i)=>({id:'p/model-'+i,label:'Model '+i}));catalog.push(catalog[0]);assert.equal(matchingModels(catalog,'').length,2500);assert.equal(matchingModels(catalog,'model-2499')[0].id,'p/model-2499');});
test('attachment capabilities are shown only when declared by the server',()=>{assert.equal(modelInputs(models[0]),'文本');assert.equal(modelInputs(models[1]),'文本 · 图片');assert.equal(modelInputs(models[2]),'文本 · PDF');});
test('quick choices retain exact identity, prioritize current/MiMo/DeepSeek and keep the source unchanged',()=>{
 const catalog=[{id:'p/other',label:'Other'},{id:'opencode/mimo',label:'MiMo'},{id:'deepseek/chat',label:'DeepSeek'},{id:'p/current',label:'Current'}];const snapshot=JSON.stringify(catalog);
 assert.deepEqual(quickModels(catalog,'p/current').map(m=>m.id),['p/current','opencode/mimo','deepseek/chat']);assert.equal(JSON.stringify(catalog),snapshot);
});
test('quick choices never fabricate unavailable models and handle small or duplicate catalogs',()=>{
 assert.deepEqual(quickModels([],'missing'),[]);assert.deepEqual(quickModels([models[0],models[0]],'missing').map(m=>m.id),['opencode/mimo-flash']);assert.equal(quickModels(models,'custom/reasoner')[0].id,'custom/reasoner');
});

test('nothing is selectable until locally enabled, and the server cannot be bypassed',()=>{
 let p=emptyModelPreferences();assert.equal(enabledModels(models,p).length,0);p=setModelEnabled(p,models[0].id,true);
 assert.deepEqual(enabledModels([...models,{id:'p/disabled',label:'Hidden',available:false}],{...p,enabled:[models[0].id,'p/disabled']}).map(m=>m.id),[models[0].id]);
});
test('favoriting enables the exact identity and disabling removes it from favorites',()=>{
 const p=setModelFavorite(emptyModelPreferences(),'xiaomi/mimo-flash',true);assert.deepEqual(p.enabled,['xiaomi/mimo-flash']);assert.deepEqual(favoriteModels(models,p).map(m=>m.id),['xiaomi/mimo-flash']);
 const off=setModelEnabled(p,'xiaomi/mimo-flash',false);assert.equal(off.favorites.length,0);assert.equal(off.enabled.length,0);assert.equal(p.enabled.length,1);
});
test('history selects two unique recent enabled nonfavorites and excludes absent models',()=>{
 let p={enabled:models.map(m=>m.id),favorites:[models[0].id],recent:[models[0].id,'missing/model',models[2].id,models[1].id]};
 assert.deepEqual(recentModels(models,p).map(m=>m.id),[models[2].id,models[1].id]);p=rememberModel(p,models[1].id);assert.deepEqual(recentModels(models,p).map(m=>m.id),[models[1].id,models[2].id]);
 p=setModelEnabled(p,models[1].id,false);assert.deepEqual(recentModels(models,p).map(m=>m.id),[models[2].id]);
});
test('malformed preferences cannot invent identities, duplicate favorites or exceed history bounds',()=>{
 const p=normalizeModelPreferences({enabled:['a/one','a/one',3,'bad','a/'],favorites:['a/one','b/two','a/one'],recent:Array.from({length:50},(_,i)=>'p/m'+i)});
 assert.deepEqual(p.enabled,['a/one']);assert.deepEqual(p.favorites,['a/one']);assert.equal(p.recent.length,30);
 assert.deepEqual(normalizeModelPreferences({enabled:{},favorites:null,recent:3}),emptyModelPreferences());
});
test('variant labels preserve unknown server IDs and do not invent selectable levels',()=>{
 assert.equal(variantLabel('medium'),'标准');assert.equal(variantLabel('vendor-custom'),'vendor-custom');assert.equal(variantLabel(''),'默认');
});
console.log(count+' model selection tests passed.');
