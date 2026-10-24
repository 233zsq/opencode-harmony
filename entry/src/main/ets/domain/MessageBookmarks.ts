import { ChatMessage, ServerConfig } from './Core';
export interface BookmarkFile { name: string; mime: string; size: number; }
export interface MessageBookmark { id: string; directory: string; sessionID: string; sessionTitle: string; messageID: string; role: string; text: string; files: BookmarkFile[]; savedAt: number; }
export interface MessageBookmarkPort {
  bookmarks(config: ServerConfig): Promise<MessageBookmark[]>;
  saveBookmark(config: ServerConfig, item: MessageBookmark): Promise<void>;
  removeBookmark(config: ServerConfig, id: string): Promise<void>;
}
export class EmptyMessageBookmarks implements MessageBookmarkPort {
  async bookmarks(config: ServerConfig): Promise<MessageBookmark[]> { throw new Error('加密收藏存储暂不可用'); }
  async saveBookmark(config: ServerConfig, item: MessageBookmark): Promise<void> { throw new Error('加密收藏存储暂不可用'); }
  async removeBookmark(config: ServerConfig, id: string): Promise<void> { throw new Error('加密收藏存储暂不可用'); }
}
export function bookmarkID(directory: string, sessionID: string, messageID: string): string { return JSON.stringify([directory, sessionID, messageID]); }
export function bookmarkMessage(message: ChatMessage, directory: string, sessionID: string, title: string): MessageBookmark {
  if (['user', 'assistant'].indexOf(message.role) < 0 || (message.role === 'assistant' && ['completed', 'failed'].indexOf(message.state) < 0)) { throw new Error('请等消息完成后再收藏'); }
  const item: MessageBookmark = { id: bookmarkID(directory, sessionID, message.id), directory: directory, sessionID: sessionID,
    sessionTitle: title.slice(0, 160), messageID: message.id, role: message.role, text: message.text,
    files: (message.files || []).slice(0, 4).map((file): BookmarkFile => ({ name: file.name.slice(0, 160), mime: file.mime.slice(0, 100), size: file.size })), savedAt: Date.now() };
  return parseBookmark(JSON.stringify(item));
}
export function parseBookmark(body: string): MessageBookmark {
  const item = JSON.parse(body) as MessageBookmark;
  if (!item || typeof item.directory !== 'string' || !item.directory || item.directory.length > 4096 || typeof item.sessionID !== 'string' || !item.sessionID || item.sessionID.length > 256 ||
    typeof item.messageID !== 'string' || !item.messageID || item.messageID.length > 256 || item.id !== bookmarkID(item.directory, item.sessionID, item.messageID) ||
    typeof item.sessionTitle !== 'string' || item.sessionTitle.length > 160 || ['user', 'assistant'].indexOf(item.role) < 0 ||
    typeof item.text !== 'string' || item.text.length > 100000 || !Array.isArray(item.files) || item.files.length > 4 || (!item.text.trim() && !item.files.length) ||
    !Number.isFinite(item.savedAt) || item.savedAt < 0 || item.files.some((file: BookmarkFile): boolean => !file || typeof file.name !== 'string' || file.name.length > 160 || typeof file.mime !== 'string' || file.mime.length > 100 || !Number.isFinite(file.size) || file.size < 0)) {
    throw new Error('收藏内容无效；正文最多 100000 字符');
  }
  return { id: item.id, directory: item.directory, sessionID: item.sessionID, sessionTitle: item.sessionTitle, messageID: item.messageID, role: item.role, text: item.text,
    files: item.files.map((file: BookmarkFile): BookmarkFile => ({ name: file.name, mime: file.mime, size: file.size })), savedAt: item.savedAt };
}
export function findBookmarks(items: MessageBookmark[], query: string): MessageBookmark[] {
  const needle = query.trim().slice(0, 120).toLowerCase();
  return items.filter((item: MessageBookmark): boolean => !needle || (item.text + '\n' + item.sessionTitle + '\n' + item.files.map((file: BookmarkFile): string => file.name).join('\n')).toLowerCase().indexOf(needle) >= 0);
}
