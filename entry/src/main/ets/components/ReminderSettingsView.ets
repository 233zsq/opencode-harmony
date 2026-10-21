import { HarmonyColors as C } from '../presentation/HarmonyColors';

@Component
struct ReminderSwitchRow {
  @Prop title: string = '';
  @Prop detail: string = '';
  @Prop checked: boolean = true;
  @Prop disabled: boolean = false;
  kind: string = '';
  switchID: string = '';
  onToggle: (kind: string, enabled: boolean) => void = (kind: string, enabled: boolean): void => {};
  build() {
    Row({ space: 12 }) {
      Column({ space: 3 }) {
        Text(this.title).fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
        Text(this.detail).fontSize(13).lineHeight(21).fontColor(C.muted).width('100%')
      }.alignItems(HorizontalAlign.Start).layoutWeight(1)
      Toggle({ type: ToggleType.Switch, isOn: this.checked })
        .id(this.switchID).selectedColor(C.accent).enabled(!this.disabled)
        .accessibilityText(this.title).accessibilityDescription(this.checked ? '已开启' : '已关闭')
        .responseRegion({ x: -8, y: -10, width: 60, height: 48 })
        .onChange((isOn: boolean): void => { this.onToggle(this.kind, isOn); })
    }.width('100%').constraintSize({ minHeight: 48 }).padding({ top: 10, bottom: 10 })
  }
}

// Notification reminder settings. It is self-contained: no page padding, no
// background and no navigation state are assumed, so it can be hosted by a
// NavDestination page or by a bindSheet in the Index page.
@Component
export struct ReminderSettingsView {
  @Prop completed: boolean = true;
  @Prop failed: boolean = true;
  @Prop pending: boolean = true;
  @Prop permission: string = 'unknown';
  @Prop ready: boolean = false;
  @Prop requesting: boolean = false;
  @Prop permissionRequested: boolean = false;
  @Prop notice: string = '';
  onToggle: (group: string, enabled: boolean) => void = (group: string, enabled: boolean): void => {};
  onRequest: () => void = (): void => {};

  private permissionLabel(): string {
    if (!this.ready) { return '正在读取系统通知权限…'; }
    if (this.permission === 'enabled') { return '已开启'; }
    if (this.permission === 'unsupported') { return '当前设备不支持系统通知'; }
    return '未开启';
  }

  // Enabling a reminder is the explicit user action that may open the system
  // authorization dialog. It never happens at app start, and the caller only
  // persists the switch (it must not request permission a second time).
  private toggle(group: string, enabled: boolean): void {
    this.onToggle(group, enabled);
    if (enabled && this.permission !== 'enabled' && this.permission !== 'unsupported') { this.onRequest(); }
  }

  private requestLabel(): string {
    if (this.requesting) { return '正在申请…'; }
    return this.permissionRequested ? '打开系统通知设置' : '申请通知权限';
  }

  @Builder
  sectionLabel(text: string) {
    Text(text).fontSize(12).fontFamily('monospace').letterSpacing(1.2).fontColor(C.muted).width('100%')
  }

