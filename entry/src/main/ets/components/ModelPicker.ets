import { ModelItem } from '../domain/Core';
import { matchingModels, modelInputs } from '../domain/ModelSelection';
import { HarmonyColors as C } from '../presentation/HarmonyColors';

@Component
export struct ModelPicker {
  @Prop models: ModelItem[] = [];
  @Prop current: string = '';
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @State query: string = '';
  @State limit: number = 40;
  onSelect: (id: string) => void = (): void => {};
  onManage: () => void = (): void => {};
  aboutToAppear(): void { this.query = ''; this.limit = 40; }
  build() {
    Column({ space: 12 }) {
      Text('选择模型').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      TextInput({ placeholder: '搜索模型名称、渠道或模型 ID', text: this.query }).id('model-search').maxLength(120).height(42).fontSize(14).backgroundColor(C.field)
        .enabled(!this.busy).onChange((value: string) => { this.query = value; this.limit = 40; })
      if (this.error) { Text(this.error).id('model-switch-error').fontSize(12).fontColor(C.danger).width('100%') }
      if (this.busy) { Text('正在切换模型…').fontSize(12).fontColor(C.secondary).width('100%') }
      List({ space: 8 }) {
        ForEach(matchingModels(this.models, this.query, this.current).slice(0, this.limit), (model: ModelItem) => {
          ListItem() {
            Row({ space: 10 }) {
              Column({ space: 5 }) {
                Text(model.label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(2).width('100%')
                Text(model.id).fontSize(11).fontColor(C.secondary).maxLines(2).width('100%')
                Text(modelInputs(model)).fontSize(10).fontColor(C.muted).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (model.id === this.current) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([C.accent]) }
            }.id('model-option-' + model.id).padding(13).width('100%').backgroundColor(model.id === this.current ? C.accent_soft : C.field).borderRadius(12)
              .enabled(!this.busy).onClick(() => { this.onSelect(model.id); })
          }
        }, (model: ModelItem) => model.id + model.label + String(model.id === this.current) + JSON.stringify(model.input || []))
        if (!matchingModels(this.models, this.query).length) {
          ListItem() { Text('没有找到匹配模型，可更换关键词或到“模型与接入”添加。').id('model-no-results').fontSize(13).fontColor(C.secondary).padding(16).width('100%') }
        }
      }.id('model-options').layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        Text('已显示 ' + Math.min(this.limit, matchingModels(this.models, this.query).length) + '/' + matchingModels(this.models, this.query).length).id('model-result-count').fontSize(11).fontColor(C.muted).layoutWeight(1)
        if (this.limit < matchingModels(this.models, this.query).length) { Button('显示更多').id('model-more').height(30).fontSize(12).buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.busy).onClick(() => { this.limit += 40; }) }
      }.width('100%')
      Button('模型与接入').id('model-manage').height(38).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.busy).onClick(() => { this.onManage(); })
    }.id('model-picker').padding({ left: 20, right: 20, top: 56, bottom: 18 }).width('100%').height('100%').backgroundColor(C.surface)
  }
}
