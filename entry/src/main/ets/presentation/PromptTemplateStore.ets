import { util } from '@kit.ArkTS';
import { PromptTemplate, PromptTemplatePort, parsePromptTemplates, PROMPT_TEMPLATE_LIMIT } from '../domain/PromptTemplates';

@Observed
export class PromptTemplateStore {
  items: PromptTemplate[] = [];
  ready: boolean = false;
  loading: boolean = false;
  saving: boolean = false;
  error: string = '';
  editing: boolean = false;
  editID: string = '';
  title: string = '';
  text: string = '';
  private originalTitle: string = '';
  private originalText: string = '';
  private port: PromptTemplatePort;
  constructor(port: PromptTemplatePort) { this.port = port; }
  async load(): Promise<void> {
    if (this.loading || this.saving) { return; }
    this.loading = true; this.error = '';
    try { this.items = parsePromptTemplates(JSON.stringify(await this.port.load())); this.ready = true; }
    catch (_) { this.error = '常用提示词未能读取，请重试；原有内容不会被覆盖'; }
    finally { this.loading = false; }
  }
  edit(item?: PromptTemplate): void {
    if (!this.ready || this.saving || this.loading) { return; }
    this.editID = item?.id || ''; this.title = item?.title || ''; this.text = item?.text || '';
    this.originalTitle = this.title; this.originalText = this.text; this.editing = true; this.error = '';
  }
  changed(): boolean { return this.title !== this.originalTitle || this.text !== this.originalText; }
  cancel(): void { if (!this.saving) { this.editing = false; this.error = ''; } }
  async save(): Promise<boolean> {
    if (!this.ready || !this.editing || this.saving || this.loading) { return false; }
    this.error = '';
    if (!this.title.trim() || this.title.trim().length > 60 || !this.text.trim() || this.text.length > 20000) {
      this.error = '请输入名称（最多 60 字符）和内容（最多 20000 字符）'; return false;
    }
    if (!this.editID && this.items.length >= PROMPT_TEMPLATE_LIMIT) { this.error = '最多保存 50 条，请先删除不再使用的提示词'; return false; }
    if (this.editID && !this.items.some((item: PromptTemplate): boolean => item.id === this.editID)) { this.error = '这条提示词已不存在，请返回列表'; return false; }
    const item: PromptTemplate = { id: this.editID || util.generateRandomUUID(true), title: this.title.trim(), text: this.text, updated: Date.now() };
    const next = this.items.filter((old: PromptTemplate): boolean => old.id !== item.id).concat([item]);
    return this.commit(next);
  }
  async remove(id: string): Promise<boolean> {
    if (!this.ready || this.loading || this.saving || !this.items.some((item: PromptTemplate): boolean => item.id === id)) { return false; }
    return this.commit(this.items.filter((item: PromptTemplate): boolean => item.id !== id));
  }
  private async commit(next: PromptTemplate[]): Promise<boolean> {
    this.saving = true; this.error = '';
    try { const copy = parsePromptTemplates(JSON.stringify(next)); await this.port.save(copy); this.items = copy; this.editing = false; return true; }
    catch (_) { this.error = '提示词未能保存，请重试；当前编辑内容仍然保留'; return false; }
    finally { this.saving = false; }
  }
}
