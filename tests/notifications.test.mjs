// Reminder notification tests: pure domain rules plus AppStore integration.
// No HarmonyOS device or platform notification service is required; only the
// platform interfaces AppStore depends on are mocked, like tests/state.test.mjs.
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
const httpMock = {
  RequestMethod: { GET: 'GET', POST: 'POST', DELETE: 'DELETE', PATCH: 'PATCH', PUT: 'PUT' }, HttpDataType: { STRING: 0 },
  createHttp: () => ({
    request: async () => ({ responseCode: 200, result: '{"version":"2.0.29"}' }),
    destroy() {}, on() {}, requestInStream: async () => 200
  })
};
class StorageMock { async sessionPreferences() { return []; } async saveSessionPreferences() {} async init() {} async servers() { return []; } async secret() { return 'test-only'; } async last() { return []; } async position() {} async activeServer() { return ''; } async rememberServer() {} }
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
load('entry/src/main/ets/domain/Attachments.ts', '../domain/Attachments');
const core = load('entry/src/main/ets/domain/Core.ts', '../domain/Core');
modules.set('./Core', modules.get('../domain/Core'));
load('entry/src/main/ets/domain/Connections.ts', '../domain/Connections');
load('entry/src/main/ets/domain/SessionUsage.ts', '../domain/SessionUsage');
load('entry/src/main/ets/data/DedicatedTrust.ets', './DedicatedTrust');
load('entry/src/main/ets/domain/Agents.ts', '../domain/Agents');
load('entry/src/main/ets/domain/TranscriptExport.ts', '../domain/TranscriptExport');
load('entry/src/main/ets/data/Protocol.ets', '../data/Protocol');
load('entry/src/main/ets/presentation/ProviderStore.ets', './ProviderStore');
const notifications = load('entry/src/main/ets/domain/Notifications.ts', '../domain/Notifications');
const { AppStore } = load('entry/src/main/ets/presentation/AppStore.ets', 'store');

let count = 0;
async function test(name, run) { await run(); count++; console.log('PASS ' + name); }
const json = value => JSON.parse(JSON.stringify(value));
function recordingSink() { const events = []; return { events, publish(event) { events.push(event); } }; }
function message(id, text, state = 'completed', role = 'assistant') { return { id, role, text, reasoning: '', tools: [], parts: [], state }; }
function pending(id, sessionID = 'other', directory = '/repo', kind = 'form') {
  return { id, sessionID, directory, kind, title: 'Pending ' + id, sessionTitle: '', stale: false };
}
function makeStore(sink, foreground = true) {
  const store = new AppStore();
  store.connected = 'one';
  store.directory = '/repo';
  store.active = true;
  store.servers = [{ id: 'one', name: 'One', url: 'https://one.example', username: 'opencode', allowHttp: false }];
  store.attachNotifier(sink, foreground);
  return store;
}
// Minimal Protocol-shaped API that follows exactly what AppStore.sync reads.
function apiFor(state) {
  return {
    stream: () => () => {},
    messages: async () => ({ data: [], cursor: {} }),
    parseMessages: () => state.messages,
    interactions: async (id, kind) => state.interactions.filter(item => item.kind === kind),
    request: async path => {
      if (path === '/api/session/active') { return { data: state.active }; }
      if (path.endsWith('/inbox')) { return { data: [] }; }
      if (path.startsWith('/api/session/') && path.indexOf('/message/') < 0) { return { data: state.detail }; }
      return { data: {} };
    }
  };
}
function newState() { return { messages: [], interactions: [], active: {}, detail: { outcome: 'succeeded' } }; }
async function openBaseline(store, state, initialMessages) {
  state.messages = initialMessages || [message('m0', 'existing')];
  store.api = apiFor(state);
  await store.openSession({ id: 'ses_a', title: 'A', directory: '/repo', model: '' });
  return state;
}
function sse(type, data) { return { data: JSON.stringify({ type, data }) }; }
async function completeCurrentTask(store, state, finalState = 'completed', messageID = 'm_new') {
  state.messages = state.messages.concat([message(messageID, 'new answer', finalState)]);
  state.active = {};
  state.detail = { outcome: 'succeeded' };
  store.onFrame(sse('session.text.delta', { sessionID: 'ses_a', assistantMessageID: messageID, ordinal: 0, delta: 'x' }));
  store.onFrame(sse('session.idle', { sessionID: 'ses_a' }));
  await store.sync();
}

