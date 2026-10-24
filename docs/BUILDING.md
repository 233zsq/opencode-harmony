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
