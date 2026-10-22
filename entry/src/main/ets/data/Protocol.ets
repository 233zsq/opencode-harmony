import { SessionUsage, usageValue, CompactRecord } from '../domain/SessionUsage';
import { AgentItem, selectableAgents } from '../domain/Agents';
import { ExportPage } from '../domain/TranscriptExport';
import { Attachment, historyAttachment } from '../domain/Attachments';
import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { DEDICATED_CA, DEDICATED_SPKI } from './DedicatedTrust';
import { ChatMessage, TextPart, ToolItem, SseParser, SseFrame, ServerConfig, ProjectItem, SessionItem,
  SessionPage, PendingItem, TimelineEntry, ModelItem, Interaction, FormField, Choice, FileItem, DiffItem, FieldValue, FormCondition, FieldConstraints, ApprovalPreview, ApprovalFile, previewText } from '../domain/Core';

export type Json = Record<string, Object>;
export function object(value: Object | undefined | null): Json { return value ? value as Json : {}; }
export function list(value: Object | undefined | null): Object[] { return Array.isArray(value) ? value as Object[] : []; }
export function string(value: Object | undefined | null, fallback: string = ''): string {
  return typeof value === 'string' ? value as string : fallback;
}
export function json(value: Object | undefined): string { return value === undefined ? '' : JSON.stringify(value, null, 2); }
export function rows(value: Object): Object[] {
  return Array.isArray(value) ? value as Object[] : list(object(value)['data']);
}

export function parseFields(value: Object | undefined): FormField[] {
  const fields: FormField[] = [];
  list(value).forEach((value: Object) => {
  const f = object(value); const options: Choice[] = list(f['options']).map((choice: Object): Choice => {
    const c = object(choice);
    return { value: string(c['value']), label: string(c['label'], string(c['value'])), description: string(c['description']) };
  });
  fields.push({ key: string(f['key']), label: string(f['title'], string(f['key'])), type: string(f['type'], 'string'),
    required: f['required'] === true, options: options,
    values: Array.isArray(f['default']) ? list(f['default']).map((v: Object) => string(v)) : [],
    text: typeof f['default'] === 'string' || typeof f['default'] === 'number' || typeof f['default'] === 'boolean' ? String(f['default']) : '',
    constraints: { hidden: f['hidden'] === true, custom: f['custom'] === true, initial: f['default'] as FieldValue,
      when: list(f['when']).map((v: Object): FormCondition => ({ key: string(object(v)['key']), op: string(object(v)['op']), value: object(v)['value'] as FieldValue })),
      minimum: f['minimum'] as number, maximum: f['maximum'] as number, minLength: f['minLength'] as number,
      maxLength: f['maxLength'] as number, minItems: f['minItems'] as number, maxItems: f['maxItems'] as number,
      pattern: string(f['pattern']), format: string(f['format']), url: string(f['url']) } as FieldConstraints });
});
  return fields;
}

interface HistoryCursor { next: string; }
interface HistoryPage { data: Object[]; cursor: HistoryCursor; }
interface ForkRequest { before?: string; }
interface CompactRequest { id: string; delivery: string; }
interface RenameSessionRequest { title: string; }
interface ApprovalPatchInput { file: string; patch: string; }

export function parseApproval(request: Json): ApprovalPreview {
  const metadata = object(request['metadata']); let incomplete = false;
  const bounded = (value: string): string => { if (value.length > 12000) { incomplete = true; } return value.slice(0, 12000); };
  let raw = list(metadata['files']);
  const patch = string(metadata['patch'], string(metadata['diff']));
  if (raw.length === 0 && patch) {
    const candidate: ApprovalPatchInput = { file: string(metadata['file'], string(metadata['path'], string(list(request['resources'])[0], '文件修改'))), patch: patch };
    raw = [candidate];
  }
  if (metadata['files'] !== undefined && !Array.isArray(metadata['files'])) { incomplete = true; }
  const files: ApprovalFile[] = raw.slice(0, 20).map((value: Object): ApprovalFile => {
    const file = object(value); const path = bounded(string(file['file'], string(file['path'])));
    const preview = previewText(string(file['patch'], string(file['diff'])));
    if (preview.truncated || !path) { incomplete = true; }
    return { path: path || '未提供文件名', patch: preview.text, status: string(file['status'], 'modified'),
      additions: typeof file['additions'] === 'number' ? Number(file['additions']) : 0,
      deletions: typeof file['deletions'] === 'number' ? Number(file['deletions']) : 0 };
  });
  const command = bounded(string(metadata['command'])); const directory = bounded(string(metadata['workdir'], string(metadata['cwd'], string(metadata['root'], string(metadata['path'])))));
  const pattern = bounded(string(metadata['pattern'])); const reason = bounded(string(request['message'], string(metadata['description'])));
  const resources = list(request['resources']).map((v: Object): string => string(v)).join('\n');
  if (raw.length > 20 || resources.length > 12000) { incomplete = true; }
  return { command: command, directory: directory, pattern: pattern, reason: reason,
    source: string(object(request['source'])['type']) === 'tool' ? 'Agent 工具' : '服务器请求',
    files: files, omittedFiles: Math.max(0, raw.length - files.length), incomplete: incomplete,
    expectsDiff: /edit|write|patch/.test(string(request['action'])) };
}