await test('notification keys isolate server, directory, session, kind and event ID', async () => {
  const { notificationKey, NotificationLedger } = notifications;
  const base = { serverID: 'a', directory: '/repo', sessionID: 's', kind: 'completed', eventID: 'evt_1' };
  const ledger = new NotificationLedger();
  assert.equal(ledger.offer(base), true);
  assert.equal(ledger.offer({ ...base }), false, 'the same event is only offered once');
  assert.notEqual(notificationKey(base), notificationKey({ ...base, serverID: 'b' }));
  assert.notEqual(notificationKey(base), notificationKey({ ...base, directory: '/other' }));
  assert.notEqual(notificationKey(base), notificationKey({ ...base, sessionID: 's2' }));
  assert.notEqual(notificationKey(base), notificationKey({ ...base, kind: 'failed' }));
  assert.notEqual(notificationKey(base), notificationKey({ ...base, eventID: 'evt_2' }));
  assert.equal(ledger.offer({ ...base, eventID: 'evt_1' }), false);
  // Same event ID on another server must not be suppressed by the first server.
  assert.equal(ledger.offer({ ...base, serverID: 'b' }), true);
  assert.equal(ledger.offer({ ...base, kind: 'failed' }), true);
});

await test('bounded ledger forgets the oldest keys instead of growing forever', async () => {
  const ledger = new notifications.NotificationLedger(2);
  const event = id => ({ serverID: 's', directory: '/d', sessionID: 'ses', kind: 'completed', eventID: id });
  assert.equal(ledger.offer(event('a')), true);
  assert.equal(ledger.offer(event('b')), true);
  assert.equal(ledger.offer(event('c')), true);
  assert.equal(ledger.size(), 2);
  // 'a' was evicted, so it can be offered again; this only affects very old events.
  assert.equal(ledger.offer(event('a')), true);
});

await test('visible notification text is generic and never includes content or titles', async () => {
  const kinds = ['completed', 'failed', 'question', 'approval'];
  for (const kind of kinds) {
    const text = notifications.notificationContent({
      serverID: 'srv', directory: '/secret/project', sessionID: 'ses_secret', kind,
      eventID: 'cmd=rm -rf / && apiKey=sk-must-never-appear', sessionTitle: 'confidential session title'
    });
    const visible = text.title + '\n' + text.text;
    for (const secret of ['sk-must-never-appear', 'rm -rf', '/secret', 'ses_secret', 'confidential session title']) {
      assert.ok(!visible.includes(secret), kind + ' text leaked: ' + secret);
    }
    assert.ok(text.title.length > 0 && text.text.length > 0);
  }
  assert.equal(notifications.notificationContent({ serverID: 's', directory: '', sessionID: 'x', kind: 'completed', eventID: 'e' }).title, '任务已完成');
  assert.equal(notifications.notificationContent({ serverID: 's', directory: '', sessionID: 'x', kind: 'failed', eventID: 'e' }).title, '任务未完成');
  assert.equal(notifications.notificationContent({ serverID: 's', directory: '', sessionID: 'x', kind: 'question', eventID: 'e' }).title, '有待回答的问题');
  assert.equal(notifications.notificationContent({ serverID: 's', directory: '', sessionID: 'x', kind: 'approval', eventID: 'e' }).title, '有待批准的请求');
});

await test('notification IDs are stable and server/session scoped labels never collide', async () => {
  const event = { serverID: 'srv', directory: '/repo', sessionID: 'ses', kind: 'completed', eventID: 'evt' };
  const id = notifications.notificationId(event);
  assert.equal(id, notifications.notificationId({ ...event }));
  assert.ok(id >= 1 && id <= 2147483647);
  assert.notEqual(id, notifications.notificationId({ ...event, eventID: 'evt2' }));
  assert.notEqual(notifications.notificationLabel(event), notifications.notificationLabel({ ...event, serverID: 'srv2' }));
  assert.equal(notifications.notificationLabel(event), notifications.notificationLabel({ ...event, eventID: 'other' }));
  assert.notEqual(notifications.notificationGroup(event), notifications.notificationGroup({ ...event, serverID: 'srv2' }));
});

await test('switch gating: completed/failed/pending groups and permission state', async () => {
  const { defaultReminderPrefs, shouldPublish } = notifications;
  const on = defaultReminderPrefs();
  assert.equal(shouldPublish(on, 'completed', 'enabled'), true);
  assert.equal(shouldPublish({ ...on, completed: false }, 'completed', 'enabled'), false);
  assert.equal(shouldPublish({ ...on, failed: false }, 'failed', 'enabled'), false);
  assert.equal(shouldPublish({ ...on, pending: false }, 'question', 'enabled'), false);
  assert.equal(shouldPublish({ ...on, pending: false }, 'approval', 'enabled'), false);
  for (const permission of ['disabled', 'unknown', 'unsupported']) {
    assert.equal(shouldPublish(on, 'completed', permission), false);
    assert.equal(shouldPublish(on, 'approval', permission), false);
  }
  assert.equal(shouldPublish(on, 'question', 'enabled'), true);
});

