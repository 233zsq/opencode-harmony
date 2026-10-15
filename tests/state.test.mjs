import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
import vm from 'node:vm';
const require = createRequire(import.meta.url);
const root = resolve(import.meta.dirname, '..');
const ts = require(resolve(process.env.DEVECO_STUDIO_HOME || 'C:/Program Files/Huawei/DevEco Studio',
  'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
class Encoder { encodeInto(value) { return new TextEncoder().encode(value); } }
class Decoder { constructor() { this.decoder = new TextDecoder(); } decodeToString(value, options) { return this.decoder.decode(value, options); } }
class Base64 { encodeToStringSync(bytes) { return Buffer.from(bytes).toString('base64'); } }
const requests = [];
const httpMock = {
  RequestMethod: { GET: 'GET', POST: 'POST', DELETE: 'DELETE' }, HttpDataType: { STRING: 0 },
  createHttp: () => ({
    request: async (url, options) => { requests.push({ url, options }); return { responseCode: 200, result: '{"version":"2.0.29"}' }; },
    destroy() {}, on() {}, requestInStream: async (url, options) => { requests.push({ url, options }); return 200; }
  })
};
class StorageMock { async init() {} async servers() { return []; } async secret() { return 'test-only'; } async last() { return []; } async position() {} }
const modules = new Map([
  ['@kit.NetworkKit', { http: httpMock }],
  ['@kit.ArkTS', { util: { TextEncoder: Encoder, TextDecoder: Decoder, Base64Helper: Base64 } }],
  ['@kit.AbilityKit', {}], ['@kit.BasicServicesKit', {}], ['../data/Storage', { Storage: StorageMock }]
]);
function load(file, key) {
  const exports = {};
  const code = ts.transpileModule(readFileSync(resolve(root, file), 'utf8'), {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022, experimentalDecorators: true }
  }).outputText;
  vm.runInNewContext(code, { exports, require: name => {
    if (!modules.has(name)) throw new Error('Unmocked platform dependency: ' + name);
    return modules.get(name);
  }, Observed: value => value, setTimeout: () => -1, clearTimeout() {}, setInterval: () => -1, clearInterval() {},
  console, Error, Map, Set, Date, Math, JSON });
  modules.set(key, exports);
  return exports;
}
const core = load('entry/src/main/ets/domain/Core.ts', '../domain/Core');
const trust = load('entry/src/main/ets/data/DedicatedTrust.ets', './DedicatedTrust');
const protocol = load('entry/src/main/ets/data/Protocol.ets', '../data/Protocol');
const { AppStore } = load('entry/src/main/ets/presentation/AppStore.ets', 'store');
let count = 0;
async function test(name, run) { await run(); count++; console.log('PASS ' + name); }
const message = (id, text) => ({ id, role: 'assistant', text, reasoning: '', tools: [], parts: [], state: 'completed' });
const form = () => ({ id: 'frm_a', sessionID: 'ses_a', kind: 'form', title: 'Question', detail: '', fields: [], state: 'pending' });

await test('same auth is injected into HTTP and SSE', async () => {
  const api = new protocol.Protocol({ id: 'a', name: 'test', url: 'https://example.com/prefix', username: 'opencode', allowHttp: false }, 'test-only');
  await api.request('/api/info');
  const close = api.stream(() => {}, () => {}, () => {}); close();
  assert.equal(requests.at(-2).options.header.Authorization, requests.at(-1).options.header.Authorization);
  assert.equal(requests.at(-1).url, 'https://example.com/prefix/api/event');
});
await test('V2 project canonical and modelID use actual HTTP envelopes', async () => {
  const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, '');
  api.request = async path => path === '/api/project' ? [{ id: 'p', canonical: '/repo', name: 'Repo' }] :
    { data: [{ id: 'compound-id', providerID: 'provider', modelID: 'actual/model', name: 'Display', enabled: true }] };
  assert.equal((await api.projects())[0].directory, '/repo');
  assert.equal((await api.models('/repo'))[0].id, 'provider/actual/model');
});
await test('V2 assistant content parses reasoning and tools without V1 parts', async () => {
  const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, '');
  const result = api.parseMessages({ data: [{ id: 'm', type: 'assistant', time: { completed: 1 },
    content: [{ type: 'reasoning', text: 'think' }, { type: 'text', text: 'answer' },
      { type: 'tool', id: 'c', name: 'read', state: { status: 'completed', input: { path: 'a' }, content: [{ type: 'text', text: 'file' }] } }] }] });
  assert.equal(result[0].text, 'answer'); assert.equal(result[0].reasoning, 'think');
  assert.equal(result[0].tools[0].output, 'file');
});
await test('failed pending read retains card; successful empty read removes it', async () => {
  const store = new AppStore(); store.interactions = [form()];
  await store.syncInteractions({ interactions: async () => { throw new Error('network'); } }, 'ses_a', 'form', 0);
  assert.equal(store.interactions.length, 1);
  await store.syncInteractions({ interactions: async () => [] }, 'ses_a', 'form', 0);
  assert.equal(store.interactions.length, 0);
});
await test('late history after disconnect cannot contaminate another connection', async () => {
  const store = new AppStore(); store.sessionID = 'ses_old';
  let release;
  store.api = { messages: () => new Promise(resolve => { release = resolve; }), parseMessages: () => [message('old', 'old')] };
  const pending = store.sync();
  store.disconnect();
  release({ data: [] }); await pending;
  assert.equal(store.messages.length, 0); assert.equal(store.sessionID, '');
});
await test('lost send acknowledgement retains immutable message ID for retry', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.draft = 'task'; store.active = false;
  const attempts = [];
  store.api = { request: async (path, method, body) => {
    attempts.push(body);
    if (attempts.length === 1) throw new Error('lost acknowledgement');
  } };
  await store.send();
  assert.ok(store.pendingSend);
  await store.send();
  assert.equal(attempts[0].id, attempts[1].id); assert.equal(attempts[0].text, attempts[1].text);
  assert.equal(store.pendingSend, undefined);
});
await test('duplicate SSE IDs and ended snapshots do not duplicate text', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.directory = '/repo';
  const event = { id: 'evt_a', type: 'session.text.delta', location: { directory: '/repo' },
    data: { sessionID: 'ses_a', assistantMessageID: 'm', ordinal: 0, delta: 'hello' } };
  store.onFrame({ data: JSON.stringify(event) }); store.onFrame({ data: JSON.stringify(event) });
  assert.equal(store.messages[0].text, 'hello');
  store.onFrame({ data: JSON.stringify({ ...event, id: 'evt_b', type: 'session.text.ended', data: { ...event.data, text: 'hello' } }) });
  assert.equal(store.messages[0].text, 'hello');
});
await test('event from other project or session is ignored', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.directory = '/repo';
  store.onFrame({ data: JSON.stringify({ id: 'evt_other', type: 'session.text.delta', location: { directory: '/other' },
    data: { sessionID: 'ses_a', assistantMessageID: 'm', ordinal: 0, delta: 'foreign' } }) });
  assert.equal(store.messages.length, 0);
});
await test('model switching sends raw modelID, not catalog identity', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.active = false;
  let request;
  store.api = { request: async (path, method, body) => { request = body; } };
  await store.chooseModel('provider/actual/model');
  assert.deepEqual(JSON.parse(JSON.stringify(request)), { model: { id: 'actual/model', providerID: 'provider' } });
});


