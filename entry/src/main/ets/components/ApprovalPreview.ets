import { ApprovalPreview, ApprovalFile, DiffLine, parseDiff } from '../domain/Core';

@Component
export struct ApprovalPreviewView {
  @Prop preview: ApprovalPreview = { command: '', directory: '', pattern: '', reason: '', source: '', files: [], omittedFiles: 0, incomplete: false, expectsDiff: false };
  @State expanded: string = '';
  onReview: () => void = (): void => {};
  aboutToAppear(): void { this.expanded = this.preview.files[0]?.path || ''; }
  @Builder
  patch(file: ApprovalFile) {
    if (!file.patch) {
      Text('服务端未提供此文件的文本 Diff。').fontSize(11).fontColor('#8A795C').width('100%')
    } else {
      Column({ space: 0 }) {
        ForEach(parseDiff(file.patch), (line: DiffLine) => {
          Row({ space: 5 }) {
            Text(line.oldLine).width(24).fontSize(9).fontColor('#84917F').textAlign(TextAlign.End)
            Text(line.newLine).width(24).fontSize(9).fontColor('#84917F').textAlign(TextAlign.End)
            Text(line.text || ' ').fontFamily('monospace').fontSize(11).layoutWeight(1).copyOption(CopyOptions.InApp)
              .fontColor(line.kind === 'remove' ? '#994F47' : '#31583A')
          }.padding(3).width('100%').alignItems(VerticalAlign.Top)
            .backgroundColor(line.kind === 'add' ? '#E1EEDF' : line.kind === 'remove' ? '#F3E2DC' : '#F4F4EB')
        }, (line: DiffLine) => line.id)
      }.width('100%')
    }
  }
  build() {
    Column({ space: 9 }) {
      Text(this.preview.source).fontSize(11).fontColor('#8A805D').width('100%')
      if (this.preview.reason) { Text(this.preview.reason).fontSize(12).fontColor('#665E43').width('100%') }
      if (this.preview.directory) { Text('目录：' + this.preview.directory).fontSize(12).fontFamily('monospace').fontColor('#665E43').copyOption(CopyOptions.InApp).width('100%') }
      if (this.preview.pattern) { Text('匹配：' + this.preview.pattern).fontSize(12).fontFamily('monospace').fontColor('#665E43').width('100%') }
      if (this.preview.command) {
        Text(this.preview.command).fontFamily('monospace').fontSize(12).fontColor('#ECF0DC').padding(12)
          .backgroundColor('#263D30').borderRadius(8).copyOption(CopyOptions.InApp).width('100%')
      }
      if (this.preview.files.length) { Text('待执行的文件修改').fontSize(13).fontWeight(FontWeight.Medium).fontColor('#5A6343').width('100%') }
      ForEach(this.preview.files, (file: ApprovalFile) => {
        Column({ space: 7 }) {
          Button((this.expanded === file.path ? '▾ ' : '▸ ') + file.path + '  +' + file.additions + ' / −' + file.deletions,
            { type: ButtonType.Normal }).id('approval-file-' + file.path).fontSize(12).width('100%').borderRadius(7)
            .backgroundColor('#ECEBD7').fontColor('#4E6241')
            .onClick(() => { this.expanded = this.expanded === file.path ? '' : file.path; this.onReview(); })
          if (this.expanded === file.path) { this.patch(file) }
        }.width('100%')
      }, (file: ApprovalFile) => file.path)
      if (!this.preview.files.length && this.preview.expectsDiff) { Text('服务端未附文本 Diff，请核对以上操作范围。').fontSize(11).fontColor('#8A795C').width('100%') }
      if (this.preview.incomplete) {
        Text('操作内容过长或无法完整预览，请在桌面核对并处理审批。当前仅支持拒绝。').id('approval-incomplete')
          .fontSize(12).fontColor('#9A5E41').width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start)
  }
}
