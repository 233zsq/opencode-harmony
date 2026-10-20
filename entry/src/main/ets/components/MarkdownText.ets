import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { MarkdownBlock, parseMarkdown, InlinePart, inlineMarkdown, previewText } from '../domain/Core';

@Component
export struct MarkdownText {
  @Prop @Watch('refresh') content: string = '';
  @State blocks: MarkdownBlock[] = [];
  onCopy: (text: string) => void = (): void => {};
  onOpenLink: (url: string) => void = (): void => {};
  aboutToAppear(): void { this.refresh(); }
  private refresh(): void { this.blocks = parseMarkdown(this.content); }
  @Builder
  replyMenu() { Menu() { MenuItem({ content: '复制完整回复' }).onClick(() => { this.onCopy(this.content); }) } }
  build() {
    Column({ space: 8 }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        if (block.kind === 'code') {
          Column({ space: 6 }) {
            Row() {
              Text(block.language || 'CODE').fontSize(9.5).fontFamily('monospace').letterSpacing(1.2).fontColor(C.code_text).layoutWeight(1)
              Button('复制代码').id('copy-code-' + block.id).buttonStyle(ButtonStyleMode.TEXTUAL).fontSize(11).fontColor(C.code_text).height(28).padding({ left: 8, right: 0 }).onClick(() => { this.onCopy(block.text); })
            }.width('100%')
            Scroll() {
              Scroll() {
                Text(previewText(block.text, 24000, 400).text || ' ').fontSize(11.5).lineHeight(19).fontFamily('monospace').fontColor(C.code_text).copyOption(CopyOptions.InApp)
              }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).padding({ bottom: 8 }).width('100%')
            }.id('markdown-code-' + block.id).scrollable(ScrollDirection.Vertical).scrollBar(BarState.Auto).width('100%')
              .height(Math.min(300, previewText(block.text, 24000, 400).text.split('\n').length * 19 + 8))
            if (previewText(block.text, 24000, 400).truncated) { Text('代码较长，预览前 400 行或 24000 字符；可复制完整代码。').fontSize(11).fontColor(C.code_text).width('100%') }
          }.alignItems(HorizontalAlign.Start).padding(12).backgroundColor(C.code_bg).borderRadius(8).width('100%')
        } else if (block.kind === 'table') {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(block.rows || [], (row: string[], index: number) => {
                Row({ space: 0 }) {
                  ForEach(row, (cell: string, column: number) => {
                    Text() {
                      ForEach(inlineMarkdown(cell), (part: InlinePart) => {
                        Span(part.text).fontWeight(index === 0 || part.strong ? FontWeight.Bold : FontWeight.Normal)
                          .fontFamily(part.kind === 'code' ? 'monospace' : 'sans-serif').fontStyle(part.emphasis ? FontStyle.Italic : FontStyle.Normal)
                          .decoration({ type: part.strike ? TextDecorationType.LineThrough : TextDecorationType.None })
                          .fontColor(part.kind === 'link' ? C.accent : C.text).onClick(() => { if (part.kind === 'link' && part.url) { this.onOpenLink(part.url); } })
                          .textBackgroundStyle({ color: part.kind === 'code' ? C.field : Color.Transparent, radius: part.kind === 'code' ? 4 : 0 })
                      }, (part: InlinePart) => part.id + part.text)
                    }.fontSize(11.5).fontColor(C.text).width(150).padding(10).border({ width: 1, color: C.separator })
                      .textAlign(block.align?.[column] === 'right' ? TextAlign.End : block.align?.[column] === 'center' ? TextAlign.Center : TextAlign.Start).copyOption(CopyOptions.InApp)
                  }, (cell: string, column: number) => String(column))
                }.backgroundColor(index === 0 ? C.field : C.surface)
              }, (row: string[], index: number) => String(index))
            }
          }.scrollable(ScrollDirection.Horizontal).width('100%')
        } else if (block.kind === 'rule') {
          Divider().color(C.separator).margin({ top: 6, bottom: 6 })
        } else {
          Text() {
            ForEach(inlineMarkdown(block.text), (part: InlinePart) => {
              Span(part.text).fontSize(part.kind === 'code' ? 11.5 : block.kind === 'heading' ? (block.level === 1 ? 20 : block.level === 2 ? 17 : 15) : block.kind === 'notice' ? 11 : 14.5)
                .fontWeight(part.kind === 'bold' || part.strong || block.kind === 'heading' ? FontWeight.Bold : FontWeight.Normal)
                .fontFamily(part.kind === 'code' ? 'monospace' : 'sans-serif').fontStyle(part.emphasis ? FontStyle.Italic : FontStyle.Normal)
                .decoration({ type: part.strike ? TextDecorationType.LineThrough : TextDecorationType.None })
                .fontColor(part.kind === 'link' ? C.accent : block.kind === 'quote' ? C.secondary : block.kind === 'notice' ? C.muted : C.text)
                .textBackgroundStyle({ color: part.kind === 'code' ? C.field : Color.Transparent, radius: part.kind === 'code' ? 4 : 0 })
                .onClick(() => { if (part.kind === 'link' && part.url) { this.onOpenLink(part.url); } })
            }, (part: InlinePart) => part.id + part.text)
          }.fontSize(block.kind === 'heading' ? (block.level === 1 ? 20 : block.level === 2 ? 17 : 15) : block.kind === 'notice' ? 11 : 14.5)
            .fontWeight(block.kind === 'heading' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(block.kind === 'quote' ? C.secondary : block.kind === 'notice' ? C.muted : C.text)
            .lineHeight(block.kind === 'heading' ? (block.level === 1 ? 27 : block.level === 2 ? 24 : 21) : block.kind === 'notice' ? 17 : 25).width('100%').copyOption(CopyOptions.InApp)
            .padding({ left: block.kind === 'list' ? (block.depth || 0) * 14 : block.kind === 'quote' ? 10 : 0 })
            .border({ width: { left: block.kind === 'quote' ? 2 : 0 }, color: C.separator })
        }
      }, (block: MarkdownBlock) => block.id + block.kind + block.text + (block.kind === 'table' ? JSON.stringify([block.rows, block.align]) : '') + (block.level || 0) + (block.depth || 0))
      if (this.content.length > 200000) { Text('预览显示前 20 万字符，可使用复制回复获取完整文本。').fontSize(11).fontColor(C.muted) }
    }.alignItems(HorizontalAlign.Start).width('100%').bindContextMenu(this.replyMenu(), ResponseType.LongPress)
  }
}
