import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { photoAccessHelper } from '@kit.MediaLibraryKit';
import { image } from '@kit.ImageKit';
import { util } from '@kit.ArkTS';
import { Attachment, ATTACHMENT_LIMIT, attachmentMime } from '../domain/Attachments';

export class AttachmentPicker {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async select(photos: boolean, count: number): Promise<Attachment[]> {
    if (count <= 0) { throw new Error('一次最多添加 4 个附件'); }
    try {
    const uris = photos ? (await new photoAccessHelper.PhotoViewPicker().select({ MIMEType: photoAccessHelper.PhotoViewMIMETypes.IMAGE_TYPE, maxSelectNumber: count })).photoUris :
      await new picker.DocumentViewPicker(this.context).select({ maxSelectNumber: count });
    const result: Attachment[] = [];
    for (const uri of uris.slice(0, count)) { result.push(await this.read(uri, '', photos)); }
    return result;
    } catch (_) { throw new Error('无法打开文件选择器，请稍后重试'); }
  }
  async read(uri: string, id: string = '', photo: boolean = false): Promise<Attachment> {
    let name = '附件';
    try { name = decodeURIComponent(uri.split('/').pop() || '附件').replace(/[\x00-\x1f]/g, '').slice(0, 160); } catch (_) {}
    const item: Attachment = { id: id || 'att_' + Date.now().toString(36) + Math.random().toString(36).slice(2), name: name, mime: '', data: '', size: 0, uri: uri };
    let file: fileIo.File | undefined = undefined;
    try {
      if (!uri.startsWith('file://')) { throw new Error('请选择本机可读取的文件'); }
      item.mime = photo ? 'image/jpeg' : attachmentMime(name);
      file = await fileIo.open(uri, fileIo.OpenMode.READ_ONLY);
      const stat = await fileIo.stat(file.fd);
      if (stat.size <= 0) { throw new Error('文件为空，无法添加'); }
      if (item.mime.startsWith('image/')) {
        if (stat.size > 20971520) { throw new Error('原图不能超过 20 MB，请先缩小图片'); }
        const bytes = await this.compress(file.fd);
        item.mime = 'image/jpeg'; item.name = name.replace(/\.[^.]+$/, '') + '.jpg'; item.size = bytes.byteLength;
        item.data = new util.Base64Helper().encodeToStringSync(new Uint8Array(bytes));
      } else {
        if (stat.size > ATTACHMENT_LIMIT) { throw new Error('单个文件不能超过 1 MB'); }
        const buffer = new ArrayBuffer(stat.size); let offset = 0;
        while (offset < stat.size) {
          const remaining = new ArrayBuffer(stat.size - offset);
          const length = await fileIo.read(file.fd, remaining, { length: remaining.byteLength });
          if (length <= 0) { throw new Error('文件读取不完整，请重试'); }
          new Uint8Array(buffer).set(new Uint8Array(remaining, 0, length), offset); offset += length;
        }
        if (item.mime === 'text/plain') {
          const text = new util.TextDecoder('utf-8', { fatal: true }).decodeToString(new Uint8Array(buffer));
          if (text.indexOf('\u0000') >= 0) { throw new Error('请选择 UTF-8 文本文件，暂不支持二进制或 UTF-16 文件'); }
        }
        if (item.mime === 'application/pdf' && new Uint8Array(buffer).slice(0, 5).join(',') !== '37,80,68,70,45') { throw new Error('文件内容不是有效的 PDF'); }
        item.size = buffer.byteLength; item.data = new util.Base64Helper().encodeToStringSync(new Uint8Array(buffer));
      }
      if (item.size > ATTACHMENT_LIMIT) { throw new Error('附件压缩后仍超过 1 MB，请先缩小文件'); }
    } catch (e) { item.data = ''; item.size = 0; item.error = (e as Error).message || '无法读取附件，请重试或重新选择'; }
    finally { if (file) { await fileIo.close(file).catch(() => {}); } }
    return item;
  }
  async save(item: Attachment): Promise<boolean> {
    let file: fileIo.File | undefined = undefined;
    try {
      if (!item.data) { throw new Error('附件内容尚未载入'); }
      const targets = await new picker.DocumentViewPicker(this.context).save({ newFileNames: [item.name.replace(/[\\/:*?"<>|]/g, '_')] });
      if (!targets.length) { return false; }
      file = await fileIo.open(targets[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      const bytes = new util.Base64Helper().decodeSync(item.data); let offset = 0;
      while (offset < bytes.byteLength) {
        const part = bytes.slice(offset); const count = await fileIo.write(file.fd, part.buffer, { length: part.byteLength });
        if (count <= 0) { throw new Error('文件写入不完整，请重试'); } offset += count;
      }
      await fileIo.fsync(file.fd); return true;
    } catch (_) { throw new Error('文件未保存，请重试'); }
    finally { if (file) { await fileIo.close(file).catch(() => {}); } }
  }
  private async compress(fd: number): Promise<ArrayBuffer> {
    const source = image.createImageSource(fd); const packer = image.createImagePacker(); let pixels: image.PixelMap | undefined = undefined;
    try {
      const info = await source.getImageInfo();
      if (info.size.width * info.size.height > 60000000) { throw new Error('图片尺寸过大，请先缩小图片'); }
      const scale = Math.min(1, 1536 / Math.max(info.size.width, info.size.height));
      pixels = await source.createPixelMap({ desiredSize: { width: Math.max(1, Math.round(info.size.width * scale)), height: Math.max(1, Math.round(info.size.height * scale)) } });
      return await packer.packToData(pixels, { format: 'image/jpeg', quality: 78 });
    } catch (e) { throw new Error((e as Error).message || '图片压缩失败，请重新选择'); }
    finally { if (pixels) { await pixels.release().catch(() => {}); } await source.release().catch(() => {}); await packer.release().catch(() => {}); }
  }
}
