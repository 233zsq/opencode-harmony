# 附件、消息显示与完整验收（2026-10-18）

本轮按使用者要求补齐附件与消息显示，并验证会话、待办、恢复和大内容。使用者已明确本轮只测 API26 模拟器，API24 Pad 与 API26 真机留待之后。没有调整云实例配置、代理、服务或其他项目文件。

## 附件

输入栏左侧“＋”使用原生菜单进入照片或文件选择器。附件先保留在当前对话草稿，点击发送时随消息提交；选取、预览、移除和读取重试不上传内容。未确认的请求冻结原始消息 ID 和附件字节，重试不生成新 ID。明确拒绝后恢复为可编辑草稿。

- 一次最多 4 个，合计 1 MB，连同 20000 字符文本的编码请求小于现有 2 MB 入口限制。
- 图片通过 Image Kit 压缩为 JPEG，最长边不超过 1536 像素、质量 78；原图最多 20 MB、6000 万像素。动图取首帧，透明度不会保留，适合截图和照片的模型输入，不能作为无损原图传输。
- 文件支持 PDF、UTF-8 文本和常见代码后缀。不支持 ZIP、Office 二进制文件、音视频附件；UTF-16、无效 UTF-8 和空文件给出读取错误。
- 按服务器模型的 capabilities.input 检查图片/PDF；未知能力不假定支持。文本文件按普通文本输入处理。当前内置免费 MiMo 声明图片能力，未声明 PDF 能力。
- 草稿卡片显示文件名、大小、缩略图或错误，可移除和重试。切换项目/会话保留本次运行中的附件；重启不保留未发送附件，不建立本地历史数据库。所有草稿附件合计上限 16 MB，达到上限拒绝丢弃旧草稿。
- 历史映射服务端 files，允许图片及文本预览，文本预览前 32000 字符并可复制全文；PDF 显示文件信息。支持通过原生保存器导出到选定位置，取消不写文件，失败关闭句柄并允许重试。
- 历史附件有效载荷合计保留约 8 MB；旧内容释放后仍显示文件名，点击时按消息 ID 重新读取。不会根据历史中的远程 URI 自动下载内容。较大历史页读取异常时最多拼接 8 个小页，约 2M 字符后保留游标供继续翻页；认证错误不降级重试。

文件读取/写入都处理部分完成的情况，关闭原生句柄；图片编码释放 ImageSource、PixelMap 和 ImagePacker。手机 URI、读取错误与内部附件 ID 不进入 PromptInput.files，请求仅包含 data URI 与文件名。

## 消息显示与大内容

Markdown 支持标题层级及 setext 标题、嵌套列表、任务复选框、带转义竖线/行内代码的表格与列对齐、粗体/斜体/删除线、转义字符、链接及两种代码围栏。流式未完成的围栏仍以代码显示，不把较短围栏当成结束。这里是有界的原生阅读器，不承诺完整 CommonMark、HTML、公式或脚注支持；远程图片链接不会自动联网加载。

单条回复预览前 20 万字符、最多约 400 个块；表格最多 12 列、100 行正文。达到边界显示提示，不继续创建成千上万个视图。长代码区支持横向和纵向滚动，预览前 400 行或 24000 字符，复制保留该代码块原文。大 Diff 最初显示 120 行，每次再展开 120 行，最多预览 1500 行，可收起或复制服务端返回的完整 Diff。

输入区显示正在读取、生成、停止及发送结果待核对等实际状态。核对状态是读取服务器历史/精确消息记录，不会自动重复提交任务。已有空会话直接输入，不再提供会额外创建另一会话的欢迎按钮。

## 已取得的证据

