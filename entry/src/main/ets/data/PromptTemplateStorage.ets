import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { PromptTemplate, PromptTemplatePort, parsePromptTemplates } from '../domain/PromptTemplates';

// Authored content lives separately from disposable transcript caches. Never falls back to plaintext.
export class PromptTemplateStorage implements PromptTemplatePort {
  private context: common.Context | undefined = undefined;
  private opening: Promise<relationalStore.RdbStore> | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  attach(context: common.Context): void { this.context = context; }
  private async open(): Promise<relationalStore.RdbStore> {
    if (!this.context) { throw new Error('加密提示词存储尚未就绪'); }
    const db = await relationalStore.getRdbStore(this.context, {
      name: 'opencode_prompt_templates_v1.db', securityLevel: relationalStore.SecurityLevel.S3, encrypt: true
    });
    await db.executeSql('CREATE TABLE IF NOT EXISTS library (id INTEGER PRIMARY KEY CHECK(id=1), body TEXT NOT NULL)');
    return db;
  }
  private async database(): Promise<relationalStore.RdbStore> {
    if (!this.opening) { this.opening = this.open(); }
    try { return await this.opening; } catch (error) { this.opening = undefined; throw error as Error; }
  }
  private serial<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation); this.queue = result.then((): void => {}, (): void => {}); return result;
  }
  load(): Promise<PromptTemplate[]> {
    return this.serial(async (): Promise<PromptTemplate[]> => {
      const db = await this.database(); const rows = await db.querySql('SELECT body FROM library WHERE id=1');
      let body = '[]'; try { if (rows.goToFirstRow()) { body = rows.getString(0); } } finally { rows.close(); }
      return parsePromptTemplates(body);
    });
  }
  save(items: PromptTemplate[]): Promise<void> {
    // Snapshot before waiting for the queue; one SQL statement replaces the complete bounded collection atomically.
    const body = JSON.stringify(parsePromptTemplates(JSON.stringify(items)));
    return this.serial(async (): Promise<void> => {
      const db = await this.database(); await db.executeSql('INSERT OR REPLACE INTO library(id,body) VALUES(1,?)', [body]);
    });
  }
}
