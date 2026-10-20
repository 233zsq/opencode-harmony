import { common, wantAgent, Want, WantAgent } from '@kit.AbilityKit';
import { notificationManager } from '@kit.NotificationKit';
import { preferences } from '@kit.ArkData';
import { BusinessError } from '@kit.BasicServicesKit';
import { TaskNotification, TaskNotifySink, NotificationTarget, ReminderPrefs, ReminderPermission, ReminderGroup,
  notificationTarget, notificationWantParameters, notificationContent, notificationId, notificationLabel, notificationGroup,
  shouldPublish, normalizeReminderPermission,
  REMINDER_STORAGE_NAME, REMINDER_KEY_COMPLETED, REMINDER_KEY_FAILED, REMINDER_KEY_PENDING, REMINDER_KEY_PERMISSION,
  NOTIFICATION_ABILITY_NAME } from '../domain/Notifications';

// Platform layer for reminders. All failures are contained here: permission
// changes, missing slots and publish errors must never affect chat, approvals or
// task execution. The visible text is produced by domain/Notifications only.
@Observed
export class NotificationCenter implements TaskNotifySink {
  completed: boolean = true;
  failed: boolean = true;
  pending: boolean = true;
  // 'unknown' until the first system check; never assume notifications work.
  permission: ReminderPermission = 'unknown';
  ready: boolean = false;
  requesting: boolean = false;
  // Internal diagnostic status only; never rendered as raw platform errors.
  lastError: string = '';
  private context: common.UIAbilityContext | undefined = undefined;
  private store: preferences.Preferences | undefined = undefined;
  private slotReady: boolean = false;

  attachContext(context: common.UIAbilityContext): void { this.context = context; }

  currentPrefs(): ReminderPrefs { return { completed: this.completed, failed: this.failed, pending: this.pending }; }
  // Best-effort background delivery: the app may keep an already-open SSE
  // connection for a short window after leaving the foreground. This is not a
  // keep-alive; the OS may freeze the process at any time.
  backgroundWanted(): boolean {
    return this.ready && this.permission === 'enabled' && (this.completed || this.failed || this.pending);
  }

  async load(): Promise<void> {
    if (this.store === undefined) { await this.openStore(); }
    const store = this.store;
    if (store) {
      try {
        this.completed = await store.get(REMINDER_KEY_COMPLETED, true) as boolean;
        this.failed = await store.get(REMINDER_KEY_FAILED, true) as boolean;
        this.pending = await store.get(REMINDER_KEY_PENDING, true) as boolean;
        this.permission = normalizeReminderPermission(await store.get(REMINDER_KEY_PERMISSION, 'unknown') as string);
      } catch (_) { this.lastError = '提醒设置暂时无法读取，先使用本次运行的默认值'; }
    }
    this.ready = true;
    await this.refreshPermission();
  }

  private async openStore(): Promise<void> {
    const context = this.context;
    if (!context) { return; }
    try { this.store = await preferences.getPreferences(context, { name: REMINDER_STORAGE_NAME }); }
    catch (_) { this.store = undefined; }
  }

  async setGroup(group: ReminderGroup, enabled: boolean): Promise<void> {
    if (group === 'completed') { this.completed = enabled; }
    else if (group === 'failed') { this.failed = enabled; }
    else { this.pending = enabled; }
    await this.persist();
  }

  private async persist(): Promise<void> {
    if (this.store === undefined) { await this.openStore(); }
    const store = this.store;
    if (!store) { return; }
    try {
      await store.put(REMINDER_KEY_COMPLETED, this.completed);
      await store.put(REMINDER_KEY_FAILED, this.failed);
      await store.put(REMINDER_KEY_PENDING, this.pending);
      await store.put(REMINDER_KEY_PERMISSION, this.permission);
      await store.flush();
    } catch (_) { this.lastError = '提醒开关未能保存，请稍后重试'; }
  }

  async refreshPermission(): Promise<ReminderPermission> {
    try {
      const enabled = await notificationManager.isNotificationEnabled();
      this.permission = enabled ? 'enabled' : 'disabled';
    } catch (error) {
      this.permission = this.unsupported(error as Error) ? 'unsupported' : 'disabled';
    }
    await this.persist();
    return this.permission;
  }

