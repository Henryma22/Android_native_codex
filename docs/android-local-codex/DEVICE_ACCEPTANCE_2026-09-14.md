# Android 本地 Codex：实体设备验收记录（2026-09-14）

本记录覆盖独立应用 `io.henry.codex` 的 Android 本地 Host-first 路径，使用真实手机完成。
它不依赖远程 Bridge、WebSocket 或本地网络服务。

## 设备与包

- 设备：`24031PN0DC`，serial `6cb21282`，Android 16 / API 36，`arm64-v8a`，分辨率
  `1440x3200`，density `560`。
- 安装包：`io.henry.codex`，version `1.0.0` / versionCode `1`，主 ABI `arm64-v8a`。
- 当前 release APK：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，大小
  `24,060,669` bytes，SHA-256
  `a315c8828adff8c4a42adfcf2b0e8aa5977e46429a4a29582c2a3026b88f16cc`。
- 当前 APK 是在上一版真机后端验收包上的 UI-only rebuild：新增 CC Pocket 的无 Bridge
  状态线/状态指示器复用层；native runtime、Host 和 session 代码路径未改变。该包已安装并
  启动到真机 Home，组件本身另由 Flutter widget test 验证；设备当时被其他应用抢占前台，
  没有再注入手势重跑 Local Session。
- 应用实际 UID：`u0_a509` / `10509`。ADB 的 KernelSU shell 能取得 root，但应用进程本身仍
  保持 App UID；两者在本次验收中分别验证。

## 已通过的真机路径

### CC Pocket UI 与 Host workspace

- 启动后进入 CC Pocket 风格 Home/Workspaces 页面，命中 `CC Pocket`、`THIS DEVICE`、
  `Available`、`Recent Sessions`、`Grouped` 与本地 workspace 卡片；最终 APK 的 Home
  截图确认横向筛选条的选中态、图标与渐隐边缘正常。
- 当前双后端 Home contract 已通过实体设备 smoke：`verify-codex-vm-ui.ps1` 不再把
  `Linux Compatibility (PRoot)` 选择下本来就不显示的 Local Android 创建按钮当成必需项，
  同时验证 `CC Pocket`、`THIS DEVICE`、`Recent Sessions`、`Grouped`、`Local Codex`
  和 `All workspaces` 均存在。
- 从 UI 创建 Host workspace 后，目录会自动初始化 `README.md`，新目录可立即进入 Files；
  这是本次真机发现并修复的首开可用性问题。
- Files 页面由真实 App UID 读取设备文件，显示 `README.md` 为 `0 bytes`。

### Changes 数据闭环

在 `/storage/emulated/0/Codex/Workspaces/odexfix20260914/README.md` 上完成：

1. 读取当前快照；
2. 输入 proposed text 并预览 diff；
3. 经 UI approval 执行带 backup 的写入；
4. 设备侧确认文件内容已经写入；
5. 经 UI approval 执行 restore；
6. 设备侧确认文件恢复为 `0` 字节。

### Host command

- App UID 模式执行显式 argv `id`：返回
  `uid=10509(u0_a509) ... context=u:r:untrusted_app:s0`，exit `0`。
- Root helper 模式执行同一个 `id`：出现应用审批对话框；批准后返回
  `uid=0(root) ... context=u:r:ksu:s0`，exit `0`。
- 两种执行身份均保持所选 Host workspace 为 cwd；没有生成 shell 脚本。

### ARM64 Codex runtime

应用 Runtime 页面报告：

- `Codex runtime: Verified`；
- `codex-cli 0.154.0`；
- `Execution identity: root`；
- ABI `arm64-v8a`；
- companion bundle `verified (5)`；
- primary SHA-256 为
  `9b7c1c7abdc26fc3c4f47c77656a8e9121def5483dbae830ef1ee561758448a9`。

