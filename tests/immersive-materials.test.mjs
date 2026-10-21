import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createRequire} from 'node:module';
import {resolve} from 'node:path';
import vm from 'node:vm';
const require=createRequire(import.meta.url);
const ts=require(resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const source=readFileSync(new URL('../entry/src/main/ets/presentation/ImmersiveMaterials.ets',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
function harness(version,{available=true,failed=false}={}) {
 const exports={},calls=[];let loads=0,versionChecks=0;
 const device={sdkApiVersion:version};
 if(version>=26)device.apiAvailable=value=>{versionChecks++;assert.equal(value,'26.0.0');return available;};
 vm.runInNewContext(code,{exports,require:name=>{
  if(name==='@ohos.deviceInfo')return{default:device};
  assert.equal(name,'@ohos.arkui.uiMaterial');loads++;if(failed)throw new Error('Native module unavailable');
  return{default:{ImmersiveStyle:{THIN:1,REGULAR:2},ImmersiveMaterial:class{constructor(options){this.options=options;calls.push(options);}}}};
 }});
 return{load:exports.loadImmersiveMaterials,calls,loads:()=>loads,versionChecks:()=>versionChecks};
}
const older=harness(24);assert.equal(Object.keys(await older.load()).length,0);assert.equal(older.loads(),0);assert.equal(older.versionChecks(),0);console.log('PASS API24 never loads or invokes API26-only native interfaces');
const supported=harness(26),surfaces=await supported.load();assert.equal(surfaces.popup.options.style,1);assert.equal(surfaces.sheet.options.style,2);assert.ok(surfaces.popup.options.lightEffect);assert.equal(supported.loads(),1);console.log('PASS API26 creates separate thin popup and regular sheet materials');
const disabled=harness(26,{available:false});assert.equal(Object.keys(await disabled.load()).length,0);assert.equal(disabled.loads(),0);console.log('PASS unavailable capability preserves the portable blur fallback');
const failure=harness(26,{failed:true});assert.equal(Object.keys(await failure.load()).length,0);assert.equal(failure.loads(),1);console.log('PASS native import failure falls back without breaking app startup');
console.log('4 immersive material compatibility tests passed.');
