import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const luminance=hex=>{assert.match(hex,/^#[0-9a-f]{6}$/i,'Reading surface must be opaque for this calculation');const [r,g,b]=hex.slice(-6).match(/../g).map(value=>{const v=parseInt(value,16)/255;return v<=.04045?v/12.92:((v+.055)/1.055)**2.4;});return .2126*r+.7152*g+.0722*b;};
const contrast=(a,b)=>(Math.max(luminance(a),luminance(b))+.05)/(Math.min(luminance(a),luminance(b))+.05);
for(const mode of ['base','dark']){
 const palette=Object.fromEntries(JSON.parse(readFileSync(new URL('../entry/src/main/resources/'+mode+'/element/color.json',import.meta.url))).color.map(c=>[c.name,c.value]));
 for(const text of ['ui_text','ui_secondary','ui_muted'])for(const surface of ['ui_page','ui_surface','ui_field','ui_sidebar','ui_bubble','ui_chip'])assert.ok(contrast(palette[text],palette[surface])>=4.5,mode+' '+text+' on '+surface+' contrast '+contrast(palette[text],palette[surface]).toFixed(2));
 for(const [text,surface]of [['ui_btn_text','ui_btn'],['ui_code_text','ui_code_bg']])assert.ok(contrast(palette[text],palette[surface])>=4.5,mode+' '+text+' contrast');
 console.log('PASS '+mode+' text, hints, buttons and code meet 4.5:1 on their opaque reading surfaces.');
}
console.log('2 UI palette contrast tests passed; translucent materials still require visual acceptance.');
