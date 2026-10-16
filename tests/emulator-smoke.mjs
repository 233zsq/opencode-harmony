import { execFileSync } from 'node:child_process';
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
const ide = process.env.DEVECO_STUDIO_HOME || 'C:/Program Files/Huawei/DevEco Studio';
const hdc = resolve(ide, 'sdk/default/openharmony/toolchains/hdc.exe');
const root = resolve(import.meta.dirname, '..');
const dir = resolve(root, '.test'); mkdirSync(dir, { recursive: true });
function command(...args) { return execFileSync(hdc, ['-t', process.env.HDC_TARGET || '127.0.0.1:5555', ...args], { encoding: 'utf8', timeout: 20000 }); }
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function nodes(node) { return [node.attributes, ...(node.children || []).flatMap(nodes)]; }
function layout() {
  command('shell', 'uitest dumpLayout -p /data/local/tmp/opencode-smoke.json');
  command('file', 'recv', '/data/local/tmp/opencode-smoke.json', resolve(dir, 'smoke-layout.json'));
  return nodes(JSON.parse(readFileSync(resolve(dir, 'smoke-layout.json'), 'utf8')));
}
const aliases={'open-menu':'__NavigationField__NavigationMenu__MenuItem2__native-navigation','menu-projects':'项目与会话','menu-review':'代码审查','menu-settings':'模型与接入','menu-connections':'服务器连接','menu-sync':'同步当前对话','appearance-menu':'外观'};
function match(query) {
  const item = layout().find(n => n.id === query || n.text === query || (aliases[query] && (n.id === aliases[query] || n.text === aliases[query])) || (query === 'back-chat' && n.id === 'native-destination'));
  if (!item) throw new Error('UI control not found: ' + query);
  const a = item.bounds.match(/\d+/g).map(Number);
  return { x: Math.round((a[0] + a[2]) / 2), y: Math.round((a[1] + a[3]) / 2), item };
}
async function click(query) {
  if(query==='back-chat'){command('shell','uitest uiInput keyEvent Back');await pause(550);return;}
  const target={连接:'menu-connections',项目:'menu-projects',审查:'menu-review',设置:'menu-settings'}[query];
  if(target){
    if(!layout().some(n=>n.id==='__NavigationField__NavigationMenu__MenuItem2__native-navigation')&&layout().some(n=>n.id==='native-destination'))await click('back-chat');
    if(layout().some(n=>n.id==='__NavigationField__NavigationMenu__MenuItem2__native-navigation')){await click('open-menu');await click(target);return;}
  }
  if(query==='聊天'&&layout().some(n=>n.id==='native-destination')){await click('back-chat');return;}
  const { x, y } = match(query); command('shell', 'uitest uiInput click ' + x + ' ' + y); await pause(300);
}
async function input(query, text) {
  const { x, y } = match(query);
  if (text.includes("'")) throw new Error('test input requires shell quoting');
  command('shell', 'uitest uiInput click ' + x + ' ' + y);
  await pause(150);
  command('shell', 'uitest uiInput keyEvent 2072 2017');
  command('shell', 'uitest uiInput keyEvent 2055');
  command('shell', "uitest uiInput text '" + text + "'");
  await pause(350);
  if (layout().some(node => node.bundleName === 'com.huawei.hmos.inputmethod')) {
    command('shell', 'uitest uiInput keyEvent Back'); await pause(350);
  }
}
async function screenshot(name) {
  command('shell', 'snapshot_display -f /data/local/tmp/opencode-smoke.jpeg');
  command('file', 'recv', '/data/local/tmp/opencode-smoke.jpeg', resolve(dir, name + '.jpeg'));
}
const mode = process.argv[2] || 'connect';
if (mode === 'connect') {
  await input('server-url', 'http://127.0.0.1:4210');
  await input('server-password', 'local-test');
  await click('allow-http');
  await click('connect-button');
  await pause(1600); await screenshot('connected');
  const texts = layout().map(n => n.text).filter(Boolean);
  console.log(texts.join(' | '));
} else if (mode === 'chat') {
  await click('项目');await click('Harmony Fixture'); await pause(1000);
  await click('new-session'); await pause(1200);
  await input('chat-input', 'test question');
  await click('send-button'); await pause(3500);
  await screenshot('chat');
  console.log(layout().map(n => n.text).filter(Boolean).join(' | '));
} else if (mode === 'review') {
  await click('审查'); await pause(1000); await screenshot('review');
  console.log(layout().map(n => n.text).filter(Boolean).join(' | '));
} else if (mode === 'snapshot') { await screenshot(process.argv[3] || 'snapshot'); }

