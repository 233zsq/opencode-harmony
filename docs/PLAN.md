# OpenCode Harmony 开发计划

日期：2026-10-15
状态：已确认并开始实施。当前结果与未完成验收见 PROGRESS.md；现场事实章节保留开发前调查快照。
目标仓库：https://github.com/233zsq/opencode-harmony
本地工程：D:\projects\opencode_harmony

## 1. 产品目标与已确认决策

使用 ArkTS + ArkUI 开发个人使用的 HarmonyOS 原生 OpenCode 客户端。代码、模型调用和 Agent 工具运行在用户管理的服务器上，手机负责发起任务、查看进度、回答问题、审批操作和审查修改。

已与用户确认：

- 第一版个人使用，允许配置多个 OpenCode 服务器。
- 代码审查只读：查看文件、修改记录和 Diff；代码修改交给 Agent。
- 完整历史保留在服务器，本机保存连接配置与最近项目/会话位置，不承诺离线阅读完整聊天。
- 采用 alvarolorentedev/opencode-mobile 作为主要参考，ArkUI 界面重新开发。
- 既有服务器上还有其他项目，必须保持其代码、配置、数据和运行服务不变。
- 用户的域名正在备案；域名和 HTTPS 公网接入不阻塞本地开发。
- 最低兼容 API 24，编译及目标 SDK 为 26.0.0；新增 API 按实际最低版本判断能力并提供降级。

已确认的隔离方向（公网接入待域名就绪）：

> 推荐为本应用部署专用 OpenCode 实例，使用独立配置、凭据、数据和工作目录，以及独立访问入口。当前已有的 OpenCode 实例仅作为版本和协议调查依据，不默认直接共享它或重启它。服务器部署开始前须明确入口、端口、证书、实例隔离和对既有服务的影响。

第一版不包含手动代码编辑、Git 提交/分支管理、完整终端、语音、应用市场发布及离线任务执行。这些能力不影响本次八项功能验收。

## 2. 当前现场事实

### 2.1 鸿蒙工程

| 项目 | 已核验结果 |
| --- | --- |
| 工程类型 | Stage 模型，单 entry 模块，Hello World ArkUI 模板 |
| 包名 | com.example.opencode_harmony，个人开发阶段保留 |
| DevEco Studio | 26.0.0.851 |
| SDK | 实际 compile 26.0.0，target 26.0.0，compatible 6.1.1(24) |
| 工具链 | SDK toolchains 26.0.0.105，Hvigor 6.26.8 |
| 依赖 | 无业务第三方依赖；现有 Hypium/Hamock 为模板测试依赖 |
| 网络权限 | module.json5 尚未声明 ohos.permission.INTERNET |
| 签名 | signingConfigs 为空，尚未确认真机签名 |
| 构建 | 已有 sync/init/clean 记录，未发现成功编译 HAP 的证据 |
| 版本管理 | 本地尚无 .git；目标 GitHub 仓库只读核验无 refs |
| 设备声明 | phone/tablet/2in1；第一版优先 Phone 验收 |

工程没有显式声明 ArkTS 语言版本，不因安装 SDK 26 就假定使用 ArkTS 1.2。初期沿用模板支持的语言及构建方式，先通过编译验证。

DevEco 内置 Node、OHPM、Hvigor 和 HDC 已安装；命令行构建优先使用这些工具的已验证绝对路径，避免混用系统 Node 或其他工程版本。

### 2.2 服务器

本轮已通过 SSH 做只读检查，没有部署、启动/停止服务、改配置或改业务数据。

- 现有 OpenCode 二进制版本为 v2.0.29。
- 当前 OpenCode 仅监听 127.0.0.1:49374，不能把此地址直接作为手机远程连接地址。
- GET /api/info 返回 401，并声明 HTTP Basic 认证；API 凭据尚未取得。
- SSH 用户与 OpenCode API 账号属于不同认证体系，不能互相代用。
- 现有 Nginx 的 80/443/8443 入口服务其他项目，已检查配置未发现对 49374 的代理。
- /global/health、/doc 返回的是 HTML Web 页面，不是所预期的 API JSON，不能当作连接成功依据。
- 当前端口是否固定、现有实例是否作为长期服务管理，尚未确认。

