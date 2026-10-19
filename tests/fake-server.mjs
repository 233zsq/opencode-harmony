// Local test fixture, not an OpenCode implementation or a production backend.
import http from 'node:http';
import { randomUUID } from 'node:crypto';

const port = Number(process.env.PORT || 4210);
const directory = '/workspace/harmony-fixture';
const streams = new Set();
const messages = [];
const forms = [];
const permissions = [];
const receipts = [];
const prompts = new Map();
const integrations = [
  {id:'opencode',name:'OpenCode',methods:[{id:'key',type:'key',label:'API Key'}],connections:[]},
  {id:'deepseek',name:'DeepSeek',methods:[{id:'key',type:'key',label:'API Key'},{type:'env',label:'服务器环境变量'}],connections:[]},
  {id:'xiaomi',name:'Xiaomi',methods:[{id:'key',type:'key',label:'API Key'}],connections:[]},
  {id:'xiaomi-token-plan-cn',name:'Xiaomi Token Plan (China)',methods:[{id:'key',type:'key',label:'API Key'}],connections:[]}
];
let permissionReadFailure = false;
let modelFailure = false;
let agentFailure=false,agentLost=false,exportFailure=false,exportDelay=false;
const historyReads=[];
const agents=[{id:'fixture-build',name:'实施 Agent',description:'实施代码变更',mode:'primary',hidden:false,model:{providerID:'fixture',id:'fixture-coder'}},{id:'fixture-plan',name:'规划 Agent',description:'分析与规划任务',mode:'primary',hidden:false,model:{providerID:'fixture',id:'fixture-second'}},{id:'fixture-hidden',name:'隐藏 Agent',mode:'primary',hidden:true},{id:'fixture-subagent',name:'内部 Agent',mode:'subagent',hidden:false}];
let uiMessageID = '';
let active = false;
let sequence = 0;
let model = { id: 'fixture-coder', providerID: 'fixture' };
const session = { id: 'ses_fixture', title: '本机联调 · 八项流程', agent:'fixture-build', location: { directory }, model,
  projectID: 'prj_fixture', time: { created: Date.now(), updated: Date.now() }, cost: 0, tokens: {} };
const send = (res, value, status = 200) => {
  res.writeHead(status, { 'Content-Type': 'application/json' });
  res.end(status === 204 ? '' : JSON.stringify(value));
};
const event = (type, data) => {
  const value = { id: 'evt_' + (++sequence), created: Date.now(), type, location: { directory }, data };
  for (const stream of streams) stream.write('data: ' + JSON.stringify(value) + '\n\n');
};
const form = () => ({
  id: 'frm_fixture', sessionID: session.id, title: '选择本次实现方式',
  fields: [
    { key: 'approach', type: 'string', title: '方案', required: true,
      options: [{ value: 'minimal', label: '最小实现' }, { value: 'expanded', label: '完整实现' }], custom: true },
    { key: 'areas', type: 'multiselect', title: '要验证的模块', required: true,
      options: [{ value: 'chat', label: '聊天' }, { value: 'diff', label: '审查' }] },
    { key: 'note', type: 'string', title: '补充说明' }
  ]
});
const permission = () => ({ id: 'per_fixture', sessionID: session.id, action: 'edit_file',
  resources: ['src/example.ets'], metadata: { workdir: directory, files: [{ file: 'src/example.ets', additions: 1, deletions: 1, patch: '--- a/src/example.ets\n+++ b/src/example.ets\n@@ -1 +1 @@\n-const platform = "HarmonyOS";\n+const platform = "HarmonyOS NEXT";\n' }] }, save: ['src/*'], source: { type: 'tool', messageID: 'msg_fixture', id: 'call_fixture' } });

