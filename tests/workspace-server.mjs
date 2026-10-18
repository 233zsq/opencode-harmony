// Deterministic loopback-only UI fixture. No tools or models execute here.
import http from 'node:http';
const port=Number(process.env.OPENCODE_FIXTURE_PORT||4212),root='/workspace/harmony-fixture',second='/workspace/second-fixture',streams=new Set(),receipts=[],reads=[],prompts=new Map();
const sessions=[{id:'s_a',title:'Workspace A',location:{directory:root}},{id:'s_b',title:'Workspace B',location:{directory:second}}];
for(let i=0;i<60;i++)sessions.push({id:'s_old_'+i,title:'History '+i,location:{directory:root}});
for(const s of sessions){s.model={providerID:'fixture',id:'fixture-coder'};s.time={created:1,updated:100};}
const messages=new Map(sessions.map(s=>[s.id,[]]));let seq=0,run=false,lose=false,hide=false,large=false,newID=0;
const forms=[{id:'q_a',sessionID:'s_a',title:'Workspace question',fields:[{key:'choice',title:'Approach',type:'string',required:true,options:[{value:'minimal',label:'Minimal'},{value:'full',label:'Full'}]},{key:'areas',title:'Areas',type:'multiselect',required:true,options:[{value:'chat',label:'Chat'},{value:'diff',label:'Diff'}]},{key:'note',title:'Note',type:'string'}]}];
const permissions=[{id:'p_b',sessionID:'s_b',action:'edit_file',resources:['sample.ts'],metadata:{workdir:second,files:[{file:'sample.ts',patch:'--- a/sample.ts\n+++ b/sample.ts\n@@ -1 +1 @@\n-old\n+new\n'}]},source:{type:'tool',id:'call_b'}}];
if(process.env.OPENCODE_FIXTURE_EMPTY==='1'){forms.splice(0);permissions.splice(0);}
function emit(type,data,directory=root){const value={id:'e'+(++seq),type,location:{directory},data};for(const res of streams)res.write('data: '+JSON.stringify(value)+'\n\n');}
const content='Title\n=====\n\n**Strong *nested* `code`**, ~~removed~~ and \\*literal\\*.\n\n- [x] Complete\n  - Nested item\n1. Ordered item\n\n| Name | Value |\n| :--- | ---: |\n| a\\|b | `x|y` |\n\n~~~~ts\n'+Array.from({length:600},(_,i)=>'const line'+i+' = "horizontal scrolling sample long text '+'.'.repeat(70)+'";').join('\n')+'\n~~~~';
const seed=(id='s_a')=>messages.set(id,[{id:'content_user',type:'user',text:'Synthetic Markdown sample',time:{created:1}},{id:'content_reply',type:'assistant',time:{created:2,completed:3},content:[{type:'reasoning',text:'Synthetic summary',time:{completed:2}},{type:'text',text:content}]}]);seed();
const server=http.createServer(async(req,res)=>{
 const url=new URL(req.url,'http://localhost'),p=url.pathname;let raw='';for await(const c of req)raw+=c;
 let input={};try{input=raw?JSON.parse(raw):{};}catch{return res.writeHead(400).end();}
 const send=(data,status=200)=>{res.writeHead(status,{'Content-Type':'application/json'});res.end(status===204?'':JSON.stringify(data));};
 if(p==='/__test/state')return send({receipts,reads,sessions,forms,permissions,streams:streams.size,prompts:[...prompts.keys()],run,counts:Object.fromEntries([...messages].map(([id,rows])=>[id,rows.length]))});
 if(p==='/__test/disconnect'){for(const s of streams)s.end();return send({});}
 if(p==='/__test/send-lost'){lose=true;hide=true;return send({});}
 if(p==='/__test/reveal-send'){hide=false;return send({});}
 if(p==='/__test/running'){run=true;return send({});}
 if(p==='/__test/attachments'){messages.set('s_a',[{id:'fixture_att',type:'user',text:'Synthetic file attachments',files:input.files,time:{created:Date.now()}}]);return send({});}
 if(p==='/__test/content'){seed(input.id||'s_a');return send({});}
 if(p==='/__test/large-attachments'){const data=Buffer.alloc(800000,65).toString('base64');messages.set('s_a',Array.from({length:10},(_,i)=>({id:'payload_'+i,type:'user',text:'Large synthetic attachment '+i,files:[{name:'large-'+i+'.txt',mime:'text/plain',data,source:{type:'inline'}}],time:{created:i}})));return send({});}
 if(p==='/__test/load'){large=true;messages.set(input.id||'s_a',Array.from({length:1000},(_,i)=>({id:'long_'+String(i).padStart(5,'0'),type:'assistant',time:{created:i,completed:i+1},content:[{type:'text',text:'# Reply '+i+'\n\nSynthetic long-history performance content.\n\n- entry\n- second entry'}]})));return send({});}
 if(req.headers.authorization!=='Basic '+Buffer.from('opencode:local-test').toString('base64'))return send({},401);
 if(req.method!=='GET')receipts.push({method:req.method,path:p,query:url.search,input});
 const directory=url.searchParams.get('location[directory]')||url.searchParams.get('directory');
 if(p==='/api/info')return send({version:'2.0.29'});
 if(p==='/api/project')return send([{id:'one',canonical:root,name:'Harmony Fixture'},{id:'two',canonical:second,name:'Second Fixture'}]);
 if(p==='/api/location')return send({directory});
 if(p==='/api/model')return send({data:[{providerID:'fixture',modelID:'fixture-coder',name:'Fixture vision',capabilities:{input:['text','image','pdf']},enabled:true}]});
 if(p==='/api/session/active')return send({data:run?{s_a:{type:'running'}}:{}});
 if(p==='/api/session'&&req.method==='POST'){const s={id:'s_new_'+(++newID),title:'New fixture '+newID,location:input.location,model:{providerID:'fixture',id:'fixture-coder'},time:{created:Date.now(),updated:Date.now()}};sessions.unshift(s);messages.set(s.id,[]);return send({data:s});}
 if(p==='/api/session'){
  const cursor=url.searchParams.get('cursor'),page=cursor?JSON.parse(Buffer.from(cursor,'base64url')):{offset:0,directory,search:url.searchParams.get('search')||''};
  const found=sessions.filter(s=>(!page.directory||s.location.directory===page.directory)&&s.title.toLowerCase().includes(page.search.toLowerCase()));
  return send({data:found.slice(page.offset,page.offset+50),cursor:{next:page.offset+50<found.length?Buffer.from(JSON.stringify({...page,offset:page.offset+50})).toString('base64url'):''}});
 }
 if(p==='/api/form'||p==='/api/permission/request')return send({data:(p==='/api/form'?forms:permissions).filter(x=>sessions.find(s=>s.id===x.sessionID)?.location.directory===directory)});
 if(p==='/api/fs/list')return send({data:[{path:'sample.ts',type:'file'}]});
 if(p.startsWith('/api/fs/read/'))return send('Synthetic file preview');
 if(p==='/api/vcs/diff')return send({data:[{file:'sample.ts',patch:'--- a/sample.ts\n+++ b/sample.ts\n@@ -1 +1 @@\n'+Array.from({length:large?10000:2},(_,i)=>'+line '+i).join('\n')}]});
 if(p==='/api/event'){
  res.writeHead(200,{'Content-Type':'text/event-stream'});res.write('data: '+JSON.stringify({id:'connected_'+Date.now(),type:'server.connected',data:{}})+'\n\n');streams.add(res);const timer=setInterval(()=>res.write(': heartbeat\n\n'),4000);res.on('close',()=>{streams.delete(res);clearInterval(timer);});return;
 }
 const match=p.match(/^\/api\/session\/([^/]+)(.*)$/);if(!match)return send({},404);
 const id=decodeURIComponent(match[1]),suffix=match[2],session=sessions.find(s=>s.id===id);if(!session)return send({},404);
 if(!suffix){if(req.method==='PATCH')session.title=input.title;return send({data:session});}
 if(suffix==='/message'){
  reads.push({id,limit:url.searchParams.get('limit'),cursor:url.searchParams.get('cursor')||''});
  const rows=hide?[]:(messages.get(id)||[]),offset=Number(url.searchParams.get('cursor')||0),rev=[...rows].reverse();return send({data:rev.slice(offset,offset+Number(url.searchParams.get('limit')||30)),cursor:{next:offset+Number(url.searchParams.get('limit')||30)<rows.length?String(offset+Number(url.searchParams.get('limit')||30)):''}});
 }
 if(suffix.startsWith('/message/')&&hide)return send({},404);
 if(suffix.startsWith('/message/'))return send({data:(messages.get(id)||[]).find(m=>m.id===decodeURIComponent(suffix.slice(9)))});
 if(suffix==='/form'||suffix==='/permission')return send({data:(suffix==='/form'?forms:permissions).filter(x=>x.sessionID===id)});
 if(suffix==='/inbox')return send({data:[]});
 if(suffix==='/diff')return send({data:[]});
 if(suffix==='/prompt'){
  if(!prompts.has(input.id)){
   prompts.set(input.id,input);const files=(input.files||[]).map(f=>{const m=/^data:([^;]+);base64,(.*)$/.exec(f.uri);return{name:f.name,mime:m[1],data:m[2],source:{type:'inline'}};});
   messages.get(id).push({id:input.id,type:'user',text:input.text,files,time:{created:Date.now()}});
   messages.get(id).push({id:'reply_'+input.id,type:'assistant',time:{created:Date.now(),completed:Date.now()},content:[{type:'text',text:'Synthetic reply accepted. No model was called.'}]});
  }
  if(lose){lose=false;return send({error:'Controlled lost acknowledgement'},503);}emit('session.idle',{sessionID:id},session.location.directory);return send({},204);
 }
 if(suffix==='/interrupt'){run=false;emit('session.idle',{sessionID:id},session.location.directory);return send({},204);}
 if(suffix==='/model'){session.model=input.model;return send({},204);}
 if(suffix==='/form/q_a/reply'){forms.splice(0);return send({},204);}
 if(suffix==='/permission/p_b/reply'){permissions.splice(0);return send({},204);}
 return send({},404);
});
server.listen(port,'127.0.0.1',()=>console.log('Workspace UI fixture ready on loopback port '+port));
