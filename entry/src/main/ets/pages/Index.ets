import { common } from '@kit.AbilityKit';
import { AppStore } from '../presentation/AppStore';
import { MarkdownText } from '../components/MarkdownText';
import { ProviderSettings } from '../components/ProviderSettings';
import { FormFieldsView } from '../components/FormFieldsView';
import { MessageDataSource } from '../presentation/MessageDataSource';
import { ServerConfig, ProjectItem, SessionItem, ChatMessage, ToolItem, Interaction, FormField, Choice,
  ModelItem, FileItem, DiffItem, DiffLine, parseDiff, visibleFormFields, messageKey } from '../domain/Core';

@Entry
@Component
struct Index {
  @State @Watch('storeChanged') store: AppStore = new AppStore();
  @StorageLink('appForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State follow: boolean = true;
  @State expandedTool: string = '';
  private scroller: Scroller = new Scroller();
  private messageSource: MessageDataSource = new MessageDataSource();

  aboutToAppear(): void {
    const context = this.getUIContext().getHostContext();
    if (context) { this.store.init(context as common.Context); }
  }
  aboutToDisappear(): void { this.store.setActive(false); }
  private storeChanged(): void {
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
        this.heading('YOUR WORKSPACE, ANYWHERE', '连接你的工作台', '代码和 Agent 留在服务器，\n在手机上查看、提问与批准。')
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
                .onClick(() => { this.store.connect(server); })
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
            Checkbox({ name: 'allow-http' }).select(this.store.allowHttp).selectedColor('#215D43').width(20).height(20)
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
            .enabled(!this.store.busy).onClick(() => { this.store.addServer(); })
        }.padding(18).backgroundColor(Color.White).borderRadius(16).width('100%')
        Text('支持 OpenCode V2 · 凭据存储在系统安全资产中').fontSize(11).fontColor('#8A948B').margin({ bottom: 22 })
      }.padding({ left: 20, right: 20 }).width('100%')
    }.layoutWeight(1).scrollBar(BarState.Off)
  }

  @Builder
  projects() {
    Scroll() {
      Column({ space: 12 }) {
        this.heading('PROJECTS & SESSIONS', '从上次的地方继续', '选择服务器上的工作目录，继续已有任务或开启新的会话。')
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
              Text(session.id).fontSize(10).fontColor('#8A978E')
            }.alignItems(HorizontalAlign.Start).padding(17).backgroundColor(Color.White).borderRadius(13)
              .width('100%').onClick(() => { this.store.openSession(session); })
          }, (session: SessionItem) => session.id)
          if (this.store.sessions.length === 0) { Text('还没有会话，创建第一个任务。').fontSize(13).fontColor('#7C8C7F').padding(22) }
        }
      }.padding(20).width('100%')
    }.layoutWeight(1).scrollBar(BarState.Off)
  }

  @Builder
  toolCard(tool: ToolItem) {
    Column({ space: 8 }) {
      Row({ space: 8 }) {
        Text('⌁').fontSize(19).fontColor('#69856F')
        Text(tool.name).fontFamily('monospace').fontSize(12).fontWeight(FontWeight.Bold).layoutWeight(1)
        this.badge(tool.status)
      }.width('100%').onClick(() => { this.expandedTool = this.expandedTool === tool.id ? '' : tool.id; })
      if (this.expandedTool === tool.id) {
        Text(tool.input.slice(0, 12000)).fontFamily('monospace').fontSize(11).fontColor('#63766C').copyOption(CopyOptions.InApp)
        if (tool.output) { Text(tool.output.slice(0, 16000)).fontFamily('monospace').fontSize(11).copyOption(CopyOptions.InApp) }
      }
    }.padding(12).backgroundColor('#EAF0E8').borderRadius(10).width('100%')
  }
  @Builder
  messageCard(message: ChatMessage) {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(message.role === 'user' ? '你' : message.role === 'assistant' ? 'OPENCODE' : '会话事件')
          .fontSize(10).fontWeight(FontWeight.Bold).letterSpacing(1).fontColor(message.role === 'user' ? '#6C886C' : '#3A7852')
        if (message.state === 'streaming' && message.role === 'assistant') { Text('●').fontSize(7).fontColor('#539465') }
      }.width('100%')
      if (message.reasoning) {
        Column({ space: 6 }) {
          Text(this.store.showReasoning ? '思考过程  ▾' : '思考过程  ▸').fontSize(11).fontColor('#829077').width('100%')
            .onClick(() => { this.store.showReasoning = !this.store.showReasoning; })
          if (this.store.showReasoning) { Text(message.reasoning).fontSize(12).fontColor('#74816F').lineHeight(19).copyOption(CopyOptions.InApp) }
        }.alignItems(HorizontalAlign.Start).padding(12).backgroundColor('#F0F2E8').borderRadius(10).width('100%')
      }
      if (message.text) { MarkdownText({ content: message.text, onOpenLink: (url: string): void => { this.openLink(url); } }) }
      ForEach(message.tools, (tool: ToolItem) => { this.toolCard(tool) }, (tool: ToolItem) => tool.id)
      if (!message.text && !message.reasoning && message.tools.length === 0) {
        Text(message.role === 'assistant' ? '正在等待输出…' : message.role).fontSize(12).fontColor('#89968B')
      }
    }.alignItems(HorizontalAlign.Start).padding(16).backgroundColor(message.role === 'user' ? '#E6EEE1' : Color.White)
      .borderRadius(15).width('100%')
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
      FormFieldsView({ fields: this.store.currentFields(item.id),
        onChange: (key: string, value: string, multiple: boolean): void => { this.store.updateField(item.id, key, value, multiple); },
        onOpenLink: (url: string): void => { this.openLink(url); } }).enabled(this.store.itemState(item.id) !== 'submitting')
      Row({ space: 10 }) {
        Button(item.kind === 'form' ? '提交回答' : '批准一次', { type: ButtonType.Normal })
          .backgroundColor('#215D43').fontColor(Color.White).borderRadius(9).layoutWeight(1)
          .enabled(this.store.itemState(item.id) !== 'submitting').onClick(() => { this.store.reply(item); })
        Button(item.kind === 'form' ? '取消' : '拒绝', { type: ButtonType.Normal })
          .backgroundColor('#EDE7D4').fontColor('#8D6647').borderRadius(9)
          .enabled(this.store.itemState(item.id) !== 'submitting').onClick(() => { this.store.reply(item, true); })
      }.width('100%')
    }.padding(16).backgroundColor('#FFFBEF').borderRadius(14).width('100%')
  }

  @Builder
  chat() {
    Column({ space: 0 }) {
      Column({ space: 6 }) {
        Text(this.store.sessionTitle || '选择一个会话').fontSize(21).fontWeight(FontWeight.Bold).fontColor('#244531').width('100%').maxLines(1)
        Text(this.store.directory).fontSize(10).fontColor('#7E8C80').width('100%').maxLines(1)
        Row({ space: 8 }) {
          if (this.store.models.length > 0) {
            Select(this.store.models.map((model: ModelItem): SelectOption => ({ value: model.label })))
              .value(this.store.models.find((m: ModelItem) => m.id === this.store.modelID)?.label || '选择模型')
              .font({ size: 11 }).fontColor('#4C7156').backgroundColor('#E6EDE0').height(30).layoutWeight(1)
              .onSelect((index: number) => { this.store.chooseModel(this.store.models[index].id); })
          }
          this.badge(this.store.interactions.length ? '等待你处理' : this.store.working ? '任务运行中' : '会话已同步')
          Button('同步', { type: ButtonType.Normal }).fontSize(11).height(30).backgroundColor('#E8EDE2').fontColor('#597158')
            .borderRadius(8).onClick(() => { this.store.sync(); })
        }.width('100%')
      }.padding({ left: 20, right: 20, top: 14, bottom: 12 }).width('100%')
      List({ space: 12, scroller: this.scroller }) {
        if (this.store.cursor) {
          ListItem() {
            Button('加载更早消息', { type: ButtonType.Normal }).fontSize(12).width('100%').backgroundColor('#E6EDE1').fontColor('#597158')
              .enabled(!this.store.busy).onClick(() => { this.follow = false; this.store.older(); })
          }
        }
        if (this.store.messages.length === 0 && this.store.interactions.length === 0) {
          ListItem() {
            Column({ space: 14 }) {
              Text('⌘').fontSize(52).fontColor('#B5C8AF')
              Text('开始一个有用的任务').fontSize(19).fontWeight(FontWeight.Medium).fontColor('#49694D')
              Text('解释项目、修复问题，或审查一次修改。').fontSize(12).fontColor('#889681')
            }.height(220).width('100%').justifyContent(FlexAlign.Center)
          }
        }
        LazyForEach(this.messageSource, (message: ChatMessage) => {
          ListItem() { this.messageCard(message) }
        }, (message: ChatMessage) => messageKey(message))
        ForEach(this.store.interactions, (item: Interaction) => {
          ListItem() { this.interactionCard(item) }
        }, (item: Interaction) => item.id)
      }.padding({ left: 16, right: 16 }).layoutWeight(1).scrollBar(BarState.Off)
        .onScrollFrameBegin((offset: number, state: ScrollState) => {
          if (state === ScrollState.Scroll && offset < 0) { this.follow = false; }
          return { offsetRemain: offset };
        })
        .onDidScroll(() => {})
      Row({ space: 8 }) {
        Button(this.follow ? '跟随输出 ✓' : '↓ 回到最新', { type: ButtonType.Normal }).fontSize(10).height(26)
          .backgroundColor(Color.Transparent).fontColor('#6C826A')
          .onClick(() => { this.follow = true; if (this.store.readingHistory) { this.store.latest(); } else { this.scroller.scrollEdge(Edge.Bottom); } })
        Blank()
        if (this.store.working) {
          Button('停止任务', { type: ButtonType.Normal }).fontSize(10).height(26).backgroundColor('#EDE5DA').fontColor('#9A6B56')
            .onClick(() => { this.store.interrupt(); })
        }
      }.padding({ left: 14, right: 18 }).width('100%')
      Row({ space: 10 }) {
        TextArea({ placeholder: '让 OpenCode 帮你做点什么…', text: this.store.draft }).id('chat-input')
          .height(58).layoutWeight(1).fontSize(14).backgroundColor(Color.White).borderRadius(13)
          .enabled(!this.store.pendingSend).onChange((value: string) => { this.store.draft = value; })
        Button(this.store.pendingSend ? '重试' : '↑', { type: ButtonType.Normal }).id('send-button')
          .width(52).height(52).fontSize(22).backgroundColor('#215D43').fontColor(Color.White).borderRadius(15)
          .enabled(!this.store.busy && this.store.sessionID.length > 0)
          .onClick(() => { this.follow = true; this.store.send(); setTimeout(() => { this.scroller.scrollEdge(Edge.Bottom); }, 300); })
      }.padding({ left: 16, right: 16, top: 8, bottom: 14 }).width('100%')
    }.layoutWeight(1).width('100%')
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
    }.layoutWeight(1).scrollBar(BarState.Off)
  }
  @Builder
  navigation() {
    Row() {
      Button('连接', { type: ButtonType.Normal }).layoutWeight(1).fontSize(12)
        .fontColor(this.store.pane === 'connections' ? '#215D43' : '#96A18F').backgroundColor(Color.Transparent)
        .onClick(() => { this.store.pane = 'connections'; })
      Button('项目', { type: ButtonType.Normal }).layoutWeight(1).fontSize(12).enabled(this.store.connected.length > 0)
        .fontColor(this.store.pane === 'projects' ? '#215D43' : '#96A18F').backgroundColor(Color.Transparent)
        .onClick(() => { this.store.pane = 'projects'; })
      Button('聊天', { type: ButtonType.Normal }).layoutWeight(1).fontSize(12).enabled(this.store.sessionID.length > 0)
        .fontColor(this.store.pane === 'chat' ? '#215D43' : '#96A18F').backgroundColor(Color.Transparent)
        .onClick(() => { this.store.pane = 'chat'; })
      Button('审查', { type: ButtonType.Normal }).layoutWeight(1).fontSize(12).enabled(this.store.directory.length > 0)
        .fontColor(this.store.pane === 'review' ? '#215D43' : '#96A18F').backgroundColor(Color.Transparent)
        .onClick(() => { this.store.openReview(); })
      Button('设置', { type: ButtonType.Normal }).id('settings-tab').layoutWeight(1).fontSize(12).enabled(this.store.connected.length > 0)
        .fontColor(this.store.pane === 'settings' ? '#215D43' : '#96A18F').backgroundColor(Color.Transparent)
        .onClick(() => { this.store.openSettings(); })
    }.width('100%').height(52).backgroundColor('#FBFCF7').border({ width: { top: 1 }, color: '#E1E8DB' })
  }
  build() {
    Row() {
    Column() {
      Row({ space: 8 }) {
        Text('◈').fontSize(25).fontColor('#2F6945')
        Text('OpenCode').fontSize(18).fontWeight(FontWeight.Bold).fontColor('#2B4933')
        Text('HARMONY').fontSize(9).fontWeight(FontWeight.Medium).letterSpacing(2).fontColor('#8C9A81')
        Blank()
        Text(this.store.status).fontSize(10).fontColor('#7B8E73')
      }.padding({ left: 20, right: 20, top: 14, bottom: 12 }).width('100%')
      if (this.store.error) {
        Row({ space: 8 }) {
          Text(this.store.error).fontSize(11).fontColor('#985C4A').layoutWeight(1).maxLines(4)
          Text('×').fontSize(20).fontColor('#A97D68').onClick(() => { this.store.error = ''; })
        }.padding(12).backgroundColor('#F6E8DE').width('100%')
      }
      if (this.store.pane === 'connections') { this.connections() }
      else if (this.store.pane === 'projects') { this.projects() }
      else if (this.store.pane === 'chat') { this.chat() }
      else if (this.store.pane === 'settings') { ProviderSettings({ store: this.store.providers, onOpenLink: (url: string): void => { this.openLink(url); } }) }
      else { this.review() }
      this.navigation()
    }.width('100%').height('100%').constraintSize({ maxWidth: 1000 }).backgroundColor('#F4F6ED')
    }.width('100%').height('100%').justifyContent(FlexAlign.Center).backgroundColor('#F4F6ED')
  }
}
