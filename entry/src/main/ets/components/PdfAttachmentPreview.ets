import { common } from '@kit.AbilityKit';
import { image } from '@kit.ImageKit';
import { PdfPreviewSession } from '../data/PdfPreviewSession';
import { ZoomableAttachment } from './ZoomableAttachment';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct PdfAttachmentPreview {
  @Prop @Watch('dataChanged') data: string = '';
  private dataChanged(): void { const previous = this.session; this.session = undefined; previous?.close(); const pixels = this.pixels; this.pixels = undefined; pixels?.release(); this.count = 0; this.page = 0; this.error = ''; this.loading = true; this.load(); }
  @State pixels: image.PixelMap | undefined = undefined;
  @State count: number = 0;
  @State page: number = 0;
  @State error: string = '';
  @State loading: boolean = true;
  private session: PdfPreviewSession | undefined = undefined;
  aboutToAppear(): void { this.load(); }
  aboutToDisappear(): void { const session = this.session; this.session = undefined; session?.close(); const pixels = this.pixels; this.pixels = undefined; pixels?.release(); }
  private async load(): Promise<void> {
    if (!canIUse('SystemCapability.OfficeService.PDFService.Core')) { this.loading = false; this.error = '此设备暂不支持 PDF 页预览，可保存到文件后打开'; return; }
    const session = new PdfPreviewSession(); this.session = session;
    try { const context = this.getUIContext().getHostContext() as common.Context; await session.open(this.data, context);
      if (session !== this.session) { return; } this.count = session.count; this.pixels = session.render(0);
    } catch (_) { if (session === this.session) { this.error = 'PDF 无法预览，文件可能已加密、损坏或超出范围；仍可保存到文件'; } await session.close(); }
    finally { if (session === this.session) { this.loading = false; } }
  }
  private async turn(offset: number): Promise<void> {
    const session = this.session; if (!session || this.loading || this.page + offset < 0 || this.page + offset >= this.count) { return; }
    this.loading = true;
    try { const next = session.render(this.page + offset); const old = this.pixels; this.pixels = next; this.page += offset; await old?.release(); }
    catch (_) { this.error = '此页未能预览，可重试或保存到文件'; }
    finally { if (session === this.session) { this.loading = false; } }
  }
  build() {
    Column({ space: 12 }) {
      if (this.pixels) { ForEach([this.page], (page: number) => { ZoomableAttachment({ pixels: this.pixels }) }, (page: number): string => String(page)) }
      if (this.error) { Text(this.error).id('attachment-pdf-error').fontSize(14).lineHeight(22).fontColor(C.secondary).width('100%') }
      if (this.count) {
        Row({ space: 12 }) {
          Button('上一页').id('attachment-pdf-previous').fontSize(14).height(44).backgroundColor(C.field).fontColor(C.text).enabled(!this.loading && this.page > 0).onClick(() => { this.turn(-1); })
          Text((this.page + 1) + ' / ' + this.count).id('attachment-pdf-page').fontSize(14).fontColor(C.text).layoutWeight(1).textAlign(TextAlign.Center)
          Button('下一页').id('attachment-pdf-next').fontSize(14).height(44).backgroundColor(C.field).fontColor(C.text).enabled(!this.loading && this.page + 1 < this.count).onClick(() => { this.turn(1); })
        }.width('100%')
      }
      if (this.loading) { Text('正在读取 PDF…').fontSize(14).fontColor(C.secondary) }
    }.id('attachment-pdf-preview').width('100%')
  }
}
