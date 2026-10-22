# 私有账号与网页登录

2026-10-22：正式域名提供登录、退出和最小账号首页；不开放公众注册。App继续使用HTTP Basic，同一账号可用于网页和手机，不需要重新安装客户端。

## 所有者首次设置

运维在私有目录生成256位随机令牌。专属链接的令牌放在URL fragment，HTTP请求、访问日志和Referer不包含它；脚本读入后立即移除地址栏fragment，不使用localStorage保存。链接只交给所有者，24小时有效，服务器仅保存其SHA-256摘要。

- /setup是首次初始化页，不是公共注册页。
- POST /auth/setup同时校验令牌、有效期、同源Origin、匿名会话及CSRF。
- SQLite事务保证只创建一个所有者；并发使用链接只能成功一次。
- 账号创建与令牌消耗在同一事务内完成。之后/setup跳转登录，初始化POST返回404。
- 链接到期且未创建账号时，须由运维重新签发，不提供公网找回或重置接口。
- 创建成功后，旧公开账号立即停止新的API登录；已有进行中的连接不主动中断。聊天、项目和模型配置保留。

账号为3–32位英文、数字、点、下划线或短横线，首位为英文或数字。密码为12–128个字符，不做截断，不强迫固定字符组合。建议使用密码管理器。

## 密码、会话与限流

密码通过HTTPS提交后，服务端使用 **Argon2id** 加盐哈希：64MiB内存、3次迭代、并行度1、16字节随机盐、32字节输出。用户密码不写入环境变量、日志或数据库明文字段，不提供明文回读。依据见 [OWASP Password Storage](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)。

浏览器使用不透明的__Host-oc_session随机Cookie，Secure、HttpOnly、SameSite=Strict、Path=/，不指定Domain。数据库仅保留会话令牌摘要。匿名会话20分钟，登录会话12小时；登录更换令牌，退出删除服务器会话，旧Cookie不能重放。写操作校验Origin和CSRF；API不接受网页登录Cookie，浏览器会话不能绕过API的Basic鉴权。

登录和初始化失败按Nginx提供的真实IP限流，每15分钟最多8次。记录经过带密钥摘要处理并持久化，重启不会清零。密码校验最多并行2次。Basic成功校验只缓存带随机密钥的凭据摘要60秒，避免SSE、轮询等每个请求都计算Argon2。会话、限流记录和缓存有容量上限。

页面只使用本地静态资源，设置严格CSP、禁止嵌入、no-store和no-referrer，不接入第三方统计、字体或脚本。

## 服务器结构

- 新增opencode-account.service，独立账号oc-account，仅监听127.0.0.1:4099。
- 程序位于/opt/opencode-account/current；独立venv依赖固定在server/account/requirements.lock。
- 数据库位于/var/lib/opencode-account/account.sqlite3，目录0700、数据库0600，由oc-account管理。
- 内部凭据和限流密钥位于/etc/opencode-account/service.env，root:oc-account 0640，不在Git中。
- systemd沙箱只允许写账号状态目录，Agent隔离根不能读取账号库、新密码哈希或网页Cookie。
- 共享443按域名分流：网页转4099，API和受限设置仍经专用9443。
- 9443的两个server统一使用auth_request，验证外部账号后再转4097/4098。Nginx仅使用内部鉴权子请求返回的后端认证头，忽略公网伪造同名头。依据见 [Nginx auth_request](https://nginx.org/en/docs/http/ngx_http_auth_request_module.html)。
- /internal/check和/_opencode_auth不对公网开放。证书、真实IP覆盖、SSE不缓冲、请求体及并发限制保留。
- 上游Agent/设置服务使用独立内部服务凭据；初始化前临时兼容原公开账号，之后不再接受它作为外部登录。内部凭据不等于用户新密码，不应直接清空内部环境文件。

网页登录位于https://<正式域名>/login，首页/只展示账号和退出；未登录访问首页跳转登录。API未认证返回401和Basic challenge。80继续308跳转同域名HTTPS。独立9443仅提供API，根路径仍404。

手机“服务器连接”填写https://<正式域名>、新账号和新密码，保留系统证书校验。用户名可编辑。旧IP9443保留专用CA/SPKI连接方式，同样接受新账号。模型提供商Key与服务器登录密码不同。

## 部署与验证

prepare-account-entry.py仅从已核对的OpenCode配置生成候选，未知结构、重复迁移或认证块数量异常时拒绝执行。

scripts/deploy-account-entry.py是本次首次部署记录，校验源配置SHA256，拒绝覆盖既有账号状态、service、发布目录和备份。它不是日常更新脚本，不要直接重跑。初始化令牌在本机忽略目录生成，服务器暂存仅接收摘要；任何示例或提交中都不能附带真实专属链接。

隔离测试使用临时SQLite、测试账号和令牌，不读取生产账号：

~~~sh
/opt/opencode-account/venv/bin/python -B tests/account_auth_test.py
/opt/opencode-account/venv/bin/python -B tests/account_proxy_test.py
~~~

第二项需要Linux Nginx，临时Nginx和测试后端只监听loopback，结束即清理。第一项覆盖哈希存储、一次性/过期令牌、并发初始化、Origin/CSRF、请求体上限、密码校验、Cookie轮换/退出、持久限流、新账号Basic、旧账号撤销、鉴权缓存和主机名限制。第二项通过真实Nginx验证子请求鉴权、内部认证头转发及Cookie不能绕过API。

已完成上述14项测试、正式HTTPS页面/资源、所有者未初始化状态、原账号临时API兼容、项目/模型/会话/受限设置只读验证，以及IP入口的CA/SPKI、SSE、401/413/429回归。无头浏览器检查手机宽度、浅深色页面、密码显隐、fragment移除及安全Cookie。正式账号由所有者自行创建成功，未读取或代设新密码，未发送模型推理或写入聊天。真实手机修改为新账号后的体验需用户验收。原IP公网回归脚本支持通过临时环境变量OPENCODE_TEST_USERNAME和OPENCODE_TEST_PASSWORD注入新账号，不必保存新密码到旧运维文件；此脚本仅面向专用CA/SPKI的IP9443入口，不能直接套用到正式域名证书。

## 更新、备份与回滚

更新时先运行隔离测试，发布root管理的代码目录，再重启opencode-account.service。不得覆盖账号数据库、环境密钥、TLS私钥或手机签名配置。依赖更新需重新锁定和测试。

本次root-only备份位于/var/backups/opencode-account-20261022，包含两份原Nginx配置、原认证文件和其他项目配置摘要。已检测到正式所有者初始化成功并签发登录会话，令牌已消耗。443和域名9443均验证旧账号返回401；线上两个不再引用的旧htpasswd已删除，仅保留root-only回滚副本。Agent内部凭据继续独立保存。

账号网关回滚会重新启用旧入口，应由所有者明确决定，并先检查线上没有后续变更。仅恢复本应用前端/专用代理配置和对应旧认证文件，分别nginx -t后向两个明确服务主进程平滑HUP。不恢复旧聊天数据库、模型或工作区，也不要因回滚TLS而回滚账号库。

使用SQLite在线backup接口备份账号数据库，不只复制活跃WAL模式主文件。备份包含密码哈希和会话，须root-only并排除Git；恢复时考虑旧会话与旧密码哈希的影响。忘记密码由运维经受限SSH处理，不开放公网注册、重置或运维命令接口。