else if (mode === 'resume') {
  await click('连接'); await pause(1200); await screenshot('restored-connection');
  console.log(layout().map(n => n.text).filter(Boolean).join(' | '));
} else if (mode === 'approve') {
  await click('批准一次'); await pause(600);
  const state = await (await fetch('http://127.0.0.1:4210/__test/state')).json();
  if (state.permissions.length) throw new Error('Permission still pending');
  console.log('Permission approval received by fixture server.');
} else if (mode === 'question') {
  for (let i = 0; i < 5 && !layout().some(n => n.text === '最小实现'); i++) {
    command('shell', 'uitest uiInput swipe 640 1000 640 1950 700'); await pause(350);
  }
  await click('最小实现'); await click('聊天'); await click('审查');
  for (let i = 0; i < 5 && !layout().some(n => n.id === 'field-note'); i++) {
    command('shell', 'uitest uiInput swipe 640 1900 640 1000 700'); await pause(350);
  }
  await input('field-note', 'native UI verified');
  await click('提交回答'); await pause(700);
  const state = await (await fetch('http://127.0.0.1:4210/__test/state')).json();
  if (state.forms.length) throw new Error('Form still pending: ' + layout().map(n => n.text).join('|'));
  const reply = state.receipts.findLast(r => r.path.includes('/form/') && r.path.endsWith('/reply'));
  if (reply.input.answer.approach !== 'minimal' || reply.input.answer.areas.length !== 2 || reply.input.answer.note !== 'native UI verified') throw new Error('Incorrect native form answer');
  console.log('Native single/multiple/text answers verified:', JSON.stringify(reply.input.answer));
  await screenshot('question-answered');
} else if (mode === 'reconnect') {
  await fetch('http://127.0.0.1:4210/__test/disconnect');
  await pause(5000);
  const nodes = layout();
  if (!nodes.some(n => n.text === '实时连接')) throw new Error('Client did not reconnect');
  console.log('Native SSE connection recovered.');
  await screenshot('reconnected');
}

else if (mode === 'files') {
  await click('文件浏览'); await pause(300); await click('README.md'); await pause(700);
  if (!layout().some(n => (n.text || '').includes('用于验证文件读取'))) throw new Error('Native file read failed');
  console.log('Native file read verified.'); await screenshot('files');
} else if (mode === 'model') {
  await click('聊天'); await pause(300); await click('本机测试模型'); await pause(300);
  await click('模型切换测试'); await pause(600);
  const state = await (await fetch('http://127.0.0.1:4210/__test/state')).json();
  const request = state.receipts.findLast(r => r.path.endsWith('/model'));
  if (request?.input.model.id !== 'fixture-second') throw new Error('Native model switch failed');
  console.log('Native model selection verified.');
} else if (mode === 'real') {
  const privateEnv = readFileSync(resolve(root, '.server-access/server.env'), 'utf8');
  const password = privateEnv.split(/\r?\n/).find(line => line.startsWith('OPENCODE_PASSWORD=')).slice(18);
  await click('连接');
  for (let i = 0; i < 4 && !layout().some(n => n.id === 'server-url'); i++) {
    command('shell', 'uitest uiInput swipe 640 2000 640 1000 700'); await pause(300);
  }
  await input('server-url', 'http://127.0.0.1:4211');
  try { await input('server-password', password); } catch { throw new Error('Private credential entry failed; details suppressed.'); }
  if (match('allow-http').item.checked !== 'true') await click('allow-http');
  await click('connect-button'); await pause(1800);
  await click('demo'); await pause(800);
  await click('鸿蒙客户端真实接口联调'); await pause(1200);
  const texts = layout().map(n => n.text || '');
  if (!texts.some(text => text.includes('鸿蒙客户端连接成功'))) throw new Error('Real server history missing in native UI');
  console.log('Native app connected to dedicated real server and rendered real MiMo history.');
  await screenshot('real-mimo');
}

