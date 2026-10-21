import { ModelItem } from '../domain/Core';
import { modelInputs, quickModels, matchingModels } from '../domain/ModelSelection';
import { HarmonyColors as C } from '../presentation/HarmonyColors';

@Component
export struct QuickModelPicker {
  @Prop models: ModelItem[] = [];
  @Prop current: string = '';
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @Prop listHeight: number = 260;
  onSelect: (id: string) => void = (): void => {};
  onAll: () => void = (): void => {};
  onManage: () => void = (): void => {};
  private provider(model: ModelItem): string {
    const id = model.id.split('/')[0];
    return id === 'opencode' ? 'OpenCode' : id === 'deepseek' ? 'DeepSeek' : id;
  }
  build() {
    Column({ space: 0 }) {
      if (this.error) { Text(this.error).id('quick-model-error').fontSize(12).lineHeight(18).fontColor(C.danger).maxLines(3).padding(12).width('100%') }
      if (this.busy) { Text('正在切换…').fontSize(12).fontColor(C.secondary).padding({ left: 12, top: 8 }).width('100%') }
      List({ space: 0 }) {
        ForEach(quickModels(this.models, this.current), (model: ModelItem) => {
          ListItem() {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 12 }) {
                Column({ space: 5 }) {
                  Text(model.label).fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(2)
                    .lineHeight(20).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                  Text(this.provider(model) + ' · ' + modelInputs(model)).fontSize(12).fontColor(C.secondary)
                    .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                if (model.id === this.current) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(18).fontColor([C.accent]).accessibilityLevel('no') }
              }.width('100%').padding({ left: 14, right: 14, top: 12, bottom: 12 })
            }.id('quick-model-option-' + model.id).width('100%').constraintSize({ minHeight: 70 })
              .backgroundColor(Color.Transparent).borderRadius(12).enabled(!this.busy)
              .accessibilityChecked(model.id === this.current).accessibilityDescription(model.id)
              .onClick(() => { this.onSelect(model.id); })
          }
        }, (model: ModelItem) => model.id + model.label + String(model.id === this.current) + JSON.stringify(model.input || []))
      }.id('quick-model-options').width('100%').height(Math.min(quickModels(this.models, this.current).length * 76, this.listHeight)).scrollBar(BarState.Off)
      Divider().color(C.separator).margin({ left: 14, right: 14, top: 4, bottom: 4 })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          Text('全部模型').fontSize(14).fontColor(C.text).layoutWeight(1)
          Text(String(matchingModels(this.models, '').length)).fontSize(12).fontColor(C.secondary)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([C.secondary])
        }.width('100%').padding({ left: 14, right: 14 })
      }.id('model-show-all').height(44).width('100%').backgroundColor(Color.Transparent).borderRadius(12)
        .enabled(!this.busy).onClick(() => { this.onAll(); })
      Button('模型与接入', { type: ButtonType.Normal }).id('quick-model-manage').height(44).width('100%').fontSize(14).fontColor(C.text)
        .backgroundColor(Color.Transparent).borderRadius(12).enabled(!this.busy).onClick(() => { this.onManage(); })
    }.id('model-quick-picker').width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(C.surface).borderRadius(22)
  }
}
