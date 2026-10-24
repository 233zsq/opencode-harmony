import { ConversationSearchPanel } from '../components/ConversationSearchPanel';
import { ConversationHit } from '../domain/ConversationSearch';
import { ModelMenuHost } from '../components/ModelMenuHost';
import { ModelLibrary } from '../components/ModelLibrary';
import { ForkPanel } from '../components/ForkPanel';
import { UsagePanel } from '../components/UsagePanel';
import { AgentItem } from '../domain/Agents';
import { AgentPicker } from '../components/AgentPicker';
import { ExportPanel } from '../components/ExportPanel';
import { TranscriptCache } from '../data/TranscriptCache';
import { DocumentSaver } from '../data/DocumentSaver';
import { DiffContent } from '../components/DiffContent';
import { Attachment, attachmentProblem } from '../domain/Attachments';
import { AttachmentPicker } from '../data/AttachmentPicker';
import { AttachmentStrip } from '../components/AttachmentStrip';
import { AttachmentPreview } from '../components/AttachmentPreview';
import { copyText } from '../presentation/Clipboard';
import { Appearance } from '../presentation/Appearance';
import { SymbolGlyphModifier, KeyboardAvoidMode } from '@kit.ArkUI';
import { NativeSegments } from '../components/NativeSegments';
import { StatusLed, CodeMark } from '../components/Material';
import { loadImmersiveMaterials } from '../presentation/ImmersiveMaterials';
import deviceInfo from '@ohos.deviceInfo';
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
  @State modelLibraryFavorites: boolean = false;
  @State savingExport: boolean = false;
  @State exportNotice: string = '';
  private async selectAgent(id: string): Promise<void> {
    const scope = this.store.connected + '/' + this.store.sessionID;
    if (await this.store.chooseAgent(id) && scope === this.store.connected + '/' + this.store.sessionID && this.panelVisible('agent')) { this.closePanel(); }
  }
  private async exportConversation(format: string, tools: boolean): Promise<void> {
    if (this.savingExport) { return; } this.exportNotice = '';
    const scope = this.store.exportScope();
    const document = await this.store.prepareExport(format, tools);
    if (!document || scope !== this.store.exportScope() || !this.panelVisible('export')) { return; }
    this.savingExport = true;
    try { const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      const saved = await new DocumentSaver(context).saveText(document.name, document.text, (): boolean => scope === this.store.exportScope());
      if (scope === this.store.exportScope()) { this.exportNotice = saved ? '已保存 ' + document.count + ' 条对话' : '已取消保存，可重新导出'; }
    } catch (_) { this.exportNotice = '文件未保存，请重试'; } finally { this.savingExport = false; }
  }
  private async selectModel(id: string): Promise<void> {
    if (this.switchingModel || !this.store.sessionID) { return; }
    if (id === this.store.modelID) { this.closePanel(); return; }
    const scope = this.store.connected + '/' + this.store.sessionID; this.switchingModel = true;
    try { await this.store.chooseModel(id); if (scope === this.store.connected + '/' + this.store.sessionID && this.store.modelID === id && !this.store.error && this.panelVisible('model')) { this.closePanel(); } }
    finally { this.switchingModel = false; }
  }
  private async selectVariant(variant: string): Promise<boolean> {
    if (this.switchingModel || !this.store.sessionID) { return false; }
    this.switchingModel = true;
    try { return await this.store.chooseModel(this.store.modelID, variant); }
    finally { this.switchingModel = false; }
  }
  @State forkBefore: string = '';
  @State forkEditing: boolean = false;
  @State forkText: string = '';
  @State forkSource: string = '';
  @State forkHasFiles: boolean = false;
  @State forkScope: string = '';
  private connectionScroller: Scroller = new Scroller();
  @State connectionFormOpen: boolean = false;
  private openFork(message?: ChatMessage, edit: boolean = false): void {
    this.forkBefore = message?.id || ''; this.forkEditing = edit; this.forkText = edit ? message?.text || '' : ''; this.forkSource = message ? message.text.slice(0, 180) || '所选消息包含附件或工具内容' : '';
    this.forkHasFiles = !!message?.files?.length; this.forkScope = this.store.exportScope(); this.store.forkError = ''; this.openSheet('fork');
  }
  private async createFork(text: string, reuse: boolean): Promise<void> {
    const scope = this.forkScope; if (scope !== this.store.exportScope()) { return; }
    const child = await this.store.forkSession(this.forkBefore, this.forkEditing, text, reuse);
    if (!child || scope !== this.store.exportScope()) { return; }
    if (this.panelVisible('fork')) { this.closePanel(); this.follow = true; await this.store.openSession(child); }
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
    this.attachmentPopupOpen = false;
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
  @State viewportHeight: number = 800;
  @State @Watch('conversationVisibilityChanged') modelPopupOpen: boolean = false;
  @State @Watch('conversationVisibilityChanged') workspacePopupOpen: boolean = false;
  @State @Watch('conversationVisibilityChanged') attachmentPopupOpen: boolean = false;
  @State private chatHeadingHeight: number = 46;
  @State private composerHeight: number = 72;
  @State private modelMaterial: SystemUiMaterial | undefined = undefined;
  @State private compactSheetMaterial: SystemUiMaterial | undefined = undefined;
  @State sessionSearch: string = '';
  @State focusedMessage: string = '';
  private locateMessage(hit: ConversationHit): void {
    const scope = this.store.exportScope(); const index = this.store.messages.findIndex((m: ChatMessage) => m.id === hit.id);
    if (index < 0) { this.toast('消息已移出加载范围，请重新查找'); return; }
    this.navigate('chat'); this.follow = false; this.focusedMessage = hit.id;
    if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; }
    if (hit.label === '思考') {
      this.reasoningClosed = this.reasoningClosed.filter((id: string): boolean => id !== hit.id);
      if (this.reasoningOpen.indexOf(hit.id) < 0) { this.reasoningOpen = this.reasoningOpen.concat([hit.id]); }
    }
    setTimeout(() => {
      if (scope !== this.store.exportScope() || this.store.pane !== 'chat') { return; }
      const current = this.store.messages.findIndex((m: ChatMessage) => m.id === hit.id);
      if (current >= 0) { this.scroller.scrollToIndex(current + (this.store.cursor ? 1 : 0), false, ScrollAlign.CENTER); }
    }, 120);
  }
  @State pendingFilter: number = 0;
  @State selectedSession: SessionItem = { id: '', title: '', directory: '', status: '', model: '' };
  @State sessionName: string = '';
  private viewMessages: ChatMessage[] = [];
  private viewInteractions: Interaction[] = [];
  private scrollTimer: number = -1;
  @State @Watch('conversationVisibilityChanged') toolSheetOpen: boolean = false;
  @State sheetKind: string = 'tool';
  private panelReturn: string = 'chat';
  private panelScope: string = '';
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
    loadImmersiveMaterials().then((materials): void => { this.modelMaterial = materials.popup; this.compactSheetMaterial = materials.sheet; });
    const context = this.getUIContext().getHostContext();
    if (context) {
      const ability = context as common.UIAbilityContext;
      this.reminders.attachContext(ability);
      this.reminders.load();
      this.store.attachNotifier(this.reminders, this.foreground);
      const cache = new TranscriptCache();
      cache.init(context as common.Context).then((): void => { this.store.attachCache(cache); this.store.attachDraftStore(cache); })
        .catch((): void => { this.store.cacheNotice = '加密缓存暂不可用，仍可正常联网使用'; })
        .then((): Promise<void> => this.store.init(context as common.Context))
        .then((): void => { this.appReady = true; this.consumeNotificationLaunch(); this.tryConsumeLaunch(); });
    }
  }
  aboutToDisappear(): void { if (this.scrollTimer >= 0) { clearTimeout(this.scrollTimer); this.scrollTimer = -1; } this.store.setActive(false); }
  private closePopups(): void { this.modelPopupOpen = false; this.workspacePopupOpen = false; this.attachmentPopupOpen = false; }
  onBackPress(): boolean { if (this.attachmentPopupOpen) { this.attachmentPopupOpen = false; return true; } if (this.workspacePopupOpen) { this.workspacePopupOpen = false; return true; } if (this.modelPopupOpen) { this.closePopups(); return true; } if (this.toolSheetOpen) { this.closePanel(); return true; } if (this.sidebarOpen) { this.dismissKeyboard(); this.sidebarOpen = false; return true; } return false; }
  private storeChanged(): void {
    if (this.store.reminderQuietSeq !== this.quietSeq) {
      this.quietSeq = this.store.reminderQuietSeq;
      this.quietNotice = this.store.reminderQuiet ? this.reminderQuietText(this.store.reminderQuiet) : '';
    }
    this.tryConsumeLaunch();
    if (!this.store.models.length || this.store.pane !== 'chat') { this.closePopups(); }
    const session = this.store.connected + '/' + this.store.sessionID;
    if (session !== this.viewSession) { this.closePopups(); if (this.store.pane.startsWith('panel-') && this.panelScope !== session) { this.store.pane = 'chat'; } this.viewSession = session; this.focusedMessage = ''; this.viewContent = ''; this.sessionSearch = ''; this.reasoningOpen = []; this.reasoningClosed = []; this.activeReasoning = []; if (this.sheetKind === 'tool' || this.sheetKind === 'session' || this.sheetKind === 'attachment' || this.sheetKind === 'model' || this.sheetKind === 'agent' || this.sheetKind === 'export' || this.sheetKind === 'fork' || this.sheetKind === 'usage') { this.toolSheetOpen = false; } this.follow = true; this.quietNotice = ''; this.reminders.refreshPermission(); }
    this.syncNavigation();
    if (this.viewMessages === this.store.messages && this.viewInteractions === this.store.interactions) { return; }
    this.viewMessages = this.store.messages; this.viewInteractions = this.store.interactions;
    const active = this.store.messages.filter((m: ChatMessage) => reasoningInProgress(m)).map((m: ChatMessage) => m.id);
    const ended = this.activeReasoning.filter((id: string) => active.indexOf(id) < 0);
    const ids = this.store.messages.map((m: ChatMessage) => m.id);
    this.reasoningOpen = this.reasoningOpen.filter((id: string) => ended.indexOf(id) < 0 && ids.indexOf(id) >= 0);
    this.reasoningClosed = this.reasoningClosed.filter((id: string) => active.indexOf(id) >= 0);
    this.activeReasoning = active;
    if (this.panelVisible('tool')) { const tool = this.store.messages.flatMap((m: ChatMessage) => m.tools).find((t: ToolItem) => t.id === this.selectedTool.id); if (tool) { this.selectedTool = tool; } }
    this.messageSource.update(this.store.messages);
    const content = this.store.messages.map((message: ChatMessage) => messageKey(message)).join('|') + '/' + this.store.interactions.map((item: Interaction) => item.id).join('|');
    const changed = content !== this.viewContent; this.viewContent = content;
    if (changed && this.follow && this.store.pane === 'chat' && this.scrollTimer < 0) { this.scrollTimer = setTimeout(() => { this.scrollTimer = -1; if (this.follow && this.store.pane === 'chat') { this.scroller.scrollEdge(Edge.Bottom); } }, 40); }
  }
  private syncNavigation(): void {
    const names = this.navigation.getAllPathName();
    if (this.store.pane === 'chat') { if (names.length) { this.navigation.clear(); } return; }
    if (names[names.length - 1] === this.store.pane) { return; }
    const route = this.store.pane;
    // Replace atomically: an intermediate empty stack can be mistaken for a user return.
    if (names.length) { this.navigation.replacePath({ name: route, param: route }, false); }
    else { this.navigation.pushPath({ name: route, param: route }); }
  }
  private conversationVisibilityChanged(): void {
    if (!this.sidebarOpen && this.workspacePopupOpen) { this.workspacePopupOpen = false; }
    if (this.sidebarOpen) { this.attachmentPopupOpen = false; }
    this.store.conversationVisible = (!this.sidebarOpen || this.wide) && !this.toolSheetOpen && !this.modelPopupOpen && !this.workspacePopupOpen && !this.attachmentPopupOpen;
  }
  private showActions(): void { this.navigate('more'); }
  private dismissKeyboard(): void { try { this.getUIContext().getFocusController().clearFocus(); } catch (_) { } }
  private panelVisible(kind: string): boolean { return (kind === 'model' && this.modelPopupOpen) || this.store.pane === 'panel-' + kind || (this.toolSheetOpen && this.sheetKind === kind); }
  private closePanel(): void {
    this.dismissKeyboard(); this.toolSheetOpen = false; this.closePopups();
    if (this.store.pane === 'panel-export' && this.store.exporting) { this.store.cancelExport(); }
    if (this.store.pane.startsWith('panel-')) { this.store.pane = this.panelReturn; }
  }
  private openSheet(kind: string): void {
    this.dismissKeyboard(); this.closePopups(); this.sheetKind = kind;
    if (['agent', 'usage', 'fork', 'export', 'tool', 'search'].indexOf(kind) >= 0) {
      this.panelReturn = this.store.pane === 'more' ? 'more' : 'chat';
      this.panelScope = this.store.connected + '/' + this.store.sessionID;
      this.toolSheetOpen = false; this.store.pane = 'panel-' + kind;
    } else { this.toolSheetOpen = true; }
  }
  private changeAppearance(mode: string): void {
    const context = this.getUIContext().getHostContext();
    if (context) { Appearance.save(context as common.Context, mode).catch(() => { this.store.error = '外观设置未保存，请稍后重试。'; }); }
  }
  private pageTitle(name: string): string {
    if (name === 'model-library') { return this.modelLibraryFavorites ? '喜爱模型' : '启用模型'; }
    if (name === 'panel-search') { return '查找对话'; }
    if (name === 'panel-agent') { return '选择 Agent'; }
    if (name === 'panel-usage') { return '上下文与用量'; }
    if (name === 'panel-fork') { return this.forkEditing ? '编辑并分叉' : '创建会话分支'; }
    if (name === 'panel-export') { return '导出当前会话'; }
    if (name === 'panel-tool') { return '工具调用详情'; }
    if (name === 'more') { return '更多功能'; }
    if (name === 'provider-auth') { return '连接模型'; }
    return name === 'pending' ? '待办中心' : name === 'connections' ? '服务器连接' : name === 'projects' ? '项目与会话' : name === 'settings' ? '模型与接入' : name === 'appearance' ? '外观' : name === 'reminders' ? '任务提醒' : name === 'storage' ? '存储与流量' : '代码审查';
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
    return this.sheetKind === 'attachment';
  }
  // One tinted glass surface for every bindSheet so sheets, drawer and composer share the same tone.
  @Builder
  sheetSurface() {
    if (this.isLargeSheet()) {
      Column() {
        this.sheetContent()
      }
      .width('100%').height('100%').backgroundColor(C.surface)
      .border({ width: { top: 1 }, color: C.glass_stroke })
      .borderRadius({ topLeft: 20, topRight: 20 }).clip(true)
    } else {
      Column() {
        this.sheetContent()
      }
      .width('100%').backgroundColor(Color.Transparent)
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
      this.closePopups();
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
    this.pendingLaunch = undefined; this.closePopups(); this.consumingLaunch = true; this.follow = true;
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
    Text(label).fontSize(12).fontFamily('monospace').letterSpacing(0.6).fontColor(C.secondary)
      .padding({ left: 7, right: 7, top: 3, bottom: 3 })
      .backgroundColor(color).border({ width: 1, color: C.separator }).borderRadius(4)
  }
  @Builder
  heading(title: string, subtitle: string) {
    Column({ space: 6 }) {
      Text(title).fontSize(23).fontWeight(FontWeight.Bold).letterSpacing(-0.4).fontColor(C.text).width('100%')
      if (subtitle) {
        Text(subtitle).fontSize(16).fontColor(C.secondary).lineHeight(24).width('100%')
      }
    }.width('100%').alignItems(HorizontalAlign.Start).padding({ top: 10, bottom: 14 })
  }
  @Builder
  homeWelcome() {
    Column({ space: 0 }) {
      Row() { CodeMark({ markSize: 48 }) }.width('100%').height(104).justifyContent(FlexAlign.Center).accessibilityLevel('no')
      Text(this.store.connected ? '想法，从这里开始' : '把想法，变成作品').fontSize(24).fontWeight(FontWeight.Bold)
        .fontColor(C.text).width('100%').textAlign(TextAlign.Center)
      Text(this.store.connected && this.store.directory ? '描述一个任务，或继续之前的对话。' : '连接你的 OpenCode，开启自己的开发空间。')
        .fontSize(15).lineHeight(24).fontColor(C.secondary).width('100%').textAlign(TextAlign.Center).margin({ top: 12 })
      Row({ space: 10 }) {
        Button(!this.store.connected ? '连接服务器' : !this.store.directory ? '选择项目' : '新建对话', { type: ButtonType.Normal })
          .id('welcome-action').constraintSize({ minHeight: 44 }).fontSize(15).fontWeight(FontWeight.Medium)
          .backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(16).enabled(!this.store.busy)
          .onClick(() => { this.newChat(); })
        Button(this.store.connected ? '切换项目' : '连接设置', { type: ButtonType.Normal })
          .constraintSize({ minHeight: 44 }).fontSize(15).backgroundColor(C.surface).fontColor(C.accent).borderRadius(16)
          .enabled(!this.store.busy).onClick(() => { this.navigate(this.store.connected ? 'projects' : 'connections'); })
      }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 20, bottom: 24 })
      if (this.store.connected && this.store.directory && this.store.recentSessions().length) {
        Row() {
          Text('继续上次的思路').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1)
          Button('全部会话').fontSize(14).fontColor(C.accent).buttonStyle(ButtonStyleMode.TEXTUAL).height(44)
            .onClick(() => { this.navigate('projects'); })
        }.width('100%').margin({ bottom: 10 })
        Column({ space: 10 }) {
          ForEach(this.store.recentSessions().slice(0, 3), (session: SessionItem) => {
            Button({ type: ButtonType.Normal }) {
              Row({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.doc_text')).fontSize(18).fontColor([C.accent])
                Text(session.title || '未命名会话').fontSize(15).fontColor(C.text).maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1).textAlign(TextAlign.Start)
                if (this.store.sessionLabel(session.id)) { Text(this.store.sessionLabel(session.id)).fontSize(12).fontColor(C.warning) }
                SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([C.muted])
              }.width('100%').padding(16)
            }.id('recent-session-' + session.id).width('100%').constraintSize({ minHeight: 52 }).backgroundColor(C.surface).borderRadius(18)
              .onClick(() => { this.pickSession(session); })
          }, (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id))
        }.width('100%')
      }
      if (this.store.connected) {
        Row({ space: 6 }) {
          StatusLed({ color: C.success })
          Text(this.serverName() + (this.store.directory ? ' · ' + this.projectName() : '')).fontSize(13).fontColor(C.secondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.width('100%').justifyContent(FlexAlign.Center).margin({ top: 24 })
      }
    }.width('100%').padding({ left: 2, right: 2, top: 10, bottom: 24 }).alignItems(HorizontalAlign.Center)
  }

  @Builder
  connections() {
    Scroll(this.connectionScroller) {
      Column({ space: 20 }) {
        this.heading('连接管理', '添加或切换你的 OpenCode 服务器；凭据保存于系统安全资产。')
        ForEach(this.store.servers, (server: ServerConfig) => {
          Column({ space: 10 }) {
            Row() {
              Column({ space: 4 }) {
                Text(server.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text)
                Text(server.url).fontSize(12).fontFamily('monospace').fontColor(C.muted).maxLines(2)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              if (this.store.connected === server.id) {
                Row({ space: 5 }) {
                  StatusLed({ color: C.success })
                  Text('CONNECTED').fontSize(12).fontFamily('monospace').letterSpacing(0.8).fontColor(C.success)
                }
              }
            }
            Row({ space: 8 }) {
              Button('连接', { type: ButtonType.Normal }).id('connect-server-' + server.id).backgroundColor(C.btn).fontColor(C.btn_text)
                .fontSize(16).borderRadius(14).constraintSize({ minHeight: 48 }).layoutWeight(1).enabled(!this.store.busy && !this.store.serverSaving)
                .onClick(() => { this.store.connect(server).then(() => { if (this.store.connected) { this.store.pane = 'chat'; } }); })
              Button('编辑', { type: ButtonType.Normal }).id('edit-server-' + server.id).height(32).fontSize(15)
                .backgroundColor(Color.Transparent).fontColor(C.text).borderRadius(14).border({ width: 1, color: C.separator })
                .enabled(!this.store.serverSaving && !this.store.busy)
                .onClick(() => { this.store.editServer(server); setTimeout(() => { this.connectionScroller.scrollEdge(Edge.Bottom); }, 50); })
              Button('移除', { type: ButtonType.Normal }).id('remove-server-' + server.id).height(32).fontSize(15)
                .backgroundColor(Color.Transparent).fontColor(C.danger).borderRadius(14).border({ width: 1, color: C.separator })
                .enabled(!this.store.serverSaving && !this.store.busy).onClick(() => { this.confirmRemoveServer(server); })
            }
          }.id('server-profile-' + server.id).padding(20).backgroundColor(C.surface)
            .border({ width: 1, color: C.separator }).borderRadius(20).width('100%')
        }, (server: ServerConfig) => server.id + server.name + server.url + server.username + String(server.id === this.store.connected))
        Button('添加服务器', { type: ButtonType.Normal }).id('add-server').width('100%').constraintSize({ minHeight: 48 })
          .fontSize(16).fontColor(C.accent).backgroundColor(C.accent_soft).borderRadius(16)
          .onClick(() => { this.store.resetServerForm(); this.connectionFormOpen = true; setTimeout(() => { this.connectionScroller.scrollEdge(Edge.Bottom); }, 80); })
        if (this.connectionFormOpen || !!this.store.serverEditID || !this.store.servers.length) {
        Column({ space: 16 }) {
          Text(this.store.serverEditID ? '编辑连接' : '添加服务器').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          TextInput({ placeholder: '连接名称，例如：我的开发服务器', text: this.store.serverName }).id('server-name').maxLength(80).enabled(!this.store.serverSaving && !this.store.busy)
            .fontSize(16).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverName = value; })
            .backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(14).constraintSize({ minHeight: 48 })
          TextInput({ placeholder: 'https://opencode.example.com', text: this.store.serverUrl }).id('server-url').maxLength(2048).enabled(!this.store.serverSaving && !this.store.busy)
            .fontSize(16).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverUrl = value; })
            .backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(14).constraintSize({ minHeight: 48 })
          Row({ space: 10 }) {
            TextInput({ placeholder: 'API 用户名', text: this.store.serverUser }).id('server-user').maxLength(120).enabled(!this.store.serverSaving && !this.store.busy)
              .fontSize(16).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverUser = value; })
              .layoutWeight(1).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(14)
            TextInput({ placeholder: this.store.serverEditID ? '密码留空保留原密码' : 'API 密码', text: this.store.serverPassword }).id('server-password').maxLength(2048).enabled(!this.store.serverSaving && !this.store.busy).type(InputType.Password)
              .fontSize(16).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.serverPassword = value; })
              .layoutWeight(1).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(14)
          }
          Row({ space: 8 }) {
            Checkbox({ name: 'allow-http' }).id('allow-http').enabled(!this.store.serverSaving && !this.store.busy).select(this.store.allowHttp).selectedColor(C.accent).width(22).height(22).responseRegion({ x: -9, y: -9, width: 40, height: 40 })
              .onChange((value: boolean) => { this.store.allowHttp = value; })
            Text('允许 HTTP（仅可信局域网或本地隧道）').id('allow-http-label').fontSize(16).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 40 })
              .onClick(() => { if (!this.store.serverSaving && !this.store.busy) { this.store.allowHttp = !this.store.allowHttp; } })
          }.width('100%')
          Row({ space: 8 }) {
            Checkbox({ name: 'dedicated-trust' }).id('dedicated-trust').enabled(!this.store.serverSaving && !this.store.busy).select(this.store.useDedicatedTrust)
              .selectedColor(C.accent).width(22).height(22).responseRegion({ x: -9, y: -9, width: 40, height: 40 })
              .onChange((value: boolean) => { this.store.useDedicatedTrust = value; })
            Text('使用专用服务器证书（IP 临时入口）').id('dedicated-trust-label').fontSize(16).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 40 })
              .onClick(() => { if (!this.store.serverSaving && !this.store.busy) { this.store.useDedicatedTrust = !this.store.useDedicatedTrust; } })
          }.width('100%')
          if (this.store.serverEditID) {
            Row({ space: 8 }) {
              Checkbox().id('server-clear-password').select(this.store.clearServerPassword).width(22).height(22).responseRegion({ x: -9, y: -9, width: 40, height: 40 }).enabled(!this.store.serverSaving)
                .onChange((value: boolean) => { this.store.clearServerPassword = value; })
              Text('清除已保存密码').id('server-clear-password-label').fontSize(16).fontColor(C.secondary).layoutWeight(1).constraintSize({ minHeight: 40 })
              .onClick(() => { if (!this.store.serverSaving && !this.store.busy) { this.store.clearServerPassword = !this.store.clearServerPassword; } })
            }.width('100%')
            Text('修改地址或账号会清理此连接旧的本机会话位置、书签与模型偏好。密码留空会保留原密码。').fontSize(12).fontColor(C.muted).width('100%')
            Button('取消编辑').id('server-cancel-edit').height(30).fontSize(14).buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.secondary)
              .enabled(!this.store.serverSaving).onClick(() => { this.store.resetServerForm(); this.store.error = ''; this.store.serverNotice = ''; })
          }
          if (this.store.serverNotice) { Text(this.store.serverNotice).id('server-notice').fontSize(14).fontColor(C.secondary).width('100%') }
          Button(this.store.serverSaving ? '正在保存…' : '保存并连接', { type: ButtonType.Normal }).id('connect-button')
            .width('100%').constraintSize({ minHeight: 48 }).borderRadius(14).backgroundColor(C.btn).fontColor(C.btn_text).fontSize(16).fontWeight(FontWeight.Medium)
            .enabled(!this.store.busy && !this.store.serverSaving)
            .onClick(() => { this.store.saveServer().then((saved: boolean) => { if (saved && this.store.connected) { this.store.pane = 'chat'; } }); })
        }.padding(16).backgroundColor(C.surface).border({ width: 1, color: C.separator }).borderRadius(20).width('100%')
        }
        Text('支持 OpenCode V2 · 凭据存储在系统安全资产中').fontSize(14).fontColor(C.muted).margin({ bottom: 22 })
      }.padding({ left: 18, right: 18 }).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }

  @Builder
  projects() {
    Scroll() {
      Column({ space: 10 }) {
        this.heading('选择项目', '选择一个仓库，继续对话或开始新的任务。')
        ForEach(this.store.projects, (project: ProjectItem) => {
          Row({ space: 11 }) {
            Stack() {
              SymbolGlyph($r('sys.symbol.folder')).fontSize(16).fontColor([C.secondary])
            }.width(30).height(30).backgroundColor(C.field).borderRadius(8)
            Column({ space: 3 }) {
              Text(project.name || '项目').fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text)
              Text(project.directory).fontSize(12).fontFamily('monospace').fontColor(C.muted).maxLines(2)
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
            if (project.directory === this.store.directory) { StatusLed({ color: C.accent }) }
            SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([C.muted])
          }.width('100%').padding({ left: 12, right: 12, top: 10, bottom: 10 })
            .backgroundColor(project.directory === this.store.directory ? C.chip : C.surface)
            .border({ width: 1, color: project.directory === this.store.directory ? C.accent_soft : C.separator })
            .borderRadius(10).onClick(() => { this.dismissKeyboard(); this.store.selectProject(project.directory); })
        }, (project: ProjectItem) => project.id + project.directory)
        Row({ space: 8 }) {
          TextInput({ placeholder: '服务器已有工作目录的绝对路径', text: this.store.manualPath }).id('project-path')
            .fontSize(14).fontColor(C.text).placeholderColor(C.muted).onChange((value: string) => { this.store.manualPath = value; })
            .layoutWeight(1).backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8).height(36)
          Button('打开', { type: ButtonType.Normal }).id('open-project').backgroundColor(C.field).fontColor(C.text)
            .fontSize(15).borderRadius(8).height(32).border({ width: 1, color: C.separator }).enabled(!this.store.busy)
            .onClick(() => { this.store.selectProject(this.store.manualPath); })
        }.margin({ top: 6 })
        if (this.store.directory) {
          Row({ space: 8 }) {
            Text('会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1)
            Button('新建对话', { type: ButtonType.Normal }).id('new-session').backgroundColor(C.btn).fontColor(C.btn_text)
              .fontSize(16).fontWeight(FontWeight.Medium).borderRadius(8).height(36).enabled(!this.store.busy)
              .onClick(() => { this.store.createSession(); })
          }.margin({ top: 14 }).width('100%')
          this.sessionFilters()
          ForEach(this.store.sessionRows(), (session: SessionItem) => { this.sessionRow(session, false) },
            (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id) + String(this.store.isPinned(session.id)))
          this.sessionPaging()
          if (this.store.sessions.length === 0) { Text('还没有会话，创建第一个任务。').fontSize(14).fontColor(C.muted).padding(20) }
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
    this.dismissKeyboard(); this.closePopups(); this.toolSheetOpen = false; this.sidebarOpen = false;
    if (pane === 'reminders') { this.store.pane = 'reminders'; this.reminders.load(); }
    else if (pane === 'settings') { this.store.openSettings(); }
    else if (pane === 'pending') { this.store.pane = 'pending'; this.store.refreshPending(true); }
    else if (pane === 'review') { this.store.openReview(); }
    else { this.store.pane = pane; }
  }
  private newChat(): void {
    this.dismissKeyboard(); this.closePopups(); this.sidebarOpen = false; this.follow = true;
    if (!this.store.connected) { this.navigate('connections'); }
    else if (!this.store.directory) { this.navigate('projects'); }
    else { this.store.createSession(); }
  }
  private projectName(): string { return this.store.directory.split('/').filter((value: string) => !!value).pop() || '选择项目'; }
  private async pickSession(session: SessionItem): Promise<void> { this.dismissKeyboard(); this.closePopups(); this.sidebarOpen = false; this.follow = true; await this.store.openSession(session); }
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
        Text(item.kind === 'form' ? '需要你的回答' : '等待操作审批').fontSize(12).fontFamily('monospace')
          .letterSpacing(0.8).fontColor(item.kind === 'form' ? C.accent : C.warning)
        Blank()
        Text(this.store.itemState(item.id) === 'submitting' ? '提交中…' : this.store.itemState(item.id) === 'error' ? '待核对' : '待处理')
          .fontSize(12).fontFamily('monospace').fontColor(C.muted)
      }.width('100%')
      Text(item.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      if (item.detail) {
        Text(item.detail).fontSize(12).fontFamily('monospace').fontColor(C.secondary)
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
          .backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(7).height(32).fontSize(15).layoutWeight(1)
          .enabled(this.store.itemState(item.id) !== 'submitting' && (item.kind === 'form' || this.store.canApprove(item.id)))
          .onClick(() => { this.follow = true; this.store.reply(item); })
        Button(item.kind === 'form' ? '取消' : '拒绝', { type: ButtonType.Normal }).id('interaction-reject-' + item.id)
          .backgroundColor(Color.Transparent).fontColor(C.secondary).borderRadius(7).height(32).fontSize(15)
          .border({ width: 1, color: C.separator })
          .enabled(this.store.itemState(item.id) !== 'submitting')
          .onClick(() => { this.follow = true; this.store.reply(item, true); })
      }.width('100%')
    }.id('interaction-card-' + item.id).padding(14).backgroundColor(C.surface)
      .border({ width: 1, color: C.separator }).borderRadius(10).width('100%')
  }

  private chatStatus(): string {
    if (this.store.cacheRestored) { return '本机缓存 · 正在等待联网核对'; }
    if (this.pickingAttachments) { return '正在读取附件…'; }
    if (this.store.pendingSend) { return '发送结果待核对 · 点击同步'; }
    if (this.store.interrupting) { return '正在停止…'; }
    if (this.store.modelUncertain) { return '模型设置待确认 · 点击核对'; }
    if (this.store.agentUncertain) { return 'Agent 待确认'; }
    if (this.store.interactions.length) { return '有 ' + this.store.interactions.length + ' 项待处理 · 点击查看'; }
    if (this.store.working) { return '正在生成…'; }
    if (this.store.draftNotice) { return this.store.draftNotice; }
    if (this.quietNotice) { return this.quietNotice + ' · 点击收起'; }
    return this.store.status || '未连接';
  }
  @Builder
  composerStatus() {
    Text(this.chatStatus()).id(this.store.pendingSend ? 'verify-send' : 'chat-status').fontSize(9).lineHeight(10).fontColor(C.secondary).maxLines(1)
      .textOverflow({ overflow: TextOverflow.Ellipsis }).width('88%').height(10).textAlign(TextAlign.Center)
      .position({ x: '50%', y: '100%' }).translate({ x: '-50%', y: -10 })
      .accessibilityText(this.chatStatus()).onClick(() => {
        if ((this.store.pendingSend || this.store.modelUncertain) && !this.store.busy) { this.store.sync(); }
        else if (this.store.interactions.length) { this.navigate('pending'); }
        else if (this.quietNotice) { this.quietNotice = ''; }
      })
  }
  @Builder
  chatHeading() {
    Column({ space: 4 }) {
      if (this.store.connected) {
        Row({ space: 10 }) {
          Text(this.store.sessionTitle || '新对话').id('conversation-title').fontSize(13).fontColor(C.secondary)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).padding({ left: 12, right: 12, top: 8, bottom: 8 })
            .constraintSize({ maxWidth: Math.max(110, (this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0)) * 0.58) }).flexShrink(1)
            .backgroundEffect({ radius: 24, saturation: 1.15, color: C.glass_fill })
            .border({ width: 0.5, color: C.glass_stroke }).borderRadius(999)
          Blank().layoutWeight(1)
          if (this.store.sessionID) {
            Button(this.store.agents.find((a: AgentItem) => a.id === this.store.agentID)?.name || this.store.agentID || '默认 Agent', { type: ButtonType.Normal })
              .id('agent-select').fontSize(13).fontColor(C.secondary).height(40)
              .labelStyle({ maxLines: 1, overflow: TextOverflow.Ellipsis }).constraintSize({ maxWidth: 140 })
              .padding({ left: 12, right: 12 }).backgroundColor(Color.Transparent).backgroundEffect({ radius: 24, saturation: 1.15, color: C.glass_fill })
              .border({ width: 0.5, color: C.glass_stroke }).borderRadius(999).accessibilityText('选择会话 Agent')
              .onClick(() => { this.openSheet('agent'); this.store.refreshAgentState(); })
          }
        }.width('100%').height(44)
      }
      if (this.store.parentSessionID) {
        Row({ space: 8 }) {
          Text(this.store.branchBoundary ? '分叉会话 · ' + this.store.branchBoundary : '子会话')
            .fontSize(12).fontColor(C.secondary).layoutWeight(1).maxLines(1)
          Button('原会话').id('branch-parent').height(26).fontSize(13).buttonStyle(ButtonStyleMode.TEXTUAL)
            .fontColor(C.accent).onClick(() => { this.store.openParentSession(); })
        }.width('100%').padding({ left: 10, right: 6 }).backgroundColor(C.glass_fill).borderRadius(14)
      }
      if (this.store.permissionError) {
        Row({ space: 8 }) {
          Text(this.store.permissionError).id('permission-sync-error').fontSize(14).fontColor(C.warning).layoutWeight(1)
          Button('重新读取审批', { type: ButtonType.Normal }).id('permission-retry').fontSize(13).height(28)
            .backgroundColor(C.warning_bg).fontColor(C.warning).borderRadius(8).onClick(() => { this.store.retryPermissions(); })
        }.width('100%').padding(8).backgroundColor(C.glass_strong).borderRadius(14)
      }
    }.id('chat-heading').padding({ left: 16, right: 16, top: 2, bottom: 4 }).width('100%').constraintSize({ maxWidth: 860 })
      .position({ x: '50%', y: 0 }).translate({ x: '-50%' }).onAreaChange((_old: Area, area: Area): void => {
        const height = Number(area.height); if (Math.abs(this.chatHeadingHeight - height) > 0.5) { this.chatHeadingHeight = height; }
      })
  }
  @Builder
  chat() {
    Stack({ alignContent: Alignment.Bottom }) {
      List({ space: 4, scroller: this.scroller }) {
        if (this.store.cursor) {
          ListItem() {
            Button('加载更早消息', { type: ButtonType.Normal }).id('older-messages').fontSize(14).width('100%').height(32)
              .backgroundColor(Color.Transparent).fontColor(C.muted).enabled(!this.store.busy)
              .onClick(() => { this.follow = false; this.store.older(); })
          }
        }
        if (!this.store.messages.length && !this.store.interactions.length && !this.store.busy) {
          ListItem() { this.homeWelcome() }
        }
        LazyForEach(this.messageSource, (message: ChatMessage) => { ListItem() { this.messageCard(message) }.backgroundColor(message.id === this.focusedMessage ? C.field : Color.Transparent).borderRadius(14) }, (message: ChatMessage) => messageKey(message))
        ForEach(this.store.interactions, (item: Interaction) => { ListItem() { this.interactionCard(item) } }, (item: Interaction) => interactionKey(item))
      }.onTouch((event: TouchEvent) => { if (event.type === TouchType.Down) { this.follow = false; } }).id('conversation-list').padding({ left: 22, right: 22 }).height('100%').width('100%')
        .contentStartOffset(this.chatHeadingHeight + 6).contentEndOffset(this.composerHeight + 12).constraintSize({ maxWidth: 860 }).scrollBar(BarState.Off)
        .onScrollFrameBegin((offset: number, state: ScrollState) => { if (state === ScrollState.Scroll && offset < 0) { this.follow = false; } return { offsetRemain: offset }; })
        .onReachEnd(() => { this.follow = true; })
      this.chatHeading()
      Column({ space: 6 }) {
        if (this.store.attachments.length) {
          AttachmentStrip({ items: this.store.attachments, editable: true, locked: this.pickingAttachments || !!this.store.pendingSend || this.store.busy,
            onOpen: (item: Attachment): void => { this.openAttachment(item); }, onRemove: (id: string): void => { this.store.removeAttachment(id); }, onRetry: (item: Attachment): void => { this.pickAttachments(false, item); } })
          if (attachmentProblem(this.store.attachments, this.store.attachmentInput())) { Text(attachmentProblem(this.store.attachments, this.store.attachmentInput())).fontSize(12).fontColor(C.warning).width('100%') }
        }
        if ((this.store.messages.length > 0 && (!this.follow || this.store.readingHistory || this.store.newerAvailable)) || this.store.interactions.length || (this.store.working && (!!this.store.draft.trim() || !!this.store.attachments.length))) {
          Row({ space: 8 }) {
            if (this.store.messages.length > 0 && (!this.follow || this.store.readingHistory || this.store.newerAvailable)) {
              Button({ type: ButtonType.Capsule }) {
                Row({ space: 5 }) {
                  SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(14).fontColor([C.secondary]).rotate({ angle: 180 })
                  Text('回到最新').fontSize(14).fontColor(C.secondary)
                }
              }.id('jump-latest').height(32).padding({ left: 10, right: 10 }).responseRegion({ x: -4, y: -6, width: 110, height: 40 })
                .backgroundColor(Color.Transparent).backgroundEffect({ radius: 24, saturation: 1.15, color: C.glass_fill }).border({ width: 0.5, color: C.glass_stroke }).borderRadius(999)
                .shadow({ radius: 10, color: C.glass_shadow, offsetY: 3 })
                .onClick(() => { this.follow = true; if (this.store.readingHistory) { this.store.latest(); } else { this.scroller.scrollEdge(Edge.Bottom); } })
            }
            Blank()
            if (this.store.interactions.length) {
              Button('待处理 ' + this.store.interactions.length).id('pending-interactions').fontSize(12).fontFamily('monospace').height(28)
                .backgroundColor(C.warning_bg).fontColor(C.warning).borderRadius(8)
                .onClick(() => { this.follow = false; this.scroller.scrollEdge(Edge.Bottom); })
            }
            if (this.store.working && (this.store.draft.trim() || this.store.attachments.length)) {
              Button('停止生成').id('stop-secondary').fontSize(14).height(28)
                .backgroundColor(Color.Transparent).fontColor(C.danger).enabled(!this.store.interrupting)
                .onClick(() => { this.store.interrupt(); })
            }
          }.width('100%').height(36)
        }
        Row({ space: 6 }) {
          Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.plus')).fontSize(18).fontColor([C.secondary]) }
            .id('attachment-add').accessibilityText('添加附件').width(40).height(40).padding(0).margin({ bottom: 1 }).backgroundColor(Color.Transparent)
            .enabled(!!this.store.sessionID && !this.store.busy && !this.store.pendingSend && !this.pickingAttachments)
            .onClick(() => { this.dismissKeyboard(); this.store.error = ''; this.modelPopupOpen = false; this.workspacePopupOpen = false; this.attachmentPopupOpen = !this.attachmentPopupOpen; })
            .bindPopup(this.attachmentPopupOpen, this.surfacePopupOptions('attachment'))
          TextArea({ placeholder: this.store.sessionID ? '发消息，或描述一个任务…' : '选择项目后开始对话', text: this.store.draft }).id('chat-input')
            .minLines(1).maxLines(5).constraintSize({ minHeight: 42, maxHeight: 148 }).maxLength(20000).layoutWeight(1).fontSize(15).fontWeight(FontWeight.Normal).lineHeight(22)
            .padding({ left: 0, right: 0, top: 10, bottom: 10 }).fontColor(C.text).placeholderColor(C.muted).caretColor(C.accent)
            .backgroundColor(Color.Transparent).borderRadius(0).enabled(!this.store.pendingSend && !!this.store.sessionID).onChange((value: string) => { this.store.updateDraft(value); })
          if (this.store.working && !this.store.draft.trim() && !this.store.attachments.length && !this.store.pendingSend) {
            Button({ type: ButtonType.Circle }) { Text('■').fontSize(16).fontColor(C.danger) }
              .id('stop-button').accessibilityText('停止生成').width(40).height(40).padding(0)
              .backgroundColor(C.danger_bg).margin({ bottom: 1 }).enabled(!this.store.interrupting)
              .onClick(() => { this.store.interrupt(); })
          } else {
            Button({ type: ButtonType.Circle }) {
              if (this.store.pendingSend) { Text('重试').fontSize(12).fontColor(C.btn_text) }
              else {
                SymbolGlyph($r('sys.symbol.arrow_up')).fontSize(17)
                  .fontColor([this.store.draft.trim() || this.store.attachments.length ? C.btn_text : C.muted])
              }
            }.id('send-button').accessibilityText(this.store.pendingSend ? '重试发送' : '发送消息').width(40).padding(0).height(40).margin({ bottom: 1 })
              .backgroundColor(this.store.draft.trim() || this.store.attachments.length || this.store.pendingSend ? C.btn : C.field)
              .enabled(this.store.canSendMessages() && !this.store.busy && !this.store.modelBusy && !this.store.modelUncertain && !this.store.agentBusy && !this.store.agentUncertain && !this.store.forkBusy && !this.store.compactionBusy && ['submitting', 'queued', 'running'].indexOf(this.store.compaction.state) < 0 && !this.pickingAttachments && !!this.store.sessionID && (!!this.store.draft.trim() || !!this.store.attachments.length || !!this.store.pendingSend))
              .onClick(() => { this.follow = true; this.store.send(); })
          }
        }.id('composer-field').alignItems(VerticalAlign.Bottom).padding({ left: 5, right: 7, top: 6, bottom: 6 }).width('100%')
          .backgroundEffect({ radius: 22, saturation: 1.15, brightness: 1.0, color: C.glass_fill })
          .border({ width: 1, color: C.glass_stroke })
          .borderRadius(24)
          .shadow({ radius: 18, color: C.glass_shadow, offsetX: 0, offsetY: 6 })
          .clip(true)
        if (this.store.draft.length > 1000) {
          Text(String(this.store.draft.length) + ' / 20000').fontSize(12).fontFamily('monospace').fontColor(C.muted)
            .width('100%').textAlign(TextAlign.End)
        }
      }.id('chat-composer').padding({ left: 16, right: 16, top: 8, bottom: 10 }).width('100%').constraintSize({ maxWidth: 860 })
        .align(Alignment.Bottom)
        .onAreaChange((_old: Area, area: Area): void => { const height = Number(area.height); if (Math.abs(this.composerHeight - height) > 0.5) { this.composerHeight = height; } })
      this.composerStatus()
    }.id('chat-stage').layoutWeight(1).width('100%').clip(false).backgroundColor(C.page)
  }
  @Builder
  diffCard(diff: DiffItem) { DiffContent({ diff: diff, onCopy: (text: string): void => { this.copy(text); } }) }
  @Builder
  review() {
    Scroll() {
      Column({ space: 10 }) {
        this.heading('看看发生了什么', '查看工作区现状，或按会话任务回看文件修改。')
        NativeSegments({ first: 'Git Diff', second: '会话修改', third: '文件浏览',
          selected: this.store.reviewTab === 'diff' ? 0 : this.store.reviewTab === 'timeline' ? 1 : 2,
          onSelect: (index: number): void => { this.store.reviewTab = index === 0 ? 'diff' : index === 1 ? 'timeline' : 'files';
            if (index === 1 && !this.store.timelineLoaded) { this.store.loadTimeline(); } } }).id('review-segments')
        Row() {
          Text(this.store.reviewTab === 'timeline' ? '会话任务快照' : this.store.reviewTab === 'files' ? '项目文件' : '工作区修改')
            .fontSize(12).fontFamily('monospace').letterSpacing(1).fontColor(C.muted).layoutWeight(1)
          Button('刷新', { type: ButtonType.Normal }).controlSize(ControlSize.SMALL).buttonStyle(ButtonStyleMode.TEXTUAL).fontColor(C.accent)
            .onClick(() => {
              if (this.store.reviewTab === 'timeline') { this.store.loadTimeline(); } else { this.store.openReview(); }
            })
        }.width('100%')
        if (this.store.reviewTab === 'diff') {
          ForEach(this.store.diffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => diffKey(diff))
          if (this.store.diffs.length === 0) {
            Text(this.store.reviewLoaded ? '当前没有可显示的修改。' : this.store.error ? '读取修改失败，请刷新重试。' : '正在读取修改…')
              .fontSize(14).fontColor(C.muted).padding(24)
          }
        } else if (this.store.reviewTab === 'timeline') {
          Text('同一轮任务中的追加消息合并显示。运行中的 Diff 随文件变化，点击刷新可重新读取。')
            .fontSize(14).fontColor(C.secondary).width('100%')
          if (this.store.timelineError) { Text(this.store.timelineError).fontSize(14).fontColor(C.warning).width('100%') }
          ForEach(this.store.turns, (turn: TurnItem) => {
            Row({ space: 10 }) {
              Column({ space: 4 }) {
                Text(turn.title).fontSize(16).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).fontColor(C.text).width('100%')
                Text((turn.created ? new Date(turn.created).toLocaleString() + ' · ' : '') + turn.prompts + ' 条消息 · ' +
                  (turn.partial ? '需加载更早记录确认起点' : turn.state === 'running' ? '尚未结束' : turn.state === 'failed' ? '任务未成功' : '已结束'))
                  .fontSize(12).fontFamily('monospace').fontColor(C.muted).width('100%')
              }.layoutWeight(1)
              Text(turn.id === this.store.turnID ? '已选择' : '查看').fontSize(14)
                .fontColor(turn.id === this.store.turnID ? C.accent : C.muted)
            }.id('turn-' + turn.id).padding(12).width('100%').borderRadius(8)
              .backgroundColor(turn.id === this.store.turnID ? C.chip : C.surface)
              .border({ width: 1, color: turn.id === this.store.turnID ? C.accent_soft : C.separator })
              .onClick(() => { this.store.selectTurn(turn); })
          }, (turn: TurnItem) => turn.id + turn.state + turn.prompts + String(turn.partial))
          if (this.store.timelineCursor) {
            Button(this.store.canLoadTimeline() ? '加载更早任务' : '已达到最近 300 条记录的窗口上限', { type: ButtonType.Normal })
              .id('timeline-older').fontSize(14).fontColor(C.secondary).height(32)
              .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
              .enabled(!this.store.timelineBusy && this.store.canLoadTimeline())
              .onClick(() => { this.store.loadTimeline(true); })
          }
          if (this.store.timelineBusy) { Text('正在读取任务记录…').fontSize(14).fontColor(C.muted) }
          if (this.store.timelineLoaded && !this.store.turns.length) { Text('这个会话还没有任务记录。').fontSize(14).fontColor(C.muted) }
          if (this.store.turnID) {
            Text('所选任务的文件修改').fontSize(16).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%').margin({ top: 6 })
            if (this.store.turnError) { Text('读取失败：' + this.store.turnError).fontSize(14).fontColor(C.warning).width('100%') }
            if (this.store.turnBusy) { Text('正在比较任务快照…').fontSize(14).fontColor(C.muted) }
            ForEach(this.store.turnDiffs, (diff: DiffItem) => { this.diffCard(diff) }, (diff: DiffItem) => this.store.turnID + ':' + diffKey(diff))
            if (this.store.turnLoaded && !this.store.turnDiffs.length) { Text('这轮任务没有文件修改。').fontSize(14).fontColor(C.muted) }
          }
        } else {
          Button('返回项目根目录', { type: ButtonType.Normal }).fontSize(14).height(28).fontColor(C.secondary)
            .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
            .onClick(() => { this.store.openReview(); })
          ForEach(this.store.files, (file: FileItem) => {
            Row({ space: 9 }) {
              Stack() {
                SymbolGlyph(file.directory ? $r('sys.symbol.folder') : $r('sys.symbol.doc_text')).fontSize(17).fontColor([C.secondary])
              }.width(26).height(26).backgroundColor(C.field).borderRadius(6)
              Text(file.name).fontFamily('monospace').fontSize(14).layoutWeight(1).fontColor(C.text)
              SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor([C.muted])
            }.padding({ left: 10, right: 10, top: 9, bottom: 9 }).width('100%').backgroundColor(C.surface)
              .border({ width: 1, color: C.separator }).borderRadius(8)
              .onClick(() => { this.store.browse(file); })
          }, (file: FileItem) => file.path)
          if (this.store.fileContent) {
            Column({ space: 8 }) {
              if (this.store.fileTruncated) { Text('文件较长，仅显示前1500行或100000字；完整内容保留在服务器。').fontSize(12).fontColor(C.warning) }
              Text(this.store.filePath).fontSize(12).fontFamily('monospace').fontColor(C.secondary).width('100%')
              Text(this.store.fileContent).fontFamily('monospace').fontSize(14).lineHeight(22).fontColor(C.code_text)
                .copyOption(CopyOptions.InApp).width('100%')
            }.padding(12).backgroundColor(C.code_bg).borderRadius(10).width('100%')
          }
        }
      }.padding(18).width('100%')
    }.layoutWeight(1).align(Alignment.TopStart).scrollBar(BarState.Off)
  }
  private sidebarWidth(): number { return this.wide ? 280 : Math.min(320, this.viewportWidth * 0.84); }
  @Builder
  historyMenu() {
    Menu() {
      MenuItem({ content: '最近对话' }).id('history-recent').onClick(() => {
        this.store.showArchived = false;
        if (this.store.sessionQuery) { this.sessionSearch = ''; this.store.refreshSessions(false, ''); }
      })
      MenuItem({ content: '本机归档' }).id('history-archived').onClick(() => { this.store.showArchived = true; })
      MenuItem({ content: '刷新历史' }).id('history-refresh').enabled(!this.store.sessionsBusy && !!this.store.directory)
        .onClick(() => { this.store.refreshSessions(false, this.sessionSearch); })
    }
  }
  @Builder
  sidebar(width: number) {
    Column({ space: 0 }) {
      Row({ space: 8 }) {
        Button({ type: ButtonType.Normal }) {
          Row({ space: 6 }) {
            Text(this.store.showArchived ? '本机归档' : '历史对话').fontSize(16).fontWeight(FontWeight.Medium).fontColor(C.text)
            SymbolGlyph($r('sys.symbol.chevron_down')).fontSize(11).fontColor([C.muted])
          }
        }.id('history-filter').height(40).padding({ left: 8, right: 8 }).backgroundColor(Color.Transparent)
          .borderRadius(12).bindMenu(this.historyMenu(), this.glassMenuOptions()).accessibilityText('切换历史列表或刷新')
        Blank().layoutWeight(1)
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.square_and_pencil')).fontSize(19).fontColor([C.accent]) }
          .id('sidebar-new-chat').accessibilityText('新建对话').width(40).height(40).backgroundColor(C.glass_strong)
          .enabled(!this.store.busy).onClick(() => { this.newChat(); })
      }.width('100%').padding({ top: 4, bottom: 8 })
      Row({ space: 0 }) {
        TextInput({ placeholder: '搜索对话', text: this.sessionSearch }).id('history-search').fontSize(14).height(40)
          .fontColor(C.text).placeholderColor(C.muted).backgroundColor(Color.Transparent).layoutWeight(1)
          .enterKeyType(EnterKeyType.Search).onChange((value: string) => { this.sessionSearch = value; })
          .onSubmit(() => { if (!this.store.sessionsBusy && this.store.directory) { this.dismissKeyboard(); this.store.refreshSessions(false, this.sessionSearch); } })
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.magnifyingglass')).fontSize(16).fontColor([C.secondary]) }
          .id('history-search-server').accessibilityText('搜索服务器历史').width(40).height(40).backgroundColor(Color.Transparent)
          .enabled(!this.store.sessionsBusy && !!this.store.directory)
          .onClick(() => { this.dismissKeyboard(); this.store.refreshSessions(false, this.sessionSearch); })
      }.width('100%').backgroundColor(C.field).borderRadius(16).margin({ bottom: 10 })
      if (this.store.sessionQuery) {
        Text('服务器搜索：' + this.store.sessionQuery).fontSize(12).fontColor(C.muted).maxLines(1).width('100%').padding({ left: 8, bottom: 6 })
      }
      Scroll() {
        Column({ space: 3 }) {
          ForEach(this.store.sessionRows(this.sessionSearch), (session: SessionItem) => { this.sessionRow(session, true) },
            (session: SessionItem) => session.id + session.title + this.store.sessionLabel(session.id) + String(this.store.isPinned(session.id)))
          this.sessionPaging()
          if (!this.store.sessionRows(this.sessionSearch).length) {
            Text(this.store.connected ? '暂无匹配对话，可搜索服务器历史或切换归档。' : '连接服务器后，继续你的对话')
              .fontSize(14).lineHeight(22).fontColor(C.muted).padding(12)
          }
        }.width('100%')
      }.id('history-list').layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
      Button({ type: ButtonType.Normal }) {
        Row({ space: 10 }) {
          SymbolGlyph($r('sys.symbol.square_grid_2x2')).fontSize(18).fontColor([C.secondary])
          Text('工作空间').fontSize(14).fontWeight(FontWeight.Medium).fontColor(C.text).layoutWeight(1).textAlign(TextAlign.Start)
          SymbolGlyph($r('sys.symbol.chevron_up')).fontSize(12).fontColor([C.muted])
        }.width('100%')
      }.id('sidebar-workspace').width('100%').height(44).padding({ left: 14, right: 14 }).margin({ top: 8 })
        .backgroundColor(C.glass_fill).border({ width: 0.5, color: C.glass_stroke }).borderRadius(16)
        .accessibilityText('打开工作空间').onClick(() => { this.dismissKeyboard(); this.modelPopupOpen = false; this.attachmentPopupOpen = false; this.workspacePopupOpen = !this.workspacePopupOpen; })
        .bindPopup(this.workspacePopupOpen, this.surfacePopupOptions('workspace'))
      Row({ space: 10 }) {
        Stack() {
          SymbolGlyph($r('sys.symbol.dot_radiowaves_left_and_right_badge_person_filled')).fontSize(16)
            .fontColor([this.store.connected ? C.accent : C.muted])
        }.width(30).height(30).backgroundColor(C.accent_soft).borderRadius(9)
        Column({ space: 4 }) {
          Text(this.serverName()).fontSize(14).fontColor(C.text).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Row({ space: 5 }) {
            StatusLed({ color: this.store.connected ? C.success : C.muted })
            Text(this.store.status).fontSize(12).fontColor(C.secondary).maxLines(1)
          }
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(13).fontColor([C.muted])
      }.id('nav-connections').accessibilityText('服务器连接').padding(10).width('100%').borderRadius(18).margin({ top: 10 })
        .backgroundColor(C.glass_strong).border({ width: 0.5, color: C.glass_stroke }).onClick(() => { this.navigate('connections'); })
    }.id('history-sidebar').padding({ left: 14, right: 14, bottom: 12 }).width(width).height('100%')
      .backgroundEffect({ radius: 38, saturation: 1.15, brightness: 1.0, color: C.glass_fill })
      .border({ width: { right: 0.5 }, color: C.glass_stroke })
      .shadow({ radius: 22, color: C.glass_shadow, offsetX: 8, offsetY: 0 })
  }
  @Builder
  attachmentPopup() {
    Column({ space: 0 }) {
      Button({ type: ButtonType.Normal }) {
        Column({ space: 4 }) {
          Text('选择照片').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          Text('从相册添加，图片会压缩').fontSize(12).fontColor(C.secondary).width('100%')
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.id('attachment-photos').width('100%').constraintSize({ minHeight: 62 }).padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(Color.Transparent).borderRadius(12).enabled(this.store.attachmentInput().indexOf('image') >= 0)
        .accessibilityText('选择照片')
        .onClick(() => { this.attachmentPopupOpen = false; this.pickAttachments(true); })
      Button({ type: ButtonType.Normal }) {
        Column({ space: 4 }) {
          Text('选择文件').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          Text('从文件管理器添加').fontSize(12).fontColor(C.secondary).width('100%')
        }.alignItems(HorizontalAlign.Start).width('100%')
      }.id('attachment-files').width('100%').constraintSize({ minHeight: 62 }).padding({ left: 14, right: 14, top: 10, bottom: 10 })
        .backgroundColor(Color.Transparent).borderRadius(12).accessibilityText('选择文件')
        .onClick(() => { this.attachmentPopupOpen = false; this.pickAttachments(false); })
      Divider().color(C.separator).margin({ left: 14, right: 14, top: 2, bottom: 2 })
      Text('最多 4 个，合计 1 MB；图片会压缩').fontSize(11).fontColor(C.muted).padding({ left: 14, right: 14, top: 6, bottom: 8 }).width('100%')
    }.id('attachment-picker').width('100%').padding({ left: 8, right: 8, top: 8, bottom: 8 }).backgroundColor(Color.Transparent).borderRadius(22)
  }
  @Builder
  sheetContent() { this.panelContent(this.sheetKind) }
  @Builder
  panelContent(kind: string) {
    if (kind === 'search') { ConversationSearchPanel({ messages: this.store.messages, hasEarlier: !!this.store.cursor, canLoad: this.store.canSearchEarlier(), busy: this.store.busy, onSelect: (hit: ConversationHit): void => { this.locateMessage(hit); }, onEarlier: (): void => { this.store.older(); } }) }
    else if (kind === 'tool') { this.toolDetails() }
    else if (kind === 'agent') { AgentPicker({ agents: this.store.agents, current: this.store.agentID, busy: this.store.agentBusy, loading: this.store.agentLoading, error: this.store.agentError, blocked: this.store.agentUncertain ? '请先重新读取，确认当前 Agent。' : this.store.working || this.store.pendingSend || this.store.interactions.length || this.store.permissionError ? '请先结束当前任务并处理问题或审批。' : '', onSelect: (id: string): void => { this.selectAgent(id); }, onRefresh: (): void => { this.store.refreshAgentState(); } }) }
    else if (kind === 'fork') {
      ForEach([this.forkScope + this.forkBefore + String(this.forkEditing)], (key: string) => {
        ForkPanel({ editing: this.forkEditing, initialText: this.forkText, source: this.forkSource, hasFiles: this.forkHasFiles, busy: this.store.forkBusy, error: this.store.forkError, uncertain: this.store.forkUncertain,
          blocked: this.store.working || !!this.store.pendingSend || !!this.store.interactions.length || !!this.store.permissionError, onCreate: (text: string, reuse: boolean): void => { this.createFork(text, reuse); }, onReview: (): void => { this.navigate('projects'); this.store.refreshSessions(); }, onChecked: (): void => { this.confirmForkReview(); } })
      }, (key: string) => key)
    }
    else if (kind === 'usage') { UsagePanel({ usage: this.store.usage, model: this.store.models.find((model: ModelItem) => model.id === this.store.modelID)?.label || this.store.modelID,
      contextLimit: this.store.models.find((model: ModelItem) => model.id === this.store.modelID)?.contextLimit ?? -1, loading: this.store.usageLoading, busy: this.store.compactionBusy, compact: this.store.compaction, error: this.store.usageError,
      blocked: this.store.working || !!this.store.pendingSend || !!this.store.interactions.length || !!this.store.permissionError || this.store.forkBusy || this.store.agentBusy, onRefresh: (): void => { this.store.refreshUsage(); }, onCompact: (): void => { this.confirmCompaction(); } }) }
    else if (kind === 'export') { ExportPanel({ busy: this.store.exporting, saving: this.savingExport, count: this.store.exportCount, error: this.store.exportError, notice: this.exportNotice, onExport: (format: string, tools: boolean): void => { this.exportConversation(format, tools); }, onCancel: (): void => { this.store.cancelExport(); } }) }
    else if (kind === 'attachment') { AttachmentPreview({ item: this.selectedAttachment, saving: this.savingAttachment, onSave: (item: Attachment): void => { this.saveAttachment(item); }, onCopy: (text: string): void => { this.copy(text); } }) }
    else if (kind === 'session') { this.sessionActions() }
    else { this.moreFunctions() }
  }
  @Builder
  actionRow(id: string, icon: Resource, title: string, detail: string, enabled: boolean, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        Stack() { SymbolGlyph(icon).fontSize(18).fontColor([C.accent]) }
          .width(28).height(28).backgroundColor(C.accent_soft).borderRadius(8)
        Column({ space: 5 }) {
          Text(title).fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          if (detail) { Text(detail).fontSize(12).fontColor(C.secondary).maxLines(1).width('100%') }
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([C.muted])
      }.width('100%').padding({ top: 12, bottom: 12 })
    }.id(id).width('100%').constraintSize({ minHeight: 60 }).padding({ left: 16, right: 16 })
      .backgroundColor(Color.Transparent).borderRadius(0).border({ width: { bottom: 0.5 }, color: C.separator }).enabled(enabled).accessibilityText(title)
      .onClick(() => { action(); })
  }
  @Builder
  moreFunctions() {
    Scroll() {
      Column({ space: 20 }) {
        Column({ space: 0 }) {
          Text('当前对话').fontSize(12).fontWeight(FontWeight.Medium).fontColor(C.secondary).width('100%').padding({ bottom: 8 })
          Column({ space: 0 }) {
          this.actionRow('open-search', $r('sys.symbol.magnifyingglass'), '查找对话', '查找已加载消息并返回上下文', !!this.store.sessionID, (): void => { this.follow = false; this.openSheet('search'); })
          this.actionRow('open-usage', $r('sys.symbol.code_square'), '上下文与用量', '查看模型上限、Token 与费用', !!this.store.sessionID, (): void => { this.openSheet('usage'); this.store.refreshUsage(); })
          this.actionRow('open-fork', $r('sys.symbol.folder'), '分叉当前会话', '保留原对话，探索新思路', !!this.store.sessionID && !this.store.forkBusy, (): void => { this.openFork(); })
          this.actionRow('open-export', $r('sys.symbol.doc_text'), '导出当前会话', '保存为 Markdown 或纯文本', !!this.store.sessionID && !this.savingExport, (): void => { this.store.exportError = ''; this.exportNotice = ''; this.openSheet('export'); })
          this.actionRow('sync-current', $r('sys.symbol.arrow_clockwise'), '同步当前对话', '重新读取服务器上的最新状态', !!this.store.sessionID, (): void => { this.navigate('chat'); this.store.sync(); })
          }.width('100%').backgroundColor(C.surface).borderRadius(18).clip(true)
        }.width('100%')
        Column({ space: 0 }) {
          Text('工作空间').fontSize(12).fontWeight(FontWeight.Medium).fontColor(C.secondary).width('100%').padding({ bottom: 8 })
          Column({ space: 0 }) {
          this.actionRow('more-pending', $r('sys.symbol.checkmark'), '待办中心', '集中处理问题与操作审批', !!this.store.connected, (): void => { this.navigate('pending'); })
          this.actionRow('more-projects', $r('sys.symbol.folder'), '项目与会话', '切换仓库，继续已有工作', !!this.store.connected, (): void => { this.navigate('projects'); })
          this.actionRow('more-review', $r('sys.symbol.doc_text'), '代码审查', '查看工作区修改与任务快照', !!this.store.directory, (): void => { this.navigate('review'); })
          }.width('100%').backgroundColor(C.surface).borderRadius(18).clip(true)
        }.width('100%')
        Column({ space: 0 }) {
          Text('应用设置').fontSize(12).fontWeight(FontWeight.Medium).fontColor(C.secondary).width('100%').padding({ bottom: 8 })
          Column({ space: 0 }) {
          this.actionRow('more-models', $r('sys.symbol.code_square'), '模型与接入', '连接提供商，管理自己的模型', !!this.store.connected, (): void => { this.navigate('settings'); })
          this.actionRow('more-connections', $r('sys.symbol.dot_radiowaves_left_and_right'), '服务器连接', '管理地址、认证与连接状态', true, (): void => { this.navigate('connections'); })
          this.actionRow('more-appearance', $r('sys.symbol.lightbulb'), '外观', '跟随系统、浅色或深色', true, (): void => { this.navigate('appearance'); })
          this.actionRow('more-storage', $r('sys.symbol.doc'), '存储与流量', '加密缓存、清理和服务器流量', true, (): void => { this.store.refreshCacheSize(); this.navigate('storage'); })
          this.actionRow('more-reminders', $r('sys.symbol.bell'), '任务提醒', '选择需要接收的状态提醒', true, (): void => { this.navigate('reminders'); })
          }.width('100%').backgroundColor(C.surface).borderRadius(18).clip(true)
        }.width('100%')
      }.padding({ left: 20, right: 20, top: 18, bottom: 32 }).width('100%')
    }.id('more-functions-page').width('100%').height('100%').align(Alignment.TopStart).scrollBar(BarState.Off)
  }
  @Builder
  sessionFilters() {
    Row({ space: 6 }) {
      TextInput({ placeholder: '搜索会话名称', text: this.sessionSearch }).id('session-search')
        .constraintSize({ minHeight: 40 }).fontSize(14).fontColor(C.text).placeholderColor(C.muted).backgroundColor(C.field)
        .border({ width: 1, color: C.separator }).borderRadius(8).layoutWeight(1)
        .onChange((value: string) => { this.sessionSearch = value; })
      Button('搜索', { type: ButtonType.Normal }).id('session-search-server').constraintSize({ minHeight: 40 }).fontSize(14).backgroundColor(C.field).fontColor(C.secondary)
        .borderRadius(8).border({ width: 1, color: C.separator }).enabled(!this.store.sessionsBusy && !!this.store.directory)
        .onClick(() => { this.store.refreshSessions(false, this.sessionSearch); })
    }.width('100%')
    if (this.store.sessionQuery) { Text('服务器搜索：' + this.store.sessionQuery).fontSize(14).fontColor(C.muted).maxLines(1).width('100%') }
    Row({ space: 4 }) {
      Button('最近', { type: ButtonType.Normal }).id('sessions-recent').padding({ left: 4, right: 4 }).layoutWeight(1).constraintSize({ minHeight: 40 }).fontSize(14).backgroundColor(Color.Transparent)
        .fontColor(this.store.showArchived ? C.muted : C.text).borderRadius(0)
        .fontWeight(this.store.showArchived ? FontWeight.Normal : FontWeight.Medium)
        .border({ width: { bottom: this.store.showArchived ? 0 : 1 }, color: C.text })
        .onClick(() => { this.store.showArchived = false; if (this.store.sessionQuery) { this.sessionSearch = ''; this.store.refreshSessions(false, ''); } })
      Button('本机归档', { type: ButtonType.Normal }).id('sessions-archived').padding({ left: 4, right: 4 }).layoutWeight(1).constraintSize({ minHeight: 40 }).fontSize(14).backgroundColor(Color.Transparent)
        .fontColor(this.store.showArchived ? C.text : C.muted).borderRadius(0)
        .fontWeight(this.store.showArchived ? FontWeight.Medium : FontWeight.Normal)
        .border({ width: { bottom: this.store.showArchived ? 1 : 0 }, color: C.text })
        .onClick(() => { this.store.showArchived = true; })
      Button('刷新', { type: ButtonType.Normal }).id('sessions-refresh').width(44).height(40).padding(0).fontSize(12).backgroundColor(Color.Transparent)
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
          .fontSize(compact ? 14 : 15).fontColor(C.text).maxLines(compact ? 1 : 2)
          .textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        if (this.store.sessionLabel(session.id)) {
          Text(this.store.sessionLabel(session.id)).fontSize(12).letterSpacing(0.6).fontColor(C.warning).width('100%')
        }
      }.id((compact ? 'sidebar-session-' : 'session-') + session.id).alignItems(HorizontalAlign.Start).layoutWeight(1)
        .padding({ left: 2, top: 6, bottom: 6 }).onClick(() => { this.pickSession(session); })
      Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.ellipsis_circle')).fontSize(15).fontColor([C.muted]) }
        .id('session-actions-' + session.id).width(40).height(40).backgroundColor(Color.Transparent)
        .accessibilityText('管理会话 ' + session.title).onClick(() => { this.manageSession(session); })
    }.width('100%').constraintSize({ minHeight: compact ? 44 : 56 }).padding({ left: session.id === this.store.sessionID ? 8 : 10, right: 2 })
      .backgroundColor(session.id === this.store.sessionID ? C.chip : compact ? Color.Transparent : C.surface)
      .border({ width: compact ? 0 : 1, color: C.separator })
      .borderRadius(8)
  }
  @Builder
  sessionPaging() {
    if (this.store.sessionsError) { Text(this.store.sessionsError).fontSize(16).fontColor(C.danger).width('100%') }
    if (this.store.sessionsBusy) { Text('正在读取会话…').fontSize(16).fontColor(C.muted).padding(8) }
    if (this.store.sessionCursor && this.store.sessions.length < 500) { Button('加载更多会话').id('sessions-more').fontSize(16).enabled(!this.store.sessionsBusy).onClick(() => { this.store.refreshSessions(true); }) }
    if (this.store.sessions.length >= 500) { Text('已显示 500 个会话，可用名称搜索服务器历史。').fontSize(14).fontColor(C.muted).padding(8) }
  }
  @Builder
  sessionActions() {
    Column({ space: 12 }) {
      Text('管理会话').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      Text('会话名称会同步到服务器。').id('session-name-scope').fontSize(16).fontColor(C.secondary).width('100%')
      TextInput({ text: this.sessionName, placeholder: '会话名称' }).id('session-name').maxLength(200)
        .fontSize(16).fontColor(C.text).placeholderColor(C.muted).height(40)
        .backgroundColor(C.field).border({ width: 1, color: C.separator }).borderRadius(8)
        .onChange((value: string) => { this.sessionName = value; })
      Button(this.store.sessionMutationBusy ? '保存中…' : '保存名称', { type: ButtonType.Normal }).id('session-rename')
        .width('100%').height(36).fontSize(16).fontWeight(FontWeight.Medium).borderRadius(8)
        .backgroundColor(C.btn).fontColor(C.btn_text)
        .enabled(!this.store.sessionMutationBusy && !this.store.sessionPreferenceBusy && !!this.sessionName.trim())
        .onClick(() => { this.store.renameSession(this.selectedSession.id, this.sessionName).then((saved: boolean) => { if (saved) { this.toolSheetOpen = false; } }); })
      Text('本机列表设置').id('session-local-scope').fontSize(14).fontColor(C.secondary).width('100%')
      Button(this.store.isPinned(this.selectedSession.id) ? '取消置顶' : '置顶会话', { type: ButtonType.Normal }).id('session-pin')
        .width('100%').height(32).fontSize(15).borderRadius(8).backgroundColor(Color.Transparent).fontColor(C.text)
        .border({ width: 1, color: C.separator })
        .enabled(!this.store.sessionPreferenceBusy && !this.store.sessionMutationBusy)
        .onClick(() => { this.store.setSessionPreference(this.selectedSession.id, !this.store.isPinned(this.selectedSession.id), this.store.isArchived(this.selectedSession.id)); })
      Button(this.store.isArchived(this.selectedSession.id) ? '移回最近会话' : '归档到本机列表', { type: ButtonType.Normal }).id('session-archive')
        .width('100%').height(32).fontSize(15).borderRadius(8).backgroundColor(Color.Transparent).fontColor(C.text)
        .border({ width: 1, color: C.separator })
        .enabled(!this.store.sessionPreferenceBusy && !this.store.sessionMutationBusy)
        .onClick(() => { this.store.setSessionPreference(this.selectedSession.id, this.store.isPinned(this.selectedSession.id), !this.store.isArchived(this.selectedSession.id)); })
      Text('置顶和归档仅影响这台设备。归档保留服务器历史，运行中的任务会继续，待办仍会显示。')
        .fontSize(12).lineHeight(17).fontColor(C.muted).width('100%')
      if (this.store.error) { Text(this.store.error).fontSize(14).fontColor(C.danger).width('100%') }
    }.padding(18).width('100%')
  }
  @Builder
  pendingCenter() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text('当前服务器 · 所有已知项目').fontSize(12).letterSpacing(0.8)
          .fontColor(C.muted).layoutWeight(1)
        Button('刷新', { type: ButtonType.Normal }).id('pending-refresh').fontSize(14).height(28).buttonStyle(ButtonStyleMode.TEXTUAL)
          .fontColor(C.accent).enabled(!this.store.pendingBusy).onClick(() => { this.store.refreshPending(true); })
      }.width('100%')
      NativeSegments({ first: '全部', second: '问题', third: '审批', selected: this.pendingFilter, onSelect: (index: number): void => { this.pendingFilter = index; } })
      if (this.store.pendingError) { Text(this.store.pendingError + '。旧结果已保留，打开会话后重新核对。').fontSize(14).fontColor(C.warning).width('100%') }
      if (this.store.pendingBusy) { Text('正在同步待办…').fontSize(14).fontColor(C.muted).width('100%') }
      if (!this.store.pendingBusy && !this.store.pendingError && !this.store.pendingItems.length) {
        Text('当前没有待处理的问题或审批。').fontSize(14).fontColor(C.muted).padding(22)
      }
      List({ space: 8 }) {
        ForEach(this.store.pendingItems.filter((p: PendingItem) => this.pendingFilter === 0 || p.kind === (this.pendingFilter === 1 ? 'form' : 'permission')), (item: PendingItem) => {
          ListItem() {
            Column({ space: 5 }) {
              Row({ space: 6 }) {
                StatusLed({ color: item.kind === 'form' ? C.accent : C.warning })
                Text((item.stale ? '待确认 · ' : '') + (item.kind === 'form' ? '需要回答' : '需要审批'))
                  .fontSize(12).fontFamily('monospace').letterSpacing(0.8)
                  .fontColor(item.kind === 'form' ? C.accent : C.warning)
              }.width('100%')
              Text(item.title).fontSize(16).fontColor(C.text).maxLines(3).width('100%')
              Text(item.sessionTitle || item.sessionID).fontSize(14)
                .fontColor(C.secondary).width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
              Text(item.directory).fontSize(12).fontFamily('monospace').fontColor(C.muted).maxLines(2).width('100%')
              Button('打开会话处理', { type: ButtonType.Normal }).id('pending-open-' + item.kind + '-' + item.id)
                .height(28).fontSize(14).fontColor(C.btn_text).backgroundColor(C.btn).borderRadius(7)
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
  storageSettings() {
    Column({ space: 14 }) {
      Text('本机缓存').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      Text((this.store.cacheBytes / 1048576).toFixed(1) + ' MB / 200 MB').id('cache-size')
        .fontSize(24).fontColor(C.text).width('100%')
      Text('最近会话、已打开的附件和最多 100 份文本草稿加密保存在本机，共用 200 MB 上限。草稿自动保存文字，重启后可恢复；附件和待发送请求不自动恢复，待回答和审批仍从服务器实时核对。')
        .fontSize(14).lineHeight(21).fontColor(C.secondary).width('100%')
      Button(this.store.cacheBusy ? '正在清理…' : '清空本机缓存').id('clear-local-cache').width('100%').height(44)
        .fontSize(15).buttonStyle(ButtonStyleMode.NORMAL).enabled(!this.store.cacheBusy)
        .onClick(() => { this.getUIContext().showAlertDialog({ title: '清空本机缓存', message: '清理本机缓存与已保存的文本草稿，当前输入保留。服务器聊天、模型和文件都会保留。',
          primaryButton: { value: '取消', action: (): void => {} },
          secondaryButton: { value: '清理', action: (): void => { this.store.clearCache(); } } }); })
      if (this.store.cacheNotice) { Text(this.store.cacheNotice).id('cache-notice').fontSize(13).fontColor(C.secondary).width('100%') }
      Divider().color(C.separator).margin({ top: 10, bottom: 10 })
      Text('服务器流量').fontSize(20).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
      Text('空闲时使用轻量核对，实时消息由事件更新。图片与文件点按时下载，已缓存的附件直接复用。')
        .fontSize(14).lineHeight(21).fontColor(C.secondary).width('100%')
      Button('打开服务器流量统计').id('open-server-traffic').width('100%').height(44).fontSize(15)
        .enabled(!!this.store.connected).onClick(() => {
          const server = this.store.servers.find((item: ServerConfig) => item.id === this.store.connected);
          if (server?.url.startsWith('https://')) { this.openLink(server.url.replace(/\/+$/, '') + '/'); }
          else { this.toast('请使用正式 HTTPS 域名查看服务器统计'); }
        })
      Text('统计页需要网页登录；流量从启用统计时开始记录，账单用量以腾讯云控制台为准。')
        .fontSize(12).lineHeight(18).fontColor(C.muted).width('100%')
    }.padding(20).width('100%').alignItems(HorizontalAlign.Start)
  }
  @Builder
  appearanceSettings() {
    Column({ space: 16 }) {
      NativeSegments({ first: '跟随系统', second: '浅色', third: '深色',
        selected: this.appearanceMode === 'dark' ? 2 : this.appearanceMode === 'light' ? 1 : 0,
        onSelect: (index: number): void => { this.changeAppearance(index === 2 ? 'dark' : index === 1 ? 'light' : 'system'); } }).id('appearance-segments')
      Text('选择此应用的显示方式').fontSize(14).fontColor(C.secondary).width('100%')
      Text('当前外观：' + (this.appearanceMode === 'dark' ? '深色' : this.appearanceMode === 'light' ? '浅色' : '跟随系统'))
        .fontSize(12).fontFamily('monospace').fontColor(C.secondary).width('100%')
      Text('跟随系统会自动适配设备的深浅色设置。').fontSize(14).lineHeight(18).fontColor(C.muted).width('100%')
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
          Text(this.selectedTool.id.slice(0, 28) || 'TOOL CALL').fontSize(12).fontFamily('monospace')
            .letterSpacing(0.8).fontColor(C.muted).maxLines(1)
        }.alignItems(HorizontalAlign.Start).layoutWeight(1)
        Row({ space: 5 }) {
          StatusLed({ color: this.selectedTool.status === 'error' || this.selectedTool.status === 'failed' ? C.danger : this.selectedTool.status === 'running' ? C.accent : C.success })
          Text(toolStatus(this.selectedTool.status)).fontSize(14).fontColor(C.secondary)
        }
      }.width('100%')
      Divider().color(C.separator)
      Scroll() {
        Column({ space: 10 }) {
          Text('调用参数').fontSize(12).fontFamily('monospace').letterSpacing(1.2).fontColor(C.muted).width('100%')
          Text(this.selectedTool.input.slice(0, 12000) || '无参数').id('tool-request')
            .fontFamily('monospace').fontSize(14).lineHeight(22).fontColor(C.code_text)
            .padding(12).backgroundColor(C.code_bg).border({ width: 1, color: C.separator }).borderRadius(8)
            .copyOption(CopyOptions.InApp).width('100%')
          Text('执行结果').fontSize(12).fontFamily('monospace').letterSpacing(1.2).fontColor(C.muted).width('100%')
          Text(this.selectedTool.output.slice(0, 16000) || (this.selectedTool.status === 'running' ? '正在执行，结果会自动更新…' : '暂无文本结果')).id('tool-response')
            .fontFamily('monospace').fontSize(14).lineHeight(22).fontColor(C.code_text)
            .padding(12).backgroundColor(C.code_bg).border({ width: 1, color: C.separator }).borderRadius(8)
            .copyOption(CopyOptions.InApp).width('100%')
          if (this.selectedTool.input.length > 12000 || this.selectedTool.output.length > 16000) {
            Text('较长内容已截断，完整记录保留在服务器。').fontSize(12).fontColor(C.muted)
          }
        }.width('100%')
      }.layoutWeight(1).width('100%').align(Alignment.TopStart).scrollBar(BarState.Auto)
      Row({ space: 8 }) {
        Button('复制参数', { type: ButtonType.Normal }).layoutWeight(1).constraintSize({ minHeight: 48 }).fontSize(16).fontColor(C.text)
          .backgroundColor(Color.Transparent).border({ width: 1, color: C.separator }).borderRadius(8)
          .onClick(() => { this.copy(this.selectedTool.input); })
        Button('复制结果', { type: ButtonType.Normal }).layoutWeight(1).constraintSize({ minHeight: 48 }).fontSize(16).fontColor(C.btn_text)
          .backgroundColor(C.btn).borderRadius(8)
          .onClick(() => { this.copy(this.selectedTool.output); })
      }.width('100%').margin({ top: 10 })
    }.id('tool-details').padding({ left: 16, right: 16, top: 8, bottom: 18 }).width('100%').height('100%')
  }
  @Builder
  workspacePopup() {
    Column({ space: 0 }) {
      Text('工作空间').fontSize(15).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%').padding({ left: 14, top: 14, bottom: 8 })
      Scroll() {
        Column({ space: 0 }) {
          this.workspaceEntry('projects', $r('sys.symbol.folder'), '项目与会话', !!this.store.connected)
          this.workspaceEntry('pending', $r('sys.symbol.checkmark'), '待办中心', !!this.store.connected)
          this.workspaceEntry('review', $r('sys.symbol.doc_text'), '代码审查', !!this.store.directory)
          this.workspaceEntry('settings', $r('sys.symbol.code_square'), '模型与接入', !!this.store.connected)
          this.workspaceEntry('reminders', $r('sys.symbol.bell'), '任务提醒', true)
        }.width('100%')
      }.width('100%').height(Math.min(250, Math.max(100, this.viewportHeight - 230))).scrollBar(BarState.Auto)
    }.id('workspace-picker').padding({ left: 8, right: 8, bottom: 8 }).width('100%').backgroundColor(Color.Transparent)
  }
  @Builder
  workspaceEntry(pane: string, icon: Resource, label: string, enabled: boolean) {
    Button({ type: ButtonType.Normal }) {
      Row({ space: 12 }) {
        SymbolGlyph(icon).fontSize(18).fontColor([C.secondary])
        Text(label).fontSize(15).fontColor(C.text).layoutWeight(1).textAlign(TextAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([C.muted])
      }.width('100%')
    }.id('workspace-' + pane).width('100%').height(50).padding({ left: 14, right: 14 }).backgroundColor(Color.Transparent)
      .borderRadius(14).enabled(enabled).onClick(() => { this.navigate(pane); })
  }
  private surfacePopupOptions(kind: string): CustomPopupOptions {
    const isWorkspace: boolean = kind === 'workspace';
    const options: CustomPopupOptions = {
      builder: (): void => { if (isWorkspace) { this.workspacePopup(); } else { this.attachmentPopup(); } },
      placement: Placement.TopLeft, enableArrow: false,
      width: Math.min(300, this.viewportWidth - 40), targetSpace: 8, offset: { x: 0, y: 0 }, radius: 24,
      popupColor: C.glass_strong, backgroundBlurStyle: BlurStyle.COMPONENT_THICK, shadow: ShadowStyle.OUTER_DEFAULT_MD,
      mask: { color: '#0A000000' }, autoCancel: true, focusable: false,
      onWillDismiss: (action): void => { action.dismiss(); if (isWorkspace) { this.workspacePopupOpen = false; } else { this.attachmentPopupOpen = false; } },
      transition: TransitionEffect.OPACITY.animation({ duration: 160, curve: Curve.EaseOut }),
      onStateChange: (event): void => { if (!event.isVisible) { if (isWorkspace) { this.workspacePopupOpen = false; } else { this.attachmentPopupOpen = false; } } } };
    if (deviceInfo.sdkApiVersion >= 26) {
      if (deviceInfo.apiAvailable('26.0.0')) { if (this.modelMaterial) { options.systemMaterial = this.modelMaterial; options.focusable = true; } }
    }
    return options;
  }
  private glassMenuOptions(): MenuOptions {
    const options: MenuOptions = { backgroundColor: C.glass_strong, backgroundBlurStyle: BlurStyle.COMPONENT_THICK, borderRadius: 22 };
    if (deviceInfo.sdkApiVersion >= 26) {
      if (deviceInfo.apiAvailable('26.0.0')) { if (this.modelMaterial) { options.systemMaterial = this.modelMaterial; } }
    }
    return options;
  }
  private surfaceSheetOptions(): SheetOptions {
    const options: SheetOptions = { height: this.isLargeSheet() ? SheetSize.LARGE : SheetSize.FIT_CONTENT,
      showClose: true, blurStyle: BlurStyle.COMPONENT_THICK, backgroundColor: C.sheet_tint,
      onWillDismiss: (action): void => { action.dismiss(); this.toolSheetOpen = false; },
      maskColor: C.sheet_scrim, borderWidth: 1, borderColor: C.glass_stroke,
      shadow: { radius: 36, color: C.glass_shadow, offsetX: 0, offsetY: -8 },
      onDisappear: (): void => { this.toolSheetOpen = false; if (this.store.exporting) { this.store.cancelExport(); } } };
    if (deviceInfo.sdkApiVersion >= 26) {
      if (deviceInfo.apiAvailable('26.0.0')) { if (this.compactSheetMaterial && !this.isLargeSheet()) { options.systemMaterial = this.compactSheetMaterial; } }
    }
    return options;
  }
  @Builder
  chatTitle() {
    Row({ space: 8 }) {
      Blank().width(this.sidebarOpen ? 0 : 52).height(40)
      if (this.store.models.length) {
        Blank().width(Math.min(220, Math.max(96, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - (this.sidebarOpen ? 168 : 224)))).height(36)
      } else { Text('OpenCode').fontSize(15).fontWeight(FontWeight.Bold).fontColor(C.text).layoutWeight(1) }
      Blank().layoutWeight(1)
    }.width(Math.max(180, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - 104)).height(56)
  }
  @Builder
  errorBanner() {
    if (this.store.error) {
      Row({ space: 8 }) {
        StatusLed({ color: C.danger })
        Text(this.store.error).fontSize(14).fontColor(C.danger).layoutWeight(1).maxLines(3)
        if (this.store.connected && this.store.status !== '实时连接' && this.store.status !== '已连接') {
          Button('重新连接').fontSize(14).height(26).backgroundColor(C.danger_bg)
            .fontColor(C.danger).borderRadius(6).enabled(!this.store.busy)
            .onClick(() => { this.store.reconnect(); })
        }
        Button({ type: ButtonType.Circle }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([C.secondary]) }
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
        if (name.startsWith('panel-')) { this.panelContent(name.substring(6)) }
        else if (name === 'more') { this.moreFunctions() }
        else if (name === 'connections') { this.connections() }
        else if (name === 'projects') { this.projects() }
        else if (name === 'pending') { this.pendingCenter() }
        else if (name === 'storage') { this.storageSettings() }
        else if (name === 'appearance') { this.appearanceSettings() }
        else if (name === 'reminders') { this.reminderSettings() }
        else if (name === 'provider-auth') { ProviderSettings({ store: this.store.providers, detail: true, onOpenLink: (url: string): void => { this.openLink(url); } }) }
        else if (name === 'model-library') { ModelLibrary({ models: this.store.models, preferences: this.store.modelPreferences,
          favoritesOnly: this.modelLibraryFavorites, busy: this.store.modelPreferencesBusy || this.store.modelBusy,
          error: this.store.modelPreferencesError,
          onManageAll: (): void => { this.modelLibraryFavorites = false; },
          onEnable: (id: string, enabled: boolean): void => { this.store.enableModel(id, enabled); },
          onFavorite: (id: string, favorite: boolean): void => { this.store.favoriteModel(id, favorite); },
          onRefresh: (): void => { this.store.refreshModels().catch((): void => { this.store.modelPreferencesError = '未能刷新模型目录，请重试'; }); } }) }
        else if (name === 'settings') { ProviderSettings({ store: this.store.providers, enabledCount: this.store.modelPreferences.enabled.length,
          favoriteCount: this.store.modelPreferences.favorites.length,
          onManageModels: (favoritesOnly: boolean): void => { this.modelLibraryFavorites = favoritesOnly; this.navigate('model-library'); }, onOpenProvider: (): void => { this.navigate('provider-auth'); }, onOpenLink: (url: string): void => { this.openLink(url); } }) }
        else { this.review() }
      }.height('100%').width('100%').backgroundColor(C.page)
    }.id('native-destination').title(this.pageTitle(name))
      .systemBarStyle({ statusBarContentColor: this.darkAppearance ? '#EDEEF0' : '#15171C' })
      .backgroundColor(C.page).onBackPressed((): boolean => { if (name.startsWith('panel-')) { this.closePanel(); } else { this.store.pane = name === 'provider-auth' || name === 'model-library' ? 'settings' : 'chat'; } return true; })
  }
  build() {
    SideBarContainer(this.wide ? SideBarContainerType.Embed : SideBarContainerType.Overlay) {
      this.sidebar(this.sidebarWidth())
      Stack() {
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
        // Navigation custom titles recreate their subtree during polling; retain this anchor in the page.
        if (this.store.pane === 'chat' && this.store.models.length && (!this.sidebarOpen || this.wide)) {
          Row() {
            ModelMenuHost({ open: $modelPopupOpen, label: this.modelLabel(), current: this.store.modelID, variant: this.store.modelVariant,
              models: this.store.models, preferences: this.store.modelPreferences, error: this.store.error,
              uncertain: this.store.modelUncertain, busy: this.switchingModel || this.store.modelBusy || this.store.modelPreferencesBusy,
              canOpen: !!this.store.sessionID && !this.store.busy,
              triggerWidth: Math.min(220, Math.max(96, this.viewportWidth - (this.wide && this.sidebarOpen ? 280 : 0) - (this.sidebarOpen ? 168 : 224))),
              popupWidth: Math.min(272, this.viewportWidth - 40), popupHeight: Math.max(240, Math.min(600, this.viewportHeight - 160)),
              onOpen: (): void => { this.dismissKeyboard(); this.store.error = ''; this.workspacePopupOpen = false; this.attachmentPopupOpen = false; },
              onSelect: (id: string): void => { this.selectModel(id); }, onVariant: (id: string): Promise<boolean> => this.selectVariant(id),
              onRefresh: (): void => { this.store.sync(); }, onManage: (): void => { this.navigate('settings'); } })
          }.id('model-anchor-layer').height(36).position({ x: this.sidebarOpen ? 16 : 60, y: 10 })
        }
        if (this.sidebarOpen && !this.wide) {
          Column().id('sidebar-dismiss').width(Math.max(44, this.viewportWidth - this.sidebarWidth())).height('100%')
            .position({ x: this.sidebarWidth(), y: 0 }).backgroundColor('#14000000')
            .accessibilityText('收起历史对话').accessibilityLevel('yes').onClick(() => { this.dismissKeyboard(); this.sidebarOpen = false; })
        }
      }.width('100%').height('100%')
    }.id('native-sidebar-container').showSideBar(this.sidebarOpen).showControlButton(!this.sidebarOpen && this.store.pane === 'chat')
      .controlButton({ left: 16, top: 16, width: 24, height: 24 })
      .sideBarWidth(this.sidebarWidth()).minSideBarWidth(220).maxSideBarWidth(320)
      .divider({ strokeWidth: 1, color: C.separator }).onChange((show: boolean) => { this.dismissKeyboard(); this.sidebarOpen = show; })
      .width('100%').height('100%').backgroundColor(C.page).expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.viewportWidth = Number(newArea.width); this.viewportHeight = Number(newArea.height); const wide = this.viewportWidth >= 840; if (this.wide !== wide) { this.wide = wide; this.sidebarOpen = wide; }
        // Keyboard opening resizes the page; keep the newest message visible only when the user is following the live end.
        const oldHeight = Number(oldArea.height); const newHeight = Number(newArea.height);
        if (oldHeight > 0 && newHeight < oldHeight - 60 && this.follow && this.store.pane === 'chat' && !this.toolSheetOpen && !this.modelPopupOpen) {
          setTimeout(() => { if (this.follow && this.store.pane === 'chat' && !this.toolSheetOpen && !this.modelPopupOpen) { this.scroller.scrollEdge(Edge.Bottom); } }, 140);
        }
      })
      .bindSheet($$this.toolSheetOpen, this.sheetSurface(), this.surfaceSheetOptions())
  }
}
