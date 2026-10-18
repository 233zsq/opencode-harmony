# OpenCode Harmony

基于 ArkTS + ArkUI 的 HarmonyOS 原生 OpenCode 远程客户端。最低兼容 API 24，编译/目标 SDK 26.0.0；协议以 OpenCode v2.0.29 为基线。

代码和 Agent 在用户自己的 OpenCode 服务器运行。本机保存连接配置、最近会话位置以及系统安全资产中的认证信息，完整聊天历史保留服务器。

## 当前实现

- 对话首页、原生导航与系统菜单、手机抽屉与Pad宽屏侧栏；历史搜索、独立管理页面及最近服务器恢复。
- API26 原生沉浸光感、系统分段控件及跟随系统/浅色/深色外观；最低兼容 API24。
- 多服务器配置、HTTP Basic 认证、连接与错误状态。
- 项目/目录、创建和恢复会话、历史分页；会话改名、本机置顶/归档及服务器名称搜索。
- 原生照片/文件选择、附件草稿与压缩、图片/文本预览及保存；按模型能力检查图片和 PDF 输入。
- SSE 流式正文，思考结束自动收起、工具摘要点击查看详情；原生 Markdown、代码块、表格和可点击 HTTPS 链接。
- V2 Question/Form：单选、多选、文本、条件字段、默认值与类型校验。
- 审批前查看命令、目录、操作范围及请求自带 Diff；批准前重新核对，支持单次批准/拒绝及失败恢复。
- 动态模型目录、会话模型切换及每个服务器的模型偏好。
- 手机端提供商搜索、API Key、OAuth 设备码/授权码和多账号管理；受限自定义兼容渠道。
- 只读文件浏览、工作区 Git Diff，以及按任务快照查看会话修改。
- 退避重连、回前台同步、消息 ID 去重与迟到响应隔离；发送结果核对、草稿及 Question 答案在本次运行中暂存。
- 跨项目待办中心、侧栏运行/待回答/待审批状态；消息/代码复制及原生多行输入。

已在 API26 模拟器和 API24 Pad 构建、安装并运行。当前附件与内容更新已完成 153 项本机回归、4 项合成负载检查及完整构建，最新交互按使用者要求只在 API26 模拟器验收；真机留待之后。真实免费 MiMo 已正确读取合成图片和文本附件。具体交互证据、预览边界与复现步骤见 [CONTENT-AND-ACCEPTANCE.md](docs/CONTENT-AND-ACCEPTANCE.md)，既有设备与服务器验证见 [PROGRESS.md](docs/PROGRESS.md)，实施方案见 [PLAN.md](docs/PLAN.md)。

独立9443 HTTPS入口已可使用。正式域名等待备案；DeepSeek等需在手机设置中输入自己的有效凭据，保存成功与实际模型调用分别核验。免费MiMo使用内置OpenCode提供商；其免费入口拒绝自定义兼容接入。提供商入口和配置边界见 [PROVIDERS.md](docs/PROVIDERS.md)。

界面位置与交互规则、设备验证及聊天间距/输入区修复见 [UI.md](docs/UI.md)。原生控件、API26材质和兼容边界见 [NATIVE-UI.md](docs/NATIVE-UI.md)。聊天、会话与待办的新功能和最终交互验收清单见 [WORKSPACE-FEATURES.md](docs/WORKSPACE-FEATURES.md)。

## 开发环境

- DevEco Studio 26.0.0.851（内置 SDK 26.0.0.105）。
- 使用 IDE 内置 Node/JDK/OHPM/Hvigor。默认安装目录为 C:\Program Files\Huawei\DevEco Studio；可用 DEVECO_STUDIO_HOME 指定其他目录。
- 工程保持 Stage 单 entry 模块，无额外业务 npm/ohpm 依赖。

构建：

    powershell -File scripts/build.ps1

构建并安装启动到当前本地模拟器（默认 HDC target 127.0.0.1:5555）：

    powershell -File scripts/build.ps1 -Install -Launch

模拟器可安装 unsigned HAP；真机需在 DevEco Studio 登录并配置自己的调试签名。签名信息和证书仅保留本地，不提交仓库。指定 USB 或 Wi-Fi HDC 目标安装签名版：

    powershell -File scripts/build.ps1 -Install -Launch -Signed -DeviceTarget "设备的HDC目标"

产物位于 entry/build/default/outputs/default，分别为 entry-default-unsigned.hap 和配置签名后生成的 entry-default-signed.hap。

测试（使用内置 Node）：

    node tests/core.test.mjs
    node tests/state.test.mjs
    node tests/attachments.test.mjs
    node tests/permission-metadata.test.mjs
    node tests/appearance.test.mjs
    node tests/local-state.test.mjs
    node tests/workspace-http.test.mjs
    node tests/performance.mjs
    python tests/domain_entry_test.py

Python设置服务的11项测试使用Linux运行 `python3 tests/mobile_settings_test.py`，依赖fcntl；Windows本机仅运行上述Node测试。

测试从本机 SDK 读取 TypeScript 转译器，不需要下载测试依赖。状态测试运行真实客户端逻辑，只替换平台接口。审批服务端修复、部署与原生失败恢复验收见 [APPROVALS.md](docs/APPROVALS.md)。

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
