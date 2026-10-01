# 独立 App 虚拟机验收（2026-09-19）

设备：`codex_api35`，API 35，x86_64，ADB serial `emulator-5554`。本记录只覆盖
`io.henry.codex` 的最终 APK UI，不包含 Bridge 或旧 CC Pocket 远程链路。

## 产物

- APK：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`
- 大小：`24,557,279` bytes
- SHA-256：`cf4c631a0df93744f659586952e4abb98eb0c487dce66f1931b05e90a87f26d2`
- 包名：`io.henry.codex`

## 已验证

- AVD 有界启动完成，`sys.boot_completed=1`、boot animation 已停止。
- 最终 APK 安装成功并可冷启动，Home 显示 `CC Pocket`、`Running`、`Recent Sessions`、
  `Workspaces` 和底部本地导航。
- Runtime 页可显示 `Local Android (host workspace)`、`Linux Compatibility (PRoot)`、
  Host capability 结果和 runtime/toolchain 状态。
- Workspaces 页可显示本地 workspace、`New folder`、`Import folder` 与 `Backup history`。
- 打开历史 `vm-demo` 后，session setup、`Resume recent session`、`Resume`、`Codex login`、
  `Start device login` 和 `Check login` 均出现在本地 UI hierarchy 中。

## 证据边界

- 该 AVD 为 x86_64，没有实体 ARM64 设备的 Codex rootfs/PRoot 安装，因此本次只声明 UI
  smoke，不声明真实 Codex runtime、provider turn 或 ARM64 compatibility worker 成功。
- 真正的 ARM64 PRoot session、登录状态检查和 provider-backed `REALTURNOK` 已在同一最终
  APK 的 Xiaomi Android 16 真机验收记录中完成。
- 验证结束后模拟器已通过 `adb emu kill` 关闭，5554/5555 已确认无监听。
