# 独立 Android Codex 路线图

> 2026-09-28：本路线图保留历史实施证据；当前路线以
> [PROJECT_DIRECTION.md](PROJECT_DIRECTION.md) 为准。产品主链固定为 KernelSU Root + PRoot
> + 官方 Linux ARM64 Codex。Android/Bionic Codex 的独立构建、导入、更新和恢复入口已退休；
> Android ABI 开发工具包也已退休：Debian guest 提供 git/node/npm/npx/python，Android
> 系统命令由宿主 OS 自带工具执行。下方 native-first/PRoot fallback 描述不得视为当前要求。

本文件是 `android_codex` 当前独立 App 的工作边界。产品是本地 Host-first Android
Codex：workspace、Host 执行、文件变更审批、备份恢复和 Local Codex session 都在
Android 本机完成。

## 归属边界

- 当前产品：`apps/codex`，包名 `io.henry.codex`。
- 当前产品的 runtime 构建链：`tools/android-local-runtime` 中的 Node/Codex 独立链路、
  PRoot 以及 Root worker 相关输入；不引入旧的 fixed-scope root-read broker。
- 明确不属于当前产品：`packages/bridge`、`apps/mobile`、旧 CC Pocket 远程控制面以及
  8766 端口上的旧服务。独立 App 不导入、不启动、不依赖这些内容。

## 历史 Phase 2：Android-native-first runtime（不再作为当前主路线）

目标是让 Android/Bionic 原生执行成为默认可用路径；Codex CLI/app-server 与其
session 协议保持可替换，只有明确缺少的 Linux ABI/工具能力才透明回退到 PRoot。
UI/session contract 已冻结，本阶段不得重做前端或改变“每个 session 独立拥有自己的
thread、进程和历史”的语义。

先完成一条可实测的 vertical slice：

- 从 App UID 实际启动并验证 Bionic 版 `git`、`node`、`npm`、`npx`、`python`；
- capability 状态必须区分 Supported、Installed/Available 与设备实测 Verified；
- app-server 启动与任意 Host command 的执行身份分开报告，不能拿 Root shell 或
  PRoot 的成功冒充 App UID native 成功；
- 若某个能力在当前 ROM/SELinux 下不可用，按能力路由到兼容层并展示明确原因，不能
  把整个 Codex session 悄悄切到另一个 runtime；
- 保留 PRoot 已验证路径，直到 Native 路径在真实设备通过同等 session/command 验收。

当前已知边界：官方 glibc ARM64 Codex 可在受控 Root/PRoot 环境运行，但此前在真实
`u:r:untrusted_app:s0` 下从临时区和 APK data 区直接 `execve` 遇到 SELinux
`entrypoint` 拒绝。下一步先复核 Android-compatible ABI 工具链、实际 resolver 和
命令分派，不把一次 shell 可执行误判成 native 支持；也不为绕过系统策略授予任意 Root。

## 当前完成

- 本地 Android Host workspace（直接路径和 SAF 路径）及文件浏览；
- 文本快照、diff 预览、审批写入、版本冲突检查、app-private backup 和恢复；
- 显式 argv Host command，并区分 App UID 与 Root helper；
- Local app-server stdio JSON-RPC：thread、prompt、审批、用户输入、停止和历史；
- Local Session 前台服务启动/停止生命周期已在 API 35 Emulator 和实体设备验证；
- 2026-09-14 已在实体 Xiaomi `24031PN0DC`（Android 16 / API 36 / ARM64）验证真实
  ARM64 Codex app-server：Root helper 审批后进入 `ready` 并获得 thread id，Stop 后
  Codex 进程与前台服务均退出；
- 同一实体设备已验证完整 Debian ARM64 compatibility rootfs 的安装、PRoot finalizer、
  `/usr/bin/true` guest probe，以及两次 `Linux Compatibility (PRoot)` app-server
  ready/stop；PRoot guest `codex` 保持 App UID `10509`，root 只负责受控 worker
  supervision；一次强制停止/重启后无残留 worker/service，rootfs 仍可重新验证；
