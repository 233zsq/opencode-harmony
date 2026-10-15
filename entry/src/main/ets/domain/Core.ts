export interface SseFrame { event: string; data: string; id: string; retry: number; }

export class SseParser {
  private line: string = '';
  private data: string[] = [];
  private event: string = '';
  private id: string = '';
  private retry: number = 0;
  private bytes: number = 0;
  private skipLF: boolean = false;
  constructor(private limit: number = 1048576) {}
  feed(chunk: string): SseFrame[] {
    const frames: SseFrame[] = [];
    for (let i = 0; i < chunk.length; i++) {
      const ch = chunk.charAt(i);
      if (this.skipLF) { this.skipLF = false; if (ch === '\n') { continue; } }
      if (ch === '\r' || ch === '\n') {
        this.consume(frames); this.skipLF = ch === '\r';
      } else {
        this.line += ch; this.bytes++;
        if (this.bytes > this.limit) { throw new Error('事件过大，请重新连接'); }
      }
    }
    return frames;
  }
  private consume(frames: SseFrame[]): void {
    const line = this.line; this.line = '';
    if (line.length === 0) {
      if (this.data.length > 0) {
        frames.push({ event: this.event || 'message', data: this.data.join('\n'), id: this.id, retry: this.retry });
      }
      this.data = []; this.event = ''; this.retry = 0; this.bytes = 0; return;
    }
    if (line.charAt(0) === ':') { return; }
    const split = line.indexOf(':');
    const field = split < 0 ? line : line.slice(0, split);
    let value = split < 0 ? '' : line.slice(split + 1);
    if (value.charAt(0) === ' ') { value = value.slice(1); }
    if (field === 'data') { this.data.push(value); }
    if (field === 'event') { this.event = value; }
    if (field === 'id' && value.indexOf('\u0000') < 0) { this.id = value; }
    if (field === 'retry' && /^\d+$/.test(value)) { this.retry = Math.min(Number(value), 60000); }
  }
}

export interface ToolItem { id: string; name: string; status: string; input: string; output: string; }
export interface TextPart { ordinal: number; type: string; text: string; ended?: boolean; }
export interface ChatMessage {
  id: string; role: string; text: string; reasoning: string; parts: TextPart[]; tools: ToolItem[]; state: string;
}
export interface DiffLine { id: string; kind: string; text: string; oldLine: string; newLine: string; }
export interface MarkdownBlock { id: string; kind: string; text: string; language: string;  rows?: string[][]; }
export interface Choice { value: string; label: string; description: string; }
export interface FormField {
  key: string; label: string; type: string; required: boolean; options: Choice[];
  values: string[]; text: string; constraints?: FieldConstraints;
}
export interface ApprovalFile { path: string; patch: string; status: string; additions: number; deletions: number; }
export interface ApprovalPreview {
  command: string; directory: string; pattern: string; reason: string; source: string;
  files: ApprovalFile[]; omittedFiles: number; incomplete: boolean; expectsDiff: boolean;
}
export interface Interaction {
  id: string; sessionID: string; kind: string; title: string; detail: string;
  fields: FormField[]; state: string; approval?: ApprovalPreview;
}
export interface ServerConfig { id: string; name: string; url: string; username: string; allowHttp: boolean; useDedicatedTrust?: boolean; preferredModel?: string; }
export interface ProjectItem { id: string; name: string; directory: string; }
export interface SessionItem { id: string; title: string; directory: string; status: string; model: string; }
export interface ModelItem { id: string; label: string; }
export interface FileItem { name: string; path: string; directory: boolean; }
export interface DiffItem { path: string; patch: string; }

export function mergeMessages(previous: ChatMessage[], incoming: ChatMessage[], older: boolean = false): ChatMessage[] {
  const map = new Map<string, ChatMessage>();
  previous.forEach((m: ChatMessage) => { map.set(m.id, m); });
  incoming.forEach((m: ChatMessage) => {
    const old = map.get(m.id);
    if (!old || JSON.stringify(old) !== JSON.stringify(m)) { map.set(m.id, m); }
  });
  const order: string[] = [];
  const first = older ? incoming : previous;
  const second = older ? previous : incoming;
  first.concat(second).forEach((m: ChatMessage) => { if (order.indexOf(m.id) < 0) { order.push(m.id); } });
  return order.map((id: string) => map.get(id) as ChatMessage);
}

