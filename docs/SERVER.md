# 专用实例与开发通道

2026-10-15 已新增专用 OpenCode v2.0.29 实例。实际主机地址、API 密码与 SSH 私钥不写入此公开文档。

## 已实施

- 服务单位：opencode-harmony.service（user systemd）。
- 根目录：~/opencode-harmony-service。
- 固定二进制：bin/opencode-v2.0.29，复制后与来源二进制逐字比较。
- 私有环境文件：server.env，权限600，密码独立随机生成。
- HOME、XDG_CONFIG_HOME、XDG_DATA_HOME、XDG_STATE_HOME、XDG_CACHE_HOME、TMPDIR、OPENCODE_DB 分开设置。
- 仅监听127.0.0.1:4097。
- 独立工作区：workspaces/demo。
- NoNewPrivileges=yes、ProtectSystem=strict、ProtectHome=read-only。
- ReadWritePaths 仅允许本实例根目录；SSH 目录不可访问。
- 不运行默认 opencode pair/service set；不复制其他实例的模型密钥。

已核验 API /api/info 返回2.0.29，专用项目可列出、会话可创建。专用实例已启用的 MiMo 免费模型完成最小文本回复，未要求模型读取或修改业务文件。

部署前后既有监听地址保持存在；现有 OpenCode、Nginx 及其他项目没有停止、重启或修改。

目录隔离及systemd挂载约束是本实例的运行边界；它与ubuntu共享账号，不代表独立Linux用户或容器级身份隔离。新增公网入口前需要再次核验隔离和访问范围。

## 开发电脑

开发隧道：

    ssh -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -N -L 127.0.0.1:4211:127.0.0.1:4097 <SSH_USER>@<HOST>

仅针对本机测试使用对应私钥，不将私钥加入App或Git。模拟器映射：

    hdc -t 127.0.0.1:5555 rport tcp:4211 tcp:4211

模拟器App可连接 http://127.0.0.1:4211；这个HTTP段是本机回环，跨公网部分由SSH加密。实际API凭据保存在系统安全资产中。

开发电脑关闭、SSH隧道退出后，这个地址不可达，服务器Agent可以继续运行。完整历史仍保留服务器。

本机私有运维材料放在 .server-access 并被 Git 忽略；.test 下记录开发进程PID和验证产物。不要将它们加入版本管理。

## 域名就绪之后

- 确认可用域名、证书签发方式和专用TLS端口。
- 新增独立HTTPS入口，避开已有80/443/8443业务。
- 不默认更改共享Nginx、云安全组或既有证书。
- 验证认证、SSE心跳、代理缓冲、长连接超时及错误响应。
- 真机通过HTTPS直接连接后，才可声明公网远程访问验收完成。

## 仅撤销本实例

需要撤销时，只停止并禁用 opencode-harmony.service，保存所需历史后处理其专用目录和unit文件。不要停止默认OpenCode服务或清理共享配置目录。
