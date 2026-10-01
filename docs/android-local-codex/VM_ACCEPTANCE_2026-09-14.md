# Android 本地 Codex：虚拟机验收记录（2026-09-14）

本记录对应独立应用 `io.henry.codex`，只覆盖 Android 本地 Host-first 路径。验证设备为
`codex_api35`（Android 15 / API 35，x86_64，Pixel 6，`emulator-5554`），不代表真实手机、
ARM64 runtime 或 KernelSU 环境已经验收。

## 已完成

- 应用启动后保持在 `io.henry.codex/.MainActivity`，虚拟机 `sys.boot_completed=1`。
- `vm-demo` Host workspace 可列出 `/storage/emulated/0/Codex/Workspaces/vm-demo/README.md`。
- Host command 页面以显式 argv 启动 `id`，工作目录为选定 Host workspace；返回 App UID
  `u0_a209`，exit code 为 `0`。
- Changes 页面完成完整文件闭环：读取快照 → diff 预览 → 审批写入 → 创建 app-private
  backup → 版本校验恢复；`README.md` 最终恢复为 `0` 字节。
- 在同一个 Android 文件树授权下，以 SAF workspace 重复完成读取 → diff → 审批写入 →
  backup → 版本校验恢复；ADB 最终确认 `README.md` 同样恢复为 `0` 字节。SAF 仍只提供
  文件数据面，Host command 和 Local Session 需要直接 Host workspace。
- Local session 页面使用仓库内确定性 JSON-RPC fixture（不连接模型、不登录、不访问网络）
  启动 `/system/bin/sh` app-server：
  - 建立 thread `fixture-thread`；
  - 发送 prompt 后显示 `item/fileChange/requestApproval` 和 README diff；
  - 审批 root 操作后创建 1 个 pre-change backup；
  - fixture 写入 README，应用报告 `1 file(s) match the approved content.`；
  - 停止 session 后仍可在 Backup history 恢复，文件回到 `0` 字节。
- 另用 user-input fixture 验证了 `item/tool/requestUserInput`：页面显示问题和 Dart/Kotlin
  选项，选择 Dart 后提交，fixture 返回完成消息；随后 session 正常停止。
- UI 已在 API 35 模拟器完成 CC Pocket 视觉回归：Home 显示 `CC Pocket` 标题、`THIS DEVICE`、
  `Running`、`Recent Sessions`、`Grouped` 筛选芯片和本地工作区卡；Local Session 显示
  Graphite/Ember 会话头、状态线、状态胶囊、圆角 setup 面板、对话气泡、橙色用户消息和
  composer。
- 使用 `/system/bin/sh` 加固定 user-input fixture 从新会话页启动本地 app-server，页面进入
  `ready`，对话树从 13 增加到 14 个事件；输入 `hello` 后出现橙色用户气泡，随后通过页面
  Stop 停止。运行期间 `SessionForegroundService` 的通知包含 `Stop` action，
  `dumpsys notification` 显示 `numBlocked=0`。
- 额外验证了 Android 前台服务生命周期：session ready 时
  `io.henry.codex/.SessionForegroundService` 出现且 `isForeground=true`；点击 Stop 后服务
  消失，UI 回到 `Status: stopped / No active thread`。
- 临时撤销模拟器的 `MANAGE_EXTERNAL_STORAGE` app-op 后，Runtime 页正确显示
  `Host files / Denied` 和 `Open settings`；点击后进入 `com.android.settings` 的本 App
  all-files access 页面。随后恢复 app-op，避免改变后续 VM 回归基线。
- 同一拒绝态下，Home 页顶部状态改为 `Needs access`，显示 Host access 提示卡，禁用
  `New workspace` 并保留 `Import folder`；首页 `Open settings` 可直达相同系统设置页。
- 测试完成后已删除虚拟机工作区中的临时 `codex-fixture.sh`；没有删除工作区目录或用户文件。
- API 35 虚拟机已完成 release UI smoke 并重启；UI smoke 确认最新 SAF 文案已加载，且
  `apps/codex` 的 Dart/Kotlin 源码扫描不含 `bridge`、`remote` 或 `websocket` 传输依赖；
  CC Pocket 字样只用于已迁入的 UI 适配层。
- 独立 App Manifest 不声明网络权限，也不再开启 cleartext traffic；本地 session 通过
  Android 进程的 stdio 通道工作。
