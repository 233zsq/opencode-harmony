# OpenCode Harmony

基于 ArkTS + ArkUI 的 HarmonyOS 原生 OpenCode 远程客户端。最低兼容 API 24，编译/目标 SDK 26.0.0；协议以 OpenCode v2.0.29 为基线。

代码和 Agent 在用户自己的 OpenCode 服务器运行。本机保存连接配置、最近会话位置以及系统安全资产中的认证信息，完整聊天历史保留服务器。

## 当前实现

- 多服务器配置、HTTP Basic 认证、连接与错误状态。
- 项目/目录、创建和恢复会话、历史分页。
- SSE 流式正文、推理与工具卡片，原生 Markdown 和代码块。
- V2 Question/Form：单选、多选、文本、条件字段、默认值与类型校验。
- 单次批准/拒绝操作及提交状态。
- 动态模型目录和会话模型切换。
- 只读文件浏览与 Git Diff。
- 退避重连、回前台同步、消息 ID 去重与迟到响应隔离。

已在 HarmonyOS 7 / API 26 本地模拟器构建、安装并启动。模拟器中的真实 MiMo 对话已通过端到端验证，另有30项回归测试与本机fixture交互验证。详细完成状态与限制见 [PROGRESS.md](docs/PROGRESS.md)，实施方案见 [PLAN.md](docs/PLAN.md)。

当前尚未完成 API 24 设备验收、真机签名与公网 HTTPS 接入。模型可用性取决于服务器提供商配置；本项目不打包模型密钥。

## 开发环境

- DevEco Studio 26.0.0.851（内置 SDK 26.0.0.105）。
- 使用 IDE 内置 Node/JDK/OHPM/Hvigor。默认安装目录为 C:\Program Files\Huawei\DevEco Studio；可用 DEVECO_STUDIO_HOME 指定其他目录。
- 工程保持 Stage 单 entry 模块，无额外业务 npm/ohpm 依赖。

构建：

    powershell -File scripts/build.ps1

构建并安装启动到当前本地模拟器（默认 HDC target 127.0.0.1:5555）：

    powershell -File scripts/build.ps1 -Install -Launch

模拟器可安装 unsigned HAP；真机需在 DevEco Studio 登录并配置自己的调试签名。产物为 entry/build/default/outputs/default/entry-default-unsigned.hap。

测试（使用内置 Node）：

    node tests/core.test.mjs
    node tests/state.test.mjs

测试从本机 SDK 读取 TypeScript 转译器，不需要下载测试依赖。状态测试运行真实客户端逻辑，只替换平台接口。

## 本机联调服务

tests/fake-server.mjs 是明确标识的本地测试 fixture，不是生产 OpenCode，也不执行真实 Agent。

    node tests/fake-server.mjs

默认监听 PC 的 127.0.0.1:4210。使用 HDC 反向映射：

    hdc -t 127.0.0.1:5555 rport tcp:4210 tcp:4210

App 地址填写 http://127.0.0.1:4210，账号 opencode，测试密码 local-test，并明确开启可信 HTTP 选项。这组凭据仅适用于随代码提供的本机测试服务，不是任何真实服务器凭据。

模拟器首次输入可能需要使用者完成输入法初始化。之后可运行 tests/emulator-smoke.mjs；截图与布局保存在被 Git 忽略的 .test 目录。

## 真实服务器连接

生产使用经验证的 HTTPS URL及 OpenCode API 凭据。SSH 账号和 API 账号不是同一认证体系；v2.0.29 的 Basic 用户名是 opencode。

备案期间可经开发电脑的 SSH 本地转发与 HDC rport 联调；这条通道依赖开发电脑，不等于手机已经拥有公网访问入口。独立实例的目录和运维边界见 [SERVER.md](docs/SERVER.md)。

scripts/provision-server.sh 是供核验后使用的独立实例部署脚本。它拒绝覆盖已有单位或抢占端口；不会运行修改默认后台服务的 opencode service set。

## 源码结构

- entry/src/main/ets/domain/Core.ts：纯逻辑，SSE/归并/Form/Markdown/Diff。
- entry/src/main/ets/data：Network Kit 协议适配与安全存储。
- entry/src/main/ets/presentation/AppStore.ets：业务状态和同步。
- entry/src/main/ets/components：原生 UI 组件。
- entry/src/main/ets/pages/Index.ets：连接、项目、聊天和审查。
- tests：协议与竞态回归、本机 fixture、模拟器交互。
- docs：计划、验证状态、服务器边界及第三方来源。

## 参考与许可

主要参考 [alvarolorentedev/opencode-mobile](https://github.com/alvarolorentedev/opencode-mobile) 的协议适配和同步设计，固定提交与来源见 [THIRD_PARTY.md](docs/THIRD_PARTY.md)。本项目使用 Apache-2.0；不使用参考应用的品牌或发布身份。

OpenCode Harmony 是独立客户端，与 OpenCode 官方没有隶属关系。
