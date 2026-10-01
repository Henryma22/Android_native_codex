# Android Codex 真机验收记录：native toolchain 0.7.0

日期：2026-09-22  
设备：`6cb21282` / `24031PN0DC`  
系统：Android 16，API 36，`arm64-v8a`  
应用：`io.henry.codex`  
包：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`  
APK SHA-256：`bfc25cf59bb8f0e1f37e52158907ab37d7f4a21e9d22d12482be5f6989868995`
APK 大小：116,213,071 bytes

注意：此记录包含一次“先把 `native-toolchain-0.7.0-arm64-v8a` 手动导入到
root slot，再验证 App UID”的设备验收。该 215 MB 工具包没有打进 APK；仅重新安装
APK 不会自动重新生成 `/data/local/tmp/io.henry.codex/native-tools`。后续 probe 已
改为后台执行并把 Flutter 超时从 4 秒提高到 90 秒，避免完整校验期间把已安装工具链
误报为不可用。

2026-09-23 复验发现：本记录中旧的 App UID 命令 smoke 没有保留足以确认 Android
应用进程 SELinux 域的证据，不能作为真实 App 子进程执行验收。新版本通过 MainActivity
中的 App UID 探测器验证，具体结果见本文末尾“2026-09-23 真机复验”；原 smoke 输出保留为
历史记录，不再据此宣称 App UID 已可用。

## 验收结果

通过设置页的“快速导入 tar”选择器导入 0.7.0 bundle。小米文件选择器不会及时展示由 ADB 写入的 `.tar`，本次选择同内容的临时 `.zip` 别名；导入器不信任扩展名，仍按 tar 表、路径安全规则、manifest、SHA-256、版本和 root 原子切换流程验证。

Root slot manifest：

```text
/data/local/tmp/io.henry.codex/native-tools/native-toolchain.manifest.json
version = 0.7.0
```

App UID（当前安装包 UID 10509）执行结果：

```text
git --version   -> git version 2.55.0
node --version  -> v22.23.2
npm --version   -> 10.9.2
npx --version   -> 10.9.2
npm prefix      -> /
```

App UID 私有目录中的无网络 package smoke：

```text
npm init --yes             -> package.json created
npm pkg get name          -> "npm-smoke"
npm pack --dry-run --json -> npm-smoke@1.0.0, entryCount=5
node -e ...               -> android-codex-npm-smoke
`npm install --offline --ignore-scripts` -> succeeded; package-lock.json generated
```

Root 执行结果：

```text
npm --version   -> 10.9.2
npx --version   -> 10.9.2
npm prefix      -> /
```

同时确认：

- root slot 目录和 `bin/npm`、`bin/npx` 均为 root-owned；
- 0.7.0 导入失败时旧 0.6.0 未被覆盖；修复后才完成原子切换；
- App UID 与 root 共用同一份已校验工具链，不需要把 Windows/glibc 二进制放进 Android 包；
- 当前 release 已重新安装到 `6cb21282`，包含图片选择超限拒绝修复；
- 当前 release 已包含 Codex app-server 的 `{type: image, url: data:...}` 图片输入协议修复；
- 当前 release 已包含独立 `io.henry.codex` KernelSU typed broker、设置页导入/风险预览和显式安装通道；
- 本次验证没有写入 boot、raw block 或其他核心系统区域。

## 本次修复的导入问题

1. Android `sh` raw string 错误保留 `\$()`，造成第一轮 folder import 的 shell 语法/计数失败。
2. toybox `cp -a` 尝试保留 App UID 的 owner，触发 `chown ... Operation not permitted`；改为 `cp -R` 后显式归一化 owner/mode。
3. tar 内 manifest 被同时放在 `bundle` 和 staging 根目录，导致 payload 文件计数多 1；解包后从 `bundle` 剥离 manifest，保留 staging 副本供 root installer 使用。

## 尚未由本记录覆盖

- 带真实第三方依赖的网络/缓存 npm install（本次已覆盖无依赖离线安装路径）；
- 第三方 OpenAI-compatible provider 的真实服务端兼容性；
- 图片附件真机 turn；
- KernelSU broker 的真实设备 harmless plugin stage/apply、list/rollback 尚未在本次工具链验收中执行；高风险写入仍 fail-closed，不允许普通 Codex worker 直接写 boot/raw block，R3 设备凭据确认也尚未接入。

## 2026-09-23 真机复验：App UID 执行路径

设备：`24031PN0DC`，Android 16 / API 36，`arm64-v8a`。安装包 `io.henry.codex`
（versionName `1.0.0`，versionCode `1`）。

新发现的阻断原因不是 Unix mode：root slot 的工具原先是 `root:root`、0755，但其
SELinux 标签继承自 `/data/local/tmp`，为 `shell_data_file`。`io.henry.codex` 进程以
`u:r:untrusted_app` 运行；设备 audit log 对 `bash` 明确记录 `{ execute }` denied。

修复后，经过 manifest 和完整 SHA-256 验证的工具目录仍保持 root-owned、App UID 不可写，
并标记为 `u:object_r:system_file:s0`。App UID 探测现在使用与 Codex host 相同的 PATH，
按命令名执行 manifest 中全部 8 个工具：`bash`、`git`、`jq`、`node`、`npm`、`npx`、
`python`、`rg`。所有版本检查通过；设置页实际显示：

```text
已验证 · 0.7.0 · App UID 可用
```

本次 APK：

```text
SHA-256: a88d86d6cf925474dc386c28c0342142443e1ca88744fdc1236fa3fe5e8ba53d
Size:    116,215,199 bytes
Signing: Android debug certificate (local QA build)
```

APK verifier 确认 5 个 ARM64 Codex/PRoot native assets 均在包内，签名验证通过；release
APK 已安装到该设备。工具链 bundle 本身仍未打入 APK，卸载后重装或在新设备首次安装时，
仍需先从设置导入/部署 0.7.0 bundle；单独安装 APK 不会产生工具目录。
