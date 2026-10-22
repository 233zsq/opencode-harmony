# 移动端输入与适配（2026-10-20）

本轮补齐手机端输入、中文输入法、大字号、窄屏与无障碍细节，并保持 Graphite / Liquid Glass 视觉和既有交互不变。

本文保留实现提交的适配记录；后续审查修复及当前包的验证边界见 [MOBILE-REVIEW.md](MOBILE-REVIEW.md)。

## 软键盘与中文输入

### 实测结果（API26 模拟器）

- 真实输入法窗口可用时，`node tests/keyboard-ui.mjs` 通过：中文三行输入（`第一行 中文` / `第二行 多行输入` / `第三行`）正确写入，输入框与发送按钮完整位于键盘上方，未发送消息。
- 中文候选栏已实际出现（拼音候选“你家那里 / 你进来 / 弄几年了”），候选条位于输入区下方、键盘上方，输入框与发送按钮未被遮挡；证据截图在本机 `ui-preview/baseline/keyboard-chinese2.jpeg`（不提交）。
- 三行输入几何：`node tests/composer-smoke.mjs` 通过（输入区 42→86vp，发送按钮保持底部对齐，未提交）。
- 键盘收起：系统返回先收起键盘；收起后输入区回到页面底部，无大块空白，可再次点击输入框唤起。
- 模拟器重启后输入法可能不再显示。本轮通过
  `hdc shell ime -s com.huawei.hmos.inputmethod`
  切换输入法后恢复；`ime -e ... -b` 可能返回 87，但不影响随后聚焦输入框显示键盘。若后续模拟器又无法显示键盘，先执行上述切换再重试，不能把“输入框获得焦点”当作键盘避让通过。

### 行为

- `KeyboardAvoidMode.RESIZE` 保持；键盘弹出导致页面高度缩小时，只有用户仍在底部跟随（`follow=true`）才滚到最新消息，查看历史时不会被强行拉到底。
- 用户上滑或触摸消息列表会关闭跟随并出现“回到最新”；滚到列表底部（`onReachEnd`）会恢复自动跟随。
- 输入框获得焦点后打开模型、Agent、工具详情、会话操作、更多功能或侧栏时，会通过 `FocusController.clearFocus()` 收起键盘；草稿不会清空。
- 切换会话、新建对话、导航到管理页前同样收起键盘；会话草稿由既有 `ConversationMemory` 保存并在回到会话时恢复。

### 焦点与草稿实测

- 输入 `DRAFT_KEEP_ME` 后点击通知深链（冷/热启动均测）切回目标会话，草稿仍保留；`openNotificationTarget` 在切换前调用 `stashConversation`，验证见 `docs/NOTIFICATIONS.md`。
- 打开模型/工具/提醒设置等页面不会清空未发送文本；关闭页面后输入区仍显示原草稿。

## 大字号

- 在 `AppScope/app.json5` 增加 `configuration: $profile:configuration`，`AppScope/resources/base/profile/configuration.json` 声明 `fontSizeScale: followSystem`、`fontSizeMaxScale: 1.75`。应用从此跟随系统字体大小，并把最大倍率限制在 1.75，避免极端倍率破坏布局。
- 主要控件改为 `constraintSize({ minHeight: ... })` 或自适应高度：思考行、工具行、消息操作按钮、侧栏/列表行、表单按钮与输入框、Sheet 标题与行、审批卡按钮等；默认字号下的视觉高度不变。
- 系统字体“超大”（模拟器字体大小滑杆最大值）实测：标题栏模型 pill 省略、Agent 与待处理状态可读，审批卡的目录/路径/代码/按钮无重叠，侧栏历史与工作区行可增长，提醒设置页完整可读。证据：本机 `ui-preview/baseline/font-actually-large.jpeg`、`large-font-sidebar.jpeg`、`large-font-reminders.jpeg`。
- 超过 1.75 的系统倍率会被 `fontSizeMaxScale` 截断；这是为可读性与布局稳定性做的上限选择，不宣称支持无限放大。

## 窄屏、横屏与分屏

- 现有阈值保持：宽度 ≥840vp 使用 Pad 常驻侧栏，否则手机抽屉；标题模型 pill 有最小/最大宽度和省略，Agent/状态行可收缩，消息列表与输入区最大宽度 860vp。
- 长路径、模型/Agent/工具 ID、审批目录等使用 `maxLines` + ellipsis 或 `wordBreak`，避免窄宽度下溢出或挤压关键操作。
- **未验证**：手机横屏、分屏/悬浮窗、Pad 横竖屏与极窄宽度。本轮只有 API26 手机模拟器竖屏证据；这些形态需要真机或 Pad 专项验收，不能用模拟器竖屏结果宣布通过。

## 无障碍

- 图标/小操作按钮补充准确 `accessibilityText`：展开/收起思考、查看工具详情、复制回复、分叉、复制代码/Diff、继续/收起 Diff、打开/移除附件、刷新、搜索、清除、申请通知权限等。
- 展开/选中状态通过 `accessibilityDescription` / `accessibilityChecked` 表达（思考、审批文件行、模型/Agent/提供商/导出格式/认证方式等）。
- 触控热区：小型按钮统一用 `responseRegion` 扩到 ≥40vp 热区，视觉尺寸与字形不变；复选框、分段控件和 Toggle 按同样方式扩大。布局 bounds 仍是视觉尺寸，验收脚本若只量 bounds 不代表热区不足。
- 浅色、深色与跟随系统在本轮截图与既有 `node tests/ui-smoke.mjs appearance` 中复查；未改动系统菜单/系统确认弹窗的原生语义。

## 验证命令与环境

    node tests/keyboard-ui.mjs
    node tests/composer-smoke.mjs
    node tests/chat-layout.mjs
    node tests/ui-smoke.mjs home
    node tests/ui-smoke.mjs sidebar
    node tests/ui-smoke.mjs providers
    node tests/notifications.test.mjs
    node tests/state.test.mjs

测试使用本机 loopback fixture、API26 模拟器与同一调试签名包；不卸载应用、不清空数据、不调用真实模型。

## 未验证项

- 真机中文 IME/候选栏/悬浮键盘与不同 OEM 输入法差异；模拟器已恢复键盘并通过，但真实软键盘避让仍需真机确认。
- 横屏、分屏、悬浮窗、Pad 布局与显示大小缩放专项。
- 系统字体倍率超过 1.75（被上限截断）、以及第三方字体/超大辅助字体设置。
- API24 设备上的大字号与输入法行为。
- 分屏状态下键盘避让、通知点击后横屏定位、通知权限撤销后的恢复。