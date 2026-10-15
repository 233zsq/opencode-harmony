# 专用实例与临时 HTTPS 入口

2026-10-15：备案等待期间使用独立 TCP 9443 + HTTPS。实际主机地址、API 密码、SSH 私钥和 TLS 私钥不写入公开文档。

## 当前运行方式

- `opencode-harmony-agent.service`：独立 Linux 账号 `oc-harmony-agent`，仅监听 `127.0.0.1:4097`。
- `opencode-harmony-tls.service`：独立账号 `oc-harmony-tls`，独立 Nginx 进程与配置，仅监听 `0.0.0.0:9443`。
- 没有修改或 reload 共享 Nginx；原 80/443/8443 配置、主进程及既有监听保持不变。
- 云侧只需放行 TCP 9443。不要开放 4097；它由本机 TLS 代理访问。

## Agent 隔离与数据

Agent 由原 user service 迁入系统 service，原 user service 已停用。迁移时先停止本应用的旧实例，再复制数据，保留原目录作为回滚快照。

- 宿主机隔离根：`/var/lib/opencode-harmony-root`。
- 隔离环境内的应用根：`/home/ubuntu/opencode-harmony-service`。
- 宿主机实际数据：`/var/lib/opencode-harmony-root/home/ubuntu/opencode-harmony-service`。
- 保留隔离环境内原有绝对路径，因此原工作区、项目及会话引用不变。
- 使用 `RootDirectory` 限制文件视图，只读挂载 `/usr`、系统公开 CA；不挂载宿主机 SSH、共享项目和 TLS 密钥目录。
- `ProtectSystem=strict`、仅专用目录可写、无 capabilities、`NoNewPrivileges`、私有临时目录和设备、非 root 账号。
- 配置、数据库、HOME、XDG 和模型凭据均为本实例专用；没有复制其他实例的模型密钥。

这是独立账号与文件系统隔离，网络仍共享宿主机，不等同独立虚拟机。允许访问的项目必须放入本实例工作区；原服务器其他项目不会自动出现在客户端。

## TLS、认证与限流

- TLS 1.2/1.3；服务器叶证书由本应用专用 CA 签发，验证 IP SAN 和有效期。
- 专用 CA 私钥保存在开发电脑私有目录，没有上传服务器。
- App 只包含公开 CA 和叶证书 SPKI SHA-256；在连接中显式勾选“使用专用服务器证书”。普通请求和 SSE 采用同一配置。
- 不使用 `remoteValidation: skip`，不关闭证书校验；禁止自动 HTTP 重定向。
- 证书或公钥校验失败停止自动重试，提示核对地址和证书配置。
- `/api/` 全部经独立强随机 Basic 密码认证；代理与 OpenCode 均验证认证。根路径及 Web UI 返回404。
- 每IP 10请求/秒，突发40，最多20并发连接，超限429；请求体上限2MiB。
- SSE 关闭代理缓冲、缓存；读取超时90秒。
- 代理配置和 TLS 密钥由 root 管理，只有代理专用组可读；Agent 看不到该目录。
- 密码在 App 系统安全资产中保存；本机 `.server-access` 仅本人、系统和管理员可访问，不纳入Git。

临时叶证书有效至 **2026-11-14**。更换叶证书公钥需要同步更新 App 中的 SPKI；保留原公钥续签仍需保持 CA/地址校验。域名就绪后迁移至正式证书与域名入口，再关闭临时公网端口。

## 连接

App 地址填写 `https://<SERVER_IP>:9443`，用户名 `opencode`，使用本实例私有 API 密码，并勾选“使用专用服务器证书”。不勾选“允许HTTP”。浏览器默认不信任这个私有 CA 属于预期行为，App 内使用显式信任与公钥绑定。

连接成功后可以关闭开发电脑和 SSH 隧道，App 直接访问公网服务。首次签名和真机安装仍按 DevEco 要求配置。

服务器证书另含 loopback SAN，便于通过开发隧道测试 TLS；这不绕过 CA、有效期或公钥校验。旧 `http://127.0.0.1:4211` 仅是开发方式，不是公网地址。

## 验证与运维

- 普通回归：`node tests/core.test.mjs` 与 `node tests/state.test.mjs`。
- 公网安全验证：设置 `OPENCODE_TEST_URL=https://<SERVER_IP>:9443`，运行 `node tests/public-entry.test.mjs`。读取被忽略的本机测试凭据；不会输出密码。
- 模拟器：同一变量下运行 `node tests/emulator-smoke.mjs https`，再运行 `live-send`。测试通过真实原生输入发送唯一短语并验证真实新回复。
- 查看本应用状态：`sudo systemctl status opencode-harmony-agent opencode-harmony-tls`。
- `scripts/secure-public-entry.sh` 是本轮迁移脚本，不应直接覆盖已部署实例；既有目标会拒绝执行。
- `scripts/provision-server.sh` 保留为初始开发部署记录，当前实例由上述系统 service 管理。

撤销公网访问时，仅停止并禁用 `opencode-harmony-tls.service`，同时删除云侧9443入站规则。保留 Agent 与历史即可继续本地开发。若回滚旧实例，须先停止新 Agent，并明确同步迁移后的新增数据；旧快照不会自动包含新聊天。不要停止默认 OpenCode、共享 Nginx 或其他项目服务。
