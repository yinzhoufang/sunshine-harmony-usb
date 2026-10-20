# USB 隧道伴侣 · 鸿蒙平板端（pad 分支）

电脑安装包和控制面板源码请前往 [pc 分支](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/pc)，项目总览见 [main](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/main)。

本分支的工程已放在根目录。可使用 GitHub 的 Code → Download ZIP 下载源码，解压后直接用 DevEco Studio 打开工程目录。

独立于 Moonlight 的桥 App，让原版 Moonlight 可以通过 USB / HDC 隧道连接 Windows Sunshine。当前仍需同时运行 Moonlight 和本 App。

媒体数据由 C++ / NAPI 原生工作线程处理，视频与控制 / 音频使用双 TCP 隧道；ArkTS 负责界面、连接管理、TCP 代理与低频统计。

## 安装前

本仓库不提供适用于所有平板的通用签名 HAP。请在 DevEco Studio 打开本目录，使用自己的开发者账号、设备及签名构建后安装。根目录 `build-profile.json5` 的个人签名配置已清空。

已验证设备为 MatePad Pro 12.2（MRO-W00），HarmonyOS 6.1.1。未验证其他型号，平台基础兼容版本不等同于每台设备均可正常工作。

## 使用

1. 电脑安装 [pc 分支的 Sunshine 面板补丁](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/pc)、Python 3 与 HDC。
2. 平板安装本 App 和 Moonlight，开启 USB 调试并授权电脑。
3. 在 Sunshine 设备中心启用鸿蒙数据线模式，等待隧道就绪。
4. 以分屏或悬浮窗保持本 App 可见，在 Moonlight 添加 `127.0.0.2`，配对并开始串流。

后台冻结 / 回收仍是已知限制，当前不保证长时间纯后台运行。网络与 USB 模式通过电脑面板切换，不要手工编辑 Sunshine 的端口。

## 主要文件

| 文件 | 用途 |
|---|---|
| `entry/src/main/cpp/tunnel.cpp` | 原生媒体工作线程、双隧道与输入优先调度 |
| `entry/src/main/cpp/napi_init.cpp` | NAPI 接口 |
| `entry/src/main/ets/bridge/TunnelBridge.ets` | 隧道生命周期、UDP 管理和 TCP 转发 |
| `entry/src/main/ets/bridge/Frames.ets` | 三字节帧头 |
| `entry/src/main/ets/bridge/Config.ets` | 地址及端口配置 |
| `entry/src/main/ets/pages/Index.ets` | 控制界面与统计 |

协议见仓库 `docs/PROTOCOL.md`，构建见 `docs/BUILD.md`。
