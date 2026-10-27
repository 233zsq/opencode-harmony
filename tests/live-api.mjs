import https from 'node:https';
import tls from 'node:tls';
import {createHash,X509Certificate} from 'node:crypto';
import {liveConfig} from './helpers/live-config.mjs';
const {endpoint,ca,pin,auth}=liveConfig();
export {endpoint};
export function options(method='GET') {
 const result={method,agent:false,ca,rejectUnauthorized:true,headers:{Authorization:auth,Accept:'application/json'}};
 if(pin)result.checkServerIdentity=(host,cert)=>{
  const error=tls.checkServerIdentity(host,cert);if(error)return error;
  const key=new X509Certificate(cert.raw).publicKey.export({type:'spki',format:'der'});
  return createHash('sha256').update(key).digest('base64')===pin?undefined:new Error('Server SPKI mismatch');
 };
 return result;
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
