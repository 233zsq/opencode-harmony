import { ChatMessage } from '../domain/Core';

export class MessageDataSource implements IDataSource {
  private messages: ChatMessage[] = [];
  private listeners: DataChangeListener[] = [];
  totalCount(): number { return this.messages.length; }
  getData(index: number): ChatMessage { return this.messages[index]; }
  registerDataChangeListener(listener: DataChangeListener): void { if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener); } }
  unregisterDataChangeListener(listener: DataChangeListener): void { this.listeners = this.listeners.filter((l: DataChangeListener) => l !== listener); }
  update(messages: ChatMessage[]): void {
    if (messages === this.messages) { return; }
    const previous = this.messages; this.messages = messages;
    if (previous.length === messages.length && previous.every((m: ChatMessage, i: number) => m.id === messages[i].id)) {
      messages.forEach((m: ChatMessage, i: number) => { if (m !== previous[i]) { this.listeners.forEach((l: DataChangeListener) => l.onDataChange(i)); } });
    } else { this.listeners.forEach((l: DataChangeListener) => l.onDataReloaded()); }
  }
}