export function applyTextDelta(messages: ChatMessage[], id: string, ordinal: number, type: string,
  text: string, ended: boolean): ChatMessage[] {
  const next = messages.slice();
  let index = next.findIndex((m: ChatMessage) => m.id === id);
  if (index < 0) {
    next.push({ id: id, role: 'assistant', text: '', reasoning: '', parts: [], tools: [], state: 'streaming' });
    index = next.length - 1;
  }
  const old = next[index];
  const parts = old.parts.map((p: TextPart) => ({ ordinal: p.ordinal, type: p.type, text: p.text, ended: p.ended }));
  const position = parts.findIndex((p: TextPart) => p.ordinal === ordinal && p.type === type);
  if (position < 0) { parts.push({ ordinal: ordinal, type: type, text: text, ended: ended }); }
  else { parts[position].text = ended ? text : parts[position].text + text; parts[position].ended = ended; }
  if (type === 'text') { parts.forEach((p: TextPart) => { if (p.type === 'reasoning' && p.ordinal < ordinal) { p.ended = true; } }); }
  parts.sort((a: TextPart, b: TextPart) => a.ordinal - b.ordinal);
  next[index] = { id: old.id, role: old.role, text: parts.filter((p: TextPart) => p.type === 'text').map((p: TextPart) => p.text).join('\n'),
    reasoning: parts.filter((p: TextPart) => p.type === 'reasoning').map((p: TextPart) => p.text).join('\n'),
    parts: parts, tools: old.tools, state: old.state };
  return next;
}

export function parseDiff(patch: string, limit: number = 1500): DiffLine[] {
  let oldLine = 0; let newLine = 0;
  return patch.split('\n', limit).map((text: string, i: number) => {
    let kind = 'context'; let left = ''; let right = '';
    const match = /^@@ -(\d+)(?:,\d+)? \+(\d+)(?:,\d+)? @@/.exec(text);
    if (match) { oldLine = Number(match[1]); newLine = Number(match[2]); kind = 'header'; }
    else if (/^(diff |index |--- |\+\+\+ |\\)/.test(text)) { kind = 'header'; }
    else if (text.charAt(0) === '+') { kind = 'add'; right = String(newLine++); }
    else if (text.charAt(0) === '-') { kind = 'remove'; left = String(oldLine++); }
    else if (text.charAt(0) === ' ') { left = String(oldLine++); right = String(newLine++); }
    else { kind = 'header'; }
    return { id: String(i), kind: kind, text: text, oldLine: left, newLine: right };
  });
}

export function parseMarkdown(text: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = []; let code = false; let language = ''; let lines: string[] = []; let paragraph: string[] = [];
  const push = (kind: string, value: string, lang: string = ''): void => { blocks.push({ id: String(blocks.length), kind: kind, text: value, language: lang }); };
  const flush = (): void => { if (paragraph.length) { push('text', paragraph.join('\n')); paragraph = []; } };
  const cells = (line: string): string[] => line.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').slice(0, 12).map((v: string) => v.trim());
  const input = text.slice(0, 200000).split('\n');
  for (let i = 0; i < input.length; i++) {
    const line = input[i];
    if (/^\s*\x60{3}/.test(line)) {
      flush(); if (code) { push('code', lines.join('\n'), language); lines = []; } else { language = line.replace(/^\s*\x60{3}/, '').trim(); }
      code = !code; continue;
    }
    if (code) { lines.push(line); continue; }
    if (line.includes('|') && i + 1 < input.length && /^\s*\|?[\s:|-]+\|?\s*$/.test(input[i + 1]) && input[i + 1].includes('-')) {
      flush(); const table: string[][] = [cells(line)]; i++;
      while (i + 1 < input.length && input[i + 1].includes('|') && table.length < 101) { table.push(cells(input[++i])); }
      blocks.push({ id: String(blocks.length), kind: 'table', text: '', language: '', rows: table }); continue;
    }
    if (/^#{1,6}\s/.test(line)) { flush(); push('heading', line.replace(/^#{1,6}\s+/, '')); }
    else if (/^>\s?/.test(line)) { flush(); push('quote', line.replace(/^>\s?/, '')); }
    else if (/^\s*[-*+]\s+/.test(line)) { flush(); push('list', '• ' + line.replace(/^\s*[-*+]\s+/, '')); }
    else if (/^\s*\d+[.)]\s+/.test(line)) { flush(); push('list', line.trim()); }
    else if (/^---+$/.test(line)) { flush(); push('rule', ''); }
    else if (!line.trim()) { flush(); } else { paragraph.push(line); }
  }
  flush(); if (code) { push('code', lines.join('\n'), language); } return blocks;
}
export interface TextPreview { text: string; truncated: boolean; }
export function previewText(input: string, maxChars: number = 100000, maxLines: number = 1500): TextPreview {
  const bounded = input.slice(0, maxChars); const lines = bounded.split('\n', maxLines + 1);
  const truncated = input.length > maxChars || lines.length > maxLines;
  return { text: lines.slice(0, maxLines).join('\n'), truncated: truncated };
}

