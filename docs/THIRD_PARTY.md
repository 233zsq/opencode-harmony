# 第三方与协议来源

## 主要参考客户端

- 仓库：https://github.com/alvarolorentedev/opencode-mobile
- 固定提交：cd869f9c75d8833a6fd644ba71753e2d4e1b7af9
- 核验版本：1.0.73
- 上游许可：Apache-2.0
- 上游许可文件：https://github.com/alvarolorentedev/opencode-mobile/blob/cd869f9c75d8833a6fd644ba71753e2d4e1b7af9/LICENSE

本项目参考其message ID归并、V2 Form/Permission映射、完整重连同步、部分失败保留状态和异步竞态测试设计；当前实现重新编写为鸿蒙平台代码，没有打包React Native、Expo或上游JS SDK运行时。

核验过的原路径：
- lib/opencode/format/window.ts
- lib/opencode/v2/mappers.ts
- lib/opencode/client/interactions.ts
- components/chat/chat-diff.ts
- providers/opencode-provider-utils.ts
- providers/use-opencode-realtime.ts
- providers/use-transcript-state.ts
- tests/fake-opencode/server.mjs
- tests/vitest/record-preservation.test.ts
- tests/vitest/audit-races.test.ts

后续若直接复制或改写上游文件，应保留其原有声明，标注来源路径、固定SHA和修改内容，并核验上游NOTICE要求。

## OpenCode协议

- 官方v2.0.29提交：042d0832f5f3a73eaa039a58a7d565776f6d4290。
- OpenAPI：packages/protocol/openapi.json。
- 关键实现：packages/schema/src/form.ts、packages/core/src/form.ts、packages/core/src/session/inbox.ts、packages/server/src/handlers/event.ts。
- 官方固定源码：https://github.com/anomalyco/opencode/tree/042d0832f5f3a73eaa039a58a7d565776f6d4290

请求体、响应envelope、scope、幂等消息ID及SSE字段按该版本核验，不依据可能漂移的文档页面直接推断兼容。

## 平台

HarmonyOS SDK及开发工具由使用者按华为条款安装，本仓库不重新分发SDK、签名材料或工具二进制。
