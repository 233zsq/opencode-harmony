import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createRequire } from 'node:module';
import { resolve } from 'node:path';
const require = createRequire(import.meta.url);
const ide = process.env.DEVECO_STUDIO_HOME || 'C:/Program Files/Huawei/DevEco Studio';
const ts = require(resolve(ide, 'sdk/default/openharmony/ets/build-tools/ets-loader/node_modules/typescript/lib/typescript.js'));
const source = readFileSync(new URL('../entry/src/main/ets/domain/Core.ts', import.meta.url), 'utf8');
const emitted = ts.transpileModule(source, { compilerOptions: { module: ts.ModuleKind.ES2022, target: ts.ScriptTarget.ES2022 } }).outputText;
const core = await import('data:text/javascript;base64,' + Buffer.from(emitted).toString('base64'));
let count = 0;
function test(name, run) { run(); count++; console.log('PASS ' + name); }
const { SseParser, mergeMessages, applyTextDelta, parseDiff, parseMarkdown, normalizeUrl } = core;
test('CRLF split, multiple data lines, id and retry', () => {
  const p = new SseParser();
  assert.deepEqual(p.feed(': heartbeat\r'), []);
  assert.deepEqual(p.feed('\nid: evt1\r\nevent: part\r\ndata:one\r\ndata: two\r'), []);
  assert.deepEqual(p.feed('\nretry: 500\n\n'), [{ event: 'part', data: 'one\ntwo', id: 'evt1', retry: 500 }]);
});
test('UTF-8 byte splits preserve Chinese and emoji', () => {
  const source = new TextEncoder().encode('data: {"text":"中文🌿"}\n\n');
  const decoder = new TextDecoder();
  const parser = new SseParser();
  const out = [];
  for (const byte of source) out.push(...parser.feed(decoder.decode(new Uint8Array([byte]), { stream: true })));
  assert.equal(out.length, 1);
  assert.deepEqual(JSON.parse(out[0].data), { text: '中文🌿' });
});
test('empty data dispatches, comments do not', () => {
  const p = new SseParser();
  assert.equal(p.feed(': only comment\n\ndata:\n\n').length, 1);
});
test('buffer is bounded', () => assert.throws(() => new SseParser(16).feed('data:' + 'x'.repeat(20)), /事件过大/));
const msg = (id, text, state = 'completed') => ({ id, role: 'assistant', text, reasoning: '', parts: [{ ordinal: 0, type: 'text', text }], tools: [], state });
test('stable-ID history merge preserves unchanged object', () => {
  const a = msg('a', 'one'); const b = msg('b', 'two');
  const result = mergeMessages([a], [msg('a', 'one'), b]);
  assert.equal(result[0], a); assert.equal(result.length, 2);
});
test('older page does not duplicate IDs or reverse chronology', () => {
  assert.deepEqual(mergeMessages([msg('b', 'b'), msg('c', 'c')], [msg('a', 'a'), msg('b', 'b')], true).map(m => m.id), ['a', 'b', 'c']);
});
test('ended event replaces accumulated delta instead of appending', () => {
  let messages = applyTextDelta([], 'a', 1, 'text', '你', false);
  messages = applyTextDelta(messages, 'a', 1, 'text', '好', false);
  messages = applyTextDelta(messages, 'a', 1, 'text', '你好', true);
  assert.equal(messages[0].text, '你好');
});
test('reasoning and interleaved text ordinals are independent', () => {
  let messages = applyTextDelta([], 'a', 0, 'reasoning', '思考', false);
  messages = applyTextDelta(messages, 'a', 2, 'text', '后', false);
  messages = applyTextDelta(messages, 'a', 1, 'text', '前', false);
  assert.equal(messages[0].text, '前\n后'); assert.equal(messages[0].reasoning, '思考');
});
test('diff headers do not increment line numbers', () => {
  const rows = parseDiff('--- a/f\n+++ b/f\n@@ -3,2 +4,2 @@\n-old\n+new\n same');
  assert.equal(rows[3].oldLine, '3'); assert.equal(rows[4].newLine, '4');
  assert.equal(rows[5].oldLine, '4'); assert.equal(rows[5].newLine, '5');
});
test('unfinished streaming code fence remains a code block', () => {
  assert.equal(parseMarkdown('# Heading\n' + String.fromCharCode(96).repeat(3) + 'ts\nconst a = 1;')[1].kind, 'code');
});
test('reverse proxy URL prefix retained and trailing slash removed', () => {
  assert.equal(normalizeUrl('https://example.com/agent/', false), 'https://example.com/agent');
});
test('credentials in URL and insecure HTTP require explicit choice', () => {
  assert.throws(() => normalizeUrl('https://u:p@example.com', false));
  assert.throws(() => normalizeUrl('http://127.0.0.1:4210', false));
  assert.equal(normalizeUrl('http://127.0.0.1:4210', true), 'http://127.0.0.1:4210');
});


test('conditional forms omit inactive stale answers and use native defaults', () => {
  const field = (key, type, text, constraints = {}) => ({ key, type, text, constraints, label: key, required: false, options: [], values: [] });
  const fields = [
    field('enabled', 'boolean', '', { initial: false }),
    field('count', 'integer', '3', { when: [{ key: 'enabled', op: 'eq', value: true }] }),
    field('fallback', 'string', 'yes', { when: [{ key: 'enabled', op: 'eq', value: false }] })
  ];
  assert.deepEqual(core.buildFormAnswer(fields), { enabled: false, fallback: 'yes' });
});
test('unanswered condition is false for both eq and neq', () => {
  const field = { key: 'child', label: 'child', type: 'string', required: true, options: [], values: [], text: 'stale',
    constraints: { when: [{ key: 'missing', op: 'neq', value: 'x' }] } };
  assert.deepEqual(core.buildFormAnswer([field]), {});
});
test('closed options reject custom strings and boolean false is valid', () => {
  const field = { key: 'choice', label: 'choice', type: 'string', required: true,
    options: [{ value: 'a', label: 'A', description: '' }], values: [], text: 'bad' };
  assert.throws(() => core.buildFormAnswer([field]), /有效选项/);
  assert.deepEqual(core.buildFormAnswer([{ ...field, key: 'bool', type: 'boolean', options: [], text: 'false' }]), { bool: false });
});
test('hidden default is included but not displayed, numeric range is enforced', () => {
  const f = { key: 'n', label: 'number', type: 'integer', required: true, options: [], values: [], text: '',
    constraints: { hidden: true, initial: 4, minimum: 1, maximum: 5 } };
  assert.deepEqual(core.buildFormAnswer([f]), { n: 4 }); assert.deepEqual(core.visibleFormFields([f]), []);
  assert.throws(() => core.buildFormAnswer([{ ...f, text: '2.5' }]), /有效数字/);
});
test('inline Markdown bold, code and link labels are rendered without delimiters', () => {
  assert.equal(core.inlineMarkdown('**bold** and ' + String.fromCharCode(96) + 'code' + String.fromCharCode(96) + ' [link](https://example.com)').map(p => p.text).join(''), 'bold and code link');
});

console.log(count + ' core tests passed.');
