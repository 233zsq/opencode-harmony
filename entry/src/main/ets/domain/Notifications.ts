// Reminder notifications: pure domain rules shared by AppStore, the platform
// NotificationCenter and the settings UI. No platform imports are allowed here so
// the same code can be type-transpiled and exercised by the local Node tests.
export type NotificationKind = 'completed' | 'failed' | 'question' | 'approval';
export type ReminderGroup = 'completed' | 'failed' | 'pending';
// 'unknown' is only used before the first system permission check.
export type ReminderPermission = 'unknown' | 'enabled' | 'disabled' | 'unsupported';

export interface TaskNotification {
  serverID: string;
  directory: string;
  sessionID: string;
  kind: NotificationKind;
  eventID: string;
  // Only used to locate the conversation after a tap. It is never copied into
  // the visible system notification title or body.
  sessionTitle?: string;
}

export interface NotificationText { title: string; text: string; }

export interface ReminderPrefs { completed: boolean; failed: boolean; pending: boolean; }

export interface NotificationTarget {
  serverID: string;
  directory: string;
  sessionID: string;
  eventID: string;
}

export interface TaskNotifySink {
  publish(event: TaskNotification): void;
  accepts?(kind: NotificationKind): boolean;
}

// AppStore keeps this by default; the Index page injects the real
// NotificationCenter once and the Node state tests inject a recording fake.
export class NoopTaskNotifier implements TaskNotifySink {
  accepts(kind: NotificationKind): boolean { return false; }
  publish(event: TaskNotification): void {}
}

export function defaultReminderPrefs(): ReminderPrefs {
  return { completed: true, failed: true, pending: true };
}

// Every key part matters: the same event ID can appear on different servers,
// projects or sessions, and the same message can end as completed or failed.
export function notificationKey(event: TaskNotification): string {
  return [event.serverID, event.directory, event.sessionID, event.kind, event.eventID].join('\n');
}

export function stableHash(value: string): number {
  let hash = 2166136261;
  for (let i = 0; i < value.length; i++) {
    hash = Math.imul(hash ^ value.charCodeAt(i), 16777619);
  }
  return hash >>> 0;
}

// Stable numeric ID; a newer event for the same conversation replaces the old
// notification only when the ID matches, so IDs are derived from the event key.
export function notificationId(event: TaskNotification): number {
  return (stableHash(notificationKey(event)) % 2147483646) + 1;
}

// Notifications are grouped per server so two servers cannot collapse into one
// group. Labels are bounded well below the 202-byte platform limit.
export function notificationLabel(event: TaskNotification): string {
  return 'oc-' + stableHash(event.serverID + '\n' + event.sessionID).toString(36);
}

export function notificationGroup(event: TaskNotification): string {
  return 'oc-' + stableHash(event.serverID).toString(36);
}

// Generic status only. Chat text, session titles, paths, tool arguments and
// credentials must never reach the visible notification.
export function notificationContent(event: TaskNotification): NotificationText {
  if (event.kind === 'completed') {
    return { title: '任务已完成', text: '一个对话中的任务已经结束，点按打开应用查看结果。' };
  }
  if (event.kind === 'failed') {
    return { title: '任务未完成', text: '一个对话中的任务执行失败，点按打开应用查看。' };
  }
  if (event.kind === 'question') {
    return { title: '有待回答的问题', text: '一个对话正在等待你的回答，点按打开应用处理。' };
  }
  return { title: '有待批准的请求', text: '一个对话正在等待操作审批，点按打开应用处理。' };
}

// Stable identity for a finished task: the assistant message id is enough,
// even when its state changes from streaming to completed between syncs.
export function completionEventID(messageID: string, sessionID: string): string {
  return messageID ? 'idle:' + messageID : 'idle:' + sessionID;
}

// Completion and failure must come from confirmed terminal state, not absence
// from the running list alone. A failed message overrides a stale outcome.
export function taskNotificationKind(outcome: string, assistantState: string = ''): NotificationKind | undefined {
  if (assistantState === 'failed' || outcome === 'failed' || outcome === 'interrupted') { return 'failed'; }
  if (outcome === 'succeeded' || (!outcome && assistantState === 'completed')) { return 'completed'; }
  return undefined;
}

export function pendingNotificationKind(pendingKind: string): NotificationKind {
  return pendingKind === 'form' ? 'question' : 'approval';
}

export function reminderGroup(kind: NotificationKind): ReminderGroup {
  if (kind === 'completed') { return 'completed'; }
  if (kind === 'failed') { return 'failed'; }
  return 'pending';
}

// Question and approval share the single "pending" switch.
export function shouldPublish(prefs: ReminderPrefs, kind: NotificationKind, permission: ReminderPermission): boolean {
  if (permission !== 'enabled') { return false; }
  const group = reminderGroup(kind);
  if (group === 'completed') { return prefs.completed; }
  if (group === 'failed') { return prefs.failed; }
  return prefs.pending;
}

// The in-app quiet hint is only for the conversation the user is already
// looking at while the process is in the foreground. Any other case may notify.
export function isQuietReminder(event: TaskNotification, sessionID: string, foreground: boolean): boolean {
  return foreground && !!sessionID && event.sessionID === sessionID;
}

