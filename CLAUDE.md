# Android Codex 工程说明

本仓库当前只维护独立的 Android 本地 Codex App。产品不依赖 Windows/Linux/macOS Bridge，
不恢复远程机器连接、WebSocket Bridge、Claude Code 或旧多平台 App 路线。

## 当前实现路线

- 前端复用 `packages/ccpocket_ui` 的 CC Pocket 信息架构、session 交互和会话组件。
- 主应用位于 `apps/codex`，负责 Android 本地 workspace、session、app-server、登录、设置和
  Root/PRoot runtime 接入。
- 默认执行环境是用户配置的 KernelSU Root + PRoot + 官方 Linux ARM64 Codex；App UID 可作为
  非 Root 执行身份。Android/Bionic Codex CLI 和 Android ABI 工具包均已从产品运行链路移除；
  不提供 Bionic fallback。Android 宿主命令直接使用系统自带执行文件，git、Node、npm、npx、
  Python 等开发工具由 Debian guest 提供。历史会话数据保留，不因路线清理而主动删除。
- 每个 session 独立持有自己的 app-server、thread、turn、流式事件、草稿和历史；切换页面
  只改变可见性，不停止未被用户明确停止的 session。
- Codex CLI、rootfs、Node/git/npm/python 工具链通过独立版本目录和探测接口接入，允许后续
  更新 CLI 而不锁死 Flutter UI 或 session 协议。

## Root 使用原则

Root 是常态执行身份，普通文件读取和普通 Root 操作不逐条弹窗审批。权限控制采用应用层软路由：

- 普通字体、hosts、应用配置和工作区修改直接执行；
- boot 镜像、raw block、启动链配置、KernelSU 模块等高风险目标先验证目标、恢复路径和命令，
  再按具体操作取得授权；
- 这是行为规范和软路由，不是架构层面的全局写隔离；不得为了假设风险重新引入通用 broker、
  自定义 SELinux 域或把所有 Root 命令变成逐条审批。

## 开发与验证

中文路径下的 Gradle/Flutter 构建使用 ASCII junction：

```powershell
cd C:\codex_ascii_build\apps\codex
C:\toolchains\flutter-3.47.0\bin\flutter.bat test --no-pub
C:\toolchains\flutter-3.47.0\bin\flutter.bat analyze --no-pub
C:\toolchains\flutter-3.47.0\bin\flutter.bat build apk --release --no-pub
```

Release APK 构建后必须运行：

```powershell
pwsh -NoProfile -File C:\Users\Henry\Documents\个人项目\android_codex\tools\verify-android-apk.ps1 `
  -ApkPath C:\codex_ascii_build\apps\codex\build\app\outputs\flutter-apk\app-release.apk
```

真机覆盖安装前必须确认没有活跃 Root/PRoot/Codex worker；不能依赖 `adb install --dont-kill`
保证会话不被中断。设备断开时可用 `codex_api35` AVD 做布局和入口交互验收，但 AVD 结果不能
替代物理设备的真实 turn、Root 数据面和多 session 并行验证。

启动长期监听进程前遵循
`C:\Users\Henry\Desktop\重要信息文件夹\本地串口表.md` 的登记规则。所有过程状态、APK
哈希、验收截图和已知限制记录在 `docs/android-local-codex/`。

## 工作顺序

当前工程按以下顺序推进：

1. 先修复性能和 session 生命周期问题；
2. 再按 CC Pocket 交互逐项做 UI/交互验收；
3. 最后清理旧路线、无效入口和未使用组件，并更新文档。

功能可用性和快速完整实现优先。遇到问题先确认实际错误和边界，再在不破坏主链路的前提下
加入必要保护；不要因为泛化风险而取消功能。

## 主要文档

- [项目目标](docs/android-local-codex/PROJECT_GOAL.md)
- [当前方向](docs/android-local-codex/PROJECT_DIRECTION.md)
- [缺陷与验收进度](docs/android-local-codex/DEFECT_REMEDIATION_PROGRESS.md)
- [仓库清理记录](docs/android-local-codex/REPOSITORY_CLEANUP_2026-09-28.md)
