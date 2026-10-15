import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { DEDICATED_CA, DEDICATED_SPKI } from './DedicatedTrust';
import { ChatMessage, TextPart, ToolItem, SseParser, SseFrame, ServerConfig, ProjectItem, SessionItem,
  TimelineEntry, ModelItem, Interaction, FormField, Choice, FileItem, DiffItem, FieldValue, FormCondition, FieldConstraints, ApprovalPreview, ApprovalFile, previewText } from '../domain/Core';

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
export class Protocol {
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
  async sessions(directory: string): Promise<SessionItem[]> {
    return rows(await this.request('/api/session?directory=' + encodeURIComponent(directory) + '&limit=50&order=desc'))
      .map((v: Object): SessionItem => {
        const s = object(v); const location = object(s['location']); const model = object(s['model']);
        return { id: string(s['id']), title: string(s['title'], '未命名会话'),
          directory: string(location['directory'], directory), status: 'idle',
          model: string(model['providerID']) + '/' + string(model['id']) };
      });
  }
  async models(directory: string): Promise<ModelItem[]> {
    return rows(await this.request('/api/model?' + this.scope(directory))).map((v: Object): ModelItem => {
      const m = object(v);
      return { id: string(m['providerID']) + '/' + string(m['modelID']), label: string(m['name'], string(m['modelID'])) };
    }).filter((m: ModelItem) => !m.id.endsWith('/'));
  }
  async messages(id: string, cursor: string = ''): Promise<Object> {
    return this.request('/api/session/' + encodeURIComponent(id) + '/message?limit=30&' +
      (cursor ? 'cursor=' + encodeURIComponent(cursor) : 'order=desc'));
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
        parts.filter((p: TextPart) => p.type === 'text').map((p: TextPart) => p.text).join('\n') || (role === 'assistant' ? (failure['message'] ? '模型调用失败：' + string(failure['message']).slice(0, 500) : '') : role === 'model-switched' ? '会话模型已切换' : role === 'agent-switched' ? 'Agent 已切换' : role === 'location-switched' ? '工作目录已切换' : '会话状态已更新');
      return { id: string(m['id']), role: role, text: text,
        reasoning: parts.filter((p: TextPart) => p.type === 'reasoning').map((p: TextPart) => p.text).join('\n'),
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