await test('reminder preferences round-trip and tolerate corrupt or partial data', async () => {
  const { encodeReminderPrefs, decodeReminderPrefs, defaultReminderPrefs, normalizeReminderPermission } = notifications;
  const prefs = { completed: false, failed: true, pending: false };
  assert.equal(JSON.stringify(json(decodeReminderPrefs(encodeReminderPrefs(prefs)))), JSON.stringify(prefs));
  assert.equal(JSON.stringify(json(decodeReminderPrefs(''))), JSON.stringify(defaultReminderPrefs()));
  assert.equal(JSON.stringify(json(decodeReminderPrefs('{broken'))), JSON.stringify(defaultReminderPrefs()));
  assert.equal(JSON.stringify(json(decodeReminderPrefs('{"failed":false}'))), JSON.stringify({ completed: true, failed: false, pending: true }));
  assert.equal(JSON.stringify(json(decodeReminderPrefs('{"completed":"yes","failed":0,"pending":null}'))), JSON.stringify(defaultReminderPrefs()));
  assert.equal(normalizeReminderPermission('enabled'), 'enabled');
  assert.equal(normalizeReminderPermission('denied'), 'unknown');
  assert.equal(normalizeReminderPermission(''), 'unknown');
});

await test('deep link parameters encode, decode and reject incomplete targets', async () => {
  const { notificationWantParameters, notificationTargetFromParameters, notificationLaunchValue, parseNotificationLaunch } = notifications;
  const target = { serverID: 'srv_1', directory: '/repo with space/中文', sessionID: 'ses/1', eventID: 'evt_9' };
  const parameters = notificationWantParameters(target);
  assert.equal(JSON.stringify(json(parameters)), JSON.stringify({
    notificationServer: 'srv_1', notificationDirectory: '/repo with space/中文', notificationSession: 'ses/1', notificationEvent: 'evt_9'
  }));
  assert.equal(JSON.stringify(json(notificationTargetFromParameters(parameters))), JSON.stringify(target));
  const launch = notificationLaunchValue(target, 1234);
  assert.equal(JSON.stringify(json(parseNotificationLaunch(launch))), JSON.stringify(target));
  assert.equal(parseNotificationLaunch(''), undefined);
  assert.equal(parseNotificationLaunch('{broken'), undefined);
  assert.equal(parseNotificationLaunch('{"notificationServer":"srv"}'), undefined, 'session is required');
  assert.equal(parseNotificationLaunch('{"notificationServer":5,"notificationSession":"s"}'), undefined, 'non-string values are ignored');
  assert.equal(JSON.stringify(json(notificationTargetFromParameters({ notificationServer: 'srv', notificationSession: 's' }))),
    JSON.stringify({ serverID: 'srv', directory: '', sessionID: 's', eventID: '' }));
  assert.equal(notificationTargetFromParameters(undefined), undefined);
});

await test('quiet reminders only cover the current conversation in the foreground', async () => {
  const { isQuietReminder, pendingNotificationKind } = notifications;
  const event = { serverID: 's', directory: '/d', sessionID: 'ses', kind: 'completed', eventID: 'e' };
  assert.equal(isQuietReminder(event, 'ses', true), true);
  assert.equal(isQuietReminder(event, 'ses', false), false);
  assert.equal(isQuietReminder(event, 'other', true), false);
  assert.equal(isQuietReminder(event, '', true), false);
  assert.equal(pendingNotificationKind('form'), 'question');
  assert.equal(pendingNotificationKind('permission'), 'approval');
});

await test('initial history and pending items are seeded without any notification', async () => {
  const sink = recordingSink();
  const store = makeStore(sink);
  const state = newState();
  state.interactions = [{ id: 'q0', sessionID: 'ses_a', kind: 'form', title: 'Question', detail: '', fields: [], state: 'pending' }];
  await openBaseline(store, state, [message('m0', 'existing')]);
  assert.equal(sink.events.length, 0, 'opening a conversation must not announce old history');
  assert.equal(store.reminderQuietSeq, 0);
});

