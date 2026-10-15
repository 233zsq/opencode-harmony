# 手机端提供商配置：OpenCode v2.0.29

核验日期：2026-10-15。固定官方提交 `042d0832f5f3a73eaa039a58a7d565776f6d4290`，依据协议、服务端、Core 和 Web 客户端源码；未读取服务器已有模型密钥。本文记录协议事实和实现建议，不代表所有认证方式已在真机完成登录。

## 官方 V2 接口

`GET /api/integration?location[directory]=...` 返回 `{ location, data: Integration.Info[] }`。每项为 `{ id, name, methods, connections, metadata? }`。`GET /api/provider` 返回当前可用提供商，而 integration 列表用于发现尚未连接的认证入口。不要将 V1 的 `/auth/:providerID` 或 provider config PATCH 请求用于本版本。[协议与 SDK][integration-api] [sdk]

认证方法由服务器声明，不写死下拉列表：

| type | 字段 | 手机行为 |
| --- | --- | --- |
| key | `label?`, `form?`，没有 methodID | 密码输入框收集 API Key；同时显示附加表单 |
| oauth | `id`, `label`, `form?` | 收集表单，启动认证，打开浏览器，轮询状态或输入授权码 |
| external | `id`, `label`, `form?` | 收集外部凭据源参数并连接；不是在手机启动服务器 CLI |
| env | `names: string[]` | 显示服务器环境变量来源；手机不能直接设置服务器环境变量 |
| command | `id`, `label`, `command: string[]` | 在服务器执行预定义认证命令，需要单独设计支持；不当作本地手机命令 |

`form` 使用与 Question 一致的 Form.Field：string/options、number/integer、boolean、multiselect、hidden/default、when。条件为 AND；inactive 字段不能提交；保留原生 bool/number/string[]，不能全部转成字符串。`external` 字段只带 URL/说明，不属于普通答案输入。[表单 schema][form-schema]

### API Key 与外部源

```http
POST /api/integration/{integrationID}/connect/key?location[directory]=...
Content-Type: application/json

{"key":"user-entered-key","answer":{"optional-field":"value"},"label":"工作账号"}
```

成功为 **204，无 JSON 响应体**。answer、label 均可省略。只有该 key 方法声明 form 才可提交非空 answer。服务端创建并激活新的 credential；保存成功不代表额度、模型或 API Key 的实际调用已经验证。不能对超时自动重新 POST，以免重复创建账号；先刷新安全连接列表，让用户确认是否已保存。[认证实现][integration-core]

external 对应 `POST /api/integration/{id}/connect/external`，请求体 `{ "methodID": "server-declared-id", "answer": {}, "label": "可选" }`，成功 204。配置持久化为外部源引用，服务器后续解析凭据。[协议][integration-api]

### OAuth

1. `POST /api/integration/{id}/connect/oauth`，请求体 `{ "methodID": "...", "answer": {}, "label": "可选" }`。
2. 返回 `{ location, data: { attemptID, url, instructions, mode: "auto" | "code", time: { created, expires } } }`。
3. 打开经过 HTTP(S) 校验的 url，显示 instructions。`auto` 模式服务端已启动等待/轮询，客户端只轮询 `GET /api/integration/{id}/connect/oauth/{attemptID}`。
4. 状态返回 `{ location, data: { status: "pending" | "complete" | "failed" | "expired", time, message? } }`，message 在 failed 时存在。
5. `code` 模式调用 `POST /.../{attemptID}/complete`，请求体 `{ "code": "..." }`，成功 204。
6. 取消用 `DELETE /.../{attemptID}`，成功 204。

所有这些请求都保留原 location。切换服务器、方法或关闭认证流程时使用 generation 隔离迟到结果；取消待处理 attempt。暂时断网保留 attempt 并重试查询，避免新建重复授权。终态在服务端仅短暂保留，404 不等于认证一定失败，应刷新 integrations 判断连接是否已经保存。[官方 Web 状态机][connect-web] [Core][integration-core]

远程手机不能直接使用 OpenAI 的 `chatgpt-browser`：此方法在**服务器** localhost:1455/1457 接收回调，而手机浏览器的 localhost 指向手机。应优先 `chatgpt-headless` 设备码方式；它仍以 auto 模式返回。OpenCode Console 使用设备码 auto 模式。其他 OAuth 方法必须按其具体回调设计判断可用性，不承诺全部第三方入口均可直接使用。[OpenAI 插件][openai-core] [Console 插件][opencode-core]