export function normalizeUrl(input: string, allowHttp: boolean): string {
  const value = input.trim().replace(/\/+$/, '');
  if (!/^https?:\/\/[^/?#\s]+(?:\/[^?#\s]*)?$/.test(value)) { throw new Error('请输入完整的 http(s) 服务器地址，不包含查询参数'); }
  const authority = value.replace(/^https?:\/\//, '').split('/')[0];
  if (authority.indexOf('@') >= 0) { throw new Error('账号密码请填写在认证栏，不要放进地址'); }
  if (value.startsWith('http://') && !allowHttp) { throw new Error('HTTP 未加密。可信本地测试需明确开启 HTTP 选项'); }
  return value;
}

export type FieldValue = string | number | boolean | string[];
export interface FormCondition { key: string; op: string; value: FieldValue; }
export interface FieldConstraints {
  hidden?: boolean; custom?: boolean; when?: FormCondition[]; initial?: FieldValue;
  minimum?: number; maximum?: number; minLength?: number; maxLength?: number;
  minItems?: number; maxItems?: number; pattern?: string; format?: string; url?: string;
}

export function updateFieldValue(field: FormField, value: string, multiple: boolean): FormField {
  return { ...field, values: multiple ? (field.values.includes(value) ? field.values.filter(v => v !== value) :
    field.values.concat([value])) : [value], text: value };
}
export function formActive(field: FormField, answers: Record<string, FieldValue>): boolean {
  return (field.constraints?.when || []).every(condition => {
    const value = answers[condition.key];
    if (value === undefined) return false;
    const equal = Array.isArray(value) ? value.includes(String(condition.value)) : value === condition.value;
    return condition.op === 'eq' ? equal : !equal;
  });
}
export function buildFormAnswer(fields: FormField[], strict: boolean = true): Record<string, FieldValue> {
  const answers: Record<string, FieldValue> = {};
  for (const field of fields) {
    if (!formActive(field, answers)) continue;
    if (field.type === 'external') {
      if (strict && field.text !== 'true') { throw new Error('请完成：' + field.label); }
      continue;
    }
    const c = field.constraints || {};
    let value: FieldValue | undefined;
    if (field.type === 'multiselect') value = field.values.length ? field.values : c.initial || [];
    else if (field.type === 'boolean') value = field.text === '' ? c.initial : field.text === 'true';
    else if (field.type === 'number' || field.type === 'integer') value = field.text === '' ? c.initial : Number(field.text);
    else if (field.type === 'external') value = field.text === 'true' ? true : undefined;
    else if (field.type === 'string') value = field.text || c.initial;
    else if (strict) throw new Error('不支持的表单字段：' + field.type);
    const missing = value === undefined || value === '' || (Array.isArray(value) && value.length === 0);
    if (strict && ((field.required && missing) || (field.type === 'external' && value !== true))) {
      throw new Error('请完成：' + field.label);
    }
    if (missing && !(field.type === 'multiselect' && !field.required)) continue;
    if (strict && (field.type === 'number' || field.type === 'integer')) {
      if (typeof value !== 'number' || !Number.isFinite(value) ||
        (field.type === 'integer' && !Number.isInteger(value))) throw new Error('请输入有效数字：' + field.label);
      if ((c.minimum !== undefined && value < c.minimum) || (c.maximum !== undefined && value > c.maximum)) {
        throw new Error('数字超出范围：' + field.label);
      }
    }
    if (strict && field.type === 'string' && typeof value === 'string') {
      if ((c.minLength !== undefined && value.length < c.minLength) ||
        (c.maxLength !== undefined && value.length > c.maxLength)) throw new Error('文本长度不符合要求：' + field.label);
      if (c.pattern && !new RegExp(c.pattern).test(value)) throw new Error('文本格式不符合要求：' + field.label);
      if (c.format === 'email' && !/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(value)) throw new Error('请输入有效邮箱：' + field.label);
      if (c.format === 'uri' && !/^[a-z][a-z0-9+.-]*:/i.test(value)) throw new Error('请输入完整地址：' + field.label);
    }
    if (strict && field.type === 'multiselect' && Array.isArray(value)) {
      if ((c.minItems !== undefined && value.length < c.minItems) ||
        (c.maxItems !== undefined && value.length > c.maxItems)) throw new Error('选择数量不符合要求：' + field.label);
    }
    if (strict && field.options.length && !c.custom && value !== undefined) {
      const values = Array.isArray(value) ? value : [String(value)];
      if (values.some(v => !field.options.some(option => option.value === v))) throw new Error('请选择有效选项：' + field.label);
    }
    if (value !== undefined) answers[field.key] = value;
  }
  return answers;
}
export function visibleFormFields(fields: FormField[]): FormField[] {
  const answers = buildFormAnswer(fields, false);
  return fields.filter(field => !field.constraints?.hidden && formActive(field, answers));
}
export interface InlinePart { id: string; text: string; kind: string; url?: string; }
export function inlineMarkdown(text: string): InlinePart[] {
  const parts: InlinePart[] = [];
  const pattern = /(\*\*([^*]+)\*\*|\x60([^\x60]+)\x60|\[([^\]]+)\]\((https?:\/\/[^)]+)\))/g;
  let start = 0; let match: RegExpExecArray | null;
  while ((match = pattern.exec(text)) !== null) {
    if (match.index > start) parts.push({ id: String(parts.length), text: text.slice(start, match.index), kind: 'text' });
    parts.push({ id: String(parts.length), text: match[2] || match[3] || match[4], kind: match[2] ? 'bold' : match[3] ? 'code' : 'link', url: match[5] || '' });
    start = pattern.lastIndex;
  }
  if (start < text.length) parts.push({ id: String(parts.length), text: text.slice(start), kind: 'text' });
  return parts;
}

export function reasoningInProgress(message: ChatMessage): boolean {
  return message.state === 'streaming' && message.parts.some((p: TextPart) => p.type === 'reasoning' && p.ended === false);
}
export function toolStatus(status: string): string {
  return status === 'completed' ? '已完成' : status === 'error' || status === 'failed' ? '失败' : status === 'running' ? '运行中' : '等待中';
}
export function toolSummary(tool: ToolItem): string {
  try {
    const input = JSON.parse(tool.input) as Record<string, string>;
    return [input['description'], input['filePath'], input['file_path'], input['path'], input['pattern'], input['command']].find((value: string) => typeof value === 'string' && value.length > 0)?.replace(/\s+/g, ' ').slice(0, 100) || '';
  } catch (_) { return tool.input.replace(/\s+/g, ' ').slice(0, 100); }
}

export function messageKey(message: ChatMessage): string {
  const text = message.text + '\u0000' + message.reasoning + '\u0000' + JSON.stringify(message.tools) + message.parts.map((p: TextPart) => String(p.ended)).join(',');
  let hash = 2166136261;
  for (let i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619);
  return message.id + ':' + (hash >>> 0) + ':' + message.state;
}
export function mergeFormDraft(incoming: FormField[], previous: FormField[]): FormField[] {
  return incoming.map(field => {
    const old = previous.find(item => item.key === field.key && item.type === field.type);
    return old ? { ...field, values: old.values, text: old.text } : field;
  });
}

export function interactionSnapshot(item: Interaction): string {
  return JSON.stringify([item.id, item.sessionID, item.kind, item.title, item.detail, item.approval || null]);
}
export function interactionKey(item: Interaction): string {
  const text = interactionSnapshot(item);
  let hash = 2166136261; for (let i = 0; i < text.length; i++) hash = Math.imul(hash ^ text.charCodeAt(i), 16777619);
  return item.id + ':' + (hash >>> 0);
}
