# 正式域名与 HTTPS 入口

状态：2026-10-22，正式入口已启用标准 HTTPS 443，客户端使用 `https://<正式域名>`，无需端口或 `/server`。独立9443域名/IP入口保留兼容。共享 Nginx 仅新增本应用的精确域名配置并执行平滑 HUP；原有项目配置文件摘要及所有主进程/后端 PID 保持基线。

## 入口方案

当前使用 `https://<正式域名>`。共享443使用精确域名server：网页转127.0.0.1:4099；`/api/` 与 `/client-settings/` 经loopback HTTPS转独立9443。API使用所有者新账号Basic鉴权，网页使用安全Cookie，不开放公众注册；详见 [ACCOUNT.md](ACCOUNT.md)。上游启用公共CA、固定域名/SNI与证书链校验，保留SSE、请求体限制和真实客户端IP限流。前端覆盖传入的转发地址，独立代理仅信任127.0.0.1提供的地址；公网直连9443无法借此伪造来源。原有默认443虚拟主机和80/8443配置保留。SNI 依据见 [Nginx 官方说明](https://nginx.org/en/docs/http/configuring_https_servers.html#sni)。

证书优先使用 DNS-01 签发，不需要占用现有 HTTP 端口。DNS 凭据应使用最小权限并保留在运维环境，不能交给 Agent 或写入 App。验证方式见 [Let's Encrypt 官方说明](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)。备案和 DNS 控制权验证是不同步骤。本次使用用户在腾讯云手动完成 DNS 验证后下载的 Nginx 证书包，没有向服务器提供云账号或 DNS API 凭据。

## 可复核的准备产物

`scripts/prepare-domain-entry.py` 从当前专用代理配置生成一个新文件，不修改源文件，也没有 reload/install 选项：

```powershell
python scripts/prepare-domain-entry.py agent.example.com --source .test/current-nginx.conf --output .test/domain-candidate.conf
python tests/domain_entry_test.py
```

`agent.example.com` 仅为语法验证示例，不是部署目标。生成器只接受单一、独立的 9443 配置及既有两个 loopback 后端，拒绝其他监听、include 和异常结构。它复制现有认证、限流、SSE 以及 `/client-settings/` 路由；原 IP server 保留为 default_server，新增域名 server 使用以下证书位置：

- `/etc/opencode-harmony-tls/domain/fullchain.pem`
- `/etc/opencode-harmony-tls/domain/privkey.pem`

## 首次迁移至独立9443的执行顺序（历史步骤）

1. 核验域名归属、备案状态与 DNS A/AAAA。解析必须匹配实际可达地址；不保留不可达的 AAAA。
2. 为实际域名签发完整证书链，核对 SAN、有效期、公私钥匹配和公共信任链。目录 root:oc-harmony-tls 0750，私钥 root:oc-harmony-tls 0640，Agent 不可访问。为续签建立明确的到期监测和只针对本服务的部署 hook。
3. 读取当时的专用代理配置重新生成候选，人工核对差异；记录源 SHA256、专用代理 PID、共享 Nginx PID/配置摘要和监听基线。源发生变化时重新生成，不能套用旧候选。
4. 使用专用代理账号执行 `nginx -t -p /run/opencode-harmony-tls/ -c <候选文件>`，验证文件可读性及语法。仅有语法成功仍不足以确认公网证书正确。
5. 以 0640 权限备份现有专用配置，原子替换；**仅向 `opencode-harmony-tls.service` 的主进程发送 HUP**。当前 unit 没有 ExecReload，不运行泛用的 `nginx -s reload` 或 `systemctl reload nginx`。
6. 从公网核验证书主机名/链、未认证401、认证后项目/模型/设置读取、SSE、不支持根路径404、限流，以及原 IP + CA/SPKI 入口继续有效。密码只从既有私有测试材料注入，不输出。
7. 在 API24 Pad 和 API26 模拟器新增域名连接，保留 HTTPS 和系统证书校验，**不勾选“使用专用服务器证书”**。原 CA/SPKI 仅适用于临时 IP 证书。检查同一服务器会话历史、MiMo 新回复、Question/审批和重连。
8. 确认验收后再决定是否停用 IP server；9443 是域名入口仍在使用的端口，不能误删云侧9443规则。如果以后要省略端口，需另行设计入口并审查共享443的影响。

失败时原子恢复第5步的专用配置备份，仅 HUP 该专用主进程，再验证 IP 入口。Agent、数据库和设置服务均无需迁移或重启。不要恢复旧数据库来回滚 TLS，这会丢失新会话。

## 当前验证边界

2026-10-22 已完成两项生成器回归、证书 SAN/有效期/公私钥匹配/完整链核验，以及专用代理账号的 `nginx -t`。原子替换配置后仅向 `opencode-harmony-tls.service` 主进程发送 HUP；共享配置摘要及相关服务主进程保持部署前基线。Agent 不可读取正式 TLS 私钥，临时上传目录和候选文件已清除。

公网已验证 Windows 与 Node 默认公共信任、未认证/错误密码 401、项目和模型目录读取、域名与 IP 读取同一既有会话、提供商设置脱敏返回、SSE 首事件、根路径 404、超大请求 413 和突发限流 429。原 IP 的专用 CA 与 SPKI 校验继续通过。本次没有发送模型推理请求或修改会话/模型配置；API24 真机、API26 模拟器切换域名后的端侧验收仍待执行。

## 标准443验收与回滚

2026-10-22 为无端口入口完成 Windows/Node 默认公共信任、401认证、项目/模型目录、历史会话一致性、提供商设置脱敏、SSE首事件、根路径404、超大请求413及突发429验证；带有不同伪造转发地址的未认证请求仍被限流。原9443域名和IP入口继续通过认证读取，IP的专用CA/SPKI保持有效。本轮未修改会话、渠道或模型配置，也未发送模型推理请求。

其他项目的7项公网基线逐项一致：80根路径和健康路径308，原443根页面/健康检查/iOS入口200、未认证API401，以及8443根路径302；对应内容类型、跳转目标及TLS证书均与变更前一致。原5个已加载共享配置文件摘要、共享与独立Nginx主进程、Agent和设置服务PID保持基线。候选/上传目录已清理。

新增共享配置为 `/etc/nginx/conf.d/opencode-harmony.conf`；独立代理变更前备份为 `/etc/opencode-harmony-tls/nginx.conf.before-443-20261022`。回滚前先核对后续是否有新改动，移除本应用新增443配置、恢复独立代理备份，分别 `nginx -t` 后平滑 HUP 两个明确的服务主进程，再验证原有网站和9443。不得覆盖原有其他项目文件、重启业务后端或回滚数据库。实际域名与本次基线/候选/记录位于本机忽略目录 `.server-access/domain-443-20261022/`。

## 域名Basic前端迁移记录（历史，已由账号网关替代）

按用户要求，正式域名现已在共享HTTPS入口统一启用Basic身份验证；复用原用户名/API密码，额外密码文件由root:www-data 0640管理，私钥目录权限不变。未认证根路径、API、SSE和渠道设置均返回401；原凭据验证项目/模型/历史、设置与SSE继续通过，认证成功后的根路径仍为404。域名80入口只向同域名HTTPS作308跳转。

密码轮换需同步新的前端密码文件与现有专用代理、后端以及客户端值。原域名443迁移时记录的配置哈希为历史基线，本次统一认证及80跳转已更新共享域名配置；不要用旧候选直接覆盖新认证。FieldNotes域名及其 `/review` 挂载独立于OpenCode；两者复用共享80/443并通过精确域名分流。

## 当前账号入口（2026-10-22）

前端静态htpasswd检查已由独立账号服务替代，用户密码以Argon2id存储。API在9443通过auth_request统一验证新Basic账号；网页提供登录与退出，未登录根路径跳转 `/login`。IP/域名9443与443共用此账号验证，不能通过旧端口绕过新账号。原后端凭据仅用于内部转发，和用户新密码分开保存。初始化后不要重新使用前述历史Basic候选或直接恢复旧认证。账号部署、验证与回滚见 [ACCOUNT.md](ACCOUNT.md)。

## 续签与首次9443迁移回滚

本次 TrustAsia 域名证书有效至北京时间 **2027-01-20 12:59:59**；没有配置自动续签或自动部署。应提前申请新证书，重新核验 SAN、有效期、完整证书链和公私钥匹配，备份现有文件后更新专用 `domain/` 目录。共享443和独立9443均加载这组证书，须分别检查共享配置与专用账号配置，再分别平滑 HUP `nginx.service` 和 `opencode-harmony-tls.service` 的主进程，完成新旧入口公网验证。服务器私钥继续采用 root:oc-harmony-tls 0640、目录 0750。

`prepare-domain-entry.py` 仅用于单 IP server 的首次迁移。现在已是双 server，不应重新运行生成器覆盖现有配置；续签只更换域名证书文件。

首次迁移前的配置备份保留在 `/etc/opencode-harmony-tls/nginx.conf.before-domain-20261022`。需回滚时先确认线上配置未被后续修改，再将备份原子恢复到本应用 `nginx.conf`，仅 HUP 本应用 TLS 主进程并验证旧 IP 入口。TLS 回滚不需要恢复数据库或重启 Agent。实际域名、证书包和本次检查记录保留在本机忽略目录 `.server-access/domain-20261022/`。