## 多账号与保密

`Integration.Info.connections` 仅返回 credential 的 `{ type:"credential", id, label, method, status? }` 或环境变量来源 `{type:"env", name, status?}`；不含密钥。当前生效项在 connections 第一项，官方账号 UI 同样取第一个 credential 作为选中账号。[连接实现][integration-core] [官方账号 UI][accounts-web]

- 启用：`POST /api/credential/{credentialID}/activate`，无 body，204。
- 改名：`PATCH /api/credential/{credentialID}`，`{"label":"新名称"}`，204。
- 移除：`DELETE /api/credential/{credentialID}`，204。移除当前账号可能启用另一个已存账号或退回 env，应重新刷新列表。
- 这些操作后刷新 integration/provider/model；部分远程目录异步刷新，短暂等待后再报告模型可用。[账号操作][account-actions-web]

**不要调用 `GET /api/credential` 来显示账号。**该接口会返回完整 `value.key`、OAuth access/refresh token，不是脱敏查询；create 的响应也包含 value。使用 integration.connections 完成账号管理。API Key 仅在本次输入期间保留，成功后清空，不写 Preferences、日志、剪贴板或截图测试输出。[Credential API 与 Handler][credential-api] [credential-handler]

`GET /api/config` 返回按优先级排列的 Config.Entry[]；document 项的 info 是已替换 `{env:...}` / `{file:...}` 的配置，settings、headers、body、MCP 认证信息都可能含 secret，不能当成安全设置查询整包展示/持久化。`GET /api/provider` 也可能包含设置和请求 headers；手机仅投影 id/name 等必要字段。[配置实现][config-core] [变量替换][variable-core]

## 自定义 OpenAI compatible 渠道

固定版本 **没有通用 provider 配置写入 API**：`PATCH /api/experimental/config` 仅接受 shell；文件系统 API 只有 read/list/find，没有 fs.write。同版本官方 Web 的 custom provider 保存分支直接报告不可用。因此不能将遗留 Web form.ts 里的 npm/options 请求体当成 V2 API。[Config API][config-api] [OpenAPI][openapi] [官方 custom dialog][custom-web]

若需要手机设置 baseURL/modelID，需本实例额外提供受限设置入口。建议只管理 `mobile-*` 提供商，允许 name、HTTPS baseURL、API Key、模型 id/name；固定内置 package，拒绝任意文件路径、插件、命令、headers 和未声明字段。返回脱敏摘要和 keyConfigured，不返回已有密钥。白名单数据原子写入专用 global 配置，保留其他设置；不重启或修改共享服务。

V2 最小配置结构如下。`providers` 是复数；providerID 来自 map key，不在子对象内增加 providerID/integrationID；models map key 即请求模型 ID，有别名时才另设 `modelID`。[配置 schema][provider-schema] [配置提供商插件][provider-config]

```json
{
  "providers": {
    "mobile-example": {
      "name": "My compatible provider",
      "package": "@opencode/ai/providers/openai-compatible",
      "settings": {
        "baseURL": "https://api.example.com/v1",
        "apiKey": "user-entered-key"
      },
      "models": {
        "vendor-model-id": { "name": "My model" }
      }
    }
  }
}
```

此 package 是 v2.0.29 内置原生适配器，直接接受 settings.baseURL/apiKey，以 Bearer 认证；不必另外创建 credential，配置插件会自动创建 integration 并启用 provider。若另外存过同 integration 的 credential，其值可能覆盖 config apiKey，应避免两套凭据来源冲突。AI SDK 表示法为 `aisdk:@ai-sdk/openai-compatible`，已知旧 package 别名亦可能被原生重写；新增设置直接固定内置原生名称最明确。[原生适配器][native-compatible] [模型解析][model-resolver] [原生重写][aisdk-native]

密钥是普通 JSON 字符串，使用 JSON 序列化写入，不需 base64。配置文件权限应仅应用账号可读写，settings bridge 响应必须移除 apiKey。所有用户字符串都要拒绝 `{env:` / `{file:` 插值标记，否则 OpenCode 读取时会替换变量或文件内容。[变量替换][variable-core]

