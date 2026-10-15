# 正式域名迁移准备

状态：2026-10-15，备案尚未完成。本轮仅生成和测试候选配置，没有部署域名、申请证书、改变 DNS 或 reload 服务。

## 入口方案

先使用 `https://<正式域名>:9443`。保持本应用独立 TLS 进程，保留现有 IP 入口作为回滚路径；通过 SNI 为域名提供公共 CA 证书。现有服务器的 80/443 属于其他项目，本方案不占用或修改它们。SNI 证书选择依据见 [Nginx 官方说明](https://nginx.org/en/docs/http/configuring_https_servers.html#sni)。

证书优先使用 DNS-01 签发，不需要占用现有 HTTP 端口。DNS 凭据应使用最小权限并保留在运维环境，不能交给 Agent 或写入 App。验证方式见 [Let's Encrypt 官方说明](https://letsencrypt.org/docs/challenge-types/#dns-01-challenge)。备案和 DNS 控制权验证是不同步骤，正式启用仍等待备案及用户的实际域名。

## 可复核的准备产物

`scripts/prepare-domain-entry.py` 从当前专用代理配置生成一个新文件，不修改源文件，也没有 reload/install 选项：

```powershell
python scripts/prepare-domain-entry.py agent.example.com --source .test/current-nginx.conf --output .test/domain-candidate.conf
python tests/domain_entry_test.py
```

`agent.example.com` 仅为语法验证示例，不是部署目标。生成器只接受单一、独立的 9443 配置及既有两个 loopback 后端，拒绝其他监听、include 和异常结构。它复制现有认证、限流、SSE 以及 `/client-settings/` 路由；原 IP server 保留为 default_server，新增域名 server 使用以下证书位置：

- `/etc/opencode-harmony-tls/domain/fullchain.pem`
- `/etc/opencode-harmony-tls/domain/privkey.pem`

## 域名就绪后的执行顺序

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

生成器的保留路由/认证/限流、拒绝注入/共享端口回归通过，并已基于实际独立代理配置生成候选。尚无实际域名和公共证书，因此没有执行部署或声称通过正式域名 TLS 验收。