// Bounded set of already handled events. The order array lets the oldest keys
// expire without keeping unbounded memory in a long-running client.
export class NotificationLedger {
  private seen: Set<string> = new Set<string>();
  private order: string[] = [];
  constructor(private limit: number = 2048) {}
  size(): number { return this.seen.size; }
  has(event: TaskNotification): boolean { return this.seen.has(notificationKey(event)); }
  markSeen(event: TaskNotification): void { this.remember(notificationKey(event)); }
  seed(events: TaskNotification[]): void { events.forEach((event: TaskNotification) => this.markSeen(event)); }
  clear(): void { this.seen = new Set<string>(); this.order = []; }
  // Returns true exactly once per distinct key; marks the key as seen first so
  // a failing platform publish can never make the same event retry forever.
  offer(event: TaskNotification): boolean {
    const key = notificationKey(event);
    if (this.seen.has(key)) { return false; }
    this.remember(key);
    return true;
  }
  private remember(key: string): void {
    if (this.seen.has(key)) { return; }
    this.seen.add(key);
    this.order.push(key);
    while (this.order.length > this.limit) {
      const oldest = this.order.shift();
      if (oldest !== undefined) { this.seen.delete(oldest); }
    }
  }
}

export const REMINDER_STORAGE_NAME = 'opencode_reminders';
export const REMINDER_KEY_COMPLETED = 'completed';
export const REMINDER_KEY_FAILED = 'failed';
export const REMINDER_KEY_PENDING = 'pending';
export const REMINDER_KEY_PERMISSION = 'permission';

export function encodeReminderPrefs(prefs: ReminderPrefs): string {
  return JSON.stringify({ completed: prefs.completed, failed: prefs.failed, pending: prefs.pending });
}

export function decodeReminderPrefs(value: string): ReminderPrefs {
  const fallback = defaultReminderPrefs();
  if (!value) { return fallback; }
  try {
    const record = JSON.parse(value) as Record<string, Object>;
    return {
      completed: typeof record[REMINDER_KEY_COMPLETED] === 'boolean' ? record[REMINDER_KEY_COMPLETED] as boolean : fallback.completed,
      failed: typeof record[REMINDER_KEY_FAILED] === 'boolean' ? record[REMINDER_KEY_FAILED] as boolean : fallback.failed,
      pending: typeof record[REMINDER_KEY_PENDING] === 'boolean' ? record[REMINDER_KEY_PENDING] as boolean : fallback.pending
    };
  } catch (_) { return fallback; }
}

export function normalizeReminderPermission(value: string): ReminderPermission {
  if (value === 'enabled' || value === 'disabled' || value === 'unsupported') { return value; }
  return 'unknown';
}

// Deep link contract. The same parameter names are used inside the notification
// want, the AppStorage launch payload and the Node tests.
export const NOTIFICATION_PARAM_SERVER = 'notificationServer';
export const NOTIFICATION_PARAM_DIRECTORY = 'notificationDirectory';
export const NOTIFICATION_PARAM_SESSION = 'notificationSession';
export const NOTIFICATION_PARAM_EVENT = 'notificationEvent';
export const NOTIFICATION_PARAM_LAUNCHED = 'notificationLaunchedAt';
export const NOTIFICATION_LAUNCH_KEY = 'notificationLaunch';
export const NOTIFICATION_ABILITY_NAME = 'EntryAbility';

export function notificationTarget(event: TaskNotification): NotificationTarget {
  return { serverID: event.serverID, directory: event.directory, sessionID: event.sessionID, eventID: event.eventID };
}

function text(value: Object | undefined | null): string {
  return typeof value === 'string' ? value as string : '';
}

// Want parameters must stay primitive. No session title or chat content is put
// into the want; the target only identifies what to open inside this app.
export function notificationWantParameters(target: NotificationTarget): Record<string, Object> {
  const parameters: Record<string, Object> = {};
  parameters[NOTIFICATION_PARAM_SERVER] = target.serverID;
  parameters[NOTIFICATION_PARAM_DIRECTORY] = target.directory;
  parameters[NOTIFICATION_PARAM_SESSION] = target.sessionID;
  parameters[NOTIFICATION_PARAM_EVENT] = target.eventID;
  return parameters;
}

export function notificationTargetFromParameters(parameters: Record<string, Object> | undefined | null): NotificationTarget | undefined {
  if (!parameters) { return undefined; }
  const serverID = text(parameters[NOTIFICATION_PARAM_SERVER]);
  const directory = text(parameters[NOTIFICATION_PARAM_DIRECTORY]);
  const sessionID = text(parameters[NOTIFICATION_PARAM_SESSION]);
  const eventID = text(parameters[NOTIFICATION_PARAM_EVENT]);
  if (!serverID || !sessionID) { return undefined; }
  return { serverID: serverID, directory: directory, sessionID: sessionID, eventID: eventID };
}

// A launch payload is JSON so @StorageLink/@Watch can compare strings. The
// timestamp makes two taps on the same notification distinct values.
export function notificationLaunchValue(target: NotificationTarget, launchedAt: number): string {
  const parameters = notificationWantParameters(target);
  parameters[NOTIFICATION_PARAM_LAUNCHED] = String(launchedAt);
  return JSON.stringify(parameters);
}

export function parseNotificationLaunch(value: string): NotificationTarget | undefined {
  if (!value) { return undefined; }
  try { return notificationTargetFromParameters(JSON.parse(value) as Record<string, Object>); }
  catch (_) { return undefined; }
}

