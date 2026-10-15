import { common } from '@kit.AbilityKit';
import { AppStore } from '../presentation/AppStore';
import { ConversationMessage } from '../components/ConversationMessage';
import { ApprovalPreviewView } from '../components/ApprovalPreview';
import { ProviderSettings } from '../components/ProviderSettings';
import { FormFieldsView } from '../components/FormFieldsView';
import { MessageDataSource } from '../presentation/MessageDataSource';
import { ServerConfig, ProjectItem, SessionItem, ChatMessage, ToolItem, Interaction, FormField, Choice,
  ModelItem, FileItem, DiffItem, DiffLine, parseDiff, visibleFormFields, messageKey, interactionKey, reasoningInProgress, toolStatus } from '../domain/Core';

@Entry
@Component
struct Index {
  @State @Watch('storeChanged') store: AppStore = new AppStore();
  @StorageLink('appForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State follow: boolean = true;
  @State sidebarOpen: boolean = false;
  @State wide: boolean = false;
  @State viewportWidth: number = 400;
  @State sessionSearch: string = '';
  @State menuOpen: boolean = false;
  @State toolSheetOpen: boolean = false;
  @State selectedTool: ToolItem = { id: '', name: '', status: '', input: '', output: '' };
  @State reasoningOpen: string[] = [];
  @State reasoningClosed: string[] = [];
  private activeReasoning: string[] = [];
  private viewSession: string = '';
  private scroller: Scroller = new Scroller();
  private messageSource: MessageDataSource = new MessageDataSource();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) { this.store.init(context as common.Context); }
  }
  aboutToDisappear(): void { this.store.setActive(false); }
  private storeChanged(): void {
    const session = this.store.connected + '/' + this.store.sessionID;
    if (session !== this.viewSession) { this.viewSession = session; this.sessionSearch = ''; this.reasoningOpen = []; this.reasoningClosed = []; this.activeReasoning = []; this.toolSheetOpen = false; this.follow = true; }
    const active = this.store.messages.filter((m: ChatMessage) => reasoningInProgress(m)).map((m: ChatMessage) => m.id);
    const ended = this.activeReasoning.filter((id: string) => active.indexOf(id) < 0);
    const ids = this.store.messages.map((m: ChatMessage) => m.id);
    this.reasoningOpen = this.reasoningOpen.filter((id: string) => ended.indexOf(id) < 0 && ids.indexOf(id) >= 0);
    this.reasoningClosed = this.reasoningClosed.filter((id: string) => active.indexOf(id) >= 0);
    this.activeReasoning = active;
    if (this.toolSheetOpen) { const tool = this.store.messages.flatMap((m: ChatMessage) => m.tools).find((t: ToolItem) => t.id === this.selectedTool.id); if (tool) { this.selectedTool = tool; } }
    this.messageSource.update(this.store.messages);
    if (this.follow && this.store.pane === 'chat') { setTimeout(() => { if (this.follow) { this.scroller.scrollEdge(Edge.Bottom); } }, 40); }
  }
  private foregroundChanged(): void { this.store.setActive(this.foreground); }

  private openLink(url: string): void {
    if (!/^https:\/\/[^/?#\s@]+(?:[/?#][^\s]*)?$/.test(url)) { this.store.error = '仅支持不含账号密码的 HTTPS 授权地址'; return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) { context.openLink(url).catch(() => { this.store.error = '无法打开浏览器，请稍后重试'; }); }
  }
  @Builder
  badge(label: string, color: string = '#DDEAE2') {
    Text(label).fontSize(11).fontColor('#315446').padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor(color).borderRadius(8)
  }
  @Builder
  heading(kicker: string, title: string, subtitle: string) {
    Column({ space: 8 }) {
      Text(kicker).fontSize(11).fontWeight(FontWeight.Bold).letterSpacing(2).fontColor('#74867A')
      Text(title).fontSize(30).fontWeight(FontWeight.Bold).fontColor('#173B2C')
      Text(subtitle).fontSize(13).fontColor('#6B7C73').lineHeight(21)
    }.alignItems(HorizontalAlign.Start).width('100%').padding({ top: 16, bottom: 20 })
  }

  @Builder
  connections() {
    Scroll() {
      Column({ space: 14 }) {
        this.heading('服务器', '连接管理', '添加或切换你的 OpenCode 服务器。')
        ForEach(this.store.servers, (server: ServerConfig) => {
          Column({ space: 10 }) {
            Row() {
              Column({ space: 5 }) {
                Text(server.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#244734')
                Text(server.url).fontSize(12).fontColor('#77847D').maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.store.connected === server.id) { this.badge('已连接') }
            }
            Row({ space: 10 }) {
              Button('连接', { type: ButtonType.Normal }).backgroundColor('#215D43').fontColor(Color.White)
                .borderRadius(9).height(36).layoutWeight(1).enabled(!this.store.busy)
                .onClick(() => { this.store.connect(server).then(() => { if (this.store.connected) { this.store.pane = 'chat'; } }); })
              Button('移除', { type: ButtonType.Normal }).backgroundColor('#F1F2EC').fontColor('#7F5048')
                .borderRadius(9).height(36).onClick(() => { this.store.removeServer(server.id); })
            }
          }.padding(16).backgroundColor(Color.White).borderRadius(16).width('100%')
        }, (server: ServerConfig) => server.id)
        Column({ space: 12 }) {
          Text('添加服务器').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#264332').width('100%')
          TextInput({ placeholder: '连接名称，例如：我的开发服务器', text: this.store.serverName })
            .onChange((value: string) => { this.store.serverName = value; }).backgroundColor('#F5F6F1').borderRadius(9).height(44)
          TextInput({ placeholder: 'https://opencode.example.com', text: this.store.serverUrl }).id('server-url')
            .onChange((value: string) => { this.store.serverUrl = value; }).backgroundColor('#F5F6F1').borderRadius(9).height(44)
          Row({ space: 10 }) {
            TextInput({ placeholder: 'API 用户名', text: this.store.serverUser }).id('server-user')
              .onChange((value: string) => { this.store.serverUser = value; }).layoutWeight(1).backgroundColor('#F5F6F1')
            TextInput({ placeholder: 'API 密码', text: this.store.serverPassword }).id('server-password').type(InputType.Password)
              .onChange((value: string) => { this.store.serverPassword = value; }).layoutWeight(1).backgroundColor('#F5F6F1')
          }
          Row({ space: 8 }) {
            Checkbox({ name: 'allow-http' }).id('allow-http').select(this.store.allowHttp).selectedColor('#215D43').width(20).height(20)
              .onChange((value: boolean) => { this.store.allowHttp = value; })
            Text('允许 HTTP（仅可信局域网或本地隧道）').fontSize(11).fontColor('#7A8075').layoutWeight(1)
          }.width('100%')
          Row({ space: 8 }) {
            Checkbox({ name: 'dedicated-trust' }).id('dedicated-trust').select(this.store.useDedicatedTrust)
              .selectedColor('#215D43').width(20).height(20)
              .onChange((value: boolean) => { this.store.useDedicatedTrust = value; })
            Text('使用专用服务器证书（IP 临时入口）').fontSize(11).fontColor('#7A8075').layoutWeight(1)
          }.width('100%')
          Button(this.store.busy ? '正在连接…' : '保存并连接', { type: ButtonType.Normal }).id('connect-button')
            .width('100%').height(46).borderRadius(11).backgroundColor('#215D43').fontColor(Color.White)
            .enabled(!this.store.busy).onClick(() => { this.store.addServer().then(() => { if (this.store.connected) { this.store.pane = 'chat'; } }); })
        }.padding(18).backgroundColor(Color.White).borderRadius(16).width('100%')
        Text('支持 OpenCode V2 · 凭据存储在系统安全资产中').fontSize(11).fontColor('#8A948B').margin({ bottom: 22 })
      }.padding({ left: 20, right: 20 }).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }

  @Builder
  projects() {
    Scroll() {
      Column({ space: 12 }) {
        this.heading('工作空间', '选择项目', '选择一个仓库，继续对话或开始新的任务。')
        ForEach(this.store.projects, (project: ProjectItem) => {
          Row({ space: 12 }) {
            Text('⌘').fontSize(24).fontColor('#3F7657')
            Column({ space: 6 }) {
              Text(project.name || '项目').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#264332')
              Text(project.directory).fontSize(11).fontColor('#7D8C81').maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            Text('›').fontSize(25).fontColor('#8A9C8C')
          }.width('100%').padding(16).backgroundColor(project.directory === this.store.directory ? '#DDEBDF' : Color.White)
            .borderRadius(13).onClick(() => { this.store.selectProject(project.directory); })
        }, (project: ProjectItem) => project.id + project.directory)
        Row({ space: 8 }) {
          TextInput({ placeholder: '服务器已有工作目录的绝对路径', text: this.store.manualPath }).id('project-path')
            .onChange((value: string) => { this.store.manualPath = value; }).layoutWeight(1).backgroundColor(Color.White).fontSize(12)
          Button('打开', { type: ButtonType.Normal }).id('open-project').backgroundColor('#E0EAE0').fontColor('#315D42')
            .borderRadius(9).enabled(!this.store.busy).onClick(() => { this.store.selectProject(this.store.manualPath); })
        }
        if (this.store.directory) {
          Row() {
            Text('会话').fontSize(19).fontWeight(FontWeight.Bold).fontColor('#254531').layoutWeight(1)
            Button('＋ 新建', { type: ButtonType.Normal }).id('new-session').backgroundColor('#215D43').fontColor(Color.White)
              .borderRadius(9).enabled(!this.store.busy).onClick(() => { this.store.createSession(); })
          }.margin({ top: 12 }).width('100%')
          ForEach(this.store.sessions, (session: SessionItem) => {
            Column({ space: 6 }) {
              Text(session.title).fontSize(16).fontColor('#294633').fontWeight(FontWeight.Medium)
              Text(session.directory.split('/').pop() || '项目会话').fontSize(11).fontColor('#8A978E')
            }.id('session-' + session.id).alignItems(HorizontalAlign.Start).padding(17).backgroundColor(Color.White).borderRadius(13)
              .width('100%').onClick(() => { this.pickSession(session); })
          }, (session: SessionItem) => session.id)
          if (this.store.sessions.length === 0) { Text('还没有会话，创建第一个任务。').fontSize(13).fontColor('#7C8C7F').padding(22) }
        }
      }.padding(20).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }

  private reasoningExpanded(message: ChatMessage): boolean {
    return reasoningInProgress(message) ? this.reasoningClosed.indexOf(message.id) < 0 : this.reasoningOpen.indexOf(message.id) >= 0;
  }
  private toggleReasoning(message: ChatMessage): void {
    this.follow = false;
    if (reasoningInProgress(message)) { this.reasoningClosed = this.reasoningClosed.indexOf(message.id) >= 0 ? this.reasoningClosed.filter((id: string) => id !== message.id) : this.reasoningClosed.concat(message.id); }
    else { this.reasoningOpen = this.reasoningOpen.indexOf(message.id) >= 0 ? this.reasoningOpen.filter((id: string) => id !== message.id) : this.reasoningOpen.concat(message.id); }
  }
  private navigate(pane: string): void {
    this.menuOpen = false; this.sidebarOpen = false;
    if (pane === 'settings') { this.store.openSettings(); }
    else if (pane === 'review') { this.store.openReview(); }
    else { this.store.pane = pane; }
  }
  private newChat(): void {
    this.sidebarOpen = false; this.follow = true;
    if (!this.store.connected) { this.navigate('connections'); }
    else if (!this.store.directory) { this.navigate('projects'); }
    else { this.store.createSession(); }
  }
  private projectName(): string { return this.store.directory.split('/').filter((value: string) => !!value).pop() || '选择项目'; }
  private async pickSession(session: SessionItem): Promise<void> { this.sidebarOpen = false; this.follow = true; await this.store.openSession(session); }
  @Builder
  messageCard(message: ChatMessage) {
    ConversationMessage({ message: message, thinking: reasoningInProgress(message), reasoningExpanded: this.reasoningExpanded(message),
      onToggleReasoning: (): void => { this.toggleReasoning(message); },
      onTool: (tool: ToolItem): void => { this.follow = false; this.selectedTool = tool; this.toolSheetOpen = true; },
      onOpenLink: (url: string): void => { this.openLink(url); } })
  }
  @Builder
  interactionCard(item: Interaction) {
    Column({ space: 12 }) {
      Row() {
        this.badge(item.kind === 'form' ? '需要你的回答' : '等待操作审批', '#F2E3B5')
        Blank()
        Text(this.store.itemState(item.id) === 'submitting' ? '提交中…' : this.store.itemState(item.id) === 'error' ? '待核对' : '待处理').fontSize(11).fontColor('#9A8959')
      }.width('100%')
      Text(item.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor('#514C2F').width('100%')
      if (item.detail) { Text(item.detail).fontSize(12).fontFamily('monospace').fontColor('#7A765E').copyOption(CopyOptions.InApp).width('100%') }
      if (item.kind === 'permission' && item.approval) {
        ApprovalPreviewView({ preview: item.approval, onReview: (): void => { this.follow = false; } })
      }
      FormFieldsView({ fields: this.store.currentFields(item.id),
        onChange: (key: string, value: string, multiple: boolean): void => { this.store.updateField(item.id, key, value, multiple); },
        onOpenLink: (url: string): void => { this.openLink(url); } }).enabled(this.store.itemState(item.id) !== 'submitting')
      Row({ space: 10 }) {
        Button(item.kind === 'form' ? '提交回答' : '批准一次', { type: ButtonType.Normal }).id('interaction-submit-' + item.id)
          .backgroundColor('#215D43').fontColor(Color.White).borderRadius(9).layoutWeight(1)
          .enabled(this.store.itemState(item.id) !== 'submitting' && (item.kind === 'form' || this.store.canApprove(item.id))).onClick(() => { this.store.reply(item); })
        Button(item.kind === 'form' ? '取消' : '拒绝', { type: ButtonType.Normal }).id('interaction-reject-' + item.id)
          .backgroundColor('#EDE7D4').fontColor('#8D6647').borderRadius(9)
          .enabled(this.store.itemState(item.id) !== 'submitting').onClick(() => { this.store.reply(item, true); })
      }.width('100%')
    }.id('interaction-card-' + item.id).padding(16).backgroundColor('#FFFBEF').borderRadius(14).width('100%')
  }

  @Builder
  chat() {
    Column({ space: 0 }) {
      if (this.store.connected) {
        Row({ space: 8 }) {
          Text(this.store.sessionTitle || '新对话').fontSize(12).fontColor('#899197').maxLines(1).layoutWeight(1)
          if (this.store.interactions.length) { Text('等待你处理').fontSize(11).fontColor('#B48643') }
          else if (this.store.working) { Text('正在运行').fontSize(11).fontColor('#668576') }
        }.padding({ left: 22, right: 22, bottom: 8 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      if (this.store.permissionError) {
        Row({ space: 8 }) {
          Text(this.store.permissionError).id('permission-sync-error').fontSize(12).fontColor('#965C40').layoutWeight(1)
          Button('重新读取审批', { type: ButtonType.Normal }).id('permission-retry').fontSize(11).backgroundColor('#F6EFE3').fontColor('#785C39').onClick(() => { this.store.retryPermissions(); })
        }.padding(12).width('100%').constraintSize({ maxWidth: 860 })
      }
      List({ space: 14, scroller: this.scroller }) {
        if (this.store.cursor) {
          ListItem() {
            Button('加载更早消息', { type: ButtonType.Normal }).fontSize(12).width('100%').backgroundColor(Color.Transparent).fontColor('#919A9F')
              .enabled(!this.store.busy).onClick(() => { this.follow = false; this.store.older(); })
          }
        }
        if (!this.store.messages.length && !this.store.interactions.length) {
          ListItem() {
            Column({ space: 16 }) {
              Text('◈').fontSize(44).fontColor('#356E55')
              Text('从一个想法开始').fontSize(24).fontWeight(FontWeight.Medium).fontColor('#2B353A')
              Text(this.store.directory ? '解释代码、修复问题，或一起完成一个任务。' : this.store.connected ? '选择一个项目，让 OpenCode 了解你的工作。' : '连接你的 OpenCode，随时继续开发。')
                .fontSize(13).fontColor('#98A0A4').textAlign(TextAlign.Center)
              Button(!this.store.connected ? '连接服务器' : !this.store.directory ? '选择项目' : '新建对话', { type: ButtonType.Normal }).id('welcome-action')
                .fontSize(13).fontColor('#416753').backgroundColor('#EDF3EF').borderRadius(20).height(40).enabled(!this.store.busy).onClick(() => { this.newChat(); })
            }.width('100%').height(330).justifyContent(FlexAlign.Center)
          }
        }
        LazyForEach(this.messageSource, (message: ChatMessage) => { ListItem() { this.messageCard(message) } }, (message: ChatMessage) => messageKey(message))
        ForEach(this.store.interactions, (item: Interaction) => { ListItem() { this.interactionCard(item) } }, (item: Interaction) => interactionKey(item))
      }.id('conversation-list').padding({ left: 22, right: 22 }).layoutWeight(1).width('100%').constraintSize({ maxWidth: 860 }).scrollBar(BarState.Off)
        .onScrollFrameBegin((offset: number, state: ScrollState) => { if (state === ScrollState.Scroll && offset < 0) { this.follow = false; } return { offsetRemain: offset }; })
      Column({ space: 5 }) {
        Row({ space: 8 }) {
          if (!this.follow || this.store.readingHistory || this.store.newerAvailable) {
            Button('↓ 回到最新', { type: ButtonType.Normal }).id('jump-latest').fontSize(11).height(30).backgroundColor('#F4F6F5').fontColor('#75817B')
              .onClick(() => { this.follow = true; if (this.store.readingHistory) { this.store.latest(); } else { this.scroller.scrollEdge(Edge.Bottom); } })
          }
          Blank()
          if (this.store.interactions.length) { Button('待处理 ' + this.store.interactions.length, { type: ButtonType.Normal }).id('pending-interactions').fontSize(11).height(30).backgroundColor('#FAF3E7').fontColor('#A27E40').onClick(() => { this.follow = false; this.scroller.scrollEdge(Edge.Bottom); }) }
          if (this.store.working) { Button('■ 停止', { type: ButtonType.Normal }).id('stop-button').fontSize(11).height(30).backgroundColor(Color.Transparent).fontColor('#8B7771').onClick(() => { this.store.interrupt(); }) }
        }.width('100%').height(32)
        Row({ space: 8 }) {
          TextArea({ placeholder: this.store.sessionID ? '说说你想做什么…' : '选择项目并新建对话后开始', text: this.store.draft }).id('chat-input')
            .height(64).layoutWeight(1).fontSize(15).backgroundColor(Color.Transparent).borderRadius(18).enabled(!this.store.pendingSend && !!this.store.sessionID).onChange((value: string) => { this.store.draft = value; })
          Button(this.store.pendingSend ? '重试' : '↑', { type: ButtonType.Normal }).id('send-button').width(42).padding(0).height(42).fontSize(this.store.pendingSend ? 12 : 23)
            .backgroundColor('#255D47').fontColor(Color.White).borderRadius(21).enabled(!this.store.busy && !!this.store.sessionID && (!!this.store.draft.trim() || !!this.store.pendingSend))
            .onClick(() => { this.follow = true; this.store.send(); setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 300); })
        }.padding({ left: 8, right: 12 }).width('100%').backgroundColor(Color.White).border({ width: 1, color: '#E8EBE9' }).borderRadius(24)
        Text('代码与任务在你的服务器运行').fontSize(9).fontColor('#B2B9B5').padding({ top: 3 })
      }.padding({ left: 18, right: 18, bottom: 10 }).width('100%').constraintSize({ maxWidth: 860 })
    }.alignItems(HorizontalAlign.Center).layoutWeight(1).width('100%')
  }
  @Builder
  diffCard(diff: DiffItem) {
    Column({ space: 8 }) {
      Text(diff.path || '文件修改').fontSize(13).fontWeight(FontWeight.Bold).fontFamily('monospace').fontColor('#345B40').width('100%')
      ForEach(parseDiff(diff.patch, 1500), (line: DiffLine) => {
        Row({ space: 6 }) {
          Text(line.oldLine).width(26).fontSize(9).fontColor('#92A092').textAlign(TextAlign.End)
          Text(line.newLine).width(26).fontSize(9).fontColor('#92A092').textAlign(TextAlign.End)
          Text(line.text || ' ').fontFamily('monospace').fontSize(10).fontColor(line.kind === 'remove' ? '#A1514F' : '#325A3E')
            .layoutWeight(1).copyOption(CopyOptions.InApp)
        }.alignItems(VerticalAlign.Top).width('100%').padding(3)
          .backgroundColor(line.kind === 'add' ? '#E0EFDF' : line.kind === 'remove' ? '#F4E4E1' : '#F4F6EF')
      }, (line: DiffLine) => line.id)
      if (diff.patch.split('\n', 1501).length > 1500) { Text('仅显示前 1500 行，请在桌面查看完整修改。').fontSize(11).fontColor('#8D815C') }
    }.padding(13).backgroundColor(Color.White).borderRadius(12).width('100%')
  }
  @Builder
  review() {
    Scroll() {
      Column({ space: 12 }) {
        this.heading('REVIEW CHANGES', '看看发生了什么', '只读查看当前工作区的文件和 Git 修改。')
        Row({ space: 8 }) {
          Button('Git Diff', { type: ButtonType.Normal }).backgroundColor(this.store.reviewTab === 'diff' ? '#215D43' : '#E1EADD')
            .fontColor(this.store.reviewTab === 'diff' ? Color.White : '#5B785C').borderRadius(9)
            .onClick(() => { this.store.reviewTab = 'diff'; })
          Button('文件浏览', { type: ButtonType.Normal }).backgroundColor(this.store.reviewTab === 'files' ? '#215D43' : '#E1EADD')
            .fontColor(this.store.reviewTab === 'files' ? Color.White : '#5B785C').borderRadius(9)
            .onClick(() => { this.store.reviewTab = 'files'; })
          Blank()
          Button('刷新', { type: ButtonType.Normal }).backgroundColor(Color.Transparent).fontColor('#688363').fontSize(12)
            .onClick(() => { this.store.openReview(); })
        }.width('100%')
        if (this.store.reviewTab === 'diff') {
          ForEach(this.store.diffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => diff.path)
          if (this.store.diffs.length === 0) { Text(this.store.reviewLoaded ? '当前没有可显示的修改。' : this.store.error ? '读取修改失败，请刷新重试。' : '正在读取修改…').fontSize(14).fontColor('#83927F').padding(25) }
        } else {
          Button('返回项目根目录', { type: ButtonType.Normal }).fontSize(12).backgroundColor('#E5EDE0').fontColor('#577651')
            .onClick(() => { this.store.openReview(); })
          ForEach(this.store.files, (file: FileItem) => {
            Row({ space: 10 }) {
              Text(file.directory ? '▸' : '·').fontColor('#748F6D')
              Text(file.name).fontFamily('monospace').fontSize(13).layoutWeight(1).fontColor('#395C3E')
            }.padding(13).width('100%').backgroundColor(Color.White).borderRadius(9)
              .onClick(() => { this.store.browse(file); })
          }, (file: FileItem) => file.path)
          if (this.store.fileContent) {
            Column({ space: 10 }) {
              if (this.store.fileTruncated) { Text('文件较长，仅显示前1500行或100000字；完整内容保留在服务器。').fontSize(11).fontColor('#9A8054') }
              Text(this.store.filePath).fontSize(12).fontWeight(FontWeight.Bold).fontColor('#415F44').width('100%')
              Text(this.store.fileContent).fontFamily('monospace').fontSize(11).fontColor('#4F6650')
                .copyOption(CopyOptions.InApp).width('100%')
            }.padding(14).backgroundColor(Color.White).borderRadius(12).width('100%')
          }
        }
      }.padding(18).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }
  @Builder
  sidebar(width: number) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        Text('◈').fontSize(23).fontColor('#356E55')
        Text('OpenCode').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#303C35').layoutWeight(1)
        Button('‹', { type: ButtonType.Normal }).id('close-sidebar').width(34).padding(0).height(34).fontSize(24).backgroundColor(Color.Transparent).fontColor('#89958E').onClick(() => { this.sidebarOpen = false; })
      }.width('100%').padding({ top: 12 })
      Button('＋ 新对话', { type: ButtonType.Normal }).id('sidebar-new-chat').width('100%').height(42).fontSize(14).backgroundColor(Color.White).fontColor('#3E5449').borderRadius(12).enabled(!this.store.busy).onClick(() => { this.newChat(); })
      Button('▱  ' + this.projectName() + '  ›', { type: ButtonType.Normal }).id('sidebar-projects').width('100%').height(40).fontSize(13).backgroundColor(Color.Transparent).fontColor('#727F77').enabled(!!this.store.connected).onClick(() => { this.navigate('projects'); })
      TextInput({ placeholder: '搜索当前项目的会话', text: this.sessionSearch }).id('session-search').height(36).fontSize(12).backgroundColor('#EDEFEF').borderRadius(10).onChange((value: string) => { this.sessionSearch = value; })
      Text('历史对话').fontSize(11).fontColor('#9BA49F').width('100%').padding({ top: 8 })
      Scroll() {
        Column({ space: 5 }) {
          ForEach(this.store.sessions.filter((session: SessionItem) => !this.sessionSearch || session.title.toLowerCase().indexOf(this.sessionSearch.toLowerCase()) >= 0), (session: SessionItem) => {
            Text(session.title).id('sidebar-session-' + session.id).fontSize(13).fontColor('#59665D').maxLines(2).width('100%').padding(12)
              .backgroundColor(session.id === this.store.sessionID ? '#E4EBE6' : Color.Transparent).borderRadius(10).onClick(() => { this.pickSession(session); })
          }, (session: SessionItem) => session.id)
          if (!this.store.sessions.length) { Text(this.store.connected ? '选择项目后，对话会出现在这里' : '连接服务器后，继续你的对话').fontSize(12).fontColor('#A0A9A3').padding(12) }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
      Divider().color('#E5E9E5')
      Button('⌘  代码审查', { type: ButtonType.Normal }).id('nav-review').width('100%').height(38).fontSize(13).backgroundColor(Color.Transparent).fontColor('#748078').enabled(!!this.store.directory).onClick(() => { this.navigate('review'); })
      Button('⚙  模型与接入', { type: ButtonType.Normal }).id('nav-settings').width('100%').height(38).fontSize(13).backgroundColor(Color.Transparent).fontColor('#748078').enabled(!!this.store.connected).onClick(() => { this.navigate('settings'); })
      Row({ space: 10 }) {
        Text('◉').fontSize(17).fontColor(this.store.connected ? '#6E9A7F' : '#AFB7B2')
        Column({ space: 3 }) {
          Text(this.store.servers.find((server: ServerConfig) => server.id === this.store.connected)?.name || '服务器连接').fontSize(13).fontColor('#607166').maxLines(1)
          Text(this.store.status).fontSize(10).fontColor('#9AA59E').maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Text('›').fontSize(20).fontColor('#9AA59E')
      }.id('nav-connections').padding(10).width('100%').borderRadius(12).onClick(() => { this.navigate('connections'); })
    }.padding({ left: 16, right: 16, bottom: 14 }).width(width).height('100%').backgroundColor('#F5F7F6')
  }
  @Builder
  menuSheet() {
    Column({ space: 8 }) {
      Text('对话与工作空间').fontSize(18).fontWeight(FontWeight.Medium).fontColor('#34453C').padding({ bottom: 12 }).width('100%')
      Button('选择项目与会话', { type: ButtonType.Normal }).id('menu-projects').width('100%').height(44).backgroundColor('#F5F7F6').fontColor('#596A60').enabled(!!this.store.connected).onClick(() => { this.navigate('projects'); })
      Button('代码审查', { type: ButtonType.Normal }).id('menu-review').width('100%').height(44).backgroundColor('#F5F7F6').fontColor('#596A60').enabled(!!this.store.directory).onClick(() => { this.navigate('review'); })
      Button('模型与接入', { type: ButtonType.Normal }).id('menu-settings').width('100%').height(44).backgroundColor('#F5F7F6').fontColor('#596A60').enabled(!!this.store.connected).onClick(() => { this.navigate('settings'); })
      Button('服务器连接', { type: ButtonType.Normal }).id('menu-connections').width('100%').height(44).backgroundColor('#F5F7F6').fontColor('#596A60').onClick(() => { this.navigate('connections'); })
      Button('同步当前对话', { type: ButtonType.Normal }).id('menu-sync').width('100%').height(44).backgroundColor(Color.Transparent).fontColor('#85948B').enabled(!!this.store.sessionID).onClick(() => { this.menuOpen = false; this.store.sync(); })
    }.padding({ left: 22, right: 22, top: 22, bottom: 28 }).width('100%')
  }
  @Builder
  toolDetails() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text(this.selectedTool.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor('#35473D').layoutWeight(1)
        Text(toolStatus(this.selectedTool.status)).fontSize(12).fontColor('#8A968E')
      }.padding({ right: 38 }).width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text('调用参数').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#7A8980').width('100%')
          Text(this.selectedTool.input.slice(0, 12000) || '无参数').id('tool-request').fontFamily('monospace').fontSize(12).lineHeight(21).fontColor('#59685F').padding(14).backgroundColor('#F5F7F6').borderRadius(12).copyOption(CopyOptions.InApp).width('100%')
          Text('执行结果').fontSize(12).fontWeight(FontWeight.Bold).fontColor('#7A8980').width('100%')
          Text(this.selectedTool.output.slice(0, 16000) || (this.selectedTool.status === 'running' ? '正在执行，结果会自动更新…' : '暂无文本结果')).id('tool-response')
            .fontFamily('monospace').fontSize(12).lineHeight(21).fontColor('#59685F').padding(14).backgroundColor('#F5F7F6').borderRadius(12).copyOption(CopyOptions.InApp).width('100%')
          if (this.selectedTool.input.length > 12000 || this.selectedTool.output.length > 16000) { Text('较长内容已截断，完整记录保留在服务器。').fontSize(11).fontColor('#A09A85') }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
    }.id('tool-details').padding({ left: 20, right: 20, top: 24, bottom: 20 }).width('100%').height('100%')
  }
  @Builder
  topBar() {
    Row({ space: 8 }) {
      if (this.store.pane === 'chat') {
        Button('☰', { type: ButtonType.Normal }).id('open-sidebar').width(40).padding(0).height(40).fontSize(22).fontColor('#596A60').backgroundColor(Color.Transparent).onClick(() => { this.sidebarOpen = !this.sidebarOpen; })
        if (this.store.models.length) {
          Select(this.store.models.map((model: ModelItem): SelectOption => ({ value: model.label }))).id('model-select')
            .value(this.store.models.find((model: ModelItem) => model.id === this.store.modelID)?.label || '选择模型').font({ size: 12 }).fontColor('#596A60').backgroundColor('#F5F7F6')
            .borderRadius(18).height(36).width(Math.min(240, Math.max(100, this.viewportWidth - 184))).enabled(!!this.store.sessionID).onSelect((index: number) => { this.store.chooseModel(this.store.models[index].id); })
        } else { Text('OpenCode').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#354A3C').layoutWeight(1) }
        Blank().layoutWeight(1)
        Button('＋', { type: ButtonType.Normal }).id('header-new-chat').width(38).padding(0).height(38).fontSize(23).backgroundColor(Color.Transparent).fontColor('#63756A').enabled(!this.store.busy).onClick(() => { this.newChat(); })
        Button('⋮', { type: ButtonType.Normal }).id('open-menu').width(32).padding(0).height(38).fontSize(24).backgroundColor(Color.Transparent).fontColor('#63756A')
          .onClick(() => { this.menuOpen = true; }).bindSheet($$this.menuOpen, this.menuSheet(), { height: 410, showClose: true })
      } else {
        Button('‹', { type: ButtonType.Normal }).id('back-chat').width(40).padding(0).height(40).fontSize(29).backgroundColor(Color.Transparent).fontColor('#63756A').onClick(() => { this.store.pane = 'chat'; })
        Text(this.store.pane === 'connections' ? '服务器连接' : this.store.pane === 'projects' ? '项目与会话' : this.store.pane === 'settings' ? '模型与接入' : '代码审查').fontSize(17).fontWeight(FontWeight.Medium).fontColor('#354A3C').layoutWeight(1)
        Text(this.store.status).fontSize(10).fontColor('#98A69C')
      }
    }.width('100%').height(62).padding({ left: 10, right: 12 })
  }
  build() {
    Stack({ alignContent: Alignment.Start }) {
      Row({ space: 0 }) {
        if (this.wide && this.sidebarOpen) { this.sidebar(268) }
        Column({ space: 0 }) {
          this.topBar()
          if (this.store.error) {
            Row({ space: 8 }) {
              Text(this.store.error).fontSize(12).fontColor('#A67564').layoutWeight(1).maxLines(3)
              Button('×', { type: ButtonType.Normal }).width(30).padding(0).height(30).fontSize(20).fontColor('#A67564').backgroundColor(Color.Transparent).onClick(() => { this.store.error = ''; })
            }.padding({ left: 20, right: 12, top: 6, bottom: 6 }).backgroundColor('#FCF6F1').width('100%')
          }
          if (this.store.pane === 'connections') { this.connections() }
          else if (this.store.pane === 'projects') { this.projects() }
          else if (this.store.pane === 'settings') { ProviderSettings({ store: this.store.providers, onOpenLink: (url: string): void => { this.openLink(url); } }) }
          else if (this.store.pane === 'review') { this.review() }
          else { this.chat() }
        }.layoutWeight(1).height('100%').backgroundColor(Color.White)
      }.width('100%').height('100%')
      if (!this.wide && this.sidebarOpen) {
        Row({ space: 0 }) {
          this.sidebar(Math.min(300, this.viewportWidth * 0.84))
          Blank().layoutWeight(1).height('100%').backgroundColor('#55000000').onClick(() => { this.sidebarOpen = false; })
        }.width('100%').height('100%')
      }
    }.width('100%').height('100%').backgroundColor(Color.White)
      .onAreaChange((oldArea: Area, newArea: Area) => { this.viewportWidth = Number(newArea.width); const wide = this.viewportWidth >= 840; if (this.wide !== wide) { this.wide = wide; this.sidebarOpen = wide; } })
      .bindSheet($$this.toolSheetOpen, this.toolDetails(), { height: SheetSize.LARGE, showClose: true })
  }
}