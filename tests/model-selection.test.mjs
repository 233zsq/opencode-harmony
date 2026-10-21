import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';import{createRequire}from'node:module';import{resolve}from'node:path';
const require=createRequire(import.meta.url);const ts=require(resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const code=ts.transpileModule(readFileSync('entry/src/main/ets/domain/ModelSelection.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const{matchingModels,modelInputs,quickModels}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
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
console.log(count+' model selection tests passed.');
