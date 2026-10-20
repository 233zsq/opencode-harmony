import { util } from '@kit.ArkTS';
import { Attachment, attachmentUrl, attachmentSize } from '../domain/Attachments';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct AttachmentPreview {
  @Prop item: Attachment = { id: '', name: '', mime: '', data: '', size: 0 };
  @Prop saving: boolean = false;
  onSave: (item: Attachment) => void = (): void => {};
  onCopy: (text: string) => void = (): void => {};
  private text(): string {
    try { return new util.TextDecoder('utf-8').decodeToString(new util.Base64Helper().decodeSync(this.item.data)); }
    catch (_) { return '暂时无法预览文本'; }
  }
  build() {
    Scroll() {
      Column({ space: 12 }) {
        Text(this.item.name).maxLines(2).wordBreak(WordBreak.BREAK_ALL).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).padding({ right: 38 }).width('100%')
        Text(this.item.mime + ' · ' + attachmentSize(this.item.size)).fontSize(10).fontFamily('monospace').fontColor(C.muted).letterSpacing(0.3).maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.item.data) { Button(this.saving ? '正在保存…' : '保存到文件', { type: ButtonType.Normal }).id('attachment-save')
          .constraintSize({ minHeight: 32 }).fontSize(12).backgroundColor(Color.Transparent).fontColor(C.text)
          .border({ width: 1, color: C.separator }).borderRadius(8).padding({ left: 14, right: 14 })
          .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
          .accessibilityText('保存附件到文件').enabled(!this.saving)
          .onClick(() => { this.onSave(this.item); }) }
        if (this.item.mime.startsWith('image/') && this.item.data) { Image(attachmentUrl(this.item)).id('attachment-preview-image').width('100%').height(380)
          .objectFit(ImageFit.Contain).borderRadius(10).border({ width: 1, color: C.separator }).backgroundColor(C.field)
          .accessibilityText('附件图片预览') }
        else if (this.item.mime === 'text/plain' && this.item.data) {
          Button('复制完整文件', { type: ButtonType.Normal }).id('attachment-copy').constraintSize({ minHeight: 32 }).fontSize(12)
            .backgroundColor(Color.Transparent).fontColor(C.text).border({ width: 1, color: C.separator }).borderRadius(8)
            .padding({ left: 14, right: 14 }).responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
            .accessibilityText('复制完整文件内容').onClick(() => { this.onCopy(this.text()); })
          Text(this.text().slice(0, 32000)).id('attachment-preview-text').fontSize(11.5).fontFamily('monospace').lineHeight(19)
            .wordBreak(WordBreak.BREAK_ALL).fontColor(C.code_text).padding(12).backgroundColor(C.code_bg).borderRadius(8).copyOption(CopyOptions.InApp).width('100%')
          if (this.item.size > 32000) { Text('仅预览前 32000 字符，可复制完整文件。').fontSize(11).fontColor(C.muted) }
        } else { Text(this.item.error || 'PDF 已添加，发送时交给支持 PDF 的模型处理；此处仅显示文件信息。').fontSize(12.5).lineHeight(19).fontColor(C.secondary) }
      }.padding({ left: 20, right: 20, top: 8, bottom: 20 }).width('100%')
    }.id('attachment-preview').width('100%').height('100%').align(Alignment.TopStart).backgroundColor(Color.Transparent)
  }
}
