# 专用实例与 HTTPS 入口

2026-10-22：正式域名通过标准 HTTPS 443 接入；独立 TCP 9443 的域名/IP入口保留兼容。实际主机地址、API 密码、SSH 私钥和 TLS 私钥不写入公开文档。

## 当前运行方式

- `opencode-harmony-agent.service`：独立 Linux 账号 `oc-harmony-agent`，仅监听 `127.0.0.1:4097`。
- `opencode-harmony-tls.service`：独立账号 `oc-harmony-tls`，独立 Nginx 进程与配置，仅监听 `0.0.0.0:9443`。
- `opencode-account.service`：独立账号 `oc-account`，仅监听 `127.0.0.1:4099`，提供单所有者初始化、登录与API鉴权。账号库在Agent隔离根之外，详见 [ACCOUNT.md](ACCOUNT.md)。
- 共享 Nginx 的精确域名443配置为 `/etc/nginx/conf.d/opencode-harmony.conf`；网页转账号服务，API仍经loopback HTTPS 9443并校验证书/SNI。两个明确Nginx服务平滑HUP，其他项目配置摘要保持基线。
- 正式入口使用既有 TCP 443；9443保留兼容，不移除现有云侧规则。4097和4098仅loopback监听，不应开放公网。

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

- TLS 1.2/1.3。正式域名通过 SNI 使用公共 CA 证书，采用系统默认信任；保留的 IP 入口使用本应用专用 CA，验证 IP SAN、有效期及 SPKI。
- 专用 CA 私钥保存在开发电脑私有目录，没有上传服务器。
- App 只包含原 IP 入口的公开 CA 和叶证书 SPKI SHA-256。正式域名连接不勾选“使用专用服务器证书”；旧 IP 连接需要显式勾选。普通请求和 SSE 采用同一连接信任配置。
- 不使用 `remoteValidation: skip`，不关闭证书校验；禁止自动 HTTP 重定向。
- 证书或公钥校验失败停止自动重试，提示核对地址和证书配置。
- 正式域名根路径未登录时跳转 `/login`，提供登录、退出与最小账号首页，不开放公众注册。新密码采用Argon2id加盐哈希，网页使用安全Cookie；API、SSE和渠道设置使用Basic，网页Cookie不能绕过API鉴权。80仅跳转同域名HTTPS。
- 专用9443通过账号服务内部子请求验证外部账号，再向Agent/设置服务注入仅服务器可见的内部凭据。所有者完成初始化后，原公开账号停止新的登录；新账号用于网页和手机，不改Agent模型或会话。旧htpasswd不再被引用，所有者初始化成功后已删除线上两份旧文件，仅保留root-only回滚副本。账号库与内部凭据受限存放，不扩大TLS私钥目录权限。
- 每IP 10请求/秒，突发40，最多20并发连接，超限429；请求体上限2MiB。443前端覆盖传入X-Forwarded-For，9443仅信任127.0.0.1代理来源，避免公网伪造客户端地址。
- SSE 关闭代理缓冲、缓存；读取超时90秒。
- 代理配置和 TLS 密钥由 root 管理，只有代理专用组可读；Agent 看不到该目录。
- 密码在 App 系统安全资产中保存；本机 `.server-access` 仅本人、系统和管理员可访问，不纳入Git。

原 IP 临时叶证书有效至 **2026-11-14**；正式域名证书有效至北京时间 **2027-01-20 12:59:59**。域名证书尚未配置自动续签。IP 入口更换叶证书公钥需要同步更新 App 中的 SPKI；保留原公钥续签仍需保持 CA/地址校验。9443 仍承载正式域名入口，不能关闭该端口；续签和回滚见 [DOMAIN-MIGRATION.md](DOMAIN-MIGRATION.md)。

## 连接

正式连接地址填写 `https://<正式域名>`，无需端口或 `/server`。通过专属链接创建所有者账号后，在手机填写新用户名与新密码；不勾选“使用专用服务器证书”或“允许HTTP”，保持系统证书校验。原 `https://<SERVER_IP>:9443` 入口继续可用，仍需勾选专用服务器证书，同样使用新账号。正式域名网页登录位于 `/login`，App通过Basic认证后的 `/api/` 访问服务。