DeepSeek/MiMo 优先使用服务器实际列出的 integration 和模型目录；内置免费 MiMo 不需要新增第三方 key。自定义渠道由用户提供真实 baseURL/modelID/key，不猜测凭据、套餐或目录；保存后先验证目录，再显式执行小型真实调用，区分“配置已保存”和“调用已验证”。

## 作用域与生效边界

location 选择项目的 integration 定义和配置折叠视图，但 Credential 服务为**本实例全局**，connect、activate、delete 会影响本实例其他项目后续请求；不是会话私有账号。当前专用实例与服务器其他项目通过独立账号/配置/数据库隔离。[Credential Core][credential-core]

global 配置目录为本实例 XDG config 的 opencode 子目录，候选文件 opencode.json/opencode.jsonc；项目设置可覆盖 global。应以已部署实例环境确定路径，不能照宿主账号默认目录硬编码。配置目录由 watcher 监控，100ms 去抖后 reload；config.updated 会重载 integration/provider/model，无需服务重启。[发现优先级][config-discovery] [watch/reload][config-core] [提供商配置插件][provider-config]

每次模型解析取得当前 active credential；已发出的模型流不会原地换账号，后续 step/请求可能使用新账号或新设置。删除当前使用模型可导致下一步不可用。因此手机全局设置修改、切账号、删账号应在进行中任务及待 Question/审批存在时阻止，并提示先结束任务。改变 provider 配置不会自动重写 session 已选 model ref。[模型解析][model-resolver] [会话模型选择][runner-model]

[integration-api]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/protocol/src/groups/integration.ts
[sdk]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/client/src/promise/generated/client.ts
[form-schema]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/schema/src/form.ts
[integration-core]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/integration.ts
[connect-web]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/app/src/providers/connect/controller.ts
[openai-core]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/plugin/provider/openai.ts
[opencode-core]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/plugin/provider/opencode.ts
[accounts-web]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/app/src/settings/providers/accounts.ts
[account-actions-web]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/app/src/settings/providers/account-actions.ts
[credential-api]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/protocol/src/groups/credential.ts
[credential-handler]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/server/src/handlers/credential.ts
[credential-core]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/credential.ts
[config-core]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/config.ts
[config-api]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/protocol/src/groups/config.ts
[openapi]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/protocol/openapi.json
[custom-web]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/app/src/providers/credentials/dialog.tsx
[provider-schema]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/schema/src/config/provider.ts
[provider-config]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/config/plugin/provider.ts
[native-compatible]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/ai/src/providers/openai-compatible.ts
[model-resolver]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/model-resolver.ts
[aisdk-native]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/aisdk-native.ts
[variable-core]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/config/variable.ts
[config-discovery]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/config/discovery.ts
[runner-model]: https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/session/runner/model.ts

## 当前手机操作

连接服务器后打开底部“设置”，搜索提供商（如 DeepSeek），选择服务器声明的 API Key 或支持的 OAuth 方法。密钥使用密码输入框，仅提交给当前 HTTPS 服务器；保存后清空，不读取或回显已有密钥。账号可以改名、启用和删除。OAuth 流程可取消；应用回前台继续查询，过期记录刷新安全账号列表，避免把404误判为登录失败或成功。

本应用专用实例另外启用了“自定义兼容渠道”：填写 mobile- 开头的渠道 ID、显示名称、公网 HTTPS Base URL、模型 ID 列表和 API Key。编辑时密钥留空保留原值；保存后刷新模型目录。只支持固定内置 OpenAI compatible 适配器，不开放任意插件、命令、文件或环境变量插值。原子写入专用配置并保留其他字段，无需重启 Agent。

入口由 server/mobile_settings.py 和 opencode-harmony-settings.service 提供，仅监听127.0.0.1:4098，经现有独立9443 TLS代理及同一认证访问 /client-settings/providers。GET仅返回脱敏摘要。修改前查询运行中任务及待交互，存在时返回409；这是单用户实例的操作检查，并非与其他客户端新建任务之间的跨服务事务锁。

DeepSeek付费凭据和第三方账号实际登录仍需使用者自行提供并完成。环境变量及 command 认证只展示为服务器管理项；需要服务器 localhost 回调的 chatgpt-browser 禁用，改用设备码入口。
