import { Attachment } from '../domain/Attachments';
import { AttachmentStrip } from './AttachmentStrip';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { ChatMessage, ToolItem, toolStatus, toolSummary } from '../domain/Core';
import { MarkdownText } from './MarkdownText';

@Component
export struct ConversationMessage {
  @Prop message: ChatMessage = { id: '', role: '', text: '', reasoning: '', tools: [], parts: [], state: 'completed' };
  @Prop thinking: boolean = false;
  @Prop reasoningExpanded: boolean = false;
  onFork: (edit: boolean) => void = (): void => {};
  onCopy: (text: string) => void = (): void => {};
  onToggleReasoning: () => void = (): void => {};
  onTool: (tool: ToolItem) => void = (tool: ToolItem): void => {};
  onOpenLink: (url: string) => void = (url: string): void => {};
  onAttachment: (item: Attachment) => void = (): void => {};
  private reasoningScroller: Scroller = new Scroller();
  @Builder
  copyMenu() { Menu() { MenuItem({ content: '复制消息' }).onClick(() => { this.onCopy(this.message.text); }) } }
  private label(tool: ToolItem): string {
    switch (tool.name) {
      case 'read': case 'read_file': return '读取文件';
      case 'edit': case 'edit_file': return '修改文件';
      case 'write': return '写入文件';
      case 'bash': return '执行命令';
      case 'glob': return '搜索文件';
      case 'grep': return '检索内容';
      case 'task': return '子任务';
      default: return tool.name;
    }
  }
  private summary(tool: ToolItem): string {
    const value = toolSummary(tool);
    return value.startsWith('/') || /^[A-Za-z]:/.test(value) ? value.split(/[\\/]/).slice(-2).join('/') : value;
  }
  private stateColor(status: string): Resource {
    if (status === 'error' || status === 'failed') { return C.danger; }
    if (status === 'completed') { return C.success; }
    if (status === 'running') { return C.accent; }
    return C.muted;
  }
  build() {
    if (this.message.role === 'user') {
      Column({ space: 8 }) {
        if (this.message.text) { Row() {
        Blank().layoutWeight(1)
        Button('编辑').id('edit-fork-' + this.message.id).accessibilityText('编辑这条消息并分叉').buttonStyle(ButtonStyleMode.TEXTUAL).height(28).constraintSize({ minWidth: 28 }).padding(0).fontSize(11).fontColor(C.muted).margin({ right: 6, top: 5 })
          .responseRegion({ x: -6, y: -6, width: 40, height: 40 }).onClick(() => { this.onFork(true); })
        Text(this.message.text).id('message-user-' + this.message.id).fontSize(14.5).lineHeight(25).fontColor(C.text)
          .padding({ left: 15, right: 15, top: 12, bottom: 12 }).backgroundColor(C.bubble)
          .borderRadius({ topLeft: 14, topRight: 14, bottomRight: 4, bottomLeft: 14 })
          .constraintSize({ maxWidth: '88%' }).wordBreak(WordBreak.BREAK_WORD).copyOption(CopyOptions.InApp)
        }.width('100%').alignItems(VerticalAlign.Top) }
        if (this.message.files?.length) { AttachmentStrip({ items: this.message.files || [], onOpen: this.onAttachment }) }
      }.width('100%').alignItems(HorizontalAlign.End).margin({ top: 12, bottom: 12 }).bindContextMenu(this.copyMenu(), ResponseType.LongPress)
    } else if (this.message.role !== 'assistant') {
      Text(this.message.text).fontSize(11).fontColor(C.muted).width('100%').textAlign(TextAlign.Center).wordBreak(WordBreak.BREAK_WORD).padding(8)
    } else {
      Column({ space: 8 }) {
        if (this.message.reasoning) {
          Column({ space: 0 }) {
            Row({ space: 9 }) {
              SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(14).fontColor([C.secondary])
              Text(this.thinking ? '正在思考' : '思考已完成').fontSize(11).fontColor(C.secondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([C.muted]).rotate({ angle: this.reasoningExpanded ? 90 : 0 })
            }.id('reasoning-toggle-' + this.message.id).width('100%').constraintSize({ minHeight: 36 }).padding({ left: 10, right: 10 })
              .accessibilityText(this.reasoningExpanded ? '收起思考' : '展开思考')
              .accessibilityDescription(this.reasoningExpanded ? '思考内容已展开' : '思考内容已收起')
              .onClick(() => { this.onToggleReasoning(); })
            if (this.reasoningExpanded) {
              Scroll(this.reasoningScroller) {
                Text(this.thinking ? this.message.reasoning.slice(-8000) : this.message.reasoning.slice(0, 12000))
                  .id('reasoning-content-' + this.message.id).fontSize(12.5).lineHeight(21).fontColor(C.secondary)
                  .wordBreak(WordBreak.BREAK_WORD).copyOption(CopyOptions.InApp).width('100%')
              }.width('100%').height(Math.min(this.thinking ? 150 : 220, Math.max(65, Math.ceil(this.message.reasoning.length / 50) * 21)))
                .padding({ left: 14, right: 14, bottom: 12 }).scrollBar(BarState.Auto)
                .onAppear(() => { if (this.thinking) { setTimeout(() => { this.reasoningScroller.scrollEdge(Edge.Bottom); }, 30); } })
              if (this.message.reasoning.length > (this.thinking ? 8000 : 12000)) {
                Text(this.thinking ? '显示最近的思考内容' : '较长内容已截断，完整记录保留在服务器').fontSize(11).fontColor(C.muted).wordBreak(WordBreak.BREAK_WORD).padding({ left: 14, right: 14, bottom: 10 })
              }
            }
          }.width('100%').border({ width: 1, color: C.separator }).borderRadius(8)
        }
        if (this.message.text) { MarkdownText({ content: this.message.text, onOpenLink: this.onOpenLink, onCopy: this.onCopy }) }
        if (this.message.text || this.message.tools.length) {
          Row({ space: 10 }) {
            if (this.message.text) {
              Button('复制回复').id('copy-message-' + this.message.id).accessibilityText('复制回复内容').buttonStyle(ButtonStyleMode.TEXTUAL).height(28).constraintSize({ minWidth: 44 }).padding({ left: 0, right: 8 }).fontSize(11).fontColor(C.muted)
                .responseRegion({ x: 0, y: -6, width: '100%', height: 40 }).onClick(() => { this.onCopy(this.message.text); })
              Divider().vertical(true).height(10).color(C.separator)
            }
            Button('分叉').id('fork-message-' + this.message.id).accessibilityText('从这条回复分叉').buttonStyle(ButtonStyleMode.TEXTUAL).height(28).constraintSize({ minWidth: 44 }).fontSize(11).fontColor(C.muted)
              .responseRegion({ x: 0, y: -6, width: '100%', height: 40 }).onClick(() => { this.onFork(false); })
          }.width('100%')
        }
        if (this.message.tools.length) {
          Column({ space: 0 }) {
            Divider().color(C.separator).margin({ left: 10, right: 10 })
            ForEach(this.message.tools, (tool: ToolItem, index: number) => {
              if (index > 0) { Divider().color(C.separator).margin({ left: 10, right: 10 }) }
              Row({ space: 8 }) {
                SymbolGlyph(tool.status === 'error' || tool.status === 'failed' ? $r('sys.symbol.exclamationmark_circle') : $r('sys.symbol.code_square')).fontSize(14).fontColor([tool.status === 'error' || tool.status === 'failed' ? C.danger : C.secondary])
                Text(this.label(tool)).fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 90 })
                Text(this.summary(tool)).fontSize(10).fontFamily('monospace').fontColor(C.muted).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                Text(toolStatus(tool.status)).fontSize(9.5).fontFamily('monospace').letterSpacing(1.2).maxLines(1).fontColor(this.stateColor(tool.status))
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([C.muted])
              }.id('tool-row-' + tool.id).width('100%').constraintSize({ minHeight: 40 }).padding({ left: 10, right: 10 })
                .accessibilityText('查看工具详情：' + this.label(tool))
                .accessibilityDescription('状态：' + toolStatus(tool.status))
                .onClick(() => { this.onTool(tool); })
            }, (tool: ToolItem) => tool.id + tool.status + tool.input)
          }.width('100%')
        }
        if (!this.message.text && !this.message.reasoning && !this.message.tools.length) {
          Text('正在等待回复…').fontSize(12.5).fontColor(C.muted).wordBreak(WordBreak.BREAK_WORD)
        }
      }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 4, bottom: 6 }).justifyContent(FlexAlign.Start)
    }
  }
}

