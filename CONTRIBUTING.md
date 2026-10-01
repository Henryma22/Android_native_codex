# Android Codex 开发

先阅读 [当前路线](docs/android-local-codex/PROJECT_DIRECTION.md) 和
[工程说明](CLAUDE.md)。本仓库维护手机本地 Android Codex，主链路为
KernelSU Root → PRoot → 官方 Linux ARM64 Codex。

源码入口是 `apps/codex`，CC Pocket 展示组件位于 `packages/ccpocket_ui`。
开发工具由 Debian guest 提供；不恢复远程 Bridge、Claude Code、Bionic Codex
或商店热更新路线。

按改动运行相关 Flutter 测试；修改 Android 实现时补做 Kotlin 编译或相关测试。
构建和 APK 验证命令见 [README](README.md)。保留既有工作区、会话数据和无关改动。
