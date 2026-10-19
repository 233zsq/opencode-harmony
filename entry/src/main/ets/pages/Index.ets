import { ForkPanel } from '../components/ForkPanel';
import { UsagePanel } from '../components/UsagePanel';
import { AgentItem } from '../domain/Agents';
import { AgentPicker } from '../components/AgentPicker';
import { ExportPanel } from '../components/ExportPanel';
import { DocumentSaver } from '../data/DocumentSaver';
import { ModelPicker } from '../components/ModelPicker';
import { DiffContent } from '../components/DiffContent';
import { Attachment, attachmentProblem } from '../domain/Attachments';
import { AttachmentPicker } from '../data/AttachmentPicker';
import { AttachmentStrip } from '../components/AttachmentStrip';
import { AttachmentPreview } from '../components/AttachmentPreview';
import { copyText } from '../presentation/Clipboard';
import { Appearance } from '../presentation/Appearance';
import { SymbolGlyphModifier, KeyboardAvoidMode } from '@kit.ArkUI';
import { NativeSegments } from '../components/NativeSegments';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { common } from '@kit.AbilityKit';
import { AppStore } from '../presentation/AppStore';
import { ConversationMessage } from '../components/ConversationMessage';
import { ApprovalPreviewView } from '../components/ApprovalPreview';
import { ProviderSettings } from '../components/ProviderSettings';
import { FormFieldsView } from '../components/FormFieldsView';
import { MessageDataSource } from '../presentation/MessageDataSource';
import { ServerConfig, ProjectItem, SessionItem, ChatMessage, ToolItem, Interaction, FormField, Choice,
  ModelItem, FileItem, DiffItem, DiffLine, TurnItem, PendingItem, pendingKey, diffKey, parseDiff, visibleFormFields, messageKey, interactionKey, reasoningInProgress, toolStatus } from '../domain/Core';