- 同一实体设备已验证 App UID / Root helper 双身份 Host command、真实 Changes 写入/备份/
  恢复闭环、应用重启后的 runtime 持久性，以及测试目录清理；
- 复用 CC Pocket 的 Graphite/Ember `AppTheme`、`AppColors` 和 Home 信息层级；
- 复用 CC Pocket 的会话状态线、状态胶囊、圆角设置面板、消息气泡、审批卡、输入栏、
  Recent Sessions 筛选芯片和工作区卡片视觉组件，落地到独立本地数据模型；其中无 Bridge
  依赖的状态线/状态指示器已直接抽离到 `apps/codex/lib/ccpocket_session_chrome.dart`，
  横向筛选条已抽离到 `apps/codex/lib/ccpocket_horizontal_chip_bar.dart`，并由
  `ccpocket_session_chrome_test.dart` 回归；旧远程适配器不进入当前 App；
- Home/Runtime 会显示真实 Host 存储授权状态；拒绝时提供系统设置入口并阻止直接创建；
- 独立 Node/Codex runtime 构建器、manifest 校验、离线检查和中文路径 release 构建脚本；
- 独立 runtime finalizer、PRoot asset、marker 和 manifest 已切换到 Codex 命名，
  不再要求旧 Bridge/MCP 输入；旧 device control scripts 已明确标为历史排除项；
- 已使用校验通过的官方 `@openai/codex@0.154.0-linux-arm64` 和 Node 24.19.0
  生成独立 ARM64 rootfs：归档 SHA-256 为
  `ac03c6de959acfc1c72b4b6e4afd4abf010435e40c785dcbabf99c961977ac42`，device
  staging digest 为 `d448e7578950c7961fa1cb39dcf5a67b4fee9b042048162af4751583b9ab00a0`；
  staging 不含旧远程运行时路径。实体设备已安装并验证该完整 rootfs，同时也验证了
  官方 ARM64 standalone bundle；两条本地 app-server 启动路径均不依赖 Bridge；
- PRoot 安装器已在 Debian finalizer 完成后重新对最终 `rootfs/home/proot-tmp` 执行
  app-private SELinux category relabel；同一实体设备重新安装归档后再次通过
  `state=verified`、`verification=finalized-proot`、Node/Codex guest probe，解决了
  `libpcre2-8.so.0` 的动态加载 `Operation not permitted` 根因；
- 最新 release APK 已在同一设备上复测 PRoot Local Session：App UID 与 Root helper 两种
  身份均进入 `ready` 并可 Stop；Codex 的 PATH alias 临时目录已按身份分成两个 app-private
  bind 根，Root helper 产生的 root-owned 临时文件不会再被 App UID 清理路径读取；干净启动
  不再出现 PATH alias warning。设备若尝试真实 provider 网络回合，仍可能受当前离线/权限环境
  限制，但这不影响本地 app-server 初始化；
- Home 已改为保活一个本地 Local Session：从 Home、Workspaces 或 Recent Sessions 进入后，
  返回 Home 不会销毁 app-server；Running 卡片会同步 workspace、状态、队列数量和 Stop，
  点击可回到原会话。Grouped 会按 workspace 展开本地历史，结构化 agent message 预览会提取
  可读文本，不再把原始 JSON 直接显示给用户；这些交互沿用 CC Pocket 的 session-list 逻辑。
- 2026-09-18 release APK 已在实体 `24031PN0DC` 上完成真实 session 回归：历史 thread
  恢复后发送 `pwd` 与 `ls -la` 均在 `/workspace` 正常返回；返回 Home 后 Running 卡片仍显示
  `realturn`，再次打开可回到原会话，Home Stop 后恢复为 Ready。当前 UI hierarchy 仍为
  CC Pocket 风格的 Home、Running、Recent Sessions、Grouped、Runtime 和 session composer。
