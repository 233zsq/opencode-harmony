import { execFileSync } from 'node:child_process';
import { readFileSync, mkdirSync } from 'node:fs';
import { resolve } from 'node:path';
const ide = process.env.DEVECO_STUDIO_HOME || 'C:/Program Files/Huawei/DevEco Studio';
const hdc = resolve(ide, 'sdk/default/openharmony/toolchains/hdc.exe');
const root = resolve(import.meta.dirname, '..');
const dir = resolve(root, '.test'); mkdirSync(dir, { recursive: true });
function command(...args) { return execFileSync(hdc, ['-t', '127.0.0.1:5555', ...args], { encoding: 'utf8', timeout: 20000 }); }
const pause = ms => new Promise(resolve => setTimeout(resolve, ms));
function nodes(node) { return [node.attributes, ...(node.children || []).flatMap(nodes)]; }
function layout() {
  command('shell', 'uitest dumpLayout -p /data/local/tmp/opencode-smoke.json');
  command('file', 'recv', '/data/local/tmp/opencode-smoke.json', resolve(dir, 'smoke-layout.json'));
  return nodes(JSON.parse(readFileSync(resolve(dir, 'smoke-layout.json'), 'utf8')));
}
function match(query) {
  const item = layout().find(n => n.id === query || n.text === query);
  if (!item) throw new Error('UI control not found: ' + query);
  const a = item.bounds.match(/\d+/g).map(Number);
  return { x: Math.round((a[0] + a[2]) / 2), y: Math.round((a[1] + a[3]) / 2), item };
}
async function click(query) {
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
  await click('Harmony Fixture'); await pause(1000);
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
