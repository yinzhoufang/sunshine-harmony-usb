# Channel：项目对话精华与发布核验

更新日期：2026-10-21。本文是经过代码、产物及实测记录核对的对话摘要，不是逐字聊天记录。历史推测与已经验证的结论分开记录。

## 1. 先看当前结论

| 项目 | 2026-10-21 核验结果 |
| --- | --- |
| 应用名称 | Channel，原称 USB 隧道伴侣；此前对话中的 label 通常指这个桥应用 |
| 工程位置 | `C:\Users\<用户>\Desktop\bridge-shine\pad` |
| 包名 | `com.chenfang.usbtunnel`；显示名称改变不等于包名改变 |
| 当前源码版本 | **1.0.4，versionCode=1000004** |
| 最新本机安装 HAP | `entry/build/default/outputs/default/entry-default-signed.hap`，已核验内部版本为 1.0.4、buildMode=debug |
| 工程里现存的 APP | `build/outputs/default/pad-default-signed.app`，**内部仍为 1.0.0**；同目录 unsigned APP 也不是本轮重新构建的发布产物 |
| 当前签名 | 根目录 `build-profile.json5` 使用 default 自动调试签名；读取对应 `.p7b` 已确认 `type=debug`，ACL 列表为空 |
| 能否编译最新功能 | 源码已具备最新功能，1.0.4 的签名 HAP 构建、安装已成功 |
| 能否按现配置直接正式上架 | **不能。** 现有 APP 版本过旧，当前签名也不是发布签名；需要发布证书、发布 Profile、release 构建及重新生成 APP |
| 本轮是否增加特殊 ACL | **没有。** 当前使用三项 normal/system_grant 权限，见第 7 节 |
| 是否已集成到 Moonlight | **没有。** 目前仍是 Channel 和 Moonlight 两个应用，合并只是讨论过的后续方向 |
| GitHub 是否包含本轮版本 | 本摘要形成时尚未同步；本次提交已同步 1.0.4 源码，Release 附件状态请以 Releases 页面为准 |

注意：构建模式和签名类型是两件独立的事。选择 release 不会自动把调试 Profile 变成发布 Profile；文件名含 signed 也不代表使用了发布签名。

## 2. 项目解决什么问题

让鸿蒙平板通过 USB 数据线串流 Windows 电脑的 Sunshine，并由平板上的 Moonlight 显示画面、传回输入。Channel 负责协议转发，既不是视频播放器，也不替代 Sunshine 或 Moonlight。

当前链路：

```text
电脑 Sunshine
  ↕ 本机 UDP / TCP
电脑中继及端口转发
  ↕ HDC rport，经 USB 数据线
平板 Channel
  ↕ 平板内部 UDP / TCP
平板 Moonlight
```

Moonlight 在 USB 模式添加 `127.0.0.2`。它是平板自己的回环地址，由 Channel 提供代理，并不是电脑的局域网 IP。网络模式应使用电脑真实网络地址。

USB 是物理连接及协议基础，HDC 是借助 USB 提供调试、日志、安装和端口转发的软件。当前媒体通过持续的 socket 连接和 HDC 端口映射传输，并不是每发一个包就执行一次 `hdc shell`。

自行实现 USB 传输意味着替换 HDC 的转发层；仍然使用 USB，且要重新解决接口开放、设备角色、权限、驱动及恢复机制。尚未证明直接 USB 一定比 HDC 更快，也未证实当前鸿蒙普通应用具备所需的全部设备侧接口。

## 3. 已实施的低延迟优化

### 3.1 原生媒体转发

高频 UDP 媒体收发、隧道解析及转发已迁移到 `entry/src/main/cpp/tunnel.cpp`。ArkTS 保留界面、生命周期、后台任务、TCP 代理和低频统计。

旧路径每个包要进入 ArkTS，再调用异步 `udp.send`，还要处理发送结果。当前 C++ 模块直接在原生工作循环中使用 `recv`、`recvfrom`、`sendto` 等系统接口，减少逐包跨运行环境交接和异步任务管理。