await test('reused ArkUI card submits current draft instead of captured old item', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.active = false;
  const stale = form();
  stale.fields = [{ key: 'choice', label: 'choice', type: 'string', required: true, options: [], values: [], text: '' }];
  store.interactions = [stale]; store.updateField(stale.id, 'choice', 'current answer');
  let body;
  store.api = { request: async (path, method, value) => { body = value; } };
  await store.reply(stale);
  assert.equal(body.answer.choice, 'current answer'); assert.equal(store.interactions.length, 0);
});
await test('polling does not reopen history cursor after last page', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.tailLoaded = true; store.cursor = '';
  store.api = { messages: async () => ({ data: [], cursor: { next: 'old-page' } }), parseMessages: () => [],
    interactions: async () => [], request: async () => ({ data: {} }) };
  await store.sync(); assert.equal(store.cursor, '');
});
await test('absence from active set does not falsely finish a retrying session', async () => {
  const store = new AppStore(); store.sessionID = 'ses_a'; store.working = true;
  store.api = { messages: async () => ({ data: [], cursor: {} }), parseMessages: () => [],
    interactions: async () => [], request: async () => ({ data: {} }) };
  await store.sync(); assert.equal(store.working, true);
});
await test('SSE HTTP authentication failure survives early dataEnd', async () => {
  const saved = httpMock.createHttp;
  const handlers = new Map(); let failure;
  httpMock.createHttp = () => ({ on: (name, handler) => handlers.set(name, handler), destroy() {},
    requestInStream: async () => { handlers.get('dataEnd')(); return 401; } });
  try {
    const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, 'test-only');
    api.stream(() => {}, () => {}, error => { failure = error; });
    await Promise.resolve(); await Promise.resolve();
    assert.equal(failure.code, 401);
  } finally { httpMock.createHttp = saved; }
});
await test('dedicated HTTPS uses the same CA, SPKI pin and validation for HTTP and SSE', async () => {
  const api = new protocol.Protocol({ url: 'https://192.0.2.1:9443', username: 'opencode', useDedicatedTrust: true }, 'test');
  await api.request('/api/info'); const close = api.stream(() => {}, () => {}, () => {}); close();
  for (const request of requests.slice(-2)) {
    assert.equal(request.options.caData, trust.DEDICATED_CA);
    assert.equal(request.options.certificatePinning.publicKeyHash, trust.DEDICATED_SPKI);
    assert.equal(request.options.certificatePinning.hashAlgorithm, 'SHA-256');
    assert.equal(request.options.remoteValidation, 'system'); assert.equal(request.options.maxRedirects, 0);
  }
});
await test('private CA is opt-in and cannot be used over HTTP', async () => {
  assert.throws(() => new protocol.Protocol({ url: 'http://192.0.2.1', useDedicatedTrust: true }, 'test'), /HTTPS/);
  const api = new protocol.Protocol({ url: 'https://example.com', username: 'opencode' }, 'test');
  await api.request('/api/info');
  assert.equal(requests.at(-1).options.caData, undefined); assert.equal(requests.at(-1).options.certificatePinning, undefined);
  assert.equal(requests.at(-1).options.maxRedirects, 0);
});
await test('certificate validation errors stop SSE retries and stay stopped on foreground', async () => {
  const store=new AppStore();let end,closed=0,opened=0;
  store.api={stream: (frame,data,done)=>{end=done;opened++;return ()=>{closed++;};}};
  store.openStream();end(protocol.networkError(Object.assign(new Error('raw'),{code:2300060})));
  assert.equal(store.status,'证书校验失败');assert.equal(store.retryTimer,-1);assert.equal(closed,1);
  store.setActive(true);assert.equal(opened,1);
});
console.log(count + ' adapter/state tests passed.');
