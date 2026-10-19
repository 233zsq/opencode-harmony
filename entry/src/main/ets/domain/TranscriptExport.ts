import { ChatMessage } from './Core';

export interface ExportPage { messages: ChatMessage[]; ids: string[]; cursor: string; }
export interface ExportReader { exportBoundary(id: string): Promise<string>; exportPage(id: string, cursor: string): Promise<ExportPage>; }
export interface ExportOptions { id: string; title: string; format: string; tools: boolean; }
export interface ExportDocument { name: string; text: string; count: number; }
export class ExportCancelled extends Error { constructor() { super('已取消导出'); } }
export function utf8Length(text: string): number {
  let bytes = 0;
  for (let i = 0; i < text.length; i++) { const c = text.charCodeAt(i);
    if (c < 128) { bytes++; } else if (c < 2048) { bytes += 2; }
    else if (c >= 0xD800 && c <= 0xDBFF && i + 1 < text.length && text.charCodeAt(i + 1) >= 0xDC00 && text.charCodeAt(i + 1) <= 0xDFFF) { bytes += 4; i++; }
    else { bytes += 3; }
  } return bytes;
}
export function exportFilename(title: string, format: string): string {
  const safe = title.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').replace(/[. ]+$/g, '').slice(0, 80).replace(/[. ]+$/g, '') || '会话导出';
  return safe + (format === 'text' ? '.txt' : '.md');
}
function fence(text: string): string {
  let longest = 2; const matches = text.match(/`+/g) || []; matches.forEach((value: string) => { longest = Math.max(longest, value.length); });
  const mark = '`'.repeat(longest + 1); return mark + '\n' + text + '\n' + mark;
}
function messageText(message: ChatMessage, options: ExportOptions): string {
  if (['user', 'assistant', 'agent-switched', 'model-switched', 'location-switched'].indexOf(message.role) < 0) { return ''; }
  if (!message.text && !(message.files || []).length && !(options.tools && message.tools.length)) { return ''; }
  const label = message.role === 'user' ? '用户' : message.role === 'assistant' ? '助手' : '会话状态';
  let text = (options.format === 'text' ? '【' + label + '】' : '## ' + label) + '\n\n' + message.text;
  (message.files || []).forEach((file) => { text += '\n\n附件：' + file.name + '（' + file.mime + '，' + file.size + ' B，仅文件信息）'; });
  if (options.tools) { message.tools.forEach((tool) => {
    text += '\n\n' + (options.format === 'text' ? '工具：' : '### 工具：') + tool.name + ' · ' + tool.status + '\n\n参数：\n' + (options.format === 'text' ? tool.input : fence(tool.input)) + '\n\n输出：\n' + (options.format === 'text' ? tool.output : fence(tool.output));
  }); }
  return text + '\n\n';
}
export class TranscriptExporter {
  private cancelled: boolean = false;
  cancel(): void { this.cancelled = true; }
  private check(): void { if (this.cancelled) { throw new ExportCancelled(); } }
  async prepare(reader: ExportReader, options: ExportOptions, progress: (count: number) => void): Promise<ExportDocument> {
    this.check(); const boundary = await reader.exportBoundary(options.id); this.check();
    const title = options.title.replace(/[\r\n]/g, ' ').slice(0, 200) || '会话导出';
    const chunks = [(options.format === 'text' ? title : '# ' + title) + '\n\n会话：' + options.id + '\n导出范围：开始读取时的用户与助手对话；附件仅列文件信息。\n\n'];
    let bytes = utf8Length(chunks[0]); let count = 0; let cursor = ''; let complete = !boundary; const ids = new Set<string>(); const cursors = new Set<string>();
    for (let page = 0; !complete; page++) {
      this.check(); if (page >= 2000) { throw new Error('会话超过 2000 页，导出未完成，请缩小会话后重试'); }
      if (cursors.has(cursor)) { throw new Error('历史分页重复，导出未完成，请重试'); } cursors.add(cursor);
      const result = await reader.exportPage(options.id, cursor); this.check();
      const boundaryIndex = result.ids.indexOf(boundary); const accepted = new Set<string>(boundaryIndex < 0 ? result.ids : result.ids.slice(0, boundaryIndex + 1));
      for (const message of result.messages) {
        if (ids.has(message.id) || !accepted.has(message.id)) { continue; } ids.add(message.id);
        const text = messageText(message, options); if (!text) { continue; }
        if (++count > 10000) { throw new Error('会话超过 10000 条消息，导出未完成'); }
        bytes += utf8Length(text); if (bytes > 8388608) { throw new Error('导出内容超过 8 MB，导出未完成；可先关闭工具详情后重试'); }
        chunks.push(text);
      }
      progress(count); complete = boundaryIndex >= 0;
      if (!complete && (!result.cursor || !result.ids.length)) { throw new Error('历史在读取期间发生变化，导出未完成，请重试'); }
      cursor = result.cursor;
    }
    this.check(); return { name: exportFilename(title, options.format), text: chunks.join(''), count: count };
  }
}
