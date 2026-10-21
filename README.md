# OpenCode Harmony

基于 ArkTS + ArkUI 的 HarmonyOS 原生 OpenCode 远程客户端。最低兼容 API 24，编译/目标 SDK 26.0.0；协议以 OpenCode v2.0.29 为基线。

代码和 Agent 在用户自己的 OpenCode 服务器运行。本机保存连接配置、最近会话位置以及系统安全资产中的认证信息，完整聊天历史保留服务器。

## 当前实现

- 对话首页、原生导航与系统菜单、手机抽屉与Pad宽屏侧栏；历史搜索、独立管理页面及最近服务器恢复。
- 鸿蒙原生视觉与比例：中性灰白/深灰主题、蓝色选中态、较窄历史侧栏、分层字号与分组列表；原创玻璃代码图标用于启动和空态。模型高频选择采用顶部锚定浮层，“全部模型”进入完整搜索页，其余复杂流程使用原生页面；见 [HARMONY-UI-REFINEMENT.md](docs/HARMONY-UI-REFINEMENT.md)。
- API26 原生沉浸光感、系统分段控件及跟随系统/浅色/深色外观；最低兼容 API24。
- 多服务器配置与编辑、密码保留/更新/清除、重复地址检查及移除确认；HTTP Basic 认证、连接与错误状态。
- 项目/目录、创建和恢复会话、历史分页；会话改名、本机置顶/归档及服务器名称搜索。
- 原生照片/文件选择、附件草稿与压缩、图片/文本预览及保存；按模型能力检查图片和 PDF 输入。
- SSE 流式正文，思考结束自动收起、工具摘要点击查看详情；原生 Markdown、代码块、表格和可点击 HTTPS 链接。
- V2 Question/Form：单选、多选、文本、条件字段、默认值与类型校验。
- 审批前查看命令、目录、操作范围及请求自带 Diff；批准前重新核对，支持单次批准/拒绝及失败恢复。
- 会话 Agent 搜索与切换、说明及默认模型展示；切换结果读回确认与重复提交保护。
- 消息分叉、编辑重发草稿、可选原附件与父会话返回；上下文上限、服务端 Token/费用及手动压缩状态核对。
- 完整历史导出 Markdown/文本、可选工具详情与原生文件保存；长会话进度、取消及失败处理。
- 动态模型目录、聊天页模型搜索与分批选择、渠道/ID和图片/PDF能力展示，以及每个服务器的模型偏好。
- 手机端提供商搜索、API Key、OAuth 设备码/授权码和多账号管理；受限自定义兼容渠道。
- 只读文件浏览、工作区 Git Diff，以及按任务快照查看会话修改。
- 退避重连、回前台同步、消息 ID 去重与迟到响应隔离；发送结果核对、草稿及 Question 答案在本次运行中暂存。
- 跨项目待办中心、侧栏运行/待回答/待审批状态；消息/代码复制及原生多行输入。
- 任务提醒：完成/失败/待回答与待审批可分别开关，仅在用户主动开启时申请系统通知权限；通知只显示通用状态，点击回到对应会话并保留草稿；当前正在查看的会话只用安静应用内提示。前台、短时间后台与进程退出边界见 [NOTIFICATIONS.md](docs/NOTIFICATIONS.md)。
- 手机输入与适配：真实软键盘避让、中文候选栏与多行输入、切换会话/打开面板时收起键盘并保留草稿、系统大字体（跟随系统，上限 1.75）、窄屏省略与图标按钮无障碍热区；边界见 [MOBILE-USABILITY.md](docs/MOBILE-USABILITY.md)，通知审查与修复见 [MOBILE-REVIEW.md](docs/MOBILE-REVIEW.md)。

