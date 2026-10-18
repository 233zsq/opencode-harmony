// Native multiline input check; never presses Send or calls an Agent.
import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
const hdc=resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/toolchains/hdc.exe');
const target=process.env.HDC_TARGET||'127.0.0.1:5555',density=Number(process.env.UI_DENSITY||3.5);
const cmd=(...args)=>execFileSync(hdc,['-t',target,...args],{encoding:'utf8',timeout:25000});const pause=ms=>new Promise(r=>setTimeout(r,ms));
mkdirSync('.test',{recursive:true});
function flat(n){return[n.attributes,...(n.children||[]).flatMap(flat)];}
function layout(){cmd('shell','uitest dumpLayout -p /data/local/tmp/opencode-composer.json');cmd('file','recv','/data/local/tmp/opencode-composer.json',resolve('.test/composer-layout.json'));return flat(JSON.parse(readFileSync('.test/composer-layout.json','utf8')));}
const b=n=>n.bounds.match(/-?\d+/g).map(Number);
async function tap(n){const a=b(n);cmd('shell','uitest uiInput click '+Math.round((a[0]+a[2])/2)+' '+Math.round((a[1]+a[3])/2));await pause(350);}
let nodes=layout();let input=nodes.find(n=>n.id==='chat-input');assert.ok(input,'Chat input missing');
if(input.text){console.log('SKIP native composer input: preserving existing user draft.');process.exit(0);}
const jump=nodes.find(n=>n.id==='jump-latest'&&n.visible!=='false');if(jump){await tap(jump);nodes=layout();input=nodes.find(n=>n.id==='chat-input');}
const beforeHeight=(b(input)[3]-b(input)[1])/density;const lines=['Layout first line','Layout second line','Layout third line'];
try{
 await tap(input);await pause(700);
 for(let i=0;i<lines.length;i++){
  if(i)cmd('shell','uitest uiInput keyEvent 2054');
  cmd('shell',"uitest uiInput text '"+lines[i]+"'");await pause(250);
 }
 nodes=layout();input=nodes.find(n=>n.id==='chat-input');assert.equal(input.text,lines.join('\n'),'Native Enter should insert newlines');
 const height=(b(input)[3]-b(input)[1])/density;assert.ok(height>beforeHeight&&height<=148,'Composer did not expand within its limit');
 const send=nodes.find(n=>n.id==='send-button');assert.ok(send);assert.ok(Math.abs(b(send)[3]-b(input)[3])<=6*density,'Send button should stay aligned to the bottom of multiline input');
 cmd('shell','snapshot_display -f /data/local/tmp/opencode-composer.jpeg');cmd('file','recv','/data/local/tmp/opencode-composer.jpeg',resolve('.test/composer-multiline.jpeg'));
 console.log('PASS native three-line input expands '+beforeHeight.toFixed(1)+' -> '+height.toFixed(1)+'vp, with send aligned at the bottom; nothing submitted.');
 const keyboard=nodes.find(n=>n.bundleName==='com.huawei.hmos.inputmethod'&&n.type==='WindowScene'&&b(n)[3]-b(n)[1]>300);
 if(keyboard){assert.ok(b(input)[3]<=b(keyboard)[1]);console.log('PASS composer remains above the visible native keyboard.');}
 else console.log('SKIP soft keyboard geometry: the emulator does not expose a visible keyboard window.');
}finally{
 nodes=layout();input=nodes.find(n=>n.id==='chat-input');
 if(input&&input.text&&input.text.split('\n').every(line=>lines.includes(line))){
  await tap(input);cmd('shell','uitest uiInput keyEvent 2072 2017');await pause(200);cmd('shell','uitest uiInput keyEvent 2055');await pause(250);
  assert.equal(layout().find(n=>n.id==='chat-input').text,'','Test draft was not cleared');
 }
 if(layout().some(n=>n.bundleName==='com.huawei.hmos.inputmethod')){cmd('shell','uitest uiInput keyEvent Back');await pause(350);}
}
