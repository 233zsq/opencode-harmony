import { pasteboard } from '@kit.BasicServicesKit';

export async function copyText(text: string): Promise<void> {
  if (!text) { return; }
  try { await pasteboard.getSystemPasteboard().setData(pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, text)); } catch (e) { throw e as Error; }
}
