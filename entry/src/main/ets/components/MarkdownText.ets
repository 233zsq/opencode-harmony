import { MarkdownBlock, parseMarkdown, InlinePart, inlineMarkdown } from '../domain/Core';

@Component
export struct MarkdownText {
  @Prop @Watch('refresh') content: string = '';
  @State blocks: MarkdownBlock[] = [];
  onOpenLink: (url: string) => void = (): void => {};
  aboutToAppear(): void { this.refresh(); }
  private refresh(): void { this.blocks = parseMarkdown(this.content); }
  build() {
    Column({ space: 6 }) {
      ForEach(this.blocks, (block: MarkdownBlock) => {
        if (block.kind === 'code') {
          Column({ space: 6 }) {
            Text(block.language || 'CODE').fontSize(10).fontColor('#7D8B9C')
            Text(block.text || ' ').fontSize(12).fontFamily('monospace').fontColor('#D9E5ED')
              .copyOption(CopyOptions.InApp).width('100%')
          }.alignItems(HorizontalAlign.Start).padding(12).backgroundColor('#142128').borderRadius(10).width('100%')
        } else if (block.kind === 'table') {
          Scroll() {
            Column({ space: 0 }) {
              ForEach(block.rows || [], (row: string[], index: number) => {
                Row({ space: 0 }) {
                  ForEach(row, (cell: string, column: number) => {
                    Text(cell).fontSize(12).fontWeight(index === 0 ? FontWeight.Bold : FontWeight.Normal)
                      .fontColor('#35513C').width(150).padding(10).border({ width: 0.5, color: '#DDE6D8' })
                  }, (cell: string, column: number) => String(column))
                }.backgroundColor(index === 0 ? '#E7EFE2' : '#F7F9F3')
              }, (row: string[], index: number) => String(index))
            }
          }.scrollable(ScrollDirection.Horizontal).width('100%')
        } else if (block.kind === 'rule') {
          Divider().color('#DFE5E1').margin({ top: 6, bottom: 6 })
        } else {
          Text() {
            ForEach(inlineMarkdown(block.text), (part: InlinePart) => {
              Span(part.text).fontWeight(part.kind === 'bold' ? FontWeight.Bold : FontWeight.Normal)
                .fontFamily(part.kind === 'code' ? 'monospace' : 'sans-serif')
                .fontColor(part.kind === 'link' ? '#2C7952' : '#24392F')
                .onClick(() => { if (part.kind === 'link' && part.url) { this.onOpenLink(part.url); } })
            }, (part: InlinePart) => part.id + part.text)
          }.fontSize(block.kind === 'heading' ? 18 : 14)
            .fontWeight(block.kind === 'heading' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(block.kind === 'quote' ? '#65776D' : '#24392F')
            .lineHeight(22).width('100%').copyOption(CopyOptions.InApp)
        }
      }, (block: MarkdownBlock) => block.id + block.kind + block.text + (block.kind === 'table' ? JSON.stringify(block.rows) : ''))
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