export class ApiError extends Error {
  code: number;
  constructor(code: number, message: string) { super(message); this.code = code; }
}

export function networkError(error: Error): Error {
  const code = (error as BusinessError).code;
  if (code === 2300060 || code === 2300077 || code === 2300058 || code === 2300090) {
    return new ApiError(495, '服务器证书校验失败，请核对地址、专用证书选项及证书有效期');
  }
  return error;
}
export function parseUsage(detail: Json): SessionUsage {
    const tokens = object(detail['tokens']); const cache = object(tokens['cache']);
    return { input: usageValue(tokens['input']), output: usageValue(tokens['output']), reasoning: usageValue(tokens['reasoning']), cacheRead: usageValue(cache['read']), cacheWrite: usageValue(cache['write']), cost: usageValue(detail['cost']) };
  }

export function parseCompactRecord(value: Object): CompactRecord {
    const message = object(value); const state = string(message['status']);
    return { id: string(message['id']), state: ['running', 'completed', 'failed'].indexOf(state) >= 0 ? state : 'unknown', error: state === 'failed' ? string(object(message['error'])['message'], '服务器压缩失败，请检查模型与上下文').slice(0, 500) : '' };
  }

export class Protocol {
  private compactHistory: Set<string> = new Set<string>();
  private thinHistory: boolean = false;
  async enableHistoryCache(): Promise<void> {
    try { const result = object(object(await this.request('/client-cache/capabilities'))['data']); this.thinHistory = result['version'] === 1; }
    catch (e) { if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { throw e; } this.thinHistory = false; }
  }
  private historyPath(id: string): string { return (this.thinHistory ? '/client-cache/session/' : '/api/session/') + encodeURIComponent(id) + '/message'; }
  async historyFile(id: string, item: Attachment): Promise<Attachment> {
    if (!this.thinHistory || !item.remoteMessage || !/^[a-f0-9]{64}$/.test(item.remoteHash || '') || item.remoteIndex === undefined) { throw new Error('附件信息已失效'); }
    const value = object(object(await this.request(this.historyPath(id) + '/' + encodeURIComponent(item.remoteMessage) + '/file/' + item.remoteIndex + '?sha256=' + item.remoteHash))['data']);
    if (string(value['sha256']) !== item.remoteHash) { throw new Error('附件校验失败'); }
    const file = historyAttachment(item.id, item.name, item.mime, string(value['data']));
    return { id: file.id, name: file.name, mime: file.mime, data: file.data, size: file.size, error: file.error,
      fingerprint: item.remoteHash, remoteHash: item.remoteHash, remoteMessage: item.remoteMessage, remoteIndex: item.remoteIndex };
  }
  private auth: string;
  config: ServerConfig;
  constructor(config: ServerConfig, password: string) {
    if (config.useDedicatedTrust && !config.url.startsWith('https://')) { throw new ApiError(0, '专用证书连接必须使用 HTTPS'); }
    this.config = config;
    this.auth = password ? 'Basic ' + new util.Base64Helper().encodeToStringSync(
      new util.TextEncoder().encodeInto(config.username + ':' + password)) : '';
  }
  private options(): http.HttpRequestOptions {
    const options: http.HttpRequestOptions = { connectTimeout: 10000, readTimeout: 20000, maxRedirects: 0,
      remoteValidation: 'system' };
    if (this.config.useDedicatedTrust) {
      options.caData = DEDICATED_CA;
      options.certificatePinning = { publicKeyHash: DEDICATED_SPKI, hashAlgorithm: 'SHA-256' };
    }
    return options;
  }
  scope(directory: string): string { return 'location%5Bdirectory%5D=' + encodeURIComponent(directory); }
  async request(path: string, method: http.RequestMethod = http.RequestMethod.GET, body: Object | undefined = undefined,
    raw: boolean = false): Promise<Object> {
    const task = http.createHttp();
    const headers: Record<string, string> = { 'Accept': raw ? '*/*' : 'application/json' };
    if (this.auth) { headers['Authorization'] = this.auth; }
    if (body !== undefined) { headers['Content-Type'] = 'application/json'; }
    try {
      const options = this.options();
      options.method = method; options.header = headers;
      options.extraData = body === undefined ? undefined : JSON.stringify(body);
      options.expectDataType = http.HttpDataType.STRING; options.maxLimit = 2097152;
      const result = await task.request(this.config.url + path, options);
      const text = typeof result.result === 'string' ? result.result : '';
      if (result.responseCode < 200 || result.responseCode >= 300) {
        const reason = result.responseCode === 401 || result.responseCode === 403 ? '认证失败，请检查 API 账号和密码' :
          result.responseCode === 429 ? '服务器请求过于频繁，请稍后重试' :
          '服务器返回 HTTP ' + result.responseCode;
        throw new ApiError(result.responseCode, reason);
      }
      if (raw) { return text; }
      if (result.responseCode === 204 || text.trim().length === 0) { return {} as Json; }
      if (!/^[\[{]/.test(text.trim())) { throw new ApiError(0, '地址返回了网页，并非 OpenCode API。请检查地址及代理子路径'); }
      return JSON.parse(text) as Object;
    } catch (e) { throw networkError(e as Error); } finally { task.destroy(); }
  }
  async projects(): Promise<ProjectItem[]> {
    const response = await this.request('/api/project');
    return rows(response).map((v: Object): ProjectItem => {
      const p = object(v);
      const directory = string(p['canonical']);
      return { id: string(p['id']), name: string(p['name'], directory.split('/').pop() || directory), directory: directory };
    });
  }
  parseSession(value: Object, directory: string = ''): SessionItem {
    const s = object(value); const location = object(s['location']); const model = object(s['model']);
    return { id: string(s['id']), title: string(s['title'], '未命名会话'), directory: string(location['directory'], directory),
      status: 'idle', model: model['id'] ? string(model['providerID']) + '/' + string(model['id']) : '',
      variant: string(model['variant']), agent: string(s['agent']), parentID: string(object(s['fork'])['sessionID'], string(s['parentID'])), forkType: string(object(object(s['fork'])['boundary'])['type']), forkBefore: string(object(object(s['fork'])['boundary'])['messageID']), updated: Number(object(s['time'])['updated']) || 0, archived: !!object(s['time'])['archived'] };
  }
  async session(id: string): Promise<SessionItem> {
    const session = this.parseSession(object(await this.request('/api/session/' + encodeURIComponent(id)))['data']);
    if (session.id !== id) { throw new ApiError(0, '服务器返回的会话标识不匹配'); }
    return session;
  }
  async sessionPage(directory: string, cursor: string = '', search: string = ''): Promise<SessionPage> {
    const query = cursor ? 'cursor=' + encodeURIComponent(cursor) : 'order=desc' +
      (directory ? '&directory=' + encodeURIComponent(directory) : '') + (search.trim() ? '&search=' + encodeURIComponent(search.trim()) : '');
    const response = await this.request('/api/session?limit=50&' + query);
    return { sessions: rows(response).map((v: Object): SessionItem => this.parseSession(v, directory)).filter((s: SessionItem) => !!s.id),
      cursor: string(object(object(response)['cursor'])['next']) };
  }
  async sessions(directory: string): Promise<SessionItem[]> { return (await this.sessionPage(directory)).sessions; }
  async renameSession(id: string, title: string): Promise<void> {
    await this.request('/api/session/' + encodeURIComponent(id), 'PATCH' as http.RequestMethod, { title: title } as RenameSessionRequest);
  }
  async pending(directory: string, kind: string): Promise<PendingItem[]> {
    const response = await this.request((kind === 'form' ? '/api/form?' : '/api/permission/request?') + this.scope(directory));
    return rows(response).map((v: Object): PendingItem => {
      const p = object(v);
      return { id: string(p['id']), sessionID: string(p['sessionID']), directory: directory, kind: kind,
        title: string(p['title'], string(p['action'], kind === 'form' ? '需要回答' : '需要审批')), sessionTitle: '', stale: false };
    }).filter((p: PendingItem) => !!p.id && !!p.sessionID);
  }
  async models(directory: string): Promise<ModelItem[]> {
    return rows(await this.request('/api/model?' + this.scope(directory))).map((v: Object): ModelItem => {
      const m = object(v);
      const variants = Array.from(new Set(list(m['variants']).map((value: Object): string => string(object(value)['id'])).filter((id: string) => !!id && id.length <= 200)));
      return { available: m['enabled'] !== false, variants: variants, id: string(m['providerID']) + '/' + string(m['modelID']), label: string(m['name'], string(m['modelID'])), input: list(object(m['capabilities'])['input']).map((v: Object) => string(v)), contextLimit: usageValue(object(m['limit'])['context']) };
    }).filter((m: ModelItem) => !m.id.endsWith('/'));
  }
  async fork(id: string, before: string): Promise<SessionItem> {
    const result = await this.request('/api/session/' + encodeURIComponent(id) + '/fork', http.RequestMethod.POST, { before: before || undefined } as ForkRequest);
    const child = this.parseSession(object(result)['data']);
    if (!child.id || child.id === id || child.parentID !== id || (before ? child.forkType !== 'before' || child.forkBefore !== before : child.forkType !== 'through')) { throw new Error('分叉结果未能确认，请检查会话列表'); } return child;
  }
  async compact(id: string, requestID: string): Promise<void> {
    const result = object(object(await this.request('/api/session/' + encodeURIComponent(id) + '/compact', http.RequestMethod.POST, { id: requestID, delivery: 'queue' } as CompactRequest))['data']);
    if (result['id'] !== requestID || result['sessionID'] !== id || result['type'] !== 'compaction') { throw new Error('压缩提交结果待核对'); }
  }
  async compactionStatus(id: string, requestID: string): Promise<CompactRecord> {
    try {
      const message = object(object(await this.request('/api/session/' + encodeURIComponent(id) + '/message/' + encodeURIComponent(requestID)))['data']);
      if (message['id'] !== requestID || message['type'] !== 'compaction') { throw new Error('压缩记录与请求不一致'); } return parseCompactRecord(message);
    } catch (e) { if (!(e instanceof ApiError) || e.code !== 404) { throw e as Error; } }
    const inbox = rows(await this.request('/api/session/' + encodeURIComponent(id) + '/inbox'));
    return { id: requestID, state: inbox.some((item: Object) => object(item)['id'] === requestID && object(item)['type'] === 'compaction') ? 'queued' : 'unknown', error: '' };
  }
  async agents(directory: string): Promise<AgentItem[]> {
    return selectableAgents(rows(await this.request('/api/agent?' + this.scope(directory))).map((value: Object): AgentItem => {
      const a = object(value); const model = object(a['model']);
      return { id: string(a['id']), name: string(a['name'], string(a['id'])).slice(0, 200), description: string(a['description']).slice(0, 2000),
        mode: string(a['mode']), hidden: a['hidden'] === true, model: model['id'] ? string(model['providerID']) + '/' + string(model['id']) : '' };
    }));
  }
  async exportBoundary(id: string): Promise<string> {
    const response = await this.request('/api/session/' + encodeURIComponent(id) + '/message?limit=1&order=desc');
    const data = rows(response); const boundary = string(object(data[0])['id']);
    if (data.length && !boundary) { throw new Error('历史消息缺少标识，导出未完成'); } return boundary;
  }
  async exportPage(id: string, cursor: string): Promise<ExportPage> {
    const base = '/api/session/' + encodeURIComponent(id) + '/message?';
    const query = cursor ? 'cursor=' + encodeURIComponent(cursor) : 'order=asc';
    let response: Object;
    try { response = await this.request(base + 'limit=30&' + query); }
    catch (e) { if (e instanceof ApiError) { throw e; } response = await this.request(base + 'limit=1&' + query); }
    const raw = rows(response); const ids = raw.map((value: Object): string => string(object(value)['id']));
    if (ids.some((id: string) => !id)) { throw new Error('历史消息缺少标识，导出未完成'); }
    const messages = this.parseMessages(response).reverse().map((message: ChatMessage): ChatMessage => {
      const source = object(raw.find((value: Object) => string(object(value)['id']) === message.id));
      const files = list(source['files']).map((value: Object, index: number): Attachment => {
        const file = object(value); const data = string(file['data']);
        return { id: message.id + '-file-' + index, name: string(file['name']).replace(/[\x00-\x1f]/g, '').slice(0, 160) || '附件', mime: string(file['mime']).slice(0, 160), data: '',
          size: Math.max(0, Math.floor(data.length * 3 / 4) - (data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0)) };
      });
      return { id: message.id, role: message.role, text: message.text, reasoning: '', parts: [], tools: message.tools, state: message.state, files: files };
    });
    return { messages: messages, ids: ids, cursor: string(object(object(response)['cursor'])['next']) };
  }
  async messages(id: string, cursor: string = ''): Promise<Object> {
    if (this.compactHistory.has(id)) { return this.smallMessages(id, cursor); }
    try {
      return await this.request(this.historyPath(id) + '?limit=30&' + (cursor ? 'cursor=' + encodeURIComponent(cursor) : 'order=desc'));
    } catch (e) {
      if (e instanceof ApiError && e.code !== 413) { throw e; }
      // A large attachment page may exceed the 2 MB response bound. GET-only fallback also tolerates transient reads.
      const page = await this.smallMessages(id, cursor); this.compactHistory.add(id); return page;
    }
  }
  private async smallMessages(id: string, cursor: string): Promise<Object> {
    let data: Object[] = []; let next = cursor; let characters = 0;
    for (let page = 0; page < 8; page++) {
      const response = await this.request(this.historyPath(id) + '?limit=1&' + (next ? 'cursor=' + encodeURIComponent(next) : 'order=desc'));
      const chunk = rows(response); data = data.concat(chunk); characters += JSON.stringify(chunk).length;
      const after = string(object(object(response)['cursor'])['next']);
      if (!after || after === next || !chunk.length) { next = ''; break; }
      next = after; if (characters >= 2097152 && page >= 1) { break; }
    }
    const result: HistoryPage = { data: data, cursor: { next: next } }; return result;
  }
  parseMessages(response: Object): ChatMessage[] {
    return rows(response).slice().reverse().map((v: Object): ChatMessage => {
      const m = object(v); const role = string(m['type']); const parts: TextPart[] = []; const tools: ToolItem[] = [];
      list(m['content']).forEach((content: Object, ordinal: number) => {
        const p = object(content); const type = string(p['type']);
        if (type === 'text' || type === 'reasoning') { parts.push({ ordinal: ordinal, type: type, text: string(p['text']), ended: !!object(p['time'])['completed'] || !!object(m['time'])['completed'] || list(m['content']).slice(ordinal + 1).some((later: Object) => string(object(later)['type']) !== 'reasoning') }); }
        if (type === 'tool') {
          const state = object(p['state']);
          tools.push({ id: string(p['id']), name: string(p['name']), status: string(state['status']),
            input: typeof state['input'] === 'string' ? string(state['input']) : json(state['input']),
            output: list(state['content']).map((c: Object) => string(object(c)['text'])).join('\n') || json(state['error']) });
        }
      });
      const failure = object(m['error']);
      const text = role === 'user' ? string(m['text'], string(object(m['payload'])['text'])) :
        parts.filter((p: TextPart) => p.type === 'text').map((p: TextPart) => p.text).join('\n') || (role === 'assistant' ? (failure['message'] ? '模型调用失败：' + string(failure['message']).slice(0, 500) : '') : role === 'compaction' ? (m['status'] === 'completed' ? '上下文压缩已完成' : m['status'] === 'failed' ? '上下文压缩失败' : '正在压缩上下文') : role === 'model-switched' ? '会话模型已切换' : role === 'agent-switched' ? 'Agent 已切换' : role === 'location-switched' ? '工作目录已切换' : '会话状态已更新');
      return { id: string(m['id']), role: role, text: text,
        reasoning: parts.filter((p: TextPart) => p.type === 'reasoning').map((p: TextPart) => p.text).join('\n'),
        files: list(m['files']).slice(0, 4).map((v: Object, index: number): Attachment => {
          const file = object(v); const item = historyAttachment(string(m['id']) + '-file-' + index, string(file['name']), string(file['mime']), string(file['data']));
          const hash = string(file['sha256']);
          return /^[a-f0-9]{64}$/.test(hash) ? { id: item.id, name: item.name, mime: item.mime, data: '', size: Number(file['size']) || 0,
            fingerprint: hash, remoteHash: hash, remoteMessage: string(m['id']), remoteIndex: index } : item;
        }),
        parts: parts, tools: tools, state: m['finish'] === 'error' ? 'failed' : object(m['time'])['completed'] ? 'completed' : 'streaming' };
    }).filter((m: ChatMessage) => m.id.length > 0 && m.role !== 'idle');
  }
  parseTimeline(response: Object): TimelineEntry[] {
    return rows(response).slice().reverse().map((value: Object): TimelineEntry => {
      const entry = object(value);
      return { id: string(entry['id']), type: string(entry['type']),
        text: string(entry['text'], string(object(entry['payload'])['text'])),
        created: Number(object(entry['time'])['created']) || 0, outcome: string(entry['outcome']) };
    }).filter((entry: TimelineEntry) => !!entry.id);
  }
  async turnDiff(id: string, directory: string, from: string): Promise<DiffItem[]> {
    return rows(await this.request('/api/session/' + encodeURIComponent(id) + '/diff?' + this.scope(directory) +
      '&from=' + encodeURIComponent(from) + '&context=3')).map((value: Object): DiffItem => {
      const diff = object(value); return { path: string(diff['file']), patch: string(diff['patch']) };
    });
  }
  async interactions(sessionID: string, kind: string, directory: string = ''): Promise<Interaction[]> {
    const path = '/api/session/' + encodeURIComponent(sessionID) + (kind === 'form' ? '/form' : '/permission');
    return rows(await this.request(path + (directory ? '?' + this.scope(directory) : ''))).map((v: Object): Interaction => {
      const p = object(v);
      const fields = parseFields(p['fields']);
      return { id: string(p['id']), sessionID: sessionID, kind: kind,
        title: string(p['title'], string(p['action'], '操作审批')),
        detail: kind === 'form' ? string(p['description']) : list(p['resources']).map((r: Object) => string(r)).join('\n').slice(0, 12000),
        fields: fields, state: 'pending', approval: kind === 'form' ? undefined : parseApproval(p) };
    });
  }
  async files(directory: string, path: string): Promise<FileItem[]> {
    return rows(await this.request('/api/fs/list?' + this.scope(directory) + '&path=' + encodeURIComponent(path))).map((v: Object): FileItem => {
      const f = object(v); const filePath = string(f['path']);
      return { name: filePath.split('/').pop() || filePath, path: filePath, directory: string(f['type']) === 'directory' };
    });
  }
  async readFile(directory: string, path: string): Promise<string> {
    const encoded = path.split('/').map((segment: string) => encodeURIComponent(segment)).join('/');
    return string(await this.request('/api/fs/read/' + encoded + '?' + this.scope(directory), http.RequestMethod.GET, undefined, true));
  }
  async diff(directory: string): Promise<DiffItem[]> {
    return rows(await this.request('/api/vcs/diff?' + this.scope(directory) + '&mode=working&context=3')).map((v: Object): DiffItem => {
      const d = object(v);
      return { path: string(d['file'], string(d['path'])), patch: string(d['diff'], string(d['patch'])) };
    });
  }
  stream(onFrame: (frame: SseFrame) => void, onData: () => void, onEnd: (error: Error) => void): () => void {
    const task = http.createHttp(); const parser = new SseParser();
    const decoder = new util.TextDecoder('utf-8'); let closed = false;
    const end = (error: Error): void => { if (!closed) { closed = true; task.destroy(); onEnd(error); } };
    task.on('dataReceive', (buffer: ArrayBuffer) => {
      if (closed) { return; }
      try {
        onData();
        parser.feed(decoder.decodeToString(new Uint8Array(buffer), { stream: true })).forEach(onFrame);
      } catch (e) { end(e as Error); }
    });
    task.on('headersReceive', (headers: Object) => {
      const h = object(headers); const type = string(h['content-type'], string(h['Content-Type']));
      if (type && type.indexOf('text/event-stream') < 0) {
        // Wait for requestInStream's status code; dataEnd can arrive before its Promise resolves.
      }
    });
    task.on('dataEnd', () => { setTimeout(() => { end(new Error('事件流已断开，正在恢复')); }, 100); });
    const headers: Record<string, string> = { 'Accept': 'text/event-stream' };
    if (this.auth) { headers['Authorization'] = this.auth; }
    const options = this.options(); options.method = http.RequestMethod.GET; options.header = headers; options.readTimeout = 60000;
    task.requestInStream(this.config.url + '/api/event', options).then((code: number) => {
      if (code !== 200) { end(new ApiError(code, '事件流 HTTP ' + code) as Error); }
    }).catch((error: Error) => { end(networkError(error)); });
    return (): void => { closed = true; task.destroy(); };
  }
}
