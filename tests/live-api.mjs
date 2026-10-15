import https from 'node:https';
import tls from 'node:tls';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {createHash,X509Certificate} from 'node:crypto';
const root=resolve(import.meta.dirname,'..');
export const endpoint=process.env.OPENCODE_TEST_URL;
if(!endpoint?.startsWith('https://'))throw new Error('Set OPENCODE_TEST_URL to dedicated server');
const env=Object.fromEntries(readFileSync(resolve(root,'.server-access/server.env'),'utf8').trim().split(/\r?\n/).map(line=>{const i=line.indexOf('=');return[line.slice(0,i),line.slice(i+1)];}));
const ca=readFileSync(resolve(root,'.server-access/tls/ca.pem'),'utf8');
const pin=JSON.parse(readFileSync(resolve(root,'.server-access/tls/public-trust.json'),'utf8')).pin;
const auth='Basic '+Buffer.from('opencode:'+env.OPENCODE_PASSWORD).toString('base64');
export function options(method='GET') {
 return {method,agent:false,ca,headers:{Authorization:auth,Accept:'application/json'},checkServerIdentity:(host,cert)=>{
  const error=tls.checkServerIdentity(host,cert);if(error)return error;
  const key=new X509Certificate(cert.raw).publicKey.export({type:'spki',format:'der'});
  return createHash('sha256').update(key).digest('base64')===pin?undefined:new Error('Server SPKI mismatch');
 }};
}
export function api(path,method='GET',body) {
 return new Promise((resolve,reject)=>{
  const opts=options(method);if(body!==undefined)opts.headers['Content-Type']='application/json';
  const req=https.request(endpoint+path,opts,res=>{let text='';res.on('data',part=>text+=part);res.on('end',()=>{
   if(res.statusCode<200||res.statusCode>=300)return reject(new Error('API '+method+' '+path.split('?')[0]+' HTTP '+res.statusCode));
   try{resolve(text?JSON.parse(text):{});}catch{resolve(text);}
  });});
  req.on('error',error=>reject(new Error('API network error: '+(error.code||'TLS'))));req.setTimeout(25000,()=>req.destroy(new Error('timeout')));req.end(body===undefined?undefined:JSON.stringify(body));
 });
}
export function scope(directory){return 'location%5Bdirectory%5D='+encodeURIComponent(directory);}
export const pause=ms=>new Promise(resolve=>setTimeout(resolve,ms));