async function runPrompt(text) {
  active = true;
  const id = 'msg_' + randomUUID().replaceAll('-', '');
  const assistant = { id, type: 'assistant', time: { created: Date.now() }, content: [] };
  messages.push(assistant);
  const reasoning = '检查协议、编码和消息归并；这是明确标识的本地测试数据。';
  assistant.content.push({ type: 'reasoning', text: reasoning });
  event('session.reasoning.ended', { sessionID: session.id, assistantMessageID: id, ordinal: 0, text: reasoning });
  const output = '# 已收到任务\n\n这里是 **本机测试服务** 的流式输出，中文与 emoji 🌿 正常显示。\n\n- 连接与认证\n- 会话历史与流式更新\n- Question、审批与 Diff\n\n' +
    String.fromCharCode(96).repeat(3) + 'typescript\nconst platform = "HarmonyOS";\n' + String.fromCharCode(96).repeat(3);
  assistant.content.push({ type: 'text', text: '' });
  for (const chunk of output.match(/.{1,7}|\n/gus)) {
    assistant.content[1].text += chunk;
    event('session.text.delta', { sessionID: session.id, assistantMessageID: id, ordinal: 1, delta: chunk });
    await new Promise(resolve => setTimeout(resolve, 70));
  }
  event('session.text.ended', { sessionID: session.id, assistantMessageID: id, ordinal: 1, text: output });
  assistant.content.push({ type: 'tool', id: 'call_fixture', name: 'read_file', time: { created: Date.now(), completed: Date.now() },
    state: { status: 'completed', input: { path: 'README.md' }, content: [{ type: 'text', text: '文件读取成功（测试数据）' }] } });
  assistant.time.completed = Date.now();
  if (/question|test|测试|验证/i.test(text)) {
    if (!forms.length) forms.push(form());
    if (!permissions.length) permissions.push(permission());
    event('form.created', { form: forms[0] });
    event('permission.asked', permissions[0]);
  }
  active = false;
  messages.push({id:'idle_'+id,type:'idle',outcome:'succeeded',time:{created:Date.now()}});
  event('session.idle', { sessionID: session.id });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, 'http://localhost');
  const path = url.pathname;
  if (path === '/__test/permission-read-failure' && req.method === 'POST') { permissionReadFailure = url.searchParams.get('enabled') === '1'; return send(res, { permissionReadFailure }); }
  if (path === '/__test/approval' && req.method === 'POST') { if (!permissions.length) permissions.push(permission()); event('permission.asked', permissions[0]); return send(res, { created: true }); }
  if (path === '/__test/ui-phase' && req.method === 'POST') {
    const phase=url.searchParams.get('phase');let m=messages.find(m=>m.id===uiMessageID);
    if(phase==='thinking') {
      if(!messages.some(m=>m.id==='msg_ui_user'))messages.push({id:'msg_ui_user',type:'user',text:'请检查这个示例文件，并说明接下来怎么改。',time:{created:Date.now()}});
      uiMessageID='msg_ui_'+Date.now().toString(36);m={id:uiMessageID,type:'assistant',time:{created:Date.now()},content:[]};messages.push(m);
      m.content=[{type:'reasoning',text:'正在检查示例文件与实现步骤。这是本机UI测试数据，不执行真实工具。',time:{created:Date.now()}}];delete m.time.completed;active=true;
      event('session.reasoning.delta',{sessionID:session.id,assistantMessageID:m.id,ordinal:0,delta:m.content[0].text});
    } else if(m && phase==='answer') {
      m.content[0].time.completed=Date.now();event('session.reasoning.ended',{sessionID:session.id,assistantMessageID:m.id,ordinal:0,text:m.content[0].text});
      m.content.push({type:'text',text:'## 可以开始了\n\n已检查示例文件，接下来可以完善交互。工具细节按需查看，正文保持清晰。'});
      m.content.push({type:'tool',id:'call_'+m.id,name:'read',time:{created:Date.now()},state:{status:'running',input:{path:'src/example.ets'},content:[]}});
      event('session.text.ended',{sessionID:session.id,assistantMessageID:m.id,ordinal:1,text:m.content[1].text});
    } else if(m && phase==='tool-done') {
      const t=m.content.find(c=>c.type==='tool');t.state.status='completed';t.state.content=[{type:'text',text:'UI fixture tool result: verified sample only.'}];t.time.completed=Date.now();m.time.completed=Date.now();active=false;event('session.idle',{sessionID:session.id});
    } else return send(res,{error:'Invalid UI phase'},400);
    return send(res,{phase,id:m.id,toolID:'call_'+m.id});
  }
  if (path === '/__test/timeline' && req.method === 'POST') {
    messages.splice(0);messages.push({id:'turn_a',type:'user',text:'第一轮：示例文件改成 A',time:{created:Date.now()-60000}},
      {id:'idle_a',type:'idle',outcome:'succeeded'}, {id:'turn_b',type:'user',text:'第二轮：同一文件改成 B',time:{created:Date.now()}},
      {id:'steer_b',type:'user',text:'追加说明仍属第二轮'}, {id:'idle_b',type:'idle',outcome:'succeeded'});
    return send(res,{ready:true});
  }
  if (path === '/__test/model-failure' && req.method === 'POST') { modelFailure = url.searchParams.get('enabled') === '1';return send(res,{modelFailure}); }
  if (path === '/__test/agent-failure' && req.method === 'POST') { agentFailure=url.searchParams.get('enabled')==='1'; return send(res,{agentFailure}); }
  if (path === '/__test/agent-lost' && req.method === 'POST') { agentLost=url.searchParams.get('enabled')==='1'; return send(res,{agentLost}); }
  if (path === '/__test/agent-running' && req.method === 'POST') { active=url.searchParams.get('enabled')==='1';session.outcome=active?undefined:'succeeded';event('session.idle',{sessionID:session.id});return send(res,{active}); }
  if (path === '/__test/export-failure' && req.method === 'POST') { exportFailure=url.searchParams.get('enabled')==='1';return send(res,{exportFailure}); }
  if (path === '/__test/export-delay' && req.method === 'POST') { exportDelay=url.searchParams.get('enabled')==='1';return send(res,{exportDelay}); }
  if (path === '/__test/export-history' && req.method === 'POST') {
    active=false;forms.splice(0);permissions.splice(0);session.outcome='succeeded';session.title='Export acceptance '+Date.now();messages.splice(0);
    for(let i=0;i<360;i++)messages.push(i%2===0?{id:'export_'+i,type:'user',text:'EXPORT_ENTRY_'+String(i).padStart(3,'0'),files:i===0?[{name:'metadata-only.txt',mime:'text/plain',data:Buffer.from('EXPORT_INLINE_PRIVATE').toString('base64')}]:[],time:{created:i+1}}:{id:'export_'+i,type:'assistant',content:[{type:'reasoning',text:'EXPORT_REASONING'},{type:'text',text:'EXPORT_ENTRY_'+String(i).padStart(3,'0')},...(i===359?[{type:'tool',id:'fixture-export-tool',name:'read',state:{status:'completed',input:{path:'test.txt'},content:[{type:'text',text:'EXPORT_TOOL_OUTPUT'}]}}]:[])],time:{created:i+1,completed:i+2}});
    event('session.idle',{sessionID:session.id});return send(res,{ready:true});
  }
  if (path === '/__test/state') return send(res, { receipts, historyReads,title:session.title,agent:session.agent,model:session.model,messages: messages.length, forms, permissions, streams: streams.size });
  if (path === '/__test/disconnect') {
    for (const stream of streams) stream.end();
    return send(res, { disconnected: true });
  }
  if (req.headers.authorization !== 'Basic ' + Buffer.from('opencode:local-test').toString('base64')) {
    res.setHeader('WWW-Authenticate', 'Basic realm="Local fixture"');
    return send(res, { error: 'Unauthorized' }, 401);
  }
  let body = '';
  for await (const chunk of req) body += chunk;
  let input = {};
  try { input = body ? JSON.parse(body) : {}; } catch { return send(res, { error: 'Invalid JSON' }, 400); }
  if (req.method !== 'GET') receipts.push({ method: req.method, path, query: url.search, input });
  if (path === '/api/info') return send(res, { version: '2.0.29', pid: process.pid, urls: [], paths: { tmp: '/tmp' } });
  if (path === '/api/project') return send(res, [{ id: 'prj_fixture', canonical: directory, name: 'Harmony Fixture', sandboxes: [], time: {} }]);
  if (path === '/api/location') return send(res, { directory, project: { id: 'prj_fixture', directory, canonical: directory } });
  if (path === '/api/session' && req.method === 'POST') return send(res, { data: session });
  if (path === '/api/session') return send(res, { data: [session], cursor: {} });
  if (path === '/api/form') return send(res, { location: { directory }, data: forms });
  if (path === '/api/permission/request') return permissionReadFailure ? send(res, { error: 'Controlled approval read failure' }, 400) : send(res, { location: { directory }, data: permissions });
  if (path === '/api/session/' + session.id && req.method === 'PATCH') { session.title = input.title; return send(res, {}, 204); }
  if (path === '/api/session/active') return send(res, { data: active ? { [session.id]: { type: 'running' } } : {} });
  if (path === '/api/agent') return send(res,{location:{directory},data:agents});
  if (path === '/api/model') return send(res, { location: { directory }, data: [
    { id: 'fixture/fixture-coder', modelID: 'fixture-coder', providerID: 'fixture', name: '本机测试模型', enabled: true, status: 'active' },
    { id: 'fixture/fixture-second', modelID: 'fixture-second', providerID: 'fixture', name: '模型切换测试', enabled: true, status: 'active' },
    ...Array.from({length:75},(_,i)=>({modelID:'model-'+String(i).padStart(3,'0'),providerID:'fixture-extra',name:'测试模型'+String(i).padStart(3,'0'),enabled:true,capabilities:{input:i%2===0?['text','image']:['text','pdf']}}))
  ] });
  if (path.endsWith('/message')) {
    const limit=Math.min(100,Number(url.searchParams.get('limit')||30));const token=url.searchParams.get('cursor');const [direction,position]=token?token.split(':'):[url.searchParams.get('order')||'desc','0'];const start=Number(position);historyReads.push({direction,start,limit});
    if(direction==='asc'&&exportFailure)return send(res,{error:'Controlled export failure'},503);
    if(direction==='asc'&&exportDelay)await new Promise(r=>setTimeout(r,1500));
    const rows=direction==='asc'?[...messages]:[...messages].reverse();return send(res,{data:rows.slice(start,start+limit),cursor:{next:start+limit<rows.length?direction+':'+(start+limit):''}});
  }
  if (path.endsWith('/agent') && req.method==='POST') {
    if(agentFailure)return send(res,{error:'Controlled Agent rejection'},400);
    const selected=agents.find(a=>a.id===input.agent&&!a.hidden&&a.mode==='primary');if(!selected)return send(res,{error:'Invalid Agent'},400);
    session.agent=selected.id;session.model=selected.model;
    return agentLost?send(res,{error:'Controlled acknowledgement loss'},503):send(res,{},204);
  }
  if (path.endsWith('/inbox')) return send(res, { data: [] });
  if (path.endsWith('/prompt')) {
    if (!prompts.has(input.id)) {
      prompts.set(input.id, input);
      messages.push({ id: input.id, type: 'user', text: input.text, time: { created: Date.now() } });
      void runPrompt(input.text);
    }
    return send(res, { data: { ...prompts.get(input.id), sessionID: session.id, type: 'user', payload: { text: input.text } } });
  }
  if (path.endsWith('/model')) { if(modelFailure)return send(res,{error:'Controlled model rejection'},400);model = input.model; session.model = model; return send(res, {}, 204); }
  if (path.endsWith('/interrupt')) { active = false; return send(res, { interrupted: true }); }
  if (path.endsWith('/form')) return send(res, { data: forms });
  if (path.endsWith('/permission')) return permissionReadFailure ? send(res, { error: 'Controlled approval read failure' }, 400) : send(res, { data: permissions });
  if (path.includes('/form/') && path.endsWith('/reply')) {
    if (!Array.isArray(input.answer?.areas) || !input.answer?.approach) return send(res, { error: 'Invalid answer' }, 400);
    forms.splice(0);
    event('form.replied', { id: 'frm_fixture', sessionID: session.id, answer: input.answer });
    return send(res, {}, 204);
  }
  if (path.includes('/form/') && req.method === 'DELETE') { forms.splice(0); return send(res, {}, 204); }
  if (path.includes('/permission/') && path.endsWith('/reply')) {
    if (!['once', 'reject'].includes(input.decision)) return send(res, { error: 'Invalid decision' }, 400);
    permissions.splice(0);
    event('permission.replied', { requestID: 'per_fixture', sessionID: session.id, reply: input.decision });
    return send(res, {}, 204);
  }
  if (path === '/api/session/'+session.id+'/diff') return send(res,{data:[{file:'src/example.ets',patch:'--- a/src/example.ets\n+++ b/src/example.ets\n@@ -1 +1 @@\n-before\n+'+(url.searchParams.get('from')==='turn_a'?'TASK_A_ONLY':'TASK_B_ONLY')+'\n'}]});
  if (path === '/api/integration') return send(res,{data:integrations});
  const credentialPath = path.match(/^\/api\/integration\/([^/]+)\/connect\/key$/);
  if (credentialPath && req.method === 'POST') { const item=integrations.find(p=>p.id===credentialPath[1]);if(!item)return send(res,{},404);item.connections.unshift({type:'credential',id:'fixture_'+randomUUID(),label:input.label||'Fixture account',method:'key'});return send(res,{},204); }
  if (path === '/client-settings/providers') return send(res,{data:[]});
  if (path === '/api/vcs/diff') return send(res, { location: { directory }, data: [{
    file: 'src/example.ets', patch: 'diff --git a/src/example.ets b/src/example.ets\n--- a/src/example.ets\n+++ b/src/example.ets\n@@ -1,2 +1,2 @@\n-const platform = "Android";\n+const platform = "HarmonyOS";\n // local fixture\n', additions: 1, deletions: 1, status: 'modified'
  }] });
  if (path === '/api/fs/list') return send(res, { location: { directory }, data: [
    { path: 'README.md', type: 'file' }, { path: 'src', type: 'directory' }
  ] });
  if (path.startsWith('/api/fs/read/')) { res.writeHead(200, { 'Content-Type': 'application/octet-stream' }); return res.end('# 本地测试仓库\n用于验证文件读取，不包含真实项目代码。'); }
  if (path === '/api/event') {
    res.writeHead(200, { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' });
    res.write('data: ' + JSON.stringify({ id: 'connected_' + randomUUID(), type: 'server.connected', data: {} }) + '\n\n');
    streams.add(res);
    const heartbeat = setInterval(() => res.write(': heartbeat\n\n'), 5000);
    res.on('close', () => { streams.delete(res); clearInterval(heartbeat); });
    return;
  }
  if (path === '/api/session/' + session.id) return send(res, { data: session });
  send(res, { error: 'Not found' }, 404);
});
server.listen(port, '127.0.0.1', () => console.log('Local V2 fixture: http://127.0.0.1:' + port));
