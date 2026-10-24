import { ChatMessage } from './Core';
export interface ConversationHit { id: string; role: string; label: string; before: string; match: string; after: string; }
export function searchConversation(messages: ChatMessage[], query: string, role: string = '', details: boolean = false): ConversationHit[] {
  const needle = Array.from(query.trim()).slice(0, 120).join('').toLowerCase();
  if (!needle) { return []; }
  const hits: ConversationHit[] = []; const seen = new Set<string>();
  for (const message of messages.slice(-300)) {
    if (seen.has(message.id) || (role && message.role !== role)) { continue; }
    seen.add(message.id);
    const texts: string[] = [message.text];
    const labels: string[] = [message.role === 'user' ? '我的消息' : message.role === 'assistant' ? '助手回复' : '会话记录'];
    if (details) {
      texts.push(message.reasoning); labels.push('思考');
      message.tools.forEach((tool) => { texts.push(tool.name + '\n' + tool.input + '\n' + tool.output); labels.push('工具 · ' + tool.name); });
    }
    (message.files || []).forEach((file) => { texts.push(file.name); labels.push('附件名称'); });
    for (let field = 0; field < texts.length; field++) {
      const text = texts[field] || ''; const folded = text.toLowerCase(); const found = folded.indexOf(needle);
      if (found < 0) { continue; }
      let start = found; let end = found + needle.length;
      if (folded.length !== text.length) {
        let offset = 0; let original = 0;
        for (const character of text) {
          const next = offset + character.toLowerCase().length;
          if (offset <= found && found < next) { start = original; }
          if (offset < found + needle.length && found + needle.length <= next) { end = original + character.length; break; }
          offset = next; original += character.length;
        }
      }
      let left = Math.max(0, start - 44); let right = Math.min(text.length, end + 88);
      if (left > 0 && /[\uDC00-\uDFFF]/.test(text.charAt(left))) { left--; }
      if (right < text.length && /[\uDC00-\uDFFF]/.test(text.charAt(right))) { right++; }
      hits.push({ id: message.id, role: message.role, label: labels[field], before: (left ? '…' : '') + text.slice(left, start),
        match: text.slice(start, end), after: text.slice(end, right) + (right < text.length ? '…' : '') });
      break;
    }
  }
  return hits.reverse();
}
