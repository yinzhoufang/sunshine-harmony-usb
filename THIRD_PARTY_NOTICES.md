# 上游与第三方组件

- 本仓库的控制面板及编译后的 `sunshine-gui.exe` 基于 https://github.com/qiin2333/sunshine-control-panel 的 v0.5.9 / `ca017d04abfe213020df1b31db93ce0f6ea11041`，保留上游 MIT License。完整上游文件与本项目修改后的源码位于 `control-panel/`。
- 上游 Node 与 Rust 依赖分别记录在 `control-panel/package-lock.json` 和 `control-panel/src-tauri/Cargo.lock`。各依赖保留自身许可证；控制面板内原有许可文件随源码提供。
- HarmonyOS 桥项目中的平台模板文件保留原有版权及许可证注释。
- 补丁不分发 Sunshine 核心、Moonlight、HDC、Python、Windows WebView2 或虚拟显示器驱动；请通过各项目和厂商渠道取得。相应名称和图标归各自权利人所有。

本项目是社区修改版，不表示获得上游项目或华为的官方背书。