C++ **同样需要调用系统接口、检查返回结果**，并没有绕过操作系统。性能收益来自具体结构、调度与内存处理的改善，不能宣称天然固定快 10～20 倍，也不能把所有提升归因于语言。

### 3.2 双隧道和输入调度

- 视频 ch0 走 TCP `47997`。
- 控制 ch1 与音频 ch2 走独立 TCP `47996`。
- 两条隧道均双向、独立分帧及重连；减少视频在本层排队对控制的影响，但底层 USB/HDC 仍共享。
- 当前正式调度保持一个 socket 所有者，优先服务输入/控制；每处理约 8 个视频数据报检查控制，避免等待整批视频处理结束。
- 曾试验双原生线程，视频尾部延迟变差，未采用为正式默认方案。
- 分帧头保持 3 字节：1 字节通道编号 + 2 字节大端长度；随后原样携带 UDP 数据报。

### 3.3 不能改坏的边界

1. PC 中继 `MAX_QUEUE_BYTES` 保持 **2 MiB**；不要盲目缩到 256 KiB。
2. 不要把历史 ArkTS 桥下行丢弃阈值从 64 收紧到 24。原生代码的 `BATCH=64` 是公平调度预算，不是该丢弃阈值。
3. 不恢复“下行未完成 Promise 发送数量”限流。JS 高负载下回调滞后曾造成计数只增不减、永久丢视频及黑屏。
4. 下行按客户端实际来源地址和端口回包；ENet 控制端口不保证固定。
5. TCP 代理必须缓存 upstream 建立前的客户端数据，连接完成后补发。
6. Sunshine 端口切换使用维护中的模式切换工具；不手改运行中的 sunshine.conf，避免服务回写覆盖。
7. 当前原生桥不会按 RTP 时间戳识别并丢弃旧视频帧；这是讨论方向，尚未实施。

## 4. 哪些数据证明优化有效

各类测试测量对象不同，不混用结论：

| 证据 | 结果及含义 |
| --- | --- |
| PC loopback | 10～100 Mbps 零丢包，40 Mbps 时中继 p50 抖动约 0.33 ms，说明电脑端本地链路具备吞吐能力 |
| 真机 HDC 吞吐 | 已验证 120 Mbps 吞吐、100% 送达；不能单凭吞吐推导操作延迟 |
| 原生正式 v3，60 秒 40 Mbps/60fps 突发回显 | 视频 214285、控制 7200、音频 6000，全部回显；桥丢弃 0，双隧道失联样本 0 |
| 同轮控制 RTT | p50/p95/p99 约 6.113/16.264/23.695 ms；视频 RTT p99 26.386 ms；空载控制 RTT p50 4.427 ms |
| 用户实际反馈 | 原生双隧道后“明显改善，已经可玩”；输入调度进一步优化后“进一步改善” |

回显 RTT 包含往返传输、平板转发和 PC 调度，**不包含游戏响应、编码、解码及屏幕显示**，不能直接叫作操作到画面的延迟。前后测试存在系统波动，不能把全部差值归因于某一次修改。

40 Mbps 约为 5 MB/s；当前包大小下约 3500 包/秒，平均每包间隔约 0.286 ms。60fps 每帧间隔约 16.7 ms。实际数据突发到达，平均带宽足够不代表处理与排队延迟足够低。

## 5. 后台断连原因及版本过程

### 5.1 已证实的旧问题

持久化系统日志显示多轮相同过程：数据传输长时任务通知约十分钟未更新 → 系统移除通知并终止任务 → 资源调度冻结 Channel → Sunshine 控制流断开。

关键系统记录包括 `more than 10 min not update notification, notification remove` 和随后的 Freeze 成功。应用可能仍保留进程及旧日志；重新打开后继续打印，不能据此认定后台期间一直在运行。

有一次 20:45:10 的断连，用户后来明确更正为自己取消；不计为自动掉线证据。

### 5.2 实验版本

