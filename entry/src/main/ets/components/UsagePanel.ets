import { SessionUsage, emptyUsage, tokenLabel, costLabel, CompactRecord, compactLabel } from '../domain/SessionUsage';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
struct UsageMetric {
  @Prop label: string = '';
  @Prop value: string = '';
  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(12.5).fontColor(C.secondary).layoutWeight(1)
      Text(this.value).fontSize(12.5).fontFamily('monospace').fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(1)
    }.width('100%').constraintSize({ minHeight: 36 }).padding({ top: 5, bottom: 5 })
  }
}
@Component
export struct UsagePanel {
  @Prop usage: SessionUsage = emptyUsage();
  @Prop contextLimit: number = -1;
  @Prop model: string = '';
  @Prop loading: boolean = false;
  @Prop busy: boolean = false;
  @Prop blocked: boolean = false;
  @Prop error: string = '';
  @Prop compact: CompactRecord = { id: '', state: '', error: '' };
  onRefresh: () => void = (): void => {};
  onCompact: () => void = (): void => {};
  build() {
    Scroll() {
      Column({ space: 12 }) {
        Column({ space: 4 }) {
          Text('上下文与用量').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).padding({ right: 38 }).width('100%')
          Text(this.model || '使用服务器默认模型').fontSize(11).fontColor(C.muted)
            .maxLines(1).padding({ right: 38 }).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)
        Column() {
          UsageMetric({ label: '模型上下文上限', value: tokenLabel(this.contextLimit) })
          Divider().strokeWidth(1).color(C.separator)
          UsageMetric({ label: '输入 Token', value: tokenLabel(this.usage.input) })
          Divider().strokeWidth(1).color(C.separator)
          UsageMetric({ label: '输出 Token', value: tokenLabel(this.usage.output) })
          Divider().strokeWidth(1).color(C.separator)
          UsageMetric({ label: '推理 Token', value: tokenLabel(this.usage.reasoning) })
          Divider().strokeWidth(1).color(C.separator)
          UsageMetric({ label: '缓存读取 Token', value: tokenLabel(this.usage.cacheRead) })
          Divider().strokeWidth(1).color(C.separator)
          UsageMetric({ label: '缓存写入 Token', value: tokenLabel(this.usage.cacheWrite) })
          Divider().strokeWidth(1).color(C.separator)
          UsageMetric({ label: '服务端记录费用（USD）', value: costLabel(this.usage.cost) })
        }.id('usage-metrics').width('100%').border({ width: { top: 1, bottom: 1 }, color: C.separator })
        Text('用量和费用以服务器返回为准；未提供的项目不会按 0 计算。会话用量不能直接换算成当前上下文占用率。')
          .fontSize(11).lineHeight(17).fontColor(C.muted).width('100%')
        if (this.error) { Text(this.error).id('usage-error').fontSize(12.5).fontColor(C.danger).width('100%') }
        Divider().strokeWidth(1).color(C.separator)
        Column({ space: 6 }) {
          Text('整理长会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          Text('压缩会调用当前模型，可能产生费用。服务器会生成摘要供后续对话使用。').fontSize(12.5).lineHeight(19).fontColor(C.secondary).width('100%')
          Text(compactLabel(this.compact.state)).id('compact-state').fontSize(11).fontColor(C.secondary).width('100%')
          if (this.compact.error) { Text(this.compact.error).id('compact-error').fontSize(12.5).fontColor(C.danger).width('100%') }
          if (this.blocked) { Text('请先结束任务并处理待回答、审批或发送确认。').id('compact-blocked').fontSize(12.5).fontColor(C.warning).width('100%') }
        }.width('100%').alignItems(HorizontalAlign.Start)
        Row({ space: 8 }) {
          Button(this.loading ? '正在读取…' : '重新读取', { type: ButtonType.Normal }).id('usage-refresh')
            .layoutWeight(1).constraintSize({ minHeight: 40 }).fontSize(12).fontColor(C.text)
            .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
            .accessibilityText('重新读取用量与上下文')
            .enabled(!this.loading && !this.busy).onClick(() => { this.onRefresh(); })
          Button(this.busy ? '正在提交…' : this.compact.state === 'unknown' ? '核对并重试压缩' : '压缩上下文', { type: ButtonType.Normal })
            .id('compact-start').layoutWeight(1).constraintSize({ minHeight: 40 }).fontSize(12.5).fontWeight(FontWeight.Medium)
            .backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(9)
            .enabled(!this.loading && !this.busy && !this.blocked && ['queued', 'running', 'submitting'].indexOf(this.compact.state) < 0)
            .onClick(() => { this.onCompact(); })
        }.width('100%').margin({ top: 4 })
      }.padding({ left: 20, right: 20, top: 8, bottom: 24 }).width('100%')
    }.id('usage-panel').width('100%').height('100%').align(Alignment.TopStart).backgroundColor(Color.Transparent)
  }
}