设备侧直接执行 `/data/local/tmp/io.henry.codex/codex-runtime/bin/codex --version` 返回
`codex-cli 0.154.0`。该旧 standalone 直执行路径曾报告 Codex helper alias 创建失败；当前
`apps/codex` 的 PRoot 启动路径已将 alias 临时目录按身份隔离，真机干净启动不再复现该警告。

### Linux Compatibility (PRoot) 真机路径

- 使用同一台 ARM64 手机安装完整 Debian Bookworm compatibility rootfs；安装归档
  SHA-256 为
  `ac03c6de959acfc1c72b4b6e4afd4abf010435e40c785dcbabf99c961977ac42`。
- 应用私有目录中的 `runtime.manifest.json` 报告 `state=verified`、
  `verificationMode=finalized-proot`、Node `24.19.0`、Codex
  `0.154.0-linux-arm64`；finalizer marker 也已在 rootfs 内确认。
- Runtime 页面选择 `Linux Compatibility (PRoot)` 后报告 `Verified`，并显示
  `PRoot guest worker executed /usr/bin/true from the finalized ARM64 compatibility rootfs.`。
- 在真实 Host workspace 上选择 App UID 运行兼容会话，显式 argv 仍为
  `codex app-server --listen stdio://`；两次启动均进入 `Status: ready` 并取得 thread
  id。运行时 `libcodex_proot.so` 与 guest `codex` 的 Android UID 都是 `10509`，只有
  worker guard 使用 root 做受控的监督/跟踪启动；这不是把 Codex worker 变成 root。
- 第二次会话执行强制停止/重新启动：停止后没有残留 PRoot、Codex 或
  `SessionForegroundService`；重新打开后 Home 恢复，workspace 仍在，显示
  `No active local session`；重新选择 PRoot 后 rootfs 再次报告 `Verified`。
- 初次 PRoot 会话曾出现 `libpcre2-8.so.0` 的 `Operation not permitted`；定位后确认
  原因是 Debian finalizer 在安装后替换/生成的共享库没有继承 app-private SELinux
  category label，而不是 Codex 或 git 的运行时权限。安装器现已在 finalizer 完成后对
  最终 `rootfs/home/proot-tmp` 重新执行受限 `app_data_file` relabel，并重新安装同一归档
  验证通过：`state=verified`、`verification=finalized-proot`、Node/Codex 版本匹配。
- relabel 修复后的最新 release APK + 最新安装 slot 已再次完成真机 Host command：
  `git --version` 输出 `git version 2.39.5`，exit `0`，没有 `libpcre2` 或 loader `EPERM`。
- 最新 APK 的 PRoot Local Session 已分别用 App UID 与 Root helper 启动并进入
  `Status: ready`，随后均可 Stop 回到 `Status: stopped / No active thread`；进程检查只剩
  正常 app 进程，`SessionForegroundService`、worker guard、PRoot 和 guest Codex 均已退出。
  Root helper 与 App UID 使用独立的 `arg0-app` / `arg0-root` bind 根；Root helper 之后再次
  启动 App UID，干净 transcript 中没有 PATH alias warning。
- 最新 APK 中已加入本地后端选择持久化：Runtime 页选择 PRoot 后强制结束并冷启动，重新进入
  Runtime 仍自动选中 `Linux Compatibility (PRoot)` 并显示 `Verified`；恢复前仍会重新探测，
  若 rootfs 失效则安全保持 `Local Android`。

### Local Session

- 使用显式 argv：`codex app-server --listen stdio://`。
- 使用 Root helper，并通过应用审批对话框批准启动。
- 真机 UI 进入 `Status: ready`，获得 thread id
  `01a09f20-4f58-7351-90d2-2d23c82bfd83`；这证明真实 ARM64 Codex app-server 已由应用启动并
  完成初始化握手。
- 运行时设备进程为 root `codex`，应用的 `SessionForegroundService` 存在并保持前台服务状态。
- 点击 Stop 后 UI 回到 `Status: stopped / No active thread`，Codex 进程和前台服务消失，
  crash buffer 没有 `io.henry.codex` 或 `codex` 崩溃记录。
