export interface Attachment {
  id: string; name: string; mime: string; data: string; size: number; uri?: string; error?: string; fingerprint?: string; remoteHash?: string; remoteMessage?: string; remoteIndex?: number;
}
export interface PromptFile { uri: string; name: string; }
export const ATTACHMENT_LIMIT = 1048576;
export const ATTACHMENT_COUNT = 4;
export function attachmentBytes(items: Attachment[]): number { return items.reduce((sum: number, item: Attachment) => sum + item.size, 0); }
export function attachmentUrl(item: Attachment): string { return item.data ? 'data:' + item.mime + ';base64,' + item.data : ''; }
export function attachmentSize(size: number): string { return size < 1024 ? String(size) + ' B' : (size / 1024).toFixed(size < 10240 ? 1 : 0) + ' KB'; }
export function attachmentMime(name: string): string {
  const ext = name.toLowerCase().split('.').pop() || '';
  if (ext === 'pdf') { return 'application/pdf'; }
  if (['png', 'jpg', 'jpeg', 'webp', 'gif', 'heic', 'heif', 'bmp'].indexOf(ext) >= 0) { return 'image/' + (ext === 'jpg' ? 'jpeg' : ext); }
  if (['txt','md','markdown','json','jsonl','csv','xml','yaml','yml','toml','ini','log','ts','tsx','js','jsx','ets','py','java','kt','c','h','cpp','hpp','css','html','sql','sh','go','rs','swift','vue','svelte','properties'].indexOf(ext) >= 0) { return 'text/plain'; }
  throw new Error('暂不支持此文件类型，请选择图片、PDF 或 UTF-8 文本/代码文件');
}
export function attachmentProblem(items: Attachment[], input: string[]): string {
  if (items.length > ATTACHMENT_COUNT) { return '一次最多添加 4 个附件'; }
  if (items.some((item: Attachment) => !!item.error || !item.data)) { return '请先重试或移除读取失败的附件'; }
  if (attachmentBytes(items) > ATTACHMENT_LIMIT) { return '附件合计不能超过 1 MB，请移除部分附件后重试'; }
  if (items.some((item: Attachment) => item.mime.startsWith('image/')) && input.indexOf('image') < 0) { return '当前模型未声明图片输入能力，请切换支持图片的模型或移除图片'; }
  if (items.some((item: Attachment) => item.mime === 'application/pdf') && input.indexOf('pdf') < 0) { return '当前模型未声明 PDF 输入能力，请切换模型或移除 PDF'; }
  return '';
}
export function promptFiles(items: Attachment[]): PromptFile[] {
  return items.map((item: Attachment): PromptFile => ({ uri: attachmentUrl(item), name: item.name }));
}
// Metadata on an unreadable history attachment is still shown; arbitrary remote URIs are never fetched.
export function historyAttachment(id: string, name: string, mime: string, data: string): Attachment {
  const safe = ['image/png','image/jpeg','image/webp','image/gif','text/plain','application/pdf'].indexOf(mime) >= 0;
  const valid = data.length <= 1500000 && data.length % 4 === 0 && /^[A-Za-z0-9+/]*={0,2}$/.test(data);
  let hash = 2166136261; for (let i = 0; i < data.length; i++) { hash = Math.imul(hash ^ data.charCodeAt(i), 16777619); }
  return { fingerprint: String(hash >>> 0), id: id, name: name.replace(/[\x00-\x1f]/g, '').slice(0, 160) || '附件', mime: mime, data: safe && valid ? data : '', size: Math.max(0, Math.floor(data.length * 3 / 4) - (data.endsWith('==') ? 2 : data.endsWith('=') ? 1 : 0)),
    error: !safe || !valid ? '附件超出预览范围或类型不支持' : undefined };
}