  build() {
    Scroll() {
      Column({ space: 14 }) {
        Column({ space: 4 }) {
          Text('提醒设置').fontSize(19).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
          Text('REMINDERS / SYSTEM NOTIFICATIONS').fontSize(12).fontFamily('monospace')
            .letterSpacing(1.2).fontColor(C.muted).width('100%')
          Text('当任务结束或出现需要处理的事项时提醒我。通知只显示通用状态，不包含聊天正文、会话标题、代码或路径。')
            .fontSize(15).lineHeight(23).fontColor(C.secondary).width('100%')
        }.width('100%').alignItems(HorizontalAlign.Start)

        this.sectionLabel('提醒类型')
        Column({ space: 0 }) {
          ReminderSwitchRow({ title: '任务完成', detail: '对话中的任务正常结束时提醒', checked: this.completed,
            disabled: !this.ready || this.requesting, kind: 'completed', switchID: 'reminder-completed',
            onToggle: (group: string, enabled: boolean): void => { this.toggle(group, enabled); } })
          Divider().strokeWidth(1).color(C.separator)
          ReminderSwitchRow({ title: '任务失败', detail: '任务执行失败或未正常结束时提醒', checked: this.failed,
            disabled: !this.ready || this.requesting, kind: 'failed', switchID: 'reminder-failed',
            onToggle: (group: string, enabled: boolean): void => { this.toggle(group, enabled); } })
          Divider().strokeWidth(1).color(C.separator)
          ReminderSwitchRow({ title: '待回答与待审批', detail: '出现新问题或操作审批时提醒', checked: this.pending,
            disabled: !this.ready || this.requesting, kind: 'pending', switchID: 'reminder-pending',
            onToggle: (group: string, enabled: boolean): void => { this.toggle(group, enabled); } })
        }.width('100%').padding({ left: 14, right: 14 }).backgroundColor(C.surface)
          .border({ width: 1, color: C.separator }).borderRadius(16)

        this.sectionLabel('系统权限')
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Column({ space: 3 }) {
              Text('通知权限').fontSize(17).fontWeight(FontWeight.Medium).fontColor(C.text).width('100%')
              Text(this.permissionLabel()).id('reminder-permission').fontSize(13)
                .fontColor(this.permission === 'enabled' ? C.success : this.permission === 'unsupported' ? C.muted : C.warning)
                .width('100%')
            }.alignItems(HorizontalAlign.Start).layoutWeight(1)
          }.width('100%')
          if (this.permission !== 'enabled' && this.permission !== 'unsupported') {
            Button(this.requestLabel(), { type: ButtonType.Normal }).id('reminder-request')
              .width('100%').constraintSize({ minHeight: 48 }).fontSize(15).fontWeight(FontWeight.Medium)
              .backgroundColor(C.btn).fontColor(C.btn_text).borderRadius(14)
              .enabled(this.ready && !this.requesting)
              .accessibilityText(this.permissionRequested ? '打开系统通知设置' : '申请通知权限')
              .onClick((): void => { this.onRequest(); })
          }
          Text('申请后请在系统弹窗或通知设置中选择允许。拒绝或撤销权限只影响提醒，不影响聊天、审批和任务执行。')
            .fontSize(13).lineHeight(21).fontColor(C.muted).width('100%')
          if (this.notice) {
            Text(this.notice).fontSize(13).fontColor(C.warning).width('100%')
          }
        }.width('100%').padding(14).backgroundColor(C.surface)
          .border({ width: 1, color: C.separator }).borderRadius(16)

        this.sectionLabel('提醒范围与限制')
        Column({ space: 6 }) {
          Text('正在查看的对话：只在应用内显示安静提示，不弹出系统通知。').fontSize(15).lineHeight(23).fontColor(C.secondary).width('100%')
          Text('其他对话，或应用不在前台但进程仍存活时：短暂尽力发送系统通知；系统冻结后停止接收。').fontSize(15).lineHeight(23).fontColor(C.secondary).width('100%')
          Text('退到后台后连接只短暂保留；系统冻结或进程退出后不会收到提醒。未接入 Push，也不常驻后台、不轮询、不保活。').fontSize(15).lineHeight(23).fontColor(C.secondary).width('100%')
          Text('点按通知会回到对应服务器、项目和会话；当前未发送的草稿会保留。').fontSize(15).lineHeight(23).fontColor(C.secondary).width('100%')
        }.id('reminder-capability').width('100%').padding(14).backgroundColor(C.surface)
          .border({ width: 1, color: C.separator }).borderRadius(16)

        Text('提醒开关与最近一次权限状态保存在本机。系统通知权限以系统设置为准，应用不会在启动时自动弹窗。')
          .fontSize(13).lineHeight(21).fontColor(C.muted).width('100%')
      }.padding({ left: 18, right: 18, top: 10, bottom: 24 }).width('100%').alignItems(HorizontalAlign.Start)
    }.id('reminder-settings').width('100%').height('100%').align(Alignment.TopStart)
      .backgroundColor(Color.Transparent).scrollBar(BarState.Off)
  }
}
