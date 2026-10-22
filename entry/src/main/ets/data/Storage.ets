import { ModelPreferences, emptyModelPreferences, normalizeModelPreferences } from '../domain/ModelSelection';
import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ServerConfig, SessionPreference } from '../domain/Core';

export class Storage {
  private prefs: preferences.Preferences | undefined = undefined;
  private encoder: util.TextEncoder = new util.TextEncoder();
  async init(context: common.Context): Promise<void> {
    try { this.prefs = await preferences.getPreferences(context, { name: 'opencode_settings' }); }
    catch (e) { throw e as Error; }
  }
  async servers(): Promise<ServerConfig[]> {
    try {
      if (!this.prefs) { return []; }
      return JSON.parse(await this.prefs.get('servers', '[]') as string) as ServerConfig[];
    } catch (e) { throw e as Error; }
  }
  async activeServer(): Promise<string> { try { return await this.prefs?.get('activeServer', '') as string || ''; } catch (e) { throw e as Error; } }
  async rememberServer(id: string): Promise<void> { try { await this.prefs?.put('activeServer', id); await this.prefs?.flush(); } catch (e) { throw e as Error; } }
  async saveServers(servers: ServerConfig[]): Promise<void> {
    try { await this.prefs?.put('servers', JSON.stringify(servers)); await this.prefs?.flush(); }
    catch (e) { throw e as Error; }
  }
  async position(serverID: string, directory: string, sessionID: string): Promise<void> {
    try { await this.prefs?.put('position.' + serverID, JSON.stringify([directory, sessionID])); await this.prefs?.flush(); }
    catch (e) { throw e as Error; }
  }
  async last(serverID: string): Promise<string[]> {
    try { return JSON.parse(await this.prefs?.get('position.' + serverID, '[]') as string || '[]') as string[]; }
    catch (e) { throw e as Error; }
  }
  async sessionPreferences(serverID: string): Promise<SessionPreference[]> {
    try {
      const value = JSON.parse(await this.prefs?.get('sessionPreferences.' + serverID, '[]') as string || '[]') as SessionPreference[];
      return Array.isArray(value) ? value.filter((p: SessionPreference) => typeof p.id === 'string' && (p.pinned === true || p.archived === true)) : [];
    } catch (_) { return []; }
  }
  async saveSessionPreferences(serverID: string, flags: SessionPreference[]): Promise<void> {
    if (!this.prefs) { throw new Error('本机设置尚未就绪'); }
    try { await this.prefs.put('sessionPreferences.' + serverID, JSON.stringify(flags)); await this.prefs.flush(); }
    catch (e) { throw e as Error; }
  }
  async resetServerPosition(id: string): Promise<void> {
    if (!this.prefs) { throw new Error('本机设置尚未就绪'); }
    try { await this.prefs.put('position.' + id, '[]'); await this.prefs.put('sessionPreferences.' + id, '[]'); await this.prefs.put('modelPreferences.' + id, JSON.stringify(emptyModelPreferences())); await this.prefs.flush(); } catch (e) { throw e as Error; }
  }
  async modelPreferences(serverID: string): Promise<ModelPreferences> {
    if (!this.prefs) { throw new Error('本机设置尚未就绪'); }
    let raw: string;
    try { raw = await this.prefs.get('modelPreferences.' + serverID, '') as string; } catch (e) { throw e as Error; }
    if (!raw) { return emptyModelPreferences(); }
    try { return normalizeModelPreferences(JSON.parse(raw) as ModelPreferences); } catch (_) { return emptyModelPreferences(); }
  }
  async saveModelPreferences(serverID: string, value: ModelPreferences): Promise<void> {
    if (!this.prefs) { throw new Error('本机设置尚未就绪'); }
    const key = 'modelPreferences.' + serverID; let before: string;
    try { before = await this.prefs.get(key, '') as string; } catch (e) { throw e as Error; }
    try { await this.prefs.put(key, JSON.stringify(normalizeModelPreferences(value))); await this.prefs.flush(); }
    catch (error) { try { await this.prefs.put(key, before); await this.prefs.flush(); } catch (_) {} throw error as Error; }
  }
  private query(id: string): asset.AssetMap {
    try {
      const q: asset.AssetMap = new Map<asset.Tag, asset.Value>();
      q.set(asset.Tag.ALIAS, this.encoder.encodeInto('opencode.server.' + id)); return q;
    } catch (e) { throw e as Error; }
  }
  async secret(id: string): Promise<string> {
    const q = this.query(id); q.set(asset.Tag.RETURN_TYPE, asset.ReturnType.ALL);
    try {
      const result = await asset.query(q);
      return result.length ? new util.TextDecoder('utf-8').decodeToString(result[0].get(asset.Tag.SECRET) as Uint8Array) : '';
    } catch (e) { if ((e as BusinessError).code === 24000002) { return ''; } throw e as Error; }
  }
  async saveSecret(id: string, secret: string): Promise<void> {
    const q = this.query(id);
    if (!secret) {
      try { await asset.remove(q); } catch (e) { if ((e as BusinessError).code !== 24000002) { throw e as Error; } }
      return;
    }
    try {
      q.set(asset.Tag.SECRET, this.encoder.encodeInto(secret));
      q.set(asset.Tag.ACCESSIBILITY, asset.Accessibility.DEVICE_FIRST_UNLOCKED);
      q.set(asset.Tag.AUTH_TYPE, asset.AuthType.NONE);
      q.set(asset.Tag.CONFLICT_RESOLUTION, asset.ConflictResolution.OVERWRITE);
      await asset.add(q);
    } catch (e) { throw e as Error; }
  }
}
