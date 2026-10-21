## Channel 1.0.4 更新日志

- 优化后台传输稳定性，改善长时间串流时的连接保持。
- 修复传输通知更新失败的问题，持续显示实际收发数据量。
- 完善后台任务的启动、停止及状态提示。
- 优化后台任务异常处理，减少状态显示与实际运行情况不一致的问题。

建议更新后重新打开 Channel，再连接 Moonlight 开始串流。本次只在已验证设备上完成后台上锁的 16 分钟观察，不保证所有设备无限后台运行。
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


## 使用步骤

1. 电脑已有兼容 Sunshine 基地版，下载 Setup.exe 安装补丁并允许管理员授权。
2. 平板 HAP 仅适用于调试 Profile 已登记设备，其他设备自行签名构建。
3. 电脑安装 Python 和华为官方 HDC；平板开启 USB 调试，打开 Channel。
4. Sunshine 设备中心打开鸿蒙数据线模式，Moonlight 添加 127.0.0.2 并配对串流。
5. Channel 可先在最近任务上锁后退到后台；后台暂停时使用分屏/悬浮窗。

