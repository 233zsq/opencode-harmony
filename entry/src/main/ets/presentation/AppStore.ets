import { ModelPreferences, emptyModelPreferences, enabledModels, setModelEnabled, setModelFavorite, rememberModel } from '../domain/ModelSelection';
import { prepareConnection, sameConnectionIdentity, ConnectionInput } from '../domain/Connections';
import { SessionUsage, emptyUsage, CompactRecord } from '../domain/SessionUsage';
import { AgentItem } from '../domain/Agents';
import { TranscriptExporter, ExportDocument, ExportCancelled } from '../domain/TranscriptExport';
import { Attachment, PromptFile, attachmentProblem, promptFiles, ATTACHMENT_LIMIT, attachmentBytes } from '../domain/Attachments';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { Storage } from '../data/Storage';
import { ProviderStore } from './ProviderStore';
import { Protocol, ApiError, parseUsage, parseCompactRecord, object, string, rows, list, json, Json } from '../data/Protocol';
import { ServerConfig, ProjectItem, SessionItem, ModelItem, ChatMessage, Interaction, FormField, FileItem,
  DiffItem, TurnItem, TimelineEntry, PendingItem, PendingPrompt, QuestionDraft, SessionPreference, ConversationMemory, filterSessions, sessionStatus, pendingKey, groupTurns, boundMessageAttachments, SseFrame, mergeMessages, applyTextDelta, buildFormAnswer, updateFieldValue, FieldValue, mergeFormDraft, previewText, interactionSnapshot, TranscriptCachePort, EmptyTranscriptCache } from '../domain/Core';
import { TaskNotification, TaskNotifySink, NoopTaskNotifier, NotificationLedger, NotificationKind, NotificationTarget,
  pendingNotificationKind, completionEventID, taskNotificationKind, isQuietReminder } from '../domain/Notifications';

