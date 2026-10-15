# 临时 IP HTTPS 接入的依据

核验时间：2026-10-15。实施与验收以本机 SDK26 类型声明、服务器实际行为及模拟器验证为准。

## 鸿蒙客户端

本机 `@ohos.net.http.d.ts` 明确：`caPath` 自API10、`certificatePinning` 自API12、`remoteValidation` 自API18、`caData` 自API20、`maxRedirects` 自API23可用，均低于本项目最低API24。`request` 和 `requestInStream` 使用同一个 `HttpRequestOptions`。

`caData` 有效时补充指定CA，不承诺排除所有系统CA；因此本应用的专用连接同时配置叶证书公钥 SHA-256 绑定，保持系统证书/地址验证。不应以“加了CA”等同“仅信任这个服务器”。相关官方依据：[数据请求API](https://developer.huawei.com/consumer/en/doc/harmonyos-references-V5/js-apis-http-V5)、[网络连接安全配置](https://developer.huawei.com/consumer/cn/doc/doccenter-capabilities/network-connection-security-configuration)。具体新属性以本机SDK声明为准。

公钥取证书 SubjectPublicKeyInfo 的DER，再做SHA-256和Base64。App只包含公开CA/公钥摘要。私钥不进入安装包或公开仓库。证书CA、有效期、SAN地址与SPKI都必须通过；没有“忽略证书错误”选项。

## 选择专用 CA 的原因

Let’s Encrypt目前可以签发IP证书，但HTTP-01必须在80端口验证、TLS-ALPN-01必须在443验证，DNS-01不能用于IP。只新增9443不能独立完成这些公开IP验证。参考：[官方挑战类型](https://letsencrypt.org/docs/challenge-types/)。

既有80/443服务其他项目，本轮选择独立9443、专用CA和App级公钥绑定，避免改变共享站点的验证路由或重启共享代理。域名就绪后再确定正式证书和入口。

## 验证边界

- 公网脚本验证独立TLS入口的认证、未知CA、地址不匹配、错误公钥、请求大小、SSE及限流。
- 原生模拟器验证实际ArkUI输入与NetworkKit请求，避免用Node请求成功替代手机平台验收。
- Agent以独立系统账号及RootDirectory运行；宿主机网络未拆分命名空间。这是当前边界，不声称为独立虚拟机或绝对无风险。