- 独立 Codex runtime 离线回归通过：manifest schema、归档安全、ARM64 Codex 包识别、
  PRoot shell 语法和 Bridge/MCP 排除检查均通过；兼容 rootfs finalizer 只校验 Node、
  Codex、PRoot 所需输入。
- 已从官方 Node 24.19.0 ARM64 tarball 和 `@openai/codex@0.154.0-linux-arm64`
  生成独立 rootfs，并完成 device staging：归档 SHA-256 为
  `ac03c6de959acfc1c72b4b6e4afd4abf010435e40c785dcbabf99c961977ac42`，runtime digest
  为 `d448e7578950c7961fa1cb39dcf5a67b4fee9b042048162af4751583b9ab00a0`；该步骤只证明
  构建、哈希、归档安全和 staging 合同，不证明 x86_64 主机或模拟器执行 ARM64 代码。
- 已用 Android NDK `29.0.13846066` 交叉构建并通过 ELF64/AArch64 检查的 PRoot、loader、
  host trampoline、worker guard 和 root-read broker；五个 native asset 已进入最新 release
  APK 的 `lib/arm64-v8a/`。源码产物 SHA-256 分别为：
  `libcodex_proot.so`=`bebce684f993a7c8ae9bdf24c8fea4309f35fdedca9f546359dc8a53de05d977`、
  `libcodex_proot_loader.so`=`d62b5d3f67fa45b3b5075b03c448888a20a48e99240d501c5723bb937abf5a83`、
  `libcodex_host_trampoline.so`=`17fb03672f15940f3d0367c0b5186f5e33f23ff1a1be5a19be3e20cc74d64a8e`、
  `libcodex_worker_guard.so`=`a461158d0c7d7961473f454c832186f3144b179a73e9f3849e07dd5d80aa68e1`、
  `libcodex_root_read_broker.so`=`4da71d4f6878acabf6562db3f354530d736a1d1da650d6761d828d3087e20658`。
  这证明 APK packaging 完整，不证明实体 ARM64 设备执行成功。
- 使用仓库脚本完成 release APK 构建；在当前 Flutter Windows 工具链对中文 checkout
  路径的 AOT 编译限制下，脚本通过临时 ASCII `SUBST` 映射构建，不复制源码。APK verifier
  已确认包名为 `io.henry.codex`、签名结构有效，并用 `-RequireCodexNativeAssets`
  确认五个 ARM64 native asset 全部进入 APK；当前未配置正式证书，因此签名类型为
  Android debug certificate，仅用于本地 QA。当前包大小为 `24,038,945` bytes，SHA-256
  为 `556fa8a4972fc1191a880f4134f79637b1647a7e1dd44ed059b980d81b0ab1a4`。
- 本次最新 release APK 已安装到 `codex_api35`（x86_64）并成功启动
  `io.henry.codex/.MainActivity`；UI tree 命中 `CC Pocket`、`THIS DEVICE`、`Recent Sessions`、
  `Grouped` 和 `Local workspace`，点击 workspace 卡片后进入 workspace 页面。该结果证明当前
  APK 的 UI/Activity 可启动，不证明 ARM64 native runtime、rootfs 或 KernelSU 在 x86_64 VM 上可执行。
- 本次当前 APK 复测（16:12:18–16:13:31 +08:00）另命中 `Back`、`Changes`、`README.md`、
  `Load`、`Preview diff` 和 `Create backup only`；结果为 `workspaceOpened=true`，APK SHA-256
  与 verifier 一致。模拟器端口 5554/5555 已在结束后确认无监听并释放。
- `flutter test --no-pub` 通过 `74` 项；Android `:app:testDebugUnitTest` 通过（在中文
  checkout 中跳过 Flutter asset 编译，避免 Gradle 对中文路径的工具链限制）；
  `dart analyze` 无 warning/error，剩余 19 项为 info 级 lint 建议。
- 本次本地 Session 回归新增覆盖：旧 app-server 退出后延迟事件不会污染重启后的新 Session。

## 尚未覆盖

- 虚拟机是 x86_64，不能运行当前只接受 `arm64-v8a` 的正式 Codex/PRoot 包；因此 runtime
  页面显示 Missing 是预期状态。