已在 API26 模拟器和 API24 Pad 构建、安装并运行。当前版本已完成 273 项 Node 回归、2 项 Python 域校验、4 项 Node 合成负载检查及完整构建；本轮交互与提醒在 API26 模拟器验收，真机、横屏/分屏和 API24 设备留待之后。真实免费 MiMo 已正确读取合成图片和文本附件。连接编辑、分叉与长会话管理见 [CONNECTIONS-AND-SESSIONS.md](docs/CONNECTIONS-AND-SESSIONS.md)。Agent 切换、会话导出与验证边界见 [AGENTS-AND-EXPORT.md](docs/AGENTS-AND-EXPORT.md)。提供商表单修复、模型搜索及后续功能优先级见 [MODEL-WORKFLOW.md](docs/MODEL-WORKFLOW.md)。附件交互证据、预览边界与复现步骤见 [CONTENT-AND-ACCEPTANCE.md](docs/CONTENT-AND-ACCEPTANCE.md)，既有设备与服务器验证见 [PROGRESS.md](docs/PROGRESS.md)，实施方案见 [PLAN.md](docs/PLAN.md)。

独立9443 HTTPS入口已可使用。正式域名等待备案；DeepSeek等需在手机设置中输入自己的有效凭据，保存成功与实际模型调用分别核验。免费MiMo使用内置OpenCode提供商；其免费入口拒绝自定义兼容接入。提供商入口和配置边界见 [PROVIDERS.md](docs/PROVIDERS.md)。

界面位置与交互规则、设备验证及聊天间距/输入区修复见 [UI.md](docs/UI.md)。原生控件、API26材质和兼容边界见 [NATIVE-UI.md](docs/NATIVE-UI.md)。聊天、会话与待办的新功能和最终交互验收清单见 [WORKSPACE-FEATURES.md](docs/WORKSPACE-FEATURES.md)。任务提醒能力边界见 [NOTIFICATIONS.md](docs/NOTIFICATIONS.md)，移动端输入/大字号/无障碍见 [MOBILE-USABILITY.md](docs/MOBILE-USABILITY.md)。

最新侧栏与材质调整见 [HISTORY-AND-MATERIALS.md](docs/HISTORY-AND-MATERIALS.md)：历史列表占侧栏主要空间，点外部收起，模型浮层按 API26 能力显式开启沉浸光感。

## 开发环境

- DevEco Studio 26.0.0.851（内置 SDK 26.0.0.105）。
- 使用 IDE 内置 Node/JDK/OHPM/Hvigor。默认安装目录为 C:\Program Files\Huawei\DevEco Studio；可用 DEVECO_STUDIO_HOME 指定其他目录。
- 工程保持 Stage 单 entry 模块，无额外业务 npm/ohpm 依赖。

构建：

    powershell -File scripts/build.ps1

构建并安装启动到当前本地模拟器（默认 HDC target 127.0.0.1:5555）：

    powershell -File scripts/build.ps1 -Install -Launch

安装脚本默认优先使用本机已生成的 signed HAP，与当前项目的 IDE 签名保持一致；没有签名产物时才回退 unsigned HAP。真机需在 DevEco Studio 登录并配置自己的调试签名。签名信息和证书仅保留本地，不提交仓库。指定 USB 或 Wi-Fi HDC 目标安装签名版：

    powershell -File scripts/build.ps1 -Install -Launch -Signed -DeviceTarget "设备的HDC目标"

产物位于 entry/build/default/outputs/default，分别为 entry-default-unsigned.hap 和配置签名后生成的 entry-default-signed.hap。

同一模拟器上的同包名应用应始终使用同一签名，后续手工 HDC 验证也安装 signed HAP。需要未签名包时可显式指定 -Unsigned，不能与 -Signed 同用。签名切换可能产生 9568332；保留数据卸载仍会校验原签名，清数据重装必须先征得使用者同意。脚本不会自动卸载，并会检查 HDC 的实际安装成功回执，避免只凭退出码 0 误判成功。

