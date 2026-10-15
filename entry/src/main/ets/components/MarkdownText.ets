import { MarkdownBlock, parseMarkdown, InlinePart, inlineMarkdown } from '../domain/Core';

@Component
export struct MarkdownText {
  @Prop content: string = '';
  build() {
    Column({ space: 6 }) {
      ForEach(parseMarkdown(this.content), (block: MarkdownBlock) => {
        if (block.kind === 'code') {
          Column({ space: 6 }) {
            Text(block.language || 'CODE').fontSize(10).fontColor('#7D8B9C')
            Text(block.text || ' ').fontSize(12).fontFamily('monospace').fontColor('#D9E5ED')
              .copyOption(CopyOptions.InApp).width('100%')
          }.alignItems(HorizontalAlign.Start).padding(12).backgroundColor('#142128').borderRadius(10).width('100%')
        } else if (block.kind === 'rule') {
          Divider().color('#DFE5E1').margin({ top: 6, bottom: 6 })
        } else {
          Text() {
            ForEach(inlineMarkdown(block.text), (part: InlinePart) => {
              Span(part.text).fontWeight(part.kind === 'bold' ? FontWeight.Bold : FontWeight.Normal)
                .fontFamily(part.kind === 'code' ? 'monospace' : 'sans-serif')
                .fontColor(part.kind === 'link' ? '#2C7952' : '#24392F')
            }, (part: InlinePart) => part.id + part.text)
          }.fontSize(block.kind === 'heading' ? 18 : 14)
            .fontWeight(block.kind === 'heading' ? FontWeight.Bold : FontWeight.Normal)
            .fontColor(block.kind === 'quote' ? '#65776D' : '#24392F')
            .lineHeight(22).width('100%').copyOption(CopyOptions.InApp)
        }
      }, (block: MarkdownBlock) => block.id + block.kind + block.text)
    }.alignItems(HorizontalAlign.Start).width('100%')
  }
}