@Entry
@Component
struct Index {
  @State @Watch('storeChanged') store: AppStore = new AppStore();
  @StorageLink('appForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @State follow: boolean = true;
  @State switchingModel: boolean = false;
  @State savingExport: boolean = false;
  @State exportNotice: string = '';
  private async selectAgent(id: string): Promise<void> {
    const scope = this.store.connected + '/' + this.store.sessionID;
    if (await this.store.chooseAgent(id) && scope === this.store.connected + '/' + this.store.sessionID && this.sheetKind === 'agent') { this.toolSheetOpen = false; }
  }
  private async exportConversation(format: string, tools: boolean): Promise<void> {
    if (this.savingExport) { return; } this.exportNotice = '';
    const scope = this.store.exportScope();
    const document = await this.store.prepareExport(format, tools);
    if (!document || scope !== this.store.exportScope() || !this.toolSheetOpen || this.sheetKind !== 'export') { return; }
    this.savingExport = true;
    try { const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved = await new DocumentSaver(context).saveText(document.name, document.text, (): boolean => scope === this.store.exportScope());
      if (scope === this.store.exportScope()) { this.exportNotice = saved ? '已保存 ' + document.count + ' 条对话' : '已取消保存，可重新导出'; }
    } catch (_) { this.exportNotice = '文件未保存，请重试'; } finally { this.savingExport = false; }
  }
  private async selectModel(id: string): Promise<void> {
    if (this.switchingModel || !this.store.sessionID) { return; }
    if (id === this.store.modelID) { this.toolSheetOpen = false; return; }
    const scope = this.store.connected + '/' + this.store.sessionID; this.switchingModel = true;
    try { await this.store.chooseModel(id); if (scope === this.store.connected + '/' + this.store.sessionID && this.store.modelID === id && !this.store.error) { this.toolSheetOpen = false; } }
    finally { this.switchingModel = false; }
  }
  @State forkBefore: string = '';
  @State forkEditing: boolean = false;
  @State forkText: string = '';
  @State forkSource: string = '';
  @State forkHasFiles: boolean = false;
  @State forkScope: string = '';
  private connectionScroller: Scroller = new Scroller();
  private openFork(message?: ChatMessage, edit: boolean = false): void {
    this.forkBefore = message?.id || ''; this.forkEditing = edit; this.forkText = edit ? message?.text || '' : ''; this.forkSource = message ? message.text.slice(0, 180) || '所选消息包含附件或工具内容' : '';
    this.forkHasFiles = !!message?.files?.length; this.forkScope = this.store.exportScope(); this.store.forkError = ''; this.sheetKind = 'fork'; this.toolSheetOpen = true;
  }
  private async createFork(text: string, reuse: boolean): Promise<void> {
    const scope = this.forkScope; if (scope !== this.store.exportScope()) { return; }
    const child = await this.store.forkSession(this.forkBefore, this.forkEditing, text, reuse);
    if (!child || scope !== this.store.exportScope()) { return; }
    if (this.toolSheetOpen && this.sheetKind === 'fork') { this.toolSheetOpen = false; this.follow = true; await this.store.openSession(child); }
    else { this.toast('分支已创建，可在会话列表打开'); }
  }
  private confirmRemoveServer(server: ServerConfig): void {
    this.getUIContext().showAlertDialog({ title: '移除连接', message: '从本机移除“' + server.name + '”的配置、凭据和会话位置。服务器任务与聊天历史仍会保留。',
      primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '移除', action: (): void => { this.store.removeServer(server.id); } } });
  }
  private confirmCompaction(): void {
    const scope = this.store.exportScope();
    this.getUIContext().showAlertDialog({ title: '压缩上下文', message: '将调用当前模型生成摘要，可能产生费用。是否继续？', primaryButton: { value: '取消', action: (): void => {} },
      secondaryButton: { value: '确认压缩', action: (): void => { if (scope === this.store.exportScope()) { this.store.requestCompaction(); } } } });
  }
  private confirmForkReview(): void {
    const scope = this.store.exportScope(); this.getUIContext().showAlertDialog({ title: '重新创建分支', message: '请先确认会话列表没有上次创建的分支。重复操作可能创建多个分支。',
      primaryButton: { value: '取消', action: (): void => {} }, secondaryButton: { value: '已检查', action: (): void => { if (scope === this.store.exportScope()) { this.store.clearForkAfterReview(); } } } });
  }
  @State savingAttachment: boolean = false;
  private toast(message: string): void { try { this.getUIContext().getPromptAction().showToast({ message: message }); } catch (_) {} }
  private async saveAttachment(item: Attachment): Promise<void> {
    if (this.savingAttachment) { return; } this.savingAttachment = true;
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      if (await new AttachmentPicker(context).save(item)) { this.toast('已保存文件'); }
    } catch (_) { this.toast('文件未保存，请重试'); }
    finally { this.savingAttachment = false; }
  }
  @State pickingAttachments: boolean = false;
  @State selectedAttachment: Attachment = { id: '', name: '', mime: '', data: '', size: 0 };
  private async pickAttachments(photos: boolean, retry?: Attachment): Promise<void> {
    if (this.pickingAttachments || this.store.pendingSend || this.store.busy || !this.store.sessionID) { return; }
    const scope = this.store.connected + '/' + this.store.directory + '/' + this.store.sessionID;
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    this.pickingAttachments = true;
    try {
      const picker = new AttachmentPicker(context);
      const items = retry?.uri ? [await picker.read(retry.uri, retry.id, retry.mime.startsWith('image/'))] : await picker.select(photos, 4 - this.store.attachments.length);
      if (scope !== this.store.connected + '/' + this.store.directory + '/' + this.store.sessionID) { return; }
      if (retry) { if (this.store.attachments.some((a: Attachment) => a.id === retry.id)) { this.store.replaceAttachment(items[0]); } }
      else { this.store.addAttachments(items); }
    } catch (_) { this.store.error = '未能打开附件选择器，请稍后重试'; }
    finally { this.pickingAttachments = false; }
  }
  private async openAttachment(item: Attachment): Promise<void> {
    const scope = this.store.connected + '/' + this.store.sessionID; this.selectedAttachment = item; this.sheetKind = 'attachment'; this.toolSheetOpen = true;
    const preview = await this.store.attachmentPreview(item);
    if (scope === this.store.connected + '/' + this.store.sessionID && this.sheetKind === 'attachment' && this.toolSheetOpen) { this.selectedAttachment = preview; }
  }
  @StorageLink('appearanceMode') appearanceMode: string = 'system';
  @StorageLink('appearanceDark') darkAppearance: boolean = false;
  @State sidebarOpen: boolean = false;
  @State wide: boolean = false;
  @State viewportWidth: number = 400;
  @State sessionSearch: string = '';
  @State pendingFilter: number = 0;
  @State selectedSession: SessionItem = { id: '', title: '', directory: '', status: '', model: '' };
  @State sessionName: string = '';
  private viewMessages: ChatMessage[] = [];
  private viewInteractions: Interaction[] = [];
  private scrollTimer: number = -1;
  @State toolSheetOpen: boolean = false;
  @State sheetKind: string = 'tool';
  @State selectedTool: ToolItem = { id: '', name: '', status: '', input: '', output: '' };
  @State reasoningOpen: string[] = [];
  @State reasoningClosed: string[] = [];
  private activeReasoning: string[] = [];
  private viewSession: string = '';
  private viewContent: string = '';
  @State navigation: NavPathStack = new NavPathStack();
  private scroller: Scroller = new Scroller();
  private messageSource: MessageDataSource = new MessageDataSource();

  aboutToAppear(): void {
    this.getUIContext().setKeyboardAvoidMode(KeyboardAvoidMode.RESIZE);
    const context = this.getUIContext().getHostContext();
    if (context) { this.store.init(context as common.Context); }
  }
  aboutToDisappear(): void { if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; } this.store.setActive(false); }
  onBackPress(): boolean { if (this.sidebarOpen) { this.sidebarOpen = false; return true; } return false; }
  private storeChanged(): void {
    this.syncNavigation();
    const session = this.store.connected + '/' + this.store.sessionID;
    if (session !== this.viewSession) { this.viewSession = session; this.viewContent = ''; this.sessionSearch = ''; this.reasoningOpen = []; this.reasoningClosed = []; this.activeReasoning = []; if (this.sheetKind === 'tool' || this.sheetKind === 'session' || this.sheetKind === 'attachment' || this.sheetKind === 'model' || this.sheetKind === 'agent' || this.sheetKind === 'export' || this.sheetKind === 'fork' || this.sheetKind === 'usage') { this.toolSheetOpen = false; } this.follow = true; }
    if (this.viewMessages === this.store.messages && this.viewInteractions === this.store.interactions) { return; }
    this.viewMessages = this.store.messages; this.viewInteractions = this.store.interactions;
    const active = this.store.messages.filter((m: ChatMessage) => reasoningInProgress(m)).map((m: ChatMessage) => m.id);
    const ended = this.activeReasoning.filter((id: string) => active.indexOf(id) < 0);
    const ids = this.store.messages.map((m: ChatMessage) => m.id);
    this.reasoningOpen = this.reasoningOpen.filter((id: string) => ended.indexOf(id) < 0 && ids.indexOf(id) >= 0);
    this.reasoningClosed = this.reasoningClosed.filter((id: string) => active.indexOf(id) >= 0);
    this.activeReasoning = active;
    if (this.toolSheetOpen && this.sheetKind === 'tool') { const tool = this.store.messages.flatMap((m: ChatMessage) => m.tools).find((t: ToolItem) => t.id === this.selectedTool.id); if (tool) { this.selectedTool = tool; } }
    this.messageSource.update(this.store.messages);
    const content = this.store.messages.map((message: ChatMessage) => messageKey(message)).join('|') + '/' + this.store.interactions.map((item: Interaction) => item.id).join('|');
    const changed = content !== this.viewContent; this.viewContent = content;
    if (changed && this.follow && this.store.pane === 'chat' && this.scrollTimer < 0) { this.scrollTimer = setTimeout(() => { this.scrollTimer = -1; if (this.follow && this.store.pane === 'chat') { this.scroller.scrollEdge(Edge.Bottom); } }, 40); }
  }
  private syncNavigation(): void {
    const names = this.navigation.getAllPathName();
    if (this.store.pane === 'chat') { if (names.length) { this.navigation.clear(); } return; }
    if (names[names.length - 1] === this.store.pane) { return; }
    if (names.length) { this.navigation.clear(false); }
    const route = this.store.pane;
    this.navigation.pushPath({ name: route, param: route });
  }
  private showActions(): void { this.sheetKind = 'actions'; this.toolSheetOpen = true; }
  private changeAppearance(mode: string): void {
    const context = this.getUIContext().getHostContext();
    if (context) { Appearance.save(context as common.Context, mode).catch(() => { this.store.error = '外观设置未保存，请稍后重试。'; }); }
  }
  private pageTitle(name: string): string {
    return name === 'pending' ? '待办中心' : name === 'connections' ? '服务器连接' : name === 'projects' ? '项目与会话' : name === 'settings' ? '模型与接入' : name === 'appearance' ? '外观' : '代码审查';
  }
  private foregroundChanged(): void { this.store.setActive(this.foreground); }

  private copy(text: string): void {
    copyText(text).then(() => { this.getUIContext().getPromptAction().showToast({ message: '已复制' }); })
      .catch(() => { this.store.error = '复制失败，请稍后重试'; });
  }
  private manageSession(session: SessionItem): void {
    this.selectedSession = session; this.sessionName = session.title; this.sheetKind = 'session'; this.toolSheetOpen = true;
  }
  private openLink(url: string): void {
    if (!/^https:\/\/[^/?#\s@]+(?:[/?#][^\s]*)?$/.test(url)) { this.store.error = '仅支持不含账号密码的 HTTPS 授权地址'; return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) { context.openLink(url).catch(() => { this.store.error = '无法打开浏览器，请稍后重试'; }); }
  }
  @Builder
  badge(label: string, color: ResourceColor = C.field) {
    Text(label).fontSize(11).fontColor(C.text).padding({ left: 9, right: 9, top: 5, bottom: 5 })
      .backgroundColor(color).borderRadius(8)
  }
  @Builder
  heading(kicker: string, title: string, subtitle: string) {
    Text(subtitle).fontSize(14).fontColor(C.secondary).lineHeight(22).width('100%').padding({ top: 12, bottom: 12 })
  }

  @Builder
  connections() {
    Scroll(this.connectionScroller) {
      Column({ space: 14 }) {
        this.heading('服务器', '连接管理', '添加或切换你的 OpenCode 服务器。')
        ForEach(this.store.servers, (server: ServerConfig) => {
          Column({ space: 10 }) {
            Row() {
              Column({ space: 5 }) {
                Text(server.name).fontSize(17).fontWeight(FontWeight.Bold).fontColor(C.text)
                Text(server.url).fontSize(12).fontColor(C.secondary).maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.store.connected === server.id) { this.badge('已连接') }
            }
            Row({ space: 10 }) {
              Button('连接', { type: ButtonType.Capsule }).id('connect-server-' + server.id).backgroundColor(C.accent).fontColor(C.on_accent)
                .borderRadius(9).height(36).layoutWeight(1).enabled(!this.store.busy && !this.store.serverSaving)
                .onClick(() => { this.store.connect(server).then(() => { if (this.store.connected) { this.store.pane = 'chat'; } }); })
              Button('编辑', { type: ButtonType.Capsule }).id('edit-server-' + server.id).height(36).backgroundColor(C.field).fontColor(C.text).enabled(!this.store.serverSaving && !this.store.busy).onClick(() => { this.store.editServer(server); setTimeout(() => { this.connectionScroller.scrollEdge(Edge.Bottom); }, 50); })
              Button('移除', { type: ButtonType.Capsule }).id('remove-server-' + server.id).backgroundColor(C.field).fontColor(C.danger)
                .borderRadius(9).height(36).enabled(!this.store.serverSaving && !this.store.busy).onClick(() => { this.confirmRemoveServer(server); })
            }
          }.id('server-profile-' + server.id).padding(16).backgroundColor(C.surface).borderRadius(16).width('100%')
        }, (server: ServerConfig) => server.id + server.name + server.url + server.username + String(server.id === this.store.connected))
        Column({ space: 12 }) {
          Text(this.store.serverEditID ? '编辑连接' : '添加服务器').fontSize(18).fontWeight(FontWeight.Bold).fontColor(C.text).width('100%')
          TextInput({ placeholder: '连接名称，例如：我的开发服务器', text: this.store.serverName }).id('server-name').maxLength(80).enabled(!this.store.serverSaving && !this.store.busy)
            .onChange((value: string) => { this.store.serverName = value; }).backgroundColor(C.field).borderRadius(9).height(44)
          TextInput({ placeholder: 'https://opencode.example.com', text: this.store.serverUrl }).id('server-url').maxLength(2048).enabled(!this.store.serverSaving && !this.store.busy)
            .onChange((value: string) => { this.store.serverUrl = value; }).backgroundColor(C.field).borderRadius(9).height(44)
          Row({ space: 10 }) {
            TextInput({ placeholder: 'API 用户名', text: this.store.serverUser }).id('server-user').maxLength(120).enabled(!this.store.serverSaving && !this.store.busy)
              .onChange((value: string) => { this.store.serverUser = value; }).layoutWeight(1).backgroundColor(C.field)
            TextInput({ placeholder: this.store.serverEditID ? '密码留空保留原密码' : 'API 密码', text: this.store.serverPassword }).id('server-password').maxLength(2048).enabled(!this.store.serverSaving && !this.store.busy).type(InputType.Password)
              .onChange((value: string) => { this.store.serverPassword = value; }).layoutWeight(1).backgroundColor(C.field)
          }
          Row({ space: 8 }) {
            Checkbox({ name: 'allow-http' }).id('allow-http').enabled(!this.store.serverSaving && !this.store.busy).select(this.store.allowHttp).selectedColor(C.accent).width(20).height(20)
              .onChange((value: boolean) => { this.store.allowHttp = value; })
            Text('允许 HTTP（仅可信局域网或本地隧道）').fontSize(11).fontColor(C.secondary).layoutWeight(1)
          }.width('100%')
          Row({ space: 8 }) {
            Checkbox({ name: 'dedicated-trust' }).id('dedicated-trust').enabled(!this.store.serverSaving && !this.store.busy).select(this.store.useDedicatedTrust)
              .selectedColor(C.accent).width(20).height(20)
              .onChange((value: boolean) => { this.store.useDedicatedTrust = value; })
            Text('使用专用服务器证书（IP 临时入口）').fontSize(11).fontColor(C.secondary).layoutWeight(1)
          }.width('100%')
          if (this.store.serverEditID) {
            Row({ space: 8 }) { Checkbox().id('server-clear-password').select(this.store.clearServerPassword).width(20).height(20).enabled(!this.store.serverSaving).onChange((value: boolean) => { this.store.clearServerPassword = value; }); Text('清除已保存密码').fontSize(12).fontColor(C.secondary) }.width('100%')
            Text('修改地址或账号会清理此连接旧的本机会话位置、书签与模型偏好。密码留空会保留原密码。').fontSize(12).fontColor(C.secondary).width('100%')
            Button('取消编辑').id('server-cancel-edit').height(32).buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.store.serverSaving).onClick(() => { this.store.resetServerForm(); this.store.error = ''; this.store.serverNotice = ''; })
          }
          if (this.store.serverNotice) { Text(this.store.serverNotice).id('server-notice').fontSize(12).fontColor(C.secondary).width('100%') }
          Button(this.store.serverSaving ? '正在保存…' : '保存并连接', { type: ButtonType.Capsule }).id('connect-button')
            .width('100%').height(46).borderRadius(11).backgroundColor(C.accent).fontColor(C.on_accent)
            .enabled(!this.store.busy && !this.store.serverSaving).onClick(() => { this.store.saveServer().then((saved: boolean) => { if (saved && this.store.connected) { this.store.pane = 'chat'; } }); })
        }.padding(18).backgroundColor(C.surface).borderRadius(16).width('100%')
        Text('支持 OpenCode V2 · 凭据存储在系统安全资产中').fontSize(11).fontColor(C.secondary).margin({ bottom: 22 })
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
            SymbolGlyph($r('sys.symbol.folder')).fontSize(22).fontColor([C.accent])
            Column({ space: 6 }) {
              Text(project.name || '项目').fontSize(16).fontWeight(FontWeight.Medium).fontColor(C.text)
              Text(project.directory).fontSize(11).fontColor(C.secondary).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([C.secondary])
          }.width('100%').padding(16).backgroundColor(project.directory === this.store.directory ? C.field : C.surface)
            .borderRadius(13).onClick(() => { this.store.selectProject(project.directory); })
        }, (project: ProjectItem) => project.id + project.directory)
        Row({ space: 8 }) {
          TextInput({ placeholder: '服务器已有工作目录的绝对路径', text: this.store.manualPath }).id('project-path')
            .onChange((value: string) => { this.store.manualPath = value; }).layoutWeight(1).backgroundColor(C.surface).fontSize(12)
          Button('打开', { type: ButtonType.Capsule }).id('open-project').backgroundColor(C.field).fontColor(C.text)
            .borderRadius(9).enabled(!this.store.busy).onClick(() => { this.store.selectProject(this.store.manualPath); })
        }
        if (this.store.directory) {
          Row() {
            Text('会话').fontSize(19).fontWeight(FontWeight.Bold).fontColor(C.text).layoutWeight(1)
            Button('新建对话', { type: ButtonType.Capsule }).id('new-session').backgroundColor(C.accent).fontColor(C.on_accent)
              .borderRadius(9).enabled(!this.store.busy).onClick(() => { this.store.createSession(); })
          }.margin({ top: 12 }).width('100%')
          this.sessionFilters()
          ForEach(this.store.sessionRows(), (session: SessionItem) => { this.sessionRow(session, false) },
            (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id) + String(this.store.isPinned(session.id)))
          this.sessionPaging()
          if (this.store.sessions.length === 0) { Text('还没有会话，创建第一个任务。').fontSize(13).fontColor(C.secondary).padding(22) }
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
    this.toolSheetOpen = false; this.sidebarOpen = false;
    if (pane === 'settings') { this.store.openSettings(); }
    else if (pane === 'pending') { this.store.pane = 'pending'; this.store.refreshPending(true); }
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
      onFork: (edit: boolean): void => { this.openFork(message, edit); }, onToggleReasoning: (): void => { this.toggleReasoning(message); },
      onTool: (tool: ToolItem): void => { this.follow = false; this.selectedTool = tool; this.sheetKind = 'tool'; this.toolSheetOpen = true; },
      onAttachment: (item: Attachment): void => { this.openAttachment(item); }, onOpenLink: (url: string): void => { this.openLink(url); }, onCopy: (text: string): void => { this.copy(text); } })
  }
  @Builder
  interactionCard(item: Interaction) {
    Column({ space: 12 }) {
      Row() {
        this.badge(item.kind === 'form' ? '需要你的回答' : '等待操作审批', C.warning_bg)
        Blank()
        Text(this.store.itemState(item.id) === 'submitting' ? '提交中…' : this.store.itemState(item.id) === 'error' ? '待核对' : '待处理').fontSize(11).fontColor(C.warning)
      }.width('100%')
      Text(item.title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(C.text).width('100%')
      if (item.detail) { Text(item.detail).fontSize(12).fontFamily('monospace').fontColor(C.secondary).copyOption(CopyOptions.InApp).width('100%') }
      if (item.kind === 'permission' && item.approval) {
        ApprovalPreviewView({ preview: item.approval, onReview: (): void => { this.follow = false; } })
      }
      FormFieldsView({ fields: this.store.currentFields(item.id),
        onChange: (key: string, value: string, multiple: boolean): void => { this.follow = false; this.store.updateField(item.id, key, value, multiple); },
        onOpenLink: (url: string): void => { this.openLink(url); } }).enabled(this.store.itemState(item.id) !== 'submitting')
      Row({ space: 10 }) {
        Button(item.kind === 'form' ? '提交回答' : '批准一次', { type: ButtonType.Capsule }).id('interaction-submit-' + item.id)
          .backgroundColor(C.accent).fontColor(C.on_accent).borderRadius(9).layoutWeight(1)
          .enabled(this.store.itemState(item.id) !== 'submitting' && (item.kind === 'form' || this.store.canApprove(item.id))).onClick(() => { this.follow = true; this.store.reply(item); })
        Button(item.kind === 'form' ? '取消' : '拒绝', { type: ButtonType.Capsule }).id('interaction-reject-' + item.id)
          .backgroundColor(C.warning_bg).fontColor(C.warning).borderRadius(9)
          .enabled(this.store.itemState(item.id) !== 'submitting').onClick(() => { this.follow = true; this.store.reply(item, true); })
      }.width('100%')
    }.id('interaction-card-' + item.id).padding(16).backgroundColor(C.warning_bg).borderRadius(14).width('100%')
  }

  @Builder
  chat() {
    Column({ space: 0 }) {
      if (this.store.connected) {
        Row({ space: 8 }) {
          Text(this.store.sessionTitle || '新对话').fontSize(12).fontColor(C.secondary).maxLines(1).layoutWeight(1)
          if (this.store.sessionID) {
            Button(this.store.agents.find((a: AgentItem) => a.id === this.store.agentID)?.name || this.store.agentID || '默认 Agent', { type: ButtonType.Capsule }).id('agent-select')
              .fontSize(11).height(28).constraintSize({ maxWidth: 150 }).labelStyle({ maxLines: 1, overflow: TextOverflow.Ellipsis }).buttonStyle(ButtonStyleMode.TEXTUAL)
              .onClick(() => { this.sheetKind = 'agent'; this.toolSheetOpen = true; this.store.refreshAgentState(); })
          }
          if (this.store.status !== '实时连接' && this.store.status !== '已连接') { Text(this.store.status).fontSize(11).fontColor(C.warning) }
          if (this.store.agentUncertain) { Text('Agent 待确认').fontSize(11).fontColor(C.warning) }
          if (this.store.interactions.length) { Text('等待你处理').fontSize(11).fontColor(C.warning) }
          else if (this.store.working) { Text('正在运行').fontSize(11).fontColor(C.secondary) }
        }.padding({ left: 22, right: 22, bottom: 8 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      if (this.store.parentSessionID) {
        Row({ space: 8 }) { Text(this.store.branchBoundary ? '分叉会话 · ' + this.store.branchBoundary : '子会话').fontSize(11).fontColor(C.secondary).layoutWeight(1); Button('原会话').id('branch-parent').height(28).fontSize(11).buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => { this.store.openParentSession(); }) }.padding({ left: 22, right: 22, bottom: 6 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      if (this.store.permissionError) {
        Row({ space: 8 }) {
          Text(this.store.permissionError).id('permission-sync-error').fontSize(12).fontColor(C.warning).layoutWeight(1)
          Button('重新读取审批', { type: ButtonType.Capsule }).id('permission-retry').fontSize(11).backgroundColor(C.warning_bg).fontColor(C.warning).onClick(() => { this.store.retryPermissions(); })
        }.padding(12).width('100%').constraintSize({ maxWidth: 860 })
      }
      List({ space: 4, scroller: this.scroller }) {
        if (this.store.cursor) {
          ListItem() {
            Button('加载更早消息', { type: ButtonType.Capsule }).id('older-messages').fontSize(12).width('100%').backgroundColor(Color.Transparent).fontColor(C.muted)
              .enabled(!this.store.busy).onClick(() => { this.follow = false; this.store.older(); })
          }
        }
        if (!this.store.messages.length && !this.store.interactions.length && !this.store.busy) {
          ListItem() {
            Column({ space: 16 }) {
              SymbolGlyph($r('sys.symbol.lightbulb')).fontSize(44).fontColor([C.accent])
              Text('从一个想法开始').fontSize(24).fontWeight(FontWeight.Medium).fontColor(C.text)
              Text(this.store.directory ? '解释代码、修复问题，或一起完成一个任务。' : this.store.connected ? '选择一个项目，让 OpenCode 了解你的工作。' : '连接你的 OpenCode，随时继续开发。')
                .fontSize(13).fontColor(C.muted).textAlign(TextAlign.Center)
              if (!this.store.sessionID) { Button(!this.store.connected ? '连接服务器' : !this.store.directory ? '选择项目' : '新建对话', { type: ButtonType.Capsule }).id('welcome-action')
                .fontSize(13).fontColor(C.text).backgroundColor(C.field).borderRadius(20).height(40).enabled(!this.store.busy).onClick(() => { this.newChat(); }) }
            }.width('100%').height(330).justifyContent(FlexAlign.Center)
          }
        }
        LazyForEach(this.messageSource, (message: ChatMessage) => { ListItem() { this.messageCard(message) } }, (message: ChatMessage) => messageKey(message))
        ForEach(this.store.interactions, (item: Interaction) => { ListItem() { this.interactionCard(item) } }, (item: Interaction) => interactionKey(item))
      }.onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) { this.follow = false; } }).id('conversation-list').padding({ left: 22, right: 22 }).layoutWeight(1).width('100%').constraintSize({ maxWidth: 860 }).scrollBar(BarState.Off)
        .onScrollFrameBegin((offset: number, state: ScrollState) => { if (state === ScrollState.Scroll && offset < 0) { this.follow = false; } return { offsetRemain: offset }; })
      Column({ space: 6 }) {
        if (this.pickingAttachments || this.store.working || this.store.pendingSend) {
          Row({ space: 6 }) {
            if (this.pickingAttachments || this.store.working) { LoadingProgress().width(14).height(14).color(C.accent) }
            Text(this.pickingAttachments ? '正在读取附件…' : this.store.pendingSend ? '发送结果待核对，重试会沿用同一条消息' : this.store.interrupting ? '正在停止…' : '正在生成…').fontSize(11).fontColor(C.secondary).layoutWeight(1)
            if (this.store.pendingSend) { Button('核对状态').id('verify-send').height(26).fontSize(11).buttonStyle(ButtonStyleMode.TEXTUAL).enabled(!this.store.busy).onClick(() => { this.store.sync(); }) }
          }.width('100%').padding({ left: 4, right: 4 })
        }
        if (this.store.attachments.length) {
          AttachmentStrip({ items: this.store.attachments, editable: true, locked: this.pickingAttachments || !!this.store.pendingSend || this.store.busy,
            onOpen: (item: Attachment): void => { this.openAttachment(item); }, onRemove: (id: string): void => { this.store.removeAttachment(id); }, onRetry: (item: Attachment): void => { this.pickAttachments(false, item); } })
          if (attachmentProblem(this.store.attachments, this.store.attachmentInput())) { Text(attachmentProblem(this.store.attachments, this.store.attachmentInput())).fontSize(11).fontColor(C.warning).width('100%') }
        }
        if (!this.follow || this.store.readingHistory || this.store.newerAvailable || this.store.interactions.length || (this.store.working && (!!this.store.draft.trim() || !!this.store.attachments.length))) {
          Row({ space: 8 }) {
            if (!this.follow || this.store.readingHistory || this.store.newerAvailable) {
              Button('回到最新').id('jump-latest').fontSize(11).height(28).backgroundColor(C.field).fontColor(C.secondary)
                .onClick(() => { this.follow = true; if (this.store.readingHistory) { this.store.latest(); } else { this.scroller.scrollEdge(Edge.Bottom); } })
            }
            Blank()
            if (this.store.interactions.length) { Button('待处理 ' + this.store.interactions.length).id('pending-interactions').fontSize(11).height(28).backgroundColor(C.warning_bg).fontColor(C.warning).onClick(() => { this.follow = false; this.scroller.scrollEdge(Edge.Bottom); }) }
            if (this.store.working && (this.store.draft.trim() || this.store.attachments.length)) { Button('停止生成').id('stop-secondary').fontSize(11).height(28).backgroundColor(Color.Transparent).fontColor(C.danger).enabled(!this.store.interrupting).onClick(() => { this.store.interrupt(); }) }
          }.width('100%').height(28)
        }
        Row({ space: 8 }) {
          Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.plus')).fontSize(19).fontColor([C.secondary]) }
            .id('attachment-add').accessibilityText('添加附件').width(32).height(36).padding(0).margin({ bottom: 3 }).backgroundColor(Color.Transparent)
            .enabled(!!this.store.sessionID && !this.store.busy && !this.store.pendingSend && !this.pickingAttachments)
            .bindMenu(this.attachmentMenu())
          TextArea({ placeholder: this.store.sessionID ? '发消息，或描述一个任务…' : '选择项目后开始对话', text: this.store.draft }).id('chat-input')
            .minLines(1).maxLines(5).constraintSize({ minHeight: 42, maxHeight: 148 }).maxLength(20000).layoutWeight(1).fontSize(15).lineHeight(22)
            .padding({ left: 0, right: 0, top: 10, bottom: 10 }).fontColor(C.text).placeholderColor(C.muted).caretColor(C.accent)
            .backgroundColor(Color.Transparent).borderRadius(0).enabled(!this.store.pendingSend && !!this.store.sessionID).onChange((value: string) => { this.store.draft = value; })
          if (this.store.working && !this.store.draft.trim() && !this.store.attachments.length && !this.store.pendingSend) {
            Button({ type: ButtonType.Circle }) { Text('■').fontSize(14).fontColor(C.on_accent) }
              .id('stop-button').accessibilityText('停止生成').width(36).height(36).padding(0).backgroundColor(C.accent).enabled(!this.store.interrupting).margin({ bottom: 3 })
              .onClick(() => { this.store.interrupt(); })
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.store.pendingSend) { Text('重试').fontSize(10).fontColor(C.on_accent) }
              else { SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(18).fontColor([this.store.draft.trim() || this.store.attachments.length ? C.on_accent : C.muted]) }
            }.id('send-button').accessibilityText(this.store.pendingSend ? '重试发送' : '发送消息').width(36).padding(0).height(36).margin({ bottom: 3 })
              .backgroundColor(this.store.draft.trim() || this.store.attachments.length || this.store.pendingSend ? C.accent : C.field).enabled(!this.store.busy && !this.store.agentBusy && !this.store.agentUncertain && !this.store.forkBusy && !this.store.compactionBusy && ['submitting', 'queued', 'running'].indexOf(this.store.compaction.state) < 0 && !this.pickingAttachments && !!this.store.sessionID && (!!this.store.draft.trim() || !!this.store.attachments.length || !!this.store.pendingSend))
              .onClick(() => { this.follow = true; this.store.send(); })
          }
        }.alignItems(VerticalAlign.Bottom).padding({ left: 14, right: 8, top: 4, bottom: 4 }).width('100%')
          .backgroundColor(C.field).border({ width: 0.5, color: C.separator }).borderRadius(22)
        if (this.store.draft.length > 1000) { Text(String(this.store.draft.length) + ' / 20000').fontSize(10).fontColor(C.muted).width('100%').textAlign(TextAlign.End) }
      }.id('chat-composer').padding({ left: 16, right: 16, top: 8, bottom: 10 }).width('100%').constraintSize({ maxWidth: 860 })
    }.alignItems(HorizontalAlign.Center).layoutWeight(1).width('100%')
  }
  @Builder
  diffCard(diff: DiffItem) { DiffContent({ diff: diff, onCopy: (text: string): void => { this.copy(text); } }) }
  @Builder
  review() {
    Scroll() {
      Column({ space: 12 }) {
        this.heading('REVIEW CHANGES', '看看发生了什么', '查看工作区现状，或按会话任务回看文件修改。')
        NativeSegments({ first: 'Git Diff', second: '会话修改', third: '文件浏览',
          selected: this.store.reviewTab === 'diff' ? 0 : this.store.reviewTab === 'timeline' ? 1 : 2,
          onSelect: (index: number): void => { this.store.reviewTab = index === 0 ? 'diff' : index === 1 ? 'timeline' : 'files';
            if (index === 1 && !this.store.timelineLoaded) { this.store.loadTimeline(); } } }).id('review-segments')
        Row() {
          Text(this.store.reviewTab === 'timeline' ? '会话任务快照' : this.store.reviewTab === 'files' ? '项目文件' : '工作区修改').fontSize(12).fontColor(C.secondary).layoutWeight(1)
          Button('刷新').controlSize(ControlSize.SMALL).buttonStyle(ButtonStyleMode.TEXTUAL).onClick(() => {
            if (this.store.reviewTab === 'timeline') { this.store.loadTimeline(); } else { this.store.openReview(); }
          })
        }.width('100%')
        if (this.store.reviewTab === 'diff') {
          ForEach(this.store.diffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => diffKey(diff))
          if (this.store.diffs.length === 0) { Text(this.store.reviewLoaded ? '当前没有可显示的修改。' : this.store.error ? '读取修改失败，请刷新重试。' : '正在读取修改…').fontSize(14).fontColor(C.secondary).padding(25) }
        } else if (this.store.reviewTab === 'timeline') {
          Text('同一轮任务中的追加消息合并显示。运行中的 Diff 随文件变化，点击刷新可重新读取。').fontSize(12).fontColor(C.secondary).width('100%')
          if (this.store.timelineError) { Text(this.store.timelineError).fontSize(12).fontColor(C.warning).width('100%') }
          ForEach(this.store.turns, (turn: TurnItem) => {
            Row({ space: 10 }) {
              Column({ space: 5 }) {
                Text(turn.title).fontSize(13).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(C.text).width('100%')
                Text((turn.created ? new Date(turn.created).toLocaleString() + ' · ' : '') + turn.prompts + ' 条消息 · ' +
                  (turn.partial ? '需加载更早记录确认起点' : turn.state === 'running' ? '尚未结束' : turn.state === 'failed' ? '任务未成功' : '已结束'))
                  .fontSize(10).fontColor(C.secondary).width('100%')
              }.layoutWeight(1)
              Text(turn.id === this.store.turnID ? '已选择' : '查看').fontSize(11).fontColor(C.secondary)
            }.id('turn-' + turn.id).padding(12).width('100%').borderRadius(10)
              .backgroundColor(turn.id === this.store.turnID ? C.field : C.surface)
              .onClick(() => { this.store.selectTurn(turn); })
          }, (turn: TurnItem) => turn.id + turn.state + turn.prompts + String(turn.partial))
          if (this.store.timelineCursor) {
            Button(this.store.canLoadTimeline() ? '加载更早任务' : '已达到最近 300 条记录的窗口上限', { type: ButtonType.Capsule })
              .id('timeline-older').fontSize(12).enabled(!this.store.timelineBusy && this.store.canLoadTimeline()).onClick(() => { this.store.loadTimeline(true); })
          }
          if (this.store.timelineBusy) { Text('正在读取任务记录…').fontSize(12).fontColor(C.secondary) }
          if (this.store.timelineLoaded && !this.store.turns.length) { Text('这个会话还没有任务记录。').fontSize(13).fontColor(C.secondary) }
          if (this.store.turnID) {
            Text('所选任务的文件修改').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
            if (this.store.turnError) { Text('读取失败：' + this.store.turnError).fontSize(12).fontColor(C.warning).width('100%') }
            if (this.store.turnBusy) { Text('正在比较任务快照…').fontSize(12).fontColor(C.secondary) }
            ForEach(this.store.turnDiffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => this.store.turnID + ':' + diffKey(diff))
            if (this.store.turnLoaded && !this.store.turnDiffs.length) { Text('这轮任务没有文件修改。').fontSize(13).fontColor(C.secondary) }
          }
        } else {
          Button('返回项目根目录', { type: ButtonType.Capsule }).fontSize(12).backgroundColor(C.field).fontColor(C.secondary)
            .onClick(() => { this.store.openReview(); })
          ForEach(this.store.files, (file: FileItem) => {
            Row({ space: 10 }) {
              SymbolGlyph(file.directory ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text')).fontSize(16).fontColor([C.secondary])
              Text(file.name).fontFamily('monospace').fontSize(13).layoutWeight(1).fontColor(C.text)
            }.padding(13).width('100%').backgroundColor(C.surface).borderRadius(9)
              .onClick(() => { this.store.browse(file); })
          }, (file: FileItem) => file.path)
          if (this.store.fileContent) {
            Column({ space: 10 }) {
              if (this.store.fileTruncated) { Text('文件较长，仅显示前1500行或100000字；完整内容保留在服务器。').fontSize(11).fontColor(C.warning) }
              Text(this.store.filePath).fontSize(12).fontWeight(FontWeight.Bold).fontColor(C.text).width('100%')
              Text(this.store.fileContent).fontFamily('monospace').fontSize(11).fontColor(C.text)
                .copyOption(CopyOptions.InApp).width('100%')
            }.padding(14).backgroundColor(C.surface).borderRadius(12).width('100%')
          }
        }
      }.padding(18).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }
  @Builder
  sidebar(width: number) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.code_square')).fontSize(24).fontColor([C.accent])
        Text('OpenCode').fontSize(18).fontWeight(FontWeight.Bold).fontColor(C.text).layoutWeight(1)
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([C.secondary]) }.id('close-sidebar').accessibilityText('关闭历史侧栏').width(36).height(36).backgroundColor(Color.Transparent).onClick(() => { this.sidebarOpen = false; })
      }.width('100%').padding({ top: 12 })
      Button('新建对话', { type: ButtonType.Capsule }).id('sidebar-new-chat').width('100%').height(42).fontSize(14).backgroundColor(C.surface).fontColor(C.text).borderRadius(12).enabled(!this.store.busy).onClick(() => { this.newChat(); })
      Button(this.projectName(), { type: ButtonType.Capsule }).id('sidebar-projects').width('100%').height(40).fontSize(13).backgroundColor(Color.Transparent).fontColor(C.secondary).enabled(!!this.store.connected).onClick(() => { this.navigate('projects'); })
      this.sessionFilters()
      Text(this.store.showArchived ? '本机归档' : '历史对话').fontSize(11).fontColor(C.muted).width('100%').padding({ top: 8 })
      Scroll() {
        Column({ space: 5 }) {
          ForEach(this.store.sessionRows(this.sessionSearch), (session: SessionItem) => { this.sessionRow(session, true) },
            (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id) + String(this.store.isPinned(session.id)))
          this.sessionPaging()
          if (!this.store.sessionRows(this.sessionSearch).length) { Text(this.store.connected ? '暂无匹配的会话，可搜索服务器历史或切换归档。' : '连接服务器后，继续你的对话').fontSize(12).fontColor(C.muted).padding(12) }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
      Divider().color(C.field)
      Button('待办中心' + (this.store.pendingItems.length ? ' · ' + this.store.pendingItems.length : ''), { type: ButtonType.Capsule }).id('nav-pending').width('100%').height(38).fontSize(13).backgroundColor(Color.Transparent).fontColor(C.secondary).enabled(!!this.store.connected).onClick(() => { this.navigate('pending'); })
      Button('代码审查', { type: ButtonType.Capsule }).id('nav-review').width('100%').height(38).fontSize(13).backgroundColor(Color.Transparent).fontColor(C.secondary).enabled(!!this.store.directory).onClick(() => { this.navigate('review'); })
      Button('模型与接入', { type: ButtonType.Capsule }).id('nav-settings').width('100%').height(38).fontSize(13).backgroundColor(Color.Transparent).fontColor(C.secondary).enabled(!!this.store.connected).onClick(() => { this.navigate('settings'); })
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right_badge_person_filled')).fontSize(17).fontColor([this.store.connected ? C.accent : C.muted])
        Column({ space: 3 }) {
          Text(this.store.servers.find((server: ServerConfig) => server.id === this.store.connected)?.name || '服务器连接').fontSize(13).fontColor(C.secondary).maxLines(1)
          Text(this.store.status).fontSize(10).fontColor(C.muted).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([C.muted])
      }.id('nav-connections').padding(10).width('100%').borderRadius(12).onClick(() => { this.navigate('connections'); })
    }.padding({ left: 16, right: 16, bottom: 14 }).width(width).height('100%').backgroundColor(C.sidebar)
  }
  @Builder
  attachmentMenu() {
    Menu() {
      MenuItem({ content: '选择照片' }).id('attachment-photos').enabled(this.store.attachmentInput().indexOf('image') >= 0).onClick(() => { this.pickAttachments(true); })
      MenuItem({ content: '选择文件' }).id('attachment-files').onClick(() => { this.pickAttachments(false); })
      MenuItem({ content: '最多 4 个，合计 1 MB；图片会压缩' }).enabled(false)
    }
  }
  @Builder
  sheetContent() {
    if (this.sheetKind === 'tool') { this.toolDetails() }
    else if (this.sheetKind === 'agent') { AgentPicker({ agents: this.store.agents, current: this.store.agentID, busy: this.store.agentBusy, loading: this.store.agentLoading, error: this.store.agentError, blocked: this.store.agentUncertain ? '请先重新读取，确认当前 Agent。' : this.store.working || this.store.pendingSend || this.store.interactions.length || this.store.permissionError ? '请先结束当前任务并处理问题或审批。' : '', onSelect: (id: string): void => { this.selectAgent(id); }, onRefresh: (): void => { this.store.refreshAgentState(); } }) }
    else if (this.sheetKind === 'fork') {
      ForEach([this.forkScope + this.forkBefore + String(this.forkEditing)], (key: string) => {
        ForkPanel({ editing: this.forkEditing, initialText: this.forkText, source: this.forkSource, hasFiles: this.forkHasFiles, busy: this.store.forkBusy, error: this.store.forkError, uncertain: this.store.forkUncertain,
          blocked: this.store.working || !!this.store.pendingSend || !!this.store.interactions.length || !!this.store.permissionError, onCreate: (text: string, reuse: boolean): void => { this.createFork(text, reuse); }, onReview: (): void => { this.navigate('projects'); this.store.refreshSessions(); }, onChecked: (): void => { this.confirmForkReview(); } })
      }, (key: string) => key)
    }
    else if (this.sheetKind === 'usage') { UsagePanel({ usage: this.store.usage, model: this.store.models.find((model: ModelItem) => model.id === this.store.modelID)?.label || this.store.modelID,
      contextLimit: this.store.models.find((model: ModelItem) => model.id === this.store.modelID)?.contextLimit ?? -1, loading: this.store.usageLoading, busy: this.store.compactionBusy, compact: this.store.compaction, error: this.store.usageError,
      blocked: this.store.working || !!this.store.pendingSend || !!this.store.interactions.length || !!this.store.permissionError || this.store.forkBusy || this.store.agentBusy, onRefresh: (): void => { this.store.refreshUsage(); }, onCompact: (): void => { this.confirmCompaction(); } }) }
    else if (this.sheetKind === 'export') { ExportPanel({ busy: this.store.exporting, saving: this.savingExport, count: this.store.exportCount, error: this.store.exportError, notice: this.exportNotice, onExport: (format: string, tools: boolean): void => { this.exportConversation(format, tools); }, onCancel: (): void => { this.store.cancelExport(); } }) }
    else if (this.sheetKind === 'model') { ModelPicker({ models: this.store.models, current: this.store.modelID, busy: this.switchingModel, error: this.store.error, onSelect: (id: string): void => { this.selectModel(id); }, onManage: (): void => { this.toolSheetOpen = false; this.navigate('settings'); } }) }
    else if (this.sheetKind === 'attachment') { AttachmentPreview({ item: this.selectedAttachment, saving: this.savingAttachment, onSave: (item: Attachment): void => { this.saveAttachment(item); }, onCopy: (text: string): void => { this.copy(text); } }) }
    else if (this.sheetKind === 'session') { this.sessionActions() }
    else {
      Column({ space: 8 }) {
        Text('更多功能').fontSize(18).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%').padding({ bottom: 10 })
        Button('待办中心').enabled(!!this.store.connected).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.navigate('pending'); })
        Button('项目与会话').enabled(!!this.store.connected).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.navigate('projects'); })
        Button('代码审查').enabled(!!this.store.directory).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.navigate('review'); })
        Button('模型与接入').enabled(!!this.store.connected).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.navigate('settings'); })
        Button('服务器连接').width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.navigate('connections'); })
        Button('外观').width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.navigate('appearance'); })
        Button('上下文与用量').id('open-usage').enabled(!!this.store.sessionID).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.sheetKind = 'usage'; this.store.refreshUsage(); })
        Button('分叉当前会话').id('open-fork').enabled(!!this.store.sessionID && !this.store.forkBusy).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.openFork(); })
        Button('导出当前会话').id('open-export').enabled(!!this.store.sessionID && !this.savingExport).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.store.exportError = ''; this.exportNotice = ''; this.sheetKind = 'export'; })
        Button('同步当前对话').enabled(!!this.store.sessionID).width('100%').buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.text).onClick(() => { this.toolSheetOpen = false; this.store.sync(); })
      }.padding({ left: 20, right: 20, top: 24, bottom: 20 }).width('100%')
    }
  }
  @Builder
  sessionFilters() {
    Row({ space: 6 }) {
      TextInput({ placeholder: '搜索会话名称', text: this.sessionSearch }).id('session-search').height(36).fontSize(12).backgroundColor(C.field).layoutWeight(1)
        .onChange((value: string) => { this.sessionSearch = value; })
      Button('搜索').id('session-search-server').height(36).fontSize(12).enabled(!this.store.sessionsBusy && !!this.store.directory)
        .onClick(() => { this.store.refreshSessions(false, this.sessionSearch); })
    }.width('100%')
    if (this.store.sessionQuery) { Text('服务器搜索：' + this.store.sessionQuery).fontSize(10).fontColor(C.secondary).maxLines(1).width('100%') }
    Row({ space: 6 }) {
      Button('最近').id('sessions-recent').layoutWeight(1).height(32).fontSize(12).backgroundColor(this.store.showArchived ? Color.Transparent : C.field).fontColor(C.text)
        .onClick(() => { this.store.showArchived = false; if (this.store.sessionQuery) { this.sessionSearch = ''; this.store.refreshSessions(false, ''); } })
      Button('本机归档').id('sessions-archived').layoutWeight(1).height(32).fontSize(12).backgroundColor(this.store.showArchived ? C.field : Color.Transparent).fontColor(C.text)
        .onClick(() => { this.store.showArchived = true; })
      Button('刷新').id('sessions-refresh').height(32).fontSize(12).enabled(!this.store.sessionsBusy).onClick(() => { this.store.refreshSessions(false, this.sessionSearch); })
    }.width('100%')
  }
  @Builder
  sessionRow(session: SessionItem, compact: boolean) {
    Row({ space: 4 }) {
      Column({ space: 4 }) {
        Text((this.store.isPinned(session.id) ? '置顶 · ' : '') + (session.forkType ? '分支 · ' : session.parentID ? '子会话 · ' : '') + session.title).fontSize(compact ? 13 : 16).fontColor(C.text).maxLines(2).width('100%')
        if (this.store.sessionLabel(session.id)) { Text(this.store.sessionLabel(session.id)).fontSize(11).fontColor(C.warning).width('100%') }
      }.id((compact ? 'sidebar-session-' : 'session-') + session.id).alignItems(HorizontalAlign.Start).layoutWeight(1).padding(10).onClick(() => { this.pickSession(session); })
      Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(18).fontColor([C.secondary]) }
        .id('session-actions-' + session.id).width(36).height(36).backgroundColor(Color.Transparent).accessibilityText('管理会话 ' + session.title).onClick(() => { this.manageSession(session); })
    }.width('100%').backgroundColor(session.id === this.store.sessionID ? C.field : compact ? Color.Transparent : C.surface).borderRadius(12)
  }
  @Builder
  sessionPaging() {
    if (this.store.sessionsError) { Text(this.store.sessionsError).fontSize(12).fontColor(C.danger).width('100%') }
    if (this.store.sessionsBusy) { Text('正在读取会话…').fontSize(12).fontColor(C.muted).padding(8) }
    if (this.store.sessionCursor && this.store.sessions.length < 500) { Button('加载更多会话').id('sessions-more').fontSize(12).enabled(!this.store.sessionsBusy).onClick(() => { this.store.refreshSessions(true); }) }
    if (this.store.sessions.length >= 500) { Text('已显示 500 个会话，可用名称搜索服务器历史。').fontSize(11).fontColor(C.muted).padding(8) }
  }
  @Builder
  sessionActions() {
    Column({ space: 14 }) {
      Text('管理会话').fontSize(18).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      TextInput({ text: this.sessionName, placeholder: '会话名称' }).id('session-name').maxLength(200).onChange((value: string) => { this.sessionName = value; })
      Button(this.store.sessionMutationBusy ? '保存中…' : '保存名称').id('session-rename').width('100%').enabled(!this.store.sessionMutationBusy && !this.store.sessionPreferenceBusy && !!this.sessionName.trim())
        .onClick(() => { this.store.renameSession(this.selectedSession.id, this.sessionName).then((saved: boolean) => { if (saved) { this.toolSheetOpen = false; } }); })
      Button(this.store.isPinned(this.selectedSession.id) ? '取消置顶' : '置顶会话').id('session-pin').width('100%').enabled(!this.store.sessionPreferenceBusy && !this.store.sessionMutationBusy)
        .onClick(() => { this.store.setSessionPreference(this.selectedSession.id, !this.store.isPinned(this.selectedSession.id), this.store.isArchived(this.selectedSession.id)); })
      Button(this.store.isArchived(this.selectedSession.id) ? '移回最近会话' : '归档到本机列表').id('session-archive').width('100%').enabled(!this.store.sessionPreferenceBusy && !this.store.sessionMutationBusy)
        .onClick(() => { this.store.setSessionPreference(this.selectedSession.id, this.store.isPinned(this.selectedSession.id), !this.store.isArchived(this.selectedSession.id)); })
      Text('置顶和归档仅影响这台设备。归档保留服务器历史，运行中的任务会继续，待办仍会显示。').fontSize(12).fontColor(C.secondary).width('100%')
      if (this.store.error) { Text(this.store.error).fontSize(12).fontColor(C.danger).width('100%') }
    }.padding(20).width('100%')
  }
  @Builder
  pendingCenter() {
    Column({ space: 12 }) {
      Row() {
        Text('当前服务器 · 所有已知项目').fontSize(13).fontColor(C.secondary).layoutWeight(1)
        Button('刷新').id('pending-refresh').enabled(!this.store.pendingBusy).onClick(() => { this.store.refreshPending(true); })
      }.width('100%')
      NativeSegments({ first: '全部', second: '问题', third: '审批', selected: this.pendingFilter, onSelect: (index: number): void => { this.pendingFilter = index; } })
      if (this.store.pendingError) { Text(this.store.pendingError + '。旧结果已保留，打开会话后重新核对。').fontSize(12).fontColor(C.warning).width('100%') }
      if (this.store.pendingBusy) { Text('正在同步待办…').fontSize(12).fontColor(C.secondary).width('100%') }
      if (!this.store.pendingBusy && !this.store.pendingError && !this.store.pendingItems.length) { Text('当前没有待处理的问题或审批。').fontSize(14).fontColor(C.secondary).padding(24) }
      List({ space: 10 }) {
        ForEach(this.store.pendingItems.filter((p: PendingItem) => this.pendingFilter === 0 || p.kind === (this.pendingFilter === 1 ? 'form' : 'permission')), (item: PendingItem) => {
          ListItem() {
            Column({ space: 6 }) {
              Text((item.stale ? '待确认 · ' : '') + (item.kind === 'form' ? '需要回答' : '需要审批')).fontSize(11).fontColor(C.warning).width('100%')
              Text(item.title).fontSize(16).fontColor(C.text).maxLines(3).width('100%')
              Text(item.sessionTitle || item.sessionID).fontSize(12).fontColor(C.secondary).width('100%')
              Text(item.directory).fontSize(11).fontColor(C.muted).maxLines(2).width('100%')
              Button('打开会话处理').id('pending-open-' + item.kind + '-' + item.id).enabled(!this.store.busy)
                .onClick(() => { this.follow = true; this.store.openPending(item); })
            }.padding(16).backgroundColor(C.surface).borderRadius(14).width('100%')
          }
        }, (item: PendingItem) => pendingKey(item) + item.title + item.sessionTitle + String(item.stale))
      }.layoutWeight(1).width('100%')
    }.padding(20).height('100%').width('100%')
  }
  @Builder
  appearanceSettings() {
    Column({ space: 20 }) {
      Text('选择此应用的显示方式').fontSize(14).fontColor(C.secondary).width('100%')
      NativeSegments({ first: '跟随系统', second: '浅色', third: '深色',
        selected: this.appearanceMode === 'dark' ? 2 : this.appearanceMode === 'light' ? 1 : 0,
        onSelect: (index: number): void => { this.changeAppearance(index === 2 ? 'dark' : index === 1 ? 'light' : 'system'); } }).id('appearance-segments')
      Text('当前外观：' + (this.appearanceMode === 'dark' ? '深色' : this.appearanceMode === 'light' ? '浅色' : '跟随系统')).fontSize(13).fontColor(C.secondary).width('100%')
      Text('跟随系统会自动适配设备的深浅色设置。').fontSize(13).fontColor(C.secondary).width('100%')
    }.padding(20).width('100%')
  }
  @Builder
  toolDetails() {
    Column({ space: 14 }) {
      Row({ space: 10 }) {
        Text(this.selectedTool.name).fontSize(18).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1)
        Text(toolStatus(this.selectedTool.status)).fontSize(12).fontColor(C.secondary)
      }.padding({ right: 38 }).width('100%')
      Scroll() {
        Column({ space: 14 }) {
          Text('调用参数').fontSize(12).fontWeight(FontWeight.Bold).fontColor(C.secondary).width('100%')
          Text(this.selectedTool.input.slice(0, 12000) || '无参数').id('tool-request').fontFamily('monospace').fontSize(12).lineHeight(21).fontColor(C.secondary).padding(14).backgroundColor(C.field).borderRadius(12).copyOption(CopyOptions.InApp).width('100%')
          Text('执行结果').fontSize(12).fontWeight(FontWeight.Bold).fontColor(C.secondary).width('100%')
          Text(this.selectedTool.output.slice(0, 16000) || (this.selectedTool.status === 'running' ? '正在执行，结果会自动更新…' : '暂无文本结果')).id('tool-response')
            .fontFamily('monospace').fontSize(12).lineHeight(21).fontColor(C.secondary).padding(14).backgroundColor(C.field).borderRadius(12).copyOption(CopyOptions.InApp).width('100%')
          if (this.selectedTool.input.length > 12000 || this.selectedTool.output.length > 16000) { Text('较长内容已截断，完整记录保留在服务器。').fontSize(11).fontColor(C.secondary) }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
    }.id('tool-details').padding({ left: 20, right: 20, top: 24, bottom: 20 }).width('100%').height('100%')
  }
  @Builder
  chatTitle() {
    Row({ space: 8 }) {
      Blank().width(this.sidebarOpen ? 0 : 56).height(40)
      if (this.store.models.length) {
        Button(this.store.models.find((model: ModelItem) => model.id === this.store.modelID)?.label || '选择模型', { type: ButtonType.Capsule }).id('model-select')
          .fontSize(13).fontColor(C.text).backgroundColor(C.field).height(36).labelStyle({ maxLines: 1, overflow: TextOverflow.Ellipsis })
          .width(Math.min(240, Math.max(100, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - (this.sidebarOpen ? 168 : 224))))
          .enabled(!!this.store.sessionID && !this.store.busy).accessibilityText('选择对话模型')
          .onClick(() => { this.store.error = ''; this.sheetKind = 'model'; this.toolSheetOpen = true; })
      } else { Text('OpenCode').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1) }
      Blank().layoutWeight(1)
    }.width(Math.max(180, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - 104)).height(56)
  }
  @Builder
  errorBanner() {
    if (this.store.error) {
      Row({ space: 8 }) {
        Text(this.store.error).fontSize(12).fontColor(C.danger).layoutWeight(1).maxLines(3)
        if (this.store.connected && this.store.status !== '实时连接' && this.store.status !== '已连接') { Button('重新连接').fontSize(12).enabled(!this.store.busy).onClick(() => { this.store.reconnect(); }) }
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(14).fontColor([C.secondary]) }
          .width(32).height(32).backgroundColor(Color.Transparent).accessibilityText('关闭提示').onClick(() => { this.store.error = ''; })
      }.padding({ left: 20, right: 12, top: 6, bottom: 6 }).backgroundColor(C.danger_bg).width('100%')
    }
  }
  @Builder
  destination(name: string) {
    NavDestination() {
      Column() {
        this.errorBanner()
        if (name === 'connections') { this.connections() }
        else if (name === 'projects') { this.projects() }
        else if (name === 'pending') { this.pendingCenter() }
        else if (name === 'appearance') { this.appearanceSettings() }
        else if (name === 'settings') { ProviderSettings({ store: this.store.providers, onOpenLink: (url: string): void => { this.openLink(url); } }) }
        else { this.review() }
      }.height('100%').width('100%').backgroundColor(C.page)
    }.id('native-destination').title({ main: this.pageTitle(name), sub: this.store.status })
      .systemBarStyle({ statusBarContentColor: this.darkAppearance ? '#F0F2F6' : '#18202C' })
      .backgroundColor(C.page).onBackPressed((): boolean => { this.store.pane = 'chat'; return true; })
  }
  build() {
    SideBarContainer(this.wide ? SideBarContainerType.Embed : SideBarContainerType.Overlay) {
      this.sidebar(this.wide ? 280 : Math.min(304, this.viewportWidth * 0.84))
      Navigation(this.navigation) {
        Column({ space: 0 }) { this.errorBanner(); this.chat() }.height('100%').width('100%').backgroundColor(C.surface)
      }.id('native-navigation').title(this.chatTitle()).titleMode(NavigationTitleMode.Mini)
        .systemBarStyle({ statusBarContentColor: this.darkAppearance ? '#F0F2F6' : '#18202C' })
        .menus([{ value: '新建对话', symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
          isEnabled: !this.store.busy, action: (): void => { this.newChat(); } },
          { value: '更多功能', symbolIcon: new SymbolGlyphModifier($r('sys.symbol.ellipsis_circle')), action: (): void => { this.showActions(); } }])
        .navDestination(this.destination).mode(NavigationMode.Stack).hideBackButton(true)
        .onNavBarStateChange((visible: boolean) => { if (visible && !this.navigation.getAllPathName().length && this.store.pane !== 'chat') { this.store.pane = 'chat'; } })
        .backgroundColor(C.surface).height('100%').width('100%')
    }.id('native-sidebar-container').showSideBar(this.sidebarOpen).showControlButton(!this.sidebarOpen && this.store.pane === 'chat')
      .controlButton({ left: 16, top: 16, width: 24, height: 24 })
      .sideBarWidth(this.wide ? 280 : Math.min(304, this.viewportWidth * 0.84)).minSideBarWidth(220).maxSideBarWidth(320)
      .divider({ strokeWidth: 1, color: C.separator }).onChange((show: boolean) => { this.sidebarOpen = show; })
      .width('100%').height('100%').backgroundColor(C.page).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, newArea: Area) => { this.viewportWidth = Number(newArea.width); const wide = this.viewportWidth >= 840; if (this.wide !== wide) { this.wide = wide; this.sidebarOpen = wide; } })
      .bindSheet($$this.toolSheetOpen, this.sheetContent(), { height: this.sheetKind === 'tool' || this.sheetKind === 'attachment' || this.sheetKind === 'model' || this.sheetKind === 'agent' || this.sheetKind === 'fork' || this.sheetKind === 'usage' ? SheetSize.LARGE : SheetSize.FIT_CONTENT, showClose: true, onDisappear: (): void => { if (this.store.exporting) { this.store.cancelExport(); } } })
  }
}
