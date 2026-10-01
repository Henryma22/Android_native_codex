# Android Codex

Android Codex 是独立的、本地优先的 Android Codex 应用。它复用 CC Pocket 的成熟 Flutter UI 组件与 session 交互，但产品身份、运行时、发布流程和仓库均独立于 CC Pocket；本项目不包含也不依赖 PC Bridge、远程机器或 Claude Code。

## 当前产品边界

- apps/codex：Android 应用、workspace/session、登录、设置和本地 app-server 客户端。
- packages/ccpocket_ui：作为本地 Flutter UI 组件库使用的 CC Pocket 前端代码；它不是本项目的 Git 远程或产品入口。
- tools/android-local-runtime：KernelSU/PRoot、官方 Linux ARM64 Codex 和 Android 宿主工具的构建与验证脚本。
- docs/android-local-codex：路线、Root 行为规范、验收证据和发布说明。

默认执行路径是 KernelSU Root + Linux ARM64 PRoot + 官方 Codex CLI/app-server；普通文件读写和常规 Root 操作不通过逐条 broker 审批。可能导致设备不可启动的目标使用应用层软路由、验证和明确授权保护，详见 docs/android-local-codex/PROJECT_DIRECTION.md 与 docs/android-local-codex/ROOT_ACCESS_POLICY.md。

## 构建与验证

中文路径下使用 ASCII staging 构建：

    pwsh -File tools/build-android.ps1 -Mode release
    pwsh -File tools/verify-android-apk.ps1 -ApkPath apps/codex/build/app/outputs/flutter-apk/app-release.apk -RequireCodexNativeAssets

测试：

    Set-Location apps/codex
    C:\toolchains\flutter-3.47.0\bin\flutter.bat test --no-pub

当前 1.0.0+1 Release 在未提供正式 keystore 时使用 Android debug certificate，仅用于本地 QA。公开分发前必须通过环境变量提供正式签名：CODEX_RELEASE_STORE_FILE、CODEX_RELEASE_STORE_PASSWORD、CODEX_RELEASE_KEY_ALIAS、CODEX_RELEASE_KEY_PASSWORD。密钥和 local.properties 永远不进入仓库。

## 发布状态

发布范围、已知限制、签名要求和可复现验证命令见 docs/release/RELEASE_1.0.md。项目当前不自动推送到任何远程仓库；新的 GitHub 仓库地址由维护者另行配置。

## 安全与贡献

提交前运行：

    pwsh -File tools/secret-scan.ps1

Root 行为和 boot 风险边界见 docs/android-local-codex/。请不要提交 API key、token、keystore、设备导出数据、APK、截图、tmp 或构建缓存。
