import { Attachment } from './Attachments';
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
  id: string; role: string; text: string; reasoning: string; parts: TextPart[]; tools: ToolItem[]; state: string; files?: Attachment[];
}
export interface TranscriptSnapshot { messages: ChatMessage[]; cursor: string; savedAt: number; }
export interface TranscriptCachePort {
  load(config: ServerConfig, directory: string, id: string): Promise<TranscriptSnapshot | undefined>;
  save(config: ServerConfig, directory: string, id: string, snapshot: TranscriptSnapshot): Promise<void>;
  file(config: ServerConfig, hash: string): Promise<string>;
  saveFile(config: ServerConfig, hash: string, data: string): Promise<void>;
  removeServer(config: ServerConfig): Promise<void>;
  size(): Promise<number>;
  clear(): Promise<void>;
}
export class EmptyTranscriptCache implements TranscriptCachePort {
  async load(config: ServerConfig, directory: string, id: string): Promise<TranscriptSnapshot | undefined> { return undefined; }
  async save(config: ServerConfig, directory: string, id: string, snapshot: TranscriptSnapshot): Promise<void> {}
  async file(config: ServerConfig, hash: string): Promise<string> { return ''; }
  async saveFile(config: ServerConfig, hash: string, data: string): Promise<void> {}
  async removeServer(config: ServerConfig): Promise<void> {}
  async size(): Promise<number> { return 0; }
  async clear(): Promise<void> {}
}
export interface DiffLine { id: string; kind: string; text: string; oldLine: string; newLine: string; }
export interface MarkdownBlock { id: string; kind: string; text: string; language: string;  rows?: string[][]; align?: string[]; depth?: number; marker?: string; checked?: boolean; level?: number; }
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
export interface SessionItem { variant?: string; parentID?: string; forkType?: string; forkBefore?: string; agent?: string; id: string; title: string; directory: string; status: string; model: string; updated?: number; archived?: boolean; }
export interface ModelItem { variants?: string[]; available?: boolean; id: string; label: string; input?: string[]; contextLimit?: number; }
export interface FileItem { name: string; path: string; directory: boolean; }
export interface DiffItem { path: string; patch: string; }
export interface TimelineEntry { id: string; type: string; text: string; created: number; outcome: string; }
export interface TurnItem { id: string; title: string; created: number; prompts: number; state: string; partial: boolean; }
// Keep server idle boundaries: prompts sent while a task runs belong to that task.
export function groupTurns(entries: TimelineEntry[], hasEarlier: boolean): TurnItem[] {
  const turns: TurnItem[] = []; let current: TurnItem | undefined = undefined; let boundary = !hasEarlier;
  entries.forEach((entry: TimelineEntry) => {
    if (entry.type === 'idle' || entry.type === 'location-switched') {
      if (current) { current.state = entry.outcome === 'failed' ? 'failed' : 'completed'; }
      current = undefined; boundary = true;
    } else if (entry.type === 'user') {
      if (!current) {
        current = { id: entry.id, title: entry.text.slice(0, 100) || '任务消息', created: entry.created,
          prompts: 1, state: 'running', partial: !boundary };
        turns.push(current);
      } else { current.prompts++; }
    }
  });
  return turns.reverse();
}
export function diffKey(diff: DiffItem): string {
  let hash = 2166136261;
  for (let i = 0; i < diff.patch.length; i++) { hash = Math.imul(hash ^ diff.patch.charCodeAt(i), 16777619); }
  return diff.path + ':' + diff.patch.length + ':' + (hash >>> 0);
}


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
  const seen = new Set<string>();
  first.concat(second).forEach((m: ChatMessage) => { if (!seen.has(m.id)) { seen.add(m.id); order.push(m.id); } });
  const merged = order.map((id: string) => map.get(id) as ChatMessage);
  return merged.length === previous.length && merged.every((m: ChatMessage, index: number) => m === previous[index]) ? previous : merged;
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
    parts: parts, tools: old.tools, state: old.state, files: old.files };
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

