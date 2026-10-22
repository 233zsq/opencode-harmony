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
class StorageMock { async modelPreferences() { return {enabled:[],favorites:[],recent:[]}; } async saveModelPreferences() {} async sessionPreferences() { return []; } async saveSessionPreferences() {} async init() {} async servers() { return []; } async secret() { return 'test-only'; } async last() { return []; } async position() {} async activeServer() { return ''; } async rememberServer() {} }
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
load('entry/src/main/ets/domain/ModelSelection.ts', '../domain/ModelSelection');
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
    session: async id => ({ id, title: id, directory: '/repo', status: 'idle', model: '' }),
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
  store.api = { request: async path => path === '/api/session/active' ? { data: active } : { data: { outcome: 'succeeded', location: { directory: '/other-repo' } } },
    messages: async () => ({}), parseMessages: () => [message('other_done', 'done')], pending: async () => [] };
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


await test('opening an already-running conversation still alerts its eventual completion', async () => {
  const sink = recordingSink(), store = makeStore(sink, false), state = newState();
  state.active = { ses_a: { type: 'running' } }; state.detail = {};
  await openBaseline(store, state, [message('running_at_open', 'working', 'streaming')]);
  assert.equal(store.working, true);
  await completeCurrentTask(store, state, 'completed', 'running_at_open');
  assert.equal(sink.events.length, 1);
});
await test('current conversation on a settings page uses a visible system reminder', async () => {
  const sink = recordingSink(), store = makeStore(sink), state = await openBaseline(store, newState());
  store.pane = 'settings'; await completeCurrentTask(store, state);
  assert.equal(sink.events.length, 1); assert.equal(store.reminderQuietSeq, 0);
});
await test('SSE transport reconnect seeds recovered interactions instead of notifying old work', async () => {
  const sink = recordingSink(), store = makeStore(sink, false), state = await openBaseline(store, newState());
  let ended; store.api.stream = (frame, data, error) => { ended = error; return () => {}; };
  store.openStream(); ended(new Error('offline'));
  state.interactions = [{ id: 'old_offline_question', sessionID: 'ses_a', kind: 'form', title: '', fields: [], state: 'pending' }];
  store.onFrame(sse('server.connected', {})); await store.sync();
  assert.equal(sink.events.length, 0);
  state.interactions.push({ id: 'fresh_question', sessionID: 'ses_a', kind: 'form', title: '', fields: [], state: 'pending' });
  await store.sync(); assert.equal(sink.events.length, 1); assert.equal(sink.events[0].eventID, 'fresh_question');
});
await test('return during the short background window suppresses catch-up but preserves later reminders', async () => {
  const sink = recordingSink(), store = makeStore(sink), state = await openBaseline(store, newState());
  store.beginBackgroundReminderWindow(20000); store.setActive(true); store.foreground = false;
  await completeCurrentTask(store, state); assert.equal(sink.events.length, 0);
  await completeCurrentTask(store, state, 'completed', 'after_resume'); assert.equal(sink.events.length, 1);
});
await test('notification resolution cannot mutate another server after its delayed response', async () => {
  const store = makeStore(recordingSink()); let release;
  store.api = { session: () => new Promise(resolve => { release = resolve; }) };
  const opening = store.openNotificationTarget({ serverID: 'one', directory: '/repo', sessionID: 'remote_a', eventID: 'e' });
  store.disconnect(); store.connected = 'two'; store.directory = '/other'; store.sessionID = 'current_b';
  store.draft = 'draft B'; store.api = apiFor(newState());
  release({ id: 'remote_a', title: 'A', directory: '/repo', status: 'idle', model: '' });
  assert.equal(await opening, false); assert.equal(store.connected, 'two');
  assert.equal(store.sessionID, 'current_b'); assert.equal(store.directory, '/other'); assert.equal(store.draft, 'draft B');
});
await test('missing notification target is resolved before replacing the visible project and draft', async () => {
  const store = makeStore(recordingSink()); store.sessionID = 'current'; store.draft = 'keep me';
  store.api = { session: async () => { throw new Error('gone'); } };
  const opened = await store.openNotificationTarget({ serverID: 'one', directory: '/missing', sessionID: 'gone', eventID: 'e' });
  assert.equal(opened, false); assert.equal(store.directory, '/repo'); assert.equal(store.sessionID, 'current'); assert.equal(store.draft, 'keep me');
});
await test('a disabled reminder group also disables the foreground quiet hint', async () => {
  const sink = recordingSink(); sink.accepts = () => false;
  const store = makeStore(sink), state = await openBaseline(store, newState());
  await completeCurrentTask(store, state); assert.equal(store.reminderQuietSeq, 0); assert.equal(sink.events.length, 0);
});
await test('partial reconnect pending reads retain suppression until all old scopes are seeded', async () => {
  const sink = recordingSink(), store = makeStore(sink); let failing = false, forms = [];
  store.api = { request: async () => ({ data: {} }), pending: async (d, kind) => {
    if (failing && kind === 'form') throw new Error('offline'); return kind === 'form' ? forms : [];
  } };
  await store.refreshPending(); store.setActive(false); store.active = true; failing = true;
  await store.refreshPending(); failing = false; forms = [pending('old_after_outage')]; await store.refreshPending();
  assert.equal(sink.events.length, 0);
  forms.push(pending('new_after_recovery')); await store.refreshPending(); assert.equal(sink.events.length, 1);
});