interface CreateRequest { title: string; location: LocationRequest; }
interface LocationRequest { directory: string; }
interface PromptRequest { id: string; text: string; delivery: string; resume: boolean; files?: PromptFile[]; }
interface ModelRef { id: string; providerID: string; variant?: string; }
interface ModelRequest { model: ModelRef; }
interface HistoryResponse { data: Object[]; }
interface AgentRequest { agent: string; }
interface AnswerRequest { answer: Record<string, FieldValue>; }
interface PermissionReply { decision: string; }
interface PendingScope { directory: string; kind: string; }
interface PendingResult { scope: PendingScope; items: PendingItem[]; error: string; }
@Observed
export class AppStore {
  pane: string = 'chat';
  providers: ProviderStore = new ProviderStore();
  servers: ServerConfig[] = [];
  connected: string = '';
  status: string = '未连接';
  version: string = '';
  error: string = '';
  busy: boolean = false;
  projects: ProjectItem[] = [];
  sessions: SessionItem[] = [];
  sessionCursor: string = '';
  sessionQuery: string = '';
  sessionsBusy: boolean = false;
  sessionsError: string = '';
  sessionPreferences: SessionPreference[] = [];
  sessionPreferenceBusy: boolean = false;
  sessionMutationBusy: boolean = false;
  showArchived: boolean = false;
  pendingItems: PendingItem[] = [];
  pendingBusy: boolean = false;
  pendingError: string = '';
  pendingUpdated: number = 0;
  runningSessions: string[] = [];
  runningUnknown: boolean = false;
  private preferenceEpoch: number = 0;
  private conversationMemory: ConversationMemory = new ConversationMemory();
  private sessionsEpoch: number = 0;
  private pendingEpoch: number = 0;
  private workspaceTimer: number = -1;
  private streamEpoch: number = 0;
  directory: string = '';
  sessionID: string = '';
  sessionTitle: string = '';
  models: ModelItem[] = [];
  modelID: string = '';
  modelVariant: string = '';
  modelBusy: boolean = false;
  modelUncertain: boolean = false;
  modelPreferences: ModelPreferences = emptyModelPreferences();
  modelPreferencesBusy: boolean = false;
  modelPreferencesError: string = '';
  private modelPreferenceEpoch: number = 0;
  agents: AgentItem[] = [];
  agentID: string = '';
  agentError: string = '';
  agentBusy: boolean = false;
  agentLoading: boolean = false;
  agentUncertain: boolean = false;
  private agentEpoch: number = 0;
  private selectionEpoch: number = 0;
  exporting: boolean = false;
  exportCount: number = 0;
  exportError: string = '';
  private exportEpoch: number = 0;
  private exportJob: TranscriptExporter | undefined = undefined;
  messages: ChatMessage[] = [];
  interactions: Interaction[] = [];
  permissionError: string = '';
  private permissionEpoch: number = 0;
  files: FileItem[] = [];
  diffs: DiffItem[] = [];
  turns: TurnItem[] = [];
  turnID: string = '';
  turnDiffs: DiffItem[] = [];
  timelineBusy: boolean = false;
  timelineLoaded: boolean = false;
  timelineError: string = '';
  timelineCursor: string = '';
  turnBusy: boolean = false;
  turnLoaded: boolean = false;
  turnError: string = '';
  private timelineEntries: TimelineEntry[] = [];
  private timelineEpoch: number = 0;
  private turnEpoch: number = 0;
  filePath: string = '';
  fileContent: string = '';
  fileTruncated: boolean = false;
  cursor: string = '';
  readingHistory: boolean = false;
  newerAvailable: boolean = false;
  private transcriptEpoch: number = 0;
  private networkBlocked: boolean = false;
  private tailLoaded: boolean = false;
  reviewLoaded: boolean = false;
  working: boolean = false;
  interrupting: boolean = false;
  draft: string = '';
  attachments: Attachment[] = [];
  attachmentInput(): string[] { return this.models.find((m: ModelItem) => m.id === this.modelID)?.input || ['text']; }
  addAttachments(items: Attachment[]): void {
    if (this.pendingSend || this.busy) { return; }
    const next = this.attachments.slice();
    for (const item of items) {
      if (next.length >= 4) { this.error = '一次最多添加 4 个附件'; break; }
      if (attachmentBytes(next) + item.size > ATTACHMENT_LIMIT) { next.push({ id: item.id, name: item.name, mime: item.mime, size: 0, data: '', uri: item.uri, error: '附件合计不能超过 1 MB，请移除部分附件后重试' }); }
      else { next.push(item); }
    }
    this.attachments = next;
  }
  removeAttachment(id: string): void { if (!this.pendingSend && !this.busy) { this.attachments = this.attachments.filter((a: Attachment) => a.id !== id); } }
  replaceAttachment(item: Attachment): void {
    if (this.pendingSend || this.busy) { return; }
    const old = this.attachments; const rest = old.filter((a: Attachment) => a.id !== item.id);
    if (attachmentBytes(rest) + item.size > ATTACHMENT_LIMIT) { item = { id: item.id, name: item.name, mime: item.mime, size: 0, data: '', uri: item.uri, error: '附件合计不能超过 1 MB' }; }
    this.attachments = old.map((a: Attachment) => a.id === item.id ? item : a);
  }
  manualPath: string = '';
  serverEditID: string = '';
  serverSaving: boolean = false;
  clearServerPassword: boolean = false;
  serverNotice: string = '';
  parentSessionID: string = '';
  branchBoundary: string = '';
  usage: SessionUsage = emptyUsage();
  usageLoading: boolean = false;
  usageError: string = '';
  forkBusy: boolean = false;
  forkError: string = '';
  forkUncertain: boolean = false;
  compactionBusy: boolean = false;
  compaction: CompactRecord = { id: '', state: '', error: '' };
  private compactRecords: Map<string, CompactRecord> = new Map<string, CompactRecord>();
  private serverRevisions: Map<string, number> = new Map<string, number>();
  private unknownForks: Set<string> = new Set<string>();
  private usageEpoch: number = 0;
  serverName: string = '';
  serverUrl: string = 'https://';
  serverUser: string = 'opencode';
  serverPassword: string = '';
  allowHttp: boolean = false;
  useDedicatedTrust: boolean = false;
  reviewTab: string = 'diff';
  pendingSend: PendingPrompt | undefined = undefined;
  cacheBytes: number = 0;
  cacheBusy: boolean = false;
  cacheNotice: string = '';
  cacheRestored: boolean = false;
  private transcriptCache: TranscriptCachePort = new EmptyTranscriptCache();
  private cacheEpoch: number = 0;
  private lastHistorySync: number = 0;
  private lastProbe: number = 0;
  private sessionVersion: number = 0;
  private streamReady: boolean = false;
  private probeBusy: boolean = false;
  private probeEpoch: number = 0;
  attachCache(cache: TranscriptCachePort): void { this.transcriptCache = cache; this.refreshCacheSize(); }
  async refreshCacheSize(): Promise<void> {
    try { this.cacheBytes = await this.transcriptCache.size(); } catch (_) { this.cacheNotice = '本机缓存暂不可用，联网功能不受影响'; }
  }
  async clearCache(): Promise<void> {
    if (this.cacheBusy) { return; }
    this.cacheBusy = true; this.cacheEpoch++;
    try { await this.transcriptCache.clear(); this.cacheBytes = 0; this.cacheNotice = '已清空本机缓存，服务器历史仍然保留'; }
    catch (_) { this.cacheNotice = '缓存未清理完成，请重试'; }
    finally { this.cacheBusy = false; }
  }
  private async restoreOffline(config: ServerConfig, generation: number): Promise<void> {
    const epoch = this.cacheEpoch;
    try {
      const position = await this.storage.last(config.id);
      if (position.length < 2) { return; }
      const snapshot = await this.transcriptCache.load(config, position[0], position[1]);
      if (!snapshot || generation !== this.generation || epoch !== this.cacheEpoch) { return; }
      this.connected = config.id; this.directory = position[0]; this.sessionID = position[1];
      this.messages = boundMessageAttachments(snapshot.messages); this.cursor = snapshot.cursor; this.tailLoaded = true;
      this.interactions = []; this.cacheRestored = true; this.status = '离线缓存'; this.sessionTitle = '缓存会话';
    } catch (_) {}
  }
  private async restoreTranscript(generation: number): Promise<void> {
    const config = this.api?.config; const id = this.sessionID; const directory = this.directory; const epoch = this.cacheEpoch;
    if (!config) { return; }
    try {
      const snapshot = await this.transcriptCache.load(config, directory, id);
      if (snapshot && generation === this.generation && epoch === this.cacheEpoch && !this.lastHistorySync && !this.syncing) {
        this.messages = boundMessageAttachments(snapshot.messages); this.cursor = snapshot.cursor; this.tailLoaded = true; this.cacheRestored = true;
      }
    } catch (_) { this.cacheNotice = '本机缓存暂不可用，正在联网读取'; }
  }
  private async cachedFiles(incoming: ChatMessage[], config: ServerConfig | undefined): Promise<void> {
    for (const message of incoming) {
      for (const file of message.files || []) {
        if (file.data || !file.remoteHash) { continue; }
        const old = this.messages.find((m: ChatMessage) => m.id === message.id)?.files?.find((f: Attachment) => f.id === file.id && f.remoteHash === file.remoteHash);
        if (old?.data) { file.data = old.data; continue; }
        if (config) { try { file.data = await this.transcriptCache.file(config, file.remoteHash); } catch (_) {} }
      }
    }
  }
  private saveTranscript(config: ServerConfig | undefined, id: string, directory: string,
    messages: ChatMessage[], cursor: string, epoch: number): void {
    if (!config || epoch !== this.cacheEpoch || this.readingHistory) { return; }
    this.transcriptCache.save(config, directory, id, { messages: messages, cursor: cursor, savedAt: Date.now() })
      .then((): void => { this.refreshCacheSize(); }).catch((): void => { this.cacheNotice = '部分内容未能缓存，仍可联网读取'; });
  }
  private async poll(): Promise<void> {
    if (!this.api || !this.sessionID || !this.active || !this.foreground || this.networkBlocked || this.syncing) { return; }
    const elapsed = Date.now() - this.lastHistorySync;
    // SSE drives normal updates. A bounded full checkpoint also catches dropped events.
    if (this.pendingSend || elapsed >= (this.working ? 30000 : this.streamReady ? 300000 : 15000)) {
      await this.sync(); return;
    }
    if (this.probeBusy || Date.now() - this.lastProbe < (this.working ? 15000 : 60000)) { return; }
    this.lastProbe = Date.now(); this.probeBusy = true; const token = ++this.probeEpoch;
    const api = this.api; const generation = this.generation; const id = this.sessionID;
    try {
      const detail = await api.session(id);
      if (generation !== this.generation || api !== this.api || token !== this.probeEpoch || !this.active) { return; }
      const updated = detail.updated || 0;
      if (updated > 0 && updated !== this.sessionVersion) { await this.sync(); }
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
    finally { if (token === this.probeEpoch) { this.probeBusy = false; } }
  }
  private storage: Storage = new Storage();
  private api: Protocol | undefined = undefined;
  private generation: number = 0;
  private streamClose: (() => void) | undefined = undefined;
  private pollTimer: number = -1;
  private retryTimer: number = -1;
  private refreshTimer: number = -1;
  private attempts: number = 0;
  private lastData: number = 0;
  private active: boolean = true;
  private syncing: boolean = false;
  private syncAgain: boolean = false;
  private eventEpoch: number = 0;
  private eventIDs: string[] = [];
  private initialized: boolean = false;
  taskNotifier: TaskNotifySink = new NoopTaskNotifier();
  foreground: boolean = true;
  conversationVisible: boolean = true;
  reminderQuiet: string = '';
  reminderQuietSeq: number = 0;
  targetBusy: boolean = false;
  // Short best-effort window after leaving the foreground. The existing SSE
  // connection is kept alive; the system may freeze it at any time. This is not
  // a background service and never polls or keeps the process artificially alive.
  private backgroundReminderTimer: number = -1;
  private notificationLedger: NotificationLedger = new NotificationLedger();
  private notifyBaseline: boolean = false;
  private syncSuppressNotify: boolean = false;
  // The first global pending read after (re)connecting seeds existing items.
  private pendingBaseline: boolean = true;
  private pendingSuppressNotify: boolean = false;
  private taskIdlePending: boolean = false;
  private runningTokens: Map<string, number> = new Map<string, number>();
  private runningTokenSeq: number = 0;

  async init(context: common.Context): Promise<void> {
    if (this.initialized) { return; }
    try { await this.storage.init(context); this.servers = await this.storage.servers(); this.initialized = true;
      const last = await this.storage.activeServer();
      const server = this.servers.find((s: ServerConfig) => s.id === last);
      if (server) { await this.connect(server); } }
    catch (e) { this.fail(e as Error); }
  }
  // Injected once by the Index page: the platform notification center in the
  // app and a recording fake in the Node tests. AppStore never imports the
  // notification platform modules itself.
  attachNotifier(sink: TaskNotifySink, foreground: boolean = true): void {
    this.taskNotifier = sink; this.foreground = foreground;
  }
  setForeground(foreground: boolean): void {
    this.foreground = foreground;
    if (!foreground) { this.suppressNotificationCatchUp(); }
  }
  beginBackgroundReminderWindow(ms: number): void {
    this.foreground = false;
    this.cancelBackgroundReminderWindow();
    this.backgroundReminderTimer = setTimeout(() => {
      this.backgroundReminderTimer = -1;
      this.setActive(false);
    }, ms);
  }
  cancelBackgroundReminderWindow(): void {
    if (this.backgroundReminderTimer >= 0) { clearTimeout(this.backgroundReminderTimer); this.backgroundReminderTimer = -1; }
  }
  // Leaving the foreground pauses the existing network loop. The first sync and
  // pending refresh after coming back must seed state instead of alerting for
  // work that finished while the app was away.
  private suppressNotificationCatchUp(): void {
    this.syncSuppressNotify = true;
    this.pendingSuppressNotify = true;
  }
  private fail(error: Error): void {
    this.error = error.message || '操作失败，请重新连接';
    if (error instanceof ApiError && [401, 403, 495].indexOf(error.code) >= 0) {
      this.cacheEpoch++;
      const config = this.api?.config;
      if (config) { this.transcriptCache.removeServer(config).then((): void => { this.refreshCacheSize(); }).catch((): void => {}); }
      if (this.cacheRestored) { this.messages = []; this.cacheRestored = false; }
      this.networkBlocked = true; this.status = error.code === 495 ? '证书校验失败' : '认证失败'; this.stopNetwork();
      this.pendingError = '连接校验失败，待办状态尚未确认';
      this.pendingItems = this.pendingItems.map((p: PendingItem): PendingItem => ({ id: p.id, sessionID: p.sessionID, directory: p.directory, kind: p.kind, title: p.title, sessionTitle: p.sessionTitle, stale: true }));
    }
  }
  private stashConversation(): boolean {
    if (!this.connected || !this.sessionID) { return true; }
    try { this.conversationMemory.save(this.connected, this.directory, this.sessionID, this.draft, this.pendingSend, this.questionDrafts(), this.attachments); return true; }
    catch (e) { this.fail(e as Error); return false; }
  }
  private questionDrafts(): QuestionDraft[] { return this.interactions.filter((p: Interaction) => p.kind === 'form').map((p: Interaction): QuestionDraft => ({ id: p.id, fields: p.fields })); }
  private clearSavedDraft(): void { this.conversationMemory.save(this.connected, this.directory, this.sessionID, '', undefined, this.questionDrafts()); }
  private knownSessions(): SessionItem[] {
    const sessions = this.sessions.slice();
    this.sessionPreferences.forEach((p: SessionPreference) => {
      if (p.directory === this.directory && p.title && !sessions.some((s: SessionItem) => s.id === p.id)) {
        sessions.push({ id: p.id, title: p.title, directory: p.directory, status: 'idle', model: '' });
      }
    });
    return sessions;
  }
  sessionRows(search: string = ''): SessionItem[] { return filterSessions(this.knownSessions(), this.sessionPreferences, search || this.sessionQuery, this.showArchived); }
  recentSessions(): SessionItem[] { return filterSessions(this.knownSessions(), this.sessionPreferences, '', false).slice(0, 3); }
  sessionLabel(id: string): string {
    const label = sessionStatus(id, this.runningSessions, this.pendingItems);
    return label === '运行中' && this.runningUnknown ? '运行状态待确认' : label;
  }
  isPinned(id: string): boolean { return this.sessionPreferences.some((p: SessionPreference) => p.id === id && p.pinned); }
  isArchived(id: string): boolean { return this.sessionPreferences.some((p: SessionPreference) => p.id === id && p.archived); }
  async setSessionPreference(id: string, pinned: boolean, archived: boolean): Promise<void> {
    if (!this.connected || this.sessionPreferenceBusy || this.sessionMutationBusy) { return; }
    const server = this.connected; const epoch = ++this.preferenceEpoch; this.sessionPreferenceBusy = true; this.error = '';
    const flags = this.sessionPreferences.filter((p: SessionPreference) => p.id !== id);
    const session = this.sessions.find((s: SessionItem) => s.id === id); const previous = this.sessionPreferences.find((p: SessionPreference) => p.id === id);
    if (pinned || archived) { flags.push({ id: id, pinned: pinned, archived: archived, title: session?.title || previous?.title, directory: session?.directory || previous?.directory }); }
    try { await this.storage.saveSessionPreferences(server, flags); if (server === this.connected && epoch === this.preferenceEpoch) {
      this.sessionPreferences = flags;
      if (!archived && previous?.directory === this.directory && previous.title && !this.sessions.some((s: SessionItem) => s.id === id)) {
        const restored: SessionItem = { id: id, title: previous.title, directory: previous.directory, status: 'idle', model: '' };
        this.sessions = [restored].concat(this.sessions).slice(0, 500);
      }
    } }
    catch (e) { if (server === this.connected && epoch === this.preferenceEpoch) { this.fail(e as Error); } }
    finally { if (server === this.connected && epoch === this.preferenceEpoch) { this.sessionPreferenceBusy = false; } }
  }
  async renameSession(id: string, title: string): Promise<boolean> {
    if (!this.api || this.sessionMutationBusy || this.sessionPreferenceBusy) { return false; }
    const value = title.trim(); this.error = '';
    if (!value || value.length > 200) { this.error = '会话名称需为 1 至 200 个字符'; return false; }
    const api = this.api; const server = this.connected; this.sessionMutationBusy = true;
    try {
      await api.renameSession(id, value);
      if (api !== this.api || server !== this.connected) { return false; }
      this.sessions = this.sessions.map((s: SessionItem): SessionItem => s.id === id ? { id: s.id, title: value, directory: s.directory, status: s.status, model: s.model, agent: s.agent, parentID: s.parentID, forkType: s.forkType, forkBefore: s.forkBefore, updated: s.updated, archived: s.archived } : s);
      if (this.sessionID === id) { this.sessionTitle = value; }
      if (this.sessionPreferences.some((p: SessionPreference) => p.id === id)) {
        this.sessionPreferences = this.sessionPreferences.map((p: SessionPreference): SessionPreference => ({ id: p.id, pinned: p.pinned, archived: p.archived, directory: p.directory, title: p.id === id ? value : p.title }));
        try { await this.storage.saveSessionPreferences(server, this.sessionPreferences); }
        catch (_) { if (api === this.api) { this.error = '名称已在服务器更新，本机书签名称暂未保存。'; } }
        if (api !== this.api) { return false; }
      }
      this.pendingItems = this.pendingItems.map((item: PendingItem): PendingItem => ({ id: item.id, sessionID: item.sessionID, directory: item.directory, kind: item.kind, title: item.title, sessionTitle: item.sessionID === id ? value : item.sessionTitle, stale: item.stale }));
      return true;
    } catch (e) { if (api === this.api) { this.fail(e as Error); } return false; }
    finally { if (api === this.api) { this.sessionMutationBusy = false; } }
  }
  async refreshSessions(older: boolean = false, search: string = this.sessionQuery): Promise<void> {
    if (!this.api || !this.directory || (older && (this.sessionsBusy || !this.sessionCursor || this.sessions.length >= 500))) { return; }
    const api = this.api; const directory = this.directory; const epoch = ++this.sessionsEpoch;
    const query = search.trim().slice(0, 200); const cursor = older ? this.sessionCursor : '';
    this.sessionsBusy = true; this.sessionsError = '';
    try {
      const page = await api.sessionPage(directory, cursor, query);
      if (api !== this.api || directory !== this.directory || epoch !== this.sessionsEpoch) { return; }
      const byID = new Map<string, SessionItem>();
      (older ? this.sessions.concat(page.sessions) : page.sessions).forEach((s: SessionItem) => byID.set(s.id, s));
      this.sessions = Array.from(byID.values()).slice(0, 500); this.sessionCursor = page.cursor; this.sessionQuery = query;
    } catch (e) { if (api === this.api && epoch === this.sessionsEpoch) { this.sessionsError = (e as Error).message; this.fail(e as Error); } }
    finally { if (epoch === this.sessionsEpoch) { this.sessionsBusy = false; } }
  }
  private queueWorkspace(): void {
    if (this.workspaceTimer >= 0 || !this.active || !this.api || this.networkBlocked) { return; }
    this.workspaceTimer = setTimeout(() => { this.workspaceTimer = -1; this.refreshPending(); }, 600);
  }
  private async readPending(api: Protocol, scope: PendingScope): Promise<PendingResult> {
    try { return { scope: scope, items: await api.pending(scope.directory, scope.kind), error: '' }; }
    catch (e) { if (api === this.api && e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } return { scope: scope, items: [], error: (e as Error).message || '读取失败' }; }
  }
  async refreshPending(force: boolean = false): Promise<void> {
    if (!this.api || !this.active || this.networkBlocked || (this.pendingBusy && !force)) { return; }
    const api = this.api; const epoch = ++this.pendingEpoch; this.pendingBusy = true;
    const directories: string[] = [];
    [this.directory].concat(this.projects.map((p: ProjectItem) => p.directory), this.pendingItems.map((p: PendingItem) => p.directory))
      .forEach((directory: string) => { if (directory && directories.indexOf(directory) < 0) { directories.push(directory); } });
    const scopes: PendingScope[] = []; directories.slice(0, 64).forEach((directory: string) => {
      scopes.push({ directory: directory, kind: 'form' }, { directory: directory, kind: 'permission' });
    });
    let next = this.pendingItems.slice(); const errors: string[] = []; let truncated = directories.length > 64;
    try {
      try {
        const active = object(object(await api.request('/api/session/active'))['data']);
        if (api !== this.api || epoch !== this.pendingEpoch) { return; }
        this.runningSessions = Object.keys(active); this.runningUnknown = false;
        await this.detectSessionCompletions(this.runningSessions, api, epoch);
        if (api !== this.api || epoch !== this.pendingEpoch) { return; }
      } catch (e) {
        if (api !== this.api || epoch !== this.pendingEpoch) { return; }
        this.runningUnknown = true; errors.push('运行状态读取失败');
        if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); return; }
      }
      for (let i = 0; i < scopes.length; i += 6) {
        const results = await Promise.all(scopes.slice(i, i + 6).map((scope: PendingScope): Promise<PendingResult> => this.readPending(api, scope)));
        if (api !== this.api || epoch !== this.pendingEpoch) { return; }
        results.forEach((result: PendingResult) => {
          const retained = next.filter((p: PendingItem) => p.directory === result.scope.directory && p.kind === result.scope.kind);
          next = next.filter((p: PendingItem) => p.directory !== result.scope.directory || p.kind !== result.scope.kind);
          if (result.error) {
            errors.push(result.scope.directory + '：' + (result.scope.kind === 'form' ? '问题' : '审批') + '读取失败');
            retained.forEach((p: PendingItem) => next.push({ id: p.id, sessionID: p.sessionID, directory: p.directory, kind: p.kind, title: p.title, sessionTitle: p.sessionTitle, stale: true }));
          } else { next = next.concat(result.items); }
        });
        if (this.networkBlocked) { return; }
      }
      const unique = new Map<string, PendingItem>();
      next.forEach((p: PendingItem) => unique.set(pendingKey(p), { id: p.id, sessionID: p.sessionID, directory: p.directory, kind: p.kind,
        title: p.title, sessionTitle: this.sessions.find((s: SessionItem) => s.id === p.sessionID)?.title || p.sessionTitle, stale: p.stale }));
      if (unique.size > 500) { truncated = true; }
      this.pendingItems = Array.from(unique.values()).slice(0, 500);
      this.pendingError = errors.join('；') + (truncated ? '。显示范围已达上限，请打开对应项目单独处理。' : '');
      this.pendingUpdated = Date.now();
      this.detectPendingNotifications(errors.length > 0);
    } finally { if (epoch === this.pendingEpoch) { this.pendingBusy = false; } }
  }
  async openPending(item: PendingItem): Promise<void> {
    if (!this.api || this.busy) { return; }
    const api = this.api; const server = this.connected; this.error = ''; this.busy = true;
    try {
      const generation = this.generation;
      const session = await api.session(item.sessionID);
      if (generation !== this.generation || api !== this.api || server !== this.connected) { return; }
      const directory = session.directory || item.directory;
      if (directory !== this.directory) {
        await this.selectProject(session.directory || item.directory);
        if (api !== this.api || server !== this.connected || this.sessionsError) { return; }
      }
      if (this.directory !== directory) { return; }
      await this.openSession(session);
      this.queueWorkspace();
    } catch (e) { if (api === this.api) { this.fail(e as Error); } }
    finally { if (api === this.api) { this.busy = false; } }
  }
  private lastAssistantMessage(): ChatMessage | undefined {
    for (let i = this.messages.length - 1; i >= 0; i--) {
      const message = this.messages[i];
      if (message.role === 'assistant') { return message; }
    }
    return undefined;
  }
  private completionEvent(outcome: string = ''): TaskNotification | undefined {
    if (!this.connected || !this.sessionID) { return undefined; }
    const last = this.lastAssistantMessage();
    const kind = taskNotificationKind(outcome, last?.state || '');
    if (!kind || (last?.state === 'streaming' && kind !== 'failed')) { return undefined; }
    // A single completion identity per assistant message. The message state can
    // move from streaming to completed between two syncs; including it would
    // create a second notification for the same finished task.
    const eventID = completionEventID(last ? last.id : '', this.sessionID);
    return { serverID: this.connected, directory: this.directory, sessionID: this.sessionID,
      kind: kind, eventID: eventID, sessionTitle: this.sessionTitle };
  }
  private pendingEvent(item: PendingItem): TaskNotification {
    return { serverID: this.connected, directory: item.directory, sessionID: item.sessionID,
      kind: pendingNotificationKind(item.kind), eventID: item.id, sessionTitle: item.sessionTitle };
  }
  private interactionEvent(sessionID: string, item: Interaction): TaskNotification {
    const session = this.sessions.find((value: SessionItem) => value.id === sessionID);
    return { serverID: this.connected, directory: session?.directory || this.directory, sessionID: sessionID,
      kind: pendingNotificationKind(item.kind), eventID: item.id, sessionTitle: session?.title || this.sessionTitle };
  }
  // Ledger dedupe happens before any delivery, so a rejected permission or a
  // failing platform publish can never make the same event retry every sync.
  private dispatchReminder(event: TaskNotification): void {
    if (!event.serverID || !event.sessionID) { return; }
    if (!this.notificationLedger.offer(event)) { return; }
    if (this.taskNotifier.accepts?.(event.kind) === false) { return; }
    if (this.pane === 'chat' && this.conversationVisible && event.directory === this.directory &&
      isQuietReminder(event, this.sessionID, this.foreground)) {
      this.reminderQuiet = event.kind; this.reminderQuietSeq = this.reminderQuietSeq + 1; return;
    }
    try { this.taskNotifier.publish(event); } catch (_) { /* a reminder never breaks chat */ }
  }
  private seedReminderBaseline(outcome: string): void {
    // A running assistant is not an already-completed historical task.
    const completion = this.working ? undefined : this.completionEvent(outcome);
    if (completion) { this.notificationLedger.markSeen(completion); }
    this.interactions.forEach((item: Interaction) => {
      if (item.state !== 'submitting') { this.notificationLedger.markSeen(this.interactionEvent(this.sessionID, item)); }
    });
    this.pendingItems.forEach((item: PendingItem) => { this.notificationLedger.markSeen(this.pendingEvent(item)); });
  }
  private finishReminderSync(outcome: string, interactionsSynced: boolean): void {
    if (this.readingHistory) { return; }
    const suppress = this.notifyBaseline || this.syncSuppressNotify;
    if (interactionsSynced) { this.notifyBaseline = false; this.syncSuppressNotify = false; }
    if (suppress) { this.seedReminderBaseline(outcome); this.taskIdlePending = false; return; }
    if (this.taskIdlePending && !this.working) {
      const completion = this.completionEvent(outcome);
      if (completion) { this.taskIdlePending = false; this.dispatchReminder(completion); }
    }
  }
  // Only interactions that are still pending after a normal sync are announced.
  // Baseline, older-history reads and post-reconnect catch-up stay quiet.
  private detectInteractionNotifications(sessionID: string, items: Interaction[]): void {
    if (this.notifyBaseline || this.syncSuppressNotify || this.readingHistory || !this.connected) { return; }
    items.forEach((item: Interaction) => {
      if (item.state === 'submitting') { return; }
      this.dispatchReminder(this.interactionEvent(sessionID, item));
    });
  }
  // The first successful global pending read seeds existing items. A read with
  // failing scopes keeps the baseline so no half-read state can cause alerts.
  private detectPendingNotifications(failed: boolean): void {
    if (this.pendingBaseline) {
      if (!failed) {
        this.pendingItems.forEach((item: PendingItem) => { this.notificationLedger.markSeen(this.pendingEvent(item)); });
        this.pendingBaseline = false;
      }
      return;
    }
    if (this.pendingSuppressNotify) {
      this.pendingItems.forEach((item: PendingItem) => { this.notificationLedger.markSeen(this.pendingEvent(item)); });
      if (!failed) { this.pendingSuppressNotify = false; }
      return;
    }
    this.pendingItems.forEach((item: PendingItem) => { if (!item.stale) { this.dispatchReminder(this.pendingEvent(item)); } });
  }
  // A disappearing running ID is only a candidate. Confirm the terminal outcome
  // and message identity before deciding the category and deep-link directory.
  private async detectSessionCompletions(ids: string[], api: Protocol, epoch: number): Promise<void> {
    const next = new Set<string>(ids);
    ids.slice(0, 500).forEach((id: string) => {
      if (!this.runningTokens.has(id) && this.runningTokens.size < 500) {
        this.runningTokenSeq++; this.runningTokens.set(id, this.runningTokenSeq);
      }
    });
    const suppress = this.pendingBaseline || this.pendingSuppressNotify;
    const previous = Array.from(this.runningTokens.keys());
    const ended: string[] = [];
    previous.forEach((id: string) => {
      if (next.has(id)) { return; }
      if (suppress || id === this.sessionID) { this.runningTokens.delete(id); }
      else { ended.push(id); }
    });
    // Bound both retained candidates and concurrent terminal-state reads.
    for (let i = 0; i < ended.length; i += 4) {
      if (api !== this.api || epoch !== this.pendingEpoch) { return; }
      await Promise.all(ended.slice(i, i + 4).map((id: string): Promise<void> => this.confirmSessionCompletion(api, epoch, id)));
    }
  }
  private async confirmSessionCompletion(api: Protocol, epoch: number, id: string): Promise<void> {
    const server = this.connected; const token = this.runningTokens.get(id);
    try {
      const detail = object(object(await api.request('/api/session/' + encodeURIComponent(id)))['data']);
      const response = await api.messages(id);
      if (api !== this.api || server !== this.connected || epoch !== this.pendingEpoch ||
        token !== this.runningTokens.get(id) || this.runningSessions.indexOf(id) >= 0) { return; }
      const last = api.parseMessages(response).filter((item: ChatMessage) => item.role === 'assistant').pop();
      const kind = taskNotificationKind(string(detail['outcome']), last?.state || '');
      if (!kind || (last?.state === 'streaming' && kind !== 'failed')) { return; }
      const directory = string(object(detail['location'])['directory']);
      if (!directory) { return; }
      this.runningTokens.delete(id);
      const event: TaskNotification = { serverID: server, directory: directory, sessionID: id, kind: kind,
        eventID: completionEventID(last?.id || 'turn:' + String(token), id) };
      if (this.pendingSuppressNotify || this.pendingBaseline) { this.notificationLedger.markSeen(event); }
      else { this.dispatchReminder(event); }
    } catch (_) { /* retain the bounded candidate for a later successful read */ }
  }
  // Deep link from a system notification. It reuses the normal safe navigation:
  // the current draft is stashed first, a different server is connected through
  // the existing flow, then the project and session are opened.
  async openNotificationTarget(target: NotificationTarget): Promise<boolean> {
    if (this.targetBusy || this.busy || !target || !target.serverID || !target.sessionID) { return false; }
    this.targetBusy = true; this.error = '';
    let api = this.api;
    try {
      const server = this.servers.find((item: ServerConfig) => item.id === target.serverID);
      if (!server) { this.error = '提醒对应的服务器已从本机移除，请在连接页重新添加。'; return false; }
      if (this.connected !== target.serverID) {
        const connectedGeneration = await this.connect(server);
        if (connectedGeneration === undefined || connectedGeneration !== this.generation ||
          this.connected !== target.serverID || this.busy) { return false; }
      }
      api = this.api;
      if (!api) { return false; }
      const generation = this.generation;
      // Resolve first: a removed session must not replace the current project.
      const session = await api.session(target.sessionID);
      if (api !== this.api || generation !== this.generation || this.connected !== target.serverID ||
        !session || session.id !== target.sessionID) { return false; }
      const directory = session.directory || target.directory || this.directory;
      if (directory && directory !== this.directory) {
        await this.selectProject(directory);
        if (api !== this.api || this.generation !== generation + 1 || this.connected !== target.serverID ||
          this.directory !== directory || this.sessionsError) { return false; }
      }
      await this.openSession(session);
      return api === this.api && this.connected === target.serverID && this.sessionID === target.sessionID;
    } catch (e) { if (api === this.api) { this.fail(e as Error); } return false; }
    finally { this.targetBusy = false; }
  }
  async reconnect(): Promise<void> {
    const server = this.servers.find((s: ServerConfig) => s.id === this.connected);
    if (server && !this.busy) { await this.connect(server); }
  }
  private sessionPath(): string { return '/api/session/' + encodeURIComponent(this.sessionID); }
  private savePosition(): void {
    if (this.connected) { this.storage.position(this.connected, this.directory, this.sessionID).catch((e: Error) => this.fail(e)); }
  }
  editServer(server: ServerConfig): void {
    if (this.serverSaving || this.busy) { return; }
    this.serverEditID = server.id; this.serverName = server.name; this.serverUrl = server.url; this.serverUser = server.username;
    this.allowHttp = server.allowHttp; this.useDedicatedTrust = !!server.useDedicatedTrust; this.serverPassword = ''; this.clearServerPassword = false; this.serverNotice = ''; this.error = '';
  }
  resetServerForm(): void {
    this.serverEditID = ''; this.serverName = ''; this.serverUrl = 'https://'; this.serverUser = 'opencode'; this.serverPassword = ''; this.allowHttp = false; this.useDedicatedTrust = false; this.clearServerPassword = false;
  }
  async saveServer(): Promise<boolean> {
    if (this.serverSaving || this.busy) { return false; }
    const editID = this.serverEditID; const previous = this.servers.find((server: ServerConfig) => server.id === editID);
    if (editID && !previous) { this.error = '此连接已被移除，请重新添加'; return false; }
    const password = this.serverPassword; const clearPassword = this.clearServerPassword;
    let config: ServerConfig;
    try {
      if (clearPassword && password) { throw new Error('清除密码时请先清空新密码输入'); }
      config = prepareConnection({ name: this.serverName, url: this.serverUrl, username: this.serverUser, allowHttp: this.allowHttp, useDedicatedTrust: this.useDedicatedTrust } as ConnectionInput,
        this.servers, editID || 'srv_' + Date.now().toString(36) + Math.random().toString(36).slice(2, 6), previous?.preferredModel || '');
    } catch (e) { this.fail(e as Error); return false; }
    const identityChanged = !!previous && !sameConnectionIdentity(previous, config);
    if (identityChanged) { config.preferredModel = ''; }
    const oldServers = this.servers; const next = previous ? oldServers.map((server: ServerConfig) => server.id === config.id ? config : server) : oldServers.concat([config]);
    const updateSecret = !previous || !!password || clearPassword; let oldSecret = ''; let resetPosition = false; let changedSecret = false; let attemptedSave = false;
    let oldPosition: string[] = []; let oldFlags: SessionPreference[] = [];
    this.serverSaving = true; this.serverNotice = ''; this.error = '';
    try {
      if (updateSecret && previous) { oldSecret = await this.storage.secret(config.id); }
      if (identityChanged) {
        oldPosition = await this.storage.last(config.id); oldFlags = await this.storage.sessionPreferences(config.id);
        if (config.id === this.connected && !this.disconnect()) { this.serverSaving = false; return false; }
        resetPosition = true; await this.storage.resetServerPosition(config.id);
      }
      if (updateSecret) { changedSecret = true; await this.storage.saveSecret(config.id, clearPassword ? '' : password); }
      attemptedSave = true; await this.storage.saveServers(next); this.servers = next;
    } catch (_) {
      let restored = true;
      try { if (attemptedSave) { await this.storage.saveServers(oldServers); } if (changedSecret) { await this.storage.saveSecret(config.id, oldSecret); }
        if (resetPosition) { await this.storage.position(config.id, oldPosition[0] || '', oldPosition[1] || ''); await this.storage.saveSessionPreferences(config.id, oldFlags); }
      } catch (_) { restored = false; }
      this.error = restored ? '连接配置未保存，请重试；原有配置和凭据已恢复' : '连接保存结果待核对，请重新打开连接页检查后再重试'; this.serverSaving = false; return false;
    }
    if (identityChanged) {
      this.conversationMemory.clearServer(config.id); this.clearControlRecords(config.id); this.cacheEpoch++;
      if (previous) { try { await this.transcriptCache.removeServer(previous); this.refreshCacheSize(); } catch (_) { this.cacheNotice = '旧账号缓存未清理，请在存储设置中重试'; } }
    }
    this.resetServerForm(); this.serverNotice = '配置已保存';
    try { await this.connect(config); } finally { this.serverSaving = false; }
    return true;
  }
  async removeServer(id: string): Promise<boolean> {
    const removedConfig = this.servers.find((server: ServerConfig) => server.id === id);
    if (this.serverSaving || this.busy) { return false; }
    if (!this.servers.some((server: ServerConfig) => server.id === id)) { return false; }
    if (id === this.connected && !this.disconnect()) { return false; }
    const previous = this.servers; const next = previous.filter((server: ServerConfig) => server.id !== id);
    this.serverSaving = true; this.error = ''; let secret = ''; let changed = false; let position: string[] = []; let flags: SessionPreference[] = [];
    try {
      secret = await this.storage.secret(id); position = await this.storage.last(id); flags = await this.storage.sessionPreferences(id);
      changed = true; await this.storage.resetServerPosition(id); await this.storage.saveSecret(id, ''); await this.storage.saveServers(next);
      this.servers = next; this.conversationMemory.clearServer(id); this.clearControlRecords(id);
      if (this.serverEditID === id) { this.resetServerForm(); } this.serverNotice = '已从本机移除连接';
      if (removedConfig) { this.cacheEpoch++; try { await this.transcriptCache.removeServer(removedConfig); this.refreshCacheSize(); } catch (_) { this.cacheNotice = '部分缓存未清理，请在存储设置中重试'; } }
      return true;
    } catch (_) {
      let restored = true; if (changed) { try { await this.storage.saveSecret(id, secret); await this.storage.saveServers(previous); await this.storage.position(id, position[0] || '', position[1] || ''); await this.storage.saveSessionPreferences(id, flags); } catch (_) { restored = false; } }
      this.error = restored ? '连接未移除，请重试' : '移除结果待核对，请重新检查本机连接列表'; return false;
    } finally { this.serverSaving = false; }
  }
  private controlKey(): string { return this.connected + '\n' + this.directory + '\n' + this.sessionID; }
  private clearControlRecords(server: string): void {
    this.serverRevisions.set(server, (this.serverRevisions.get(server) || 0) + 1);
    Array.from(this.compactRecords.keys()).forEach((key: string) => { if (key.startsWith(server + '\n')) { this.compactRecords.delete(key); } });
    Array.from(this.unknownForks).forEach((key: string) => { if (key.startsWith(server + '\n')) { this.unknownForks.delete(key); } });
  }
  private resetSessionControl(): void {
    this.modelBusy = false; this.modelUncertain = false;
    this.usageEpoch++; this.parentSessionID = ''; this.branchBoundary = ''; this.usage = emptyUsage(); this.usageError = ''; this.usageLoading = false;
    this.forkBusy = false; this.forkError = ''; this.forkUncertain = this.unknownForks.has(this.controlKey()); this.compactionBusy = false;
    this.compaction = this.compactRecords.get(this.controlKey()) || { id: '', state: '', error: '' };
  }
  disconnect(): boolean {
    if (!this.stashConversation()) { return false; }
    this.pendingEpoch++; this.sessionsEpoch++; this.preferenceEpoch++; this.pendingItems = []; this.pendingError = ''; this.pendingUpdated = 0; this.pendingBusy = false;
    this.sessionCursor = ''; this.sessionQuery = ''; this.sessionsBusy = false; this.sessionsError = ''; this.sessionPreferences = [];
    this.sessionMutationBusy = false; this.sessionPreferenceBusy = false; this.runningSessions = []; this.runningUnknown = false; this.showArchived = false;
    this.cancelExport(); this.agentEpoch++; this.agents = []; this.agentID = ''; this.agentError = ''; this.agentBusy = false; this.agentLoading = false; this.agentUncertain = false;
    this.providers.attach(undefined, '', async (): Promise<void> => {});
    this.cacheRestored = false; this.lastHistorySync = 0; this.lastProbe = 0;
    this.clearTimeline(); this.generation++; this.transcriptEpoch++; this.readingHistory = false; this.newerAvailable = false; this.networkBlocked = false; this.stopNetwork(); this.api = undefined; this.connected = ''; this.status = '未连接'; this.modelVariant = ''; this.modelPreferenceEpoch++; this.modelPreferences = emptyModelPreferences(); this.modelPreferencesBusy = false; this.modelPreferencesError = '';
    this.projects = []; this.sessions = []; this.models = []; this.messages = []; this.interactions = []; this.permissionError = ''; this.permissionEpoch++;
    this.diffs = []; this.files = []; this.fileContent = ''; this.filePath = ''; this.directory = '';
    this.sessionID = ''; this.sessionTitle = ''; this.cursor = ''; this.tailLoaded = false; this.working = false; this.interrupting = false;
    this.resetSessionControl(); this.pendingSend = undefined; this.draft = ''; this.attachments = []; this.modelID = ''; this.eventIDs = []; this.syncing = false; this.syncAgain = false; this.busy = false;
    this.notificationLedger = new NotificationLedger(); this.notifyBaseline = false; this.syncSuppressNotify = false;
    this.pendingBaseline = true; this.pendingSuppressNotify = false; this.taskIdlePending = false; this.runningTokens = new Map<string, number>();
    this.cancelBackgroundReminderWindow();
    this.reminderQuiet = ''; this.reminderQuietSeq = 0; return true;
  }
  async connect(config: ServerConfig): Promise<number | undefined> {
    if (!this.disconnect()) { return; } const generation = this.generation; this.error = ''; this.status = '正在连接'; this.busy = true; let ownedGeneration = generation;
    try {
      const password = await this.storage.secret(config.id);
      if (generation !== this.generation) { return; }
      const api = new Protocol(config, password);
      const info = object(await api.request('/api/info'));
      const version = string(info['version']);
      if (!version.startsWith('2.')) { throw new ApiError(0, '此版本仅支持 OpenCode V2。服务器版本：' + (version || '未知')); }
      const projects = await api.projects();
      const flags = await this.storage.sessionPreferences(config.id);
      const modelPreferences = await this.storage.modelPreferences(config.id);
      if (generation !== this.generation) { return; }
      await api.enableHistoryCache();
      if (generation !== this.generation) { return; }
      this.api = api; this.providers.attach(api, '', async (): Promise<void> => { await this.refreshModels(); }); this.connected = config.id; this.version = version; this.projects = projects; this.sessionPreferences = flags; this.modelPreferences = modelPreferences;
      this.pendingBaseline = true; this.syncSuppressNotify = false; this.pendingSuppressNotify = false; this.taskIdlePending = false;
      this.storage.rememberServer(config.id).catch((e: Error) => this.fail(e));
      this.status = '已连接'; this.pane = 'chat'; this.attempts = 0; this.openStream();
      this.pollTimer = setInterval(() => {
        if (this.active) {
          this.poll().catch((e: Error) => this.fail(e));
          if (Date.now() - this.pendingUpdated > 15000) { this.refreshPending(); }
          if (Date.now() - this.lastData > 45000) { this.streamClose?.(); this.openStream(); }
        }
      }, 5000);
      this.queueWorkspace();
      const last = await this.storage.last(config.id);
      if (generation !== this.generation) { return; }
      if (last.length > 0 && last[0]) {
        await this.selectProject(last[0]);
        ownedGeneration++;
        if (api !== this.api || ownedGeneration !== this.generation || this.sessionsError) { return; }
        if (last[1]) {
          const session = this.sessions.find((s: SessionItem) => s.id === last[1]) || await api.session(last[1]);
          if (api !== this.api || ownedGeneration !== this.generation) { return; }
          if (session.directory === this.directory) {
            await this.openSession(session); ownedGeneration++;
            if (api !== this.api || ownedGeneration !== this.generation || this.sessionID !== session.id) { return; }
          }
        }
      }
      return api === this.api && ownedGeneration === this.generation ? ownedGeneration : undefined;
    } catch (e) { if (generation === this.generation) {
      this.status = '连接失败'; this.fail(e as Error);
      if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) {
        this.cacheEpoch++; try { await this.transcriptCache.removeServer(config); this.refreshCacheSize(); } catch (_) {}
      } else { await this.restoreOffline(config, generation); }
    } }
    finally { if (generation === this.generation) { this.busy = false; } }
    return undefined;
  }
  private stopNetwork(): void {
    this.streamReady = false; this.probeEpoch++; this.probeBusy = false;
    this.streamEpoch++;
    if (this.workspaceTimer >= 0) { clearTimeout(this.workspaceTimer); this.workspaceTimer = -1; }
    this.streamClose?.(); this.streamClose = undefined;
    if (this.pollTimer >= 0) { clearInterval(this.pollTimer); this.pollTimer = -1; }
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
    if (this.refreshTimer >= 0) { clearTimeout(this.refreshTimer); this.refreshTimer = -1; }
  }
  setActive(active: boolean): void {
    if (active && !this.foreground) { this.suppressNotificationCatchUp(); }
    this.active = active; this.providers.setActive(active); this.foreground = active;
    if (!active) {
      this.suppressNotificationCatchUp();
      this.pendingEpoch++; this.pendingBusy = false;
      this.streamEpoch++; this.streamClose?.(); this.streamClose = undefined;
      if (this.workspaceTimer >= 0) { clearTimeout(this.workspaceTimer); this.workspaceTimer = -1; }
      if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
      if (!this.networkBlocked) { this.status = this.api ? '后台暂停连接' : '未连接'; }
    } else if (this.api && !this.networkBlocked) { this.openStream(); this.queueSync(); this.queueWorkspace(); }
  }
  private openStream(): void {
    if (!this.api || !this.active || this.networkBlocked || this.status === '认证失败' || this.status === '证书校验失败') { return; }
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
    this.streamReady = false;
    this.streamClose?.(); const streamEpoch = ++this.streamEpoch; const generation = this.generation; this.lastData = Date.now();
    this.streamClose = this.api.stream((frame: SseFrame) => {
      if (generation === this.generation && streamEpoch === this.streamEpoch && this.active) { this.onFrame(frame); }
    }, () => { if (generation === this.generation && streamEpoch === this.streamEpoch) { this.lastData = Date.now(); } }, (error: Error) => {
      if (generation !== this.generation || streamEpoch !== this.streamEpoch || !this.active) { return; }
      if (error instanceof ApiError && (error.code === 401 || error.code === 403 || error.code === 495)) {
        this.networkBlocked = true; this.status = error.code === 495 ? '证书校验失败' : '认证失败'; this.error = error.message; this.stopNetwork(); return;
      }
      this.streamReady = false;
      this.suppressNotificationCatchUp();
      this.status = '重新连接中'; this.attempts++;
      if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); }
      this.retryTimer = setTimeout(() => { this.retryTimer = -1; this.openStream(); },
        Math.min(15000, 1000 * Math.pow(2, Math.min(this.attempts, 4))) + Math.random() * 500);
    });
  }
  private onFrame(frame: SseFrame): void {
    let event: Json;
    try { event = object(JSON.parse(frame.data) as Object); } catch (_) { return; }
    const type = string(event['type']); const id = string(event['id']);
    if (id && this.eventIDs.indexOf(id) >= 0) { return; }
    if (id) { this.eventIDs.push(id); if (this.eventIDs.length > 4096) { this.eventIDs.shift(); } }
    if (type === 'server.connected') {
      if (this.attempts > 0) { this.suppressNotificationCatchUp(); }
      this.streamReady = true; this.status = '实时连接'; this.attempts = 0; this.queueSync(); return;
    }
    const location = string(object(event['location'])['directory']);
    const data = object(event['data']); const sessionID = string(data['sessionID'], string(object(data['form'])['sessionID']));
    if (sessionID && type === 'session.idle') { this.runningSessions = this.runningSessions.filter((id: string) => id !== sessionID); }
    else if (sessionID && /^session\.(text|reasoning)\./.test(type)) {
      if (this.runningSessions.indexOf(sessionID) < 0) { this.runningSessions = this.runningSessions.concat([sessionID]); }
      if (!this.runningTokens.has(sessionID) && this.runningTokens.size < 500) {
        this.runningTokenSeq++; this.runningTokens.set(sessionID, this.runningTokenSeq);
      }
    }
    if (/^(form\.|permission\.|session\.(idle|created|updated|removed))/.test(type)) { this.queueWorkspace(); }
    if (location && location !== this.directory) { return; }
    if (!sessionID || sessionID !== this.sessionID) { return; }
    this.eventEpoch++;
    if (/^session\.(text|reasoning)\.(delta|ended)$/.test(type)) {
      const partType = type.indexOf('.reasoning.') >= 0 ? 'reasoning' : 'text';
      const ended = type.endsWith('.ended'); const ordinal = Number(data['ordinal'] || 0);
      const messageID = string(data['assistantMessageID']);
      if (this.readingHistory && !this.messages.some((m: ChatMessage) => m.id === messageID)) { this.newerAvailable = true; }
      else { this.messages = applyTextDelta(this.messages, messageID, ordinal, partType,
        string(data[ended ? 'text' : 'delta']), ended).slice(-300); }
      this.working = true; this.taskIdlePending = false;
      if (ended) { this.queueSync(); }
    } else {
      if (type === 'session.idle') {
        const wasWorking = this.working; this.working = false;
        // The task may be finished; a following sync decides completed/failed
        // from the newest assistant message before anything is displayed.
        if (wasWorking) { this.taskIdlePending = true; }
      }
      if (type.indexOf('retry') >= 0) { this.working = true; }
      this.queueSync();
    }
  }
  private queueSync(): void {
    if (!this.api || !this.active || this.networkBlocked) { return; }
    if (this.refreshTimer >= 0) { return; }
    this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; this.sync().catch((e: Error) => this.fail(e)); }, 750);
  }
  async selectProject(directory: string): Promise<void> {
    if (!this.api || !directory.trim()) { return; }
    if (!this.stashConversation()) { return; }
    this.sessionsEpoch++; this.sessionCursor = ''; this.sessionQuery = ''; this.sessionsBusy = false; this.sessionsError = ''; this.showArchived = false;
    this.clearTimeline(); this.generation++; this.streamClose?.(); const generation = this.generation; const api = this.api;
    this.cancelExport(); this.agentEpoch++; this.agents = []; this.agentID = ''; this.agentError = ''; this.agentBusy = false; this.agentLoading = false; this.agentUncertain = false;
    this.providers.attach(api, directory.trim(), async (): Promise<void> => { await this.refreshModels(); });
    this.pendingSend = undefined; this.draft = ''; this.attachments = []; this.directory = directory.trim(); this.sessionID = ''; this.modelID = ''; this.modelVariant = ''; this.resetSessionControl(); this.sessions = []; this.models = []; this.messages = []; this.interactions = []; this.permissionError = ''; this.permissionEpoch++; this.diffs = [];
    this.fileContent = ''; this.filePath = ''; this.files = []; this.fileTruncated = false; this.cursor = ''; this.tailLoaded = false; this.readingHistory = false; this.newerAvailable = false; this.transcriptEpoch++; this.error = ''; this.busy = true; this.syncing = false;
    try {
      await api.request('/api/location?' + api.scope(this.directory));
      const page = await api.sessionPage(this.directory);
      const models = await api.models(this.directory);
      if (generation !== this.generation) { return; }
      await this.loadAgents(); if (generation !== this.generation) { return; }
      this.sessions = page.sessions; this.sessionCursor = page.cursor; this.models = models; this.manualPath = this.directory; this.pane = 'projects';
      this.savePosition(); this.openStream(); this.queueWorkspace();
    } catch (e) { if (generation === this.generation) { this.sessionsError = (e as Error).message; this.fail(e as Error); this.openStream(); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  async createSession(): Promise<void> {
    if (!this.api || !this.directory || this.busy) { return; }
    if (!this.stashConversation()) { return; }
    const generation = this.generation; this.busy = true;
    const preferred = this.servers.find((s: ServerConfig) => s.id === this.connected)?.preferredModel || '';
    try {
      const result = object(await this.api.request('/api/session', http.RequestMethod.POST,
        { title: '新的开发会话', location: { directory: this.directory } } as CreateRequest));
      if (generation !== this.generation) { return; }
      const s = object(result['data']);
      const session: SessionItem = { id: string(s['id']), title: string(s['title'], '新的开发会话'), directory: this.directory, model: '', status: 'idle' };
      this.sessions = [session].concat(this.sessions.filter((item: SessionItem) => item.id !== session.id)).slice(0, 50);
      await this.openSession(session);
      if (generation + 1 === this.generation && preferred && this.models.some((m: ModelItem) => m.id === preferred)) { await this.chooseModel(preferred); }
    } catch (e) { this.fail(e as Error); } finally { this.busy = false; }
  }
  async openSession(session: SessionItem): Promise<void> {
    if (!this.api || !this.stashConversation()) { return; }
    const api = this.api;
    if (session.directory && session.directory !== this.directory) {
      await this.selectProject(session.directory);
      if (api !== this.api || this.directory !== session.directory || this.sessionsError) { return; }
    }
    this.cancelExport(); this.agentEpoch++; this.agentID = session.agent || ''; this.agentError = ''; this.agentBusy = false; this.agentLoading = false; this.agentUncertain = false;
    this.clearTimeline(); this.generation++; this.streamClose?.(); this.syncing = false; this.syncAgain = false;
    this.transcriptEpoch++; this.readingHistory = false; this.newerAvailable = false;
    this.cacheRestored = false; this.lastHistorySync = 0; this.lastProbe = 0; this.sessionVersion = 0; this.probeEpoch++; this.probeBusy = false;
    this.sessionID = session.id; this.sessionTitle = session.title; this.modelID = session.model; this.modelVariant = session.variant || ''; this.resetSessionControl(); this.parentSessionID = session.parentID || ''; this.branchBoundary = session.forkType === 'before' ? '所选消息之前' : session.forkType === 'through' ? '创建分叉时的最后一条消息' : '';
    // Existing history and pending items are seeded on the first sync; they are
    // never announced as new while the user is opening the conversation.
    this.notifyBaseline = true; this.taskIdlePending = false;
    this.messages = []; this.interactions = []; this.permissionError = ''; this.permissionEpoch++; this.diffs = []; this.cursor = ''; this.tailLoaded = false; this.pendingSend = undefined;
    const saved = this.conversationMemory.read(this.connected, this.directory, session.id);
    this.draft = saved.text; this.attachments = saved.files || []; this.pendingSend = saved.pending; this.working = false; this.interrupting = false; this.pane = 'chat'; this.error = ''; this.savePosition(); this.openStream(); this.queueWorkspace();
    const generation = this.generation; this.busy = true; await this.restoreTranscript(generation);
    if (generation !== this.generation) { return; }
    await this.sync(); if (generation === this.generation) { this.busy = false; }
  }
  async sync(): Promise<void> {
    if (!this.api || !this.sessionID || !this.active || this.networkBlocked) { return; }
    if (this.syncing) { this.syncAgain = true; return; }
    this.syncing = true; const generation = this.generation; const api = this.api;
    const id = this.sessionID; const epoch = this.eventEpoch; const transcript = this.transcriptEpoch; const selection = this.selectionEpoch;
    const cacheEpoch = this.cacheEpoch; const directory = this.directory;
    try {
      const response = await api.messages(id);
      if (generation !== this.generation || transcript !== this.transcriptEpoch) { return; }
      const incoming = api.parseMessages(response);
      await this.cachedFiles(incoming, api.config);
      if (generation !== this.generation || transcript !== this.transcriptEpoch) { return; }
      const safe = incoming.map((m: ChatMessage): ChatMessage => {
        const current = this.messages.find((old: ChatMessage) => old.id === m.id);
        if (current && m.state !== 'completed' &&
          (epoch !== this.eventEpoch || current.text.length > m.text.length || current.reasoning.length > m.reasoning.length)) {
          return { id: m.id, role: m.role, text: current.text, reasoning: current.reasoning,
            parts: current.parts, tools: m.tools, state: current.state, files: m.files };
        }
        return m;
      });
      if (this.readingHistory) {
        if (safe.some((m: ChatMessage) => !this.messages.some((old: ChatMessage) => old.id === m.id))) { this.newerAvailable = true; }
        this.messages = mergeMessages(this.messages, safe.filter((m: ChatMessage) => this.messages.some((old: ChatMessage) => old.id === m.id)));
      } else { const merged = mergeMessages(this.messages, safe); this.messages = merged.length > 300 ? merged.slice(-300) : merged; }
      this.messages = boundMessageAttachments(this.messages);
      this.cacheRestored = false; this.lastHistorySync = Date.now(); this.lastProbe = Date.now();
      this.saveTranscript(api.config, id, directory, safe, string(object(object(response)['cursor'])['next']), cacheEpoch);
      if (!this.tailLoaded) { this.cursor = string(object(object(response)['cursor'])['next']); this.tailLoaded = true; }
      if (this.pendingSend) {
        const pending = this.pendingSend; let confirmed = incoming.some((m: ChatMessage) => m.id === pending.id);
        if (!confirmed) {
          try { const message = object(object(await api.request('/api/session/' + encodeURIComponent(id) + '/message/' + encodeURIComponent(pending.id)))['data']); confirmed = message['id'] === pending.id && message['type'] === 'user'; }
          catch (e) { if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { throw e; } }
        }
        if (generation !== this.generation) { return; }
        if (confirmed && this.pendingSend?.id === pending.id) { this.pendingSend = undefined; this.draft = ''; this.attachments = []; if (this.error.indexOf('发送结果待核对') >= 0) { this.error = ''; } this.clearSavedDraft(); }
      }
      const formsSynced = await this.syncInteractions(api, id, 'form', generation);
      const permissionsSynced = await this.syncInteractions(api, id, 'permission', generation);
      const active = object(object(await api.request('/api/session/active'))['data']);
      const usageEpoch = ++this.usageEpoch; const detail = object(object(await api.request('/api/session/' + encodeURIComponent(id)))['data']);
      const inbox = rows(await api.request('/api/session/' + encodeURIComponent(id) + '/inbox'));
      if (generation === this.generation) {
        if (usageEpoch === this.usageEpoch) { this.usage = parseUsage(detail); this.usageError = ''; }
        this.sessionVersion = Number(object(detail['time'])['updated']) || 0;
        this.readBranch(detail); this.updateCompactPage(response, inbox);
        this.runningSessions = Object.keys(active);
        const title = string(detail['title'], this.sessionTitle);
        if (title !== this.sessionTitle) {
          this.sessionTitle = title;
          this.sessions = this.sessions.map((item: SessionItem): SessionItem => ({ id: item.id, title: item.id === id ? title : item.title, directory: item.directory, status: item.status, model: item.model, variant: item.variant, agent: item.agent, parentID: item.parentID, forkType: item.forkType, forkBefore: item.forkBefore, updated: item.updated, archived: item.archived }));
        }
        const wasWorking = this.working; const wasListedRunning = this.runningSessions.indexOf(id) >= 0;
        if (active[id] !== undefined || inbox.length > 0) { this.working = true; }
        else if (detail['outcome']) { this.working = false; if (wasWorking || wasListedRunning) { this.taskIdlePending = true; } }
        const model = object(detail['model']);
        if (selection === this.selectionEpoch) {
          this.agentID = string(detail['agent']);
          this.modelVariant = string(model['variant']);
          if (model['id']) {
            if (this.modelUncertain && this.error === '模型设置结果待核对，请同步后再继续') { this.error = ''; }
            this.modelUncertain = false;
          }
          if (model['id']) { this.modelID = string(model['providerID']) + '/' + string(model['id']); }
          else { this.modelID = this.agents.find((a: AgentItem) => a.id === this.agentID)?.model || ''; }
        }
        this.finishReminderSync(string(detail['outcome']), formsSynced && permissionsSynced);
      }
    } catch (e) {
      if (generation === this.generation) {
        this.fail(e as Error);
        if (e instanceof ApiError && ((e as ApiError).code === 401 || (e as ApiError).code === 403 || (e as ApiError).code === 495)) {
          this.networkBlocked = true; this.status = (e as ApiError).code === 495 ? '证书校验失败' : '认证失败'; this.stopNetwork();
        }
      }
    } finally {
      if (generation === this.generation) {
        this.syncing = false; if (this.syncAgain) { this.syncAgain = false; this.queueSync(); }
      }
    }
  }
  private async syncInteractions(api: Protocol, id: string, kind: string, generation: number): Promise<boolean> {
    const epoch = kind === 'permission' ? ++this.permissionEpoch : 0;
    try {
      const incoming = await api.interactions(id, kind, this.directory);
      if (generation !== this.generation || (kind === 'permission' && epoch !== this.permissionEpoch)) { return false; }
      const savedForms = this.conversationMemory.read(this.connected, this.directory, id).forms || [];
      const next = incoming.map((item: Interaction): Interaction => {
        const old = this.interactions.find((p: Interaction) => p.id === item.id);
        const saved = kind === 'form' ? savedForms.find((p: QuestionDraft) => p.id === item.id) : undefined;
        if (!old && saved) { return { id: item.id, sessionID: item.sessionID, kind: item.kind, title: item.title, detail: item.detail, approval: item.approval,
          fields: mergeFormDraft(item.fields, saved.fields), state: 'pending' }; }
        return old ? { id: item.id, sessionID: item.sessionID, kind: item.kind, title: item.title, detail: item.detail, approval: item.approval,
          fields: mergeFormDraft(item.fields, old.fields), state: old.state === 'submitting' ? 'submitting' : 'pending' } : item;
      });
      const combined = this.interactions.filter((p: Interaction) => p.kind !== kind).concat(next);
      if (JSON.stringify(this.interactions) !== JSON.stringify(combined)) { this.interactions = combined; }
      if (kind === 'permission') { this.permissionError = ''; }
      this.detectInteractionNotifications(id, next);
      return true;
    } catch (e) {
      if (generation === this.generation && (kind !== 'permission' || epoch === this.permissionEpoch)) {
        if (kind === 'permission') { this.permissionError = '审批列表读取失败，已保留上次结果。请重新读取后再批准；仍可拒绝已显示的请求。'; }
        else { this.fail(e as Error); }
      }
      return false;
    }
  }
  async retryPermissions(): Promise<void> {
    if (this.api && this.sessionID) { await this.syncInteractions(this.api, this.sessionID, 'permission', this.generation); }
  }
  canApprove(id: string): boolean {
    const item = this.interactions.find((p: Interaction) => p.id === id);
    return item !== undefined && !this.permissionError && item.state !== 'submitting' && item.approval?.incomplete !== true;
  }
  async older(): Promise<void> {
    if (!this.api || !this.cursor || this.busy) { return; }
    const generation = this.generation; const transcript = ++this.transcriptEpoch; this.readingHistory = true; this.busy = true;
    try {
      const result = await this.api.messages(this.sessionID, this.cursor);
      if (generation !== this.generation || transcript !== this.transcriptEpoch) { return; }
      this.messages = boundMessageAttachments(mergeMessages(this.messages, this.api.parseMessages(result), true).slice(0, 300));
      this.cursor = string(object(object(result)['cursor'])['next']);
    } catch (e) { this.fail(e as Error); } finally { if (generation === this.generation) { this.busy = false; } }
  }
  async latest(): Promise<void> {
    this.transcriptEpoch++; this.readingHistory = false; this.newerAvailable = false;
    // Returning from older history is a catch-up view, not a new event.
    this.notifyBaseline = true; this.taskIdlePending = false;
    this.messages = []; this.cursor = ''; this.tailLoaded = false; this.syncAgain = true;
    await this.sync();
  }
  async attachmentPreview(item: Attachment): Promise<Attachment> {
    if (item.data || !this.api) { return item; }
    const message = this.messages.find((m: ChatMessage) => m.files?.some((f: Attachment) => f.id === item.id));
    if (!message) { return item; }
    const generation = this.generation; const epoch = this.cacheEpoch; const api = this.api; const config = api.config; const sessionID = this.sessionID;
    try {
      let file: Attachment | undefined = undefined;
      if (item.remoteHash) {
        let data = '';
        if (config) { try { data = await this.transcriptCache.file(config, item.remoteHash); } catch (_) { this.cacheNotice = '附件缓存暂不可用，正在联网读取'; } }
        if (generation !== this.generation || api !== this.api) { return item; }
        file = data ? { id: item.id, name: item.name, mime: item.mime, size: item.size, data: data,
          fingerprint: item.remoteHash, remoteHash: item.remoteHash, remoteMessage: item.remoteMessage, remoteIndex: item.remoteIndex } :
          await api.historyFile(sessionID, item);
        if (config && !data && file.data && epoch === this.cacheEpoch) {
          try { await this.transcriptCache.saveFile(config, item.remoteHash, file.data); this.refreshCacheSize(); }
          catch (_) { this.cacheNotice = '附件已读取，本次未能缓存'; }
        }
      } else {
        const result = await api.request(this.sessionPath() + '/message/' + encodeURIComponent(message.id));
        const envelope: Json = {}; const entries: Object[] = [object(result)['data']]; envelope['data'] = entries;
        file = api.parseMessages(envelope)[0]?.files?.find((f: Attachment) => f.id === item.id);
      }
      if (generation !== this.generation || api !== this.api) { return item; }
      if (file) {
        const ready = file;
        this.messages = this.messages.map((m: ChatMessage): ChatMessage => m.id === message.id ? {
          id: m.id, role: m.role, text: m.text, reasoning: m.reasoning, parts: m.parts, tools: m.tools, state: m.state,
          files: m.files?.map((f: Attachment): Attachment => f.id === item.id ? ready : f)
        } : m);
      }
      return file || item;
    } catch (_) { return { id: item.id, name: item.name, mime: item.mime, size: item.size, data: '', error: '读取失败，请关闭后重试' }; }
  }

  async send(): Promise<void> {
    if (!this.api || !this.sessionID || this.busy || this.modelBusy || this.modelUncertain || this.agentBusy || this.agentUncertain || this.forkBusy || this.compactionBusy || ['queued', 'running', 'submitting'].indexOf(this.compaction.state) >= 0 || (!this.draft.trim() && !this.attachments.length && !this.pendingSend)) { return; }
    const pending: PendingPrompt = this.pendingSend || {
      id: 'msg_' + Date.now().toString(36) + Math.random().toString(36).slice(2),
      sessionID: this.sessionID, text: this.draft.trim(), files: this.attachments.map((a: Attachment): Attachment => ({ id: a.id, name: a.name, mime: a.mime, data: a.data, size: a.size }))
    };
    const problem = attachmentProblem(pending.files || [], this.attachmentInput());
    if (problem) { this.error = problem; return; }
    this.pendingSend = pending; const generation = this.generation; this.busy = true; this.error = '';
    try {
      await this.api.request(this.sessionPath() + '/prompt', http.RequestMethod.POST,
        { id: pending.id, text: pending.text, delivery: 'steer', resume: true, files: pending.files?.length ? promptFiles(pending.files) : undefined } as PromptRequest);
      if (generation !== this.generation) { return; }
      this.pendingSend = undefined; this.draft = ''; this.attachments = []; this.clearSavedDraft(); this.working = true; if (this.readingHistory) { await this.latest(); } else { await this.sync(); }
    } catch (e) {
      if (generation === this.generation) {
        this.fail(e as Error);
        if (e instanceof ApiError && [400, 401, 403, 404, 405, 413, 422, 495].indexOf(e.code) >= 0) {
          this.pendingSend = undefined; this.draft = pending.text; this.attachments = pending.files || []; this.stashConversation();
        } else { this.error += '。发送结果待核对，重试将使用同一消息 ID'; }
      }
    } finally { if (generation === this.generation) { this.busy = false; } }
  }
  async interrupt(): Promise<void> {
    if (!this.api || !this.sessionID || this.interrupting) { return; }
    const generation = this.generation; this.interrupting = true;
    try { await this.api.request(this.sessionPath() + '/interrupt', http.RequestMethod.POST); if (generation === this.generation) { await this.sync(); } }
    catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
    finally { if (generation === this.generation) { this.interrupting = false; } }
  }
  private readBranch(detail: Json): void {
    const fork = object(detail['fork']); const type = string(object(fork['boundary'])['type']);
    this.parentSessionID = string(fork['sessionID'], string(detail['parentID'])); this.branchBoundary = type === 'before' ? '所选消息之前' : type === 'through' ? '创建分叉时的最后一条消息' : '';
  }
  private publishCompact(key: string, record: CompactRecord, revision: number = -1): void {
    if (revision >= 0 && revision !== (this.serverRevisions.get(key.split('\n')[0]) || 0)) { return; }
    this.compactRecords.set(key, record); if (key === this.controlKey()) { this.compaction = record; }
  }
  private updateCompactPage(response: Object, inbox: Object[]): void {
    const tracked = this.compactRecords.get(this.controlKey());
    const value = rows(response).find((value: Object) => object(value)['type'] === 'compaction' && (!tracked?.id || object(value)['id'] === tracked.id));
    if (value) { this.publishCompact(this.controlKey(), parseCompactRecord(value)); }
    else if (tracked && inbox.some((value: Object) => object(value)['id'] === tracked.id && object(value)['type'] === 'compaction')) { this.publishCompact(this.controlKey(), { id: tracked.id, state: 'queued', error: '' }); }
  }
  private async requireIdle(api: Protocol, id: string, directory: string): Promise<void> {
    const checks = await Promise.all([api.request('/api/session/active'), api.interactions(id, 'form', directory), api.interactions(id, 'permission', directory),
      api.request('/api/session/' + encodeURIComponent(id) + '/inbox'), api.request('/api/session/' + encodeURIComponent(id))]);
    if (object(object(checks[0])['data'])[id] !== undefined || (checks[1] as Interaction[]).length || (checks[2] as Interaction[]).length || rows(checks[3]).length) { throw new Error('当前任务或待办尚未结束，请先处理后再操作'); }
    const detail = object(object(checks[4])['data']);
    if (detail['id'] !== id) { throw new Error('会话状态未能确认，请重新连接后重试'); }
    if (detail['revert']) { throw new Error('此会话存在待确认的回退，请先在桌面处理'); }
  }
  async refreshUsage(): Promise<void> {
    if (!this.api || !this.sessionID || this.usageLoading) { return; }
    const api = this.api; const id = this.sessionID; const generation = this.generation; const epoch = ++this.usageEpoch; const key = this.controlKey(); this.usageLoading = true; this.usageError = '';
    try {
      const detail = object(object(await api.request('/api/session/' + encodeURIComponent(id)))['data']);
      if (detail['id'] !== id) { throw new Error('会话信息不完整，请重试'); }
      if (generation !== this.generation) { return; }
      if (epoch === this.usageEpoch) { this.usage = parseUsage(detail); this.readBranch(detail); }
      const tracked = this.compactRecords.get(key);
      if (tracked?.id) { const record = await api.compactionStatus(id, tracked.id); if (generation === this.generation) { this.publishCompact(key, record); } }
    } catch (e) { if (generation === this.generation) { this.usageError = '读取失败，已保留上次用量与压缩状态，请重新读取'; if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } } }
    finally { if (generation === this.generation) { this.usageLoading = false; } }
  }
  async requestCompaction(): Promise<void> {
    if (!this.api || !this.sessionID || this.busy || this.forkBusy || this.compactionBusy || this.agentBusy) { return; }
    const api = this.api; const id = this.sessionID; const directory = this.directory; const key = this.controlKey(); const generation = this.generation;
    const revision = this.serverRevisions.get(this.connected) || 0; const old = this.compactRecords.get(key);
    if (old && ['queued', 'running', 'submitting'].indexOf(old.state) >= 0) { return; }
    if (this.working || this.pendingSend || this.interactions.length || this.permissionError) { this.usageError = '请先结束任务、确认发送结果并处理问题或审批'; return; }
    this.compactionBusy = true; this.usageError = ''; let submitted = false; let requestID = old?.state === 'unknown' ? old.id : '';
    try {
      if (requestID) { const existing = await api.compactionStatus(id, requestID); if (generation !== this.generation) { return; } if (existing.state !== 'unknown') { this.publishCompact(key, existing, revision); return; } }
      await this.requireIdle(api, id, directory); if (generation !== this.generation) { return; }
      requestID = requestID || 'msg_' + Date.now().toString(36) + Math.random().toString(36).slice(2);
      this.publishCompact(key, { id: requestID, state: 'submitting', error: '' }, revision); submitted = true;
      await api.compact(id, requestID); this.publishCompact(key, { id: requestID, state: 'queued', error: '' }, revision);
      if (generation === this.generation) { this.working = true; await this.sync(); await this.refreshUsage(); }
    } catch (e) {
      if (submitted) {
        const rejected = e instanceof ApiError && [400, 401, 403, 404, 405, 422, 495].indexOf(e.code) >= 0;
        this.publishCompact(key, { id: requestID, state: rejected ? 'failed' : 'unknown', error: rejected ? (e as Error).message : '提交结果待核对，请重新读取；重试将沿用同一请求' }, revision);
      }
      if (generation === this.generation) { this.usageError = (e as Error).message || '压缩未能提交'; if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } }
    } finally { if (generation === this.generation) { this.compactionBusy = false; } }
  }
  clearForkAfterReview(): void { this.unknownForks.delete(this.controlKey()); this.forkUncertain = false; this.forkError = ''; }
  async forkSession(before: string, edit: boolean, text: string, reuseFiles: boolean): Promise<SessionItem | undefined> {
    if (!this.api || !this.sessionID || this.busy || this.forkBusy || this.compactionBusy || this.agentBusy) { return undefined; }
    const api = this.api; const id = this.sessionID; const directory = this.directory; const server = this.connected; const generation = this.generation; const key = this.controlKey();
    const revision = this.serverRevisions.get(server) || 0;
    if (this.unknownForks.has(key)) { this.forkUncertain = true; this.forkError = '上次分叉结果待确认，请先检查会话列表，避免重复创建'; return undefined; }
    if (this.working || this.pendingSend || this.interactions.length || this.permissionError) { this.forkError = '请先结束任务、确认发送结果并处理问题或审批'; return undefined; }
    if (before && !this.messages.some((message: ChatMessage) => message.id === before)) { this.forkError = '请重新加载原消息后再分叉'; return undefined; }
    if (edit && text.length > 20000) { this.forkError = '编辑内容最多 20000 字符'; return undefined; }
    if (!this.stashConversation()) { return undefined; }
    this.forkBusy = true; this.forkError = ''; let submitted = false; let reserved = false;
    const reservation = '__fork_' + Date.now().toString(36) + Math.random().toString(36).slice(2); let files: Attachment[] = [];
    try {
      await this.requireIdle(api, id, directory); if (generation !== this.generation) { return undefined; }
      if (edit) {
        if (!this.messages.some((message: ChatMessage) => message.id === before && message.role === 'user')) { throw new Error('请从用户消息创建编辑分叉'); }
        if (reuseFiles) {
          const raw = object(object(await api.request('/api/session/' + encodeURIComponent(id) + '/message/' + encodeURIComponent(before)))['data']);
          if (raw['id'] !== before || raw['type'] !== 'user') { throw new Error('原用户消息未能确认，请重新选择'); }
          if (list(raw['files']).length > 4) { throw new Error('原消息附件超过 4 个，请取消沿用附件后重新选择'); }
          files = api.parseMessages({ data: [raw] } as HistoryResponse)[0]?.files || [];
          const problem = attachmentProblem(files, ['text', 'image', 'pdf']); if (problem) { throw new Error(problem); }
        }
        if (!text.trim() && !files.length) { throw new Error('请填写问题或沿用原附件'); }
        this.conversationMemory.save(server, directory, reservation, text, undefined, [], files); reserved = true;
      }
      if (generation !== this.generation) { return undefined; }
      submitted = true; const child = await api.fork(id, before);
      if (child.directory !== directory) { throw new Error('分叉目录与原会话不一致，请检查会话列表'); }
      if (revision === (this.serverRevisions.get(server) || 0)) { this.unknownForks.delete(key); }
      if (reserved) { this.conversationMemory.save(server, directory, reservation, '', undefined, []); reserved = false; }
      if (api === this.api && edit) { this.conversationMemory.save(server, directory, child.id, text, undefined, [], files); }
      if (generation === this.generation) { this.sessions = [child].concat(this.sessions.filter((session: SessionItem) => session.id !== child.id)).slice(0, 500); this.forkError = ''; }
      return child;
    } catch (e) {
      const uncertain = submitted && (!(e instanceof ApiError) || [400, 401, 403, 404, 405, 422, 495].indexOf(e.code) < 0);
      if (uncertain && revision === (this.serverRevisions.get(server) || 0)) { this.unknownForks.add(key); }
      if (generation === this.generation) { this.forkUncertain = uncertain; this.forkError = uncertain ? '分叉结果待确认，请检查会话列表；不会自动重复创建' : (e as Error).message; if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } }
      return undefined;
    } finally {
      if (reserved) { this.conversationMemory.save(server, directory, reservation, '', undefined, []); }
      if (generation === this.generation) { this.forkBusy = false; }
    }
  }
  async openParentSession(): Promise<void> {
    if (!this.api || !this.parentSessionID || this.busy || this.forkBusy || this.compactionBusy) { return; }
    const api = this.api; const generation = this.generation; const parent = this.parentSessionID;
    try { const session = await api.session(parent); if (generation === this.generation) { await this.openSession(session); } }
    catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
  async loadAgents(): Promise<void> {
    if (!this.api || !this.directory) { return; } const api = this.api; const generation = this.generation; const epoch = ++this.agentEpoch;
    this.agentLoading = true;
    try { const agents = await api.agents(this.directory); if (generation === this.generation && epoch === this.agentEpoch) { this.agents = agents; this.agentError = ''; } }
    catch (e) { if (generation === this.generation && epoch === this.agentEpoch) { this.agentError = 'Agent 列表读取失败，请重新读取；聊天仍可使用当前 Agent。'; if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } } }
    finally { if (generation === this.generation && epoch === this.agentEpoch) { this.agentLoading = false; } }
  }
  private async readAgentState(api: Protocol, id: string, generation: number): Promise<void> {
    const session = await api.session(id);
    if (generation !== this.generation || id !== this.sessionID) { return; }
    this.selectionEpoch++; this.modelVariant = session.variant || ''; this.agentID = session.agent || ''; this.modelID = session.model || this.agents.find((a: AgentItem) => a.id === this.agentID)?.model || ''; this.agentUncertain = false;
  }
  async refreshAgentState(): Promise<void> {
    if (!this.api || this.agentBusy || this.agentLoading) { return; } const api = this.api; const id = this.sessionID; const generation = this.generation;
    await this.loadAgents();
    if (generation !== this.generation || !id) { return; }
    this.agentLoading = true;
    try { await this.readAgentState(api, id, generation); }
    catch (e) { if (generation === this.generation) { this.agentError = '当前 Agent 尚未确认，请恢复连接后重新读取。'; this.agentUncertain = true; if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } } }
    finally { if (generation === this.generation) { this.agentLoading = false; } }
  }
  async chooseAgent(id: string): Promise<boolean> {
    if (!this.api || !this.sessionID || this.busy || this.modelBusy || this.modelUncertain || this.agentBusy || this.agentLoading || this.agentUncertain || this.forkBusy || this.compactionBusy) { return false; }
    if (id === this.agentID) { return true; }
    if (!this.agents.some((a: AgentItem) => a.id === id)) { this.agentError = '请从当前服务器的可用 Agent 中选择'; return false; }
    if (this.working || this.pendingSend || this.interactions.length || this.permissionError) { this.agentError = '请先结束当前任务并处理问题或审批，再切换 Agent'; return false; }
    const api = this.api; const session = this.sessionID; const directory = this.directory; const generation = this.generation;
    this.agentBusy = true; this.agentError = ''; this.selectionEpoch++; let submitted = false; let accepted = false;
    try {
      const checks = await Promise.all([api.request('/api/session/active'), api.interactions(session, 'form', directory), api.interactions(session, 'permission', directory)]);
      if (generation !== this.generation) { return false; }
      if (object(object(checks[0])['data'])[session] !== undefined || (checks[1] as Interaction[]).length || (checks[2] as Interaction[]).length) { this.agentError = '当前任务或待办已更新，请先处理后再切换 Agent'; return false; }
      submitted = true; await api.request('/api/session/' + encodeURIComponent(session) + '/agent', http.RequestMethod.POST, { agent: id } as AgentRequest); accepted = true;
      if (generation !== this.generation) { return false; }
      await this.readAgentState(api, session, generation);
      if (generation !== this.generation) { return false; }
      if (this.agentID !== id) { this.agentError = '服务器当前使用其他 Agent，请核对后再选择'; return false; }
      return true;
    } catch (e) {
      if (generation === this.generation) {
        this.agentUncertain = submitted && (accepted || !(e instanceof ApiError) || e.code >= 500);
        this.agentError = this.agentUncertain ? '切换结果待确认，请重新读取状态；不会自动重复提交。' : (e as Error).message || 'Agent 切换失败，请重试';
        if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); }
      } return false;
    } finally { if (generation === this.generation) { this.agentBusy = false; } }
  }
  exportScope(): string { return this.connected + '/' + this.directory + '/' + this.sessionID + '/' + this.generation; }
  cancelExport(): void {
    if (!this.exportJob) { return; } this.exportJob.cancel(); this.exportJob = undefined; this.exportEpoch++; this.exporting = false; this.exportError = '已取消导出';
  }
  async prepareExport(format: string, tools: boolean): Promise<ExportDocument | undefined> {
    if (!this.api || !this.sessionID || this.exporting) { return undefined; }
    const api = this.api; const generation = this.generation; const epoch = ++this.exportEpoch; const job = new TranscriptExporter(); this.exportJob = job;
    this.exporting = true; this.exportCount = 0; this.exportError = '';
    try {
      const document = await job.prepare(api, { id: this.sessionID, title: this.sessionTitle, format: format, tools: tools }, (count: number): void => {
        if (generation === this.generation && epoch === this.exportEpoch) { this.exportCount = count; }
      });
      return generation === this.generation && epoch === this.exportEpoch ? document : undefined;
    } catch (e) {
      if (generation === this.generation && epoch === this.exportEpoch && !(e instanceof ExportCancelled)) { this.exportError = (e as Error).message || '导出未完成，请重试'; if (e instanceof ApiError && [401, 403, 495].indexOf(e.code) >= 0) { this.fail(e as Error); } }
      return undefined;
    } finally { if (generation === this.generation && epoch === this.exportEpoch) { this.exporting = false; this.exportJob = undefined; } }
  }
  private async persistModelPreferences(next: ModelPreferences): Promise<boolean> {
    if (!this.connected || this.modelPreferencesBusy) { return false; }
    const server = this.connected; const epoch = ++this.modelPreferenceEpoch;
    this.modelPreferencesBusy = true; this.modelPreferencesError = '';
    try {
      await this.storage.saveModelPreferences(server, next);
      if (server !== this.connected || epoch !== this.modelPreferenceEpoch) { return false; }
      this.modelPreferences = next; return true;
    } catch (_) { if (server === this.connected && epoch === this.modelPreferenceEpoch) { this.modelPreferencesError = '模型偏好未保存，请重试'; } return false; }
    finally { if (server === this.connected && epoch === this.modelPreferenceEpoch) { this.modelPreferencesBusy = false; } }
  }
  async enableModel(id: string, enabled: boolean): Promise<boolean> {
    if (this.modelBusy || this.modelPreferencesBusy) { return false; }
    if ((this.modelPreferences.enabled.indexOf(id) >= 0) === enabled) { return true; }
    if (enabled && !this.models.some((model: ModelItem) => model.id === id && model.available !== false)) { return false; }
    return this.persistModelPreferences(setModelEnabled(this.modelPreferences, id, enabled));
  }
  async favoriteModel(id: string, favorite: boolean): Promise<boolean> {
    if (this.modelBusy || this.modelPreferencesBusy) { return false; }
    if ((this.modelPreferences.favorites.indexOf(id) >= 0) === favorite) { return true; }
    if (favorite && !this.models.some((model: ModelItem) => model.id === id && model.available !== false)) { return false; }
    return this.persistModelPreferences(setModelFavorite(this.modelPreferences, id, favorite));
  }
  async chooseModel(id: string, variant: string = ''): Promise<boolean> {
    if (!this.api || !this.sessionID || this.modelBusy || this.modelPreferencesBusy || this.agentBusy || this.agentUncertain || this.forkBusy || this.compactionBusy) { return false; }
    if (this.modelUncertain) { this.error = '模型设置结果待核对，请先同步再选择'; return false; }
    if (this.pendingSend) { this.error = '请先核对上一次发送结果，再切换模型或思考程度'; return false; }
    const model = enabledModels(this.models, this.modelPreferences).find((item: ModelItem) => item.id === id);
    if (!model) { this.error = '请先在模型与接入中启用这个模型'; return false; }
    if (variant && (model.variants || []).indexOf(variant) < 0) { this.error = '服务器没有提供这个思考档位，请刷新模型目录'; return false; }
    if (id === this.modelID && variant === this.modelVariant) { return true; }
    const slash = id.indexOf('/'); const generation = this.generation; const api = this.api;
    this.selectionEpoch++; this.error = ''; this.modelBusy = true; let submitted = false;
    try {
      const reference: ModelRef = { id: id.slice(slash + 1), providerID: id.slice(0, slash) };
      if (variant) { reference.variant = variant; }
      submitted = true;
      await api.request(this.sessionPath() + '/model', http.RequestMethod.POST, { model: reference } as ModelRequest);
      if (generation !== this.generation) { return false; }
      const detail = object(object(await api.request(this.sessionPath()))['data']); const confirmed = object(detail['model']);
      if (generation !== this.generation) { return false; }
      if (!confirmed['id']) { throw new Error('模型设置结果待核对，请同步后重试'); }
      this.selectionEpoch++; this.modelID = string(confirmed['providerID']) + '/' + string(confirmed['id']); this.modelVariant = string(confirmed['variant']); this.modelUncertain = false;
      if (this.modelID !== id || this.modelVariant !== variant) { this.error = '服务器未确认所选模型或思考程度，请同步后重试'; return false; }
      if (this.connected) {
        this.servers = this.servers.map((s: ServerConfig): ServerConfig => ({ id: s.id, name: s.name, url: s.url,
          username: s.username, allowHttp: s.allowHttp, useDedicatedTrust: s.useDedicatedTrust,
          preferredModel: s.id === this.connected ? id : s.preferredModel }));
        await this.storage.saveServers(this.servers);
      }
      if (generation !== this.generation) { return false; }
      await this.sync();
      if (generation !== this.generation || this.error) { return false; }
      if (this.modelID !== id || this.modelVariant !== variant) { this.error = '服务器未确认所选模型或思考程度，请同步后重试'; return false; }
      await this.persistModelPreferences(rememberModel(this.modelPreferences, id));
      return generation === this.generation;
    } catch (e) { if (generation === this.generation) {
      this.modelUncertain = submitted && !(e instanceof ApiError && [400, 401, 403, 404, 405, 422, 495].indexOf(e.code) >= 0);
      this.fail(e as Error); if (this.modelUncertain) { this.error = '模型设置结果待核对，请同步后再继续'; }
    } return false; }
    finally { if (generation === this.generation) { this.modelBusy = false; } }
  }
  async openSettings(): Promise<void> { this.pane = 'settings'; await this.providers.load(); }
  async refreshModels(): Promise<void> {
    if (!this.api) { return; } const generation = this.generation;
    const models = await this.api.models(this.directory);
    if (generation === this.generation) { this.models = models; this.queueSync(); }
  }
  updateField(id: string, key: string, value: string, multiple: boolean = false): void {
    this.interactions = this.interactions.map((p: Interaction) => {
      if (p.id !== id || p.state === 'submitting') { return p; }
      const fields = p.fields.map((f: FormField): FormField => {
        if (f.key !== key) { return f; }
        return updateFieldValue(f, value, multiple);
      });
      return { id: p.id, sessionID: p.sessionID, kind: p.kind, title: p.title, detail: p.detail, fields: fields, approval: p.approval, state: 'pending' };
    });
  }
  private interactionState(id: string, state: string): void {
    this.interactions = this.interactions.map((p: Interaction): Interaction => ({
      id: p.id, sessionID: p.sessionID, kind: p.kind, title: p.title, detail: p.detail, fields: p.fields, approval: p.approval, state: p.id === id ? state : p.state
    }));
  }
  currentFields(id: string): FormField[] { return this.interactions.find((p: Interaction) => p.id === id)?.fields || []; }
  itemState(id: string): string { return this.interactions.find((p: Interaction) => p.id === id)?.state || 'pending'; }
  fieldText(id: string, key: string): string { return this.currentFields(id).find((f: FormField) => f.key === key)?.text || ''; }
  selected(id: string, key: string, value: string): boolean { return (this.currentFields(id).find((f: FormField) => f.key === key)?.values || []).indexOf(value) >= 0; }
  async reply(request: Interaction, reject: boolean = false): Promise<void> {
    const item = this.interactions.find((p: Interaction) => p.id === request.id);
    if (!item || !this.api || item.state === 'submitting') { return; }
    if (item.kind === 'permission' && !reject && !this.canApprove(item.id)) { this.error = this.permissionError || '无法完整预览此操作，请在桌面核对后处理。'; return; }
    if (item.kind === 'permission' && !reject && interactionSnapshot(request) !== interactionSnapshot(item)) { this.error = '操作内容已更新，请重新核对当前预览。'; return; }
    let answer: Record<string, FieldValue> = {};
    if (item.kind === 'form' && !reject) { try { answer = buildFormAnswer(item.fields); } catch (e) { this.fail(e as Error); return; } }
    const generation = this.generation; const api = this.api; const id = this.sessionID; const directory = this.directory;
    const reviewed = interactionSnapshot(item); this.interactionState(item.id, 'submitting'); this.error = '';
    const base = '/api/session/' + encodeURIComponent(id) + (item.kind === 'form' ? '/form/' : '/permission/') + encodeURIComponent(item.id);
    const scope = directory ? '?' + api.scope(directory) : '';
    try {
      if (item.kind === 'permission' && !reject) {
        const epoch = ++this.permissionEpoch;
        const snapshot = await api.interactions(id, 'permission', directory);
        if (generation !== this.generation) { return; }
        if (epoch !== this.permissionEpoch) { this.interactionState(item.id, 'pending'); this.error = '审批状态已更新，请重新核对。'; return; }
        const current = snapshot.find((p: Interaction) => p.id === item.id);
        if (!current) { this.interactions = this.interactions.filter((p: Interaction) => p.id !== item.id); this.error = '该请求已处理，无需再次批准。'; return; }
        if (interactionSnapshot(current) !== reviewed || current.approval?.incomplete) {
          this.interactions = this.interactions.filter((p: Interaction) => p.kind !== 'permission').concat(snapshot);
          this.error = '操作内容已更新，请核对最新预览后再批准。'; return;
        }
        this.permissionError = '';
      }
      if (item.kind === 'form' && reject) { await api.request(base + scope, http.RequestMethod.DELETE); }
      else { await api.request(base + '/reply' + scope, http.RequestMethod.POST,
        item.kind === 'form' ? { answer: answer } as AnswerRequest : { decision: reject ? 'reject' : 'once' } as PermissionReply); }
      if (generation === this.generation) { this.interactions = this.interactions.filter((p: Interaction) => p.id !== item.id); this.stashConversation(); this.queueWorkspace(); await this.sync(); }
    } catch (e) {
      if (generation === this.generation) {
        this.fail(e as Error); this.interactionState(item.id, 'error');
        if (item.kind === 'permission') { this.permissionError = '审批结果未确认，请重新读取状态；不会自动重复批准。'; }
        await this.syncInteractions(api, id, item.kind, generation);
      }
    }
  }
  private clearTimeline(): void {
    this.timelineEpoch++; this.turnEpoch++; this.timelineEntries = []; this.turns = []; this.turnID = ''; this.turnDiffs = [];
    this.timelineBusy = false; this.timelineLoaded = false; this.timelineError = ''; this.timelineCursor = '';
    this.turnBusy = false; this.turnLoaded = false; this.turnError = '';
  }
  async loadTimeline(older: boolean = false): Promise<void> {
    if (!this.api || !this.sessionID || (older && (!this.timelineCursor || this.timelineBusy || this.timelineEntries.length >= 300))) { return; }
    const api = this.api; const generation = this.generation; const epoch = ++this.timelineEpoch; const id = this.sessionID;
    this.timelineBusy = true; this.timelineError = '';
    if (!older) { this.turnEpoch++; this.turnID = ''; this.turnDiffs = []; this.turnLoaded = false; this.turnBusy = false; this.turnError = ''; }
    try {
      const response = await api.messages(id, older ? this.timelineCursor : '');
      if (generation !== this.generation || epoch !== this.timelineEpoch) { return; }
      const entries = api.parseTimeline(response);
      const byID = new Map<string, TimelineEntry>();
      (older ? entries.concat(this.timelineEntries) : entries).forEach((entry: TimelineEntry) => { byID.set(entry.id, entry); });
      this.timelineEntries = Array.from(byID.values()).slice(-300);
      this.timelineCursor = string(object(object(response)['cursor'])['next']);
      this.turns = groupTurns(this.timelineEntries, !!this.timelineCursor); this.timelineLoaded = true;
      if (!older && this.turns.length && !this.turns[0].partial) { await this.selectTurn(this.turns[0]); }
    } catch (e) { if (generation === this.generation && epoch === this.timelineEpoch) { this.timelineError = (e as Error).message; } }
    finally { if (generation === this.generation && epoch === this.timelineEpoch) { this.timelineBusy = false; } }
  }
  canLoadTimeline(): boolean { return !!this.timelineCursor && this.timelineEntries.length < 300; }
  async selectTurn(turn: TurnItem): Promise<void> {
    if (!this.api || !this.sessionID || turn.partial) { return; }
    const api = this.api; const generation = this.generation; const epoch = ++this.turnEpoch;
    this.turnID = turn.id; this.turnDiffs = []; this.turnError = ''; this.turnBusy = true; this.turnLoaded = false;
    try {
      const diffs = await api.turnDiff(this.sessionID, this.directory, turn.id);
      if (generation === this.generation && epoch === this.turnEpoch) { this.turnDiffs = diffs; this.turnLoaded = true; }
    } catch (e) { if (generation === this.generation && epoch === this.turnEpoch) { this.turnError = (e as Error).message; } }
    finally { if (generation === this.generation && epoch === this.turnEpoch) { this.turnBusy = false; } }
  }
  async openReview(): Promise<void> {
    this.pane = 'review'; this.reviewLoaded = false; this.error = ''; const generation = this.generation;
    if (!this.api || !this.directory) { return; }
    try {
      const diffs = await this.api.diff(this.directory);
      const files = await this.api.files(this.directory, '');
      if (generation === this.generation) { this.diffs = diffs; this.files = files; this.fileContent = ''; this.filePath = ''; this.reviewLoaded = true; }
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
  async browse(file: FileItem): Promise<void> {
    if (!this.api) { return; }
    const generation = this.generation;
    try {
      if (file.directory) {
        const files = await this.api.files(this.directory, file.path);
        if (generation === this.generation) { this.files = files; this.filePath = file.path; this.fileContent = ''; }
      } else {
        const content = await this.api.readFile(this.directory, file.path);
        if (generation === this.generation) { const preview = previewText(content); this.fileContent = preview.text; this.filePath = file.path; this.fileTruncated = preview.truncated; }
      }
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
}
