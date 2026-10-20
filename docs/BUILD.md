# 开发构建

## Windows 控制面板

先按 `control-panel/README.md` 准备上游项目的 Node、Rust、Windows C++ 构建工具及 WebView2 环境。

在 `control-panel` 目录执行：

```powershell
npm ci
npm run test:renderer
npm run build:renderer
cargo test --locked --manifest-path src-tauri/Cargo.toml virtual_display
cargo build --release --locked --manifest-path src-tauri/Cargo.toml
```

请以 `control-panel/package.json` 中的脚本为准。最终程序位于 `control-panel/src-tauri/target/release/sunshine-gui.exe`。

制作安装包时，把最终 EXE 与 `installer/` 的文件放在同一个目录，重新生成 `manifest.json` 中 EXE 及 `harmony-usb/` 运行文件的 SHA-256。修改程序后不能继续使用旧清单。

安装器会请求 Windows 管理员授权，验证适配版本和清单后备份并更新面板。不要直接覆盖正在运行的 EXE。

## HarmonyOS 平板桥

用 DevEco Studio 打开 `pad/`。本仓库去除了开发者私有签名配置、设备列表、私钥及证书，需要使用自己的开发者账号和设备重新配置签名。

构建前安装项目所需的 HarmonyOS SDK、Native 工具链和依赖。通过 DevEco 管理依赖并构建；原生入口为 `entry/src/main/cpp/CMakeLists.txt`。如果命令行构建提示找不到 Java，请配置 `JAVA_HOME` 并将其 `bin` 加入 PATH。

平板源码里的包名 `com.chenfang.usbtunnel` 同时用于电脑模式脚本检查桥是否已安装；若改包名，需要同步修改脚本。

桥的设计、依赖和当前限制见 `pad/README.md`。请勿把个人生成的签名配置、证书、私钥、设备名单或已绑定开发设备的 HAP 提交到公开仓库。
