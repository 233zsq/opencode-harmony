import { http } from '@kit.NetworkKit';
import { Protocol, ApiError, object, list, string, rows, parseFields, Json } from '../data/Protocol';
import { ModelItem, FormField, FieldValue, buildFormAnswer, updateFieldValue } from '../domain/Core';

export interface Account { id: string; label: string; type: string; method: string; active: boolean; }
export interface AuthMethod { id: string; type: string; label: string; fields: FormField[]; supported: boolean; }
export interface Integration { id: string; name: string; methods: AuthMethod[]; accounts: Account[]; }
export interface CustomProvider { id: string; name: string; baseURL: string; models: string[]; hasKey: boolean; }
interface KeyRequest { key: string; answer: Record<string, FieldValue>; label: string; }
interface MethodRequest { methodID: string; answer: Record<string, FieldValue>; label: string; }
interface CodeRequest { code: string; }
interface CustomRequest { id: string; name: string; baseURL: string; models: string[]; apiKey?: string; }
interface RenameRequest { label: string; }

@Observed
export class ProviderStore {
  section: string = 'native';
  catalog: ModelItem[] = [];
  catalogError: string = '';
  modelSearch: string = '';
  editingID: string = '';
  entries: Integration[] = [];
  custom: CustomProvider[] = [];
  customAvailable: boolean = false;
  busy: boolean = false;
  error: string = '';
  notice: string = '';
  search: string = '';
  selected: string = '';
  methodID: string = '';
  methodType: string = '';
  fields: FormField[] = [];
  key: string = '';
  label: string = '';
  attemptID: string = '';
  authURL: string = '';
  instructions: string = '';
  authMode: string = '';
  authStatus: string = '';
  code: string = '';
  customID: string = '';
  customName: string = '';
  customURL: string = '';
  customModels: string = '';
  customKey: string = '';
  private api: Protocol | undefined = undefined;
  private directory: string = '';
  private generation: number = 0;
  private timer: number = -1;
  private changed: () => Promise<void> = async (): Promise<void> => {};
  private active: boolean = true;

