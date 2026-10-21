# Channel 1.0.4：后台稳定性与安装说明

Channel 是独立的鸿蒙 USB 串流桥，需要配合 Moonlight 和电脑端 Sunshine 补丁使用，没有合并进 Moonlight。

## 平板 HAP 安装限制

Release 中的 Channel-1.0.4-device-test.hap 是已经在开发者登记设备上安装验证的调试签名包。它不是通用签名发行版；其他用户下载后可能因设备不在 Profile、签名授权或有效期不匹配而无法安装。开启开发者模式不会自动解除签名设备限制。

其他设备请打开 pad 分支源码，用自己的 DevEco Studio、开发者账号和设备签名构建。当前仅验证 MatePad Pro 12.2、HarmonyOS 6.1.1；ABI 为 arm64-v8a。上架还需 release 构建与发布证书/Profile，不能上传本调试 HAP。

已授权设备可通过官方 HDC 执行：

```powershell
hdc install -r Channel-1.0.4-device-test.hap
```

安装后打开 Channel，在电脑 Sunshine 设备中心启用鸿蒙数据线模式，Moonlight 添加 127.0.0.2。可先在最近任务里给 Channel 上锁，再切 Moonlight 全屏；不能保持后台运行时改用分屏/悬浮窗。

## 本轮修复与证据

- 历史系统日志证明：传输长时任务通知十分钟未更新，被系统移除，随后 Channel 冻结、控制流断开。
- 1.0.1 尝试 multiDeviceConnection，系统判定未使用对应多设备能力，该实验失败。
- 1.0.2 加入真实收发量通知更新，因通知类型不匹配而失败。
- 1.0.3 修正为公开系统实况通知类型后，仍缺少系统要求的更新模板。
- 1.0.4 同时使用公开通知常量和 downloadTemplate，只显示真实字节量，省略可选 progressValue。无假百分比、无假音频、无后台循环重新申请取消任务。

约每 15 秒更新一次，且只在双隧道连接并有实际流量增加时刷新。高频媒体转发仍为原有 C++ 双隧道与输入优先调度，没有调整中继 2 MiB 队列或收紧丢弃阈值。

2026-10-21 后台上锁实测：960.19 秒，474 样本覆盖 959.588 秒，最长统计间隔 2.099 秒；同一进程无回前台记录。60 次通知成功，最长通知间隔 16.341 秒。通知错误、任务取消/暂停、丢弃、双隧道断开样本均为 0；中继 buf 最大 0 B。实际 min/avg/max 1.9/2.86/7.3 Mbps，Sunshine 新增异常/重配 0。15 项生命周期与通知行为测试通过。

本次是单设备、通知修复与后台上锁组合观察。未单独隔离上锁效果，不等于 40 Mbps 长测，不保证永久后台常驻。公开汇总去除了进程 ID 和原始系统日志。

## Windows EXE

Sunshine-Harmony-USB-0.5.9-usb.3-Setup.exe 是完整补丁 ZIP 的安装入口，不是把面板 EXE 单独改名。要求 Windows x64、.NET Framework 4.5 或以上及兼容的 Sunshine 基地版 GUI 0.5.9 系列，默认安装路径 C:\Program Files\Sunshine。

运行安装器后确认安装、允许管理员授权。内部安装脚本检查版本及哈希、备份面板，再安装控制面板和配套中继文件；安装本身不切换 Sunshine 传输模式。Windows 补丁核心功能仍为 0.5.9+usb.3：USB 映射自动恢复、网络/USB 模式切换及虚拟显示器开关。

安装文件会保留在本机 LocalAppData/Sunshine-Harmony-USB/Packages/ 下；恢复原面板可运行对应目录内“恢复原版面板.bat”。也可使用 Release 的 ZIP 完整解压后安装和恢复。不包含完整 Sunshine、Python、HDC、Moonlight 或 VDD 驱动。EXE 未配置数字代码签名。

## 权限与发布

当前只声明 INTERNET、GET_NETWORK_INFO、KEEP_BACKGROUND_RUNNING，均为普通 normal/system_grant 权限；backgroundModes 为 dataTransfer。不需要为当前源码先申请 SPECIAL_SCENARIO ACL，也不因使用 C++ 而增加特殊权限。应用市场是否接受持续串流代理的后台使用场景仍待实际审核，不能把设备实测成功等同于审核通过。
