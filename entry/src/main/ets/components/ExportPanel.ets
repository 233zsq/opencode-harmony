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
    Column({ space: 12 }) {
      Text('导出当前会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).padding({ right: 38 }).width('100%')
      Text('导出截至启动时最后一条消息的对话，生成中的内容以读取时为准。附件仅列文件信息；思考记录与内部消息不导出。')
        .fontSize(12.5).lineHeight(19).fontColor(C.secondary).width('100%')
      Row({ space: 3 }) {
        Button('Markdown', { type: ButtonType.Normal }).id('export-markdown').layoutWeight(1).constraintSize({ minHeight: 32 }).fontSize(12)
          .fontColor(this.format === 'markdown' ? C.text : C.secondary).fontWeight(this.format === 'markdown' ? FontWeight.Medium : FontWeight.Normal)
          .backgroundColor(this.format === 'markdown' ? C.surface : Color.Transparent)
          .border({ width: 1, color: this.format === 'markdown' ? C.separator : Color.Transparent }).borderRadius(8)
          .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
          .accessibilityChecked(this.format === 'markdown').accessibilityText('导出格式 Markdown')
          .enabled(!this.busy && !this.saving).onClick(() => { this.format = 'markdown'; })
        Button('纯文本', { type: ButtonType.Normal }).id('export-text').layoutWeight(1).constraintSize({ minHeight: 32 }).fontSize(12)
          .fontColor(this.format === 'text' ? C.text : C.secondary).fontWeight(this.format === 'text' ? FontWeight.Medium : FontWeight.Normal)
          .backgroundColor(this.format === 'text' ? C.surface : Color.Transparent)
          .border({ width: 1, color: this.format === 'text' ? C.separator : Color.Transparent }).borderRadius(8)
          .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
          .accessibilityChecked(this.format === 'text').accessibilityText('导出格式 纯文本')
          .enabled(!this.busy && !this.saving).onClick(() => { this.format = 'text'; })
      }.width('100%').padding(3).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(9)
      Row({ space: 8 }) {
        Checkbox().id('export-tools').select(this.tools).selectedColor(C.accent).width(22).height(22)
          .responseRegion({ x: -9, y: -9, width: 40, height: 40 }).accessibilityText('包含工具参数和输出')
          .enabled(!this.busy && !this.saving).onChange((value: boolean) => { this.tools = value; })
        Text('包含工具参数和输出（可能含敏感内容）').fontSize(12.5).lineHeight(19).fontColor(C.secondary).layoutWeight(1)
          .constraintSize({ minHeight: 40 })
          .onClick(() => { if (!this.busy && !this.saving) { this.tools = !this.tools; } })
      }.width('100%')
      if (this.busy) { Text('已读取 ' + this.count + ' 条对话，正在继续…').id('export-progress').fontSize(11).fontColor(C.muted).width('100%') }
      if (this.error) { Text(this.error).id('export-error').fontSize(12.5).fontColor(C.danger).width('100%') }
      if (this.notice) { Text(this.notice).id('export-notice').fontSize(11).lineHeight(17).fontColor(C.secondary).width('100%') }
      Text('单次最多 10000 条对话、8 MB；达到上限会提示未完成。读取完成后选择保存位置。').fontSize(11).lineHeight(17).fontColor(C.muted).width('100%')
      Button(this.busy ? '正在读取历史…' : this.saving ? '正在保存文件…' : '导出并保存', { type: ButtonType.Normal }).id('export-start')
        .constraintSize({ minHeight: 36 }).width('100%').fontSize(12.5).fontWeight(FontWeight.Medium).backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(9)
        .responseRegion({ x: 0, y: -2, width: '100%', height: 40 })
        .enabled(!this.busy && !this.saving).onClick(() => { this.onExport(this.format, this.tools); })
      if (this.busy) { Button('取消导出', { type: ButtonType.Normal }).id('export-cancel').constraintSize({ minHeight: 32 }).width('100%').fontSize(12)
        .backgroundColor(Color.Transparent).fontColor(C.danger).border({ width: 1, color: C.separator }).borderRadius(8)
        .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
        .accessibilityText('取消导出')
        .onClick(() => { this.onCancel(); }) }
    }.id('export-panel').padding({ left: 20, right: 20, top: 8, bottom: 20 }).width('100%').backgroundColor(Color.Transparent)
  }
}