function markdownCells(value: string): string[] {
  let line = value.trim(); if (line.startsWith('|')) { line = line.slice(1); }
  if (line.endsWith('|') && line.charCodeAt(line.length - 2) !== 92) { line = line.slice(0, -1); }
  const cells: string[] = []; let cell = ''; let code = '';
  for (let i = 0; i < line.length; i++) {
    const ch = line.charAt(i);
    if (ch.charCodeAt(0) === 92 && line.charAt(i + 1) === '|') { cell += '|'; i++; continue; }
    if (ch === '\x60') {
      let ticks = ch; while (line.charAt(i + 1) === ch) { ticks += ch; i++; }
      if (!code) { code = ticks; } else if (code === ticks) { code = ''; } cell += ticks; continue;
    }
    if (ch === '|' && !code) { if (cells.length < 11) { cells.push(cell.trim()); cell = ''; } }
    else { cell += ch; }
  }
  cells.push(cell.trim()); return cells;
}
export function parseMarkdown(text: string): MarkdownBlock[] {
  const blocks: MarkdownBlock[] = []; let fence = ''; let language = ''; let lines: string[] = []; let paragraph: string[] = []; let truncated = text.length > 200000;
  const push = (kind: string, value: string, lang: string = ''): MarkdownBlock => {
    const block: MarkdownBlock = { id: String(blocks.length), kind: kind, text: value, language: lang };
    if (blocks.length >= 400 && kind !== 'notice') { truncated = true; return block; }
    blocks.push(block); return block;
  };
  const flush = (): void => { if (paragraph.length) { push('text', paragraph.join('\n')); paragraph = []; } };
  const input = text.slice(0, 200000).replace(/\r\n?/g, '\n').split('\n');
  for (let i = 0; i < input.length; i++) {
    if (blocks.length >= 400) { truncated = true; break; }
    const line = input[i];
    if (fence) {
      const close = /^ {0,3}([\x60~]{3,})\s*$/.exec(line);
      if (close && close[1].charAt(0) === fence.charAt(0) && close[1].length >= fence.length && close[1].split('').every((ch: string) => ch === fence.charAt(0))) {
        push('code', lines.join('\n'), language); lines = []; fence = '';
      } else { lines.push(line); } continue;
    }
    const open = /^ {0,3}(\x60{3,}|~{3,})(.*)$/.exec(line);
    if (open) { flush(); fence = open[1]; language = open[2].trim().split(/\s/)[0].slice(0, 32); continue; }
    if (line.includes('|') && i + 1 < input.length) {
      const separators = markdownCells(input[i + 1]);
      if (separators.every((cell: string) => /^:?-{3,}:?$/.test(cell))) {
        flush(); const table: string[][] = [markdownCells(line)]; i++;
        while (i + 1 < input.length && input[i + 1].trim() && input[i + 1].includes('|')) {
          i++; if (table.length < 101) { table.push(markdownCells(input[i])); } else { truncated = true; }
        }
        const block = push('table', ''); block.rows = table;
        block.align = separators.map((cell: string) => cell.startsWith(':') && cell.endsWith(':') ? 'center' : cell.endsWith(':') ? 'right' : 'left'); continue;
      }
    }
    if (paragraph.length && /^ {0,3}(=+|-+)\s*$/.test(line)) { const heading = push('heading', paragraph.join('\n')); heading.level = line.trim().startsWith('=') ? 1 : 2; paragraph = []; continue; }
    const heading = /^ {0,3}(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
    const item = /^(\s*)([-*+]|\d{1,9}[.)])\s+(.*)$/.exec(line);
    if (heading) { flush(); const block = push('heading', heading[2]); block.level = heading[1].length; }
    else if (/^ {0,3}([-*_])(?:\s*\1){2,}\s*$/.test(line)) { flush(); push('rule', ''); }
    else if (/^ {0,3}>\s?/.test(line)) { flush(); push('quote', line.replace(/^ {0,3}>\s?/, '')); }
    else if (item) {
      flush(); const checkbox = /^\[([ xX])\]\s+(.*)$/.exec(item[3]);
      const marker = checkbox ? (checkbox[1] === ' ' ? '☐' : '☑') : /\d/.test(item[2]) ? item[2] : '•';
      const block = push('list', marker + ' ' + (checkbox ? checkbox[2] : item[3])); block.marker = marker;
      block.depth = Math.min(8, Math.floor(item[1].replace(/\t/g, '  ').length / 2));
      if (checkbox) { block.checked = checkbox[1] !== ' '; }
    } else if (!line.trim()) { flush(); } else { paragraph.push(line); }
  }
  if (blocks.length < 400) { flush(); if (fence) { push('code', lines.join('\n'), language); } }
  if (truncated) { push('notice', '内容较长，已限制预览；可长按复制完整回复。'); } return blocks;
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
export interface InlinePart { id: string; text: string; kind: string; url?: string; strong?: boolean; emphasis?: boolean; strike?: boolean; }
interface InlineBudget { remaining: number; }
function parseInline(text: string, depth: number, budget: InlineBudget): InlinePart[] {
  if (depth >= 8 || budget.remaining <= 0) { return [{ id: '0', text: text, kind: 'text' }]; }
  const parts: InlinePart[] = []; let plain = '';
  const add = (part: InlinePart): void => { part.id = String(parts.length); parts.push(part); budget.remaining--; };
  const flush = (): void => { if (plain) { add({ id: '', text: plain, kind: 'text' }); plain = ''; } };
  for (let i = 0; i < text.length;) {
    if (budget.remaining <= 0) { plain += text.slice(i); break; }
    const ch = text.charAt(i);
    if (ch.charCodeAt(0) === 92 && (String.fromCharCode(92, 96) + '*{}[]()#+.!_>~|-').indexOf(text.charAt(i + 1)) >= 0 && i + 1 < text.length) { plain += text.charAt(i + 1); i += 2; continue; }
    if (ch === '\x60') {
      let ticks = ch; while (text.charAt(i + ticks.length) === ch) { ticks += ch; }
      let end = text.indexOf(ticks, i + ticks.length);
      while (end >= 0 && (text.charAt(end - 1) === ch || text.charAt(end + ticks.length) === ch)) { end = text.indexOf(ticks, end + ticks.length); }
      if (end >= 0) { flush(); add({ id: '', text: text.slice(i + ticks.length, end).replace(/\n/g, ' '), kind: 'code' }); i = end + ticks.length; continue; }
      plain += ticks; i += ticks.length; continue;
    }
    const image = ch === '!' && text.charAt(i + 1) === '[';
    if (ch === '[' || image) {
      const labelStart = i + (image ? 2 : 1), labelEnd = text.indexOf('](', labelStart);
      if (labelEnd >= 0 && labelEnd - labelStart <= 2000) {
        const end = text.indexOf(')', labelEnd + 2), url = end < 0 ? '' : text.slice(labelEnd + 2, end);
        if (/^https?:\/\/[^\s<>]+$/.test(url) && url.length <= 2048) {
          flush(); add({ id: '', text: (image ? '图片：' : '') + text.slice(labelStart, labelEnd), kind: 'link', url: url }); i = end + 1; continue;
        }
      }
    }
    let matched = false;
    for (const token of ['**', '__', '~~', '*', '_']) {
      if (!text.startsWith(token, i) || (token.includes('_') && /[\w]/.test(text.charAt(i - 1)))) { continue; }
      let end = text.indexOf(token, i + token.length);
      while (end >= 0 && text.charCodeAt(end - 1) === 92) { end = text.indexOf(token, end + token.length); }
      if (end <= i + token.length || /\s/.test(text.charAt(i + token.length)) || /\s/.test(text.charAt(end - 1))) { continue; }
      flush(); const children = parseInline(text.slice(i + token.length, end), depth + 1, budget);
      children.forEach((part: InlinePart) => {
        if (token.length === 2 && token !== '~~') { part.strong = true; if (part.kind === 'text') { part.kind = 'bold'; } }
        else if (token === '~~') { part.strike = true; } else { part.emphasis = true; }
        part.id = String(parts.length); parts.push(part);
      });
      i = end + token.length; matched = true; break;
    }
    if (!matched) { plain += ch; i++; }
  }
  flush(); return parts;
}
export function inlineMarkdown(text: string): InlinePart[] { return parseInline(text, 0, { remaining: 512 }); }

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
  const text = message.text + '\u0000' + message.reasoning + '\u0000' + JSON.stringify(message.tools) + JSON.stringify((message.files || []).map((f: Attachment) => [f.id, f.name, f.mime, f.data.length, f.fingerprint || '', f.error || ''])) + message.parts.map((p: TextPart) => String(p.ended)).join(',');
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

export interface SessionPage { sessions: SessionItem[]; cursor: string; }
export interface SessionPreference { id: string; pinned: boolean; archived: boolean; title?: string; directory?: string; }
export interface PendingItem {
  id: string; sessionID: string; directory: string; kind: string; title: string; sessionTitle: string; stale: boolean;
}
export interface PendingPrompt { id: string; sessionID: string; text: string; files?: Attachment[]; }
export interface QuestionDraft { id: string; fields: FormField[]; }
export interface ConversationDraft { text: string; pending?: PendingPrompt; forms?: QuestionDraft[]; files?: Attachment[]; }

// Unsent text stays in memory, isolated by server, location and session. No chat history is persisted.
export class ConversationMemory {
  private drafts: Map<string, ConversationDraft> = new Map<string, ConversationDraft>();
  private key(server: string, directory: string, session: string): string { return JSON.stringify([server, directory, session]); }
  save(server: string, directory: string, session: string, text: string, pending?: PendingPrompt, forms: QuestionDraft[] = [], files: Attachment[] = []): void {
    const key = this.key(server, directory, session);
    if (!text && !pending && !forms.length && !files.length) { this.drafts.delete(key); return; }
    if (!this.drafts.has(key) && this.drafts.size >= 100) { throw new Error('已暂存 100 个会话草稿，请先发送或清空部分草稿后再切换。'); }
    let bytes = files.reduce((sum: number, f: Attachment) => sum + f.size, 0);
    this.drafts.forEach((draft: ConversationDraft, oldKey: string) => { if (oldKey !== key) { bytes += (draft.files || []).reduce((sum: number, f: Attachment) => sum + f.size, 0); } });
    if (bytes > 16777216) { throw new Error('附件草稿合计已达 16 MB，请先发送或移除部分附件'); }
    this.drafts.set(key, { text: text, pending: pending, forms: forms, files: files.slice() });
  }
  read(server: string, directory: string, session: string): ConversationDraft {
    return this.drafts.get(this.key(server, directory, session)) || { text: '' };
  }
  clearServer(server: string): void {
    const prefix = JSON.stringify([server]).slice(0, -1) + ',';
    Array.from(this.drafts.keys()).forEach((key: string) => { if (key.startsWith(prefix)) { this.drafts.delete(key); } });
  }
}
export function pendingKey(item: PendingItem): string { return JSON.stringify([item.directory, item.sessionID, item.kind, item.id]); }
export function sessionStatus(id: string, running: string[], pending: PendingItem[]): string {
  const items = pending.filter((item: PendingItem) => item.sessionID === id);
  if (items.some((item: PendingItem) => item.stale)) { return '待办待确认'; }
  if (items.some((item: PendingItem) => item.kind === 'permission')) { return '等待审批'; }
  if (items.length) { return '等待回答'; }
  return running.indexOf(id) >= 0 ? '运行中' : '';
}
export function filterSessions(sessions: SessionItem[], preferences: SessionPreference[], search: string, archived: boolean): SessionItem[] {
  const needle = search.trim().toLowerCase();
  return sessions.filter((session: SessionItem) => {
    const flag = preferences.find((p: SessionPreference) => p.id === session.id);
    return (flag?.archived === true) === archived && (!needle || session.title.toLowerCase().indexOf(needle) >= 0);
  }).sort((a: SessionItem, b: SessionItem) => {
    const pinnedA = preferences.some((p: SessionPreference) => p.id === a.id && p.pinned);
    const pinnedB = preferences.some((p: SessionPreference) => p.id === b.id && p.pinned);
    return Number(pinnedB) - Number(pinnedA);
  });
}

// Keep old attachment metadata while bounding decoded history payloads across all pages.
export function boundMessageAttachments(messages: ChatMessage[], limit: number = 8388608): ChatMessage[] {
  let bytes = 0; let changed = false; const result = messages.slice();
  for (let i = result.length - 1; i >= 0; i--) {
    const message = result[i]; let removed = false;
    const files = (message.files || []).map((file: Attachment): Attachment => {
      if (!file.data) { return file; }
      const size = Math.ceil(file.data.length * 3 / 4);
      if (bytes + size <= limit) { bytes += size; return file; }
      removed = true; return { id: file.id, name: file.name, mime: file.mime, size: file.size, data: '', fingerprint: file.fingerprint, remoteHash: file.remoteHash, remoteMessage: file.remoteMessage, remoteIndex: file.remoteIndex, error: '预览已释放，点按重新读取' };
    });
    if (removed) { changed = true; result[i] = { id: message.id, role: message.role, text: message.text, reasoning: message.reasoning, parts: message.parts, tools: message.tools, state: message.state, files: files }; }
  }
  return changed ? result : messages;
}
