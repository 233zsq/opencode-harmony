import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { asset } from '@kit.AssetStoreKit';
import { util } from '@kit.ArkTS';
import { BusinessError } from '@kit.BasicServicesKit';
import { ServerConfig } from '../domain/Core';

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
