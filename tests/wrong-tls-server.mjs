import https from 'node:https';
import {writeFileSync,mkdirSync} from 'node:fs';
import {tlsFixture} from './helpers/live-config.mjs';
const fixture=tlsFixture();
let reached=0;
const file=new URL('../.test/wrong-tls-receipts.json',import.meta.url);
mkdirSync(new URL('../.test/',import.meta.url),{recursive:true});
writeFileSync(file,JSON.stringify({reached}));
https.createServer(fixture,(req,res)=>{
  reached++;writeFileSync(file,JSON.stringify({reached}));res.setHeader('Content-Type','application/json');res.end(JSON.stringify(req.url==='/api/info'?{version:'2.0.29'}:[]));
}).listen(4213,'127.0.0.1');