await test('a new task completion is alerted exactly once; duplicates never repeat', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, false);
  const state = await openBaseline(store, newState());
  await completeCurrentTask(store, state);
  assert.equal(sink.events.length, 1);
  assert.equal(sink.events[0].kind, 'completed');
  assert.equal(sink.events[0].sessionID, 'ses_a');
  assert.equal(sink.events[0].directory, '/repo');
  assert.equal(sink.events[0].serverID, 'one');
  // A repeated idle sync and a duplicate SSE idle event must not alert again.
  store.onFrame(sse('session.idle', { sessionID: 'ses_a' }));
  await store.sync();
  store.onFrame(sse('session.idle', { sessionID: 'ses_a' }));
  await store.sync();
  assert.equal(sink.events.length, 1);
});

await test('failed task is reported as failed using the newest assistant state', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, false);
  const state = await openBaseline(store, newState());
  await completeCurrentTask(store, state, 'failed');
  assert.equal(sink.events.length, 1);
  assert.equal(sink.events[0].kind, 'failed');
});

await test('current conversation in the foreground only raises the quiet hint', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  const state = await openBaseline(store, newState());
  await completeCurrentTask(store, state);
  assert.equal(sink.events.length, 0);
  assert.equal(store.reminderQuiet, 'completed');
  assert.equal(store.reminderQuietSeq, 1);
  await store.sync();
  assert.equal(store.reminderQuietSeq, 1, 'the same completion cannot disturb twice');
});

await test('older history reads never announce old messages and latest re-baselines', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, false);
  const state = await openBaseline(store, newState());
  store.cursor = 'older-page';
  store.api.messages = async () => ({ data: [], cursor: { next: '' } });
  store.api.parseMessages = () => [message('very_old', 'history')];
  await store.older();
  assert.equal(store.readingHistory, true);
  state.messages = [message('very_old', 'history'), message('m0', 'existing'), message('m_new', 'new answer')];
  state.active = {};
  state.detail = { outcome: 'succeeded' };
  store.api.parseMessages = () => state.messages;
  store.onFrame(sse('session.text.delta', { sessionID: 'ses_a', assistantMessageID: 'm_new', ordinal: 0, delta: 'x' }));
  store.onFrame(sse('session.idle', { sessionID: 'ses_a' }));
  await store.sync();
  assert.equal(sink.events.length, 0, 'history reads must not alert');
  await store.latest();
  assert.equal(sink.events.length, 0, 'jumping back to the newest page is not a new event');
  assert.equal(store.readingHistory, false);
});

await test('reconnect catch-up is seeded silently; a later completion still alerts', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  const state = await openBaseline(store, newState());
  store.onFrame(sse('session.text.delta', { sessionID: 'ses_a', assistantMessageID: 'm_run', ordinal: 0, delta: 'working' }));
  store.setActive(false);
  store.setActive(true);
  await completeCurrentTask(store, state);
  assert.equal(sink.events.length, 0, 'history recovered after a reconnect must stay quiet');
  store.foreground = false;
  await completeCurrentTask(store, state, 'completed', 'm_new2');
  assert.equal(sink.events.length, 1);
});

await test('new pending question and approval are alerted after the global baseline', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  let forms = [pending('q0')];
  let permissions = [];
  store.api = {
    request: async () => ({ data: {} }),
    pending: async (directory, kind) => kind === 'form' ? forms : permissions
  };
  await store.refreshPending();
  assert.equal(sink.events.length, 0, 'existing pending items are baseline');
  forms = [pending('q0'), pending('q1', 'other')];
  permissions = [pending('p1', 'other', '/repo', 'permission')];
  await store.refreshPending();
  assert.equal(sink.events.length, 2);
  assert.deepEqual(sink.events.map(event => event.kind).sort(), ['approval', 'question']);
  assert.ok(sink.events.some(event => event.eventID === 'q1'));
  assert.ok(sink.events.some(event => event.eventID === 'p1'));
  await store.refreshPending();
  assert.equal(sink.events.length, 2, 'the same pending item is only announced once');
});

await test('pending item for the current foreground conversation stays quiet', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  store.sessionID = 'ses_a';
  let forms = [];
  store.api = { request: async () => ({ data: {} }), pending: async () => forms };
  await store.refreshPending();
  forms = [pending('q_current', 'ses_a')];
  await store.refreshPending();
  assert.equal(sink.events.length, 0);
  assert.equal(store.reminderQuiet, 'question');
  assert.equal(store.reminderQuietSeq, 1);
});