连接成功后可以关闭开发电脑和 SSH 隧道，App 直接访问公网服务。首次签名和真机安装仍按 DevEco 要求配置。

原 IP 临时证书另含 loopback SAN，便于通过开发隧道测试 TLS；这不绕过 CA、有效期或公钥校验。旧 `http://127.0.0.1:4211` 仅是开发方式，不是公网地址。

## 验证与运维

- 普通回归：`node tests/core.test.mjs` 与 `node tests/state.test.mjs`。
- 公网安全验证：设置 `OPENCODE_TEST_URL=https://<SERVER_IP>:9443`，运行 `node tests/public-entry.test.mjs`。读取被忽略的本机测试凭据；不会输出密码。
- 模拟器：同一变量下运行 `node tests/emulator-smoke.mjs https`，再运行 `live-send`。测试通过真实原生输入发送唯一短语并验证真实新回复。
- 查看本应用状态：`sudo systemctl status opencode-harmony-agent opencode-harmony-tls`。
- `scripts/secure-public-entry.sh` 是本轮迁移脚本，不应直接覆盖已部署实例；既有目标会拒绝执行。
- `scripts/provision-server.sh` 保留为初始开发部署记录，当前实例由上述系统 service 管理。

撤销本应用公网访问时，先仅移除 `/etc/nginx/conf.d/opencode-harmony.conf`，检查共享配置后平滑 HUP `nginx.service`；再停止并禁用 `opencode-harmony-tls.service`，删除仅属于本应用的云侧9443规则。共享443仍供其他项目使用，不能关闭该端口或停止共享Nginx。保留 Agent 与历史即可继续本地开发。若回滚旧实例，须先停止新 Agent，并明确同步迁移后的新增数据；旧快照不会自动包含新聊天。不要停止默认 OpenCode、共享 Nginx 或其他项目服务。

## 手机端受限渠道设置

新增 opencode-harmony-settings.service，使用同一隔离根及 oc-harmony-agent 账号，只有本应用 config 目录可写；监听127.0.0.1:4098。独立TLS代理的 /client-settings/ 路径使用同一 Basic认证，请求体上限64KiB；未修改共享Nginx。

只允许管理 mobile-* 渠道，固定内置兼容适配器，允许名称、公网HTTPS地址、模型ID列表和API Key。拒绝任意文件/命令/插件/其他配置字段以及文件或环境变量插值。返回脱敏摘要；已有密钥不回显。配置文件0600，临时文件fsync后原子替换，保留不相关设置；任务或待交互存在时拒绝修改。

scripts/deploy-settings.sh 用于首次安装，会拒绝覆盖已存在服务。更新需先核验并运行 tests/mobile_settings_test.py，再只替换本服务代码并重启 opencode-harmony-settings.service；不必重启Agent。测试使用临时目录和测试凭据，不修改真实配置。

本实例已通过官方permission evaluate hook修复v2.0.29可选metadata.path为undefined时的审批列表400，仅规范化元数据，不放宽权限。无需二进制升级或共享服务变更。手机失败时保留上次待办并暂停批准，恢复后批准前再核对。插件部署、回滚和验证见 [APPROVALS.md](APPROVALS.md)。

## 搜索依赖与后续域名

2026-10-15补齐本实例缓存的固定ripgrep15.1.0，解决真实glob的30秒超时，不改共享/usr或重启服务。`scripts/install-search-dependency.sh`需要官方归档并校验固定SHA256、jail标记和路径；相同版本重复运行不覆盖，不同二进制拒绝覆盖。运行方式和真实回归见 [REFINEMENTS.md](REFINEMENTS.md)。

2026-10-22 已部署正式域名公共证书及标准443入口，域名/IP的独立9443入口保留兼容。公网证书、认证、历史读取、脱敏设置和SSE验证通过；其他项目7项公开入口、原有配置摘要及相关主进程保持部署前基线。本轮未执行设备端切换域名后的验收或真实模型推理，见 [DOMAIN-MIGRATION.md](DOMAIN-MIGRATION.md)。