  attach(api: Protocol | undefined, directory: string, changed: () => Promise<void>): void {
    this.cancelSilently(); this.generation++; this.api = api; this.directory = directory; this.changed = changed;
    this.catalog = []; this.catalogError = ''; this.modelSearch = ''; this.newCustom(); this.search = ''; this.section = 'native';
    this.entries = []; this.custom = []; this.selected = ''; this.methodID = ''; this.methodType = ''; this.fields = []; this.key = ''; this.customKey = '';
    this.error = ''; this.notice = ''; this.customAvailable = false; this.busy = false;
  }
  setActive(active: boolean): void {
    this.active = active; this.stopTimer();
    if (active && this.attemptID && this.authStatus === 'pending') { this.poll().catch(() => {}); }
  }
  private stopTimer(): void { if (this.timer >= 0) { clearTimeout(this.timer); this.timer = -1; } }
  private path(suffix: string): string { return '/api/integration/' + encodeURIComponent(this.selected) + suffix + '?' + this.api?.scope(this.directory); }
  private attemptPath(): string { return this.path('/connect/oauth/' + encodeURIComponent(this.attemptID)); }
  private fail(): void { this.error = '操作未完成，请检查输入及连接状态；不会自动重复保存凭据。'; }
  filtered(): Integration[] {
    const term = this.search.toLowerCase().trim();
    if (this.selected && !term) { return this.entries.filter((p: Integration) => p.id === this.selected); }
    return this.entries.filter((p: Integration) => term ? (p.id + ' ' + p.name).toLowerCase().includes(term) :
      p.accounts.length > 0 || /deepseek|mimo|xiaomi|openai|opencode|anthropic|openrouter|google|silicon|volc|kimi|moonshot|zhipu|minimax|alibaba/i.test(p.id + p.name)).slice(0, 40);
  }
  quickSelect(term: string): void {
    this.section = 'native'; this.search = '';
    const entry = this.entries.find((item: Integration) => item.id === term) || this.entries.find((item: Integration) => (item.id + ' ' + item.name).toLowerCase().includes(term));
    if (entry) { this.select(entry); const method = entry.methods.find((item: AuthMethod) => item.type === 'key' && item.supported); if (method) { this.choose(method); } }
    else { this.search = term; this.notice = '请从服务器提供的入口中选择；也可使用自定义兼容渠道。'; }
  }
  modelMatches(): ModelItem[] { const term = this.modelSearch.trim().toLowerCase(); return this.catalog.filter((item: ModelItem) => (item.id + ' ' + item.label).toLowerCase().includes(term)); }
  visibleModels(): ModelItem[] { return this.modelMatches().slice(0, 60); }
  newCustom(): void {
    this.editingID = ''; this.customID = ''; this.customName = ''; this.customURL = ''; this.customModels = ''; this.customKey = ''; this.error = ''; this.notice = '';
  }
  customValidation(): string {
    if (!/^mobile-[a-z0-9][a-z0-9-]{0,47}$/.test(this.customID.trim())) { return '渠道 ID 请使用 mobile- 开头的小写字母、数字或连字符'; }
    if (!this.editingID && this.custom.some((item: CustomProvider) => item.id === this.customID.trim())) { return '此 ID 已存在，请选择已有渠道编辑，或使用新 ID'; }
    const name = this.customName.trim(); if (!name || name.length > 128 || /[\u0000-\u001f]/.test(name)) { return '请填写渠道名称，最多 128 个字'; }
    const url = this.customURL.trim();
    if (url.length > 2048 || !/^https:\/\/[^/?#@\s]+(?:\/[^?#\s]*)?$/.test(url) || /\/(?:chat\/completions|responses|messages)\/?$/.test(url)) {
      return '请填写 HTTPS Base URL，例如 https://api.example.com/v1，不要填写完整请求接口或认证参数';
    }
    const models = this.customModels.split(/[\n,，]/).map((value: string) => value.trim()).filter((value: string) => !!value);
    if (!models.length || models.length > 100 || models.some((value: string) => !/^[A-Za-z0-9_./:~+-]{1,160}$/.test(value))) { return '请填写准确模型 ID，每行一个，最多 100 个'; }
    if (new Set<string>(models).size !== models.length) { return '模型 ID 不能重复'; }
    if (this.customKey.length > 4096 || /[\u0000-\u001f]/.test(this.customKey) || /\{(?:env|file):/i.test(name + url + this.customKey)) { return '名称、地址和密钥需为普通文本，不能包含控制字符或配置插值'; }
    return '';
  }
  current(): Integration | undefined { return this.entries.find((p: Integration) => p.id === this.selected); }
  async load(): Promise<void> {
    if (!this.api || this.busy) { return; }
    const generation = this.generation; this.busy = true; this.error = '';
    try { await this.refresh(generation); } catch (_) { if (generation === this.generation) { this.fail(); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  private async refresh(generation: number): Promise<void> {
    if (!this.api) { return; }
    const response = rows(await this.api.request('/api/integration?' + this.api.scope(this.directory)));
    if (generation !== this.generation) { return; }
    this.entries = response.map((value: Object): Integration => {
      const p = object(value); let first = true;
      const accounts = list(p['connections']).map((value: Object): Account => {
        const a = object(value); const credential = a['type'] === 'credential'; const active = credential && first;
        if (credential) { first = false; }
        return { id: string(a['id']), label: string(a['label'], string(a['name'], '环境变量')), type: string(a['type']),
          method: string(a['method']), active: active };
      });
      return { id: string(p['id']), name: string(p['name'], string(p['id'])), accounts: accounts,
        methods: list(p['methods']).map((value: Object): AuthMethod => {
          const m = object(value); const type = string(m['type']); const id = string(m['id'], type);
          return { id: id, type: type, label: string(m['label'], type === 'key' ? 'API Key' : type === 'env' ? '服务器环境变量' : type),
            fields: parseFields(m['form']), supported: ['key', 'oauth', 'external'].indexOf(type) >= 0 && id !== 'chatgpt-browser' };
        }) };
    });
    try {
      const models = await this.api.models(this.directory);
      if (generation !== this.generation) { return; }
      this.catalog = models; this.catalogError = '';
    } catch (_) { if (generation === this.generation) { this.catalogError = '模型目录暂时读取失败，保留上次目录；请刷新后再选择。'; } }
    try {
      const response = await this.api.request('/client-settings/providers');
      if (generation !== this.generation) { return; }
      this.custom = rows(response).map((value: Object): CustomProvider => {
        const p = object(value); return { id: string(p['id']), name: string(p['name']), baseURL: string(p['baseURL']),
          models: list(p['models']).map((m: Object) => string(m)), hasKey: p['hasKey'] === true };
      }); this.customAvailable = true;
    } catch (error) {
      if (generation === this.generation) {
        if (error instanceof ApiError && error.code === 404) { this.customAvailable = false; this.custom = []; }
        else { this.error = '自定义渠道暂时读取失败，请稍后刷新。'; }
      }
    }
  }
  select(entry: Integration): void {
    this.cancelSilently(); this.generation++; this.selected = entry.id; this.methodID = ''; this.methodType = '';
    this.fields = []; this.key = ''; this.label = ''; this.error = ''; this.notice = ''; this.busy = false;
  }
  choose(method: AuthMethod): void {
    if (!method.supported || this.busy) { return; }
    this.cancelSilently(); this.generation++; this.methodID = method.id; this.methodType = method.type;
    this.fields = method.fields.map((f: FormField): FormField => ({ key: f.key, label: f.label, type: f.type, required: f.required,
      options: f.options, values: f.values.slice(), text: f.text, constraints: f.constraints }));
    this.key = ''; this.code = ''; this.error = ''; this.notice = '';
  }
  field(key: string, value: string, multiple: boolean = false): void {
    this.fields = this.fields.map((f: FormField) => f.key === key ? updateFieldValue(f, value, multiple) : f);
  }
  private async idle(): Promise<void> {
    if (!this.api) { throw new Error('请先连接服务器'); }
    const active = object(object(await this.api.request('/api/session/active'))['data']);
    const forms = rows(await this.api.request('/api/form')); const permissions = rows(await this.api.request('/api/permission/request'));
    if (Object.keys(active).length || forms.length || permissions.length) { throw new ApiError(409, '本实例有运行中的任务或待处理交互，请先结束任务再更改全局模型配置'); }
  }
  private report(error: Error): void { this.error = error instanceof ApiError && error.code === 409 ? error.message : '保存未确认，请检查输入或连接；刷新账号列表后再决定是否重试。'; }
  async connect(): Promise<void> {
    if (!this.api || this.busy || !this.methodType || this.attemptID) { return; }
    let answer: Record<string, FieldValue>;
    try { answer = buildFormAnswer(this.fields); if (this.methodType === 'key' && !this.key.trim()) { throw new Error('请输入 API Key'); } }
    catch (e) { this.error = (e as Error).message; return; }
    const generation = this.generation; const api = this.api; const methodType = this.methodType; const directory = this.directory;
    const connectPath = this.path('/connect/' + methodType);
    this.busy = true; this.error = ''; this.notice = '';
    try {
      await this.idle(); if (generation !== this.generation) { return; }
      if (this.methodType === 'key') {
        await api.request(connectPath, http.RequestMethod.POST,
          { key: this.key.trim(), answer: answer, label: this.label.trim() } as KeyRequest);
      } else {
        const result = await api.request(connectPath, http.RequestMethod.POST,
          { methodID: this.methodID, answer: answer, label: this.label.trim() } as MethodRequest);
        if (generation !== this.generation) {
          if (methodType === 'oauth') {
            const attempt = string(object(object(result)['data'])['attemptID']);
            if (attempt) { await api.request(connectPath.split('?')[0] + '/' + encodeURIComponent(attempt) + '?' + api.scope(directory), http.RequestMethod.DELETE).catch(() => {}); }
          }
          return;
        }
        if (methodType === 'oauth') {
          const a = object(object(result)['data']); this.attemptID = string(a['attemptID']); this.authURL = string(a['url']);
          this.instructions = string(a['instructions']); this.authMode = string(a['mode']); this.authStatus = 'pending';
          this.poll().catch(() => {}); return;
        }
      }
      if (generation !== this.generation) { return; }
      this.key = ''; this.fields = []; this.methodType = ''; this.notice = '凭据已保存到服务器。可用性仍需实际模型调用确认。';
      await this.refresh(generation); if (generation === this.generation) { await this.changed(); }
    } catch (e) {
      if (generation === this.generation) { this.key = ''; this.report(e as Error); await this.refresh(generation).catch(() => {}); }
    } finally { if (generation === this.generation) { this.busy = false; } }
  }
  async poll(): Promise<void> {
    if (!this.api || !this.attemptID || !this.active) { return; }
    const generation = this.generation; this.stopTimer();
    try {
      const a = object(object(await this.api.request(this.attemptPath()))['data']);
      if (generation !== this.generation) { return; }
      this.authStatus = string(a['status'], 'pending');
      if (this.authStatus !== 'pending') {
        this.notice = this.authStatus === 'complete' ? '授权成功，可返回会话选择模型。' : '授权未完成，请重新开始。';
        this.attemptID = ''; this.code = ''; this.authURL = ''; await this.refresh(generation); await this.changed(); return;
      }
    } catch (error) {
      if (generation === this.generation) {
        if (error instanceof ApiError && error.code === 404) {
          this.attemptID = ''; this.code = ''; this.authURL = ''; this.authStatus = 'ended';
          this.notice = '授权记录已结束，请核对账号列表；未出现新账号时可重新授权。';
          await this.refresh(generation).catch(() => {});
          if (generation === this.generation) { await this.changed().catch(() => {}); }
          return;
        }
        this.error = '授权状态查询失败；保留本次授权，恢复网络后继续查询。';
      }
    }
    if (generation === this.generation && this.attemptID && this.active) { this.timer = setTimeout(() => { this.poll().catch(() => {}); }, 2500); }
  }
  async complete(): Promise<void> {
    if (!this.api || !this.attemptID || this.busy || !this.code.trim()) { return; }
    const generation = this.generation; this.busy = true; this.error = '';
    try {
      await this.api.request(this.attemptPath().split('?')[0] + '/complete?' + this.api.scope(this.directory),
        http.RequestMethod.POST, { code: this.code.trim() } as CodeRequest);
      if (generation === this.generation) { this.code = ''; await this.poll(); }
    } catch (_) { if (generation === this.generation) { this.fail(); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  cancel(): void { this.cancelSilently(); this.generation++; this.busy = false; this.notice = '已取消授权'; }
  private cancelSilently(): void {
    this.stopTimer(); if (this.api && this.attemptID) { this.api.request(this.attemptPath(), http.RequestMethod.DELETE).catch(() => {}); }
    this.attemptID = ''; this.authURL = ''; this.instructions = ''; this.authStatus = ''; this.code = '';
  }
  async account(account: Account, action: string): Promise<void> {
    if (!this.api || this.busy || account.type !== 'credential') { return; }
    const generation = this.generation; this.busy = true; this.error = '';
    try {
      await this.idle(); if (generation !== this.generation) { return; }
      const path = '/api/credential/' + encodeURIComponent(account.id);
      if (action === 'activate') { await this.api.request(path + '/activate', http.RequestMethod.POST); }
      else if (action === 'rename') {
        if (!this.label.trim()) { throw new Error('请输入新的账号名称'); }
        await this.api.request(path, 'PATCH' as http.RequestMethod, { label: this.label.trim() } as RenameRequest);
      } else if (action === 'delete') { await this.api.request(path, http.RequestMethod.DELETE); }
      if (generation === this.generation) { await this.refresh(generation); await this.changed(); this.notice = '账号设置已更新'; }
    } catch (e) { if (generation === this.generation) { this.report(e as Error); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
  editCustom(provider: CustomProvider): void {
    this.section = 'custom'; this.editingID = provider.id; this.error = ''; this.customID = provider.id; this.customName = provider.name; this.customURL = provider.baseURL;
    this.customModels = provider.models.join('\n'); this.customKey = ''; this.notice = '密钥留空表示保留原密钥，不会回显已有密钥。';
  }
  async saveCustom(remove: boolean = false): Promise<void> {
    if (!this.api || this.busy || !this.customAvailable) { return; }
    const id = this.customID.trim();
    if (!/^mobile-[a-z0-9][a-z0-9-]{0,47}$/.test(id)) { this.error = '渠道 ID 请使用 mobile- 开头的小写字母、数字或连字符'; return; }
    if (!remove) { const error = this.customValidation(); if (error) { this.error = error; return; } }
    const generation = this.generation; this.busy = true; this.error = ''; this.notice = '';
    try {
      await this.idle(); if (generation !== this.generation) { return; }
      const path = '/client-settings/providers/' + encodeURIComponent(id);
      if (remove) { await this.api.request(path, http.RequestMethod.DELETE); }
      else {
        const body: CustomRequest = { id: id, name: this.customName.trim(), baseURL: this.customURL.trim(),
          models: this.customModels.split(/[\n,，]/).map((v: string) => v.trim()).filter((v: string) => v.length > 0) };
        if (this.customKey.trim()) { body.apiKey = this.customKey.trim(); }
        await this.api.request(path, http.RequestMethod.PUT, body);
      }
      if (generation !== this.generation) { return; }
      this.customKey = ''; await this.api.request('/api/location/reload', http.RequestMethod.POST);
      if (generation !== this.generation) { return; }
      await this.refresh(generation); await this.changed(); if (remove) { this.newCustom(); } else { this.editingID = id; } this.notice = remove ? '自定义渠道已删除' : '自定义渠道已保存，模型列表已刷新';
    } catch (e) { if (generation === this.generation) { this.customKey = ''; this.report(e as Error); } }
    finally { if (generation === this.generation) { this.busy = false; } }
  }
}
