# 平板桥构建与安装

本分支工程位于根目录，源码由主项目的 pad/ 目录整理而来，运行代码保持一致。电脑端见 [pc 分支](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/pc)。

## 构建步骤

1. 在本分支使用 Code → Download ZIP 下载并解压工程，或用 Git 克隆 pad 分支。
2. 用 DevEco Studio 打开工程根目录，安装项目需要的 HarmonyOS SDK 与 Native 工具链，管理并安装项目依赖。
3. 使用自己的开发者账号和设备配置签名。仓库的 build-profile.json5 不含原开发者私有签名，不能直接复用别人的开发签名 HAP。
4. 构建 entry 模块的 HAP，连接自己的平板，允许 USB 调试并安装。
5. 启动 USB 隧道伴侣，配合电脑端鸿蒙数据线模式与 Moonlight 使用。

原生入口为 entry/src/main/cpp/CMakeLists.txt。若命令行构建提示找不到 Java，请配置 JAVA_HOME 并将其 bin 加入 PATH。

Windows 上若原生类型依赖无法建立链接，可将 entry/src/main/cpp/types/libusbtunnel 复制到 entry/oh_modules/libusbtunnel.so 后重试构建。

包名 com.chenfang.usbtunnel 同时用于电脑脚本检查桥是否已安装；改包名时需同步修改电脑脚本。

## 签名与使用范围

当前未提供通用已签名安装包，开发签名通常需要登记目标设备。请在自己的开发环境配置签名，不要提交私钥、证书、设备名单或个人签名配置。

已验证 MatePad Pro 12.2（MRO-W00）与 HarmonyOS 6.1.1；其他设备尚未验证。后台冻结 / 回收仍是已知限制，当前建议以分屏或悬浮窗保持桥可见。

协议见 [PROTOCOL.md](PROTOCOL.md)，已验证范围见 [VALIDATION.md](VALIDATION.md)。