let systemEnabled = false, settingsOpened = 0, permissionRequests = 0;
let preferenceStore, getPreferences = async () => preferenceStore;
const permissionAPI = {
  isNotificationEnabled: async () => systemEnabled,
  requestEnableNotification: async () => { permissionRequests++; throw Object.assign(new Error('declined'), { code: 1600004 }); },
  openNotificationSettings: async () => { settingsOpened++; }
};
modules.set('@kit.NotificationKit', { notificationManager: permissionAPI });
modules.set('@kit.ArkData', { preferences: { getPreferences: (...args) => getPreferences(...args) } });
const { NotificationCenter } = load('entry/src/main/ets/presentation/NotificationCenter.ets', 'notification-center');
function prefsStore(initial = {}) {
  const data = { ...initial }; return { data, get: async (key, fallback) => key in data ? data[key] : fallback,
    put: async (key, value) => { data[key] = value; }, flush: async () => {} };
}
await test('permission refresh during startup cannot overwrite saved disabled reminder switches', async () => {
  preferenceStore = prefsStore({ completed: false, failed: false, pending: false });
  let release; let calls = 0;
  getPreferences = async () => ++calls === 1 ? new Promise(resolve => { release = resolve; }) : preferenceStore;
  const center = new NotificationCenter(); center.attachContext({}); const loading = center.load();
  await center.refreshPermission(); release(preferenceStore); await loading;
  assert.equal(center.completed, false); assert.equal(center.failed, false); assert.equal(center.pending, false);
  assert.equal(preferenceStore.data.completed, false); assert.equal(preferenceStore.data.failed, false);
});
await test('first permission rejection ends the action; only the next explicit action opens settings', async () => {
  preferenceStore = prefsStore(); getPreferences = async () => preferenceStore;
  permissionRequests = 0; settingsOpened = 0;
  const center = new NotificationCenter(); center.attachContext({}); await center.load();
  await center.requestPermission(); assert.equal(permissionRequests, 1); assert.equal(settingsOpened, 0);
  await center.requestPermission(); assert.equal(permissionRequests, 1); assert.equal(settingsOpened, 1);
});