- 35 项核心、85 项协议/状态、11 项附件原生适配器故障注入、6 项审批元数据、3 项外观、5 项存储/剪贴板、6 项真实 loopback HTTP 和 2 项域名生成器，共 153 项通过。
- 4 项合成负载覆盖 50000 条消息归并、1000 页/300 条窗口、100000 行 Diff 和大 Markdown。属于 Node 测量，不是设备帧率。
- API26 原生文件选择、图片压缩、文本与图片预览、系统保存器导出、跨项目附件草稿恢复以及一次携带两个 data URI 的真实 HTTP 请求通过；本机服务不执行模型或工具。
- API26 原生 Question 的单选、多选、文本在项目切换后恢复，提交的原始值与数组正确；另一项目审批预览后仅一次带该目录范围的 once 回执通过。
- API26 会话改名、置顶/归档及重启后书签保留、移回最近列表通过；跨项目待办定位正确。
- API26 发送回执丢失后通过读取历史核对，原始请求仅一次；SSE 断流重连、回前台恢复运行任务及一次停止通过，回复经系统剪贴板粘贴结果一致。核对成功时会清除对应旧错误。
- 专用真实 HTTPS 会话使用内置免费 MiMo，正确识别合成图片左右红/蓝和短文本首行；两份附件实际入模，无工具调用。没有修改云服务或配置。
- API26 实际软键盘顶部 1705px，三行中文输入框底部 1683px、发送按钮底部 1673px，均在键盘上方。原生剪贴板复制/粘贴保留中文和 emoji；HDC 直接注入非 BMP 字符有工具限制，因此 emoji 通过文件和系统剪贴板验证。

### 模拟器大内容检查

1000 条合成消息连续读取 10 个不同的更早游标，消息窗口最多 300 条；10000 行 Diff 最初显示 120 行，点击后为 240/1500。10 条各含 800000 字节文本附件的历史超过普通 2 MB 响应上限，原生请求实际从 limit=30 恢复到 limit=1 并正确显示最新消息。

这一过程的单次内存快照为 PSS 127505 kB（约 124.5 MiB），含本轮其他原生操作累积状态，不是长期内存稳定性结论。打开历史的自动化总往返 12.647 秒，5 次滚动/布局读取往返约 1.90–1.97 秒；Diff 导航、长距离滚动和展开合计约 95 秒。全部包含 HDC 等待及人工式滚动，不能当作接口耗时、触摸响应延迟或帧率。真实大仓库、长期增长、字体放大/分屏及真机材质性能继续留待后续验收。

## 复现

使用 DevEco 内置 Node，先运行常规回归和构建，再启动本机服务：

    node tests/content-samples.mjs
    node tests/attachments.test.mjs
    node tests/workspace-server.mjs

默认仅监听 127.0.0.1:4212，通过 HDC 反向映射 4212。添加明确标识的临时 HTTP 配置，使用 fixture 账号 opencode、密码 local-test，选择 Harmony Fixture。tests/approval-smoke.mjs connect 可通过 OPENCODE_FIXTURE_PORT=4212 辅助连接。

按原生系统选择器选中合成文件后，可运行 tests/workspace-ui.mjs 的 attachments、questions-pending、bookmarks、recovery、copy、performance 和 large-attachments 场景；不同场景有明确前置状态，脚本拒绝操作非 Fixture vision 模型。keyboard-ui.mjs 不发送消息，输入后清理已知样本。文件导入/导出由系统窗口完成，不需要存储权限、root 或产品内测试后门。

真实附件联调单独使用 tests/attachments-live.mjs，必须设置专用 HTTPS 地址和 OPENCODE_ALLOW_MODEL_TEST=1。它仅创建一个验收会话，使用内置免费 MiMo 读取合成红蓝图片和短文本；不借用其他项目 Key，不修改文件，不自动批准工具操作。

结束后移除本轮 fixture 配置、反向端口及本机进程，恢复实际 HTTPS 会话。布局、截图、设备内存与受控测试记录位于忽略的 .test；签名和凭据不提交。

## 来源

OpenCode v2.0.29 固定提交的 [PromptInput](https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/schema/src/prompt-input.ts)、[附件解析](https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/session/prompt.ts)、[模型输入](https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/session/runner/to-llm-message.ts)及[模型能力](https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/schema/src/model.ts)。

平台接口以本机 API26 SDK 的 @ohos.file.picker、@ohos.file.fs、@ohos.file.photoAccessHelper 和 @ohos.multimedia.image 声明及编译/模拟器运行核验；使用 API24 可用的接口。官方入口：[文件选择器](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/js-apis-file-picker)、[照片选择器](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-photoaccesshelper-photoviewpicker)、[ImageSource](https://developer.huawei.com/consumer/cn/doc/harmonyos-references/arkts-apis-image-imagesource)。
