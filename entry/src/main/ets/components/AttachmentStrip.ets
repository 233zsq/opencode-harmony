import { Attachment, attachmentUrl, attachmentSize } from '../domain/Attachments';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct AttachmentStrip {
  @Prop items: Attachment[] = [];
  @Prop editable: boolean = false;
  @Prop locked: boolean = false;
  onOpen: (item: Attachment) => void = (): void => {};
  onRemove: (id: string) => void = (): void => {};
  onRetry: (item: Attachment) => void = (): void => {};
  build() {
    Scroll() {
      Row({ space: 8 }) {
        ForEach(this.items, (item: Attachment) => {
          Row({ space: 6 }) {
            Column({ space: 4 }) {
              Row({ space: 6 }) {
                if (item.mime.startsWith('image/') && item.data) { Image(attachmentUrl(item)).width(36).height(36).objectFit(ImageFit.Cover).borderRadius(6) }
                else { SymbolGlyph($r('sys.symbol.doc')).fontSize(22).fontColor([item.error ? C.danger : C.secondary]) }
                Column({ space: 3 }) {
                  Text(item.name).fontSize(12).fontColor(C.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text(item.error || attachmentSize(item.size)).fontSize(10).fontColor(item.error ? C.danger : C.muted).maxLines(2).width('100%')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              }.width('100%')
              if (this.editable && item.error && item.uri) { Button('重试读取').id('attachment-retry-' + item.id).height(26).fontSize(11).buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.locked).onClick(() => { this.onRetry(item); }) }
            }.id('attachment-open-' + item.id).width(148).onClick(() => { this.onOpen(item); })
            if (this.editable) { Button('×', { type: ButtonType.Circle }).id('attachment-remove-' + item.id).accessibilityText('移除 ' + item.name).fontSize(18).width(28).height(28).fontColor(C.secondary).backgroundColor(Color.Transparent).enabled(!this.locked).onClick(() => { this.onRemove(item.id); }) }
          }.padding(8).backgroundColor(C.field).border({ width: 0.5, color: item.error ? C.danger : C.separator }).borderRadius(10)
        }, (item: Attachment) => item.id + item.name + item.mime + (item.fingerprint || '') + item.data.length + (item.error || ''))
      }.padding({ bottom: 4 })
    }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Auto).align(Alignment.TopStart).width('100%')
  }
}
