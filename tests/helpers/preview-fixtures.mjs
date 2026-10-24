import {deflateSync} from 'node:zlib';
export function previewPdf(){
 const stream=text=>{const body=`0.1 0.2 0.5 RG 2 w 20 20 260 360 re S\nBT /F1 16 Tf 35 320 Td (${text}) Tj ET\n`;return `<< /Length ${Buffer.byteLength(body)} >>\nstream\n${body}endstream`;};
 const objects=['<< /Type /Catalog /Pages 2 0 R >>','<< /Type /Pages /Kids [3 0 R 5 0 R] /Count 2 >>',
 '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 7 0 R >> >> /Contents 4 0 R >>',stream('NATIVE_PDF_PAGE_ONE'),
 '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 400] /Resources << /Font << /F1 7 0 R >> >> /Contents 6 0 R >>',stream('NATIVE_PDF_PAGE_TWO'),'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>'];
 let pdf='%PDF-1.4\n',offsets=[0];for(let i=0;i<objects.length;i++){offsets.push(Buffer.byteLength(pdf));pdf+=`${i+1} 0 obj\n${objects[i]}\nendobj\n`;}
 const xref=Buffer.byteLength(pdf);pdf+='xref\n0 8\n0000000000 65535 f \n'+offsets.slice(1).map(n=>String(n).padStart(10,'0')+' 00000 n \n').join('')+`trailer\n<< /Size 8 /Root 1 0 R >>\nstartxref\n${xref}\n%%EOF\n`;return Buffer.from(pdf);
}
function crc32(bytes){let crc=0xffffffff;for(const byte of bytes){crc^=byte;for(let i=0;i<8;i++)crc=(crc>>>1)^((crc&1)?0xedb88320:0);}return(crc^0xffffffff)>>>0;}
export function previewPng(){const chunk=(name,bytes)=>{const type=Buffer.from(name),length=Buffer.alloc(4),crc=Buffer.alloc(4);length.writeUInt32BE(bytes.length);crc.writeUInt32BE(crc32(Buffer.concat([type,bytes])));return Buffer.concat([length,type,bytes,crc]);};
 const info=Buffer.alloc(13);info.writeUInt32BE(32,0);info.writeUInt32BE(24,4);info[8]=8;info[9]=2;const raw=Buffer.alloc(24*(1+32*3));for(let y=0;y<24;y++)for(let x=0;x<32;x++){const p=y*97+1+x*3;raw[p]=x*8;raw[p+1]=y*10;raw[p+2]=160;}
 return Buffer.concat([Buffer.from([137,80,78,71,13,10,26,10]),chunk('IHDR',info),chunk('IDAT',deflateSync(raw)),chunk('IEND',Buffer.alloc(0))]);}
