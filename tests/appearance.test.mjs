import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import vm from 'node:vm';
const require=createRequire(import.meta.url);
const ts=require(resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
function harness(initial='system',fail=false){
 const values=new Map([['mode',initial]]),storage=new Map(),calls=[];let color=1,flushed=0;
 const context={getApplicationContext:()=>({setColorMode:mode=>{calls.push(mode);color=mode===0?0:1;}}),resourceManager:{getConfigurationSync:()=>({colorMode:color})}};
 const prefs={getSync:key=>values.get(key),get:async key=>values.get(key),put:async(key,value)=>values.set(key,value),flush:async()=>{if(fail)throw new Error('disk full');flushed++;}};
 const exports={};const code=ts.transpileModule(readFileSync(new URL('../entry/src/main/ets/presentation/Appearance.ets',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 vm.runInNewContext(code,{exports,Error,AppStorage:{setOrCreate:(key,value)=>storage.set(key,value)},require:name=>name==='@kit.AbilityKit'?{ConfigurationConstant:{ColorMode:{COLOR_MODE_DARK:0,COLOR_MODE_LIGHT:1,COLOR_MODE_NOT_SET:-1}}}:name==='@kit.ArkData'?{preferences:{getPreferencesSync:(_,options)=>{assert.equal(options.name,'opencode_appearance');return prefs;},getPreferences:async(_,options)=>{assert.equal(options.name,'opencode_appearance');return prefs;}}}:(()=>{throw new Error('Unexpected dependency');})()});
 return{appearance:exports.Appearance,context,values,storage,calls,flushed:()=>flushed};
}
const fallback=harness('invalid');await fallback.appearance.restore(fallback.context);assert.equal(fallback.storage.get('appearanceMode'),'system');assert.deepEqual(fallback.calls,[-1]);console.log('PASS corrupt appearance preference falls back to system without affecting connection settings');
const dark=harness();await dark.appearance.save(dark.context,'dark');assert.equal(dark.values.get('mode'),'dark');assert.equal(dark.flushed(),1);assert.equal(dark.storage.get('appearanceDark'),true);assert.deepEqual(dark.calls,[0]);await dark.appearance.restore(dark.context);assert.equal(dark.storage.get('appearanceMode'),'dark');console.log('PASS app-local dark appearance persists and restores before rendering');
const failure=harness('light',true);await failure.appearance.restore(failure.context);await assert.rejects(failure.appearance.save(failure.context,'dark'),/外观设置未保存/);assert.equal(failure.storage.get('appearanceMode'),'light');assert.deepEqual(failure.calls,[1]);console.log('PASS failed preference flush preserves visible appearance and reports failure');
console.log('3 appearance tests passed.');
