// Isolated rendered Flask home fixture, with all browser requests intercepted.
import assert from 'node:assert/strict';
import {readFileSync,mkdirSync,existsSync} from 'node:fs';
import {createRequire} from 'node:module';
import {spawnSync} from 'node:child_process';
import {resolve} from 'node:path';
const require=createRequire(import.meta.url),root=resolve(import.meta.dirname,'..');
const runtime=process.env.CODEX_PLAYWRIGHT||'playwright';
const {chromium}=require(runtime);
function renderHome(){
 const rendered=spawnSync(process.env.PYTHON_BINARY||'python',[resolve(root,'tests/render-account-fixture.py')],{encoding:'utf8',maxBuffer:1048576});
 assert.equal(rendered.status,0,'Rendering requires Python and Flask (pip install -r server/account/requirements.txt). '+(rendered.error?.message||rendered.stderr));
 return rendered.stdout;
}
const html=process.env.ACCOUNT_WEB_HTML?readFileSync(process.env.ACCOUNT_WEB_HTML,'utf8'):renderHome();
assert.ok(html.includes('data-mode="home"'));
const summary={available:true,month:'2026-10',started_at:'2026-10-22T10:29:49+00:00',updated_at:'2026-10-22T10:35:00+00:00',http_bytes:3250000000,
 projects:{opencode:{bytes:250000000},fieldnotes:{bytes:3000000000},other:{bytes:0}}};
const defaultEdge='C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe';
const browserPath=process.env.EDGE_BINARY||(process.platform==='win32'&&existsSync(defaultEdge)?defaultEdge:undefined);
const browser=await chromium.launch({executablePath:browserPath,headless:true});
try{
 for(const colorScheme of ['light','dark']){
  const page=await browser.newPage({viewport:{width:390,height:844},colorScheme});
  const errors=[];page.on('pageerror',error=>errors.push(error.message));const requests=[];
  await page.route('**/*',async route=>{
   const request=route.request(),url=new URL(request.url());requests.push(url.origin+url.pathname);
   assert.equal(url.origin,'https://traffic-fixture.invalid','No production or third-party requests');
   const path=url.pathname;
   if(path==='/')return route.fulfill({contentType:'text/html',body:html});
   if(path==='/assets/account.js'||path==='/assets/account.css')return route.fulfill({
    contentType:path.endsWith('.js')?'application/javascript':'text/css',body:readFileSync(resolve(root,'server/account/static',path.split('/').pop()),'utf8')});
   if(path==='/auth/status')return route.fulfill({contentType:'application/json',body:JSON.stringify({initialized:true,username:'traffic-fixture-owner',csrf:'fixture-only'})});
   if(path==='/auth/traffic')return route.fulfill({contentType:'application/json',body:JSON.stringify({data:summary})});
   return route.fulfill({status:404,body:''});
  });
  await page.goto('https://traffic-fixture.invalid/');
  await page.locator('#traffic-panel').waitFor({state:'visible'});
  assert.equal(await page.locator('#traffic-total').textContent(),'3.25 GB');
  assert.ok((await page.locator('#traffic-rows').textContent()).includes('250.0 MB'));
  assert.ok((await page.locator('#traffic-rows').textContent()).includes('3.00 GB'));
  assert.ok((await page.locator('#traffic-period').textContent()).includes('2026-10'));
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth>innerWidth),false);
  assert.deepEqual(errors,[]);assert.ok(requests.includes('https://traffic-fixture.invalid/auth/traffic'));
  mkdirSync(resolve(root,'.test'),{recursive:true});await page.screenshot({path:resolve(root,'.test','account-traffic-'+colorScheme+'.png'),fullPage:true});await page.close();
  console.log('PASS private traffic home: '+colorScheme+', mobile layout, counters, no external requests');
 }
}finally{await browser.close();}
