# Channel 1.0.4（HarmonyOS 平板端）

通过 USB / HDC 把原版 Moonlight 与 Windows Sunshine 连接起来的独立桥 App。媒体转发使用 C++ / NAPI，视频和控制/音频分为两条 TCP 隧道；ArkTS 负责界面、生命周期、TCP 代理和统计。

## Channel 1.0.4 与安装包下载

**[打开 Release 下载页面](https://github.com/yinzhoufang/sunshine-harmony-usb/releases/tag/v1.0.4)**

| 文件 | 用途与安装要求 |
| --- | --- |
| `Channel-1.0.4-device-test.hap` | 鸿蒙平板端，当前已登记设备的调试签名测试包；不是任意设备通用包，也不是应用市场发布包。其他设备请从 pad 分支自行签名构建。 |
| `Sunshine-Harmony-USB-0.5.9-usb.3-Setup.exe` | Windows x64 补丁安装器，要求已安装兼容的 Sunshine 基地版 GUI 0.5.9 系列；不是完整 Sunshine。 |
| `Sunshine-Harmony-USB-0.5.9-usb.3.zip` | 同一 Windows 补丁的手动解压安装/恢复包。 |
| `SHA256SUMS.txt` | 下载附件的 SHA-256 校验值。 |

Channel 1.0.4 修复后台传输通知的类型和必需模板，每约 15 秒用真实收发量更新。单台 MatePad Pro 12.2 在“Channel 后台、最近任务上锁、Moonlight 全屏”条件下实测 960.19 秒：474 个连续样本、60 次通知成功、丢弃 0、双隧道断开样本 0、中继积压 0。平均实际流量约 2.86 Mbps，不能当作 40 Mbps 压力验收，也不保证所有设备无限后台运行。出现后台暂停时可使用分屏或悬浮窗。

当前源码使用普通网络与后台运行权限，未加入特殊 ACL。测试包在本机可用不代表该后台使用场景已通过应用市场审核。详见 [1.0.4 说明](../docs/CHANNEL_1.0.4.md)。

Windows 功能仍为 0.5.9+usb.3，本次增加 EXE 安装入口；运行后按提示允许管理员授权。安装器会校验、备份并安装完整补丁，失败时显示错误。USB 串流另需 Python、华为官方 HDC、Channel 与 Moonlight。EXE 未配置代码签名证书。本项目不新增 DHCP 服务或开机自启动。


## 自行构建

在 DevEco Studio 打开本分支根目录，用自己的账号和设备配置签名。仓库 build-profile.json5 已去除个人签名。显示名称为 Channel，包名为 com.chenfang.usbtunnel。

源码路径：entry/src/main/cpp/tunnel.cpp（媒体转发）、entry/src/main/ets/bridge/BackgroundSession.ets（后台任务与通知）、TunnelBridge.ets（生命周期和 TCP 代理）、entry/src/main/ets/pages/Index.ets（界面）。

详情见 docs/BUILD.md、../docs/CHANNEL_1.0.4.md 和 ../docs/PROJECT_NOTES.md。
