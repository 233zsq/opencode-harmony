import { AppStore } from '../presentation/AppStore';
import { MessageBookmark, BookmarkFile, findBookmarks } from '../domain/MessageBookmarks';
import { MarkdownText } from './MarkdownText';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
@Component
export struct MessageBookmarksPanel {
  @ObjectLink store: AppStore;
  @Link selectedID: string;
  @State query: string = '';
  onContext: (item: MessageBookmark) => void = (): void => {};
  onCopy: (text: string) => void = (): void => {};
  onLink: (url: string) => void = (): void => {};
  private selected(): MessageBookmark | undefined { return this.store.bookmarks.find((item: MessageBookmark): boolean => item.id === this.selectedID); }
  private remove(item: MessageBookmark): void {
    this.getUIContext().showAlertDialog({ title: '取消收藏', message: '移除这份本机收藏？原会话不受影响。', primaryButton: { value: '保留', action: (): void => {} },
      secondaryButton: { value: '取消收藏', action: (): void => { this.store.removeMessageBookmark(item.id).then((removed: boolean): void => { if (removed && this.selectedID === item.id) { this.selectedID = ''; } }); } } });
  }
  @Builder detail(item: MessageBookmark) {
    Scroll() {
      Column({ space: 16 }) {
        Text(item.sessionTitle || '未命名会话').fontSize(16).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text((item.role === 'user' ? '我的消息' : '助手回复') + ' · 收藏于 ' + new Date(item.savedAt).toLocaleString('zh-CN', { hour12: false })).fontSize(12).fontColor(C.secondary).width('100%')
        if (item.text) { MarkdownText({ content: item.text, onCopy: this.onCopy, onOpenLink: this.onLink }) }
        ForEach(item.files, (file: BookmarkFile, index: number) => { Text('附件 · ' + file.name).fontSize(14).fontColor(C.secondary).width('100%') }, (file: BookmarkFile, index: number) => String(index) + file.name + file.mime)
        Row({ space: 12 }) {
          if (item.text) { Button('复制正文').id('bookmark-copy').fontSize(14).height(44).layoutWeight(1).backgroundColor(C.field).fontColor(C.text).onClick(() => { this.onCopy(item.text); }) }
          Button('查看原会话').id('bookmark-context').fontSize(14).height(44).layoutWeight(1).backgroundColor(C.field).fontColor(C.text)
            .enabled(this.store.canSendMessages() && !this.store.busy && !this.store.targetBusy).onClick(() => { this.onContext(item); })
        }.width('100%')
        Button('取消收藏').id('bookmark-remove').fontSize(14).height(44).backgroundColor(Color.Transparent).fontColor(C.danger).enabled(!this.store.bookmarkSaving).onClick(() => { this.remove(item); })
        Text('这是收藏时的正文快照。附件仅保存名称，不会自动下载文件；思考与工具日志仍在原会话中。').fontSize(12).lineHeight(18).fontColor(C.secondary).width('100%')
      }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
    }.id('bookmark-detail').layoutWeight(1).width('100%').align(Alignment.TopStart)
  }
  build() {
    Column({ space: 12 }) {
      if (this.store.bookmarkError) { Text(this.store.bookmarkError).id('bookmark-error').fontSize(13).fontColor(C.danger).padding({ left: 20, right: 20 }).width('100%') }
      if (this.selected()) { this.detail(this.selected()!) }
      else {
        TextInput({ text: this.query, placeholder: '搜索正文、会话或附件名称' }).id('bookmark-search').height(44).fontSize(15).placeholderFont({ size: 15 }).maxLength(120)
          .backgroundColor(Color.Transparent).backgroundEffect({ radius: 24, saturation: 1.1, color: C.glass_fill }).border({ width: 0.5, color: C.glass_stroke }).borderRadius(14)
          .margin({ left: 20, right: 20 }).onChange((value: string) => { this.query = value; })
        Row() {
          Text(findBookmarks(this.store.bookmarks, this.query).length + ' 条收藏 · 当前服务器账号').fontSize(12).fontColor(C.secondary).layoutWeight(1)
          Button(this.store.bookmarksBusy ? '正在读取…' : '重新读取').id('bookmark-refresh').fontSize(14).height(40).backgroundColor(Color.Transparent).fontColor(C.text)
            .enabled(!this.store.bookmarksBusy && !this.store.bookmarkSaving).onClick(() => { this.store.refreshBookmarks(); })
        }.padding({ left: 20, right: 20 }).width('100%')
        List({ space: 10 }) {
          ForEach(findBookmarks(this.store.bookmarks, this.query), (item: MessageBookmark, index: number) => {
            ListItem() { Button({ type: ButtonType.Normal }) {
              Column({ space: 8 }) {
                Text(item.sessionTitle || '未命名会话').fontSize(13).fontColor(C.secondary).maxLines(1).width('100%').textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(item.text || item.files.map((file: BookmarkFile): string => file.name).join(' · ')).fontSize(15).lineHeight(23).fontColor(C.text).maxLines(4).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              }.padding(16).width('100%').alignItems(HorizontalAlign.Start)
            }.id('bookmark-item-' + index).width('100%').backgroundColor(Color.Transparent).border({ width: 0.5, color: C.glass_stroke }).borderRadius(18).onClick(() => { this.selectedID = item.id; }) }
          }, (item: MessageBookmark): string => item.id)
          if (this.store.bookmarksReady && !findBookmarks(this.store.bookmarks, this.query).length) {
            ListItem() { Text(this.query.trim() ? '没有匹配的收藏' : '在消息旁点“收藏”，把值得留存的内容保存到这里。').id('bookmark-empty').fontSize(14).lineHeight(22).fontColor(C.secondary).padding(20) }
          }
        }.layoutWeight(1).width('100%').padding({ left: 20, right: 20 })
        Text('最多 100 条，本机加密保存。清理缓存或移除连接会保留收藏，重新添加相同地址与账号后可查看；可在详情中取消收藏。').fontSize(12).lineHeight(18).fontColor(C.secondary).padding({ left: 20, right: 20, bottom: 16 }).width('100%')
      }
    }.id('message-bookmarks-panel').padding({ top: 12 }).width('100%').height('100%')
  }
}
