import { AgentItem } from '../domain/Agents';
import { TranscriptExporter, ExportDocument, ExportCancelled } from '../domain/TranscriptExport';
import { Attachment, PromptFile, attachmentProblem, promptFiles, ATTACHMENT_LIMIT, attachmentBytes } from '../domain/Attachments';
import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { Storage } from '../data/Storage';
import { ProviderStore } from './ProviderStore';
import { Protocol, ApiError, object, string, rows, list, json, Json } from '../data/Protocol';
import { ServerConfig, ProjectItem, SessionItem, ModelItem, ChatMessage, Interaction, FormField, FileItem,
  DiffItem, TurnItem, TimelineEntry, PendingItem, PendingPrompt, QuestionDraft, SessionPreference, ConversationMemory, filterSessions, sessionStatus, pendingKey, groupTurns, boundMessageAttachments, SseFrame, mergeMessages, applyTextDelta, normalizeUrl, buildFormAnswer, updateFieldValue, FieldValue, mergeFormDraft, previewText, interactionSnapshot } from '../domain/Core';

interface CreateRequest { title: string; location: LocationRequest; }
interface LocationRequest { directory: string; }
interface PromptRequest { id: string; text: string; delivery: string; resume: boolean; files?: PromptFile[]; }
interface ModelRef { id: string; providerID: string; }
interface ModelRequest { model: ModelRef; }
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
  serverName: string = '';
  serverUrl: string = 'https://';
  serverUser: string = 'opencode';
  serverPassword: string = '';
  allowHttp: boolean = false;
  useDedicatedTrust: boolean = false;
  reviewTab: string = 'diff';
  pendingSend: PendingPrompt | undefined = undefined;
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

  async init(context: common.Context): Promise<void> {
    if (this.initialized) { return; }
    try { await this.storage.init(context); this.servers = await this.storage.servers(); this.initialized = true;
      const last = await this.storage.activeServer();
      const server = this.servers.find((s: ServerConfig) => s.id === last);
      if (server) { await this.connect(server); } }
    catch (e) { this.fail(e as Error); }
  }
  private fail(error: Error): void {
    this.error = error.message || '操作失败，请重新连接';
    if (error instanceof ApiError && [401, 403, 495].indexOf(error.code) >= 0) {
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
  sessionRows(search: string = ''): SessionItem[] {
    const sessions = this.sessions.slice();
    this.sessionPreferences.forEach((p: SessionPreference) => {
      if (p.directory === this.directory && p.title && !sessions.some((s: SessionItem) => s.id === p.id)) {
        sessions.push({ id: p.id, title: p.title, directory: p.directory, status: 'idle', model: '' });
      }
    });
    return filterSessions(sessions, this.sessionPreferences, search || this.sessionQuery, this.showArchived);
  }
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
      this.sessions = this.sessions.map((s: SessionItem): SessionItem => s.id === id ? { id: s.id, title: value, directory: s.directory, status: s.status, model: s.model, updated: s.updated, archived: s.archived } : s);
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
  async reconnect(): Promise<void> {
    const server = this.servers.find((s: ServerConfig) => s.id === this.connected);
    if (server && !this.busy) { await this.connect(server); }
  }
  private sessionPath(): string { return '/api/session/' + encodeURIComponent(this.sessionID); }
  private savePosition(): void {
    if (this.connected) { this.storage.position(this.connected, this.directory, this.sessionID).catch((e: Error) => this.fail(e)); }
  }
  async addServer(): Promise<void> {
    this.error = '';
    try {
      const url = normalizeUrl(this.serverUrl, this.allowHttp);
      if (this.useDedicatedTrust && !url.startsWith('https://')) { throw new Error('专用证书连接必须使用 HTTPS'); }
      const id = 'srv_' + Date.now().toString(36);
      const config: ServerConfig = { id: id, name: this.serverName.trim() || 'OpenCode', url: url,
        username: this.serverUser.trim() || 'opencode', allowHttp: this.allowHttp, useDedicatedTrust: this.useDedicatedTrust };
      await this.storage.saveSecret(id, this.serverPassword);
      const servers = this.servers.concat([config]);
      await this.storage.saveServers(servers); this.servers = servers; this.serverPassword = '';
      await this.connect(config);
    } catch (e) { this.fail(e as Error); }
  }
  async removeServer(id: string): Promise<void> {
    if (id === this.connected && !this.disconnect()) { return; }
    try {
      await this.storage.saveSecret(id, '');
      this.servers = this.servers.filter((s: ServerConfig) => s.id !== id);
      await this.storage.saveServers(this.servers); this.conversationMemory.clearServer(id);
    } catch (e) { this.fail(e as Error); }
  }
  disconnect(): boolean {
    if (!this.stashConversation()) { return false; }
    this.pendingEpoch++; this.sessionsEpoch++; this.preferenceEpoch++; this.pendingItems = []; this.pendingError = ''; this.pendingUpdated = 0; this.pendingBusy = false;
    this.sessionCursor = ''; this.sessionQuery = ''; this.sessionsBusy = false; this.sessionsError = ''; this.sessionPreferences = [];
    this.sessionMutationBusy = false; this.sessionPreferenceBusy = false; this.runningSessions = []; this.runningUnknown = false; this.showArchived = false;
    this.cancelExport(); this.agentEpoch++; this.agents = []; this.agentID = ''; this.agentError = ''; this.agentBusy = false; this.agentLoading = false; this.agentUncertain = false;
    this.providers.attach(undefined, '', async (): Promise<void> => {});
    this.clearTimeline(); this.generation++; this.transcriptEpoch++; this.readingHistory = false; this.newerAvailable = false; this.networkBlocked = false; this.stopNetwork(); this.api = undefined; this.connected = ''; this.status = '未连接';
    this.projects = []; this.sessions = []; this.models = []; this.messages = []; this.interactions = []; this.permissionError = ''; this.permissionEpoch++;
    this.diffs = []; this.files = []; this.fileContent = ''; this.filePath = ''; this.directory = '';
    this.sessionID = ''; this.sessionTitle = ''; this.cursor = ''; this.tailLoaded = false; this.working = false; this.interrupting = false;
    this.pendingSend = undefined; this.draft = ''; this.attachments = []; this.modelID = ''; this.eventIDs = []; this.syncing = false; this.syncAgain = false; this.busy = false; return true;
  }
  async connect(config: ServerConfig): Promise<void> {
    if (!this.disconnect()) { return; } const generation = this.generation; this.error = ''; this.status = '正在连接'; this.busy = true;
    try {
      const password = await this.storage.secret(config.id);
      if (generation !== this.generation) { return; }
      const api = new Protocol(config, password);
      const info = object(await api.request('/api/info'));
      const version = string(info['version']);
      if (!version.startsWith('2.')) { throw new ApiError(0, '此版本仅支持 OpenCode V2。服务器版本：' + (version || '未知')); }
      const projects = await api.projects();
      const flags = await this.storage.sessionPreferences(config.id);
      if (generation !== this.generation) { return; }
      this.api = api; this.providers.attach(api, '', async (): Promise<void> => { await this.refreshModels(); }); this.connected = config.id; this.version = version; this.projects = projects; this.sessionPreferences = flags;
      this.storage.rememberServer(config.id).catch((e: Error) => this.fail(e));
      this.status = '已连接'; this.pane = 'chat'; this.attempts = 0; this.openStream();
      this.pollTimer = setInterval(() => {
        if (this.active) {
          this.sync().catch((e: Error) => this.fail(e));
          if (Date.now() - this.pendingUpdated > 15000) { this.refreshPending(); }
          if (Date.now() - this.lastData > 45000) { this.streamClose?.(); this.openStream(); }
        }
      }, 5000);
      this.queueWorkspace();
      const last = await this.storage.last(config.id);
      if (generation !== this.generation) { return; }
      if (last.length > 0 && last[0]) {
        await this.selectProject(last[0]);
        if (api !== this.api || this.sessionsError) { return; }
        if (last[1]) {
          const session = this.sessions.find((s: SessionItem) => s.id === last[1]) || await api.session(last[1]);
          if (api === this.api && session.directory === this.directory) { await this.openSession(session); }
        }
      }
    } catch (e) { if (generation === this.generation) { this.status = '连接失败'; this.fail(e as Error); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  private stopNetwork(): void {
    this.streamEpoch++;
    if (this.workspaceTimer >= 0) { clearTimeout(this.workspaceTimer); this.workspaceTimer = -1; }
    this.streamClose?.(); this.streamClose = undefined;
    if (this.pollTimer >= 0) { clearInterval(this.pollTimer); this.pollTimer = -1; }
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
    if (this.refreshTimer >= 0) { clearTimeout(this.refreshTimer); this.refreshTimer = -1; }
  }
  setActive(active: boolean): void {
    this.active = active; this.providers.setActive(active);
    if (!active) {
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
    this.streamClose?.(); const streamEpoch = ++this.streamEpoch; const generation = this.generation; this.lastData = Date.now();
    this.streamClose = this.api.stream((frame: SseFrame) => {
      if (generation === this.generation && streamEpoch === this.streamEpoch && this.active) { this.onFrame(frame); }
    }, () => { if (generation === this.generation && streamEpoch === this.streamEpoch) { this.lastData = Date.now(); } }, (error: Error) => {
      if (generation !== this.generation || streamEpoch !== this.streamEpoch || !this.active) { return; }
      if (error instanceof ApiError && (error.code === 401 || error.code === 403 || error.code === 495)) {
        this.networkBlocked = true; this.status = error.code === 495 ? '证书校验失败' : '认证失败'; this.error = error.message; this.stopNetwork(); return;
      }
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
    if (type === 'server.connected') { this.status = '实时连接'; this.attempts = 0; this.queueSync(); return; }
    const location = string(object(event['location'])['directory']);
    const data = object(event['data']); const sessionID = string(data['sessionID'], string(object(data['form'])['sessionID']));
    if (sessionID && type === 'session.idle') { this.runningSessions = this.runningSessions.filter((id: string) => id !== sessionID); }
    else if (sessionID && /^session\.(text|reasoning)\./.test(type) && this.runningSessions.indexOf(sessionID) < 0) { this.runningSessions = this.runningSessions.concat([sessionID]); }
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
      this.working = true;
      if (ended) { this.queueSync(); }
    } else {
      if (type === 'session.idle') { this.working = false; }
      if (type.indexOf('retry') >= 0) { this.working = true; }
      this.queueSync();
    }
  }
  private queueSync(): void {
    if (!this.api || !this.active || this.networkBlocked) { return; }
    if (this.refreshTimer >= 0) { return; }
    this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; this.sync().catch((e: Error) => this.fail(e)); }, 200);
  }
  async selectProject(directory: string): Promise<void> {
    if (!this.api || !directory.trim()) { return; }
    if (!this.stashConversation()) { return; }
    this.sessionsEpoch++; this.sessionCursor = ''; this.sessionQuery = ''; this.sessionsBusy = false; this.sessionsError = ''; this.showArchived = false;
    this.clearTimeline(); this.generation++; this.streamClose?.(); const generation = this.generation; const api = this.api;
    this.cancelExport(); this.agentEpoch++; this.agents = []; this.agentID = ''; this.agentError = ''; this.agentBusy = false; this.agentLoading = false; this.agentUncertain = false;
    this.providers.attach(api, directory.trim(), async (): Promise<void> => { await this.refreshModels(); });
    this.pendingSend = undefined; this.draft = ''; this.attachments = []; this.directory = directory.trim(); this.sessionID = ''; this.sessions = []; this.models = []; this.messages = []; this.interactions = []; this.permissionError = ''; this.permissionEpoch++; this.diffs = [];
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
    this.sessionID = session.id; this.sessionTitle = session.title; this.modelID = session.model;
    this.messages = []; this.interactions = []; this.permissionError = ''; this.permissionEpoch++; this.diffs = []; this.cursor = ''; this.tailLoaded = false; this.pendingSend = undefined;
    const saved = this.conversationMemory.read(this.connected, this.directory, session.id);
    this.draft = saved.text; this.attachments = saved.files || []; this.pendingSend = saved.pending; this.working = false; this.interrupting = false; this.pane = 'chat'; this.error = ''; this.savePosition(); this.openStream(); this.queueWorkspace();
    const generation = this.generation; this.busy = true; await this.sync(); if (generation === this.generation) { this.busy = false; }
  }
  async sync(): Promise<void> {
    if (!this.api || !this.sessionID || !this.active || this.networkBlocked) { return; }
    if (this.syncing) { this.syncAgain = true; return; }
    this.syncing = true; const generation = this.generation; const api = this.api;
    const id = this.sessionID; const epoch = this.eventEpoch; const transcript = this.transcriptEpoch; const selection = this.selectionEpoch;
    try {
      const response = await api.messages(id);
      if (generation !== this.generation || transcript !== this.transcriptEpoch) { return; }
      const incoming = api.parseMessages(response);
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
      await this.syncInteractions(api, id, 'form', generation);
      await this.syncInteractions(api, id, 'permission', generation);
      const active = object(object(await api.request('/api/session/active'))['data']);
      const detail = object(object(await api.request('/api/session/' + encodeURIComponent(id)))['data']);
      const inbox = rows(await api.request('/api/session/' + encodeURIComponent(id) + '/inbox'));
      if (generation === this.generation) {
        this.runningSessions = Object.keys(active);
        const title = string(detail['title'], this.sessionTitle);
        if (title !== this.sessionTitle) {
          this.sessionTitle = title;
          this.sessions = this.sessions.map((item: SessionItem): SessionItem => ({ id: item.id, title: item.id === id ? title : item.title, directory: item.directory, status: item.status, model: item.model, updated: item.updated, archived: item.archived }));
        }
        if (active[id] !== undefined || inbox.length > 0) { this.working = true; }
        else if (detail['outcome']) { this.working = false; }
        const model = object(detail['model']);
        if (selection === this.selectionEpoch) {
          this.agentID = string(detail['agent']);
          if (model['id']) { this.modelID = string(model['providerID']) + '/' + string(model['id']); }
          else { this.modelID = this.agents.find((a: AgentItem) => a.id === this.agentID)?.model || ''; }
        }
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
  private async syncInteractions(api: Protocol, id: string, kind: string, generation: number): Promise<void> {
    const epoch = kind === 'permission' ? ++this.permissionEpoch : 0;
    try {
      const incoming = await api.interactions(id, kind, this.directory);
      if (generation !== this.generation || (kind === 'permission' && epoch !== this.permissionEpoch)) { return; }
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
    } catch (e) {
      if (generation === this.generation && (kind !== 'permission' || epoch === this.permissionEpoch)) {
        if (kind === 'permission') { this.permissionError = '审批列表读取失败，已保留上次结果。请重新读取后再批准；仍可拒绝已显示的请求。'; }
        else { this.fail(e as Error); }
      }
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
    this.messages = []; this.cursor = ''; this.tailLoaded = false; this.syncAgain = true;
    await this.sync();
  }
  async attachmentPreview(item: Attachment): Promise<Attachment> {
    if (item.data || !this.api) { return item; }
    const message = this.messages.find((m: ChatMessage) => m.files?.some((f: Attachment) => f.id === item.id));
    if (!message) { return item; }
    const generation = this.generation;
    try {
      const result = await this.api.request(this.sessionPath() + '/message/' + encodeURIComponent(message.id));
      if (generation !== this.generation) { return item; }
      const envelope: Json = {}; const entries: Object[] = [object(result)['data']]; envelope['data'] = entries;
      return this.api.parseMessages(envelope)[0]?.files?.find((f: Attachment) => f.id === item.id) || item;
    } catch (_) { return { id: item.id, name: item.name, mime: item.mime, size: item.size, data: '', error: '读取失败，请关闭后重试' }; }
  }
  async send(): Promise<void> {
    if (!this.api || !this.sessionID || this.busy || this.agentBusy || this.agentUncertain || (!this.draft.trim() && !this.attachments.length && !this.pendingSend)) { return; }
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
    this.selectionEpoch++; this.agentID = session.agent || ''; this.modelID = session.model || this.agents.find((a: AgentItem) => a.id === this.agentID)?.model || ''; this.agentUncertain = false;
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
    if (!this.api || !this.sessionID || this.busy || this.agentBusy || this.agentLoading || this.agentUncertain) { return false; }
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
  async chooseModel(id: string): Promise<void> {
    if (!this.api || !this.sessionID || this.agentBusy || this.agentUncertain) { return; }
    const slash = id.indexOf('/'); const generation = this.generation; this.selectionEpoch++; this.error = '';
    try {
      await this.api.request(this.sessionPath() + '/model', http.RequestMethod.POST,
        { model: { id: id.slice(slash + 1), providerID: id.slice(0, slash) } } as ModelRequest);
      if (generation === this.generation) {
        this.selectionEpoch++; this.modelID = id;
        if (this.connected) {
          this.servers = this.servers.map((s: ServerConfig): ServerConfig => ({ id: s.id, name: s.name, url: s.url,
            username: s.username, allowHttp: s.allowHttp, useDedicatedTrust: s.useDedicatedTrust,
            preferredModel: s.id === this.connected ? id : s.preferredModel }));
          await this.storage.saveServers(this.servers);
        }
        await this.sync();
      }
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
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