- 尚未在实体手机上验证 Android 版本差异、真实存储授权、KernelSU root broker、ARM64
  rootfs finalize/install、正式 Codex `app-server` 和真实 provider/model 回合。
- Provider 登录、真实模型请求、正式签名和商店发布均未执行。

## 可复核产物

- APK（release，本地 QA 签名）：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`
- APK（debug）：`apps/codex/build/app/outputs/flutter-apk/app-debug.apk`
- 用户输入完成态截图：`tmp/codex-vm-user-input-card.png`
- 用户输入完成态 UI 树：`tmp/codex-vm-user-input-completed.xml`
- 前台服务运行态 UI 树：`tmp/codex-vm-session-lifecycle-running.xml`
- 前台服务停止态 UI 树：`tmp/codex-vm-session-lifecycle-stopped.xml`
- Host 权限拒绝态 UI 树：`tmp/codex-vm-host-settings-denied.xml`
- Home Host 权限拒绝态截图/UI 树：`tmp/codex-vm-home-host-denied.png`、
  `tmp/codex-vm-home-host-denied.xml`
- Android 存储权限设置页 UI 树：`tmp/codex-vm-storage-settings.xml`
- SAF 恢复完成态截图：`tmp/codex-vm-saf-restored.png`
- SAF 恢复完成态 UI 树：`tmp/codex-vm-saf-restored.xml`
- 最新 release UI smoke 截图：`tmp/codex-release-final.png`
- 最新 release UI smoke 树：`tmp/codex-release-final.xml`
- 本次 Codex runtime 解耦后的 release UI smoke 截图/UI 树：
  `tmp/codex-release-independent-final.png`、`tmp/codex-release-independent-final.xml`
- 当前带 ARM64 native asset 的 release APK UI smoke 截图/UI 树：
  `tmp/codex-current-release-home.png`、`tmp/codex-current-release-home.xml`、
  `tmp/codex-current-release-workspace.png`、`tmp/codex-current-release-workspace.xml`
- 可重复的 API35 Home smoke 脚本：`tools/verify-codex-vm-ui.ps1`；它不启动 AVD、Bridge
  或业务服务，只验证已启动的 `emulator-5554` 并把结果写入 `tmp/codex-vm-smoke/`；
  本次脚本实跑 `activityResumed=true`、`missingLabels=[]`，APK SHA-256 与 release verifier
  一致。
- 可重复脚本本次输出：`tmp/codex-vm-smoke/result.json`、`tmp/codex-vm-smoke/home.png`、
  `tmp/codex-vm-smoke/home.xml`
- 有界等待复测输出：`tmp/codex-vm-smoke-bounded/result.json`、
  `tmp/codex-vm-smoke-bounded/home.png`、`tmp/codex-vm-smoke-bounded/home.xml`；
  设备就绪和 Android boot 均在脚本超时范围内完成，`activityResumed=true`、
  `missingLabels=[]`，且 5554/5555 已在复测结束后释放。
- Home→workspace smoke 输出：`tmp/codex-vm-home-workspace-smoke-2/result.json`、
  `home.png`、`home.xml`、`workspace.png`、`workspace.xml`；在 `vm-demo` fixture
  已存在时，脚本自动点击 workspace 卡片并命中 `Back`、`Changes`、`README.md`、
  `Load`、`Preview diff`、`Create backup only`，结果为 `workspaceOpened=true`。
- 当前 APK Home→workspace smoke 输出：`tmp/codex-vm-current-ui/result.json`、
  `home.png`、`home.xml`、`workspace.png`、`workspace.xml`。
- CC Pocket Home 截图：`tmp/codex-ccpocket-home-debug.png`
- release APK CC Pocket Home 截图：`tmp/codex-release-ccpocket-final.png`
- CC Pocket Local Session 截图：`tmp/codex-ccpocket-session-debug.png`、
  `tmp/codex-ccpocket-session-running.png`、`tmp/codex-ccpocket-session-conversation.png`、
  `tmp/codex-ccpocket-session-composer.png`
- 应用入口：`apps/codex/lib/main.dart`
- CC Pocket 主题迁移：`apps/codex/lib/ccpocket_app_theme.dart`
- 本地后端：`apps/codex/lib/backends/local/`
- 本地 session 客户端：`apps/codex/lib/core/application/codex_session_client.dart`
- 离线 fixture：`tools/android-local-runtime/fixtures/codex-approval-app-server.sh`