实际服务器 IP、SSH 私钥、API 密码、模型密钥和签名证书不写入工程或 Git。此公开计划仅记录技术事实。

## 3. 八项功能的第一版边界

| 功能 | 交付内容 |
| --- | --- |
| 连接服务器 | 多连接配置、URL/子路径规范化、独立 API 认证、版本识别、错误分类、连接状态、凭据安全保存 |
| 项目与会话 | 浏览服务端已有项目/目录、查看文件、新建会话、历史分页、恢复最近会话 |
| Agent 聊天 | 发送与中断、流式正文、服务端实际返回的推理内容、工具状态、Markdown 与代码块 |
| Question 交互 | 适配 V2 Form，支持所需单选、多选、自定义文本；pending/submitting/answered/cancelled/error |
| 操作审批 | 展示服务端给出的请求类型和范围，单次批准/拒绝；提交状态和重复点击保护 |
| 模型切换 | 获取服务器可用 provider/model，选择和恢复会话模型；MiMo/DeepSeek 以服务端实际配置为准 |
| 代码审查 | 修改文件列表、工作区/会话 Diff、逐文件统一格式展示及历史加载 |
| 断线恢复 | 退避重连、前台恢复、历史及 pending 同步、消息去重、旧连接响应隔离 |

“项目浏览”指 OpenCode 服务器可访问的工作区；不默认添加 GitHub 仓库检索、clone 或任意磁盘扫描。

只展示服务端和模型实际返回的 reasoning，不制造推理文本；不支持该字段的模型正常展示正文与工具事件。

## 4. 架构与模块边界

保持一个 entry 模块，先按职责组织代码，避免在功能未验证前拆成多个工程模块。

拟定目录：

- common/model：客户端模型、明确的可序列化字段、状态枚举。
- data/opencode：版本/能力探测、V2 协议适配、请求与响应转换。
- data/network：普通 HTTP、SSE 传输、认证头、UTF-8 增量解码、错误映射。
- data/storage：普通连接设置、最近项目/会话位置、安全凭据引用。
- domain：会话同步、消息归并、Question/审批提交、重连调度。
- presentation/store：连接、项目、会话与聊天的可观察状态。
- components：消息、工具、推理、Question、审批、Markdown、Diff 等 ArkUI 组件。
- pages：连接管理、项目/会话、聊天和审查页面。
- tests 与本地 fixture 服务：协议样本、网络故障、竞态与集成场景。

界面不拼 endpoint、不解析 SSE，也不直接决定历史覆盖规则。业务层只依赖协议适配接口，不直接绑定参考项目的 React hooks 或 JS SDK。

初版首先保证 V2.0.29 实际可用。允许多服务器不意味着承诺支持任意 OpenCode 旧版：连接时明确展示可验证的版本/能力，不支持的版本给出可理解提示。V1 兼容留在独立适配边界，未纳入第一版交付。

### 4.1 鸿蒙平台实现

- 网络使用 Network Kit；普通 HTTP 与 requestInStream 的认证由同一配置生成。
- 本地 SDK 明确说明 HTTP 拦截器不支持 requestInStream，不依赖该拦截器自动补 SSE 认证头。
- 使用增量 TextDecoder 保存跨网络包的 UTF-8 残字节。
- SSE 按完整事件帧解析，支持 LF/CRLF、多行 data、注释/心跳与未知事件；设置单帧/缓存上限。
- Preferences 保存地址与最近位置等非秘密信息；密码/Token 使用经验证的系统安全资产接口保存。
- 退后台不承诺永久保持网络连接；Agent 继续在服务器运行，回前台重新建立连接并同步。
- 第一版采用原生 ArkUI 渲染正文、代码块和 Diff；Markdown 组件/解析器先做 API 24 兼容与性能验证，保留明确降级。
- 长消息分块、长列表懒加载、稳定 ID、Markdown 缓存和自动滚动策略在流式阶段一起处理。

## 5. 参考代码移植计划

主要来源：https://github.com/alvarolorentedev/opencode-mobile
核验提交：cd869f9c75d8833a6fd644ba71753e2d4e1b7af9
核验 package 版本：1.0.73
许可证：Apache-2.0

