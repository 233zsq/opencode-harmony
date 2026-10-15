import { common } from '@kit.AbilityKit';
import { http } from '@kit.NetworkKit';
import { Storage } from '../data/Storage';
import { Protocol, ApiError, object, string, rows, list, json, Json } from '../data/Protocol';
import { ServerConfig, ProjectItem, SessionItem, ModelItem, ChatMessage, Interaction, FormField, FileItem,
  DiffItem, SseFrame, mergeMessages, applyTextDelta, normalizeUrl, buildFormAnswer, updateFieldValue, FieldValue, mergeFormDraft } from '../domain/Core';

interface CreateRequest { title: string; location: LocationRequest; }
interface LocationRequest { directory: string; }
interface PromptRequest { id: string; text: string; delivery: string; resume: boolean; }
interface ModelRef { id: string; providerID: string; }
interface ModelRequest { model: ModelRef; }
interface AnswerRequest { answer: Record<string, FieldValue>; }
interface PermissionReply { decision: string; }
interface PendingSend { id: string; sessionID: string; text: string; }
@Observed
export class AppStore {
  pane: string = 'connections';
  servers: ServerConfig[] = [];
  connected: string = '';
  status: string = '未连接';
  version: string = '';
  error: string = '';
  busy: boolean = false;
  projects: ProjectItem[] = [];
  sessions: SessionItem[] = [];
  directory: string = '';
  sessionID: string = '';
  sessionTitle: string = '';
  models: ModelItem[] = [];
  modelID: string = '';
  messages: ChatMessage[] = [];
  interactions: Interaction[] = [];
  files: FileItem[] = [];
  diffs: DiffItem[] = [];
  filePath: string = '';
  fileContent: string = '';
  cursor: string = '';
  private tailLoaded: boolean = false;
  reviewLoaded: boolean = false;
  working: boolean = false;
  showReasoning: boolean = true;
  draft: string = '';
  manualPath: string = '';
  serverName: string = '';
  serverUrl: string = 'https://';
  serverUser: string = 'opencode';
  serverPassword: string = '';
  allowHttp: boolean = false;
  useDedicatedTrust: boolean = false;
  reviewTab: string = 'diff';
  pendingSend: PendingSend | undefined = undefined;
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
    try { await this.storage.init(context); this.servers = await this.storage.servers(); this.initialized = true; }
    catch (e) { this.fail(e as Error); }
  }
  private fail(error: Error): void { this.error = error.message || '操作失败，请重新连接'; }
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
    if (id === this.connected) { this.disconnect(); }
    try {
      await this.storage.saveSecret(id, '');
      this.servers = this.servers.filter((s: ServerConfig) => s.id !== id);
      await this.storage.saveServers(this.servers);
    } catch (e) { this.fail(e as Error); }
  }
  disconnect(): void {
    this.generation++; this.stopNetwork(); this.api = undefined; this.connected = ''; this.status = '未连接';
    this.projects = []; this.sessions = []; this.models = []; this.messages = []; this.interactions = [];
    this.diffs = []; this.files = []; this.fileContent = ''; this.filePath = ''; this.directory = '';
    this.sessionID = ''; this.sessionTitle = ''; this.cursor = ''; this.tailLoaded = false; this.working = false;
    this.pendingSend = undefined; this.draft = ''; this.eventIDs = []; this.syncing = false; this.syncAgain = false; this.busy = false;
  }
  async connect(config: ServerConfig): Promise<void> {
    this.disconnect(); const generation = this.generation; this.error = ''; this.status = '正在连接'; this.busy = true;
    try {
      const password = await this.storage.secret(config.id);
      if (generation !== this.generation) { return; }
      const api = new Protocol(config, password);
      const info = object(await api.request('/api/info'));
      const version = string(info['version']);
      if (!version.startsWith('2.')) { throw new ApiError(0, '此版本仅支持 OpenCode V2。服务器版本：' + (version || '未知')); }
      const projects = await api.projects();
      if (generation !== this.generation) { return; }
      this.api = api; this.connected = config.id; this.version = version; this.projects = projects;
      this.status = '已连接'; this.pane = 'projects'; this.attempts = 0; this.openStream();
      this.pollTimer = setInterval(() => {
        if (this.active) {
          this.sync().catch((e: Error) => this.fail(e));
          if (Date.now() - this.lastData > 45000) { this.streamClose?.(); this.openStream(); }
        }
      }, 5000);
      const last = await this.storage.last(config.id);
      if (generation !== this.generation) { return; }
      if (last.length > 0 && last[0]) {
        await this.selectProject(last[0]);
        if (last[1] && this.sessions.some((s: SessionItem) => s.id === last[1])) {
          await this.openSession(this.sessions.find((s: SessionItem) => s.id === last[1]) as SessionItem);
        }
      }
    } catch (e) { if (generation === this.generation) { this.status = '连接失败'; this.fail(e as Error); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  private stopNetwork(): void {
    this.streamClose?.(); this.streamClose = undefined;
    if (this.pollTimer >= 0) { clearInterval(this.pollTimer); this.pollTimer = -1; }
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
    if (this.refreshTimer >= 0) { clearTimeout(this.refreshTimer); this.refreshTimer = -1; }
  }
  setActive(active: boolean): void {
    this.active = active;
    if (!active) {
      this.streamClose?.(); this.streamClose = undefined;
      if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
      this.status = this.api ? '后台暂停连接' : '未连接';
    } else if (this.api) { this.openStream(); this.queueSync(); }
  }
  private openStream(): void {
    if (!this.api || !this.active || this.status === '认证失败' || this.status === '证书校验失败') { return; }
    if (this.retryTimer >= 0) { clearTimeout(this.retryTimer); this.retryTimer = -1; }
    this.streamClose?.(); const generation = this.generation; this.lastData = Date.now();
    this.streamClose = this.api.stream((frame: SseFrame) => {
      if (generation === this.generation && this.active) { this.onFrame(frame); }
    }, () => { if (generation === this.generation) { this.lastData = Date.now(); } }, (error: Error) => {
      if (generation !== this.generation || !this.active) { return; }
      if (error instanceof ApiError && (error.code === 401 || error.code === 403 || error.code === 495)) {
        this.status = error.code === 495 ? '证书校验失败' : '认证失败'; this.error = error.message; this.stopNetwork(); return;
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
    if (location && location !== this.directory) { return; }
    const data = object(event['data']); const sessionID = string(data['sessionID'], string(object(data['form'])['sessionID']));
    if (!sessionID || sessionID !== this.sessionID) { return; }
    this.eventEpoch++;
    if (/^session\.(text|reasoning)\.(delta|ended)$/.test(type)) {
      const partType = type.indexOf('.reasoning.') >= 0 ? 'reasoning' : 'text';
      const ended = type.endsWith('.ended'); const ordinal = Number(data['ordinal'] || 0);
      this.messages = applyTextDelta(this.messages, string(data['assistantMessageID']), ordinal, partType,
        string(data[ended ? 'text' : 'delta']), ended);
      this.working = true;
      if (ended) { this.queueSync(); }
    } else {
      if (type === 'session.idle') { this.working = false; }
      if (type.indexOf('retry') >= 0) { this.working = true; }
      this.queueSync();
    }
  }
  private queueSync(): void {
    if (this.refreshTimer >= 0) { return; }
    this.refreshTimer = setTimeout(() => { this.refreshTimer = -1; this.sync().catch((e: Error) => this.fail(e)); }, 200);
  }
  async selectProject(directory: string): Promise<void> {
    if (!this.api || !directory.trim()) { return; }
    this.generation++; this.streamClose?.(); const generation = this.generation; const api = this.api;
    this.pendingSend = undefined; this.draft = ''; this.directory = directory.trim(); this.sessionID = ''; this.messages = []; this.interactions = []; this.diffs = [];
    this.fileContent = ''; this.filePath = ''; this.cursor = ''; this.error = ''; this.busy = true; this.syncing = false;
    try {
      await api.request('/api/location?' + api.scope(this.directory));
      const sessions = await api.sessions(this.directory);
      const models = await api.models(this.directory);
      if (generation !== this.generation) { return; }
      this.sessions = sessions; this.models = models; this.manualPath = this.directory; this.pane = 'projects';
      this.savePosition(); this.openStream();
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); this.openStream(); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  async createSession(): Promise<void> {
    if (!this.api || !this.directory || this.busy) { return; }
    const generation = this.generation; this.busy = true;
    try {
      const result = object(await this.api.request('/api/session', http.RequestMethod.POST,
        { title: '新的开发会话', location: { directory: this.directory } } as CreateRequest));
      if (generation !== this.generation) { return; }
      const s = object(result['data']);
      await this.openSession({ id: string(s['id']), title: string(s['title'], '新的开发会话'),
        directory: this.directory, model: '', status: 'idle' });
    } catch (e) { this.fail(e as Error); } finally { this.busy = false; }
  }
  async openSession(session: SessionItem): Promise<void> {
    if (!this.api) { return; }
    this.generation++; this.streamClose?.(); this.syncing = false; this.syncAgain = false;
    this.sessionID = session.id; this.sessionTitle = session.title; this.modelID = session.model;
    this.messages = []; this.interactions = []; this.diffs = []; this.cursor = ''; this.tailLoaded = false; this.pendingSend = undefined;
    this.draft = ''; this.working = false; this.pane = 'chat'; this.error = ''; this.savePosition(); this.openStream(); await this.sync();
  }
  async sync(): Promise<void> {
    if (!this.api || !this.sessionID || !this.active) { return; }
    if (this.syncing) { this.syncAgain = true; return; }
    this.syncing = true; const generation = this.generation; const api = this.api;
    const id = this.sessionID; const epoch = this.eventEpoch;
    try {
      const response = await api.messages(id);
      if (generation !== this.generation) { return; }
      const incoming = api.parseMessages(response);
      const safe = incoming.map((m: ChatMessage): ChatMessage => {
        const current = this.messages.find((old: ChatMessage) => old.id === m.id);
        if (current && m.state !== 'completed' &&
          (epoch !== this.eventEpoch || current.text.length > m.text.length || current.reasoning.length > m.reasoning.length)) {
          return { id: m.id, role: m.role, text: current.text, reasoning: current.reasoning,
            parts: current.parts, tools: m.tools, state: current.state };
        }
        return m;
      });
      this.messages = mergeMessages(this.messages, safe);
      if (!this.tailLoaded) { this.cursor = string(object(object(response)['cursor'])['next']); this.tailLoaded = true; }
      if (this.pendingSend && incoming.some((m: ChatMessage) => m.id === this.pendingSend?.id)) { this.pendingSend = undefined; this.draft = ''; }
      await this.syncInteractions(api, id, 'form', generation);
      await this.syncInteractions(api, id, 'permission', generation);
      const active = object(object(await api.request('/api/session/active'))['data']);
      const detail = object(object(await api.request('/api/session/' + encodeURIComponent(id)))['data']);
      const inbox = rows(await api.request('/api/session/' + encodeURIComponent(id) + '/inbox'));
      if (generation === this.generation) {
        if (active[id] !== undefined || inbox.length > 0) { this.working = true; }
        else if (detail['outcome']) { this.working = false; }
        const model = object(detail['model']);
        if (model['id']) { this.modelID = string(model['providerID']) + '/' + string(model['id']); }
      }
    } catch (e) {
      if (generation === this.generation) {
        this.fail(e as Error);
        if (e instanceof ApiError && ((e as ApiError).code === 401 || (e as ApiError).code === 403 || (e as ApiError).code === 495)) {
          this.status = (e as ApiError).code === 495 ? '证书校验失败' : '认证失败'; this.stopNetwork();
        }
      }
    } finally {
      if (generation === this.generation) {
        this.syncing = false; if (this.syncAgain) { this.syncAgain = false; this.queueSync(); }
      }
    }
  }
  private async syncInteractions(api: Protocol, id: string, kind: string, generation: number): Promise<void> {
    try {
      const incoming = await api.interactions(id, kind);
      if (generation !== this.generation) { return; }
      const next = incoming.map((item: Interaction) => {
        const old = this.interactions.find((p: Interaction) => p.id === item.id);
        return old ? { id: old.id, sessionID: old.sessionID, kind: old.kind, title: old.title, detail: old.detail,
          fields: mergeFormDraft(item.fields, old.fields), state: old.state === 'submitting' ? 'submitting' : 'pending' } as Interaction : item;
      });
      this.interactions = this.interactions.filter((p: Interaction) => p.kind !== kind).concat(next);
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
  async older(): Promise<void> {
    if (!this.api || !this.cursor || this.busy) { return; }
    const generation = this.generation; this.busy = true;
    try {
      const result = await this.api.messages(this.sessionID, this.cursor);
      if (generation !== this.generation) { return; }
      this.messages = mergeMessages(this.messages, this.api.parseMessages(result), true);
      this.cursor = string(object(object(result)['cursor'])['next']);
    } catch (e) { this.fail(e as Error); } finally { if (generation === this.generation) { this.busy = false; } }
  }
  async send(): Promise<void> {
    if (!this.api || !this.sessionID || this.busy || (!this.draft.trim() && !this.pendingSend)) { return; }
    const pending: PendingSend = this.pendingSend || {
      id: 'msg_' + Date.now().toString(36) + Math.random().toString(36).slice(2),
      sessionID: this.sessionID, text: this.draft.trim()
    };
    this.pendingSend = pending; const generation = this.generation; this.busy = true; this.error = '';
    try {
      await this.api.request(this.sessionPath() + '/prompt', http.RequestMethod.POST,
        { id: pending.id, text: pending.text, delivery: 'steer', resume: true } as PromptRequest);
      if (generation !== this.generation) { return; }
      this.pendingSend = undefined; this.draft = ''; this.working = true; await this.sync();
    } catch (e) {
      if (generation === this.generation) { this.fail(e as Error); this.error += '。发送结果待核对，重试将使用同一消息 ID'; }
    } finally { if (generation === this.generation) { this.busy = false; } }
  }
  async interrupt(): Promise<void> {
    if (!this.api) { return; }
    const generation = this.generation;
    try { await this.api.request(this.sessionPath() + '/interrupt', http.RequestMethod.POST); if (generation === this.generation) { await this.sync(); } }
    catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
  async chooseModel(id: string): Promise<void> {
    if (!this.api || !this.sessionID) { return; }
    const slash = id.indexOf('/'); const generation = this.generation;
    try {
      await this.api.request(this.sessionPath() + '/model', http.RequestMethod.POST,
        { model: { id: id.slice(slash + 1), providerID: id.slice(0, slash) } } as ModelRequest);
      if (generation === this.generation) { this.modelID = id; await this.sync(); }
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
  updateField(id: string, key: string, value: string, multiple: boolean = false): void {
    this.interactions = this.interactions.map((p: Interaction) => {
      if (p.id !== id || p.state === 'submitting') { return p; }
      const fields = p.fields.map((f: FormField): FormField => {
        if (f.key !== key) { return f; }
        return updateFieldValue(f, value, multiple);
      });
      return { id: p.id, sessionID: p.sessionID, kind: p.kind, title: p.title, detail: p.detail, fields: fields, state: 'pending' };
    });
  }
  private interactionState(id: string, state: string): void {
    this.interactions = this.interactions.map((p: Interaction): Interaction => ({
      id: p.id, sessionID: p.sessionID, kind: p.kind, title: p.title, detail: p.detail, fields: p.fields, state: p.id === id ? state : p.state
    }));
  }
  currentFields(id: string): FormField[] { return this.interactions.find((p: Interaction) => p.id === id)?.fields || []; }
  itemState(id: string): string { return this.interactions.find((p: Interaction) => p.id === id)?.state || 'pending'; }
  fieldText(id: string, key: string): string { return this.currentFields(id).find((f: FormField) => f.key === key)?.text || ''; }
  selected(id: string, key: string, value: string): boolean { return (this.currentFields(id).find((f: FormField) => f.key === key)?.values || []).indexOf(value) >= 0; }
  async reply(request: Interaction, reject: boolean = false): Promise<void> {
    const item = this.interactions.find((p: Interaction) => p.id === request.id);
    if (!item) { return; }
    if (!this.api || item.state === 'submitting') { return; }
    let answer: Record<string, FieldValue> = {};
    if (item.kind === 'form' && !reject) { try { answer = buildFormAnswer(item.fields); } catch (e) { this.fail(e as Error); return; } }
    const generation = this.generation; this.interactionState(item.id, 'submitting'); this.error = '';
    const base = this.sessionPath() + (item.kind === 'form' ? '/form/' : '/permission/') + encodeURIComponent(item.id);
    try {
      if (item.kind === 'form' && reject) { await this.api.request(base, http.RequestMethod.DELETE); }
      else { await this.api.request(base + '/reply', http.RequestMethod.POST,
        item.kind === 'form' ? { answer: answer } as AnswerRequest : { decision: reject ? 'reject' : 'once' } as PermissionReply); }
      if (generation === this.generation) {
        this.interactions = this.interactions.filter((p: Interaction) => p.id !== item.id); await this.sync();
      }
    } catch (e) {
      if (generation === this.generation) {
        this.fail(e as Error); this.interactionState(item.id, 'error');
        await this.syncInteractions(this.api, this.sessionID, item.kind, generation);
      }
    }
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
        if (generation === this.generation) { this.fileContent = content.slice(0, 100000); this.filePath = file.path; }
      }
    } catch (e) { if (generation === this.generation) { this.fail(e as Error); } }
  }
}
