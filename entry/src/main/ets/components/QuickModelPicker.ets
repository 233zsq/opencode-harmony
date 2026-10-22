import { ModelItem } from '../domain/Core';
import { ModelPreferences, emptyModelPreferences, enabledModels, favoriteModels, recentModels, matchingModels, modelInputs, variantLabel } from '../domain/ModelSelection';
import { HarmonyColors as C } from '../presentation/HarmonyColors';

@Component
export struct QuickModelPicker {
  @Prop models: ModelItem[] = [];
  @Prop preferences: ModelPreferences = emptyModelPreferences();
  @Prop current: string = '';
  @Prop variant: string = '';
  @Prop busy: boolean = false;
  @Prop uncertain: boolean = false;
  onRefresh: () => void = (): void => {};
  @Prop error: string = '';
  @Prop maxHeight: number = 560;
  @State expanded: string = '';
  @State query: string = '';
  @State limit: number = 30;
  onSelect: (id: string) => void = (): void => {};
  onVariant: (id: string) => Promise<boolean> = (): Promise<boolean> => Promise.resolve(false);
  onManage: () => void = (): void => {};
  private favorites(): ModelItem[] { return favoriteModels(this.models, this.preferences); }
  private history(): ModelItem[] { return recentModels(this.models, this.preferences); }
  private matches(): ModelItem[] { return matchingModels(enabledModels(this.models, this.preferences), this.query, this.current); }
  private variants(): string[] { return this.models.find((model: ModelItem) => model.id === this.current)?.variants || []; }
  private expansionHeight(): number { return Math.min(210, Math.max(118, this.maxHeight - 370)); }
  private favoriteHeight(): number { return this.favorites().length ? Math.min(this.favorites().length * 54, this.expanded ? 54 : 162) : 42; }
  private bodyHeight(): number {
    const footer = this.history().length ? 70 + this.history().length * 48 : 104;
    return Math.min(this.favoriteHeight() + 90 + (this.expanded ? this.expansionHeight() + 6 : 0), Math.max(88, this.maxHeight - footer - 20));
  }
  private toggle(kind: string): void { this.expanded = this.expanded === kind ? '' : kind; if (kind === 'all') { this.query = ''; this.limit = 30; } }
  @Builder
  modelRow(model: ModelItem, prefix: string, compact: boolean = false) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 8 }) {
        Column({ space: 3 }) {
          Text(model.label).fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(prefix === 'inline-model-option-' ? model.id : model.id.split('/')[0] + ' · ' + modelInputs(model))
            .fontSize(11).fontWeight(FontWeight.Normal).fontColor(C.secondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        if (model.id === this.current) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(15).fontColor([prefix === 'inline-model-option-' ? C.text : C.accent]).accessibilityLevel('no') }
      }.width('100%')
    }.id(prefix + model.id).width('100%').height(compact ? 48 : 54).padding({ left: 10, right: 10 })
      .backgroundColor(Color.Transparent).borderRadius(12).enabled(!this.busy)
      .accessibilityChecked(model.id === this.current).accessibilityDescription(model.id).onClick(() => { this.onSelect(model.id); })
  }
  @Builder
  allModels() {
    Column({ space: 5 }) {
      TextInput({ placeholder: '搜索已启用模型', text: this.query }).id('inline-model-search').height(34).fontSize(12).fontWeight(FontWeight.Normal)
        .padding({ left: 10, right: 10 }).backgroundColor(C.field).caretColor(C.text).borderRadius(12).placeholderColor(C.muted).enabled(!this.busy)
        .onChange((value: string) => { this.query = value; this.limit = 30; })
      List({ space: 0 }) {
        ForEach(this.matches().slice(0, this.limit), (model: ModelItem) => { ListItem() { this.modelRow(model, 'inline-model-option-', true) } }, (model: ModelItem) => model.id + String(model.id === this.current))
        if (this.matches().length > this.limit) {
          ListItem() { Button('显示更多', { type: ButtonType.Normal }).id('inline-model-more').height(40).width('100%').fontSize(14).fontWeight(FontWeight.Medium)
            .fontColor(C.text).backgroundColor(Color.Transparent).enabled(!this.busy).onClick(() => { this.limit += 30; }) }
        }
        if (!this.matches().length) {
          ListItem() { Text(this.preferences.enabled.length ? '没有匹配的已启用模型' : '先到模型与接入启用模型').id('inline-model-no-results')
            .fontSize(12).fontWeight(FontWeight.Normal).fontColor(C.secondary).padding(10).width('100%') }
        }
      }.id('inline-model-options').width('100%').layoutWeight(1).scrollBar(BarState.Auto)
      Text(String(this.matches().length) + ' 个已启用模型').id('inline-model-result-count').fontSize(11).fontWeight(FontWeight.Normal).fontColor(C.muted).width('100%').padding({ left: 4 })
    }.id('model-inline-all').padding(7).height(this.expansionHeight()).width('100%')
      .backgroundColor(Color.Transparent).border({ width: 0.5, color: C.glass_stroke }).borderRadius(18)
  }
  @Builder
  thinkingOptions() {
    List({ space: 0 }) {
      ForEach([''].concat(this.variants()), (id: string) => {
        ListItem() {
          Button({ type: ButtonType.Normal }) {
            Row({ space: 8 }) {
              Column({ space: 2 }) {
                Text(variantLabel(id)).fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(1).width('100%')
                Text(id || '使用服务器默认设置').fontSize(11).fontWeight(FontWeight.Normal).fontColor(C.secondary).maxLines(1).width('100%')
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              if (id === this.variant) { SymbolGlyph($r('sys.symbol.checkmark')).fontSize(15).fontColor([C.text]) }
            }.width('100%')
          }.id('model-variant-' + (id || 'default')).width('100%').height(48).padding({ left: 12, right: 12 }).borderRadius(12)
            .backgroundColor(Color.Transparent).enabled(!this.busy).accessibilityChecked(id === this.variant)
            .onClick(async (): Promise<void> => { if (await this.onVariant(id)) { this.expanded = ''; } })
        }
      }, (id: string) => id + String(id === this.variant))
    }.id('model-thinking-options').width('100%').height(Math.min(this.expansionHeight(), (this.variants().length + 1) * 48 + 12))
      .padding(6).backgroundColor(Color.Transparent)
      .border({ width: 0.5, color: C.glass_stroke }).borderRadius(18).scrollBar(BarState.Auto)
  }
  build() {
    Column({ space: 0 }) {
      if (this.error) { Text(this.error).id('quick-model-error').fontSize(12).fontWeight(FontWeight.Normal).lineHeight(17).fontColor(C.danger).maxLines(2).padding(8).width('100%') }
      if (this.uncertain) { Button('核对模型设置', { type: ButtonType.Normal }).id('model-refresh').height(34).width('100%').fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.accent).backgroundColor(Color.Transparent).enabled(!this.busy).onClick(() => { this.onRefresh(); }) }
      Scroll() {
        Column({ space: 2 }) {
          if (this.favorites().length) {
            List({ space: 0 }) {
              ForEach(this.favorites(), (model: ModelItem) => { ListItem() { this.modelRow(model, 'quick-model-option-') } }, (model: ModelItem) => model.id + String(model.id === this.current))
            }.id('quick-model-options').width('100%').height(this.favoriteHeight()).scrollBar(BarState.Auto)
          } else { Text('设置喜爱模型，便于快速切换').id('model-favorites-empty').fontSize(12).fontWeight(FontWeight.Normal).fontColor(C.secondary).height(42).padding({ left: 10 }).width('100%') }
          Divider().color(C.separator).margin({ left: 10, right: 10, top: 2, bottom: 2 })
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              Text('全部模型').fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1).textAlign(TextAlign.Start)
              Text(String(enabledModels(this.models, this.preferences).length)).fontSize(11).fontWeight(FontWeight.Normal).fontColor(C.secondary)
              SymbolGlyph(this.expanded === 'all' ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down')).fontSize(11).fontColor([C.secondary])
            }.width('100%')
          }.id('model-show-all').height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(Color.Transparent).borderRadius(12)
            .enabled(!this.busy).accessibilityDescription(this.expanded === 'all' ? '已展开' : '已收起').onClick(() => { this.toggle('all'); })
          if (this.expanded === 'all') { this.allModels() }
          Button({ type: ButtonType.Normal }) {
            Row({ space: 6 }) {
              Text('思考程度').fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1).textAlign(TextAlign.Start)
              Text(this.variants().length ? variantLabel(this.variant) : '模型默认').fontSize(14).fontWeight(FontWeight.Normal).fontColor(C.secondary).maxLines(1)
              SymbolGlyph(this.expanded === 'thinking' ? $r('sys.symbol.chevron_up') : $r('sys.symbol.chevron_down')).fontSize(11).fontColor([C.secondary])
            }.width('100%')
          }.id('model-thinking').height(40).width('100%').padding({ left: 10, right: 10 }).backgroundColor(Color.Transparent).borderRadius(12)
            .enabled(!this.busy && this.variants().length > 0 && this.preferences.enabled.indexOf(this.current) >= 0)
            .accessibilityDescription(this.variants().length ? '展开服务器提供的思考档位' : '服务器未提供可调整档位').onClick(() => { this.toggle('thinking'); })
          if (this.expanded === 'thinking') { this.thinkingOptions() }
        }.width('100%')
      }.id('model-quick-body').width('100%').height(this.bodyHeight()).scrollBar(BarState.Off).align(Alignment.TopStart)
      Divider().color(C.separator).margin({ left: 10, right: 10, top: 4, bottom: 4 })
      Text('历史模型').id('model-history-title').fontSize(11).fontWeight(FontWeight.Medium).fontColor(C.muted).padding({ left: 10, top: 3, bottom: 3 }).width('100%')
      if (this.history().length) {
        ForEach(this.history(), (model: ModelItem) => { this.modelRow(model, 'recent-model-option-', true) }, (model: ModelItem) => model.id + String(model.id === this.current))
      } else { Text('暂无非喜爱模型的使用记录').id('model-history-empty').fontSize(12).fontWeight(FontWeight.Normal).fontColor(C.secondary).padding({ left: 10, top: 6, bottom: 8 }).width('100%') }
      Button('模型与接入', { type: ButtonType.Normal }).id('quick-model-manage').height(40).width('100%').fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text)
        .backgroundColor(Color.Transparent).borderRadius(12).enabled(!this.busy).onClick(() => { this.onManage(); })
    }.id('model-quick-picker').width('100%').padding(6).backgroundColor(Color.Transparent).borderRadius(22)
  }
}
