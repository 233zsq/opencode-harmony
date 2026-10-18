// Real soft-keyboard geometry and Chinese multiline input; never sends a message.
import assert from 'node:assert/strict';
import {writeFileSync} from 'node:fs';
import {layout,find,tap,pause,input,bounds,cmd,shot,back} from './native-driver.mjs';
if(find('chat-input')?.text){console.log('SKIP preserving user draft');process.exit(0);}
const lines=['第一行 中文','第二行 多行输入','第三行'];
try{
 await tap('chat-input');await pause(900);
 for(let i=0;i<lines.length;i++){if(i)cmd('shell','uitest uiInput keyEvent 2054');cmd('shell',"uitest uiInput text '"+lines[i]+"'");await pause(180);}
 const nodes=layout(),keyboard=find('SkinBgContent',nodes),area=find('chat-input',nodes),send=find('send-button',nodes);
 assert.ok(keyboard,'Visible native keyboard background missing');assert.equal(area.text,lines.join('\n'));assert.ok(bounds(area)[3]<=bounds(keyboard)[1]);assert.ok(bounds(send)[3]<=bounds(keyboard)[1]);
 const result={keyboard:bounds(keyboard),input:bounds(area),send:bounds(send),lines:3};writeFileSync('.test/native-keyboard-geometry.json',JSON.stringify(result,null,2));await shot('content-native-keyboard');console.log('PASS visible native keyboard avoids Chinese multiline input and send button; no message submitted.');
}finally{
 const area=find('chat-input');if(area?.text===lines.join('\n')){await input('chat-input','');await back();}
}
