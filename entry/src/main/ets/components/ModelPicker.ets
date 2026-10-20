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
      Text('选择模型').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).padding({ right: 38 }).width('100%')
      TextInput({ placeholder: '搜索模型名称、渠道或模型 ID', text: this.query }).id('model-search').maxLength(120).constraintSize({ minHeight: 40 }).fontSize(13)
        .backgroundColor(C.field).borderRadius(8).placeholderColor(C.muted).accessibilityText('搜索模型')
        .enabled(!this.busy).onChange((value: string) => { this.query = value; this.limit = 40; })
      if (this.error) { Text(this.error).id('model-switch-error').fontSize(12.5).fontColor(C.danger).width('100%') }
      if (this.busy) { Text('正在切换模型…').fontSize(11).fontColor(C.muted).width('100%') }
      List({ space: 0 }) {
        ForEach(matchingModels(this.models, this.query, this.current).slice(0, this.limit), (model: ModelItem) => {
          ListItem() {
            Row({ space: 10 }) {
              Row().width(2.5).height(30).borderRadius(2).backgroundColor(model.id === this.current ? C.accent : Color.Transparent)
              Column({ space: 3 }) {
                Text(model.label).fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(model.id).fontSize(10).fontFamily('monospace').fontColor(C.muted).letterSpacing(0.3).maxLines(2)
                  .wordBreak(WordBreak.BREAK_ALL).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(modelInputs(model)).fontSize(12.5).fontColor(C.secondary).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (model.id === this.current) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(14).fontColor([C.accent]).accessibilityLevel('no') }
            }.id('model-option-' + model.id).padding({ left: 10, right: 10, top: 10, bottom: 10 }).width('100%')
              .constraintSize({ minHeight: 44 })
              .backgroundColor(model.id === this.current ? C.field : Color.Transparent)
              .border({ width: { bottom: 1 }, color: C.separator })
              .accessibilityChecked(model.id === this.current)
              .accessibilityDescription(model.id === this.current ? '当前已选模型' : '')
              .enabled(!this.busy).onClick(() => { this.onSelect(model.id); })
          }
        }, (model: ModelItem) => model.id + model.label + String(model.id === this.current) + JSON.stringify(model.input || []))
        if (!matchingModels(this.models, this.query).length) {
          ListItem() { Text('没有找到匹配模型，可更换关键词或到“模型与接入”添加。').id('model-no-results').fontSize(12.5).fontColor(C.secondary).padding(16).width('100%') }
        }
      }.id('model-options').layoutWeight(1).width('100%').scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        Text('已显示 ' + Math.min(this.limit, matchingModels(this.models, this.query).length) + '/' + matchingModels(this.models, this.query).length).id('model-result-count')
          .fontSize(11).fontColor(C.muted).maxLines(1).layoutWeight(1)
        if (this.limit < matchingModels(this.models, this.query).length) { Button('显示更多', { type: ButtonType.Normal }).id('model-more').constraintSize({ minHeight: 28 }).fontSize(11)
          .backgroundColor(Color.Transparent).fontColor(C.text).border({ width: 1, color: C.separator }).borderRadius(8)
          .padding({ left: 12, right: 12 }).responseRegion({ x: 0, y: -6, width: '100%', height: 40 })
          .accessibilityText('显示更多模型').enabled(!this.busy).onClick(() => { this.limit += 40; }) }
      }.width('100%')
      Button('模型与接入', { type: ButtonType.Normal }).id('model-manage').constraintSize({ minHeight: 32 }).width('100%').fontSize(12)
        .backgroundColor(Color.Transparent).fontColor(C.text).border({ width: 1, color: C.separator }).borderRadius(8)
        .responseRegion({ x: 0, y: -4, width: '100%', height: 40 })
        .accessibilityText('打开模型与接入设置')
        .enabled(!this.busy).onClick(() => { this.onManage(); })
    }.id('model-picker').padding({ left: 20, right: 20, top: 8, bottom: 18 }).width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
