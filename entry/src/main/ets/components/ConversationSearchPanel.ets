import { ChatMessage } from '../domain/Core';
import { ConversationHit, searchConversation } from '../domain/ConversationSearch';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { NativeSegments } from './NativeSegments';
@Component
export struct ConversationSearchPanel {
  @Prop messages: ChatMessage[] = [];
  @Prop hasEarlier: boolean = false;
  @Prop canLoad: boolean = false;
  @Prop busy: boolean = false;
  @State query: string = '';
  @State role: number = 0;
  @State details: boolean = false;
  onSelect: (hit: ConversationHit) => void = (): void => {};
  onEarlier: () => void = (): void => {};
  private hits(): ConversationHit[] { return searchConversation(this.messages, this.query, this.role === 1 ? 'user' : this.role === 2 ? 'assistant' : '', this.details); }
  build() {
    Column({ space: 12 }) {
      TextInput({ placeholder: '查找这段对话中的内容', text: this.query }).id('conversation-search-input').fontSize(15).height(44).maxLength(120)
        .backgroundColor(Color.Transparent).backgroundEffect({ radius: 24, saturation: 1.1, color: C.glass_fill })
        .border({ width: 0.5, color: C.glass_stroke }).borderRadius(14).placeholderFont({ size: 15 })
        .onChange((value: string) => { this.query = value; })
      NativeSegments({ first: '全部', second: '我的消息', third: '助手回复', selected: this.role, onSelect: (index: number): void => { this.role = index; } })
      Row({ space: 10 }) {
        Text('同时查找思考与工具').fontSize(14).fontColor(C.secondary).layoutWeight(1)
        Toggle({ type: ToggleType.Switch, isOn: this.details }).id('search-details').accessibilityText('同时查找思考与工具').onChange((value: boolean) => { this.details = value; })
      }.width('100%')
      Text('已加载 ' + this.messages.length + ' 条 · ' + this.hits().length + ' 条匹配').id('conversation-search-count').fontSize(12).fontColor(C.secondary).width('100%')
      List({ space: 8 }) {
        ForEach(this.hits(), (hit: ConversationHit) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Column({ space: 8 }) {
                Text(hit.label).fontSize(12).fontColor(C.secondary).width('100%')
                Text() { Span(hit.before); Span(hit.match).fontWeight(FontWeight.Bold); Span(hit.after) }
                  .fontSize(15).lineHeight(23).fontColor(C.text).width('100%').maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.padding(14).width('100%').alignItems(HorizontalAlign.Start)
            }.id('search-hit-' + hit.id).width('100%').backgroundColor(Color.Transparent)
              .border({ width: 0.5, color: C.glass_stroke }).borderRadius(16).onClick(() => { this.onSelect(hit); })
          }
        }, (hit: ConversationHit) => hit.id + hit.label + hit.before + hit.match + hit.after)
        if (!this.hits().length) { ListItem() { Text(this.query.trim() ? '当前已加载的消息中没有找到。' : '输入关键词，点按结果返回消息位置。')
          .id('conversation-search-empty').fontSize(14).fontColor(C.secondary).padding(16) } }
      }.layoutWeight(1).width('100%')
      if (this.hasEarlier) {
        Button(this.busy ? '正在读取更早消息…' : '加载更早消息后继续查找').id('search-earlier').height(44).width('100%').fontSize(14)
          .backgroundColor(Color.Transparent).fontColor(C.text).border({ width: 0.5, color: C.glass_stroke }).borderRadius(14)
          .enabled(this.canLoad && !this.busy).onClick(() => { this.onEarlier(); })
      }
      Text('仅查找当前加载的消息，最多保留 300 条；更早内容需手动读取，不会自动下载整段历史或附件。')
        .fontSize(12).lineHeight(18).fontColor(C.secondary).width('100%')
    }.id('conversation-search-panel').padding(20).width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