- 本次只验证 app-server 初始化/停止，没有发送需要 provider、账号或模型回合的 prompt。

## 测试清理

本轮创建的 `codexdevicesmoke20260914` 和 `odexfix20260914` 两个测试目录已经按精确路径删除；
本轮 PRoot 测试创建的 `prootdevice20260914` 和 `prootrestart20260914` 也已按精确路径删除；
本轮最终 PRoot workspace `prootgit20260914`、`prootalias20260914` 和
`identityarg020260914` 也已按精确路径删除；刷新 Home 后不再出现这些 workspace，UI 显示
`No recent sessions / Create or import a local workspace to begin.`。
没有删除其他用户目录或文件。

## 当前限制

- Codex runtime 当前安装在 Root helper slot；Local Session 需要显式选择 Root helper 并批准
  root operation，普通 App UID 不应被误认为 root。后续可以继续优化默认选择和提示，但权限边界
  仍需保留。
- 本次没有登录 provider，也没有执行真实模型请求；因此网络、认证、模型回合、审批回合的实体
  设备行为仍未签署验收。
- PRoot 已完成实体设备安装、finalizer、guest probe、Host `git`、app-server ready/stop 和
  强制停止清理；强制停止后不会自动恢复原会话，需用户重新进入 workspace 并启动。后端选择
  已可跨冷启动保留，但跨重连的活动会话恢复策略仍待完善。app-server 会提示 PATH 中没有
  系统 `bubblewrap` 并回退到 bundled bubblewrap；provider 网络回合尚未在真机验收，当前
  环境对外连接可能返回 `Operation not permitted`。
- 当前 APK 使用 debug certificate，仅用于本地 QA；正式签名、更新密钥与发布包仍未完成。

## 可复核产物

- 实体设备 Home/Workspaces/Runtime/Host/Session UI 树和截图：
  `tmp/codex-real-device-ui/`
- 最新 APK 清理后的最终 Home UI 树：
  `tmp/codex-real-device-ui/codex-final-device-home.xml`，显示 `CC Pocket`、
  `Ready / No active local session`，且进程列表只剩正常 app 进程。
- 本轮最新 relabel 后的 Host/PRoot/Session/清理证据：
  `tmp/codex-host-git-result.xml`、`tmp/codex-runtime-proot-selected.xml`、
  `tmp/codex-session-starting.xml`、`tmp/codex-session-stopped-final.xml`、
  `tmp/codex-home-cleaned.xml`。
- 本轮 App UID / Root helper alias 隔离和连续启动证据：
  `tmp/codex-real-device-ui/codex-identity-session-app-ready.xml`、
  `tmp/codex-real-device-ui/codex-identity-session-root-ready.xml`、
  `tmp/codex-real-device-ui/codex-identity-session-app-after-root.xml`。
- 当前 CC Pocket session chrome 的 widget 回归：
  `apps/codex/test/ccpocket_session_chrome_test.dart`；实现为
  `apps/codex/lib/ccpocket_session_chrome.dart`。
- 当前 APK 真机 Home 截图与 UI 树：
  `tmp/codex-real-device-ui/codex-final-home-a315.png`、
  `tmp/codex-real-device-ui/codex-final-ui-a315.xml`。
- PRoot 停止态与强制停止重启后的 Runtime 证据：
  `tmp/codex-real-device-ui/proot-session-stopped.xml`、
  `tmp/codex-real-device-ui/runtime-proot-after-restart.xml`、
  `tmp/codex-real-device-ui/runtime-proot-preference-after-cold-start.xml`。
- 真机 smoke 脚本结果：`tmp/codex-real-device-script-smoke/result.json`。
- 当前 release APK 双后端 Home smoke 结果：
  `tmp/codex-real-device-final-smoke/result.json`。
- 最新 release APK：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`
- runtime manifest：`tools/android-local-runtime/manifests/codex-0.154.0-linux-arm64.manifest.json`
- 虚拟机基线记录：`docs/android-local-codex/VM_ACCEPTANCE_2026-09-14.md`
