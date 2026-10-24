# 从源码构建

v0.1 Beta 是源码预览版，适合愿意自行构建和反馈问题的使用者。本仓库不提供开发者个人签名材料；安装到设备时请使用自己的 DevEco 调试签名。

## 环境

- DevEco Studio 26，安装对应的 HarmonyOS API26 SDK。
- 使用 IDE 配套 Node.js、JDK、OHPM 和 Hvigor，打开工程后完成依赖同步。
- 最低兼容 API24；运行环境与设备支持情况以当前 Beta 说明为准。

在 DevEco Studio 中打开仓库根目录，选择 entry / default，在 Signing Configs 中配置自己的签名，然后 Build / Run。已有同包名应用需要相同签名才能保留数据覆盖安装。

仓库里的 build-profile.json5 保留空签名模板。IDE 生成的本机签名配置、证书、密码和设备信息应仅保存在本地，提交时按文件选择变更。

## Windows 命令行

使用 IDE 默认安装目录时：

~~~powershell
powershell -File scripts/build.ps1
~~~

覆盖安装并启动到当前模拟器：

~~~powershell
powershell -File scripts/build.ps1 -Install -Launch
~~~

使用其他 DevEco 安装位置时，先设置 DEVECO_STUDIO_HOME。指定设备可加 -DeviceTarget；签名安装方式与 IDE 保持一致。脚本不卸载或清空应用数据。

构建产物位于 entry/build/default/outputs/default。当前 Release 只分发源码；生成的调试 HAP 用于自己的设备，不作为通用安装包发布。

## 连接与服务端

应用需要已有的兼容 OpenCode v2.0.29 服务。模型、Agent 和工作目录均由该服务器提供，账号和密码以服务器管理员的配置为准。

server/ 包含可选的登录、设置和流量统计扩展。scripts/ 中的部署迁移脚本绑定既有实例基线，不是通用安装器；连接兼容服务器不要求运行这些迁移脚本。

## 验证

本机或干净的 Windows/Linux 环境都可运行逻辑回归，需 Node.js 24：

~~~sh
npm ci
npm test
~~~

