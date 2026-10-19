import { ServerConfig, normalizeUrl } from './Core';
export interface ConnectionInput { name: string; url: string; username: string; allowHttp: boolean; useDedicatedTrust: boolean; }
export function connectionAddress(value: string, allowHttp: boolean): string {
  const normalized = normalizeUrl(value.replace(/^https:/i, 'https:').replace(/^http:/i, 'http:'), allowHttp);
  if (normalized.indexOf('\\') >= 0) { throw new Error('服务器地址不能包含反斜杠'); }
  const match = normalized.match(/^(https?:\/\/)([^/]+)(.*)$/);
  if (!match) { throw new Error('服务器地址无效'); }
  let host = match[2].toLowerCase();
  if (match[1] === 'https://') { host = host.replace(/:443$/, ''); } else { host = host.replace(/:80$/, ''); }
  return match[1] + host + match[3];
}
export function sameConnectionIdentity(left: ServerConfig, right: ServerConfig): boolean {
  try { return connectionAddress(left.url, true) === right.url && left.username === right.username; } catch (_) { return false; }
}
export function prepareConnection(input: ConnectionInput, servers: ServerConfig[], id: string, preferredModel: string = ''): ServerConfig {
  const url = connectionAddress(input.url.trim(), input.allowHttp); const username = input.username.trim() || 'opencode';
  if (username.length > 120 || /[:\x00-\x1f]/.test(username)) { throw new Error('API 用户名不能包含冒号或控制字符，最多 120 字符'); }
  if (/[\x00-\x1f]/.test(input.name.trim())) { throw new Error('连接名称不能包含控制字符'); }
  if (input.name.trim().length > 80) { throw new Error('连接名称最多 80 字符'); }
  if (input.useDedicatedTrust && !url.startsWith('https://')) { throw new Error('专用证书连接必须使用 HTTPS'); }
  if (servers.some((server: ServerConfig) => server.id !== id && sameConnectionIdentity(server, { id: id, name: '', url: url, username: username, allowHttp: input.allowHttp }))) { throw new Error('相同地址和账号的连接已存在，请直接编辑或连接'); }
  return { id: id, name: input.name.trim() || 'OpenCode', url: url, username: username, allowHttp: input.allowHttp, useDedicatedTrust: input.useDedicatedTrust, preferredModel: preferredModel };
}
