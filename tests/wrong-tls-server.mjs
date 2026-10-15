import https from 'node:https';
import { readFileSync,writeFileSync } from 'node:fs';
let reached=0;
const file=new URL('../.test/wrong-tls-receipts.json',import.meta.url);
writeFileSync(file,JSON.stringify({reached}));
https.createServer({key:readFileSync(new URL('../.server-access/tls/wrong.key',import.meta.url)),cert:readFileSync(new URL('../.server-access/tls/wrong.pem',import.meta.url))},(req,res)=>{
  reached++;writeFileSync(file,JSON.stringify({reached}));res.setHeader('Content-Type','application/json');res.end(JSON.stringify(req.url==='/api/info'?{version:'2.0.29'}:[]));
}).listen(4213,'127.0.0.1');
