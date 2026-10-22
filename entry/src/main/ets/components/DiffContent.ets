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
        Text(this.diff.path || '文件修改').fontSize(this.diff.path ? 10 : 12.5).fontFamily(this.diff.path ? 'monospace' : 'sans-serif').fontColor(C.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Button('复制 Diff').id('diff-copy-' + this.diff.path).fontSize(11).fontColor(C.secondary).height(28).buttonStyle(ButtonStyleMode.TEXTUAL)
          .accessibilityText('复制 Diff 内容')
          .responseRegion({ x: 0, y: -6, width: '100%', height: 40 })
          .onClick(() => { this.onCopy(this.diff.patch); })
      }.width('100%').margin({ bottom: 10 })
      ForEach(this.lines.slice(0, this.count), (line: DiffLine) => {
        Row({ space: 6 }) {
          Text(line.oldLine).width(32).fontSize(10).fontFamily('monospace').fontColor(C.muted).textAlign(TextAlign.End).maxLines(1).maxFontScale(1.2)
          Text(line.newLine).width(32).fontSize(10).fontFamily('monospace').fontColor(C.muted).textAlign(TextAlign.End).maxLines(1).maxFontScale(1.2)
          Text(line.text || ' ').fontFamily('monospace').fontSize(11.5).lineHeight(19).fontColor(line.kind === 'remove' ? C.removed_text : line.kind === 'add' ? C.added_text : C.secondary)
            .layoutWeight(1).wordBreak(WordBreak.BREAK_WORD).copyOption(CopyOptions.InApp)
        }.alignItems(VerticalAlign.Top).width('100%').padding(3).backgroundColor(line.kind === 'add' ? C.added : line.kind === 'remove' ? C.removed : C.surface)
      }, (line: DiffLine) => line.id)
      if (this.count < this.lines.length) {
        Button('继续显示 ' + Math.min(120, this.lines.length - this.count) + ' 行（' + this.count + '/' + this.lines.length + '）').id('diff-more-' + this.diff.path).margin({ top: 8 }).fontSize(12).height(32).backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8).fontColor(C.text)
          .constraintSize({ maxWidth: '100%' })
          .accessibilityText('继续查看 Diff')
          .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
          .onClick(() => { this.count += 120; })
      }
      if (this.count > 120) {
        Button('收起修改').id('diff-collapse-' + this.diff.path).margin({ top: 8 }).fontSize(12).height(32).backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8).fontColor(C.text)
          .constraintSize({ maxWidth: '100%' })
          .accessibilityText('收起 Diff')
          .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
          .onClick(() => { this.count = 120; })
      }
      if (this.diff.patch.split('\n', 1501).length > 1500) { Text('仅预览前 1500 行，可复制 Diff 查看完整内容。').fontSize(11).fontColor(C.muted).width('100%').wordBreak(WordBreak.BREAK_WORD) }
    }.padding(14).backgroundColor(C.surface).border({ width: 1, color: C.separator }).borderRadius(12).width('100%')
  }
}