await test('other-session failures use failure preferences and the confirmed project directory', async () => {
  const sink = recordingSink(); sink.accepts = kind => kind === 'failed';
  const store = makeStore(sink); let active = { remote: { type: 'running' } };
  store.api = { request: async path => path === '/api/session/active' ? { data: active } : { data: { outcome: 'failed', location: { directory: '/second-project' } } },
    messages: async () => ({}), parseMessages: () => [message('remote_failure', 'error', 'failed')], pending: async () => [] };
  await store.refreshPending(); active = {}; await store.refreshPending();
  assert.equal(sink.events.length, 1); assert.equal(sink.events[0].kind, 'failed');
  assert.equal(sink.events[0].directory, '/second-project');
  await store.refreshPending(); assert.equal(sink.events.length, 1);
});
await test('a task that starts and ends between polls is observed through SSE without a false success', async () => {
  const sink = recordingSink(), store = makeStore(sink); store.sessionID = 'ses_a';
  store.api = { request: async path => path === '/api/session/active' ? { data: {} } : { data: { outcome: 'failed', location: { directory: '/remote' } } },
    messages: async () => ({}), parseMessages: () => [message('quick_failure', 'error', 'failed')], pending: async () => [] };
  await store.refreshPending();
  store.onFrame(sse('session.text.delta', { sessionID: 'quick', assistantMessageID: 'quick_failure', ordinal: 0, delta: 'x' }));
  store.onFrame(sse('session.idle', { sessionID: 'quick' })); await store.refreshPending();
  assert.equal(sink.events.length, 1); assert.equal(sink.events[0].sessionID, 'quick'); assert.equal(sink.events[0].kind, 'failed');
});
await test('a removed active ID without a confirmed terminal outcome is not reported as success', async () => {
  const sink = recordingSink(), store = makeStore(sink); let active = { unknown: { type: 'running' } };
  store.api = { request: async path => path === '/api/session/active' ? { data: active } : { data: { location: { directory: '/remote' } } },
    messages: async () => ({}), parseMessages: () => [], pending: async () => [] };
  await store.refreshPending(); active = {}; await store.refreshPending();
  assert.equal(sink.events.length, 0);
});
await test('completion readback cannot send a stale reminder after switching connections', async () => {
  const sink = recordingSink(), store = makeStore(sink); let active = { remote: {} }, release;
  store.api = { request: async path => path === '/api/session/active' ? { data: active } : new Promise(resolve => { release = resolve; }),
    messages: async () => ({}), parseMessages: () => [message('remote_done', 'done')], pending: async () => [] };
  await store.refreshPending(); active = {}; const refreshing = store.refreshPending();
  while (!release) await Promise.resolve();
  store.disconnect(); store.connected = 'two'; store.api = apiFor(newState());
  release({ data: { outcome: 'succeeded', location: { directory: '/remote' } } }); await refreshing;
  assert.equal(sink.events.length, 0); assert.equal(store.connected, 'two');
});
await test('the same task cannot be notified again after moving away from its chat', async () => {
  const sink = recordingSink(), store = makeStore(sink), state = newState();
  state.active = { ses_a: {} }; state.detail = {};
  await openBaseline(store, state, [message('task_one', 'working', 'streaming')]);
  await store.refreshPending(); await completeCurrentTask(store, state, 'completed', 'task_one');
  assert.equal(store.reminderQuietSeq, 1); store.sessionID = 'ses_b';
  store.api.request = async path => path === '/api/session/active' ? { data: {} } : { data: { outcome: 'succeeded', location: { directory: '/repo' } } };
  store.api.pending = async () => []; await store.refreshPending(); assert.equal(sink.events.length, 0);
});
await test('a covered chat uses a system reminder rather than an invisible quiet hint', async () => {
  const sink = recordingSink(), store = makeStore(sink), state = await openBaseline(store, newState());
  store.conversationVisible = false; await completeCurrentTask(store, state);
  assert.equal(sink.events.length, 1); assert.equal(store.reminderQuietSeq, 0);
});
await test('failed baseline interaction reads stay quiet until all recovered lists are seeded', async () => {
  const sink = recordingSink(), store = makeStore(sink, false), state = newState();
  store.api = apiFor(state); let fail = true;
  store.api.interactions = async (id, kind) => { if (kind === 'form' && fail) throw new Error('offline'); return kind === 'form' ? state.interactions : []; };
  await store.openSession({ id: 'ses_a', title: 'A', directory: '/repo', model: '' });
  fail = false; state.interactions = [{ id: 'old_recovered', sessionID: 'ses_a', kind: 'form', title: '', fields: [], state: 'pending' }];
  await store.sync(); assert.equal(sink.events.length, 0);
  state.interactions.push({ id: 'new_question', sessionID: 'ses_a', kind: 'form', title: '', fields: [], state: 'pending' });
  await store.sync(); assert.equal(sink.events.length, 1);
});