| 版本 | 修改 | 真机结果 |
| --- | --- | --- |
| 1.0.1 | 统一后台任务生命周期管理，尝试 multiDeviceConnection | 系统判定没有使用对应多设备能力，暂停任务并冻结；该方案失败 |
| 1.0.2 | 回到 dataTransfer，真实流量增加时每约 15 秒更新收发量通知 | 使用返回的通知类型值造成类型和内容不匹配，发布报 401 |
| 1.0.3 | 使用公开的系统实况通知类型常量 | 仍报 401；系统进一步明确 `Owner must has template to update` |
| **1.0.4** | 补充 downloadTemplate，显示真实累计收发量，省略可选 progressValue | 系统接受通知更新；通过本轮后台上锁的 16 分钟观察 |

1.0.4 在实际传输增加、双隧道连接、任务有效时刷新通知；不伪造下载完成百分比，不用假音频保活，不在后台循环重新申请被取消的任务。处理启动/停止竞态、任务取消、挂起及恢复，界面显示实际保护状态。

### 5.3 1.0.4 长测结果及限制

2026-10-21，用户确认最近任务已上锁、Moonlight 全屏、Channel 在后台。系统记录 17:43:01 进入后台；随后采样 960.19 秒，至 17:59:45：

- 474 个统计样本，覆盖 959.588 秒；最长统计间隔 2.099 秒。
- 同一个桥进程，无切回前台记录。
- 60 次通知更新成功；最长更新间隔 16.341 秒。
- 没有通知失败、任务取消或暂停记录。
- 桥丢弃新增和累计均 0，双隧道断开样本 0，中继 buf 最大 0 B。
- Sunshine 新增异常/重配行 0。
- 实际码率 min/avg/max：1.9 / 2.86 / 7.3 Mbps。

结论：**“1.0.4 通知修复 + 用户后台上锁”组合通过本轮后台稳定性观察。** 未单独测试只上锁或不上锁的效果；未证明无限时长、全部系统版本和设备都稳定；该低动态样本不是 40 Mbps 长测。

原始证据在本机工作区 `work/channel104-background-locked`，汇总为 `background_result.json`；不应把含设备或用户信息的原始系统日志直接公开。

## 6. 常见概念的准确解释

| 概念 | 含义 |
| --- | --- |
| HarmonyOS | 操作系统，管理硬件、内存、网络及应用生命周期 |
| ArkTS | 编程语言，不是 IDE，也不是解释器 |
| DevEco Studio | 写代码、调试、构建鸿蒙应用的开发工具 |
| 方舟编译与运行体系 | 转换、执行代码并管理运行环境；不能简单认定 ArkTS 每行都必须现场翻译 |
| UDP | 按数据报收发的网络传输协议；在 Channel 与 Moonlight 之间主要是平板内部回环通信，不代表使用 Wi-Fi |
| udp.send | ArkTS 网络接口的一次 UDP 发送请求，底层最终调用原生系统网络实现 |
| Promise | 表达“稍后完成或失败”的异步操作结果；不是网络协议，不必然意味着所有包串行等待 |
| 原生接口 | 程序调用底层能力的入口，例如 sendto；不是物理插口 |
| NAPI / Node-API | 连接 ArkTS/JS 环境和 C/C++ 模块的接口；媒体包不需要逐个跨此边界交接 |
| HAP | 模块安装包，当前本机测试安装的是它 |
| APP | 打包 HAP/HSP 等内容的应用分发产物；扩展名相同也可能版本、构建模式或签名不同 |
| ACL | 受限权限的额外授权机制，不等于应用所有普通权限 |

Promise 成功通常只表示本次发送操作按接口定义完成，并不证明 Moonlight 收到、解码或显示了这一包。C++ 的 sendto 也有返回结果，只是由 C++ 自己处理。

Python 适合电脑端工具和快速开发；把当前平板 C++ 转发换为 Python，没有已知提速依据，反而可能增加解释器、对象和调用开销。最终仍应实测，不能把语言名称直接当性能结论。

## 7. 权限：现在是否需要额外向华为申请

已核对 `entry/src/main/module.json5` 及本机 SDK 的 PermissionDefinitions.json：

