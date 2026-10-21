# Sunshine 鸿蒙 USB 串流与虚拟显示器增强

## Channel 1.0.4 与安装包下载

**[打开 Release 下载页面](https://github.com/yinzhoufang/sunshine-harmony-usb/releases/tag/v1.0.4)**

| 文件 | 用途与安装要求 |
| --- | --- |
| `Channel-1.0.4-device-test.hap` | 鸿蒙平板端，当前已登记设备的调试签名测试包；不是任意设备通用包，也不是应用市场发布包。其他设备请从 pad 分支自行签名构建。 |
| `Sunshine-Harmony-USB-0.5.9-usb.3-Setup.exe` | Windows x64 补丁安装器，要求已安装兼容的 Sunshine 基地版 GUI 0.5.9 系列；不是完整 Sunshine。 |
| `Sunshine-Harmony-USB-0.5.9-usb.3.zip` | 同一 Windows 补丁的手动解压安装/恢复包。 |
| `SHA256SUMS.txt` | 下载附件的 SHA-256 校验值。 |

Channel 1.0.4 修复后台传输通知的类型和必需模板，每约 15 秒用真实收发量更新。单台 MatePad Pro 12.2 在“Channel 后台、最近任务上锁、Moonlight 全屏”条件下实测 960.19 秒：474 个连续样本、60 次通知成功、丢弃 0、双隧道断开样本 0、中继积压 0。平均实际流量约 2.86 Mbps，不能当作 40 Mbps 压力验收，也不保证所有设备无限后台运行。出现后台暂停时可使用分屏或悬浮窗。

当前源码使用普通网络与后台运行权限，未加入特殊 ACL。测试包在本机可用不代表该后台使用场景已通过应用市场审核。详见 [1.0.4 说明](docs/CHANNEL_1.0.4.md)。

Windows 功能仍为 0.5.9+usb.3，本次增加 EXE 安装入口；运行后按提示允许管理员授权。安装器会校验、备份并安装完整补丁，失败时显示错误。USB 串流另需 Python、华为官方 HDC、Channel 与 Moonlight。EXE 未配置代码签名证书。本项目不新增 DHCP 服务或开机自启动。

## 按平台选择

| 平台 | 分支 | 下载与使用 |
|---|---|---|
| 电脑 Windows | [pc 分支](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/pc) | [下载电脑补丁](https://github.com/yinzhoufang/sunshine-harmony-usb/blob/pc/downloads/Sunshine-Harmony-USB-0.5.9-usb.3.zip?raw=true)，或查看控制面板源码 |
| 鸿蒙平板 | [pad 分支](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/pad) | 下载平板桥源码，用 DevEco Studio 配置自己的设备签名后构建安装 |

平板分支提供 1.0.4 源码，Release 提供设备受限的调试 HAP，并非通用签名包。电脑补丁仍需已有兼容的 Sunshine 基地版。main 保留项目总览和原有下载入口。

让已安装 **Sunshine 基地版** 的 Windows 电脑增加两个入口：在设备中心切换网络 / 鸿蒙数据线传输，在虚拟显示器页面手动开关虚拟屏。

这是基于 [Sunshine Control Panel](https://github.com/qiin2333/sunshine-control-panel) **v0.5.9** 修改的社区补丁，不是完整 Sunshine 安装器，也不是 Sunshine 官方发行版。

## 0.5.9+usb.3：USB 映射自动恢复

修复 USB 重连或 HDC 转发规则丢失后，模式仍开启却无法访问应用列表的问题。正式中继每约 2 秒在独立线程中检查已选平板，只补缺失的七条映射，不覆盖冲突规则；切换模式时暂停修复，切回网络模式后停止恢复。不会新增开机自启动。

**从旧版升级：**结束当前串流，安装新版补丁，然后在设备中心关闭并重新开启一次鸿蒙数据线模式，使中继加载新逻辑。此操作会重启 Sunshine。若升级 Channel 1.0.4，可按新版后台使用说明操作；旧桥仍需分屏或悬浮窗。拔线导致的会话结束后，可能仍需手动重连 Moonlight。

验证：正式中继在七条映射全部被删除后约 **1.31 秒**自行补齐；135 项前端测试、10 项恢复专项测试以及既有模式切换 / 回滚 / 所有权测试通过。60.2 秒真实低负载观察中，双隧道失联样本 0、新增丢弃 0、中继积压最大 0 B。平均流量约 2.4 Mbps，**不作为本版 40 Mbps 满负载或操作延迟验收**。详见 [恢复说明](docs/USB_RECOVERY.md)。

## 下载与安装

**[下载 Windows 补丁 0.5.9+usb.3](downloads/Sunshine-Harmony-USB-0.5.9-usb.3.zip?raw=true)** · [SHA-256 校验](downloads/SHA256SUMS.txt)

1. 确认已安装适配的 Sunshine 基地版，控制面板版本为 **0.5.9 系列**，安装位置为 `C:\Program Files\Sunshine`。
2. 下载上面的补丁 ZIP，先完整解压，再进入补丁的解压目录，双击其中的 `安装集成版.bat`。
3. 接受 Windows 管理员授权。安装器会校验文件、备份原面板并处理程序占用。
4. 安装完成后打开 Sunshine，按下面的说明使用新增入口。

安装补丁本身不切换传输模式、不修改 Sunshine 端口，也不替换 Sunshine 核心程序。需要恢复时，运行同一包内的 `恢复原版面板.bat`。

## 能做什么

| 功能 | 入口 | 用途 |
|---|---|---|
| 鸿蒙数据线模式 | 设备中心 | 自动检查平板、切换主机端口、建立 HDC 映射并启动双隧道中继 |
| 恢复网络模式 | 设备中心 | 停止受管理的中继、清理映射并恢复记录的网络端口配置 |
| 虚拟显示器开关 | 虚拟显示器页面顶部 | 手动创建或关闭当前虚拟显示器；会话结束后仍保留虚拟屏时，可在这里关闭 |
| 状态与错误提示 | 对应功能卡片 | 显示设备、模式、操作进度、虚拟屏状态和失败原因 |

本项目不安装 DHCP 服务，也不新增开机自启动项。

### 虚拟显示器开关

- 需要已安装 ZakoVDD 虚拟显示器驱动，并且 Sunshine 核心支持 `api/tray` 中的 VDD 操作。
- 开启后，请在 **Keep Virtual Display?** 弹窗中点“是”保留；20 秒未确认会自动关闭。
- 关闭时会同时取消“保持开启”策略，避免关闭后被该策略再次保留。
- 若有客户端正在串流，关闭前会提示确认；关闭可能中断客户端画面。
- Sunshine 未运行、正在切换显示器或等待确认时，开关会暂时不可用。

开关控制当前虚拟显示器，不提供两台客户端各自显示不同桌面的独立会话功能，也不替代 Sunshine 原有的会话自动清理逻辑。

### 鸿蒙数据线串流

电脑需要 **Python 3**、可用的 **HDC**，平板需要 **USB 隧道伴侣** 和 **Moonlight**。平板还需开启 USB 调试并授权这台电脑。

1. 安装并启动平板端 USB 隧道伴侣，确认 HDC 能识别设备。
2. 在 Sunshine 的设备中心开启鸿蒙数据线模式，等待检查、映射和中继启动完成。
3. 在平板 Moonlight 手动添加 **`127.0.0.2`**，按正常流程配对并选择应用。
4. 结束使用后，关闭该模式切回网络传输。切换模式会重启 Sunshine，请先结束串流。

HDC 可放在系统 PATH 中，或放到 `C:\Program Files\Sunshine\tools\harmony-usb\hdc.exe`。HDC 由用户通过华为官方开发工具获得，本项目不附带分发。Python 也需另行安装。

平板桥仍是独立 App，**没有合并进 Moonlight**。仓库提供 [平板桥源码与构建说明](pad/README.md)，Release 提供设备受限的调试 HAP，其他设备仍需自行签名构建；不提供任意设备通用签名包。

## 传输方式

```text
平板 Moonlight → 平板 USB 桥 → USB / HDC TCP 转发 → 电脑中继 → Sunshine
```

- 平板媒体转发使用 C++ / NAPI 原生线程，ArkTS 负责界面、连接管理及低频统计。
- 视频使用 TCP 47997，控制与音频使用另一条 TCP 47996，减少视频排队对输入的影响。
- 输入上行优先；处理视频块时也会穿插检查控制数据。
- USB 模式下 Sunshine 端口基准使用 48989，切回网络模式时恢复此前记录的端口。
- HDC 负责建立长连接转发，不是每个数据包执行一次 `hdc shell`。

端口由模式切换脚本管理，**不要一边运行 Sunshine 一边手工编辑端口配置**。详细协议见 [docs/PROTOCOL.md](docs/PROTOCOL.md)。

## 兼容性与已知限制

- 已验证环境：Windows、Sunshine 基地版 / GUI 0.5.9、MatePad Pro 12.2（MRO-W00，HarmonyOS 6.1.1）。尚未在其他电脑和更多平板上验证。
- 安装器目前只接受默认安装路径及 GUI 0.5.9 / `0.5.9+usb.N`。有同版本面板不代表其他 Sunshine 核心一定兼容，VDD 接口与驱动仍需满足条件。
- Channel 1.0.4 在单台设备上通过后台上锁的 16 分钟观察；更多设备和更长时长仍待验证。后台暂停时可使用分屏或悬浮窗。
- 传输仍经过 TCP，可能受重传、调试通道调度和系统负载影响；不承诺固定的端到端延迟。
- 本项目没有提供虚拟显示驱动、完整 Sunshine、Python、HDC 或 Moonlight 安装器。
- 上游控制面板更新可能覆盖本补丁，更新 Sunshine 后请重新确认版本兼容性。

## 验证记录

前端 134 项、后端新增 4 项测试通过。真实界面已验证开关创建 / 关闭虚拟屏，未确认超时回退也已验证；本次自动验收的“保留”步骤通过本地核心接口确认，原生弹窗自动点击未完成。

此前在单台设备上进行的 60 秒 40 Mbps / 60fps 双向突发回显测试中：视频 214,285、控制 7,200、音频 6,000 包全部返回，桥 dropped 新增为 0；控制传输 RTT p50 / p95 / p99 为 6.113 / 16.264 / 23.695 ms。**这是传输回显耗时，不是操作到画面的完整延迟，也不代表所有设备的性能。**

详见 [docs/VALIDATION.md](docs/VALIDATION.md)。

## 源码目录

| 目录 | 内容 |
|---|---|
| `control-panel/` | 修改后的 Tauri / Vue 控制面板完整源码 |
| `pad/` | 平板桥 ArkTS + C++ / NAPI 源码，个人签名配置已去除 |
| `installer/` | Windows 补丁安装、恢复及运行时脚本源码 |
| `downloads/` | 可直接解压安装的 Windows 补丁 ZIP 与校验值 |
| `docs/` | 使用、协议、验证和故障排查说明 |

开发者构建说明见 [docs/BUILD.md](docs/BUILD.md)。普通用户请下载上方的补丁 ZIP，`installer/` 源码目录本身不含编译好的 EXE。

## 致谢与许可

控制面板基于 [qiin2333/sunshine-control-panel](https://github.com/qiin2333/sunshine-control-panel) v0.5.9（提交 `ca017d04abfe213020df1b31db93ce0f6ea11041`）修改，保留其 MIT 许可及原有版权声明。详见 [LICENSE](LICENSE) 和 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。Sunshine、Moonlight、HDC 和虚拟显示驱动属于各自项目。
