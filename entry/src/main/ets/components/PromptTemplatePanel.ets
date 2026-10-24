import { PromptTemplateStore } from '../presentation/PromptTemplateStore';
import { PromptTemplate, findPromptTemplates } from '../domain/PromptTemplates';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct PromptTemplatePanel {
  @ObjectLink library: PromptTemplateStore;
  @Prop canInsert: boolean = false;
  @State query: string = '';
  onInsert: (text: string) => void = (): void => {};
  onCancel: () => void = (): void => {};
  private confirmDelete(): void {
    const id = this.library.editID;
    this.getUIContext().showAlertDialog({ title: '删除提示词', message: '从本机永久删除这条提示词？已插入会话的文字仍会保留。',
      primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '删除', action: (): void => { this.library.remove(id); } } });
  }
  build() {
    Column({ space: 12 }) {
      if (this.library.editing) {
        TextInput({ text: this.library.title, placeholder: '名称，例如：检查代码' }).id('prompt-template-title').fontSize(15).placeholderFont({ size: 15 })
          .height(44).maxLength(60).backgroundColor(C.field).borderRadius(14).enabled(!this.library.saving)
          .onChange((value: string) => { this.library.title = value; })
        TextArea({ text: this.library.text, placeholder: '写下希望重复使用的任务描述…' }).id('prompt-template-text').fontSize(15).placeholderFont({ size: 15 })
          .layoutWeight(1).maxLength(20000).backgroundColor(C.field).borderRadius(16).padding(14).enabled(!this.library.saving)
          .onChange((value: string) => { this.library.text = value; })
        Text(this.library.text.length + ' / 20000 字符').fontSize(12).fontColor(C.secondary).width('100%')
        if (this.library.error) { Text(this.library.error).id('prompt-template-editor-error').fontSize(13).fontColor(C.danger).width('100%') }
        Row({ space: 12 }) {
          Button('取消').id('prompt-template-cancel').height(44).fontSize(15).layoutWeight(1).backgroundColor(C.field).fontColor(C.text)
            .enabled(!this.library.saving).onClick(() => { this.onCancel(); })
          Button(this.library.saving ? '正在保存…' : '保存').id('prompt-template-save').height(44).fontSize(15).layoutWeight(1).backgroundColor(C.text).fontColor(C.page)
            .enabled(!this.library.saving).onClick(() => { this.library.save(); })
        }.width('100%')
        if (this.library.editID) {
          Button('删除这条提示词').id('prompt-template-delete').height(44).fontSize(14).backgroundColor(Color.Transparent).fontColor(C.danger)
            .enabled(!this.library.saving).onClick(() => { this.confirmDelete(); })
        }
      } else {
        Row({ space: 12 }) {
          TextInput({ text: this.query, placeholder: '搜索名称或内容' }).id('prompt-template-search').fontSize(15).placeholderFont({ size: 15 }).maxLength(120).height(44)
            .layoutWeight(1).backgroundColor(Color.Transparent).backgroundEffect({ radius: 24, saturation: 1.1, color: C.glass_fill })
            .border({ width: 0.5, color: C.glass_stroke }).borderRadius(14).onChange((value: string) => { this.query = value; })
          Button('新建').id('prompt-template-add').height(44).fontSize(15).backgroundColor(C.field).fontColor(C.text)
            .enabled(this.library.ready && !this.library.loading).onClick(() => { this.library.edit(); })
        }.width('100%')
        if (this.library.error) { Text(this.library.error).id('prompt-template-error').fontSize(13).fontColor(C.danger).width('100%') }
        if (!this.library.ready) {
          Button(this.library.loading ? '正在读取…' : '重新读取').id('prompt-template-retry').height(44).fontSize(15).backgroundColor(C.field).fontColor(C.text)
            .enabled(!this.library.loading).onClick(() => { this.library.load(); })
        }
        List({ space: 10 }) {
          ForEach(findPromptTemplates(this.library.items, this.query), (item: PromptTemplate) => {
            ListItem() {
              Column({ space: 6 }) {
                Row({ space: 10 }) {
                  Text(item.title).fontSize(16).fontWeight(FontWeight.Medium).fontColor(C.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
                  Button('编辑').id('prompt-template-edit-' + item.id).height(40).fontSize(14).backgroundColor(Color.Transparent).fontColor(C.secondary)
                    .onClick(() => { this.library.edit(item); })
                }.width('100%')
                Text(item.text).fontSize(14).lineHeight(21).fontColor(C.secondary).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
                Button('插入输入栏').id('prompt-template-insert-' + item.id).height(40).fontSize(14).backgroundColor(C.field).fontColor(C.text).width('100%')
                  .enabled(this.canInsert).onClick(() => { this.onInsert(item.text); })
              }.alignItems(HorizontalAlign.Start).padding(14).width('100%').border({ width: 0.5, color: C.glass_stroke }).borderRadius(18)
            }
          }, (item: PromptTemplate) => item.id + String(item.updated))
          if (this.library.ready && !findPromptTemplates(this.library.items, this.query).length) {
            ListItem() { Text(this.query.trim() ? '没有匹配的提示词' : '把常用的任务描述保存到这里，下次直接插入。').id('prompt-template-empty').fontSize(14).lineHeight(22).fontColor(C.secondary).padding(16) }
          }
        }.width('100%').layoutWeight(1)
        Text(this.library.items.length + ' / 50 条 · 本机加密保存，不会自动发送。清理会话缓存不会删除提示词。' + (this.canInsert ? '' : '打开会话后即可插入。'))
          .fontSize(12).lineHeight(18).fontColor(C.secondary).width('100%')
      }
    }.id('prompt-template-panel').padding(20).width('100%').height('100%').backgroundColor(Color.Transparent)
  }
}