- 2026-09-19 最新 release APK 在同一实体设备上再次恢复该 thread，确认 session 页面保留
  `gpt-5.6-luna · low`、PRoot fallback 状态和 Resume/Stop 交互；`pwd` 返回 `/workspace`，
  `ls -la` 返回 guest workspace 内容，Stop 后无 Codex/PRoot 残留进程。Runtime 页面同时
  明确显示 App UID direct runtime 未安装/不可用，避免将 root fallback 误报为 Android-native。
- 同一 APK 在该 thread 中完成 provider-backed real turn：发送
  `Reply exactly REALTURNOK and nothing else.` 后准确收到 `REALTURNOK`；模型/推理档位仍为
  `gpt-5.6-luna / low`，随后 Stop 清理了 Codex/PRoot worker。
- 同一 session 页面通过 `Check login` 返回 `Status: Logged in`，确认登录状态检查与
  device-login 入口仍属于本地 CC Pocket 风格 session setup，而非外部 Bridge 控制面。
- 2026-09-19 已补齐 CC Pocket 风格 session 状态持久化：transcript、draft、queued prompts、
  prompt history、sandbox/approval/plan 设置和固定的 `gpt-5.6-luna · low` 会随本地历史记录
  恢复；活动 session 返回 Home 时只保留在 Running，避免与 Recent Sessions 重复。
- 当 App UID direct runtime 不可用而 Linux Compatibility/PRoot 已 Verified 时，session setup
  的 `Start device login` 与 `Check login` 仍可用并走本地 fallback，避免把 direct probe 限制
  错误地变成登录功能限制；真机随后完成了 provider-backed `REALTURNOK` 回合。
- 2026-09-19 已将 Android 当前活动网络的显式 HTTP 代理以本地环境变量传入 PRoot guest，
  同时覆盖 `HTTP(S)_PROXY`、`ALL_PROXY` 及大小写变体；DNS 仍优先取活动网络。代理变量已在
  真机 `codex app-server` 进程内确认存在，不包含任何 Bridge/远程服务配置。
- 2026-09-19 又将同一份受限代理环境注入 Local Android 的 App UID/Root helper Host
  process；调用方显式环境仍可覆盖，网络配置不可用时不会阻断本地进程启动。这样 direct、
  root 和 PRoot 三条本地执行路径不再因 Android `LinkProperties.httpProxy` 传递不同而分叉。
- 2026-09-19 已在真机精确终止当前 App 自己的 `codex app-server` 进程，确认活动页保留
  transcript、thread id 和 composer，并显示 `Local session disconnected`、`Reconnect`、
  `New session`；点击 `Reconnect` 后可重新回到活动 session 壳。历史记录中的 ANSI/MCP
  诊断也会被清洗为可读的可选 worker 降级提示；provider TLS/WebSocket 断链会显示可重试的
  网络提示，不再把原始握手错误当作普通对话消息。
- 2026-09-19 已将断线恢复卡抽取为独立的 `CcpocketSessionRecoveryBanner` session chrome，
  并用 widget test 覆盖 `Reconnect` 与 `New session` 两条回调路径；这部分不引入 Bridge，
  只由本地 session owner 提供回调。
- 2026-09-19 已补齐 CC Pocket 风格的断线输入队列：断线且 thread 仍可恢复时 composer 保持
  可输入，prompt 进入本地队列并持久化，`Reconnect` 成功后按原顺序自动投递；队列 strip 会
  明确显示 `Queued until local reconnect`。该路径已在 Xiaomi Android 16 真机通过真实
  app-server 进程终止、输入、Reconnect、assistant 回复和 Stop 清理闭环验证。
