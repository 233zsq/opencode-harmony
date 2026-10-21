import assert from 'node:assert/strict';
import {execFileSync} from 'node:child_process';
import {readFileSync,mkdirSync} from 'node:fs';
import {resolve} from 'node:path';
const hdc=resolve(process.env.DEVECO_STUDIO_HOME||'C:/Program Files/Huawei/DevEco Studio','sdk/default/openharmony/toolchains/hdc.exe');
export const pause=ms=>new Promise(r=>setTimeout(r,ms));
export const cmd=(...args)=>execFileSync(hdc,['-t',process.env.HDC_TARGET||'127.0.0.1:5555',...args],{encoding:'utf8',timeout:25000});
mkdirSync('.test',{recursive:true});
function flat(n,parent='',viewport='',listBounds='',parentVisible=true){const visible=parentVisible&&n.attributes.visible!=='false';const list=n.attributes.type==='List'?n.attributes.bounds:listBounds;const view=['Scroll','List'].includes(n.attributes.type)?n.attributes.bounds:viewport;return[{...n.attributes,visible:String(visible),parent,viewport:view,listBounds:list},...(n.children||[]).flatMap(c=>flat(c,n.attributes.id,view,list,visible))];}
export const bounds=n=>n.bounds.match(/-?\d+/g).map(Number);
export function layout(){cmd('shell','uitest dumpLayout -i -p /data/local/tmp/complete-ui.json');cmd('file','recv','/data/local/tmp/complete-ui.json',resolve('.test/complete-ui.json'));const roots=JSON.parse(readFileSync('.test/complete-ui.json','utf8'));return Array.isArray(roots)?roots.sort((a,b)=>Number(a.attributes.focused==='true')-Number(b.attributes.focused==='true')).flatMap(n=>flat(n)):flat(roots);}
const aliases={'open-menu':'__NavigationField__NavigationMenu__MenuItem2__native-navigation','native-back':'__NavdestinationField__BackButton__Back__native-destination'};
export const find=(q,nodes=layout())=>nodes.findLast(n=>n.visible!=='false'&&bounds(n)[2]>0&&bounds(n)[0]>=0&&bounds(n)[3]>0&&bounds(n)[1]<2832&&(n.id===q||n.text===q||(aliases[q]&&n.id===aliases[q])||(q==='open-sidebar'&&n.parent==='native-sidebar-container'&&n.type==='Button')));
export async function wait(q,timeout=14000){const end=Date.now()+timeout;do{const n=find(q);if(n)return n;await pause(300);}while(Date.now()<end);throw new Error('Native control missing: '+q);}
export async function tap(q){const n=typeof q==='string'?await wait(q):q;assert.ok(n);const b=bounds(n);cmd('shell','uitest uiInput click '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));await pause(450);}
export async function back(){cmd('shell','uitest uiInput keyEvent Back');await pause(1300);}
export async function reveal(q){
 for(let i=0;i<22;i++){
  const nodes=layout(),n=nodes.findLast(n=>(n.id===q||n.text===q)&&n.visible!=='false'&&bounds(n)[0]>=0&&bounds(n)[2]>0),b=n&&bounds(n);
  const screen=bounds(nodes.findLast(n=>n.type==='root')||nodes[0]);
  const chat=/^(choice-|field-|interaction-|approval-|copy-|message-|reasoning-|tool-row-|older-messages)/.test(q);
  const fallback=chat?nodes.find(n=>n.id==='conversation-list'&&n.visible!=='false'):nodes.findLast(n=>n.type==='Scroll'&&n.visible!=='false'&&bounds(n)[0]>=0);
  const viewport=n?(n.listBounds?bounds({bounds:n.listBounds}):n.viewport?bounds({bounds:n.viewport}):screen):fallback?bounds(fallback):screen;
  if(n&&n.visible!=='false'&&b[1]>=viewport[1]&&b[3]<=viewport[3]&&b[3]-b[1]>20)return n;
  const up=n?b[1]<viewport[1]+8:/^(copy-|message-|older-messages)/.test(q)||i>12;
  const x=Math.round((viewport[0]+viewport[2])/2),a=Math.round(viewport[1]+(viewport[3]-viewport[1])*(up?.3:.75)),z=Math.round(viewport[1]+(viewport[3]-viewport[1])*(up?.7:.3));
  cmd('shell','uitest uiInput swipe '+x+' '+a+' '+x+' '+z+' 450');await pause(250);
 }
 throw new Error('Cannot reveal: '+q);
}
export async function input(q,text){assert.ok(!text.includes("'"));await tap(await reveal(q));cmd('shell','uitest uiInput keyEvent 2072 2017');cmd('shell','uitest uiInput keyEvent 2055');if(text)cmd('shell',"uitest uiInput text '"+text+"'");await pause(350);}
export async function shot(name){cmd('shell','snapshot_display -f /data/local/tmp/complete-ui.jpeg');cmd('file','recv','/data/local/tmp/complete-ui.jpeg',resolve('.test/'+name+'.jpeg'));}
export async function menu(name){await tap('open-menu');await tap(await reveal(name));await pause(1000);}
