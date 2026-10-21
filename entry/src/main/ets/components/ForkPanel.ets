import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct ForkPanel {
  @Prop editing: boolean = false;
  @Prop initialText: string = '';
  @Prop source: string = '';
  @Prop hasFiles: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop uncertain: boolean = false;
  @Prop blocked: boolean = false;
  @State text: string = '';
  @State reuseFiles: boolean = true;
  onCreate: (text: string, reuse: boolean) => void = (): void => {};
  onReview: () => void = (): void => {};
  onChecked: () => void = (): void => {};
  aboutToAppear(): void { this.text = this.initialText; }
  build() {
    Scroll() {
      Column({ space: 20 }) {
        Text(this.editing ? '编辑并分叉' : '创建会话分支').fontSize(19).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text(this.source ? '复制所选消息之前的对话到新会话。' : '复制当前会话已有的对话到新会话。').fontSize(15).lineHeight(23).fontColor(C.secondary).width('100%')
        if (this.source) { Text(this.source).maxLines(3).fontSize(15).lineHeight(23).fontColor(C.secondary)
          .padding(10).width('100%').backgroundColor(C.field).borderRadius(14) }
        Text('分叉沿用当前工作区文件状态。创建分支不会自动发送消息或调用模型。').fontSize(13).lineHeight(21).fontColor(C.muted).width('100%')
        if (this.editing) {
          TextArea({ text: this.text, placeholder: '修改这条问题，稍后在新会话确认发送' }).id('fork-text').fontSize(16).maxLength(20000).constraintSize({ minHeight: 180 })
            .backgroundColor(C.field).borderRadius(14).placeholderColor(C.muted).accessibilityText('编辑分叉的问题')
            .enabled(!this.busy).onChange((value: string) => { this.text = value; })
          if (this.hasFiles) { Row({ space: 8 }) { Checkbox().id('fork-reuse-files').select(this.reuseFiles).selectedColor(C.accent).width(22).height(22)
            .responseRegion({ x: -9, y: -9, width: 40, height: 40 }).accessibilityText('沿用原消息附件')
            .enabled(!this.busy).onChange((value: boolean) => { this.reuseFiles = value; })
            Text('沿用原消息附件').fontSize(15).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 48 })
              .onClick(() => { if (!this.busy) { this.reuseFiles = !this.reuseFiles; } }) }.width('100%') }
          Text('编辑后的问题会放入新会话草稿，由你确认发送。').fontSize(13).lineHeight(21).fontColor(C.muted).width('100%')
        }
        if (this.blocked) { Text('请先结束任务、确认发送结果并处理问题或审批。').id('fork-blocked').fontSize(15).fontColor(C.warning).width('100%') }
        if (this.error) { Text(this.error).id('fork-error').fontSize(15).fontColor(C.danger).width('100%') }
        Button(this.busy ? '正在创建…' : this.editing ? '创建分支并填写草稿' : '创建分支', { type: ButtonType.Normal }).id('fork-create')
          .constraintSize({ minHeight: 48 }).width('100%').fontSize(15).fontWeight(FontWeight.Medium).backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(14)

          .enabled(!this.busy && !this.blocked && !this.uncertain).onClick(() => { this.onCreate(this.text, this.reuseFiles); })
        if (this.uncertain) {
          Button('检查会话列表', { type: ButtonType.Normal }).id('fork-review').constraintSize({ minHeight: 44 }).width('100%').fontSize(15)
            .backgroundColor(Color.Transparent).fontColor(C.text).border({ width: 1, color: C.separator }).borderRadius(14)
            .accessibilityDescription('打开会话列表核对是否已创建分支')
            .onClick(() => { this.onReview(); })
          Button('已检查，允许重新创建', { type: ButtonType.Normal }).id('fork-checked').constraintSize({ minHeight: 44 }).width('100%').fontSize(15)
            .backgroundColor(Color.Transparent).fontColor(C.text).border({ width: 1, color: C.separator }).borderRadius(14)
            .onClick(() => { this.onChecked(); })
        }
      }.padding({ left: 20, right: 20, top: 8, bottom: 24 }).width('100%')
    }.id('fork-panel').width('100%').height('100%').align(Alignment.TopStart).backgroundColor(Color.Transparent)
  }
}
