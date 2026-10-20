import { DiffItem, DiffLine, parseDiff } from '../domain/Core';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct DiffContent {
  @Prop @Watch('refresh') diff: DiffItem = { path: '', patch: '' };
  @State lines: DiffLine[] = [];
  @State count: number = 120;
  onCopy: (text: string) => void = (): void => {};
  aboutToAppear(): void { this.refresh(); }
  private refresh(): void { this.lines = parseDiff(this.diff.patch, 1500); this.count = 120; }
  build() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text(this.diff.path || '文件修改').fontSize(12.5).fontWeight(FontWeight.Bold).fontFamily('monospace').fontColor(C.text).layoutWeight(1)
        Button('复制 Diff').id('diff-copy-' + this.diff.path).fontSize(10.5).fontFamily('monospace').fontColor(C.secondary).height(26).buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.onCopy(this.diff.patch); })
      }.width('100%').margin({ bottom: 10 })
      ForEach(this.lines.slice(0, this.count), (line: DiffLine) => {
        Row({ space: 6 }) {
          Text(line.oldLine).width(26).fontSize(9).fontFamily('monospace').fontColor(C.muted).textAlign(TextAlign.End)
          Text(line.newLine).width(26).fontSize(9).fontFamily('monospace').fontColor(C.muted).textAlign(TextAlign.End)
          Text(line.text || ' ').fontFamily('monospace').fontSize(10.5).fontColor(line.kind === 'remove' ? C.removed_text : line.kind === 'add' ? C.added_text : C.secondary)
            .layoutWeight(1).copyOption(CopyOptions.InApp)
        }.alignItems(VerticalAlign.Top).width('100%').padding(3).backgroundColor(line.kind === 'add' ? C.added : line.kind === 'remove' ? C.removed : C.surface)
      }, (line: DiffLine) => line.id)
      if (this.count < this.lines.length) {
        Button('继续显示 ' + Math.min(120, this.lines.length - this.count) + ' 行（' + this.count + '/' + this.lines.length + '）').id('diff-more-' + this.diff.path).margin({ top: 8 }).fontSize(10.5).fontFamily('monospace').height(32).backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8).fontColor(C.text).onClick(() => { this.count += 120; })
      }
      if (this.count > 120) { Button('收起修改').id('diff-collapse-' + this.diff.path).margin({ top: 8 }).fontSize(10.5).fontFamily('monospace').height(32).backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8).fontColor(C.text).onClick(() => { this.count = 120; }) }
      if (this.diff.patch.split('\n', 1501).length > 1500) { Text('仅预览前 1500 行，可复制 Diff 查看完整内容。').fontSize(10.5).fontFamily('monospace').fontColor(C.muted) }
    }.padding(14).backgroundColor(C.surface).border({ width: 1, color: C.separator }).borderRadius(12).width('100%')
  }
}
