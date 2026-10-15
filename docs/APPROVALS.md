# 审批预览、恢复与 v2.0.29 兼容修复

本轮完成审批功能增量。客户端不执行本地命令；工具仍由专用 OpenCode 实例执行。

## 手机行为

- 审批卡显示 action、resources、来源，以及服务端提供的命令、工作目录、匹配模式和说明。
- 文件修改使用**当前审批请求 metadata.files/patch**，不是工作区当前 Git Diff；显示文件名、增删行、展开/折叠，首文件默认展开。
- 批准前重新读取当前会话、当前目录的审批列表，比较用户所见的完整预览快照。请求已处理或内容变化时不提交，要求重新查看。
- 只提交 once 或 reject，不提供永久放行。重复点击、迟到请求、断线丢回执不会自动产生第二次批准。
- 读取失败保留上次卡片并禁用批准，拒绝仍可用。重新读取成功解除限制；成功空列表才移除已处理卡片。切换会话清除旧错误。
- 最多预览20个文件；每个patch最多100000字符/1500行，范围和命令最多12000字符。截断或无法完整解析时明确提示并禁用批准。服务端未提供Diff时明确说明。

## 400 根因与修复边界

协议固定在官方提交 [042d0832f5f3a73eaa039a58a7d565776f6d4290](https://github.com/anomalyco/opencode/tree/042d0832f5f3a73eaa039a58a7d565776f6d4290)。

真实glob只传pattern而不传可选path时，工具生成 `{root: '.', path: undefined, hidden: undefined, limit: undefined}`。待审批队列中的metadata仍引用该对象，GET permission由严格JSON编码器拒绝，400指出 `data[0].metadata.path`。同一接口处理普通JSON元数据正常。

[官方permission实现](https://github.com/anomalyco/opencode/blob/042d0832f5f3a73eaa039a58a7d565776f6d4290/packages/core/src/permission.ts) 在入队前调用evaluate hook。`server/permission-json` 使用此公开插件接口，原地规范化共享metadata：删除对象的undefined属性，数组的undefined/空洞变为null，保留有效值和patch。循环、非JSON对象、非有限数等抛错，不替用户放行。action、resources、effect、save、source均不变。

只修复新请求进入队列前的元数据；不会改写现有坏请求，也不修复glob搜索本身的超时。未升级OpenCode二进制、未修改代理协议或关闭审批。

## 本实例部署与回滚

运行时插件位于隔离环境内 `/home/ubuntu/opencode-harmony-service/plugins/permission-json`，宿主路径前缀为 `/var/lib/opencode-harmony-root`。这是仅供管理员操作的固定实例路径；手机渠道设置不能写插件。

已经部署并核对源码SHA256：

    2cc56d4d03e3e32936831047d4a4ceb215ccda04a9f9a223bb736c2ab7c2fe67

首次安装或更新须在本实例无运行中任务/待审批时进行；配置重载可能关闭已有上下文。以源码根目录为当前目录，管理员在该服务器执行：

    set -euo pipefail
    APP=/var/lib/opencode-harmony-root/home/ubuntu/opencode-harmony-service
    sudo test -f /var/lib/opencode-harmony-root/.opencode-harmony-jail-owned
    sudo test ! -L "$APP"
    sudo test -d "$APP/config/opencode"
    sudo test ! -L "$APP/plugins"
    sudo test ! -L "$APP/plugins/permission-json"
    sudo install -d -o root -g oc-harmony-agent -m 0750 "$APP/plugins/permission-json"
    sudo test ! -L "$APP/plugins/permission-json/index.js"
    sudo test ! -L "$APP/plugins/permission-json/package.json"
    sudo install -o root -g oc-harmony-agent -m 0550 server/permission-json/index.js "$APP/plugins/permission-json/index.js"
    sudo install -o root -g oc-harmony-agent -m 0550 server/permission-json/package.json "$APP/plugins/permission-json/package.json"
    sudo python3 scripts/configure-permission-plugin.py add permission-json

注册脚本检查隔离根标记及固定插件名，使用与手机渠道服务相同的文件锁，保留其他配置。备份、临时配置及最终配置均为0600，fsync后原子替换。备份可能含凭据，仅留在服务器私有配置目录。

保持 `OPENCODE_CONFIG_PROJECT_DISABLE=1`，不为加载插件开放各仓库的项目配置。使用**本实例全局配置**注册固定受信任插件，已部署实例通过配置监视加载，无需重启Agent/TLS或共享Nginx。

回滚仅撤销本插件注册：

    sudo python3 scripts/configure-permission-plugin.py remove permission-json

确认撤销后再决定是否保留插件文件。撤销会恢复上游400问题，客户端仍会保留卡片并禁用批准。不要直接用整个旧配置备份覆盖手机后来保存的渠道。

## 验证

本机回归：

    node tests/core.test.mjs
    node tests/state.test.mjs
    node tests/permission-metadata.test.mjs

设置服务依赖Linux fcntl，在Linux运行 `python3 tests/mobile_settings_test.py`，11项通过。上述Node测试为66项，合计77项。状态测试覆盖预览来源、上限、失败保留、手动恢复、批准前比较、失效/变更请求、丢回执不重发、切换连接和迟到轮询。

API26原生可重复验收：启动 `tests/fake-server.mjs`，用HDC把模拟器4210反向映射到PC4210，然后依次运行：

    node tests/approval-smoke.mjs connect
    node tests/approval-smoke.mjs preview
    node tests/approval-smoke.mjs failure
    node tests/approval-smoke.mjs recover
    node tests/approval-smoke.mjs approve

脚本默认target为本地模拟器，支持HDC_TARGET和OPENCODE_FIXTURE_PORT。fixture只监听127.0.0.1，不执行Agent。检查原生按钮enabled状态、展开折叠、恢复时零决策POST及最终一次带目录范围的once。

真实服务器读取：设置OPENCODE_TEST_URL、OPENCODE_PERMISSION_SESSION、OPENCODE_PERMISSION_DIRECTORY，运行 `node tests/permission-live.test.mjs`。测试要求存在真实待审批，不接受空列表冒充成功；认证/CA/SPKI从被忽略的本机标准测试材料读取。

服务器编码器红绿回归 `tests/permission-hook-live.test.mjs` 仅用于一次性隔离诊断实例：在插件安装目录并排放置production permission-json与 `tests/fixtures/permission-json-fixture` 的内容，**仅注册fixture**。在专用工作区根下创建approval-json-red/green两个目录，设置OPENCODE_PERMISSION_TEST_ROOT后运行。fixture只对harmony.fixture注入undefined，green调用真实normalizer；断言red400、green200及隔离性，不调用模型。完成后撤销并删除fixture，仅注册production插件。不要在运行中的生产实例为重跑此测试临时移除修复。

本轮实测证据分别为：

- 真实glob待审批从400变为200，API24原生显示目录和范围。其后搜索工具报30秒超时，不计为执行成功。
- API24真实Agent请求编辑三行测试样例，待执行patch为“你好，”→“早上好，”。原生拒绝收到SSE reject，实际Git Diff不变。
- API24另用明确标识的真实服务器纯协议请求验证批准前读取及SSE once回执；它不执行工具，不冒充新的成功文件修改。
- API26可控失败矩阵验证预览、读取失败保留、禁用批准、允许拒绝、手动恢复无POST及一次批准。
- 临时诊断插件已清除，专用服务和共享Nginx保持原进程运行。布局与截图在被忽略的.test目录。