- 2026-09-19 已将本地 session 历史从 workspace 单键改为 workspace + sessionId 索引，保留
  旧单记录格式的读取兼容；同一工作区可以保留多个独立 session，点击不同 Recent Session
  会恢复对应的 transcript/thread，`New session` 不再覆盖原历史。该行为已在真机 Home
  的 Recent Sessions 中形成多条独立记录并验证。
- 2026-09-19 又修复了同一 workspace 内打开旧格式历史记录时的页面复用边界：session
  页面现在比较完整的历史身份（workspace、sessionId、threadId、更新时间），因此缺少
  `sessionId` 的 legacy row 也会切换到正确 transcript；没有可恢复 thread 的旧记录在 Home
  显示 `Open`，不会伪装成可 Resume。PRoot fallback 同样保留用户点开的准确历史 row。
- 2026-09-19 最新修复 APK 已在真机完成一次新的 provider-backed real turn：发送 `FINALMULTI`
  后准确收到 `What would you like me to do with “FINALMULTI”?`，页面固定显示
  `gpt-5.6-luna · low`，Stop 后无 Codex/PRoot/worker guard 残留。
- 2026-09-19 已补齐 Recent Sessions 的 CC Pocket 风格长按操作和本地状态：底部操作面板
  支持 Resume/Open、Pin/Unpin、Archive/Restore；置顶状态按 sessionId 持久化并置前，归档
  session 默认隐藏且可通过 `Archived` 筛选器恢复。该链路已在 Xiaomi Android 16 真机验证，
  并在测试结束后恢复原有历史状态。
- 2026-09-19 又补齐 provider turn 失败后的 CC Pocket 风格恢复交互：失败 prompt 保留在
  当前 session，显示 `Retry turn`，本地 app-server 仍存活时可重新发送同一 prompt；它与
  app-server 断线时的 `Reconnect`/本地队列恢复路径分开，避免误把两类失败混为一谈。
- 2026-09-19 又补齐本地 session rename：Home 长按菜单和 session 页面菜单均可修改标题，
  标题按 sessionId 写入 Android 私有历史索引，清空后恢复工作区默认名称；真机已完成写入、
  显示、清空和冷启动恢复验证。
- 2026-09-19 又将活动 Running 卡的 Pin/Unpin 接入相同的 sessionId 历史状态；真机验证
  Running 卡切换、状态恢复和 Stop 后的 Codex/PRoot/worker 清理。
- 2026-09-19 又补齐 Recent Session 的滑动 Archive/Restore 手势，Grouped 与普通列表共用
  同一条本地归档回调；真机已验证滑动隐藏、Archived 找回、Restore 和冷启动恢复。
- Runtime 页的本地后端选择已通过 Android 私有偏好持久化；PRoot 冷启动恢复前会重新探测
  rootfs，探测失败时安全回退到 Local Android，不会把失效运行时带入执行路径；
- 已用 NDK `29.0.13846066` 构建并打入 release APK 的四个 ARM64 native asset：PRoot、
  loader、host trampoline 和 worker guard；旧的 fixed-scope root-read broker 已从独立
  App packaging contract 移除，APK packaging 已验证，并已在实体 ARM64 设备随当前
  release APK 完成加载与 UI 验收；
- 当前 release APK（`io.henry.codex`）大小为 `24,557,279` bytes，SHA-256 为
  `cf4c631a0df93744f659586952e4abb98eb0c487dce66f1931b05e90a87f26d2`；同时保留 API 35
  x86_64 `codex_api35` 的 UI/fixture 回归，不以模拟器替代 ARM64 真机证据；
