import { common } from '@kit.AbilityKit';
import { picker, fileIo } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';

export class DocumentSaver {
  private context: common.UIAbilityContext;
  constructor(context: common.UIAbilityContext) { this.context = context; }
  async saveText(name: string, text: string, valid: () => boolean = (): boolean => true): Promise<boolean> {
    return this.save(name, new util.TextEncoder().encodeInto(text), valid);
  }
  async save(name: string, bytes: Uint8Array, valid: () => boolean = (): boolean => true): Promise<boolean> {
    let file: fileIo.File | undefined = undefined;
    try {
      if (!bytes.byteLength) { throw new Error('文件内容为空'); }
      if (!valid()) { return false; }
      const safe = name.replace(/[\\/:*?"<>|\x00-\x1f]/g, '_').slice(0, 160) || '会话导出.txt';
      const targets = await new picker.DocumentViewPicker(this.context).save({ newFileNames: [safe] });
      if (!targets.length || !valid()) { return false; }
      file = await fileIo.open(targets[0], fileIo.OpenMode.READ_WRITE | fileIo.OpenMode.CREATE | fileIo.OpenMode.TRUNC);
      let offset = 0;
      while (offset < bytes.byteLength) {
        const part = bytes.slice(offset, Math.min(bytes.byteLength, offset + 65536));
        const count = await fileIo.write(file.fd, part.buffer, { length: part.byteLength });
        if (count <= 0 || count > part.byteLength) { throw new Error('文件写入不完整'); } offset += count;
      }
      await fileIo.fsync(file.fd); return true;
    } catch (_) { throw new Error('文件未保存，请重试'); }
    finally { if (file) { await fileIo.close(file).catch(() => {}); } }
  }
}
