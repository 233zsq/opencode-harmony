# 任务提醒通知（2026-10-20）

本地任务提醒：在应用进程仍能观测到状态变化时，为任务完成、失败、新问题和新审批发送系统通知；正在查看的会话只显示应用内安静提示。没有接入 Push、常驻后台任务、轮询保活或服务器推送，因此进程退出或后台被冻结时收不到提醒。

## 实际能力边界

| 场景 | 是否提醒 | 说明 |
| --- | --- | --- |
| 前台，正在查看的会话 | 只写应用内安静提示（`reminderQuiet` / `reminderQuietSeq`），不弹系统通知 | 用户已经在看结果，不重复打扰；同一事件只提示一次 |
| 前台，其他会话 | 尽力发送系统通知 | 新问题/审批来自全局待办轮询；其他会话从“运行中”变为空闲时按完成提醒 |
| 应用在前台但处于项目/设置等页面 | 当前会话完成仍算安静提示；其他会话走系统通知 | “当前会话”以已打开的服务器、目录和会话为准，与当前页面无关 |
| 应用退到后台、进程仍存活 | 短暂尽力发送系统通知 | 仅当提醒开启且已授权时，保留已建立连接约 20 秒；系统随时可能冻结，冻结后停止接收；不使用常驻后台任务或 keep-alive |
| 后台被系统冻结 | 收不到 | 没有后台长任务、Push 或保活；冻结后连接与 JS 定时器停止 |
| 应用进程退出/被清理 | 收不到 | 客户端没有服务端 Push；任务结束状态要在下次打开应用后读取 |
| 通知权限被拒绝或撤销 | 收不到系统通知，其他功能不受影响 | 聊天、审批、任务执行、待办中心继续工作；不会反复弹窗 |

应用退到后台时：若提醒已开启、系统通知已授权且仍有提醒开关打开，`Index` 调用 `AppStore.beginBackgroundReminderWindow(20000)`，把前台标志置为 false、保留已建立的 SSE 连接最多 20 秒，用于捕捉“刚切后台就结束”的任务；窗口结束或回到前台时恢复正常生命周期。系统冻结后不再有任何检测；回到前台后的第一次补同步按“历史同步不通知”处理，避免把离线期间完成的任务当成刚发生的事件反复提醒；这些结果在会话内正常可见。没有实现无限轮询、常驻后台或虚假保活。

## 通知类型与开关

- `任务完成`：当前会话或观察中的其他会话任务结束。
- `任务失败`：当前会话最后一条助手消息为失败状态。
- `待回答与待审批`：出现新的 Question/Form 或权限审批请求。
- 开关持久化在独立 `preferences`（`opencode_reminders`）中，并保存最近一次权限状态；系统权限每次启动、进入提醒设置和回到前台时重新核对，以系统为准。

## 权限

- 使用系统通知授权弹窗（`requestEnableNotification(context)`）只在用户主动打开提醒开关或点击“申请通知权限”时调用，启动时不弹窗。
- 用户拒绝过一次后系统不再允许自动弹窗；再次点击会引导到系统通知设置页（`openNotificationSettings(context)`，API 13+，最低兼容 API 24 可用）。
- 权限状态分为 `enabled` / `disabled` / `unsupported`（`unknown` 仅表示尚未检查）。设备不支持通知 API 时只显示说明，不重试。
- 发布失败（权限被撤销、通道关闭、频率限制等）静默处理，仅更新 `NotificationCenter.lastError` 内部状态，不影响聊天、审批或任务执行。

## 检测、基线与去重

- **初始基线**：`openSession` 的第一次同步把已有消息、待办和待处理项标记为已见，绝不通知。
- **历史分页**：`older()` / `readingHistory` 期间检测全部跳过；`latest()` 回到最新后重新建立基线。
- **断线/回前台补同步**：SSE 断开或应用退后台会设置一次性抑制标记，下一次同步只建立基线、不通知。
- **全局待办基线**：每次（重新）连接后的第一次成功待办读取种入基线；读取有失败范围时保持基线，避免半读取状态误报。
- **SSE 与账本双重去重**：SSE 重复 eventID 由原有 `eventIDs` 处理；提醒账本 `NotificationLedger` 使用 `serverID + directory + sessionID + kind + eventID` 组成的键（`notificationKey`），同一事件只投递一次。跨服务器、跨目录、跨会话的同名 ID 互不抑制。
- 账本最多保留 2048 个键，超出后淘汰最早记录；提醒是否成功显示不影响去重，避免每次同步重复尝试。
- 其他会话完成通过 `/api/session/active` 中“之前观察为运行中、现在消失”判断；该路径无法区分失败，统一按“已完成”提醒，会话内仍显示真实失败状态。SSE 的 `session.idle` 会触发一次待办刷新，使该判断通常在 1 秒内完成；轮询间隔约 5–15 秒。

## 隐私

