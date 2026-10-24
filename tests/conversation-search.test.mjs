import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {ts} from './helpers/typescript.mjs';
import vm from 'node:vm';
const source=readFileSync(new URL('../entry/src/main/ets/domain/ConversationSearch.ts',import.meta.url),'utf8');
const code=ts.transpileModule(source,{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const {searchConversation}=await import('data:text/javascript;base64,'+Buffer.from(code).toString('base64'));
const message=(id,text,role='assistant')=>({id,text,role,reasoning:'',tools:[],files:[],parts:[],state:'completed'});
let count=0;function test(name,run){run();count++;console.log('PASS '+name);}
test('literal query, case-insensitive text and newest-first results',()=>{
 const messages=[message('a','Hello [a.*]'),message('b','HELLO [a.*]')];assert.deepEqual(searchConversation(messages,'hello').map(h=>h.id),['b','a']);assert.equal(searchConversation(messages,'[a.*]').length,2);assert.equal(searchConversation(messages,'.*]').length,2);
});
test('role filters preserve the source and exclude other authors',()=>{
 const messages=[message('u','needle','user'),message('a','needle')],before=JSON.stringify(messages);assert.deepEqual(searchConversation(messages,'needle','user').map(h=>h.id),['u']);assert.equal(JSON.stringify(messages),before);
});
test('reasoning and tool input/output are opt-in and their source is identified',()=>{
 const m=message('a','body');m.reasoning='private reasoning';m.tools=[{name:'read',input:'needle-input',output:'needle-output'}];assert.equal(searchConversation([m],'private').length,0);assert.equal(searchConversation([m],'private','',true)[0].label,'思考');assert.equal(searchConversation([m],'needle-output','',true)[0].label,'工具 · read');
});
test('file names are searchable without reading or matching file bytes',()=>{
 const m=message('a','');m.files=[{name:'报告.pdf',data:'secret-base64'}];assert.equal(searchConversation([m],'报告')[0].label,'附件名称');assert.equal(searchConversation([m],'secret').length,0);
});
test('Chinese and emoji hits retain intact snippets',()=>{
 const m=message('a','😀'.repeat(25)+'中文😀关键词'+'😀'.repeat(60));const h=searchConversation([m],'😀关键词')[0];assert.equal(h.match,'😀关键词');assert.ok(!/[\uD800-\uDBFF]$/.test(h.before));assert.ok(!/^[\uDC00-\uDFFF]/.test(h.after));
});
test('Unicode case expansion does not shift the highlighted original substring',()=>{
 const h=searchConversation([message('a','İ xx NEEDLE end')],'needle')[0];assert.equal(h.match,'NEEDLE');assert.ok(h.before.includes('İ xx '));
});
test('empty and long queries are bounded and duplicate IDs do not repeat',()=>{
 const m=message('a','x'.repeat(150));assert.equal(searchConversation([m],'   ').length,0);assert.equal(searchConversation([m,m],'x'.repeat(150)).length,1);assert.equal(searchConversation([m],'x'.repeat(150))[0].match.length,120);
});
test('lookup remains within the loaded 300-message window',()=>{
 const messages=Array.from({length:330},(_,i)=>message('m'+i,'needle'));assert.equal(searchConversation(messages,'needle').length,300);assert.equal(searchConversation(messages,'needle').at(-1).id,'m30');
});
test('query bounds never split an emoji',()=>{const query='x'+'😀'.repeat(120);const hit=searchConversation([message('a',query)],query)[0];assert.ok(!/[\uD800-\uDBFF]$/.test(hit.match));assert.equal(Array.from(hit.match).length,120);});

// Run the actual Index event handlers together with the real search/core functions.
// ArkUI rendering is checked separately; no copied state transition is used here.
const coreCode=ts.transpileModule(readFileSync(new URL('../entry/src/main/ets/domain/Core.ts',import.meta.url),'utf8'),{compilerOptions:{module:ts.ModuleKind.ES2022,target:ts.ScriptTarget.ES2022}}).outputText;
const {reasoningInProgress}=await import('data:text/javascript;base64,'+Buffer.from(coreCode).toString('base64'));
const indexSource=readFileSync(new URL('../entry/src/main/ets/pages/Index.ets',import.meta.url),'utf8');
const methods=['locateMessage','reasoningExpanded','toggleReasoning'].map(name=>{const match=indexSource.match(new RegExp('^  private '+name+'\\([^]*?^  }','m'));assert.ok(match,'Actual Index handler: '+name);return match[0];}).join('\n');
function navigationFixture(messages){
 const exports={},timers=[],scrolls=[],toasts=[];
 const code=ts.transpileModule('export class Navigation {\n'+methods+'\n}',{compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText;
 vm.runInNewContext(code,{exports,reasoningInProgress,setTimeout:fn=>{timers.push(fn);return timers.length;},clearTimeout:()=>{},ScrollAlign:{CENTER:'center'}});
 const ui=new exports.Navigation();Object.assign(ui,{store:{messages,cursor:'older',pane:'panel-search',exportScope:()=> 'same-session'},reasoningOpen:[],reasoningClosed:[],follow:true,focusedMessage:'',scrollTimer:-1,scroller:{scrollToIndex:(...args)=>scrolls.push(args)},navigate:pane=>{ui.store.pane=pane;},toast:text=>toasts.push(text)});
 return{ui,scrolls,toasts,flush:()=>timers.splice(0).forEach(fn=>fn())};
}
const thinking=(id)=>({...message(id,'visible answer'),reasoning:'unique reasoning needle',state:'streaming',parts:[{type:'reasoning',text:'unique reasoning needle',ended:false}]});
test('a reasoning search hit reopens manually collapsed in-progress content and preserves other folds',()=>{
 const other=thinking('other'),target=thinking('target'),{ui,scrolls,flush}=navigationFixture([other,target]);ui.reasoningOpen=['target'];ui.toggleReasoning(other);ui.toggleReasoning(target);assert.equal(ui.reasoningExpanded(target),false);
 const hit=searchConversation([target],'unique reasoning','',true)[0];assert.equal(hit.label,'思考');ui.locateMessage(hit);
 assert.equal(ui.reasoningExpanded(target),true,'Selecting the hit must reveal the actual matching content');assert.equal(ui.reasoningExpanded(other),false);assert.equal(ui.reasoningOpen.filter(id=>id==='target').length,1);
 assert.equal(ui.focusedMessage,'target');assert.equal(ui.follow,false);assert.equal(ui.store.pane,'chat');flush();assert.deepEqual(scrolls,[[2,false,'center']]);
});
test('completed reasoning hits still expand without duplicating the open state',()=>{
 const target={...thinking('target'),state:'completed',parts:[{type:'reasoning',ended:true}]},{ui}=navigationFixture([target]);const hit=searchConversation([target],'unique reasoning','',true)[0];
 assert.equal(ui.reasoningExpanded(target),false);ui.locateMessage(hit);ui.locateMessage(hit);assert.equal(ui.reasoningExpanded(target),true);assert.equal(ui.reasoningOpen.filter(id=>id==='target').length,1);
});
test('a body-only search hit preserves the manually collapsed reasoning',()=>{
 const target=thinking('target'),{ui}=navigationFixture([target]);ui.toggleReasoning(target);const hit=searchConversation([target],'visible answer','',true)[0];assert.equal(hit.label,'助手回复');ui.locateMessage(hit);assert.equal(ui.reasoningExpanded(target),false);
});
test('a search result outside the loaded window leaves folds and navigation unchanged',()=>{
 const target=thinking('target'),{ui,scrolls,toasts,flush}=navigationFixture([target]);ui.toggleReasoning(target);ui.locateMessage({id:'removed',label:'思考'});assert.equal(ui.reasoningExpanded(target),false);assert.equal(ui.store.pane,'panel-search');assert.equal(toasts.length,1);flush();assert.equal(scrolls.length,0);
});

console.log(count+' conversation search tests passed.');
