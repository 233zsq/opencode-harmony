import { ChatMessage, ToolItem, toolStatus, toolSummary } from '../domain/Core';
import { MarkdownText } from './MarkdownText';

@Component
export struct ConversationMessage {
  @Prop message: ChatMessage = { id: '', role: '', text: '', reasoning: '', tools: [], parts: [], state: 'completed' };
  @Prop thinking: boolean = false;
  @Prop reasoningExpanded: boolean = false;
  onToggleReasoning: () => void = (): void => {};
  onTool: (tool: ToolItem) => void = (tool: ToolItem): void => {};
  onOpenLink: (url: string) => void = (url: string): void => {};
  private reasoningScroller: Scroller = new Scroller();
  build() {
    if (this.message.role === 'user') {
      Row() {
        Blank().layoutWeight(1)
        Text(this.message.text).id('message-user-' + this.message.id).fontSize(15).lineHeight(25).fontColor('#252B30')
          .padding({ left: 18, right: 18, top: 12, bottom: 12 }).backgroundColor('#F1F3F4').borderRadius(20)
          .constraintSize({ maxWidth: '88%' }).copyOption(CopyOptions.InApp)
      }.width('100%').margin({ top: 6, bottom: 14 })
    } else if (this.message.role !== 'assistant') {
      Text(this.message.text).fontSize(11).fontColor('#939A9F').width('100%').textAlign(TextAlign.Center).padding(8)
    } else {
      Column({ space: 15 }) {
        if (this.message.reasoning) {
          Column({ space: 0 }) {
            Row({ space: 9 }) {
              Text(this.thinking ? '◌' : '✧').fontSize(19).fontColor('#6A8175')
              Text(this.thinking ? '正在思考' : '思考已完成').fontSize(13).fontColor('#747D83').layoutWeight(1)
              Text(this.reasoningExpanded ? '⌃' : '›').fontSize(18).fontColor('#A0A6AA')
            }.id('reasoning-toggle-' + this.message.id).width('100%').padding(12)
              .onClick(() => { this.onToggleReasoning(); })
            if (this.reasoningExpanded) {
              Scroll(this.reasoningScroller) {
                Text(this.thinking ? this.message.reasoning.slice(-8000) : this.message.reasoning.slice(0, 12000))
                  .id('reasoning-content-' + this.message.id).fontSize(13).lineHeight(22).fontColor('#828B90')
                  .copyOption(CopyOptions.InApp).width('100%')
              }.width('100%').height(Math.min(this.thinking ? 150 : 220, Math.max(65, Math.ceil(this.message.reasoning.length / 50) * 22)))
                .padding({ left: 14, right: 14, bottom: 14 }).scrollBar(BarState.Auto)
                .onAppear(() => { if (this.thinking) { setTimeout(() => { this.reasoningScroller.scrollEdge(Edge.Bottom); }, 30); } })
              if (this.message.reasoning.length > (this.thinking ? 8000 : 12000)) {
                Text(this.thinking ? '显示最近的思考内容' : '较长内容已截断，完整记录保留在服务器').fontSize(10).fontColor('#929B9F').padding(8)
              }
            }
          }.width('100%').border({ width: 1, color: '#E9ECEB' }).borderRadius(12)
        }
        if (this.message.text) { MarkdownText({ content: this.message.text, onOpenLink: this.onOpenLink }) }
        if (this.message.tools.length) {
          Column({ space: 0 }) {
            ForEach(this.message.tools, (tool: ToolItem) => {
              Row({ space: 9 }) {
                Text(tool.status === 'error' || tool.status === 'failed' ? '!' : '⌁').fontSize(18).fontColor(tool.status === 'error' ? '#B86B5B' : '#7D8883')
                Column({ space: 3 }) {
                  Text(tool.name).fontSize(13).fontWeight(FontWeight.Medium).fontColor('#4D575D').maxLines(1)
                  if (toolSummary(tool)) { Text(toolSummary(tool)).fontSize(11).fontColor('#939BA0').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }) }
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text(toolStatus(tool.status)).fontSize(10).fontColor(tool.status === 'error' || tool.status === 'failed' ? '#B86B5B' : '#8E9993')
                Text('›').fontSize(20).fontColor('#B2B7BA')
              }.id('tool-row-' + tool.id).width('100%').padding(12).onClick(() => { this.onTool(tool); })
            }, (tool: ToolItem) => tool.id + tool.status + tool.input)
          }.width('100%').border({ width: 1, color: '#E9ECEB' }).borderRadius(12)
        }
        if (!this.message.text && !this.message.reasoning && !this.message.tools.length) {
          Text('正在等待回复…').fontSize(13).fontColor('#A0A7AB')
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 4, bottom: 20 })
    }
  }
}