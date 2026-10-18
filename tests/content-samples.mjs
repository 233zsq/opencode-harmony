// Synthetic fixtures only. No personal photo or document is read.
import {mkdirSync,writeFileSync} from 'node:fs';
import {deflateSync} from 'node:zlib';
import {resolve} from 'node:path';
const crc=data=>{let c=0xffffffff;for(const v of data){c^=v;for(let i=0;i<8;i++)c=(c>>>1)^((c&1)?0xedb88320:0);}return(c^0xffffffff)>>>0;};
function chunk(type,data){const t=Buffer.from(type),head=Buffer.alloc(4),tail=Buffer.alloc(4);head.writeUInt32BE(data.length);tail.writeUInt32BE(crc(Buffer.concat([t,data])));return Buffer.concat([head,t,data,tail]);}
const w=640,h=400,rows=Buffer.alloc(h*(w*3+1));for(let y=0;y<h;y++)for(let x=0;x<w;x++){const i=y*(w*3+1)+1+x*3;rows.set(x<w/2?[220,35,55]:[30,90,220],i);}
const header=Buffer.alloc(13);header.writeUInt32BE(w);header.writeUInt32BE(h,4);header[8]=8;header[9]=2;
const folder=resolve('.test/content-fixtures');mkdirSync(folder,{recursive:true});
writeFileSync(resolve(folder,'harmony-sample.png'),Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',header),chunk('IDAT',deflateSync(rows)),chunk('IEND',Buffer.alloc(0))]));
writeFileSync(resolve(folder,'harmony-sample.txt'),'HARMONY_ATTACHMENT_FIXTURE\n中文与 emoji 🌿\nOnly synthetic content, no private data.\n');
console.log('Prepared synthetic image and UTF-8 text in ignored .test/content-fixtures.');
