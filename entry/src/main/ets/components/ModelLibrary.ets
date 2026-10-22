import { ModelItem } from '../domain/Core';
import { ModelPreferences, emptyModelPreferences, matchingModels } from '../domain/ModelSelection';
import { HarmonyColors as C } from '../presentation/HarmonyColors';

@Component
export struct ModelLibrary {
  @Prop models: ModelItem[] = [];
  @Prop preferences: ModelPreferences = emptyModelPreferences();
  @Prop favoritesOnly: boolean = false;
  @Prop busy: boolean = false;
  @Prop error: string = '';
  @State query: string = '';
  @State limit: number = 40;
  onEnable: (id: string, enabled: boolean) => void = (): void => {};
  onFavorite: (id: string, favorite: boolean) => void = (): void => {};
  onManageAll: () => void = (): void => {};
  onRefresh: () => void = (): void => {};
  private matches(): ModelItem[] {
    const missing: ModelItem[] = this.preferences.enabled.filter((id: string) => !this.models.some((model: ModelItem) => model.id === id)).map((id: string): ModelItem => ({ id: id, label: id, available: false }));
    return matchingModels(this.models.concat(missing), this.query).filter((model: ModelItem) => !this.favoritesOnly || this.preferences.favorites.indexOf(model.id) >= 0); }
  build() {
    Column({ space: 12 }) {
      Text(this.favoritesOnly ? '喜爱模型固定显示在对话的快捷选择栏。添加喜爱会同时启用模型。' : '仅启用的模型会出现在全部模型中；这是当前服务器在本机的显示设置。')
        .fontSize(13).lineHeight(20).fontColor(C.secondary).width('100%')
      TextInput({ placeholder: '搜索模型名称或 ID', text: this.query }).id('library-search').height(40).fontSize(14).backgroundColor(C.field).borderRadius(14)
        .placeholderColor(C.muted).onChange((value: string) => { this.query = value; this.limit = 40; })
      if (this.error) { Text(this.error).id('library-error').fontSize(13).fontColor(C.warning).width('100%') }
      Row() {
        Text('已启用 ' + this.preferences.enabled.length + ' · 喜爱 ' + this.preferences.favorites.length).id('library-count').fontSize(12).fontColor(C.secondary).layoutWeight(1)
        Button('刷新', { type: ButtonType.Normal }).id('library-refresh').height(36).fontSize(13).fontColor(C.accent).backgroundColor(Color.Transparent)
          .enabled(!this.busy).onClick(() => { this.onRefresh(); })
      }.width('100%')
      if (this.favoritesOnly) { Button('添加喜爱模型', { type: ButtonType.Normal }).id('library-add-favorites').height(36).fontSize(13).fontColor(C.accent).backgroundColor(Color.Transparent).onClick(() => { this.onManageAll(); }) }
      List({ space: 6 }) {
        ForEach(this.matches().slice(0, this.limit), (model: ModelItem) => {
          ListItem() {
            Row({ space: 8 }) {
              Column({ space: 4 }) {
                Text(model.label).fontSize(15).fontColor(C.text).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Text(model.id).fontSize(10).fontColor(C.muted).maxLines(2).wordBreak(WordBreak.BREAK_ALL).width('100%')
                if (model.available === false) { Text('服务器当前不可用').fontSize(11).fontColor(C.warning) }
              }.layoutWeight(1).alignItems(HorizontalAlign.Start)
              Button({ type: ButtonType.Circle }) {
                SymbolGlyph(this.preferences.favorites.indexOf(model.id) >= 0 ? $r('sys.symbol.star_fill') : $r('sys.symbol.star')).fontSize(19)
                  .fontColor([this.preferences.favorites.indexOf(model.id) >= 0 ? C.accent : C.muted])
              }.id('favorite-model-' + model.id).width(40).height(40).padding(0).backgroundColor(Color.Transparent)
                .accessibilityText(this.preferences.favorites.indexOf(model.id) >= 0 ? '取消喜爱 ' + model.label : '喜爱 ' + model.label)
                .accessibilityChecked(this.preferences.favorites.indexOf(model.id) >= 0).enabled(!this.busy && (model.available !== false || this.preferences.favorites.indexOf(model.id) >= 0))
                .onClick(() => { this.onFavorite(model.id, this.preferences.favorites.indexOf(model.id) < 0); })
              Checkbox().id('enable-model-' + model.id).select(this.preferences.enabled.indexOf(model.id) >= 0).shape(CheckBoxShape.ROUNDED_SQUARE)
                .width(22).height(22).margin({ left: 5, right: 5 }).selectedColor(C.accent).enabled(!this.busy && (model.available !== false || this.preferences.enabled.indexOf(model.id) >= 0))
                .accessibilityText('启用 ' + model.label).onChange((enabled: boolean) => { this.onEnable(model.id, enabled); })
            }.id('library-model-' + model.id).width('100%').constraintSize({ minHeight: 68 }).padding(12).backgroundColor(C.surface).borderRadius(16)
          }
        }, (model: ModelItem) => model.id + String(this.preferences.enabled.indexOf(model.id) >= 0) + String(this.preferences.favorites.indexOf(model.id) >= 0))
        if (!this.matches().length) { ListItem() { Text(this.favoritesOnly ? '还没有喜爱模型，可在启用模型页面点击星标添加。' : '没有匹配的模型，请连接项目或刷新目录。').id('library-empty').fontSize(14).fontColor(C.secondary).padding(16) } }
        if (this.limit < this.matches().length) { ListItem() { Button('显示更多').id('library-more').height(40).width('100%').onClick(() => { this.limit += 40; }) } }
      }.id('model-library-list').layoutWeight(1).width('100%').scrollBar(BarState.Auto)
    }.id('model-library').padding({ left: 18, right: 18, top: 12, bottom: 20 }).height('100%').width('100%')
  }
}
