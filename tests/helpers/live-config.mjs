import {readFileSync} from 'node:fs';

function required(env, name) {
 const value=env[name];
 if(typeof value!=='string'||!value.length)throw new Error('Set '+name+' explicitly for this test');
 return value;
}

export function testEndpoint(env=process.env) {
 const value=required(env,'OPENCODE_TEST_URL');let parsed;
 try{parsed=new URL(value);}catch{throw new Error('OPENCODE_TEST_URL must be an HTTPS base URL');}
 if(parsed.protocol!=='https:'||parsed.username||parsed.password||parsed.href.includes('?')||parsed.href.includes('#'))
  throw new Error('OPENCODE_TEST_URL must use HTTPS without credentials, query or fragment');
 return parsed.href.replace(/\/+$/,'');
}

export function liveCredentials(env=process.env) {
 const username=required(env,'OPENCODE_TEST_USERNAME'),password=required(env,'OPENCODE_TEST_PASSWORD');
 if(!username.trim()||username.includes(':')||/[\u0000-\u001f\u007f]/.test(username))
  throw new Error('OPENCODE_TEST_USERNAME must be nonblank and contain no colon or control characters');
 if(/[\u0000-\u001f\u007f]/.test(password))throw new Error('OPENCODE_TEST_PASSWORD must contain no control characters');
 return {username,password};
}

function readExplicitFile(env, name, readText) {
 const path=required(env,name);
 try{return readText(path,'utf8');}catch{throw new Error('Unable to read '+name);}
}

export function liveConfig(env=process.env,{readText=readFileSync}={}) {
 const endpoint=testEndpoint(env),{username,password}=liveCredentials(env);
 const pin=env.OPENCODE_TEST_PIN||undefined;
 if(pin&&(typeof pin!=='string'||!/^[A-Za-z0-9+/]{43}=$/.test(pin)||Buffer.from(pin,'base64').toString('base64')!==pin))
  throw new Error('OPENCODE_TEST_PIN must be a base64 SHA-256 SPKI digest');
 if(env.OPENCODE_TEST_CA_FILE&&!pin)throw new Error('Set OPENCODE_TEST_PIN with OPENCODE_TEST_CA_FILE');
 const ca=env.OPENCODE_TEST_CA_FILE?readExplicitFile(env,'OPENCODE_TEST_CA_FILE',readText):undefined;
 return {endpoint,username,password,ca,pin,auth:'Basic '+Buffer.from(username+':'+password).toString('base64')};
}

export function tlsFixture(env=process.env,{readText=readFileSync}={}) {
 // Validate both names before reading either file. No implicit operation directory.
 required(env,'OPENCODE_TLS_FIXTURE_KEY_FILE');required(env,'OPENCODE_TLS_FIXTURE_CERT_FILE');
 return {key:readExplicitFile(env,'OPENCODE_TLS_FIXTURE_KEY_FILE',readText),
         cert:readExplicitFile(env,'OPENCODE_TLS_FIXTURE_CERT_FILE',readText)};
}
