import assert from 'node:assert/strict';
import plugin from '../server/permission-json/index.js';
let hook;await plugin.setup({permission:{hook:async(name,callback)=>{assert.equal(name,'evaluate');hook=callback;return{dispose:async()=>{}};}}});
let count=0;const test=(name,run)=>{try{run();console.log('PASS '+name);count++;}catch(error){console.error('FAIL '+name+': '+error.message);process.exit(1);}};
const event=(metadata,effect='ask')=>({sessionID:'ses_test',action:'glob',resources:['**/*.ts'],effect,metadata,source:{type:'tool',messageID:'msg_test',id:'call_test'}});
test('real glob optional fields are omitted before the shared pending request is encoded',()=>{
 const metadata={root:'.',path:undefined,hidden:undefined,limit:undefined};const pending={metadata};const e=event(metadata);hook(e);
 assert.equal(pending.metadata,metadata);assert.deepEqual(pending.metadata,{root:'.'});assert.equal(e.effect,'ask');assert.deepEqual(e.resources,['**/*.ts']);assert.equal(e.source.id,'call_test');
});
test('edit patches and false zero empty null metadata remain exact',()=>{
 const metadata={files:[{file:'greeting.ts',patch:'@@ -1 +1 @@\n-old\n+new\n',additions:1,deletions:1}],flag:false,zero:0,empty:'',nil:null};const expected=structuredClone(metadata);hook(event(metadata));assert.deepEqual(metadata,expected);
});
test('nested undefined is omitted and array positions remain stable',()=>{
 const metadata={nested:{missing:undefined,keep:'yes'},values:[undefined,0,false,null,,{missing:undefined,keep:1}]};hook(event(metadata));assert.deepEqual(metadata,{nested:{keep:'yes'},values:[null,0,false,null,null,{keep:1}]});
});
test('permission decisions and scope are never widened',()=>{
 for(const effect of ['ask','allow','deny']){const e=event({path:undefined},effect);const resources=e.resources;hook(e);assert.equal(e.effect,effect);assert.equal(e.resources,resources);assert.equal(e.action,'glob');assert.equal(e.sessionID,'ses_test');}
});
test('invalid cyclic and non-JSON metadata fails closed',()=>{
 const cycle={};cycle.self=cycle;assert.throws(()=>hook(event(cycle)),/JSON/);assert.throws(()=>hook(event({bad:NaN})),/JSON/);assert.throws(()=>hook(event({bad:1n})),/JSON/);
});
test('shared nested values are valid and omitted metadata is safe',()=>{
 const value={a:1};const e=event({left:value,right:value});hook(e);assert.equal(e.metadata.left,e.metadata.right);hook(event(undefined));
});
console.log(count+' permission metadata tests passed.');