- `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 已将四个 ARM64 native asset
  纳入可重复的 APK packaging contract 检查，当前 release 的 missing 列表为空；
- 独立 runtime 的三个 ADB 安装器均使用可配置的有界设备就绪等待，离线 suite 会阻止
  无界 `adb wait-for-device` 回归；
- rootfs builder 默认 Codex 版本已与当前已验证 manifest 对齐为 `0.154.0-linux-arm64`，
  npm integrity 也固定到官方包摘要；
- API 35 x86_64 Emulator 上的文件、Host、变更、备份恢复和两个 session fixture 验收。
- 2026-09-19 最终 release APK 已在 `codex_api35` API 35 x86_64 AVD 上完成有界启动、安装、
  冷启动 Home、Runtime、Workspaces、历史 session setup/Resume/login UI smoke；模拟器仅作为
  UI 证据，未冒充 ARM64 PRoot runtime。
- `CodexSessionClient` 已加入进程代际隔离：旧 app-server 退出后的延迟 stdout/exit 事件不会
  影响重启后的新 session；历史、队列、草稿、Home 保活、断线恢复和 ANSI 历史清洗回归后，
  完整 Flutter 测试为 89 项，`flutter analyze` 无 error，仅有既有 lint/info 建议；
  `thread/start`/`thread/resume` 现在显式带 `skipGitRepoCheck=true`，允许 Android 本地
  workspace 不必预先初始化 Git；本次 release APK 已重新安装到实体设备，
  Home/Running/Recent Sessions/Grouped hierarchy 仍正常可见。
- Android `CompatibilityNetworkConfigurationTest` 已覆盖 IPv4、IPv6、非法端点和大小写
  代理变量；当前 `testDebugUnitTest` 共 12/12 通过，确保 Android `LinkProperties` 代理被
  转换为不含凭据的本地执行环境后，仍由 direct/root/PRoot 共用同一规则。

## 尚未完成或尚未验证

- 直接 Android App UID Codex runtime 尚未具备可验证的 `libcodex.so`。2026-09-19 的边界探测
  证明：同一官方 `codex-cli 0.154.0` 二进制可在 KernelSU shell 中以 UID `10509` 完成
  `initialize`/`thread/start`，但切换到真实 App 的 `u:r:untrusted_app:s0` 后，从
  `/data/local/tmp` 和 `apk_data_file` 直接 `execve` 均收到 SELinux `entrypoint` 拒绝；
  因此该 shell 结果不能冒充 App UID 原生执行能力，也不再复制一个实际不可执行的直跑
  bundle。当前 APK 仍先探测真正可执行的 App runtime，能力不足时回退到已验证的
  Linux Compatibility/PRoot；在当前设备上 PRoot 是可靠主路径。
- PRoot 的认证、thread resume、`pwd`、`ls -la`、`/workspace` 和一次
  `REALTURNOK` provider-backed real turn 已验证。设备此前的 Clash/VPN 链路曾让 provider
  WebSocket 与 HTTPS fallback 报告 `tls handshake eof`，因此跨网络/OEM 的长回合稳定性仍需
  复测；这属于设备网络链路风险，不是 Bridge 缺失。可选 MCP worker 已隔离并降级为可读
  提示，活动 session 断线/重连 UI 已完成真机验证。
- API 35 x86_64 模拟器已完成 UI 验收，但没有当前设备的 rootfs/PRoot runtime 安装，因此不能
  用模拟器替代 ARM64 真机的真实 Codex runtime 证据。
- 正式签名、更新密钥、发布包和商店验收；当前 APK 仍为本地 QA debug certificate；
- 不同 OEM、被撤销存储授权和跨 Android 用户的设备回归。

## 当前路线下的下一步

先以 `PROJECT_DIRECTION.md` 的顺序完成 Root/PRoot 官方 CLI/app-server、工具链、真实
session 和宿主文件/命令衔接的可用闭环；再补齐 CC Pocket UI 暴露能力、第三方 provider、
动态模型/permission profile、独立更新和 KernelSU 模块软路由。native ABI 能力只按实际
设备证据逐项接入，不允许因为 native 探测失败而阻断 Root/PRoot 主路径。保持独立 App，
不引入 Bridge；每个完成的局部检查点都继续推进总体 Goal。