| 当前声明 | 用途 | SDK 级别/授权方式 |
| --- | --- | --- |
| ohos.permission.INTERNET | 网络套接字通信 | normal / system_grant |
| ohos.permission.GET_NETWORK_INFO | 读取网络状态 | normal / system_grant |
| ohos.permission.KEEP_BACKGROUND_RUNNING | 申请长时后台任务 | normal / system_grant |

EntryAbility 的 backgroundModes 当前只有 `dataTransfer`。本轮普通能力已在无额外 ACL 的调试 Profile 下运行成功；**当前实现不要求先申请新的受限 ACL，也不因使用 C++ 而需要额外特殊权限。**

没有声明 `ohos.permission.KEEP_BACKGROUND_RUNNING_SPECIAL_SCENARIO`。本机 API 24 的定义把它列为 system_basic；这是另一条特殊场景路线，不能与当前普通 dataTransfer 混为一谈。今后如果改用它，才应核查相应 ACL、Profile 和能力申请条件。

权限可调用、设备实测可用、应用市场接受该使用场景，是三个不同问题。官方 dataTransfer 文档围绕上传下载任务及通知更新；当前持续串流代理的上架场景尚未经审核验证。提交时应真实说明持续收发数据、可见通知、停止机制和依赖电脑端中继的使用方式；如平台要求补充业务说明或指定能力，以实际审核意见处理，不能预先保证一定免申请、一定过审。

## 8. 最新源码如何准备发布 APP

本机 DevEco Studio 版本核验为 **6.1.1.280**。按这台机器的现有工具链：

1. 在华为开发者后台使用与工程一致的包名 `com.chenfang.usbtunnel` 创建/选择 Channel。所属项目只是后台的管理分组，不决定本机源码位置。
2. 准备发布密钥库、匹配的发布证书和发布 Profile。不要把当前自动调试 Profile 当成发布 Profile。
3. 在 DevEco 的 `File → Project Structure → Project/Product → Signing Configs` 配置发布材料。根目录 `build-profile.json5` 中的 signingConfigs 保存签名方案，products 选择方案；不是在 AppScope 或 entry 中照搬 Android 的签名结构。
4. 把构建模式选为 **release**。该模式独立于签名配置；工程已经定义 debug/release 两种模式。不要寻找 Android 的 Build Variants 面板，也不要跳过 release 设置。
5. 选择 `Build → Build Hap(s)/APP(s) → Build APP(s)`，重新生成项目级 APP；菜单文字会随 IDE 版本略有差别。
6. 查看 `pad/build/outputs/default/` 下的新产物，核验内部版本确为 1.0.4、release 构建、发布 Profile、包名匹配；不能只看文件名或生成时间。
7. 在 AGC 上传新 APP，按实际情况补全图标、截图、简介、隐私说明、审核测试步骤及平台要求的资料，再提交审核。

当前源码、默认签名配置中并未配置一套已验证的发布材料，所以不能说“现在点 Build APP 就能直接正式上架”。本次整理没有替换签名、生成新 APP 或代替用户提交审核。

设备兼容性也应与测试范围匹配：目前只构建 arm64-v8a，真机验证对象为 MatePad Pro 12.2；manifest 另列 phone/tablet/2in1/wearable，不能据此宣称所有这些形态均已支持、验证。发布选择的设备范围应与实际支持能力一致。

本机签名配置、私钥、密码、设备标识不写入此摘要，也不随公开源码上传。SDK 配置、OAuth Client Secret、Server SDK 凭据不是普通离线转发所必需，不应为发布此功能而随意启用云服务。

## 9. 构建、安装和验收入口

本机测试 HAP 的现行构建步骤：

```powershell
$env:NODE_HOME="C:\Program Files\Huawei\DevEco Studio\tools\node"
$env:NODE_PATH="C:\Users\<用户>\Desktop\bridge-shine\pad\node_modules"
$env:DEVECO_SDK_HOME="C:\Program Files\Huawei\DevEco Studio\sdk"
$env:JAVA_HOME="C:\Program Files\Huawei\DevEco Studio\jbr"
$env:PATH="$env:JAVA_HOME\bin;$env:NODE_HOME;$env:PATH"
cd C:\Users\<用户>\Desktop\bridge-shine\pad
& "$env:NODE_HOME\node.exe" "C:\Program Files\Huawei\DevEco Studio\tools\hvigor\hvigor\bin\hvigor.js" `
  --mode module -p module=entry@default -p product=default assembleHap --no-daemon