已阅读下列源码和测试，尚未运行其测试或证明对现场服务器兼容。

| 参考文件 | 可复用知识/候选逻辑 | 鸿蒙侧处理 |
| --- | --- | --- |
| lib/opencode/format/window.ts | message ID 合并、较旧页去重、不变记录引用保留 | 优先移植为 ArkTS 纯逻辑 |
| lib/opencode/v2/mappers.ts | V2 Permission/Form 及答案字段映射 | 按现场 schema 校验后选择性移植 |
| lib/opencode/client/interactions.ts | pending 获取、回复及部分读取失败语义 | 重写网络调用，保留状态语义 |
| components/chat/chat-diff.ts | patch 行号、加删行和上下文折叠 | 提取纯解析逻辑，移除主题耦合 |
| providers/opencode-provider-utils.ts | 防止轮询将 retry 状态错误改为 idle | 迁移行为与回归测试，重新验证时间规则 |
| providers/use-opencode-realtime.ts | 重连、认证失败停重试、前台恢复、轮询与完整同步排队 | 参考行为，使用鸿蒙生命周期与网络重写 |
| providers/use-transcript-state.ts | 历史分页、尾页桥接、有限窗口、连接身份校验 | 按 ArkUI store 重写 |
| providers/services/session-service.ts | V2 cursor 分页、结果排序、请求合并、Diff 目标 | 核验 API 合约后重写 |
| tests/fake-opencode/fixtures.mjs | 原生 V2 Form/Permission、模型及 Markdown 样本 | 整理匿名测试 fixture |
| tests/fake-opencode/server.mjs | suppress/stall/disconnect、交互首次失败等控制 | 选择性移植为本机测试服务 |
| tests/vitest/record-preservation.test.ts、audit-races.test.ts | 信息更新、部分失败、迟到响应、切换连接竞态 | 移植测试场景 |

复制或改写参考代码时记录来源仓库、固定 SHA、原路径、修改内容；保留 Apache-2.0 许可证和原有声明，维护 THIRD_PARTY_NOTICES 或来源清单。不要沿用参考 App 的品牌、图标或发布身份。

纯 TypeScript 也必须通过 ArkTS 语法与类型检查。React、Expo、浏览器流、动态对象及具体 JS SDK 不能整体直接引入。

## 6. 同步、交互与错误处理的关键规则

1. 所有状态至少绑定 server identity、location/project、sessionID；异步请求再绑定 generation。切换连接、项目或会话后，旧请求的迟到响应不得覆盖新状态。
2. 消息按服务端稳定 ID 归并；optimistic 消息与服务端消息明确关联，不按角色或文本相同就删除。
3. 区分完整快照与增量事件。不能把完整正文重复追加为 delta，也不能在历史请求和流式更新交错时重复渲染。
4. V2 全局事件流不保证断线重放。重连后补消息、会话状态、Question/Form、permission 和必要的 Diff；已有同步正在运行时排队补一次完整同步，不能直接丢弃。
5. 消息分页保留 cursor 和排序语义。活跃会话更新尾部，旧页按需加载，限制内存窗口。
6. pending 成功返回空列表可清空旧状态；获取失败必须保留旧 pending 并展示失败，不能视作“已经全部回答”。
7. 提交 Question/审批后遇到超时或断线，先查询服务端确认是否已处理，再允许再次提交；其他客户端已处理的请求应同步关闭。
8. 对发送消息的“结果未知”状态进行核对，不自动重复发送可能已被服务器接受的任务。幂等字段必须先验证服务器支持。
9. 401/403 停止自动重试并提示修正认证；429/5xx/网络错误按类别处理，不因一次失败就切换协议。
10. 活跃集合不包含某会话，不足以证明它已完成；还要结合 retry、inbox、pending Form/permission 和服务端会话状态。
11. 暂不在线下排队自动提交消息、Question 或审批；恢复后先同步，再由用户继续操作。
12. 大文件/Diff 使用行数与字节上限、按需加载及截断提示，防止阻塞 UI。

## 7. 分阶段实施与完成条件