else if (mode === 'real-resume') {
  const all = layout();
  const start = all.findIndex(n => n.type === 'Text' && n.text === 'http://127.0.0.1:4211');
  const button = all.slice(start).find(n => n.type === 'Button' && n.text === '连接');
  if (start < 0 || !button) throw new Error('Saved real connection not found');
  const bounds = button.bounds.match(/\d+/g).map(Number);
  command('shell', 'uitest uiInput click ' + Math.round((bounds[0]+bounds[2])/2) + ' ' + Math.round((bounds[1]+bounds[3])/2));
  await pause(1500);
  if (layout().some(n => n.text === 'demo')) { await click('demo'); await pause(700); }
  if (layout().some(n => n.text === '鸿蒙客户端真实接口联调' && n.type !== 'Text')) { await click('鸿蒙客户端真实接口联调'); await pause(1000); }
  await pause(700);
  if (!layout().some(n => (n.text || '').includes('鸿蒙客户端连接成功') || /^HarmonyOS NEXT connected/.test(n.text || ''))) throw new Error('Live MiMo history not rendered');
  console.log('Native app restored real credentials and rendered real MiMo history.'); await screenshot('real-mimo');
} else if (mode === 'live-send') {
  const phrase = 'HarmonyOS NEXT connected ' + Date.now();
  await input('chat-input', 'Please reply only ' + phrase + '. Do not use tools or change files.');
  await click('send-button');
  let found = false;
  for (let i = 0; i < 20; i++) {
    await pause(800);
    if (layout().some(n => (n.text || '').trim().replace(/[.!]$/, '') === phrase)) { found = true; break; }
  }
  if (!found) throw new Error('Native live reply not yet visible');
  console.log('Native UI sent prompt and received real MiMo response.'); await screenshot('real-live-chat');
}

