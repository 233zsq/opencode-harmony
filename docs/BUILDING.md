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

常用逻辑回归使用 IDE 配套 Node.js，测试会从本机 SDK 读取 TypeScript 转译器：

~~~sh
node tests/core.test.mjs
node tests/state.test.mjs
node tests/transcript-cache.test.mjs
node tests/workspace-http.test.mjs
~~~

其余测试位于 tests/。模拟器交互测试需要本机 fixture 和 HDC；Python 服务测试需要 Linux 与相应依赖。网页交互测试使用 Playwright，可通过 CODEX_PLAYWRIGHT 指定已安装模块路径。测试结果和截图统一保存在被忽略的 .test/。

## 文档范围

公开文档保留本文件、第三方来源和根目录更新说明。实施计划、开发记录、服务器运维笔记及历史验收材料仅保存在开发者本地，不随当前源码包分发；既有 Git 历史保持不变。