- 通知标题/正文只使用通用状态文案（如“任务已完成”“有待批准的请求”），禁止出现聊天正文、会话标题、代码、工具参数、路径或密钥。
- `TaskNotification.sessionTitle` 只用于点击定位和内部上下文，不进入可见通知文案。
- 点击通知的 `want.parameters` 只包含服务器 ID、目录、会话 ID 和事件 ID，属于应用内部数据；通知不含会话标题。
- 通知按服务器分组（`groupName`）并带稳定 ID，ID 由事件键哈希得到；同一事件重复发布只会更新同一条通知。

## 点击通知的定位

1. 通知通过 `WantAgent`（`START_ABILITY`）携带参数启动 `EntryAbility`。
2. `EntryAbility.onCreate`（冷启动）和 `onNewWant`（应用存活时）把参数解析成 `NotificationTarget`，以 JSON 字符串写入 `AppStorage` 键 `notificationLaunch`；时间戳保证重复点击同一通知也会产生新值。
3. `Index` 页监听该键，调用 `AppStore.openNotificationTarget(target)`。
4. `openNotificationTarget` 复用现有安全切换：先经 `stashConversation` 保留当前草稿；目标服务器不同则 `connect(server)`；再 `selectProject(directory)`、定位/读取会话、`openSession`。全程 `targetBusy` 防重入；目标服务器已被移除时只提示、不破坏当前会话；失败时保留当前可见会话。
5. 已见事件不会因为点击而再次提醒。通知本身在点击后由系统清除（`tapDismissed`）。

## 代码结构

- `entry/src/main/ets/domain/Notifications.ts`：纯逻辑（类型、文案、开关与权限判定、账本、深链编解码、稳定 ID），无平台 import，可被本机 Node 测试转译。
- `entry/src/main/ets/presentation/NotificationCenter.ets`：平台层（权限、通知通道、发布、WantAgent、设置持久化）。所有平台失败静默降级。
- `entry/src/main/ets/components/ReminderSettingsView.ets`：Graphite 设置 UI（三个 `Toggle`、权限状态与申请按钮、能力说明）；控件 ID：`reminder-completed` / `reminder-failed` / `reminder-pending` / `reminder-permission` / `reminder-request` / `reminder-capability`。
- `AppStore.ets`：`TaskNotifySink`（默认 no-op）与 `attachNotifier`、事件检测与安静提示、`openNotificationTarget`。AppStore 不 import 任何通知平台模块，Node 状态测试注入记录型 sink。
- `EntryAbility.ets`：`onCreate` / `onNewWant` 写入 `notificationLaunch`。
- `Index.ets`（由集成者接入）：设置页入口、`@StorageLink('notificationLaunch')` watcher、安静提示 UI、向 `AppStore` 注入 `NotificationCenter` 并传入前台标志。

## 验证记录

- 纯逻辑/状态测试：`node tests/notifications.test.mjs` 22 项通过（新增“同一助手消息从 streaming 到 completed 的完成事件 ID 稳定”）；`node tests/state.test.mjs` 93 项通过（既有 88 项断言未修改，追加 5 项提醒集成测试）。
- 其余 Node 回归：core 35、workspace-controls 28、agent-export 23、model-selection 4、attachments 13、permission-metadata 6、appearance 3、ui-palette 2、local-state 7、workspace-http 6，共 242 项 Node 测试通过；performance 4 项合成负载通过。
- `powershell -File scripts/build.ps1`：ArkTS 编译、HAP 打包与调试签名通过；集成后完整构建通过并以同一调试签名安装，未卸载或清空应用数据。
- API26 模拟器实测（本机 loopback fixture，未调用真实模型/服务器）：
  - 通知授权系统弹窗出现，选择“允许”后提醒页权限状态变为“已开启”。
  - 后台 20 秒窗口内完成任务：收到一条“任务已完成”通知。修复前同一任务会因 streaming→completed 生成两个事件键而重复，现完成事件按助手消息 ID 稳定去重，实测仅一条。
  - 失败事件：收到一条“任务未完成”通知；通知文案只含通用状态。
  - 其他会话新审批：前台不在该会话时收到一条“有待批准的请求”通知；点击后回到对应会话并展示审批卡。
  - 点击通知（后台热启动）与模拟 want 冷启动均定位到目标服务器/项目/会话；打开通知前后输入框草稿 `DRAFT_KEEP_ME` 保持。
  - 当前会话前台完成时只出现应用内安静提示“当前会话任务已完成”+“知道了”，未发布系统通知。
  - 清除通知后单事件只产生一条通知；实测日志只有一次 dispatch/publish。

## 未验证项与后续

- 未在真机验证系统授权弹窗样式、通知展示、点击冷/热启动与分组；模拟器仅验证了功能路径。
- 未验证系统冻结/进程被杀后的真实收不到行为（按设计不承诺；需要真机长时间后台测试确认不会残留失效通知）。
- 未验证 API24 设备上的通知能力与 `openNotificationSettings` 行为（目标 SDK 26，最低 API 24；调用失败会静默降级）。
- 未验证权限拒绝后再次引导到设置页、以及撤销权限后的恢复流程。
- 若需要离线/进程退出提醒，必须引入 Push Kit 与服务端推送；这超出当前客户端范围，且需要服务端改造与用户授权。
