// Native layout regression, API26 simulator by default. Override UI_DENSITY for another device.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
const density=Number(process.env.UI_DENSITY||3.5);assert.ok(density>0);
const hdc=resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/toolchains/hdc.exe');
const target=process.env.HDC_TARGET||'127.0.0.1:5555';mkdirSync('.test',{recursive:true});
const snapshot=process.argv[2]==='--snapshot'?process.argv[3]:'.test/chat-layout.json';
if(process.argv[2]!=='--snapshot'){
 execFileSync(hdc,['-t',target,'shell','uitest dumpLayout -p /data/local/tmp/opencode-chat-layout.json'],{stdio:'pipe'});
 execFileSync(hdc,['-t',target,'file','recv','/data/local/tmp/opencode-chat-layout.json',resolve(snapshot)],{stdio:'pipe'});
}
const tree=JSON.parse(readFileSync(snapshot,'utf8')),nodes=[],parents=new Map();
function visit(n,parent){nodes.push(n);if(parent)parents.set(n,parent);for(const child of n.children||[])visit(child,n);}visit(tree);
const b=n=>(n.attributes.bounds||'').match(/-?\d+/g).map(Number);const shown=n=>n.attributes.visible!=='false';
const all=n=>[n,...(n.children||[]).flatMap(all)];
const list=nodes.find(n=>n.attributes.id==='conversation-list');assert.ok(list,'Conversation list missing');
const failures=[],metrics=[];const check=(name,value,max)=>{metrics.push(name+': '+value.toFixed(1)+'vp (max '+max+')');if(value>max)failures.push(name);};
for(const row of nodes.filter(n=>shown(n)&&(n.attributes.id||'').startsWith('reasoning-toggle-'))){
 const card=parents.get(row),message=parents.get(card);if(!card||!message)continue;
 if(all(card).some(n=>(n.attributes.id||'').startsWith('reasoning-content-')))continue;
 const following=(message.children||[]).slice(message.children.indexOf(card)+1).find(n=>shown(n)&&n.attributes.type==='Column'&&all(n).some(c=>c.attributes.type==='Text'));
 if(following&&b(card)[3]<b(list)[3]-5&&b(card)[1]>=b(list)[1])check('collapsed reasoning to content',(b(following)[1]-b(card)[3])/density,10);
}
for(const item of list.children||[]){
 const rows=all(item).filter(n=>(n.attributes.id||'').startsWith('tool-row-'));if(!rows.length)continue;
 const last=rows.at(-1),index=list.children.indexOf(item),next=list.children[index+1];if(!next)continue;
 const reasoning=all(next).find(n=>(n.attributes.id||'').startsWith('reasoning-toggle-'));
 if(reasoning&&b(last)[3]>=b(list)[1]&&b(reasoning)[3]<b(list)[3])check('tools to next reasoning',(b(parents.get(reasoning))[1]-b(last)[3])/density,24);
}
const input=nodes.find(n=>n.attributes.id==='chat-input');assert.ok(input,'Composer missing');
if(!(input.attributes.text||'').trim())check('empty input height',(b(input)[3]-b(input)[1])/density,48);
const composer=parents.get(parents.get(input));
for(const row of composer.children||[]){
 if(row.attributes.type==='Row'&&all(row).every(n=>!['Button','Text','TextArea','SymbolGlyph'].includes(n.attributes.type)))check('empty composer toolbar',(b(row)[3]-b(row)[1])/density,0);
}
if(process.env.REQUIRE_CHAT_CARDS==='1'){
 assert.ok(metrics.some(m=>m.startsWith('collapsed reasoning to content:')),'Scroll a collapsed reasoning block and its following text into view.');
 assert.ok(metrics.some(m=>m.startsWith('tools to next reasoning:')),'Scroll adjacent tool and reasoning blocks into view.');
}
for(const metric of metrics)console.log(metric);
assert.equal(failures.length,0,'Excessive spacing: '+failures.join(', '));
console.log('PASS native reasoning/tool spacing and compact composer ('+metrics.length+' measurements).');
