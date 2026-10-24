export interface PromptTemplate { id: string; title: string; text: string; updated: number; }
export interface PromptTemplatePort {
  load(): Promise<PromptTemplate[]>;
  save(items: PromptTemplate[]): Promise<void>;
}
export const PROMPT_TEMPLATE_LIMIT = 50;
export function parsePromptTemplates(body: string): PromptTemplate[] {
  const items = JSON.parse(body) as PromptTemplate[];
  if (!Array.isArray(items) || items.length > PROMPT_TEMPLATE_LIMIT) { throw new Error('提示词数据格式不正确'); }
  const seen = new Set<string>();
  for (const item of items) {
    if (!item || typeof item.id !== 'string' || !/^[a-zA-Z0-9_-]{1,80}$/.test(item.id) || seen.has(item.id) ||
      typeof item.title !== 'string' || !item.title.trim() || item.title.length > 60 ||
      typeof item.text !== 'string' || !item.text.trim() || item.text.length > 20000 ||
      typeof item.updated !== 'number' || !Number.isFinite(item.updated) || item.updated < 0) { throw new Error('提示词数据格式不正确'); }
    seen.add(item.id);
  }
  return items.map((item: PromptTemplate): PromptTemplate => ({ id: item.id, title: item.title, text: item.text, updated: item.updated }))
    .sort((a: PromptTemplate, b: PromptTemplate): number => b.updated - a.updated || a.id.localeCompare(b.id));
}
export function findPromptTemplates(items: PromptTemplate[], query: string): PromptTemplate[] {
  const needle = query.trim().slice(0, 120).toLowerCase();
  return items.filter((item: PromptTemplate): boolean => !needle || (item.title + '\n' + item.text).toLowerCase().indexOf(needle) >= 0);
}
export function appendPromptTemplate(draft: string, text: string): string {
  if (!text.trim() || text.length > 20000) { throw new Error('提示词需包含 1–20000 个字符'); }
  const result = draft ? draft + '\n\n' + text : text;
  if (result.length > 20000) { throw new Error('插入后超过 20000 字符，请先缩短输入栏中的文字'); }
  return result;
}