测试（使用内置 Node）：

    node tests/core.test.mjs
    node tests/state.test.mjs
    node tests/workspace-controls.test.mjs
    node tests/agent-export.test.mjs
    node tests/model-selection.test.mjs
    node tests/attachments.test.mjs
    node tests/permission-metadata.test.mjs
    node tests/appearance.test.mjs
    node tests/immersive-materials.test.mjs
    node tests/native-driver.test.mjs
    node tests/ui-palette.test.mjs
    node tests/local-state.test.mjs
    node tests/workspace-http.test.mjs
    node tests/notifications.test.mjs
    node tests/performance.mjs
    python tests/domain_entry_test.py

Python设置服务的11项测试使用Linux运行 `python3 tests/mobile_settings_test.py`，依赖fcntl；Windows本机运行上述 Node 回归和 domain_entry_test.py。

测试从本机 SDK 读取 TypeScript 转译器，不需要下载测试依赖。状态测试运行真实客户端逻辑，只替换平台接口。审批服务端修复、部署与原生失败恢复验收见 [APPROVALS.md](docs/APPROVALS.md)。

悬浮标题、输入区和工作空间二级入口见 [FLOATING-CHAT.md](docs/FLOATING-CHAT.md)。

## 本机联调服务

tests/fake-server.mjs 是明确标识的本地测试 fixture，不是生产 OpenCode，也不执行真实 Agent。

    node tests/fake-server.mjs

默认监听 PC 的 127.0.0.1:4210。使用 HDC 反向映射：

    hdc -t 127.0.0.1:5555 rport tcp:4210 tcp:4210

App 地址填写 http://127.0.0.1:4210，账号 opencode，测试密码 local-test，并明确开启可信 HTTP 选项。这组凭据仅适用于随代码提供的本机测试服务，不是任何真实服务器凭据。

模拟器首次输入可能需要使用者完成输入法初始化。之后可运行 tests/emulator-smoke.mjs；截图与布局保存在被 Git 忽略的 .test 目录。

## 真实服务器连接

生产使用经验证的 HTTPS URL及 OpenCode API 凭据。SSH 账号和 API 账号不是同一认证体系；v2.0.29 的 Basic 用户名是 opencode。

备案期间已提供独立9443 HTTPS入口，使用专用CA及服务器公钥绑定。App中填写HTTPS地址，勾选“使用专用服务器证书”，无需保持电脑或SSH隧道在线。独立账号、受限文件系统、证书期限及运维边界见 [SERVER.md](docs/SERVER.md)。

scripts/provision-server.sh 是供核验后使用的独立实例部署脚本。它拒绝覆盖已有单位或抢占端口；不会运行修改默认后台服务的 opencode service set。

## 源码结构

- entry/src/main/ets/domain/Core.ts：纯逻辑，SSE/归并/Form/Markdown/Diff。
- entry/src/main/ets/data：Network Kit 协议适配与安全存储。
- entry/src/main/ets/presentation/AppStore.ets：业务状态和同步。
- entry/src/main/ets/components：原生 UI 组件。
- entry/src/main/ets/pages/Index.ets：连接、项目、聊天、审查和设置。
- server/mobile_settings.py：本实例受限自定义渠道接口，只管理 mobile-* 配置。
- tests：协议与竞态回归、本机 fixture、模拟器交互。
- docs：计划、验证状态、服务器边界及第三方来源。

## 参考与许可

主要参考 [alvarolorentedev/opencode-mobile](https://github.com/alvarolorentedev/opencode-mobile) 的协议适配和同步设计，固定提交与来源见 [THIRD_PARTY.md](docs/THIRD_PARTY.md)。本项目使用 Apache-2.0；不使用参考应用的品牌或发布身份。

OpenCode Harmony 是独立客户端，与 OpenCode 官方没有隶属关系。

DeepSeek Graphite / Liquid Glass 分支的审查、修正和本轮验证范围见 [UI-REVIEW.md](docs/UI-REVIEW.md)。
