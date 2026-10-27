<img src="AppScope/resources/base/media/opencode_mark_v1.png" width="88" alt="OpenCode Harmony 图标">

# OpenCode Harmony

把你的 OpenCode 工作空间带到鸿蒙设备上。

一个使用 ArkTS / ArkUI 构建的原生远程客户端。连接自己的 OpenCode 服务器，在手机或平板上继续对话、查看代码、处理问答和审批。

**[v0.1 Beta 3 · 测试版](https://github.com/233zsq/opencode-harmony/releases/tag/v0.1.0-beta.3)** · [更新说明](CHANGELOG.md) · [问题反馈](https://github.com/233zsq/opencode-harmony/issues)

## 可以做什么

- **流畅对话**：流式回复、Markdown、代码与表格；思考完成后自动收起，工具详情点击查看。
- **选择模型**：模型搜索、启用与喜爱、最近使用，以及服务器支持的思考档位。
- **管理会话**：项目与历史搜索、对话内容查找与定位、消息收藏、置顶、归档、分叉、编辑重发和导出。
- **查看工作**：文件浏览、Git Diff、问答表单与权限审批。
- **常用提示词**：本机加密保存常用任务描述，搜索、编辑后插入输入栏，保留已有文字并手动发送。
- **发送附件**：图片、文本和 PDF；发送前可预览、切换和移除，图片支持缩放，PDF 页预览取决于设备系统能力。输入能力取决于所选模型。
- **原生体验**：浅深色、沉浸光感、任务提醒，以及加密文本草稿、缓存与离线只读。

## 开始使用

本次提供源码和未签名 HAP，需使用自己的 DevEco 签名后安装。未签名包不能直接安装；含设备授权信息的自用调试签名包不公开分发。

1. 从 [Releases](https://github.com/233zsq/opencode-harmony/releases) 下载源码，按[构建说明](docs/BUILDING.md)安装到设备。
2. 准备兼容 **OpenCode v2.0.29** 的服务器及其 API 账号、密码。
3. 在应用的“服务器连接”中填写 HTTPS 地址与凭据。
4. 选择项目、会话和模型，开始使用。

模型与 Agent 在服务器上运行。客户端不附带模型 Key；服务器 API 密码、模型 Key 与 SSH 密码是不同的凭据。

当前仓库只维护鸿蒙客户端及客户端测试。账号服务、管理网站和部署工具已独立维护，构建或连接客户端不需要访问其私人仓库。服务器接口与可选扩展要求见[服务端兼容说明](docs/SERVER-API.md)。

## Beta 说明

- 最低兼容 **API24**，目标 **API26**；沉浸光感按系统能力启用。
- API26 模拟器已覆盖主要流程；API24 真机、部分附件与搜索流程仍需进一步验收。
- 当前以 OpenCode v2.0.29 协议为基线，其他服务端版本可能不兼容。
- 一次最多 4 个附件，合计 1 MiB；任务提醒受系统后台与进程存活状态限制。
- 连接凭据保存在系统安全资产；本机加密缓存默认上限 200 MiB，可在“更多功能 → 存储与流量”清理。完整历史由服务器保存。

反馈问题时，请提供系统版本、复现步骤和脱敏截图，并隐藏密码、模型 Key 与私人对话。

## 开源与致谢

[Apache-2.0](LICENSE)。协议适配与同步设计参考 [opencode-mobile](https://github.com/alvarolorentedev/opencode-mobile)，详见[第三方来源](docs/THIRD_PARTY.md)。

OpenCode Harmony 是独立社区客户端，与 OpenCode 官方没有隶属关系。