npm 锁定的 TypeScript 仅用于平台替身上的逻辑检查；未安装 npm 依赖时，单独执行 tests/*.test.mjs 仍可使用本机 DevEco SDK 转译器。真正的 ArkTS 编译、原生加密和设备布局需通过 DevEco 与设备另外验证。

网页检查使用 Python 3.12、Flask 和 Playwright，从仓库模板自动生成隔离页面：

~~~sh
python -m pip install -r server/account/requirements.lock
npx playwright install chromium
npm run test:web
~~~

可通过 PYTHON_BINARY 指定 Python、EDGE_BINARY 指定已有浏览器。Windows 默认可复用本机 Edge，其他环境使用 Playwright 的 Chromium。测试输出自动写入被忽略的 .test/。

GitHub Actions 在所有 PR、main 提交和版本标签上自动运行 Windows/Linux 逻辑回归、Linux Python/真实 Nginx 测试和网页浅深色检查。所有服务测试使用 loopback 与临时数据，不读取线上账号、签名或私有服务器配置。模拟器脚本和真实服务脚本需按各自前置条件单独运行。

## 新功能的模拟器检查

`tests/search-drafts-ui.mjs` 的 search / paging / draft / offline / clear 模式仅用于已连接到 4216 loopback fixture 的 API26 模拟器；先运行 fake-server 并准备 cache-history 种子，paging 模式会切换到 360 条的导出种子会话，使用设备到本机的临时端口映射。offline 模式前停止 fixture，清理模式前恢复服务；结束后移除临时连接和映射。脚本不发送真实模型任务，不用于生产账号。

会话查找只覆盖当前加载的最多 300 条消息，思考和工具默认不参与；附件仅搜索名称。文本草稿最多 20000 字符、100 份，复用本机加密缓存和 200 MiB 逻辑上限；附件、审批及结果待核对的发送请求不会持久化为草稿。恢复文本后仍需用户检查并手动发送，缓存或存储失败不会阻断在线功能。

## 文档范围

公开文档保留本文件、第三方来源和根目录更新说明。实施计划、开发记录、服务器运维笔记及历史验收材料仅保存在开发者本地，不随当前源码包分发；既有 Git 历史保持不变。

## 常用提示词验收

入口为“更多功能 → 常用提示词”或输入栏加号。提示词为设备本地内容，独立使用加密 S3 数据库；最多 50 条，每条名称 60 字符、正文 20000 字符。清理会话缓存、移除服务器不会删除这些手工保存的提示词，可在编辑页逐条删除。插入只追加到当前输入，不上传提示词库或自动发送；合并超过输入限制时保留原文并提示。

`node tests/prompt-templates.test.mjs` 覆盖数据边界、读写失败、重启、重复操作和真实 SQLite 原子写入。API26 原生验收脚本为 `node tests/prompt-templates-ui.mjs`，只允许使用本机 loopback 测试连接，不调用真实 Agent。

## 消息收藏与附件预览验收

消息正文旁的星标或“收藏”按钮保存快照；“更多功能 → 消息收藏”可搜索、查看、复制、返回原会话和取消收藏。每个服务器地址与账号最多 100 条，每条正文最多 100000 字符，超过限制会拒绝而不是截断。附件仅保存名称、类型和大小，思考与工具日志不进入收藏，不会自动下载附件。收藏使用原生加密数据库的独立表，不受 200 MiB 会话缓存淘汰或清理影响；移除连接或变更身份会隐藏原账号收藏，重新添加相同地址与账号可恢复；认证或证书失败时立即隐藏当前列表并停止读写，但不会因临时校验失败误删手工收藏。取消收藏是删除副本的明确入口。

输入栏中的附件可打开完整预览页，切换、移除所选附件并保留已有文本。图片缩放与拖动只改变显示；PDF 使用从 API12 起提供的 PDF Kit，逐页渲染、最多 2000 页，位图最长边 1536 像素。临时文件在写入私人内容前取消文件名链接，仅保留进程内文件描述符，关闭或进程退出即释放。PDF 组件不可用、文档加密或损坏时保留保存文件入口。当前 API26 模拟器没有 PDF 原生组件：缺失能力的提示与保存入口已验收，真正的 PDF 页绘制和翻页仍需在支持该组件的设备上验收。未增加裁剪或文件改写。

`node tests/bookmarks-previews.test.mjs` 检查快照边界和 PDF 资源生命周期；原生脚本为 `node tests/bookmarks-previews-ui.mjs preview`、`user`、`composer`、`composer-fork`、`restart` 和 `offline`，只针对已选择的 loopback fixture。已知不提供 PDF 组件的模拟器可显式设置 `ALLOW_UNSUPPORTED_PDF=1` 验收缺失能力路径；脚本会输出 SKIP，不能据此声称真实 PDF 渲染通过。`offline` 模式需要先停止本机 fixture，随后验证离线收藏并移除本轮收藏。发送前预览验收使用脚本生成的两份 `ocp24.png`、`ocp24.pdf` 测试文件，清理时只删除这两份测试文件。

当前模拟器的系统文件选择器在进入 Download 时发生系统文件管理器崩溃（`libarkdata_db_core.z.so`）。`composer-fork` 改用已有的“编辑并分叉 → 沿用附件”载入本机 fixture 的三种附件，验收发送前预览；只创建测试分支，不调用模型。系统文件选择器的完整导入流程仍需后续设备复核，不可用本项替代。

向模拟器部署测试文件时，HDC 的本机源路径应使用完整 Windows 绝对路径，目标使用 Download 中的完整文件名；相对源路径可能保留父目录结构。只清理本轮生成的测试文件，保留已有下载文件与服务器配置。
