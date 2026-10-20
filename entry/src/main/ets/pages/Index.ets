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
import { GlassPanel, StatusLed } from '../components/Material';
import { HarmonyColors as C } from '../presentation/HarmonyColors';
import { common } from '@kit.AbilityKit';
import { AppStore } from '../presentation/AppStore';
import { ConversationMessage } from '../components/ConversationMessage';
import { ApprovalPreviewView } from '../components/ApprovalPreview';
import { ProviderSettings } from '../components/ProviderSettings';
import { FormFieldsView } from '../components/FormFieldsView';
import { MessageDataSource } from '../presentation/MessageDataSource';
import { NotificationCenter } from '../presentation/NotificationCenter';
import { ReminderSettingsView } from '../components/ReminderSettingsView';
import { NotificationTarget, ReminderGroup, parseNotificationLaunch } from '../domain/Notifications';
import { ServerConfig, ProjectItem, SessionItem, ChatMessage, ToolItem, Interaction, FormField, Choice,
  ModelItem, FileItem, DiffItem, DiffLine, TurnItem, PendingItem, pendingKey, diffKey, parseDiff, visibleFormFields, messageKey, interactionKey, reasoningInProgress, toolStatus } from '../domain/Core';

@Entry
@Component
struct Index {
  @State @Watch('storeChanged') store: AppStore = new AppStore();
  @StorageLink('appForeground') @Watch('foregroundChanged') foreground: boolean = true;
  @StorageLink('notificationLaunch') @Watch('notificationLaunchChanged') notificationLaunch: string = '';
  @State reminders: NotificationCenter = new NotificationCenter();
  @State quietNotice: string = '';
  private quietSeq: number = 0;
  private consumingLaunch: boolean = false;
  private appReady: boolean = false;
  private pendingLaunch: NotificationTarget | undefined = undefined;
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
    this.forkHasFiles = !!message?.files?.length; this.forkScope = this.store.exportScope(); this.store.forkError = ''; this.openSheet('fork');
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
    const scope = this.store.connected + '/' + this.store.sessionID; this.selectedAttachment = item; this.openSheet('attachment');
    const preview = await this.store.attachmentPreview(item);
    if (scope === this.store.connected + '/' + this.store.sessionID && this.sheetKind === 'attachment' && this.toolSheetOpen) { this.selectedAttachment = preview; }
  }
  @StorageLink('appearanceMode') appearanceMode: string = 'system';
  @StorageLink('appearanceDark') darkAppearance: boolean = false;
  @State @Watch('conversationVisibilityChanged') sidebarOpen: boolean = false;
  @State @Watch('conversationVisibilityChanged') wide: boolean = false;
  @State viewportWidth: number = 400;
  @State sessionSearch: string = '';
  @State pendingFilter: number = 0;
  @State selectedSession: SessionItem = { id: '', title: '', directory: '', status: '', model: '' };
  @State sessionName: string = '';
  private viewMessages: ChatMessage[] = [];
  private viewInteractions: Interaction[] = [];
  private scrollTimer: number = -1;
  @State @Watch('conversationVisibilityChanged') toolSheetOpen: boolean = false;
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
    if (context) {
      const ability = context as common.UIAbilityContext;
      this.reminders.attachContext(ability);
      this.reminders.load();
      this.store.attachNotifier(this.reminders, this.foreground);
      this.store.init(context as common.Context).then((): void => { this.appReady = true; this.consumeNotificationLaunch(); this.tryConsumeLaunch(); });
    }
  }
  aboutToDisappear(): void { if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; } this.store.setActive(false); }
  onBackPress(): boolean { if (this.sidebarOpen) { this.sidebarOpen = false; return true; } return false; }
  private storeChanged(): void {
    if (this.store.reminderQuietSeq !== this.quietSeq) {
      this.quietSeq = this.store.reminderQuietSeq;
      this.quietNotice = this.store.reminderQuiet ? this.reminderQuietText(this.store.reminderQuiet) : '';
    }
    this.tryConsumeLaunch();
    this.syncNavigation();
    const session = this.store.connected + '/' + this.store.sessionID;
    if (session !== this.viewSession) { this.viewSession = session; this.viewContent = ''; this.sessionSearch = ''; this.reasoningOpen = []; this.reasoningClosed = []; this.activeReasoning = []; if (this.sheetKind === 'tool' || this.sheetKind === 'session' || this.sheetKind === 'attachment' || this.sheetKind === 'model' || this.sheetKind === 'agent' || this.sheetKind === 'export' || this.sheetKind === 'fork' || this.sheetKind === 'usage') { this.toolSheetOpen = false; } this.follow = true; this.quietNotice = ''; this.reminders.refreshPermission(); }
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
  private conversationVisibilityChanged(): void { this.store.conversationVisible = (!this.sidebarOpen || this.wide) && !this.toolSheetOpen; }
  private showActions(): void { this.openSheet('actions'); }
  private dismissKeyboard(): void { try { this.getUIContext().getFocusController().clearFocus(); } catch (_) { } }
  private openSheet(kind: string): void { this.dismissKeyboard(); this.sheetKind = kind; this.toolSheetOpen = true; }
  private changeAppearance(mode: string): void {
    const context = this.getUIContext().getHostContext();
    if (context) { Appearance.save(context as common.Context, mode).catch(() => { this.store.error = '外观设置未保存，请稍后重试。'; }); }
  }
  private pageTitle(name: string): string {
    return name === 'pending' ? '待办中心' : name === 'connections' ? '服务器连接' : name === 'projects' ? '项目与会话' : name === 'settings' ? '模型与接入' : name === 'appearance' ? '外观' : name === 'reminders' ? '任务提醒' : '代码审查';
  }
  private modelLabel(): string {
    const model = this.store.models.find((item: ModelItem) => item.id === this.store.modelID);
    return model?.label || this.store.modelID || '选择模型';
  }
  private toolLabel(name: string): string {
    switch (name) {
      case 'read': case 'read_file': return '读取文件';
      case 'edit': case 'edit_file': return '修改文件';
      case 'write': return '写入文件';
      case 'bash': return '执行命令';
      case 'glob': return '搜索文件';
      case 'grep': return '检索内容';
      case 'task': return '子任务';
      default: return name;
    }
  }
  private isLargeSheet(): boolean {
    return this.sheetKind === 'tool' || this.sheetKind === 'attachment' || this.sheetKind === 'model'
      || this.sheetKind === 'agent' || this.sheetKind === 'fork' || this.sheetKind === 'usage';
  }
  // One tinted glass surface for every bindSheet so sheets, drawer and composer share the same tone.
  @Builder
  sheetSurface() {
    if (this.isLargeSheet()) {
      Column() {
        this.sheetContent()
      }
      .width('100%').height('100%').backgroundColor(C.sheet_tint)
      .border({ width: { top: 1 }, color: C.glass_stroke })
      .borderRadius({ topLeft: 20, topRight: 20 }).clip(true)
    } else {
      Column() {
        this.sheetContent()
      }
      .width('100%').backgroundColor(C.sheet_tint)
      .border({ width: { top: 1 }, color: C.glass_stroke })
      .borderRadius({ topLeft: 20, topRight: 20 }).clip(true)
    }
  }
  private serverName(): string {
    const server = this.store.servers.find((item: ServerConfig) => item.id === this.store.connected);
    return server?.name || '未连接';
  }
  private foregroundChanged(): void {
    this.reminders.refreshPermission();
    if (!this.foreground) {
      // Best effort only: keep the already-open stream briefly if the user wants
      // reminders and notifications are authorized. The OS may freeze the process
      // at any time; there is no background service, polling or keep-alive.
      if (this.reminders.backgroundWanted()) { this.store.beginBackgroundReminderWindow(20000); }
      else { this.store.setActive(false); }
      return;
    }
    this.store.cancelBackgroundReminderWindow();
    this.store.setActive(true);
  }
  private notificationLaunchChanged(): void { this.consumeNotificationLaunch(); }
  private consumeNotificationLaunch(): void {
    if (!this.notificationLaunch) { return; }
    const target = parseNotificationLaunch(this.notificationLaunch);
    this.notificationLaunch = ''; this.pendingLaunch = target; this.tryConsumeLaunch();
  }
  private tryConsumeLaunch(): void {
    const target = this.pendingLaunch; if (!target || !this.appReady || this.consumingLaunch || this.store.busy || this.store.targetBusy || !this.store.servers.length) { return; }
    this.pendingLaunch = undefined; this.consumingLaunch = true; this.follow = true;
    this.store.openNotificationTarget(target).finally((): void => { this.consumingLaunch = false; this.tryConsumeLaunch(); });
  }
  private reminderQuietText(kind: string): string {
    if (kind === 'completed') { return '当前会话任务已完成'; }
    if (kind === 'failed') { return '当前会话任务未成功'; }
    if (kind === 'question') { return '当前会话有待回答的问题'; }
    if (kind === 'approval') { return '当前会话有待处理的审批'; }
    return '当前会话有新的任务状态';
  }

  private copy(text: string): void {
    copyText(text).then(() => { this.getUIContext().getPromptAction().showToast({ message: '已复制' }); })
      .catch(() => { this.store.error = '复制失败，请稍后重试'; });
  }
  private manageSession(session: SessionItem): void {
    this.selectedSession = session; this.sessionName = session.title; this.openSheet('session');
  }
  private openLink(url: string): void {
    if (!/^https:\/\/[^/?#\s@]+(?:[/?#][^\s]*)?$/.test(url)) { this.store.error = '仅支持不含账号密码的 HTTPS 授权地址'; return; }
    const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
    if (context) { context.openLink(url).catch(() => { this.store.error = '无法打开浏览器，请稍后重试'; }); }
  }
  @Builder
  badge(label: string, color: ResourceColor = C.chip) {
    Text(label).fontSize(9.5).fontFamily('monospace').letterSpacing(0.6).fontColor(C.secondary)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(color).border({ width: 1, color: C.separator }).borderRadius(4)
  }
  @Builder
  heading(kicker: string, title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(kicker).fontSize(9.5).fontWeight(FontWeight.Medium).letterSpacing(1.6).fontFamily('monospace')
        .fontColor(C.muted).width('100%')
      Text(title).fontSize(23).fontWeight(FontWeight.Bold).letterSpacing(-0.4).fontColor(C.text).width('100%')
      if (subtitle) {
        Text(subtitle).fontSize(12.5).fontColor(C.secondary).lineHeight(20).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 14 })
  }
  @Builder
  sectionLabel(label: string) {
    Text(label).fontSize(9.5).fontWeight(FontWeight.Medium).letterSpacing(1.3)
      .fontColor(C.muted).width('100%').margin({ top: 18, bottom: 2 })
  }
  @Builder
  homeActionRow(icon: Resource, title: string, meta: string, enabled: boolean, action: () => void) {
    Row({ space: 10 }) {
      SymbolGlyph(icon).fontSize(16).fontColor([enabled ? C.secondary : C.muted])
      Text(title).fontSize(12.5).fontColor(enabled ? C.text : C.muted).layoutWeight(1)
      Text(meta).fontSize(11).fontColor(C.muted).maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 156 })
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
    }.width('100%').height(43).border({ width: { top: 1 }, color: C.separator })
      .onClick(() => { if (enabled) { action(); } })
  }
  @Builder
  homeWelcome() {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Text(this.store.directory ? this.projectName().toUpperCase() : 'OPENCODE')
          .fontSize(9.5).fontFamily('monospace').letterSpacing(1.4).fontColor(C.muted).layoutWeight(1).maxLines(1)
        Row({ space: 6 }) {
          StatusLed({ color: this.store.connected ? C.success : C.muted })
          Text(this.store.connected ? 'CONNECTED' : 'OFFLINE').fontSize(9.5).fontFamily('monospace')
            .letterSpacing(1).fontColor(C.secondary)
        }
      }.width('100%')
      Text(this.store.connected ? '继续工作' : '开始使用').fontSize(25).fontWeight(FontWeight.Bold)
        .letterSpacing(-0.3).fontColor(C.text).margin({ top: 12 })
      Text(this.store.connected && this.store.directory
        ? '选择最近会话，或直接开始新的任务。'
        : '连接你的 OpenCode 服务器，选择一个项目开始对话。')
        .fontSize(12.5).fontColor(C.muted).lineHeight(19).margin({ top: 6 })
      Row({ space: 8 }) {
        Button(!this.store.connected ? '连接服务器' : !this.store.directory ? '选择项目' : '新建对话', { type: ButtonType.Normal })
          .id('welcome-action').height(36).fontSize(12.5).fontWeight(FontWeight.Medium)
          .backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(9).enabled(!this.store.busy)
          .onClick(() => { this.newChat(); })
        Button(this.store.connected ? '打开项目' : '服务器设置', { type: ButtonType.Normal })
          .height(32).fontSize(12).backgroundColor(Color.Transparent).fontColor(C.text).borderRadius(8)
          .border({ width: 1, color: C.separator }).enabled(!this.store.busy)
          .onClick(() => { this.navigate(this.store.connected ? 'projects' : 'connections'); })
      }.width('100%').margin({ top: 18 })
      if (this.store.connected && this.store.directory && this.store.recentSessions().length) {
        this.sectionLabel('最近会话')
        ForEach(this.store.recentSessions(), (session: SessionItem) => {
          Row({ space: 10 }) {
            Column({ space: 3 }) {
              Text(session.title || '未命名会话').fontSize(12.5).fontColor(C.text).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
              Text(session.id).fontSize(9.5).fontFamily('monospace').fontColor(C.muted).maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (this.store.sessionLabel(session.id)) {
              Text(this.store.sessionLabel(session.id)).fontSize(9.5).fontFamily('monospace')
                .letterSpacing(0.6).fontColor(C.warning)
            }
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
          }.id('recent-session-' + session.id).width('100%').constraintSize({ minHeight: 46 }).padding({ left: 2, right: 2, top: 6, bottom: 6 })
            .border({ width: { top: 1 }, color: C.separator })
            .onClick(() => { this.pickSession(session); })
        }, (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id))
      }
      if (this.store.connected) {
        this.sectionLabel('工作区')
        this.homeActionRow($r('sys.symbol.doc_text'), '代码审查',
          this.store.directory ? '工作区 Diff · 任务快照' : '需要先选择项目', !!this.store.directory,
          (): void => { this.navigate('review'); })
        this.homeActionRow($r('sys.symbol.code_square'), '模型与接入',
          this.store.connected ? this.modelLabel() : '连接服务器后可用', !!this.store.connected,
          (): void => { this.navigate('settings'); })
      }
      Blank()
      Row({ space: 8 }) {
        Text('SERVER').fontSize(9.5).fontFamily('monospace').letterSpacing(1).fontColor(C.muted)
        Text(this.serverName()).fontSize(11).fontColor(C.secondary)
          .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
        Text('MODEL').fontSize(9.5).fontFamily('monospace').letterSpacing(1).fontColor(C.muted)
        Text(this.store.modelID ? this.modelLabel() : '—').fontSize(11)
          .fontColor(C.secondary).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
      }.width('100%').padding({ top: 11, bottom: 4 })
        .border({ width: { top: 1 }, color: C.separator })
    }.width('100%').height('100%').alignItems(HorizontalAlign.Start).padding({ left: 2, right: 2, top: 16, bottom: 12 })
  }

  @Builder
  connections() {
    Scroll(this.connectionScroller) {
      Column({ space: 12 }) {
        this.heading('SERVER / CONNECTION', '连接管理', '添加或切换你的 OpenCode 服务器；凭据保存于系统安全资产。')
        ForEach(this.store.servers, (server: ServerConfig) => {
          Column({ space: 10 }) {
            Row() {
              Column({ space: 4 }) {
                Text(server.name).fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(C.text)
                Text(server.url).fontSize(10).fontFamily('monospace').fontColor(C.muted).maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.store.connected === server.id) {
                Row({ space: 5 }) {
                  StatusLed({ color: C.success })
                  Text('CONNECTED').fontSize(9.5).fontFamily('monospace').letterSpacing(0.8).fontColor(C.success)
                }
              }
            }
            Row({ space: 8 }) {
              Button('连接', { type: ButtonType.Normal }).id('connect-server-' + server.id).backgroundColor(C.btn).fontColor(C.btn_text)
                .fontSize(12.5).borderRadius(8).height(36).layoutWeight(1).enabled(!this.store.busy && !this.store.serverSaving)
                .onClick(() => { this.store.connect(server).then(() => { if (this.store.connected) { this.store.pane = 'chat'; } }); })
              Button('编辑', { type: ButtonType.Normal }).id('edit-server-' + server.id).height(32).fontSize(12)
                .backgroundColor(Color.Transparent).fontColor(C.text).borderRadius(8).border({ width: 1, color: C.separator })
                .enabled(!this.store.serverSaving && !this.store.busy)
                .onClick(() => { this.store.editServer(server); setTimeout(() => { this.connectionScroller.scrollEdge(Edge.Bottom); }, 50); })
              Button('移除', { type: ButtonType.Normal }).id('remove-server-' + server.id).height(32).fontSize(12)
                .backgroundColor(Color.Transparent).fontColor(C.danger).borderRadius(8).border({ width: 1, color: C.separator })
                .enabled(!this.store.serverSaving && !this.store.busy).onClick(() => { this.confirmRemoveServer(server); })
            }
          }.id('server-profile-' + server.id).padding(14).backgroundColor(C.surface)
            .border({ width: 1, color: C.separator }).borderRadius(12).width('100%')
        }, (server: ServerConfig) => server.id + server.name + server.url + server.username + String(server.id === this.store.connected))
        Column({ space: 12 }) {
          Text(this.store.serverEditID ? '编辑连接' : '添加服务器').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          TextInput({ placeholder: '连接名称，例如：我的开发服务器', text: this.store.serverName }).id('server-name').maxLength(80).enabled(!this.store.serverSaving && !this.store.busy)
            .fontSize(13).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverName = value; })
            .backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8).height(40)
          TextInput({ placeholder: 'https://opencode.example.com', text: this.store.serverUrl }).id('server-url').maxLength(2048).enabled(!this.store.serverSaving && !this.store.busy)
            .fontSize(13).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverUrl = value; })
            .backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8).height(40)
          Row({ space: 10 }) {
            TextInput({ placeholder: 'API 用户名', text: this.store.serverUser }).id('server-user').maxLength(120).enabled(!this.store.serverSaving && !this.store.busy)
              .fontSize(13).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverUser = value; })
              .layoutWeight(1).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8)
            TextInput({ placeholder: this.store.serverEditID ? '密码留空保留原密码' : 'API 密码', text: this.store.serverPassword }).id('server-password').maxLength(2048).enabled(!this.store.serverSaving && !this.store.busy).type(InputType.Password)
              .fontSize(13).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverPassword = value; })
              .layoutWeight(1).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8)
          }
          Row({ space: 8 }) {
            Checkbox({ name: 'allow-http' }).id('allow-http').enabled(!this.store.serverSaving && !this.store.busy).select(this.store.allowHttp).selectedColor(C.accent).width(22).height(22).responseRegion({ x: -9, y: -9, width: 40, height: 40 })
              .onChange((value: boolean) => { this.store.allowHttp = value; })
            Text('允许 HTTP（仅可信局域网或本地隧道）').id('allow-http-label').fontSize(12.5).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 40 })
              .onClick(() => { if (!this.store.serverSaving && !this.store.busy) { this.store.allowHttp = !this.store.allowHttp; } })
          }.width('100%')
          Row({ space: 8 }) {
            Checkbox({ name: 'dedicated-trust' }).id('dedicated-trust').enabled(!this.store.serverSaving && !this.store.busy).select(this.store.useDedicatedTrust)
              .selectedColor(C.accent).width(22).height(22).responseRegion({ x: -9, y: -9, width: 40, height: 40 })
              .onChange((value: boolean) => { this.store.useDedicatedTrust = value; })
            Text('使用专用服务器证书（IP 临时入口）').id('dedicated-trust-label').fontSize(12.5).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 40 })
              .onClick(() => { if (!this.store.serverSaving && !this.store.busy) { this.store.useDedicatedTrust = !this.store.useDedicatedTrust; } })
          }.width('100%')
          if (this.store.serverEditID) {
            Row({ space: 8 }) {
              Checkbox().id('server-clear-password').select(this.store.clearServerPassword).width(22).height(22).responseRegion({ x: -9, y: -9, width: 40, height: 40 }).enabled(!this.store.serverSaving)
                .onChange((value: boolean) => { this.store.clearServerPassword = value; })
              Text('清除已保存密码').id('server-clear-password-label').fontSize(12.5).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 40 })
              .onClick(() => { if (!this.store.serverSaving && !this.store.busy) { this.store.clearServerPassword = !this.store.clearServerPassword; } })
            }.width('100%')
            Text('修改地址或账号会清理此连接旧的本机会话位置、书签与模型偏好。密码留空会保留原密码。').fontSize(10).fontColor(C.muted).width('100%')
            Button('取消编辑').id('server-cancel-edit').height(30).fontSize(11).buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.secondary)
              .enabled(!this.store.serverSaving).onClick(() => { this.store.resetServerForm(); this.store.error = ''; this.store.serverNotice = ''; })
          }
          if (this.store.serverNotice) { Text(this.store.serverNotice).id('server-notice').fontSize(11).fontColor(C.secondary).width('100%') }
          Button(this.store.serverSaving ? '正在保存…' : '保存并连接', { type: ButtonType.Normal }).id('connect-button')
            .width('100%').height(36).borderRadius(8).backgroundColor(C.btn).fontColor(C.btn_text).fontSize(12.5).fontWeight(FontWeight.Medium)
            .enabled(!this.store.busy && !this.store.serverSaving)
            .onClick(() => { this.store.saveServer().then((saved: boolean) => { if (saved && this.store.connected) { this.store.pane = 'chat'; } }); })
        }.padding(16).backgroundColor(C.surface).border({ width: 1, color: C.separator }).borderRadius(12).width('100%')
        Text('支持 OpenCode V2 · 凭据存储在系统安全资产中').fontSize(11).fontColor(C.muted).margin({ bottom: 22 })
      }.padding({ left: 18, right: 18 }).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }

  @Builder
  projects() {
    Scroll() {
      Column({ space: 10 }) {
        this.heading('WORKSPACE / PROJECT', '选择项目', '选择一个仓库，继续对话或开始新的任务。')
        ForEach(this.store.projects, (project: ProjectItem) => {
          Row({ space: 11 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([C.secondary])
            }.width(30).height(30).backgroundColor(C.field).borderRadius(8)
            Column({ space: 3 }) {
              Text(project.name || '项目').fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(C.text)
              Text(project.directory).fontSize(9.5).fontFamily('monospace').fontColor(C.muted).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (project.directory === this.store.directory) { StatusLed({ color: C.accent }) }
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
          }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(project.directory === this.store.directory ? C.chip : C.surface)
            .border({ width: 1, color: project.directory === this.store.directory ? C.accent_soft : C.separator })
            .borderRadius(10).onClick(() => { this.dismissKeyboard(); this.store.selectProject(project.directory); })
        }, (project: ProjectItem) => project.id + project.directory)
        Row({ space: 8 }) {
          TextInput({ placeholder: '服务器已有工作目录的绝对路径', text: this.store.manualPath }).id('project-path')
            .fontSize(11).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.manualPath = value; })
            .layoutWeight(1).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8).height(36)
          Button('打开', { type: ButtonType.Normal }).id('open-project').backgroundColor(C.field).fontColor(C.text)
            .fontSize(12).borderRadius(8).height(32).border({ width: 1, color: C.separator }).enabled(!this.store.busy)
            .onClick(() => { this.store.selectProject(this.store.manualPath); })
        }.margin({ top: 6 })
        if (this.store.directory) {
          Row({ space: 8 }) {
            Text('会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1)
            Button('新建对话', { type: ButtonType.Normal }).id('new-session').backgroundColor(C.btn).fontColor(C.btn_text)
              .fontSize(12.5).fontWeight(FontWeight.Medium).borderRadius(8).height(36).enabled(!this.store.busy)
              .onClick(() => { this.store.createSession(); })
          }.margin({ top: 14 }).width('100%')
          this.sessionFilters()
          ForEach(this.store.sessionRows(), (session: SessionItem) => { this.sessionRow(session, false) },
            (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id) + String(this.store.isPinned(session.id)))
          this.sessionPaging()
          if (this.store.sessions.length === 0) { Text('还没有会话，创建第一个任务。').fontSize(11).fontColor(C.muted).padding(20) }
        }
      }.padding(18).width('100%')
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
    this.dismissKeyboard(); this.toolSheetOpen = false; this.sidebarOpen = false;
    if (pane === 'reminders') { this.store.pane = 'reminders'; this.reminders.load(); }
    else if (pane === 'settings') { this.store.openSettings(); }
    else if (pane === 'pending') { this.store.pane = 'pending'; this.store.refreshPending(true); }
    else if (pane === 'review') { this.store.openReview(); }
    else { this.store.pane = pane; }
  }
  private newChat(): void {
    this.dismissKeyboard(); this.sidebarOpen = false; this.follow = true;
    if (!this.store.connected) { this.navigate('connections'); }
    else if (!this.store.directory) { this.navigate('projects'); }
    else { this.store.createSession(); }
  }
  private projectName(): string { return this.store.directory.split('/').filter((value: string) => !!value).pop() || '选择项目'; }
  private async pickSession(session: SessionItem): Promise<void> { this.dismissKeyboard(); this.sidebarOpen = false; this.follow = true; await this.store.openSession(session); }
  @Builder
  messageCard(message: ChatMessage) {
    ConversationMessage({ message: message, thinking: reasoningInProgress(message), reasoningExpanded: this.reasoningExpanded(message),
      onFork: (edit: boolean): void => { this.openFork(message, edit); }, onToggleReasoning: (): void => { this.toggleReasoning(message); },
      onTool: (tool: ToolItem): void => { this.follow = false; this.selectedTool = tool; this.openSheet('tool'); },
      onAttachment: (item: Attachment): void => { this.openAttachment(item); }, onOpenLink: (url: string): void => { this.openLink(url); }, onCopy: (text: string): void => { this.copy(text); } })
  }
  @Builder
  interactionCard(item: Interaction) {
    Column({ space: 10 }) {
      Row({ space: 6 }) {
        StatusLed({ color: item.kind === 'form' ? C.accent : C.warning })
        Text(item.kind === 'form' ? '需要你的回答' : '等待操作审批').fontSize(9.5).fontFamily('monospace')
          .letterSpacing(0.8).fontColor(item.kind === 'form' ? C.accent : C.warning)
        Blank()
        Text(this.store.itemState(item.id) === 'submitting' ? '提交中…' : this.store.itemState(item.id) === 'error' ? '待核对' : '待处理')
          .fontSize(9.5).fontFamily('monospace').fontColor(C.muted)
      }.width('100%')
      Text(item.title).fontSize(13.5).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      if (item.detail) {
        Text(item.detail).fontSize(9.5).fontFamily('monospace').fontColor(C.secondary)
          .copyOption(CopyOptions.InApp).width('100%')
      }
      if (item.kind === 'permission' && item.approval) {
        ApprovalPreviewView({ preview: item.approval, onReview: (): void => { this.follow = false; } })
      }
      FormFieldsView({ fields: this.store.currentFields(item.id),
        onChange: (key: string, value: string, multiple: boolean): void => { this.follow = false; this.store.updateField(item.id, key, value, multiple); },
        onOpenLink: (url: string): void => { this.openLink(url); } }).enabled(this.store.itemState(item.id) !== 'submitting')
      Row({ space: 8 }) {
        Button(item.kind === 'form' ? '提交回答' : '批准一次', { type: ButtonType.Normal }).id('interaction-submit-' + item.id)
          .backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(7).height(32).fontSize(12).layoutWeight(1)
          .enabled(this.store.itemState(item.id) !== 'submitting' && (item.kind === 'form' || this.store.canApprove(item.id)))
          .onClick(() => { this.follow = true; this.store.reply(item); })
        Button(item.kind === 'form' ? '取消' : '拒绝', { type: ButtonType.Normal }).id('interaction-reject-' + item.id)
          .backgroundColor(Color.Transparent).fontColor(C.secondary).borderRadius(7).height(32).fontSize(12)
          .border({ width: 1, color: C.separator })
          .enabled(this.store.itemState(item.id) !== 'submitting')
          .onClick(() => { this.follow = true; this.store.reply(item, true); })
      }.width('100%')
    }.id('interaction-card-' + item.id).padding(14).backgroundColor(C.surface)
      .border({ width: 1, color: C.separator }).borderRadius(10).width('100%')
  }

  @Builder
  chat() {
    Column({ space: 0 }) {
      if (this.store.connected) {
        Row({ space: 8 }) {
          Text(this.store.sessionTitle || '新对话').fontSize(11).fontColor(C.muted).maxLines(1).layoutWeight(1)
          if (this.store.sessionID) {
            Button(this.store.agents.find((a: AgentItem) => a.id === this.store.agentID)?.name || this.store.agentID || '默认 Agent', { type: ButtonType.Normal })
              .id('agent-select').fontSize(12.5).fontColor(C.secondary).height(40)
              .labelStyle({ maxLines: 1, overflow: TextOverflow.Ellipsis })
              .constraintSize({ maxWidth: Math.min(166, this.viewportWidth * 0.46) }).padding({ left: 8, right: 8 })
              .backgroundColor(Color.Transparent).borderRadius(8).accessibilityText('选择会话 Agent')
              .onClick(() => { this.openSheet('agent'); this.store.refreshAgentState(); })
          }
          if (this.store.status !== '实时连接' && this.store.status !== '已连接') {
            Row({ space: 5 }) {
              StatusLed({ color: C.warning })
              Text(this.store.status).fontSize(9.5).fontFamily('monospace').letterSpacing(0.4).fontColor(C.warning)
            }
          }
          if (this.store.agentUncertain) {
            Text('AGENT 待确认').fontSize(9.5).fontFamily('monospace').letterSpacing(0.5).fontColor(C.warning)
          }
          if (this.store.interactions.length) {
            Row({ space: 5 }) {
              StatusLed({ color: C.warning })
              Text('待处理 ' + this.store.interactions.length).fontSize(9.5).fontFamily('monospace').fontColor(C.warning)
            }
          } else if (this.store.working) {
            Row({ space: 5 }) {
              StatusLed({ color: C.accent })
              Text('运行中').fontSize(9.5).fontFamily('monospace').fontColor(C.secondary)
            }
          }
        }.padding({ left: 20, right: 20, top: 2, bottom: 8 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      if (this.quietNotice) {
        Row({ space: 8 }) {
          StatusLed({ color: this.store.reminderQuiet === 'failed' ? C.danger : this.store.reminderQuiet === 'completed' ? C.success : C.warning })
          Text(this.quietNotice).fontSize(11).fontColor(C.secondary).layoutWeight(1).maxLines(2)
          Button('知道了').id('quiet-dismiss').fontSize(11).height(28).buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.accent)
            .accessibilityText('关闭任务状态提示').onClick(() => { this.quietNotice = ''; })
        }.padding({ left: 20, right: 20, bottom: 6 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      if (this.store.parentSessionID) {
        Row({ space: 8 }) {
          Text(this.store.branchBoundary ? '分叉会话 · ' + this.store.branchBoundary : '子会话')
            .fontSize(10).fontFamily('monospace').fontColor(C.muted).layoutWeight(1).maxLines(1)
          Button('原会话').id('branch-parent').height(24).fontSize(11).buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(C.accent).onClick(() => { this.store.openParentSession(); })
        }.padding({ left: 20, right: 20, bottom: 6 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      if (this.store.permissionError) {
        Row({ space: 8 }) {
          Text(this.store.permissionError).id('permission-sync-error').fontSize(12.5).fontColor(C.warning).layoutWeight(1)
          Button('重新读取审批', { type: ButtonType.Normal }).id('permission-retry').fontSize(11).height(28)
            .backgroundColor(C.warning_bg).fontColor(C.warning).borderRadius(8)
            .onClick(() => { this.store.retryPermissions(); })
        }.padding({ left: 20, right: 20, top: 4, bottom: 4 }).width('100%').constraintSize({ maxWidth: 860 })
      }
      List({ space: 4, scroller: this.scroller }) {
        if (this.store.cursor) {
          ListItem() {
            Button('加载更早消息', { type: ButtonType.Normal }).id('older-messages').fontSize(11).width('100%').height(32)
              .backgroundColor(Color.Transparent).fontColor(C.muted).enabled(!this.store.busy)
              .onClick(() => { this.follow = false; this.store.older(); })
          }
        }
        if (!this.store.messages.length && !this.store.interactions.length && !this.store.busy) {
          ListItem() { this.homeWelcome() }
        }
        LazyForEach(this.messageSource, (message: ChatMessage) => { ListItem() { this.messageCard(message) } }, (message: ChatMessage) => messageKey(message))
        ForEach(this.store.interactions, (item: Interaction) => { ListItem() { this.interactionCard(item) } }, (item: Interaction) => interactionKey(item))
      }.onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) { this.follow = false; } }).id('conversation-list').padding({ left: 22, right: 22 }).layoutWeight(1).width('100%').constraintSize({ maxWidth: 860 }).scrollBar(BarState.Off)
        .onScrollFrameBegin((offset: number, state: ScrollState) => { if (state === ScrollState.Scroll && offset < 0) { this.follow = false; } return { offsetRemain: offset }; })
        .onReachEnd(() => { this.follow = true; })
      Column({ space: 6 }) {
        if (this.pickingAttachments || this.store.working || this.store.pendingSend) {
          Row({ space: 6 }) {
            if (this.pickingAttachments || this.store.working) { LoadingProgress().width(13).height(13).color(C.accent) }
            Text(this.pickingAttachments ? '正在读取附件…' : this.store.pendingSend ? '发送结果待核对，重试会沿用同一条消息' : this.store.interrupting ? '正在停止…' : '正在生成…')
              .fontSize(9.5).fontFamily('monospace').letterSpacing(0.3).fontColor(C.secondary).layoutWeight(1)
            if (this.store.pendingSend) {
              Button('核对状态').id('verify-send').height(24).fontSize(11)
                .buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.accent).enabled(!this.store.busy)
                .onClick(() => { this.store.sync(); })
            }
          }.width('100%').padding({ left: 4, right: 4 })
        }
        if (this.store.attachments.length) {
          AttachmentStrip({ items: this.store.attachments, editable: true, locked: this.pickingAttachments || !!this.store.pendingSend || this.store.busy,
            onOpen: (item: Attachment): void => { this.openAttachment(item); }, onRemove: (id: string): void => { this.store.removeAttachment(id); }, onRetry: (item: Attachment): void => { this.pickAttachments(false, item); } })
          if (attachmentProblem(this.store.attachments, this.store.attachmentInput())) { Text(attachmentProblem(this.store.attachments, this.store.attachmentInput())).fontSize(10).fontColor(C.warning).width('100%') }
        }
        if (!this.follow || this.store.readingHistory || this.store.newerAvailable || this.store.interactions.length || (this.store.working && (!!this.store.draft.trim() || !!this.store.attachments.length))) {
          Row({ space: 8 }) {
            if (!this.follow || this.store.readingHistory || this.store.newerAvailable) {
              Button({ type: ButtonType.Capsule }) {
                Row({ space: 5 }) {
                  SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(11).fontColor([C.secondary]).rotate({ angle: 180 })
                  Text('回到最新').fontSize(11).fontColor(C.secondary)
                }
              }.id('jump-latest').height(28).padding({ left: 10, right: 10 }).responseRegion({ x: -4, y: -6, width: 110, height: 40 })
                .backgroundColor(C.glass_fill).border({ width: 1, color: C.glass_stroke }).borderRadius(999)
                .onClick(() => { this.follow = true; if (this.store.readingHistory) { this.store.latest(); } else { this.scroller.scrollEdge(Edge.Bottom); } })
            }
            Blank()
            if (this.store.interactions.length) {
              Button('待处理 ' + this.store.interactions.length).id('pending-interactions').fontSize(10).fontFamily('monospace').height(28)
                .backgroundColor(C.warning_bg).fontColor(C.warning).borderRadius(8)
                .onClick(() => { this.follow = false; this.scroller.scrollEdge(Edge.Bottom); })
            }
            if (this.store.working && (this.store.draft.trim() || this.store.attachments.length)) {
              Button('停止生成').id('stop-secondary').fontSize(11).height(28)
                .backgroundColor(Color.Transparent).fontColor(C.danger).enabled(!this.store.interrupting)
                .onClick(() => { this.store.interrupt(); })
            }
          }.width('100%').height(28)
        }
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([C.secondary]) }
            .id('attachment-add').accessibilityText('添加附件').width(32).height(38).padding(0).margin({ bottom: 1 }).responseRegion({ x: -4, y: -1, width: 40, height: 40 }).backgroundColor(Color.Transparent)
            .enabled(!!this.store.sessionID && !this.store.busy && !this.store.pendingSend && !this.pickingAttachments)
            .bindMenu(this.attachmentMenu())
          TextArea({ placeholder: this.store.sessionID ? '发消息，或描述一个任务…' : '选择项目后开始对话', text: this.store.draft }).id('chat-input')
            .minLines(1).maxLines(5).constraintSize({ minHeight: 42, maxHeight: 148 }).maxLength(20000).layoutWeight(1).fontSize(14.5).lineHeight(22)
            .padding({ left: 0, right: 0, top: 10, bottom: 10 }).fontColor(C.text).placeholderColor(C.muted).caretColor(C.accent)
            .backgroundColor(Color.Transparent).borderRadius(0).enabled(!this.store.pendingSend && !!this.store.sessionID).onChange((value: string) => { this.store.draft = value; })
          if (this.store.working && !this.store.draft.trim() && !this.store.attachments.length && !this.store.pendingSend) {
            Button({ type: ButtonType.Circle }) { Text('■').fontSize(12.5).fontColor(C.danger) }
              .id('stop-button').accessibilityText('停止生成').width(36).height(36).padding(0).responseRegion({ x: -2, y: -2, width: 40, height: 40 })
              .backgroundColor(C.danger_bg).margin({ bottom: 1 }).enabled(!this.store.interrupting)
              .onClick(() => { this.store.interrupt(); })
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.store.pendingSend) { Text('重试').fontSize(9.5).fontColor(C.btn_text) }
              else {
                SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(17)
                  .fontColor([this.store.draft.trim() || this.store.attachments.length ? C.btn_text : C.muted])
              }
            }.id('send-button').accessibilityText(this.store.pendingSend ? '重试发送' : '发送消息').width(36).padding(0).height(36).margin({ bottom: 1 }).responseRegion({ x: -2, y: -2, width: 40, height: 40 })
              .backgroundColor(this.store.draft.trim() || this.store.attachments.length || this.store.pendingSend ? C.btn : C.field)
              .enabled(!this.store.busy && !this.store.agentBusy && !this.store.agentUncertain && !this.store.forkBusy && !this.store.compactionBusy && ['submitting', 'queued', 'running'].indexOf(this.store.compaction.state) < 0 && !this.pickingAttachments && !!this.store.sessionID && (!!this.store.draft.trim() || !!this.store.attachments.length || !!this.store.pendingSend))
              .onClick(() => { this.follow = true; this.store.send(); })
          }
        }.alignItems(VerticalAlign.Bottom).padding({ left: 10, right: 7, top: 6, bottom: 6 }).width('100%')
          .backgroundEffect({ radius: 26, saturation: 1.6, brightness: 1.0, color: C.glass_strong })
          .border({ width: 1, color: C.glass_stroke })
          .borderRadius(16)
          .shadow({ radius: 30, color: C.glass_shadow, offsetX: 0, offsetY: 10 })
          .clip(true)
        if (this.store.draft.length > 1000) {
          Text(String(this.store.draft.length) + ' / 20000').fontSize(9.5).fontFamily('monospace').fontColor(C.muted)
            .width('100%').textAlign(TextAlign.End)
        }
      }.id('chat-composer').padding({ left: 16, right: 16, top: 8, bottom: 10 }).width('100%').constraintSize({ maxWidth: 860 })
    }.alignItems(HorizontalAlign.Center).layoutWeight(1).width('100%').backgroundColor(C.page)
  }
  @Builder
  diffCard(diff: DiffItem) { DiffContent({ diff: diff, onCopy: (text: string): void => { this.copy(text); } }) }
  @Builder
  review() {
    Scroll() {
      Column({ space: 10 }) {
        this.heading('REVIEW / CHANGES', '看看发生了什么', '查看工作区现状，或按会话任务回看文件修改。')
        NativeSegments({ first: 'Git Diff', second: '会话修改', third: '文件浏览',
          selected: this.store.reviewTab === 'diff' ? 0 : this.store.reviewTab === 'timeline' ? 1 : 2,
          onSelect: (index: number): void => { this.store.reviewTab = index === 0 ? 'diff' : index === 1 ? 'timeline' : 'files';
            if (index === 1 && !this.store.timelineLoaded) { this.store.loadTimeline(); } } }).id('review-segments')
        Row() {
          Text(this.store.reviewTab === 'timeline' ? '会话任务快照' : this.store.reviewTab === 'files' ? '项目文件' : '工作区修改')
            .fontSize(9.5).fontFamily('monospace').letterSpacing(1).fontColor(C.muted).layoutWeight(1)
          Button('刷新', { type: ButtonType.Normal }).controlSize(ControlSize.SMALL).buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.accent)
            .onClick(() => {
              if (this.store.reviewTab === 'timeline') { this.store.loadTimeline(); } else { this.store.openReview(); }
            })
        }.width('100%')
        if (this.store.reviewTab === 'diff') {
          ForEach(this.store.diffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => diffKey(diff))
          if (this.store.diffs.length === 0) {
            Text(this.store.reviewLoaded ? '当前没有可显示的修改。' : this.store.error ? '读取修改失败，请刷新重试。' : '正在读取修改…')
              .fontSize(11).fontColor(C.muted).padding(24)
          }
        } else if (this.store.reviewTab === 'timeline') {
          Text('同一轮任务中的追加消息合并显示。运行中的 Diff 随文件变化，点击刷新可重新读取。')
            .fontSize(11).fontColor(C.secondary).width('100%')
          if (this.store.timelineError) { Text(this.store.timelineError).fontSize(11).fontColor(C.warning).width('100%') }
          ForEach(this.store.turns, (turn: TurnItem) => {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text(turn.title).fontSize(12.5).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(C.text).width('100%')
                Text((turn.created ? new Date(turn.created).toLocaleString() + ' · ' : '') + turn.prompts + ' 条消息 · ' +
                  (turn.partial ? '需加载更早记录确认起点' : turn.state === 'running' ? '尚未结束' : turn.state === 'failed' ? '任务未成功' : '已结束'))
                  .fontSize(9.5).fontFamily('monospace').fontColor(C.muted).width('100%')
              }.layoutWeight(1)
              Text(turn.id === this.store.turnID ? '已选择' : '查看').fontSize(11)
                .fontColor(turn.id === this.store.turnID ? C.accent : C.muted)
            }.id('turn-' + turn.id).padding(12).width('100%').borderRadius(8)
              .backgroundColor(turn.id === this.store.turnID ? C.chip : C.surface)
              .border({ width: 1, color: turn.id === this.store.turnID ? C.accent_soft : C.separator })
              .onClick(() => { this.store.selectTurn(turn); })
          }, (turn: TurnItem) => turn.id + turn.state + turn.prompts + String(turn.partial))
          if (this.store.timelineCursor) {
            Button(this.store.canLoadTimeline() ? '加载更早任务' : '已达到最近 300 条记录的窗口上限', { type: ButtonType.Normal })
              .id('timeline-older').fontSize(11).fontColor(C.secondary).height(32)
              .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
              .enabled(!this.store.timelineBusy && this.store.canLoadTimeline())
              .onClick(() => { this.store.loadTimeline(true); })
          }
          if (this.store.timelineBusy) { Text('正在读取任务记录…').fontSize(11).fontColor(C.muted) }
          if (this.store.timelineLoaded && !this.store.turns.length) { Text('这个会话还没有任务记录。').fontSize(11).fontColor(C.muted) }
          if (this.store.turnID) {
            Text('所选任务的文件修改').fontSize(13).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%').margin({ top: 6 })
            if (this.store.turnError) { Text('读取失败：' + this.store.turnError).fontSize(11).fontColor(C.warning).width('100%') }
            if (this.store.turnBusy) { Text('正在比较任务快照…').fontSize(11).fontColor(C.muted) }
            ForEach(this.store.turnDiffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => this.store.turnID + ':' + diffKey(diff))
            if (this.store.turnLoaded && !this.store.turnDiffs.length) { Text('这轮任务没有文件修改。').fontSize(11).fontColor(C.muted) }
          }
        } else {
          Button('返回项目根目录', { type: ButtonType.Normal }).fontSize(11).height(28).fontColor(C.secondary)
            .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
            .onClick(() => { this.store.openReview(); })
          ForEach(this.store.files, (file: FileItem) => {
            Row({ space: 9 }) {
              Stack() {
                SymbolGlyph(file.directory ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text')).fontSize(13.5).fontColor([C.secondary])
              }.width(26).height(26).backgroundColor(C.field).borderRadius(6)
              Text(file.name).fontFamily('monospace').fontSize(11).layoutWeight(1).fontColor(C.text)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(11).fontColor([C.muted])
            }.padding({ left: 10, right: 10, top: 9, bottom: 9 }).width('100%').backgroundColor(C.surface)
              .border({ width: 1, color: C.separator }).borderRadius(8)
              .onClick(() => { this.store.browse(file); })
          }, (file: FileItem) => file.path)
          if (this.store.fileContent) {
            Column({ space: 8 }) {
              if (this.store.fileTruncated) { Text('文件较长，仅显示前1500行或100000字；完整内容保留在服务器。').fontSize(10).fontColor(C.warning) }
              Text(this.store.filePath).fontSize(10).fontFamily('monospace').fontColor(C.secondary).width('100%')
              Text(this.store.fileContent).fontFamily('monospace').fontSize(11).lineHeight(18).fontColor(C.code_text)
                .copyOption(CopyOptions.InApp).width('100%')
            }.padding(12).backgroundColor(C.code_bg).borderRadius(10).width('100%')
          }
        }
      }.padding(18).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }
  @Builder
  sidebar(width: number) {
    Column({ space: 0 }) {
      Row({ space: 9 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.code_square')).fontSize(15).fontColor([C.btn_text])
        }.width(28).height(28).backgroundColor(C.btn).borderRadius(7)
        Column({ space: 2 }) {
          Text('OpenCode').fontSize(15).fontWeight(FontWeight.Bold).fontColor(C.text).letterSpacing(-0.2)
          Text('OPENCODE V2.0.29').fontSize(9.5).fontFamily('monospace').letterSpacing(1).fontColor(C.muted)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(15).fontColor([C.secondary]) }
          .id('close-sidebar').accessibilityText('关闭历史侧栏').width(40).height(40).backgroundColor(Color.Transparent)
          .onClick(() => { this.sidebarOpen = false; })
      }.width('100%').padding({ top: 10, bottom: 16 })
      Button('新建对话', { type: ButtonType.Normal }).id('sidebar-new-chat').width('100%').constraintSize({ minHeight: 36 }).fontSize(12.5)
        .fontWeight(FontWeight.Medium).backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(8).enabled(!this.store.busy)
        .onClick(() => { this.newChat(); })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 8 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(15).fontColor([C.secondary])
          Text(this.projectName()).fontSize(12.5).fontColor(C.secondary).layoutWeight(1).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
        }.padding({ left: 8, right: 8 })
      }.id('sidebar-projects').width('100%').height(36).backgroundColor(Color.Transparent).borderRadius(8)
        .enabled(!!this.store.connected).onClick(() => { this.navigate('projects'); })
      this.sessionFilters()
      Text(this.store.showArchived ? '本机归档' : '历史对话').fontSize(9.5).fontWeight(FontWeight.Medium)
        .letterSpacing(1.4).fontColor(C.muted).width('100%').padding({ top: 16, bottom: 4 })
      Scroll() {
        Column({ space: 2 }) {
          ForEach(this.store.sessionRows(this.sessionSearch), (session: SessionItem) => { this.sessionRow(session, true) },
            (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id) + String(this.store.isPinned(session.id)))
          this.sessionPaging()
          if (!this.store.sessionRows(this.sessionSearch).length) {
            Text(this.store.connected ? '暂无匹配的会话，可搜索服务器历史或切换归档。' : '连接服务器后，继续你的对话')
              .fontSize(11).fontColor(C.muted).padding(12)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
      Divider().color(C.separator)
      Text('工作区').fontSize(9.5).fontWeight(FontWeight.Medium).letterSpacing(1.4).fontColor(C.muted)
        .width('100%').padding({ top: 10, bottom: 2 })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.checkmark')).fontSize(16).fontColor([C.secondary])
          Text('待办中心').fontSize(12.5).fontColor(C.text).layoutWeight(1)
          if (this.store.pendingItems.length) { this.badge(String(this.store.pendingItems.length), C.warning_bg) }
        }.padding({ left: 8, right: 8 })
      }.id('nav-pending').width('100%').height(38).backgroundColor(Color.Transparent).borderRadius(8)
        .enabled(!!this.store.connected).onClick(() => { this.navigate('pending'); })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.doc_text')).fontSize(16).fontColor([C.secondary])
          Text('代码审查').fontSize(12.5).fontColor(C.text).layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
        }.padding({ left: 8, right: 8 })
      }.id('nav-review').width('100%').height(38).backgroundColor(Color.Transparent).borderRadius(8)
        .enabled(!!this.store.directory).onClick(() => { this.navigate('review'); })
      Button({ type: ButtonType.Normal }) {
        Row({ space: 9 }) {
          SymbolGlyph($r('sys.symbol.code_square')).fontSize(16).fontColor([C.secondary])
          Text('模型与接入').fontSize(12.5).fontColor(C.text).layoutWeight(1)
          SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
        }.padding({ left: 8, right: 8 })
      }.id('nav-settings').width('100%').height(38).backgroundColor(Color.Transparent).borderRadius(8)
        .enabled(!!this.store.connected).onClick(() => { this.navigate('settings'); })
      Row({ space: 9 }) {
        SymbolGlyph($r('sys.symbol.bell')).fontSize(16).fontColor([C.secondary])
        Text('任务提醒').fontSize(12.5).fontColor(C.text).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
      }.id('nav-reminders').width('100%').height(38).backgroundColor(Color.Transparent).borderRadius(8)
        .onClick(() => { this.navigate('reminders'); })
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right_badge_person_filled')).fontSize(15)
            .fontColor([this.store.connected ? C.accent : C.muted])
        }.width(28).height(28).backgroundColor(C.field).borderRadius(7)
        Column({ space: 2 }) {
          Text(this.serverName()).fontSize(12.5).fontColor(C.text).maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 5 }) {
            StatusLed({ color: this.store.connected ? C.success : C.muted })
            Text(this.store.status).fontSize(9.5).fontFamily('monospace').fontColor(C.muted).maxLines(1)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12.5).fontColor([C.muted])
      }.id('nav-connections').padding({ left: 8, right: 8, top: 9, bottom: 9 }).width('100%').borderRadius(8)
        .border({ width: 1, color: C.separator }).onClick(() => { this.navigate('connections'); })
    }.padding({ left: 14, right: 14, bottom: 12 }).width(width).height('100%')
      .backgroundEffect({ radius: 32, saturation: 1.7, brightness: 1.0, color: C.glass_fill })
      .border({ width: { right: 1 }, color: C.glass_stroke })
      .shadow({ radius: 28, color: C.glass_shadow, offsetX: 14, offsetY: 0 })
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
      Column({ space: 0 }) {
        Text('更多功能').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text('ACTIONS · 常用入口').fontSize(9.5).letterSpacing(1.2)
          .fontColor(C.muted).width('100%').padding({ top: 4, bottom: 8 })
        Button('待办中心', { type: ButtonType.Normal }).enabled(!!this.store.connected).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('pending'); })
        Button('项目与会话', { type: ButtonType.Normal }).enabled(!!this.store.connected).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('projects'); })
        Button('代码审查', { type: ButtonType.Normal }).enabled(!!this.store.directory).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('review'); })
        Button('模型与接入', { type: ButtonType.Normal }).enabled(!!this.store.connected).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('settings'); })
        Button('服务器连接', { type: ButtonType.Normal }).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('connections'); })
        Button('外观', { type: ButtonType.Normal }).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('appearance'); })
        Button('任务提醒', { type: ButtonType.Normal }).id('more-reminders').width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.navigate('reminders'); })
        Button('上下文与用量', { type: ButtonType.Normal }).id('open-usage').enabled(!!this.store.sessionID).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.openSheet('usage'); this.store.refreshUsage(); })
        Button('分叉当前会话', { type: ButtonType.Normal }).id('open-fork').enabled(!!this.store.sessionID && !this.store.forkBusy).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.openFork(); })
        Button('导出当前会话', { type: ButtonType.Normal }).id('open-export').enabled(!!this.store.sessionID && !this.savingExport).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.store.exportError = ''; this.exportNotice = ''; this.openSheet('export'); })
        Button('同步当前对话', { type: ButtonType.Normal }).enabled(!!this.store.sessionID).width('100%').constraintSize({ minHeight: 42 }).borderRadius(0)
          .backgroundColor(Color.Transparent).fontColor(C.text).fontSize(12.5).border({ width: { bottom: 1 }, color: C.separator })
          .onClick(() => { this.toolSheetOpen = false; this.store.sync(); })
      }.padding({ left: 18, right: 18, top: 18, bottom: 20 }).width('100%')
    }
  }
  @Builder
  sessionFilters() {
    Row({ space: 6 }) {
      TextInput({ placeholder: '搜索会话名称', text: this.sessionSearch }).id('session-search')
        .height(32).fontSize(11).fontColor(C.text).placeholderColor(C.muted).backgroundColor(C.field)
        .border({ width: 1, color: C.separator }).borderRadius(8).layoutWeight(1)
        .onChange((value: string) => { this.sessionSearch = value; })
      Button('搜索', { type: ButtonType.Normal }).id('session-search-server').height(32).fontSize(11).backgroundColor(C.field).fontColor(C.secondary)
        .borderRadius(8).border({ width: 1, color: C.separator }).enabled(!this.store.sessionsBusy && !!this.store.directory)
        .onClick(() => { this.store.refreshSessions(false, this.sessionSearch); })
    }.width('100%')
    if (this.store.sessionQuery) { Text('服务器搜索：' + this.store.sessionQuery).fontSize(11).fontColor(C.muted).maxLines(1).width('100%') }
    Row({ space: 4 }) {
      Button('最近', { type: ButtonType.Normal }).id('sessions-recent').layoutWeight(1).height(28).fontSize(11).backgroundColor(Color.Transparent)
        .fontColor(this.store.showArchived ? C.muted : C.text).borderRadius(0)
        .fontWeight(this.store.showArchived ? FontWeight.Normal : FontWeight.Medium)
        .border({ width: { bottom: this.store.showArchived ? 0 : 1 }, color: C.text })
        .onClick(() => { this.store.showArchived = false; if (this.store.sessionQuery) { this.sessionSearch = ''; this.store.refreshSessions(false, ''); } })
      Button('本机归档', { type: ButtonType.Normal }).id('sessions-archived').layoutWeight(1).height(28).fontSize(11).backgroundColor(Color.Transparent)
        .fontColor(this.store.showArchived ? C.text : C.muted).borderRadius(0)
        .fontWeight(this.store.showArchived ? FontWeight.Medium : FontWeight.Normal)
        .border({ width: { bottom: this.store.showArchived ? 1 : 0 }, color: C.text })
        .onClick(() => { this.store.showArchived = true; })
      Button('刷新', { type: ButtonType.Normal }).id('sessions-refresh').height(28).fontSize(11).backgroundColor(Color.Transparent)
        .fontColor(C.muted).borderRadius(0)
        .enabled(!this.store.sessionsBusy).onClick(() => { this.store.refreshSessions(false, this.sessionSearch); })
    }.width('100%').margin({ top: 8 })
  }
  @Builder
  sessionRow(session: SessionItem, compact: boolean) {
    Row({ space: 6 }) {
      if (session.id === this.store.sessionID) {
        Rect().width(2).height(16).radius(1).fill(C.accent)
      }
      Column({ space: 3 }) {
        Text((this.store.isPinned(session.id) ? '置顶 · ' : '') + (session.forkType ? '分支 · ' : session.parentID ? '子会话 · ' : '') + session.title)
          .fontSize(compact ? 12 : 14).fontColor(C.text).maxLines(compact ? 1 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.store.sessionLabel(session.id)) {
          Text(this.store.sessionLabel(session.id)).fontSize(9.5).letterSpacing(0.6).fontColor(C.warning).width('100%')
        }
      }.id((compact ? 'sidebar-session-' : 'session-') + session.id).alignItems(HorizontalAlign.Start).layoutWeight(1)
        .padding({ left: 2, top: 6, bottom: 6 }).onClick(() => { this.pickSession(session); })
      Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(15).fontColor([C.muted]) }
        .id('session-actions-' + session.id).width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText('管理会话 ' + session.title).onClick(() => { this.manageSession(session); })
    }.width('100%').constraintSize({ minHeight: compact ? 44 : 54 }).padding({ left: session.id === this.store.sessionID ? 8 : 10, right: 2 })
      .backgroundColor(session.id === this.store.sessionID ? C.chip : compact ? Color.Transparent : C.surface)
      .border({ width: compact ? 0 : 1, color: C.separator })
      .borderRadius(8)
  }
  @Builder
  sessionPaging() {
    if (this.store.sessionsError) { Text(this.store.sessionsError).fontSize(12.5).fontColor(C.danger).width('100%') }
    if (this.store.sessionsBusy) { Text('正在读取会话…').fontSize(12.5).fontColor(C.muted).padding(8) }
    if (this.store.sessionCursor && this.store.sessions.length < 500) { Button('加载更多会话').id('sessions-more').fontSize(12.5).enabled(!this.store.sessionsBusy).onClick(() => { this.store.refreshSessions(true); }) }
    if (this.store.sessions.length >= 500) { Text('已显示 500 个会话，可用名称搜索服务器历史。').fontSize(11).fontColor(C.muted).padding(8) }
  }
  @Builder
  sessionActions() {
    Column({ space: 12 }) {
      Text('管理会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      Text('会话名称会同步到服务器。').id('session-name-scope').fontSize(12.5).fontColor(C.secondary).width('100%')
      TextInput({ text: this.sessionName, placeholder: '会话名称' }).id('session-name').maxLength(200)
        .fontSize(13).fontColor(C.text).placeholderColor(C.muted).height(40)
        .backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8)
        .onChange((value: string) => { this.sessionName = value; })
      Button(this.store.sessionMutationBusy ? '保存中…' : '保存名称', { type: ButtonType.Normal }).id('session-rename')
        .width('100%').height(36).fontSize(12.5).fontWeight(FontWeight.Medium).borderRadius(8)
        .backgroundColor(C.btn).fontColor(C.btn_text)
        .enabled(!this.store.sessionMutationBusy && !this.store.sessionPreferenceBusy && !!this.sessionName.trim())
        .onClick(() => { this.store.renameSession(this.selectedSession.id, this.sessionName).then((saved: boolean) => { if (saved) { this.toolSheetOpen = false; } }); })
      Text('本机列表设置').id('session-local-scope').fontSize(11).fontColor(C.secondary).width('100%')
      Button(this.store.isPinned(this.selectedSession.id) ? '取消置顶' : '置顶会话', { type: ButtonType.Normal }).id('session-pin')
        .width('100%').height(32).fontSize(12).borderRadius(8).backgroundColor(Color.Transparent).fontColor(C.text)
        .border({ width: 1, color: C.separator })
        .enabled(!this.store.sessionPreferenceBusy && !this.store.sessionMutationBusy)
        .onClick(() => { this.store.setSessionPreference(this.selectedSession.id, !this.store.isPinned(this.selectedSession.id), this.store.isArchived(this.selectedSession.id)); })
      Button(this.store.isArchived(this.selectedSession.id) ? '移回最近会话' : '归档到本机列表', { type: ButtonType.Normal }).id('session-archive')
        .width('100%').height(32).fontSize(12).borderRadius(8).backgroundColor(Color.Transparent).fontColor(C.text)
        .border({ width: 1, color: C.separator })
        .enabled(!this.store.sessionPreferenceBusy && !this.store.sessionMutationBusy)
        .onClick(() => { this.store.setSessionPreference(this.selectedSession.id, this.store.isPinned(this.selectedSession.id), !this.store.isArchived(this.selectedSession.id)); })
      Text('置顶和归档仅影响这台设备。归档保留服务器历史，运行中的任务会继续，待办仍会显示。')
        .fontSize(10).lineHeight(17).fontColor(C.muted).width('100%')
      if (this.store.error) { Text(this.store.error).fontSize(11).fontColor(C.danger).width('100%') }
    }.padding(18).width('100%')
  }
  @Builder
  pendingCenter() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('当前服务器 · 所有已知项目').fontSize(9.5).letterSpacing(0.8)
          .fontColor(C.muted).layoutWeight(1)
        Button('刷新', { type: ButtonType.Normal }).id('pending-refresh').fontSize(11).height(28).buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor(C.accent).enabled(!this.store.pendingBusy).onClick(() => { this.store.refreshPending(true); })
      }.width('100%')
      NativeSegments({ first: '全部', second: '问题', third: '审批', selected: this.pendingFilter, onSelect: (index: number): void => { this.pendingFilter = index; } })
      if (this.store.pendingError) { Text(this.store.pendingError + '。旧结果已保留，打开会话后重新核对。').fontSize(11).fontColor(C.warning).width('100%') }
      if (this.store.pendingBusy) { Text('正在同步待办…').fontSize(11).fontColor(C.muted).width('100%') }
      if (!this.store.pendingBusy && !this.store.pendingError && !this.store.pendingItems.length) {
        Text('当前没有待处理的问题或审批。').fontSize(11).fontColor(C.muted).padding(22)
      }
      List({ space: 8 }) {
        ForEach(this.store.pendingItems.filter((p: PendingItem) => this.pendingFilter === 0 || p.kind === (this.pendingFilter === 1 ? 'form' : 'permission')), (item: PendingItem) => {
          ListItem() {
            Column({ space: 5 }) {
              Row({ space: 6 }) {
                StatusLed({ color: item.kind === 'form' ? C.accent : C.warning })
                Text((item.stale ? '待确认 · ' : '') + (item.kind === 'form' ? '需要回答' : '需要审批'))
                  .fontSize(9.5).fontFamily('monospace').letterSpacing(0.8)
                  .fontColor(item.kind === 'form' ? C.accent : C.warning)
              }.width('100%')
              Text(item.title).fontSize(12.5).fontColor(C.text).maxLines(3).width('100%')
              Text(item.sessionTitle || item.sessionID).fontSize(11)
                .fontColor(C.secondary).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.directory).fontSize(9.5).fontFamily('monospace').fontColor(C.muted).maxLines(2).width('100%')
              Button('打开会话处理', { type: ButtonType.Normal }).id('pending-open-' + item.kind + '-' + item.id)
                .height(28).fontSize(11).fontColor(C.btn_text).backgroundColor(C.btn).borderRadius(7)
                .enabled(!this.store.busy)
                .onClick(() => { this.follow = true; this.store.openPending(item); })
            }.padding(14).backgroundColor(C.surface).border({ width: 1, color: C.separator }).borderRadius(10).width('100%')
          }
        }, (item: PendingItem) => pendingKey(item) + item.title + item.sessionTitle + String(item.stale))
      }.layoutWeight(1).width('100%')
    }.padding(18).height('100%').width('100%')
  }
  @Builder
  reminderSettings() {
    ReminderSettingsView({ completed: this.reminders.completed, failed: this.reminders.failed, pending: this.reminders.pending,
      permission: this.reminders.permission, ready: this.reminders.ready, requesting: this.reminders.requesting,
      permissionRequested: this.reminders.permissionRequested,
      notice: this.reminders.lastError,
      onToggle: (group: string, enabled: boolean): void => { this.reminders.setGroup(group as ReminderGroup, enabled); },
      onRequest: (): void => { this.reminders.requestPermission(); } })
  }
  @Builder
  appearanceSettings() {
    Column({ space: 16 }) {
      NativeSegments({ first: '跟随系统', second: '浅色', third: '深色',
        selected: this.appearanceMode === 'dark' ? 2 : this.appearanceMode === 'light' ? 1 : 0,
        onSelect: (index: number): void => { this.changeAppearance(index === 2 ? 'dark' : index === 1 ? 'light' : 'system'); } }).id('appearance-segments')
      Text('选择此应用的显示方式').fontSize(11).fontColor(C.secondary).width('100%')
      Text('当前外观：' + (this.appearanceMode === 'dark' ? '深色' : this.appearanceMode === 'light' ? '浅色' : '跟随系统'))
        .fontSize(9.5).fontFamily('monospace').fontColor(C.secondary).width('100%')
      Text('跟随系统会自动适配设备的深浅色设置。').fontSize(11).lineHeight(18).fontColor(C.muted).width('100%')
    }.padding(18).width('100%')
  }
  @Builder
  toolDetails() {
    Column({ space: 12 }) {
      Row({ space: 9 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.code_square')).fontSize(15).fontColor([C.secondary])
        }.width(28).height(28).backgroundColor(C.field).borderRadius(7)
        Column({ space: 2 }) {
          Text(this.toolLabel(this.selectedTool.name)).fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text)
          Text(this.selectedTool.id.slice(0, 28) || 'TOOL CALL').fontSize(9.5).fontFamily('monospace')
            .letterSpacing(0.8).fontColor(C.muted).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Row({ space: 5 }) {
          StatusLed({ color: this.selectedTool.status === 'error' || this.selectedTool.status === 'failed' ? C.danger : this.selectedTool.status === 'running' ? C.accent : C.success })
          Text(toolStatus(this.selectedTool.status)).fontSize(11).fontColor(C.secondary)
        }
      }.padding({ right: 38 }).width('100%')
      Divider().color(C.separator)
      Scroll() {
        Column({ space: 10 }) {
          Text('CALL ARGUMENTS').fontSize(9.5).fontFamily('monospace').letterSpacing(1.2).fontColor(C.muted).width('100%')
          Text(this.selectedTool.input.slice(0, 12000) || '无参数').id('tool-request')
            .fontFamily('monospace').fontSize(11).lineHeight(18).fontColor(C.code_text)
            .padding(12).backgroundColor(C.code_bg).border({ width: 1, color: C.separator }).borderRadius(8)
            .copyOption(CopyOptions.InApp).width('100%')
          Text('EXECUTION OUTPUT').fontSize(9.5).fontFamily('monospace').letterSpacing(1.2).fontColor(C.muted).width('100%')
          Text(this.selectedTool.output.slice(0, 16000) || (this.selectedTool.status === 'running' ? '正在执行，结果会自动更新…' : '暂无文本结果')).id('tool-response')
            .fontFamily('monospace').fontSize(11).lineHeight(18).fontColor(C.code_text)
            .padding(12).backgroundColor(C.code_bg).border({ width: 1, color: C.separator }).borderRadius(8)
            .copyOption(CopyOptions.InApp).width('100%')
          if (this.selectedTool.input.length > 12000 || this.selectedTool.output.length > 16000) {
            Text('较长内容已截断，完整记录保留在服务器。').fontSize(9.5).fontColor(C.muted)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        Button('复制参数', { type: ButtonType.Normal }).layoutWeight(1).height(32).fontSize(12).fontColor(C.text)
          .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
          .onClick(() => { this.copy(this.selectedTool.input); })
        Button('复制结果', { type: ButtonType.Normal }).layoutWeight(1).height(36).fontSize(12.5).fontColor(C.btn_text)
          .backgroundColor(C.btn).borderRadius(8)
          .onClick(() => { this.copy(this.selectedTool.output); })
      }.width('100%').margin({ top: 10 })
    }.id('tool-details').padding({ left: 16, right: 16, top: 8, bottom: 18 }).width('100%').height('100%')
  }
  @Builder
  chatTitle() {
    Row({ space: 8 }) {
      Blank().width(this.sidebarOpen ? 0 : 52).height(40)
      if (this.store.models.length) {
        Button(this.modelLabel(), { type: ButtonType.Normal }).id('model-select')
          .fontSize(12.5).fontColor(C.text).height(40)
          .labelStyle({ maxLines: 1, overflow: TextOverflow.Ellipsis })
          .backgroundColor(C.surface).border({ width: 1, color: C.separator }).borderRadius(999)
          .padding({ left: 13, right: 13 })
          .constraintSize({ maxWidth: 220 })
          .width(Math.min(220, Math.max(96, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - (this.sidebarOpen ? 168 : 224))))
          .enabled(!!this.store.sessionID && !this.store.busy).accessibilityText('选择对话模型')
          .onClick(() => { this.store.error = ''; this.openSheet('model'); })
      } else { Text('OpenCode').fontSize(15).fontWeight(FontWeight.Bold).fontColor(C.text).layoutWeight(1) }
      Blank().layoutWeight(1)
    }.width(Math.max(180, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - 104)).height(56)
  }
  @Builder
  errorBanner() {
    if (this.store.error) {
      Row({ space: 8 }) {
        StatusLed({ color: C.danger })
        Text(this.store.error).fontSize(11).fontColor(C.danger).layoutWeight(1).maxLines(3)
        if (this.store.connected && this.store.status !== '实时连接' && this.store.status !== '已连接') {
          Button('重新连接').fontSize(11).height(26).backgroundColor(C.danger_bg)
            .fontColor(C.danger).borderRadius(6).enabled(!this.store.busy)
            .onClick(() => { this.store.reconnect(); })
        }
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(13).fontColor([C.secondary]) }
          .width(28).height(28).backgroundColor(Color.Transparent).accessibilityText('关闭提示').responseRegion({ x: -6, y: -6, width: 40, height: 40 })
          .onClick(() => { this.store.error = ''; })
      }.padding({ left: 20, right: 12, top: 7, bottom: 7 }).backgroundColor(C.danger_bg).width('100%')
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
        else if (name === 'reminders') { this.reminderSettings() }
        else if (name === 'settings') { ProviderSettings({ store: this.store.providers, onOpenLink: (url: string): void => { this.openLink(url); } }) }
        else { this.review() }
      }.height('100%').width('100%').backgroundColor(C.page)
    }.id('native-destination').title({ main: this.pageTitle(name), sub: this.store.status })
      .systemBarStyle({ statusBarContentColor: this.darkAppearance ? '#EDEEF0' : '#15171C' })
      .backgroundColor(C.page).onBackPressed((): boolean => { this.store.pane = 'chat'; return true; })
  }
  build() {
    SideBarContainer(this.wide ? SideBarContainerType.Embed : SideBarContainerType.Overlay) {
      this.sidebar(this.wide ? 280 : Math.min(304, this.viewportWidth * 0.84))
      Navigation(this.navigation) {
        Column({ space: 0 }) { this.errorBanner(); this.chat() }.height('100%').width('100%').backgroundColor(C.page)
      }.id('native-navigation').title(this.chatTitle()).titleMode(NavigationTitleMode.Mini)
        .systemBarStyle({ statusBarContentColor: this.darkAppearance ? '#EDEEF0' : '#15171C' })
        .menus([{ value: '新建对话', symbolIcon: new SymbolGlyphModifier($r('sys.symbol.plus')),
          isEnabled: !this.store.busy, action: (): void => { this.newChat(); } },
          { value: '更多功能', symbolIcon: new SymbolGlyphModifier($r('sys.symbol.ellipsis_circle')), action: (): void => { this.showActions(); } }])
        .navDestination(this.destination).mode(NavigationMode.Stack).hideBackButton(true)
        .onNavBarStateChange((visible: boolean) => { if (visible && !this.navigation.getAllPathName().length && this.store.pane !== 'chat') { this.store.pane = 'chat'; } })
        .backgroundColor(C.page).height('100%').width('100%')
    }.id('native-sidebar-container').showSideBar(this.sidebarOpen).showControlButton(!this.sidebarOpen && this.store.pane === 'chat')
      .controlButton({ left: 16, top: 16, width: 24, height: 24 })
      .sideBarWidth(this.wide ? 280 : Math.min(304, this.viewportWidth * 0.84)).minSideBarWidth(220).maxSideBarWidth(320)
      .divider({ strokeWidth: 1, color: C.separator }).onChange((show: boolean) => { if (show) { this.dismissKeyboard(); } this.sidebarOpen = show; })
      .width('100%').height('100%').backgroundColor(C.page).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.viewportWidth = Number(newArea.width); const wide = this.viewportWidth >= 840; if (this.wide !== wide) { this.wide = wide; this.sidebarOpen = wide; }
        // Keyboard opening resizes the page; keep the newest message visible only when the user is following the live end.
        const oldHeight = Number(oldArea.height); const newHeight = Number(newArea.height);
        if (oldHeight > 0 && newHeight < oldHeight - 60 && this.follow && this.store.pane === 'chat' && !this.toolSheetOpen) {
          setTimeout(() => { if (this.follow && this.store.pane === 'chat' && !this.toolSheetOpen) { this.scroller.scrollEdge(Edge.Bottom); } }, 140);
        }
      })
      .bindSheet($$this.toolSheetOpen, this.sheetSurface(), {
        height: this.isLargeSheet() ? SheetSize.LARGE : SheetSize.FIT_CONTENT,
        showClose: true,
        blurStyle: BlurStyle.COMPONENT_ULTRA_THICK,
        maskColor: C.sheet_scrim,
        borderWidth: 1,
        borderColor: C.glass_stroke,
        shadow: { radius: 36, color: C.glass_shadow, offsetX: 0, offsetY: -8 },
        onDisappear: (): void => { if (this.store.exporting) { this.store.cancelExport(); } }
      })
  }
}
