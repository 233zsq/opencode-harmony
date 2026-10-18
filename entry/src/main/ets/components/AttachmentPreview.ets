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
      Column({ space: 14 }) {
        Text(this.item.name).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).fontSize(18).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text(this.item.mime + ' · ' + attachmentSize(this.item.size)).fontSize(12).fontColor(C.muted).width('100%')
        if (this.item.data) { Button(this.saving ? '正在保存…' : '保存到文件').id('attachment-save').enabled(!this.saving).buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.onSave(this.item); }) }
        if (this.item.mime.startsWith('image/') && this.item.data) { Image(attachmentUrl(this.item)).id('attachment-preview-image').width('100%').height(380).objectFit(ImageFit.Contain) }
        else if (this.item.mime === 'text/plain' && this.item.data) {
          Button('复制完整文件').id('attachment-copy').buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.onCopy(this.text()); })
          Text(this.text().slice(0, 32000)).id('attachment-preview-text').fontSize(12).fontFamily('monospace').lineHeight(20).fontColor(C.text).copyOption(CopyOptions.InApp).width('100%')
          if (this.item.size > 32000) { Text('仅预览前 32000 字符，可复制完整文件。').fontSize(11).fontColor(C.muted) }
        } else { Text(this.item.error || 'PDF 已添加，发送时交给支持 PDF 的模型处理；此处仅显示文件信息。').fontSize(13).fontColor(C.secondary) }
      }.padding({ left: 20, right: 20, top: 56, bottom: 20 }).width('100%')
    }.id('attachment-preview').width('100%').height('100%').align(Alignment.TopStart).backgroundColor(C.surface)
  }
}