else if (mode === 'https' || mode === 'tls-negative') {
  const endpoint = process.env.OPENCODE_TEST_URL;
  if (!endpoint?.startsWith('https://')) throw new Error('Set OPENCODE_TEST_URL');
  const privateEnv = readFileSync(resolve(root, '.server-access/server.env'), 'utf8');
  const password = mode === 'tls-negative' ? 'test-only-invalid' : privateEnv.split(/\r?\n/).find(line => line.startsWith('OPENCODE_PASSWORD=')).slice(18);
  if (!layout().some(n => n.id === 'server-url')) await click('连接');
  async function reveal(id) {
    for (let i=0;i<8;i++) {
      const n=layout().find(n=>n.id===id);
      if (n) { const b=n.bounds.match(/-?\d+/g).map(Number); if (n.visible!=='false' && b[1]>190 && b[3]<2630) return;
        if (b[1]<190) { command('shell','uitest uiInput swipe 640 1100 640 2250 500'); await pause(200); continue; } }
      command('shell','uitest uiInput swipe 640 2250 640 1100 500'); await pause(200);
    }
    throw new Error('Control not visible: '+id);
  }
  await reveal('server-url'); await input('server-url',endpoint);
  await reveal('server-password');
  try { await input('server-password',password); } catch { throw new Error('Private credential entry failed; details suppressed.'); }
  await reveal('dedicated-trust');
  const trust = mode !== 'tls-negative' || process.env.OPENCODE_EXPECT_TRUST !== 'false';
  if ((match('dedicated-trust').item.checked === 'true') !== trust) await click('dedicated-trust');
  await reveal('connect-button'); await click('connect-button'); await pause(2300);
  if (mode === 'tls-negative') {
    if (!layout().some(n => (n.text || '').includes('服务器证书校验失败'))) throw new Error('Native invalid certificate was not rejected');
    if (JSON.parse(readFileSync(resolve(dir,'wrong-tls-receipts.json'),'utf8')).reached !== 0) throw new Error('Invalid TLS reached HTTP');
    console.log('Native TLS rejected invalid certificate before sending an HTTP request.'); await screenshot('tls-negative-'+(trust?'pin':'ca'));
    command('shell','uitest uiInput swipe 640 1000 640 2300 500'); await pause(300);
    const all=layout();const start=all.findIndex(n=>n.text===endpoint);const button=all.slice(start).find(n=>n.type==='Button'&&n.text==='移除');
    if (start<0||!button) throw new Error('Test profile cleanup control missing');
    const b=button.bounds.match(/-?\d+/g).map(Number);command('shell','uitest uiInput click '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));await pause(300);
    process.exit(0);
  }
  if (layout().some(n=>n.text==='demo')) { await click('demo'); await pause(700); }
  if (layout().some(n=>n.text==='鸿蒙客户端真实接口联调')) { await click('鸿蒙客户端真实接口联调'); await pause(1300); }
  if (!layout().some(n=>n.id==='chat-input')) throw new Error('Native public HTTPS connection failed');
  console.log('Native app connected using dedicated CA and SPKI to HTTPS.'); await screenshot('public-https');
}

else if (mode === 'https-resume') {
  const endpoint=process.env.OPENCODE_TEST_URL;if (!endpoint?.startsWith('https://')) throw new Error('Set OPENCODE_TEST_URL');
  if (!layout().some(n=>n.id==='server-url')) await click('连接');
  const screen=layout()[0].bounds.match(/\d+/g).map(Number);command('shell','uitest uiInput swipe '+Math.round(screen[2]/2)+' '+Math.round(screen[3]*.35)+' '+Math.round(screen[2]/2)+' '+Math.round(screen[3]*.75)+' 500');await pause(250);
  async function savedButton(url,label) {
    const all=layout();const start=all.findIndex(n=>n.type==='Text'&&n.text===url);
    if (start<0) return false;const b=all.slice(start).find(n=>n.type==='Button'&&n.text===label);
    if (!b) throw new Error('Saved profile control missing');const r=b.bounds.match(/-?\d+/g).map(Number);
    command('shell','uitest uiInput click '+Math.round((r[0]+r[2])/2)+' '+Math.round((r[1]+r[3])/2));await pause(500);return true;
  }
  await savedButton('http://127.0.0.1:4211','移除');
  if (!await savedButton(endpoint,'连接')) throw new Error('Saved HTTPS profile missing');await pause(2000);
  if (layout().some(n=>n.text==='demo')) { await click('demo');await pause(800); }
  if (layout().some(n=>n.text==='鸿蒙客户端真实接口联调')) { await click('鸿蒙客户端真实接口联调');await pause(1200); }
  if (!layout().some(n=>n.id==='chat-input')) throw new Error('HTTPS restoration failed');
  console.log('Saved HTTPS credentials restored; native chat ready.');await screenshot('public-https-restored');
}

else if (mode === 'acceptance-start') {
  const {directory}=JSON.parse(readFileSync(resolve(dir,'acceptance.json'),'utf8'));
  await click('项目');await pause(300);await input('project-path',directory);await click('open-project');await pause(1300);
  await click('真实任务闭环验收');await pause(1000);
  await input('chat-input','First use your question tool to ask one choice (Chinese/English), a multiple choice (code/docs), and a text greeting prefix. Wait for my answers. Then update greeting.ts accordingly and add a README usage example. Use tools; change files only in this repo. Do not run destructive commands or make network requests.');
  await click('send-button');await pause(1800);await screenshot('acceptance-start');
  console.log('Native UI submitted real file-edit task to isolated acceptance session.');
}

