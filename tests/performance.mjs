import { ts } from './helpers/typescript.mjs';
// Synthetic Node benchmark; device frame rate and real large repositories require separate acceptance.
import assert from 'node:assert/strict';
import {performance} from 'node:perf_hooks';
import {readFileSync,writeFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';

const code=ts.transpileModule(readFileSync('entry/src/main/ets/domain/Core.ts','utf8'),{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const core=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
const results=[];function scenario(name,run){const start=performance.now();const detail=run();results.push({name,milliseconds:Math.round((performance.now()-start)*100)/100,...detail});}
scenario('50000 message merge preserves IDs, order and unchanged object references',()=>{
 const messages=Array.from({length:50000},(_,i)=>({id:'m'+i,role:'assistant',text:'reply '+i,reasoning:'',parts:[],tools:[],state:'completed'}));
 const merged=core.mergeMessages(messages,messages.slice(-100).map(m=>({...m})));assert.equal(merged,messages);return{messages:merged.length};
});
scenario('1000 history pages retain a bounded 300-message window',()=>{
 let window=[];for(let page=0;page<1000;page++){
  const incoming=Array.from({length:30},(_,i)=>({id:'m'+(page*30+i),role:'assistant',text:'中文回复',reasoning:'',parts:[],tools:[],state:'completed'}));
  window=core.mergeMessages(window,incoming).slice(-300);assert.ok(window.length<=300);
 }assert.equal(window.at(-1).id,'m29999');return{pages:1000,window:window.length};
});
scenario('100000-line Diff preview is bounded and reports truncation',()=>{
 const patch='@@ -1 +1 @@\n'+Array.from({length:100000},(_,i)=>'+line '+i).join('\n');const preview=core.previewText(patch);assert.equal(preview.truncated,true);assert.ok(core.parseDiff(preview.text).length<=1500);return{sourceLines:100000,previewLines:core.parseDiff(preview.text).length};
});
scenario('large Markdown input respects the rendering text bound',()=>{
 const text='# Heading\n\n'+('Long paragraph.\n\n'.repeat(20000));const blocks=core.parseMarkdown(text);assert.ok(blocks.map(b=>b.text).join('').length<=200000);return{sourceCharacters:text.length,blocks:blocks.length};
});
mkdirSync('.test',{recursive:true});writeFileSync('.test/performance.json',JSON.stringify({runtime:process.version,results},null,2));
for(const result of results)console.log('PASS '+result.name+' ('+result.milliseconds+' ms)');
console.log('4 synthetic load scenarios passed; timings are Node-only.');