hdc install -r entry\build\default\outputs\default\entry-default-signed.hap
```

以上是本机调试 HAP 流程，**不是发布 APP 流程**。HDC 可能在失败时仍返回 0，应检查输出确实含安装成功；锁屏可能阻止启动，需要解锁。

验收使用 `pc端/stutter_probe.py`，配合平板 UsbTunnel hilog、实际中继日志和 Sunshine 日志。安装后的管理版中继日志位于 `C:\ProgramData\Sunshine\harmony-usb\relay_run.log`，不要只读源码目录中的旧日志。

```powershell
python C:\Users\<用户>\Desktop\bridge-shine\pc端\stutter_probe.py --seconds 60 `
  --relay-log C:\ProgramData\Sunshine\harmony-usb\relay_run.log
```

正式采样必须持续读取新日志，`hilog -x` 只是历史快照。检查 dropped、buf、send_errors、protocol_errors、reconnects、双隧道状态及实际动态流量；包统计不能替代黑屏、手感和端到端延迟体验确认。

## 10. 其他有价值的结论和后续方向

- USB 映射缺失是电脑 HDC/转发管理链路的问题，不能只凭“Moonlight 无应用列表”归咎平板。电脑端已实施映射守护恢复，需同时检查中继、七条映射和 Channel 是否运行。
- 以太网曾出现能看到电脑地址但添加失败，DHCP 修复后进入配对/应用列表；该次证据不支持直接归因为插件改端口。DHCP 负责自动分配 IP、子网等参数，不是加速串流的工具。后续用户要求已移除相关 DHCP 内容和关闭对应自启动，不应擅自重新开启。
- Windows Sunshine 插件和鸿蒙 Channel 是两个组件；给别人使用不能仅发送平板源码或调试 HAP，也不能假设对方已有所需电脑侧中继、映射工具和驱动授权。GitHub Release 可提供明确版本的下载产物；pad/pc 分支用于源码组织，不替代正式发布包。
- 退出会话后虚拟显示器清理、手动虚拟显示器开关属于电脑端功能；是否包含于某个分发包，需要核验该 PC 包，不能从 pad 版本推断。
- 下一步优先测 Moonlight 解码/帧队列、Sunshine 捕获编码、控制流排队及端到端操作延迟；只有发现桥仍有处理尖峰时，再优化原生复制、分配和收发循环。
- 60fps 下一帧间隔约 16.7 ms，减少一帧等待可能比继续优化已很快的转发更有收益。更小的队列不自动等于更低延迟，先测量再改。

## 11. 官方核对入口

- [工程级 build-profile 的签名配置说明](https://developer.huawei.com/consumer/cn/doc/doccenter-deveco-studio/ide-hmos-hvigor-build-profile-app)：签名材料、products 与构建配置。
- [应用包上传常见问题](https://developer.huawei.com/consumer/cn/doc/doccenter-testing/agc-help-cloudtest-faq-0000002255036920)：release 模式和发布证书/Profile 需要分别核对。
- [后台任务接口与通知示例](https://developer.huawei.com/consumer/cn/doc/harmonyos-references-V14/js-apis-resourceschedule-backgroundtaskmanager-V14)：长时任务及通知更新接口；不同 API 版本应对应查阅。
- [长时任务开发指南](https://developer.huawei.com/consumer/cn/doc/harmonyos-guides/continuous-task)：当前使用场景和限制应以华为最新文档、实际平台反馈为准。
- [申请调试 Profile](https://developer.huawei.com/consumer/cn/doc/doccenter-getting-started/agc-help-debug-profile-0000002248181278)：调试设备绑定与可选 ACL 授权机制。

本文刻意保留“未验证”和失败实验的记录，避免后续把讨论过的功能当成已完成、把本机调试成功当成已具备上架资格。