else if (mode === 'acceptance-continue') {
  await input('chat-input','Please perform my previous task now with the available MiMo model. First use the question tool and wait for my answers.');
  await click('send-button');await pause(1600);console.log('Native UI resumed real task after explicit model switch.');
}

else if (mode === 'acceptance-approve') {
  await click('批准一次');await pause(700);console.log('Native UI approved one real pending tool operation.');await screenshot('acceptance-approved');
}

else if (mode === 'acceptance-answer') {
  command('shell','uitest uiInput swipe 640 1000 640 2000 600');await pause(200);
  command('shell','uitest uiInput swipe 640 1000 640 2000 600');await pause(200);
  async function revealField(id) {
    for(let i=0;i<9;i++) {
      const n=layout().find(n=>n.id===id);const b=n?.bounds.match(/-?\d+/g).map(Number);
      if(n&&n.visible!=='false'&&b[1]>650&&b[3]<2100)return;
      command('shell',n&&b[1]<650?'uitest uiInput swipe 640 1100 640 2000 500':'uitest uiInput swipe 640 2000 640 1100 500');await pause(250);
    }
    throw new Error('Real Question input not visible: '+id);
  }
  await revealField('field-q0');await input('field-q0','Chinese (中文)');
  await revealField('field-q1');await input('field-q1','Both');
  await revealField('field-q2');await input('field-q2','你好，');
  command('shell','uitest uiInput swipe 640 2000 640 1100 500');await pause(300);
  await click('提交回答');await pause(1000);await screenshot('acceptance-question-answered');console.log('Native UI answered real Agent Question with choices and custom Chinese text.');
}

else if (mode === 'acceptance-edit') {
  await input('chat-input','The answers are Chinese, Both code and docs, and greeting prefix 你好，. Implement greeting.ts and the README usage example now. Work only in this repository. Use your edit tools and wait for approval when required.');
  await click('send-button');await pause(1200);console.log('Native UI resumed file-edit phase with edit-only approval.');
}

else if (mode === 'acceptance-reject') {
  const all=layout();const index=all.findIndex(n=>n.type==='Button'&&n.text==='拒绝'&&n.visible!=='false'&&n.bounds.match(/-?\d+/g).map(Number)[1]>650);
  if(index<0)throw new Error('No visible real edit approval');
  const resource=all.slice(0,index).reverse().find(n=>n.type==='Text'&&(n.text==='greeting.ts'||n.text==='README.md'))?.text;
  if(!resource)throw new Error('Unknown approval resource');
  const b=all[index].bounds.match(/-?\d+/g).map(Number);command('shell','uitest uiInput click '+Math.round((b[0]+b[2])/2)+' '+Math.round((b[1]+b[3])/2));
  writeFileSync(resolve(dir,'rejected-resource.json'),JSON.stringify({path:resource}));await pause(700);await screenshot('acceptance-rejected');
  console.log('Native UI rejected real edit of '+resource);
}

else if (mode === 'acceptance-retry') {
  await input('chat-input','I deliberately rejected the last batch for testing. Retry the same two edits now; I will approve this time.');
  await click('send-button');await pause(1000);console.log('Native UI explicitly resumed task after rejection.');
} else if (mode === 'acceptance-open') {
  const {directory}=JSON.parse(readFileSync(resolve(dir,'acceptance.json'),'utf8'));
  await click('项目');await input('project-path',directory);await click('open-project');await pause(1100);await click('真实任务闭环验收');await pause(1000);
  console.log('Native UI restored the real acceptance session.');await screenshot(process.env.HDC_TARGET?'pad-acceptance':'acceptance-restored');
}