### M0：工程与协议基线

工作：
- 初始化本地 Git 并关联已确认的目标仓库，保留现有模板。
- 核查 ignore，排除本地工具路径、构建缓存、签名文件和所有凭据。
- 用 DevEco 内置工具编译模板，修复真实阻塞，确认运行默认页。
- 建立 API 24/26 兼容测试目标；补齐必要网络权限。
- 固定参考 SHA，整理来源清单与核心匿名 fixture。
- 针对 V2.0.29 核验可访问合约；无认证时通过固定 fixture 开发，并明确尚未完成实服验证。

完成条件：
- 可复现的编译命令与构建结果；有模拟器/真机默认页运行证据。
- 目标仓库能保存无秘密的工程。
- 协议适配边界、fixture 与版本约束已确定。

### M1：连接、认证与流式传输

工作：
- 多服务器配置、地址/子路径处理、连接测试和版本显示。
- 安全保存认证，普通 HTTP 和 SSE 一致注入。
- 实现增量解码、SSE parser、取消、退避与错误分类。
- 使用本地 fake server 验证，建立只用于开发的访问路径。

完成条件：
- 连接成功与认证失败有明确区别；HTML 200 不会被误判为 API 成功。
- 中文/emoji 跨包、半帧、多帧、多行 data、心跳与异常大小测试通过。
- 切换连接后无残留流或迟到状态污染。

### M2：项目、会话与聊天闭环

工作：
- 服务端项目与目录浏览、会话列表/新建/恢复、历史分页。
- 发送、中断、流式正文、推理和工具卡片。
- 初版 Markdown/代码块，长消息与自动滚动处理。
- 稳定 ID 归并、历史/事件竞态保护、前台恢复同步。

完成条件：
- 能完成“选项目 → 新建会话 → 发消息 → 流式显示 → 退出后恢复”。
- 同一消息不因 SSE、轮询或恢复历史重复渲染。
- 流中切换服务器/项目/会话不会显示其他上下文的数据。

### M3：Question、操作审批与模型

工作：
- V2 Form 的单选、多选、自定义文本与字段映射。
- 回答/审批状态机、取消、失败和服务端已处理状态。
- 单次批准/拒绝及防重复提交。
- 获取可用模型、按服务端 ID 切换；验证已配置的 MiMo/DeepSeek 或其他可用模型。

完成条件：
- 回答 Question 和批准/拒绝操作后 Agent 能按服务端语义继续或结束。
- 断线重连后 pending 仍正确；提交失败不会误显示成功。
- 模型变化与服务端会话状态一致，不硬编码营销名称为 ID。

### M4：只读代码审查与恢复完善

工作：
- 文件列表/内容、修改记录、会话/工作区 Diff 的明确来源。
- unified Diff 行号、加删行、上下文折叠和大文件保护。
- 补齐丢事件、静默连接、服务重启、长时间后台恢复。
- 保持完整历史在服务器，本机仅持久化配置和最近位置。

完成条件：
- Diff 与服务端结果一致，空 Diff 和读取失败可区分。
- 人为断网/切网/退后台后，消息、工具、Question/审批和修改列表能恢复一致。
- 不存在只重连但历史/待办卡片未同步的状态。

### M5：专用服务接入与验收交付

工作：
- 在最终确认的隔离方案下准备专用实例与 HTTPS 入口。
- 明确模型凭据、API 凭据、工作目录和服务数据的归属。
- 验证实服协议、双客户端交互及 API 24/26 行为。
- 完成签名与真机 HAP 安装，记录交付步骤和已知限制。
- 运行必要测试、ArkTS 检查、构建及 git diff --check，筛查秘密后推送。

完成条件：
- 真机通过八项功能验收，有可复现证据。
- 既有项目的进程、端口、代理和数据保持不变。
- 工程、Plan、第三方来源、构建/安装和服务器连接说明可追踪。
- 若域名尚未就绪，标记公网实服验收待完成，不将本地测试冒称公网交付。

## 8. 服务器共存与接入计划

本轮只记录方案，部署为后续独立阶段。

