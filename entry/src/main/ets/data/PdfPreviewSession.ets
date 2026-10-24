import { pdfService } from '@kit.PDFKit';
import { common } from '@kit.AbilityKit';
import { fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { image } from '@kit.ImageKit';
export class PdfPreviewSession {
  count: number = 0;
  private document: pdfService.PdfDocument | undefined = undefined;
  private file: fileIo.File | undefined = undefined;
  private closed: boolean = false;
  private closing: Promise<void> | undefined = undefined;
  private opening: Promise<void> = Promise.resolve();
  open(data: string, context: common.Context): Promise<void> { this.opening = this.prepare(data, context); return this.opening; }
  private async prepare(data: string, context: common.Context): Promise<void> {
    const bytes = new util.Base64Helper().decodeSync(data);
    if (!bytes.byteLength || bytes.byteLength > 1048576 || String.fromCharCode(...bytes.slice(0, 5)) !== '%PDF-') { throw new Error('PDF 超出预览范围或内容无效'); }
    try { this.document = new pdfService.PdfDocument(); } catch (_) { throw new Error('此设备暂不支持 PDF 页预览，可保存到文件后打开'); }
    const path = context.cacheDir + '/opencode-preview-' + util.generateRandomUUID(true) + '.pdf';
    this.file = await fileIo.open(path, fileIo.OpenMode.CREATE | fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.TRUNC);
    // Unlink before writing private bytes. The anonymous file disappears even if the process exits unexpectedly.
    try { await fileIo.unlink(path); } catch (_) { await fileIo.close(this.file); this.file = undefined; throw new Error('无法创建私有 PDF 预览'); }
    let offset = 0;
    while (offset < bytes.byteLength) {
      if (this.closed) { throw new Error('预览已关闭'); }
      const remaining = bytes.slice(offset).buffer; const written = await fileIo.write(this.file.fd, remaining);
      if (written <= 0) { throw new Error('PDF 读取不完整'); } offset += written;
    }
    if (this.closed) { throw new Error('预览已关闭'); }
    if (this.document.loadDocument('/proc/self/fd/' + this.file.fd) !== pdfService.ParseResult.PARSE_SUCCESS) { throw new Error('PDF 无法预览，文件可能已加密或损坏'); }
    this.count = this.document.getPageCount();
    if (!Number.isInteger(this.count) || this.count < 1 || this.count > 2000) { throw new Error('PDF 页数超出预览范围（最多 2000 页）'); }
  }
  render(index: number): image.PixelMap {
    if (this.closed || !this.document || !Number.isInteger(index) || index < 0 || index >= this.count) { throw new Error('PDF 页面不可用'); }
    const page = this.document.getPage(index);
    try {
      const width = page.getWidth(); const height = page.getHeight();
      if (!Number.isFinite(width) || !Number.isFinite(height) || width <= 0 || height <= 0 || width / height > 50 || height / width > 50) { throw new Error('PDF 页面尺寸超出预览范围'); }
      const scale = Math.min(2, 1536 / Math.max(width, height)); const matrix = new pdfService.PdfMatrix();
      matrix.x = 0; matrix.y = 0; matrix.width = width; matrix.height = height; matrix.rotate = 0;
      return page.getAreaPixelMap(matrix, Math.max(1, Math.round(width * scale)), Math.max(1, Math.round(height * scale)), false, true);
    } finally { page.release(); }
  }
  close(): Promise<void> {
    if (!this.closing) { this.closed = true; this.closing = this.dispose(); } return this.closing;
  }
  private async dispose(): Promise<void> { await this.opening.catch((): void => {});
    try { this.document?.releaseDocument(); } catch (_) {} this.document = undefined;
    if (this.file) { await fileIo.close(this.file).catch((): void => {}); this.file = undefined; }
  }
}
