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

## 配套平板端

平板桥独立保存在 [pad 分支](https://github.com/yinzhoufang/sunshine-harmony-usb/tree/pad)，其工程位于该分支根目录。签名与构建步骤见 [平板构建说明](https://github.com/yinzhoufang/sunshine-harmony-usb/blob/pad/docs/BUILD.md)。