  // Must only be called from an explicit user action (enabling a switch or the
  // permission button). The dialog itself is never opened at app start.
  async requestPermission(): Promise<ReminderPermission> {
    if (this.requesting) { return this.permission; }
    this.requesting = true;
    try {
      const current = await this.refreshPermission();
      if (current === 'enabled' || !this.context) { return this.permission; }
      try { await notificationManager.requestEnableNotification(this.context); }
      catch (_) {
        // The system dialog can only be shown once. After a rejection (or when
        // notifications are disabled) guide the user to the settings page.
        try { await notificationManager.openNotificationSettings(this.context); }
        catch (_) { /* capability may be unavailable on this device */ }
      }
      await this.refreshPermission();
    } catch (_) { /* permission is best effort and never blocks the app */ }
    finally { this.requesting = false; }
    return this.permission;
  }

  publish(event: TaskNotification): void {
    if (!shouldPublish(this.currentPrefs(), event.kind, this.permission)) { return; }
    if (!this.context) { return; }
    this.publishEvent(event).catch((error: Error) => { this.lastError = this.describe(error); });
  }

  private async publishEvent(event: TaskNotification): Promise<void> {
    try {
      await this.ensureSlot();
      const content = notificationContent(event);
      const request: notificationManager.NotificationRequest = {
        id: notificationId(event),
        label: notificationLabel(event),
        content: {
          notificationContentType: notificationManager.ContentType.NOTIFICATION_CONTENT_BASIC_TEXT,
          normal: { title: content.title, text: content.text }
        },
        notificationSlotType: notificationManager.SlotType.SERVICE_INFORMATION,
        groupName: notificationGroup(event),
        tapDismissed: true,
        isAlertOnce: true
      };
      const agent = await this.buildWantAgent(event);
      if (agent) { request.wantAgent = agent; }
      await notificationManager.publish(request);
      this.lastError = '';
    } catch (error) {
      // Best effort: a disabled slot, revoked permission or a busy notification
      // service only updates a private status field.
      this.lastError = this.describe(error as Error);
    }
  }

  private async ensureSlot(): Promise<void> {
    if (this.slotReady) { return; }
    try { await notificationManager.addSlot(notificationManager.SlotType.SERVICE_INFORMATION); }
    catch (_) { /* publish still carries notificationSlotType */ }
    this.slotReady = true;
  }

  // Only generic status and an internal target are used. The want parameters
  // identify server/project/session; no chat text, session title, path or code
  // is ever attached to the notification.
  private async buildWantAgent(event: TaskNotification): Promise<WantAgent | undefined> {
    const context = this.context;
    if (!context) { return undefined; }
    try {
      const target: NotificationTarget = notificationTarget(event);
      const want: Want = {
        bundleName: context.abilityInfo.bundleName,
        abilityName: NOTIFICATION_ABILITY_NAME,
        parameters: notificationWantParameters(target)
      };
      const info: wantAgent.WantAgentInfo = {
        wants: [want],
        actionType: wantAgent.OperationType.START_ABILITY,
        requestCode: notificationId(event),
        actionFlags: [wantAgent.WantAgentFlags.UPDATE_PRESENT_FLAG]
      };
      return await wantAgent.getWantAgent(info);
    } catch (_) { return undefined; }
  }

  private unsupported(error: Error): boolean {
    const code = (error as BusinessError).code;
    // 801: the device/API does not support this notification capability.
    return code === 801;
  }

  private describe(error: Error): string {
    const code = (error as BusinessError).code;
    if (code === 1600004 || code === 1600020) { return '系统通知未开启，提醒未显示'; }
    if (code === 1600005) { return '通知通道已关闭，提醒未显示'; }
    if (code === 1600009) { return '通知发送过于频繁，提醒未显示'; }
    if (code === 801) { return '当前设备不支持系统通知提醒'; }
    return '提醒暂未显示';
  }
}