推荐：
- 专用 OpenCode 实例，不覆盖或升级现有实例及其配置。
- 独立配置、状态、凭据和工作目录；实际支持的隔离参数先按固定版本验证。
- 绑定 localhost 的专用端口，经独立 HTTPS 入口访问。
- 首选不占用已有 80/443/8443 的专用 TLS 端口；具体端口部署前检查。
- 域名、证书签发、云安全组和服务管理明确后再落地；不默认修改共享 Nginx。
- 若用户明确选择在现有反向代理增加独立站点，需要单独说明共享配置及 reload 影响后确认。
- 上线前后对现有监听/进程和已知健康入口做对照，准备仅撤销本应用新增内容的回滚方案。

开发阶段：
- fake server 仅运行在开发电脑，不部署到共用服务器。
- 如需要 SSH 本地转发，临时转发只作为开发电脑通道，不会自动让手机获得公网访问。
- 模拟器/真机到开发电脑的地址、端口与认证按实际网络验证；不把 localhost 当手机到远端服务器的地址。
- 不在 App 中携带 SSH 私钥，不跳过 TLS 证书验证，不公开无认证的 Agent API。

## 9. 验证矩阵

| 场景 | 必须验证的结果 |
| --- | --- |
| 中文/emoji 分散到多个字节包 | 无乱码、无丢字符 |
| 一次接收多帧/半帧/多行 data | 只在完整事件时更新，未知事件可跳过 |
| SSE 与历史/轮询同时到达 | 正文不重复、不回退，元数据更新不丢 |
| 切换服务器/项目/会话 | 旧请求无法污染当前状态 |
| 发送已被接受但响应丢失 | 不自动重复执行任务 |
| Question/审批首次失败或响应丢失 | pending 保留，核对服务器再重试 |
| 其他客户端回答/批准 | 本机同步关闭已处理请求 |
| 401/403、429、5xx、HTML 200 | 错误分类正确，无错误协议降级 |
| 网络中断、事件静默、服务重启、回前台 | 完整补同步，状态一致 |
| 长会话/大文件/Diff | 有界内存、滚动可用、超限提示 |
| API 24 与 API 26 | 核心功能均可用，新增能力按条件降级 |
| 多实例同主机 | 本应用操作不改变其他项目的数据或运行状态 |

## 10. 执行与交付规则

- 完成本计划确认前，不开始业务实现或服务器部署。
- 分阶段交付可运行增量；每阶段记录实际构建、测试与设备结果。
- 不把模板、截图、假数据或 fake server 结果当作实服完成。
- 优先迁移有边界测试的纯逻辑，平台功能原生实现；不为了复用而引入完整 RN 运行时。
- 版本提交采用英文 Conventional Commit 前缀及中文说明，例如 feat: 增加服务器连接与认证。
- 公共仓库不包含运维密钥、模型密钥、认证信息、签名材料和业务聊天内容。
- 开始实现前最后确认服务器隔离方案；域名就绪后再确定可访问 URL、端口和证书。

## 11. 证据与参考资料

本地证据：
- build-profile.json5：target/compatible、签名和模块配置。
- AppScope/app.json5：包名。
- entry/src/main/module.json5：设备类型、Ability、权限。
- entry/src/main/ets/pages/Index.ets：模板页面。
- .hvigor/cache/meta.json：已使用工具链版本。
- 已安装 SDK 类型定义：HTTP requestInStream/dataReceive/dataEnd、流式 TextDecoder、安全资产接口。

公开资料：
- OpenCode V2 API：https://opencode.ai/v2/docs/api
- OpenCode V2 Provider：https://opencode.ai/v2/docs/providers
- 鸿蒙构建版本配置：https://developer.huawei.com/consumer/cn/doc/HarmonyOS-Guides/ide-hmos-hvigor-build-profile-app
- 固定参考源码：https://github.com/alvarolorentedev/opencode-mobile/tree/cd869f9c75d8833a6fd644ba71753e2d4e1b7af9
- 参考许可证：https://github.com/alvarolorentedev/opencode-mobile/blob/cd869f9c75d8833a6fd644ba71753e2d4e1b7af9/LICENSE

公开文档可能跟随新版更新；实现时以固定服务器版本及实际响应合约为准。
