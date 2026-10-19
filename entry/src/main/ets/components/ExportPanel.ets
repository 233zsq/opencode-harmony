import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct ExportPanel {
  @Prop busy: boolean = false;
  @Prop saving: boolean = false;
  @Prop count: number = 0;
  @Prop error: string = '';
  @Prop notice: string = '';
  @State format: string = 'markdown';
  @State tools: boolean = false;
  onExport: (format: string, tools: boolean) => void = (): void => {};
  onCancel: () => void = (): void => {};
  build() {
    Column({ space: 14 }) {
      Text('导出当前会话').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      Text('导出截至启动时最后一条消息的对话，生成中的内容以读取时为准。附件仅列文件信息；思考记录与内部消息不导出。').fontSize(13).fontColor(C.secondary).width('100%')
      Row({ space: 8 }) {
        Button('Markdown').id('export-markdown').layoutWeight(1).height(38).fontColor(C.text).backgroundColor(this.format === 'markdown' ? C.accent_soft : C.field).enabled(!this.busy && !this.saving).onClick(() => { this.format = 'markdown'; })
        Button('纯文本').id('export-text').layoutWeight(1).height(38).fontColor(C.text).backgroundColor(this.format === 'text' ? C.accent_soft : C.field).enabled(!this.busy && !this.saving).onClick(() => { this.format = 'text'; })
      }.width('100%')
      Row({ space: 8 }) {
        Checkbox().id('export-tools').select(this.tools).selectedColor(C.accent).width(22).height(22).enabled(!this.busy && !this.saving).onChange((value: boolean) => { this.tools = value; })
        Text('包含工具参数和输出（可能含敏感内容）').fontSize(12).fontColor(C.secondary).layoutWeight(1)
      }.width('100%')
      if (this.busy) { Text('已读取 ' + this.count + ' 条对话，正在继续…').id('export-progress').fontSize(13).fontColor(C.secondary).width('100%') }
      if (this.error) { Text(this.error).id('export-error').fontSize(12).fontColor(C.danger).width('100%') }
      if (this.notice) { Text(this.notice).id('export-notice').fontSize(12).fontColor(C.secondary).width('100%') }
      Text('单次最多 10000 条对话、8 MB；达到上限会提示未完成。读取完成后选择保存位置。').fontSize(11).fontColor(C.muted).width('100%')
      Button(this.busy ? '正在读取历史…' : this.saving ? '正在保存文件…' : '导出并保存').id('export-start').height(42).width('100%').backgroundColor(C.accent).fontColor(C.on_accent).enabled(!this.busy && !this.saving).onClick(() => { this.onExport(this.format, this.tools); })
      if (this.busy) { Button('取消导出').id('export-cancel').height(36).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.onCancel(); }) }
    }.id('export-panel').padding({ left: 20, right: 20, top: 56, bottom: 20 }).width('100%').backgroundColor(C.surface)
  }
}