await test('a transient reminder preference read failure never replaces saved disabled switches', async () => {
  preferenceStore = prefsStore({ completed: false, failed: false, pending: false });
  const read = preferenceStore.get; let fail = true;
  preferenceStore.get = async (...args) => { if (fail) { fail = false; throw new Error('temporary read failure'); } return read(...args); };
  getPreferences = async () => preferenceStore;
  const center = new NotificationCenter(); center.attachContext({}); await center.load();
  assert.equal(preferenceStore.data.completed, false); assert.equal(preferenceStore.data.failed, false); assert.equal(preferenceStore.data.pending, false);
  await center.setGroup('failed', true);
  assert.equal(preferenceStore.data.failed, true); assert.equal(preferenceStore.data.completed, false); assert.equal(preferenceStore.data.pending, false);
});
await test('a notification connect superseded by user navigation cannot replace the selected session', async () => {
  const { Protocol } = modules.get('../data/Protocol'); const proto = Protocol.prototype;
  const names = ['request', 'projects', 'stream', 'messages', 'parseMessages', 'interactions', 'session'];
  const originals = Object.fromEntries(names.map(name => [name, proto[name]]));
  try {
    proto.request = async path => path === '/api/info' ? { version: '2.0.29' } : path.endsWith('/inbox') ? { data: [] } : { data: {} };
    proto.projects = async () => []; proto.stream = () => () => {};
    proto.messages = async () => ({ data: [] }); proto.parseMessages = () => []; proto.interactions = async () => [];
    proto.session = async id => ({ id, title: id, directory: '/repo', model: '', status: 'idle' });
    const store = makeStore(recordingSink());
    store.servers.push({ id: 'two', name: 'Two', url: 'https://two.example', username: 'opencode', allowHttp: false });
    let release; store.storage.last = () => new Promise(resolve => { release = resolve; });
    const opening = store.openNotificationTarget({ serverID: 'two', directory: '/repo', sessionID: 'notification_task', eventID: 'e' });
    while (!release) await Promise.resolve();
    await store.openSession({ id: 'user_selected', title: 'User selected', directory: '', model: '', status: 'idle' });
    release([]); assert.equal(await opening, false); assert.equal(store.sessionID, 'user_selected'); assert.equal(store.connected, 'two');
  } finally { Object.assign(proto, originals); }
});


await test('a successful notification connection may restore its remembered project before opening the target', async () => {
  const { Protocol } = modules.get('../data/Protocol'); const proto = Protocol.prototype;
  const names = ['request', 'projects', 'stream', 'messages', 'parseMessages', 'interactions', 'session', 'sessionPage', 'models', 'agents'];
  const originals = Object.fromEntries(names.map(name => [name, proto[name]]));
  try {
    proto.request = async path => path === '/api/info' ? { version: '2.0.29' } : path.endsWith('/inbox') ? { data: [] } : { data: {} };
    proto.projects = async () => []; proto.stream = () => () => {};
    proto.messages = async () => ({ data: [] }); proto.parseMessages = () => []; proto.interactions = async () => [];
    proto.session = async id => ({ id, title: id, directory: '/repo', model: '', status: 'idle' });
    proto.sessionPage = async () => ({ sessions: [], cursor: '' }); proto.models = async () => []; proto.agents = async () => [];
    const store = makeStore(recordingSink());
    store.servers.push({ id: 'two', name: 'Two', url: 'https://two.example', username: 'opencode', allowHttp: false });
    store.storage.last = async () => ['/repo', 'remembered'];
    assert.equal(await store.openNotificationTarget({ serverID: 'two', directory: '/repo', sessionID: 'notification_task', eventID: 'e' }), true);
    assert.equal(store.sessionID, 'notification_task'); assert.equal(store.directory, '/repo'); assert.equal(store.connected, 'two'); assert.equal(store.busy, false);
  } finally { Object.assign(proto, originals); }
});

console.log(count + ' notification tests passed.');

