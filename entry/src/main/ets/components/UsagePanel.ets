import { SessionUsage, emptyUsage, tokenLabel, costLabel, CompactRecord, compactLabel } from '../domain/SessionUsage';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
struct UsageMetric {
  @Prop label: string = '';
  @Prop value: string = '';
  build() {
    Row({ space: 12 }) {
      Text(this.label).fontSize(14).fontColor(C.secondary).layoutWeight(1)
      Text(this.value).fontSize(15).fontColor(C.text)
    }.width('100%').padding({ top: 8, bottom: 8 })
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
        Text('上下文与用量').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text(this.model || '使用服务器默认模型').fontSize(13).fontColor(C.secondary).width('100%')
        Column() {
          UsageMetric({ label: '模型上下文上限', value: tokenLabel(this.contextLimit) })
          Divider().color(C.separator)
          UsageMetric({ label: '输入 Token', value: tokenLabel(this.usage.input) })
          UsageMetric({ label: '输出 Token', value: tokenLabel(this.usage.output) })
          UsageMetric({ label: '推理 Token', value: tokenLabel(this.usage.reasoning) })
          UsageMetric({ label: '缓存读取 Token', value: tokenLabel(this.usage.cacheRead) })
          UsageMetric({ label: '缓存写入 Token', value: tokenLabel(this.usage.cacheWrite) })
          UsageMetric({ label: '服务端记录费用（USD）', value: costLabel(this.usage.cost) })
        }.id('usage-metrics').padding(14).width('100%').backgroundColor(C.field).borderRadius(12)
        Text('用量和费用以服务器返回为准；未提供的项目不会按 0 计算。会话用量不能直接换算成当前上下文占用率。').fontSize(12).fontColor(C.secondary).width('100%')
        if (this.error) { Text(this.error).id('usage-error').fontSize(12).fontColor(C.danger).width('100%') }
        Button(this.loading ? '正在读取…' : '重新读取').id('usage-refresh').height(36).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.loading && !this.busy).onClick(() => { this.onRefresh(); })
        Divider().color(C.separator)
        Text('整理长会话').fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text('压缩会调用当前模型，可能产生费用。服务器会生成摘要供后续对话使用。').fontSize(13).fontColor(C.secondary).width('100%')
        Text(compactLabel(this.compact.state)).id('compact-state').fontSize(13).fontColor(C.secondary).width('100%')
        if (this.compact.error) { Text(this.compact.error).id('compact-error').fontSize(12).fontColor(C.danger).width('100%') }
        if (this.blocked) { Text('请先结束任务并处理待回答、审批或发送确认。').id('compact-blocked').fontSize(12).fontColor(C.warning).width('100%') }
        Button(this.busy ? '正在提交…' : this.compact.state === 'unknown' ? '核对并重试压缩' : '压缩上下文').id('compact-start').height(42).width('100%').backgroundColor(C.accent).fontColor(C.on_accent)
          .enabled(!this.loading && !this.busy && !this.blocked && ['queued', 'running', 'submitting'].indexOf(this.compact.state) < 0).onClick(() => { this.onCompact(); })
      }.padding({ left: 20, right: 20, top: 56, bottom: 24 }).width('100%')
    }.id('usage-panel').width('100%').height('100%').align(Alignment.TopStart).backgroundColor(C.surface)
  }
}
