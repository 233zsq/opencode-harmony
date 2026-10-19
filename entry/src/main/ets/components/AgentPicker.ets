import { AgentItem, selectableAgents } from '../domain/Agents';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct AgentPicker {
  @Prop agents: AgentItem[] = [];
  @Prop current: string = '';
  @Prop busy: boolean = false;
  @Prop loading: boolean = false;
  @Prop error: string = '';
  @Prop blocked: string = '';
  @State query: string = '';
  @State limit: number = 40;
  onSelect: (id: string) => void = (): void => {};
  onRefresh: () => void = (): void => {};
  build() {
    Column({ space: 12 }) {
      Text('选择 Agent').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      Text('选择用于后续轮次的 Agent，具体能力和操作权限由服务器定义。').fontSize(12).fontColor(C.secondary).width('100%')
      TextInput({ placeholder: '搜索 Agent 名称或说明', text: this.query }).id('agent-search').height(42).maxLength(120).fontSize(14).backgroundColor(C.field).enabled(!this.busy).onChange((value: string) => { this.query = value; this.limit = 40; })
      if (this.error) { Text(this.error).id('agent-error').fontSize(12).fontColor(C.danger).width('100%') }
      if (this.blocked) { Text(this.blocked).id('agent-blocked').fontSize(12).fontColor(C.secondary).width('100%') }
      if (this.busy || this.loading) { Text(this.busy ? '正在切换并核对…' : '正在读取…').fontSize(12).fontColor(C.secondary).width('100%') }
      List({ space: 8 }) {
        ForEach(selectableAgents(this.agents, this.query).slice(0, this.limit), (agent: AgentItem) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 5 }) {
                Text(agent.name).fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
                if (agent.description) { Text(agent.description).fontSize(12).fontColor(C.secondary).width('100%') }
                Text(agent.id + (agent.model ? ' · ' + agent.model : '')).fontSize(10).fontColor(C.muted).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (agent.id === this.current) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([C.accent]) }
            }.id('agent-option-' + agent.id).padding(13).width('100%').backgroundColor(agent.id === this.current ? C.accent_soft : C.field).borderRadius(12)
              .enabled(!this.busy && !this.loading && !this.blocked).onClick(() => { this.onSelect(agent.id); })
          }
        }, (agent: AgentItem) => agent.id + agent.name + agent.description + agent.model + String(agent.id === this.current))
        if (!selectableAgents(this.agents, this.query).length) { ListItem() { Text('没有可选择的 Agent，请重新读取或更换关键词。').id('agent-empty').fontSize(13).fontColor(C.secondary).padding(14) } }
      }.layoutWeight(1).width('100%')
      if (this.limit < selectableAgents(this.agents, this.query).length) { Button('显示更多').id('agent-more').height(32).fontSize(12).buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.limit += 40; }) }
      Button('重新读取状态').id('agent-refresh').height(38).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.busy && !this.loading).onClick(() => { this.onRefresh(); })
    }.id('agent-picker').padding({ left: 20, right: 20, top: 56, bottom: 18 }).width('100%').height('100%').backgroundColor(C.surface)
  }
}