await test('a different conversation that stops running is reported as completed once', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  let active = { other: { type: 'running' } };
  store.api = { request: async path => path === '/api/session/active' ? { data: active } : { data: {} }, pending: async () => [] };
  await store.refreshPending();
  assert.equal(sink.events.length, 0, 'a task already running at baseline is not an event');
  active = {};
  await store.refreshPending();
  assert.equal(sink.events.length, 1);
  assert.equal(sink.events[0].kind, 'completed');
  assert.equal(sink.events[0].sessionID, 'other');
  await store.refreshPending();
  assert.equal(sink.events.length, 1, 'a finished session cannot alert twice');
});

await test('a throwing notifier or missing permission never breaks the chat sync', async () => {
  const store = makeStore({ publish() { throw new Error('platform notification failure'); } }, false);
  const state = await openBaseline(store, newState());
  await completeCurrentTask(store, state);
  assert.ok(store.messages.some(item => item.id === 'm_new'), 'sync still applied the message');
  assert.equal(store.error, '', 'a reminder failure is not a chat error');
});

await test('openNotificationTarget keeps the current draft and rejects unknown servers', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  const state = newState();
  state.messages = [];
  store.api = apiFor(state);
  store.sessions = [
    { id: 'ses_a', title: 'A', directory: '/repo', status: 'idle', model: '' },
    { id: 'ses_b', title: 'B', directory: '/repo', status: 'idle', model: '' }
  ];
  await store.openSession(store.sessions[0]);
  store.draft = 'draft A';
  assert.equal(await store.openNotificationTarget({ serverID: 'one', directory: '/repo', sessionID: 'ses_b', eventID: 'evt' }), true);
  assert.equal(store.sessionID, 'ses_b');
  assert.equal(store.draft, '');
  assert.equal(await store.openNotificationTarget({ serverID: 'one', directory: '/repo', sessionID: 'ses_a', eventID: 'evt' }), true);
  assert.equal(store.sessionID, 'ses_a');
  assert.equal(store.draft, 'draft A', 'unsent text is restored through the existing draft store');
  const connected = store.connected;
  assert.equal(await store.openNotificationTarget({ serverID: 'missing', directory: '/repo', sessionID: 'ses_a', eventID: 'evt' }), false);
  assert.equal(store.connected, connected, 'a missing server target cannot disconnect the current session');
  assert.match(store.error, /移除/);
  assert.equal(store.targetBusy, false);
});

await test('openNotificationTarget is re-entrant safe while a session is being resolved', async () => {
  const store = makeStore(recordingSink(), true);
  store.sessions = [];
  let release;
  store.api = {
    session: () => new Promise(resolve => { release = resolve; }),
    stream: () => () => {},
    messages: async () => ({ data: [], cursor: {} }), parseMessages: () => [],
    interactions: async () => [], request: async () => ({ data: {} })
  };
  const target = { serverID: 'one', directory: '/repo', sessionID: 'ses_b', eventID: 'evt' };
  const first = store.openNotificationTarget(target);
  assert.equal(await store.openNotificationTarget(target), false, 'a second tap is ignored while busy');
  release({ id: 'ses_b', title: 'B', directory: '/repo', status: 'idle', model: '' });
  assert.equal(await first, true);
  assert.equal(store.targetBusy, false);
});

await test('disconnecting clears reminder state and stays idempotent', async () => {
  const sink = recordingSink();
  const store = makeStore(sink, true);
  await openBaseline(store, newState());
  store.reminderQuiet = 'completed'; store.reminderQuietSeq = 4;
  store.disconnect();
  assert.equal(store.reminderQuiet, '');
  assert.equal(store.reminderQuietSeq, 0);
  assert.equal(store.foreground, true, 'foreground flag is not a connection state');
  store.setActive(false);
  assert.equal(store.foreground, false);
  store.setActive(true);
  assert.equal(store.foreground, true);
});

await test('completion identity stays the same while a message moves from streaming to completed', () => {
  const first = notifications.completionEventID('msg_done', 'ses_a');
  const second = notifications.completionEventID('msg_done', 'ses_a');
  assert.equal(first, second);
  assert.equal(first, 'idle:msg_done');
  const ledger = new notifications.NotificationLedger();
  const event = { serverID: 'one', directory: '/repo', sessionID: 'ses_a', kind: 'completed', eventID: first };
  assert.equal(ledger.offer(event), true, 'first detection is offered');
  assert.equal(ledger.offer({ ...event, kind: 'completed' }), false, 'state-only resync cannot notify twice');
});

console.log(count + ' notification tests passed.');

