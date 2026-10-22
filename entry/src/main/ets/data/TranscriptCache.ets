import { common } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { cryptoFramework } from '@kit.CryptoArchitectureKit';
import { util } from '@kit.ArkTS';
import { Attachment } from '../domain/Attachments';
import { ServerConfig, ChatMessage, TranscriptSnapshot, TranscriptCachePort } from '../domain/Core';

interface CacheEntry { body: string; }
export class TranscriptCache implements TranscriptCachePort {
  private db: relationalStore.RdbStore | undefined = undefined;
  private queue: Promise<void> = Promise.resolve();
  private encoder: util.TextEncoder = new util.TextEncoder();
  private limit: number = 200 * 1048576;

  async init(context: common.Context): Promise<void> {
    this.db = await relationalStore.getRdbStore(context, {
      name: 'opencode_transcript_cache_v1.db', securityLevel: relationalStore.SecurityLevel.S3, encrypt: true
    });
    await this.db.executeSql('CREATE TABLE IF NOT EXISTS entries (key TEXT PRIMARY KEY, server TEXT NOT NULL, body TEXT NOT NULL, bytes INTEGER NOT NULL, touched INTEGER NOT NULL)');
    await this.db.executeSql('CREATE INDEX IF NOT EXISTS cache_lru ON entries(touched)');
  }
  private serial<T>(operation: () => Promise<T>): Promise<T> {
    const result = this.queue.then(operation);
    this.queue = result.then((): void => {}, (): void => {});
    return result;
  }
  private async hash(text: string): Promise<string> {
    const hash = cryptoFramework.createMd('SHA256');
    await hash.update({ data: this.encoder.encodeInto(text) });
    const value = await hash.digest();
    return Array.from(value.data).map((byte: number): string => byte.toString(16).padStart(2, '0')).join('');
  }
  private server(config: ServerConfig): Promise<string> {
    return this.hash(JSON.stringify([config.url.replace(/\/+$/, ''), config.username]));
  }
  private async key(config: ServerConfig, directory: string, id: string): Promise<string> {
    return 'session:' + await this.hash(JSON.stringify([await this.server(config), directory, id]));
  }
  private async read(key: string): Promise<CacheEntry | undefined> {
    if (!this.db) { return undefined; }
    const rows = await this.db.querySql('SELECT body FROM entries WHERE key=?', [key]);
    let body: string | undefined = undefined;
    try { if (rows.goToFirstRow()) { body = rows.getString(0); } } finally { rows.close(); }
    if (body === undefined) { return undefined; }
    await this.db.executeSql('UPDATE entries SET touched=? WHERE key=?', [Date.now(), key]);
    return { body: body };
  }
  private async write(key: string, server: string, body: string): Promise<void> {
    if (!this.db) { return; }
    const size = this.encoder.encodeInto(body).byteLength;
    if (size > Math.min(this.limit, 20 * 1048576)) { return; }
    await this.db.executeSql('INSERT OR REPLACE INTO entries(key,server,body,bytes,touched) VALUES(?,?,?,?,?)',
      [key, server, body, size, Date.now()]);
  }
  private async bytes(): Promise<number> {
    if (!this.db) { return 0; }
    const rows = await this.db.querySql('SELECT COALESCE(SUM(bytes),0) FROM entries');
    try { return rows.goToFirstRow() ? rows.getLong(0) : 0; } finally { rows.close(); }
  }
  private async trim(): Promise<void> {
    if (!this.db) { return; }
    while (await this.bytes() > this.limit) {
      await this.db.executeSql('DELETE FROM entries WHERE key=(SELECT key FROM entries ORDER BY touched,key LIMIT 1)');
    }
  }
  load(config: ServerConfig, directory: string, id: string): Promise<TranscriptSnapshot | undefined> {
    return this.serial(async (): Promise<TranscriptSnapshot | undefined> => {
      const key = await this.key(config, directory, id);
      const row = await this.read(key);
      if (!row) { return undefined; }
      try {
        const snapshot = JSON.parse(row.body) as TranscriptSnapshot;
        if (!Array.isArray(snapshot.messages) || snapshot.messages.length > 30 || typeof snapshot.cursor !== 'string' ||
          snapshot.messages.some((m: ChatMessage) => !m || typeof m.id !== 'string' || !Array.isArray(m.parts) || !Array.isArray(m.tools))) {
          throw new Error('Invalid cache');
        }
        const scope = await this.server(config);
        for (const message of snapshot.messages) {
          for (const file of message.files || []) {
            const hash = file.data.startsWith('blob:') ? file.data.slice(5) : !file.data ? file.remoteHash || '' : '';
            if (hash) {
              const blob = /^[a-f0-9]{64}$/.test(hash) ? await this.read(scope + ':blob:' + hash) : undefined;
              file.data = blob ? blob.body : '';
              if (!file.data && !file.remoteHash) { file.error = '预览已释放，联网后点按重新读取'; }
            }
          }
        }
        return snapshot;
      } catch (_) {
        await this.db?.executeSql('DELETE FROM entries WHERE key=?', [key]);
        return undefined;
      }
    });
  }
  save(config: ServerConfig, directory: string, id: string, snapshot: TranscriptSnapshot): Promise<void> {
    // Clone at invocation: later UI updates must not mutate queued disk writes.
    const copy = JSON.parse(JSON.stringify(snapshot)) as TranscriptSnapshot;
    return this.serial(async (): Promise<void> => {
      const scope = await this.server(config);
      copy.messages = copy.messages.slice(-30);
      for (const message of copy.messages) {
        for (const file of message.files || []) {
          if (file.data) {
            const hash = await this.hash(file.data);
            await this.write(scope + ':blob:' + hash, scope, file.data);
            file.data = 'blob:' + hash;
          }
        }
      }
      await this.write(await this.key(config, directory, id), scope, JSON.stringify(copy));
      await this.trim();
    });
  }
  file(config: ServerConfig, hash: string): Promise<string> {
    return this.serial(async (): Promise<string> => {
      if (!/^[a-f0-9]{64}$/.test(hash)) { return ''; }
      return (await this.read(await this.server(config) + ':blob:' + hash))?.body || '';
    });
  }
  saveFile(config: ServerConfig, hash: string, data: string): Promise<void> {
    return this.serial(async (): Promise<void> => {
      if (!/^[a-f0-9]{64}$/.test(hash) || await this.hash(data) !== hash) { throw new Error('附件校验失败'); }
      const scope = await this.server(config);
      await this.write(scope + ':blob:' + hash, scope, data); await this.trim();
    });
  }
  removeServer(config: ServerConfig): Promise<void> {
    return this.serial(async (): Promise<void> => {
      await this.db?.executeSql('DELETE FROM entries WHERE server=?', [await this.server(config)]);
    });
  }
  size(): Promise<number> { return this.serial((): Promise<number> => this.bytes()); }
  clear(): Promise<void> {
    return this.serial(async (): Promise<void> => {
      await this.db?.executeSql('DELETE FROM entries');
      await this.db?.executeSql('VACUUM');
    });
  }
}
