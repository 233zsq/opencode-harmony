// Isolated rendered Flask home fixture, with all browser requests intercepted.
import assert from 'node:assert/strict';
import {readFileSync,mkdirSync} from 'node:fs';
import {createRequire} from 'node:module';
const require=createRequire(import.meta.url);
const runtime=process.env.CODEX_PLAYWRIGHT||'playwright';
const {chromium}=require(runtime);
const html=readFileSync(process.env.ACCOUNT_WEB_HTML||'.test/account-traffic-fixture.html','utf8');
assert.ok(html.includes('data-mode="home"'));
const summary={available:true,month:'2026-10',started_at:'2026-10-22T10:29:49+00:00',updated_at:'2026-10-22T10:35:00+00:00',http_bytes:3250000000,
 projects:{opencode:{bytes:250000000},fieldnotes:{bytes:3000000000},other:{bytes:0}}};
const browser=await chromium.launch({executablePath:process.env.EDGE_BINARY||'C:/Program Files (x86)/Microsoft/Edge/Application/msedge.exe',headless:true});
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
    contentType:path.endsWith('.js')?'application/javascript':'text/css',body:readFileSync('server/account/static/'+path.split('/').pop(),'utf8')});
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
  mkdirSync('.test',{recursive:true});await page.screenshot({path:'.test/account-traffic-'+colorScheme+'.png',fullPage:true});await page.close();
  console.log('PASS private traffic home: '+colorScheme+', mobile layout, counters, no external requests');
 }
}finally{await browser.close();}
