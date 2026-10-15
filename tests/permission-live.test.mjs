import https from 'node:https';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {endpoint,options,scope} from './live-api.mjs';
const fixture=process.env.OPENCODE_PERMISSION_SESSION&&process.env.OPENCODE_PERMISSION_DIRECTORY?{id:process.env.OPENCODE_PERMISSION_SESSION,directory:process.env.OPENCODE_PERMISSION_DIRECTORY}:JSON.parse(readFileSync('.test/approval-repro.json','utf8'));
const sessionID=process.env.OPENCODE_PERMISSION_SESSION||fixture.id;
const result=await new Promise((resolve,reject)=>{const request=https.get(endpoint+'/api/session/'+encodeURIComponent(sessionID)+'/permission?'+scope(process.env.OPENCODE_PERMISSION_DIRECTORY||fixture.directory),options(),response=>{let body='';response.setEncoding('utf8');response.on('data',chunk=>body+=chunk);response.on('end',()=>resolve({status:response.statusCode,body}));});request.on('error',reject);request.setTimeout(10000,()=>request.destroy(new Error('timeout')));});
if(result.status!==200){let message='';try{message=JSON.parse(result.body).message||'';}catch{}console.log('Approval list HTTP '+result.status+': '+message.slice(0,240));}
assert.equal(result.status,200,'A pending approval must remain readable');
const rows=JSON.parse(result.body).data;assert.ok(Array.isArray(rows));assert.ok(rows.length>0,'The test must exercise a real pending approval');
for(const permission of rows){assert.ok(permission.id);assert.equal(permission.sessionID,sessionID);assert.ok(Array.isArray(permission.resources));}
console.log('PASS real pending approvals are readable; '+rows.length+' request(s).');
