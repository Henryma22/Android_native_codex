# Android Codex 缺陷补足进度

更新时间：2026-10-01  
工作区：`feat/android-local-codex`  
范围：独立 Android Codex 本地应用；不把 Bridge 重新引入本项目。

## 2026-10-01 会话诊断与批量文件工具中文投影

- 修复会话内用户输入提交、MCP 请求结果、文件变更验证/备份/预览、断线恢复和会话清理等
  直接写入英文的问题。历史 transcript 仍保存原始英文；当前 locale 只改变展示投影，避免影响
  session 恢复、协议匹配和诊断搜索。
- 批量文本替换页现在也会在中文界面翻译扫描深度、文件数量、文件大小、符号链接和批量写入
  失败提示；英文界面和动态路径/错误内容保持原样。
- 全套定向 Flutter 回归（updater、Linux/PRoot、session client、CC Pocket UI、导航、会话恢复、
  批量文件页）为 `131/131` 通过；Dart analyzer 退出码为 `0`。
- 最终重新生成并校验 Release QA APK：`31,486,363` bytes，SHA-256
  `7CFAD8475F935286212D675A0D11496EB53B6C7A840422A79A0C453CA835F72C`；包
  `io.henry.codex` / `1.0.0`，四个 ARM64 Codex/PRoot/worker-guard asset 全部存在，退役
  Bionic/Bridge asset 全部缺失。仍为本机 debug certificate，未覆盖安装以保护真机 Root worker。

## 2026-10-01 登录状态中文展示补足

- 修复本地登录卡片直接显示底层英文事件的问题：浏览器 OAuth、设备码、API key 的完成、
  失败、停止、挑战校验和 app-server 退出状态现在在中文界面统一翻译；动态退出码仍保留。
- 登录挑战码的 `Code:` 标签改为随 locale 展示，分叉会话的自动标题也改为中文 `分叉自 ...`，
  不改变底层登录事件或 thread/history 协议。
- 本轮全套定向回归为 `129/129` 通过，Dart analyzer 退出码为 `0`；重新生成的 Release QA
  APK 为 `31,478,319` bytes，SHA-256
  `19BCDC812D6B5CE61194B3145E988CFE14AE37C15DA4A9E0D031A41F6A86EE78`，native asset
  verifier 通过。该包仍为本机 debug certificate，且未覆盖安装；真机 Root worker 保持运行。

## 2026-10-01 权限审批卡片中文残留清理

- 修复 `PermissionRequestBubble` 绕过会话展示层本地化的问题。中文会话现在会把
  `Command Approval`、`File Change Approval`、`Additional Permissions`、MCP 请求、
  应用工具审批及其静态摘要、权限/策略/原因前缀映射为中文；动态命令、文件路径、服务器名、
  URL 和原始 JSON 仍保持原文，避免破坏协议和诊断信息。
- 文件变更的动态摘要（例如 `Allow changes to 2 files`）及多文件折叠提示也已按中文展示；
  新增 widget 回归覆盖命令审批、额外权限和文件变更三条路径。
- 全套定向 Flutter 回归为 `128/128` 通过；`dart analyze --format machine --no-fatal-warnings`
  未发现错误，仅保留仓库既有 lint/info。真机当前 Root `PRoot → Node → Codex` worker 未被触碰。
- 重新生成 Release QA APK 并通过只读 verifier：`31,476,027` bytes，SHA-256
  `DEDC5C05FD04E582BE4A3CBF338A6B1B75153E120C9548D928CACAA1068DC3E1`，包
  `io.henry.codex` / `1.0.0`，四个 ARM64 Codex/PRoot/worker-guard asset 齐全，未发现退役
  Bionic/Bridge asset。该包仍使用本机 debug certificate，且暂不覆盖安装，以免打断真机 worker；
  修复后的真机像素验收仍待 worker 结束后安装执行。

## 2026-10-01 CC Pocket 本地化残留清理

- 对 `packages/ccpocket_ui/lib/l10n` 的抽象接口和四个语言实现做了调用者对照：
  当前 Android App 实际只使用本地会话、Codex、工具、权限、模型和设置文案；旧
  Bridge/Claude/Firebase/远程 machine 文案没有任何 Dart 调用者。
- 删除了 217 个旧远程产品入口相关键，并继续删除其余未被当前源码引用的生成式键；
  仍被当前组件引用的会话、composer、approval、diff 和设置文案均保留。
- 修正仍被活跃错误卡片使用的登录、重连和待处理会话文案，使其指向“此设备/此应用
  的 Codex”，不再显示 Bridge、Claude 或远程机器语义。
- 定向 Flutter 回归重新通过 `123/123`；本轮未安装 APK，也没有触碰真机上仍存活的
  Root `PRoot → Node → Codex` worker。

## 2026-10-01 项目会话列表默认展开

- 当前 Android 首页的本地历史加载器已经为每个 workspace 提供全部 session；移除
  `HomeContent` 中遗留的逐项目 display limit、load-more callback、加载 spinner 和
  “显示更多”入口，项目卡片现在直接渲染该 workspace 已加载的全部会话，不再把完整历史
  隐藏在 CC Pocket 的旧分页路径后面。
- 同步移除不再可达的 `showMore` 本地化键；静态搜索确认没有旧分页字段或调用点残留。
- 该变更后的定向 Flutter 回归为 `123/123`；未安装 APK，真机上的 Root worker 保持运行。
- 重新构建 Release APK 并通过只读 verifier：`31,464,507` bytes，SHA-256
  `1384252EFCE79E256F28104218A72EB69F8C8B103AC131279CDF78C842C2B072`，包
  `io.henry.codex` / `1.0.0`，四个 ARM64 PRoot/host/worker-guard asset 齐全，已排除
  退役的 Bionic/Bridge asset。该包仍由本机 debug certificate 签名，未覆盖安装。
- 静态分析又发现并删除 `HomeContent` 中三个不可达成员/局部变量；变更后该文件无分析器
  输出，定向 Flutter 回归仍为 `123/123`。这是适配层清理，不改变 session、分组或恢复协议。

## 2026-10-01 真机中文工具事件验收

- 在真机 `6cb21282` 当前前台 Root session 截图中发现中文界面仍把工具结果标题显示为
  原始协议名 `commandExecution`；问题只在工具结果组件，工具审批名称已有独立映射。
- 修复 CC Pocket `ToolResultBubble` 的折叠和展开标题，统一把 `commandExecution`/`Bash`、
  `fileChange`/`FileChange`、用户输入和计划工具映射为中文名称；补充“中文工具结果名称”
  widget 回归，相关 session UI 测试为 `25/25` 通过。
- 该次截图也确认当前顶部模型/计划/Root 控件已收紧到一行、额度和上下文摘要位于会话区，
  但截图来自现有 Release worker，修复后的 APK 尚未覆盖安装，因此修复后的真机像素结果仍需
  在 worker 结束后重新安装再验收。
- 同步修正 session 卡片的状态展示层：`Needs You`、`Working`、`Reconnecting`、`Ready`、
  审批/重连/失败详情等在中文环境下会显示中文；assistant/tool diff 提示也不再强制英文。
  home/session 联合 widget 回归为 `35/35` 通过，底层 `SessionVisualStatus` 协议字段保持不变。
- 继续清理当前中文界面中的共享 CC Pocket 英文残留：上下文用量语义标签、全局加载更多、
  摘要展开/收起、问答卡片 Open/Confirm/Other/Cancel、复制提示和登录帮助提示均按当前
  locale 展示；结构化错误卡片、图片生成状态、实施计划卡片、问答汇总提交按钮、用量条、
  回合结果标签、Todo 展开控件和工具/diff 截断提示也已按 locale 展示。全套定向 Flutter 回归更新为 `127/127`
  通过；现有真机 worker 未被触碰。
- 以上本地化修复已重新生成 Release QA APK 并通过只读 verifier：`31,469,535` bytes，SHA-256
  `04672BF72AA8BCF5914DC43D36DEFDB1644A97F0F565F3E6C3A9B4403FBF790C`，包
  `io.henry.codex` / `1.0.0`，四个 ARM64 Codex/PRoot/worker-guard asset 齐全，未发现
  退役 Bionic/Bridge asset。该包仍使用本机 debug certificate，且没有覆盖安装，以免打断当前
  真机 Root worker；修复后的真机像素结果仍待 worker 结束后再做安装验收。

## 2026-10-01 当前检查点续记

- 重新查询 npm 官方 registry，`@openai/codex` 当前最新版本仍为 `0.159.2`；真机已安装并
  激活的也是 `0.159.2`，因此更新入口的正确结果是保留当前版本的幂等 no-op，不伪造高版本更新，
  也不触碰正在运行的 fresh Root session。
- 兼容运行时、session/provider、模型目录、历史恢复、并发隐藏 session、UI 导航和 updater 的
  定向 Flutter 回归本轮为 `123/123` 通过。Android guest-admin、命令 argv、session home 的
  定向 Kotlin 单测也通过；`builder/test-offline.sh` 也已通过。这只证明当前代码
  合同，不替代下一版 rootfs 在实体机上的更新验收。
- 修正 `CompatibilityGuestAdminInstaller` 的过时注释：APK 内 guest-admin asset 对真实 Root
  worker 采用 Linux guest 命令直通，对 App UID 采用私有包前缀；两者都不经过 Android 通用
  privilege broker。此次仅修正文档性注释，未改变设备 worker、KernelSU profile 或权限配置。
- 清理兼容 runtime 中最后一条未被生产链路调用的旧包安装分支：删除
  `tools/android-local-runtime/rootfs/sudo` 及其仅引用该脚本的 Docker fixture；当前唯一生效的
  guest-admin 入口是 APK asset `apps/codex/android/app/src/main/assets/codex-guest-admin/sudo`，
  离线合同也只验证这一份 asset。历史记录中对旧 helper 的说明保留为证据，不再把它作为可部署路径。
- 修复 `builder/test-offline.sh` 把 Python 命令写死为 `python3` 的主机可复现性问题，统一改为
  `PYTHON_BIN`（默认仍为 `python3`）。在当前 Git Bash + Python 3.11 环境下重新执行，离线合同
  全部通过；首次失败只来自调用了没有 `/bin/bash` 的 WSL 和 Windows Store Python alias。
- 直接从中文 checkout 执行 `flutter build apk --release --no-pub` 仍复现 Flutter/Gradle 的
  `File.exists()` `parent == null` 主机路径错误；按仓库既有 `tools/build-android.ps1` 的临时
  ASCII `SUBST` 路径重试成功。Release APK 只读 verifier 通过：`31,464,843` bytes，SHA-256
  `859EB96411B4104FD2DC587AAE390CDABC18F375C63761365B1BB17BBD529BDF`，包
  `io.henry.codex` / `1.0.0`，4 个 ARM64 PRoot/host/worker-guard asset 齐全。该产物未安装，
  因为实体机上的 fresh Root worker 仍在运行；证书仍是本机 Android debug certificate，属于
  Release QA 包而不是正式商店签名。
- 构建后没有覆盖安装；只读设备复查仍看到同一条 Root `PRoot → Node → Codex`、worker guard
  和 Android App 进程。当前累计 gfxinfo 为 `413` 帧、`3` 个 jank（`0.73%`），p50/p95/p99
  为 `7/10/16ms`；这说明当前窗口没有新的渲染热点，但它不是首页、设置、长 transcript 和
  多 session 全路径验收，整体随机卡顿仍保持未结论。

## 2026-10-01 模型目录入口卡顿与设置缓存修复

- 在实体机 `6cb21282` 的 Release 包中复现了设置页模型入口的真实问题：无活动 thread 时错误地
  启动独立 app-server 做 `model/list`，模型卡片会保持加载，随后 worker 以 `137` 退出；这不是
  旧 session 或真实 turn 的恢复问题。
- 修复后，无活动 thread 的设置/新会话模型目录改走当前 CLI 的 `debug models`，主动关闭 stdin，
  在线目录 10 秒、bundled 目录 8 秒有界回退；已有活动 thread 仍使用其 app-server 的分页
  `model/list`，不改变真实会话协议。设置页还会先读取按 CLI 版本与 OpenAI auth generation
  隔离的本地缓存，只有没有缓存或目录失效时才启动 CLI 探测。
- 45/45 定向 Flutter 回归通过（模型目录、账号代次缓存、session/provider 交互）。
- 真机验证：首次冷目录探测正常弹出完整的 `11` 个 CLI 模型，无 `failed to load models cache`、
  `Permission denied`、`try_lock` 或 FATAL；覆盖安装后重启 App，再进入设置直接显示“11 个 CLI 模型”，
  未重新拉起 Codex/PRoot/Node/Python worker。测试结束后已停止本轮 App。
- 当前 Release APK：`31,464,847` bytes，SHA-256
  `8D1FBEDA51DB11EF4990F07CAC552EBAD8670F363ADD0B68F5287BBA3C179B54`；
  verifier 通过，包 `io.henry.codex`、`versionName=1.0.0`、`targetSdk=36`，四个 ARM64 native
  assets 齐全。仍是本地 debug certificate 签名的 Release variant，不等同于商店签名包。
- 随后只在 `test-project` 下新建了一个 fresh session，没有打开或恢复旧 session；首次发送时完成
  一次 session 级 Root 授权，真实 turn 返回精确文本 `FRESH_RELEASE_TURN_OK`。UI 同时显示
  账户用量 `Codex 剩余 1w 93%`、上下文进度 `Context usage 11%` 以及最终回复，session 保持
  `就绪`，设备进程树仍为该 session 自己的 `PRoot → Node → Codex`。
- 在该 fresh thread 内打开模型控制器与模型列表均在约 1 秒内完成，显示当前 CLI 的 Astra、6.1 Sol、
  6 Sol、6 Luna、5.6 系列及 Daybreak 等动态模型；无新的 worker、网络、权限、`try_lock` 或
  FATAL 错误。本轮没有触碰旧 session；fresh session 为便于后续人工复查暂留在前台。

## 2026-10-01 Rootfs 工具合同与会话顶部布局修复

- 真实 fresh turn 的工具链探测确认 Root worker 为 UID 0/GID 0，`git`、`node`、`npm`、`npx`、
  `python`、`bash`、`rg` 均能从 Debian/PRoot guest 执行；唯一缺口是 `jq`。设备上虽然残留
  Android native-toolchain 的 `bin/jq`，但当前路线明确不把 Android/Bionic 工具链作为 PRoot
  fallback，因此不能用它掩盖 guest rootfs 的缺包问题。
- 修复 rootfs 构建合同：Debian foreign bootstrap 显式加入 `jq`，设备侧 PRoot finalizer 在二阶段
  完成后按 `jq --version` 与其他开发工具一起验收，离线脚本同步检查这两处合同。新 rootfs 需要
  通过现有设置页的 rootfs 更新流程部署后，设备上的 `jq` 才会对新 worker 生效；当前前台 fresh
  session 未被重启或覆盖安装。
- 压缩 CC Pocket 会话顶部的本地适配层：quota 行由 28dp 调为 24dp，usage 内容行保持 18dp，
  usage widget 不再以 22dp 子布局挤压父容器；模型/effort/计划/权限栏的外层留白、divider 和
  chip 最小高度同步收紧，交互和原始 CC Pocket 控件不变。
- `ccpocket_native_session_test.dart`、`local_ui_navigation_test.dart`、
  `local_session_conversation_test.dart` 联合回归 `63/63` 通过；shell 语法检查通过。完整离线
  rootfs 回归的首次运行曾被 Windows Git Bash 缺少默认 `python3`、Linux symlink 和大小写敏感
  staging 环境阻断；随后补充显式 `PYTHON_BIN` 与仅针对 Windows fixture 的环境分支后，
  `builder/test-offline.sh` 已完整通过。生产设备上的 rootfs 验收合同没有放宽。
- 新的普通 ARM64 Release APK 已编译并通过只读 verifier：`31,464,847` bytes，SHA-256
  `0AF84228F3172799891C3E152BFAD313833E20C0E5585FCB3550CB77846E4BE7`，包
  `io.henry.codex`、`versionName=1.0.0`、`targetSdk=36`，四个 Codex/PRoot ARM64 native
  assets 齐全。由于设备上的 fresh worker 仍在前台，本轮只生成并验证 APK，尚未覆盖安装。
- 在同一个已授权的 Root fresh session 中执行 `sudo apt install --yes jq`，没有触碰 Android
  系统分区、KernelSU 或 boot；真实 turn 返回 `/usr/bin/jq (jq-1.6)`，安装后 session 仍保持
  `就绪`。这证明现有 guest 包安装路径可作为当前设备的即时补齐方式；后续新 rootfs 仍以构建时
  内置 `jq` 为默认，不要求用户逐台手工修复。
- 清理 rootfs 构建遗留：删除未被当前 manifest/独立安装器调用、仍保留旧 Bridge 与旧包路径的
  `builder/finalize-on-device.sh`，离线检查统一针对唯一的
  `device/proot-finalize-rootfs.sh`。补齐 Windows Git Bash 的 Python、绝对 symlink 和大小写
  敏感 staging 环境说明后，`builder/test-offline.sh` 全部检查通过；这类 host 限制只跳过无法在
  Windows 创建的 fixture，不放宽生产设备 finalizer 的合同。
- 设备只读复查仍显示 App 主进程、Root `PRoot → Node → Codex` 和 code-mode host 共存，包版本
  `1.0.0`，最近 500 条 logcat 未见 `FATAL`、`try_lock`、`Permission denied` 或模型缓存错误；
  fresh session 未被停止。

## 2026-10-01 模型目录账号代次隔离

- 修复模型目录缓存只按 CLI 版本区分的问题。OpenAI 模型可见性还取决于当前账号，缓存现在同时
  绑定 `AuthBindingStore` 的账号代次；登录、退出、切换登录路径和检测到账号代次变化时都会使
  当前模型目录 future 失效，避免新账号继续看到旧账号的模型目录。
- 旧格式缓存通过 schema version `2` 失效；带账号代次的缓存不会在缺少代次时被读取，第三方
  provider 目录仍不进入该缓存路径。
- 新增“不同账号代次拒绝缓存”和“无账号代次拒绝账号绑定缓存”回归用例。模型目录、会话/provider
  隔离及会话交互定向 Flutter 回归共 `45/45` 通过；本轮未发送真实 turn，也未重试旧 session。
- 使用正式 Release 构建验证并覆盖安装到实体机 `6cb21282`，APK `31,462,183` bytes，SHA-256 为
  `21E42CA8302F0C4EF4B6C2DAC9BBD92AF9A991743CA07A388836D12AE0C1CCC`；只读 APK verifier 通过，
  四个 ARM64 Codex/PRoot native assets 齐全。冷启动仅进入 `MainActivity`，未打开旧 session；4 秒日志
  窗口未见 `FATAL EXCEPTION`、models-cache、权限或 `try_lock` 错误，进程检查只有 App 主进程，测试后
  已停止本轮启动的 App，未留下 Codex/PRoot/Node/Python worker。

## 2026-10-01 Android 原生默认模型漂移修复

- 修复 Android `SessionHistoryStore` 在模型字段缺失或仅包含空白时仍回退到旧
  `gpt-5.6-luna` 的问题，使原生历史存储与 Flutter 设置、会话和动态目录的当前默认值统一为
  `gpt-6-luna` / `low`。已有明确保存的模型不会被覆盖，仅修正缺省回退路径。
- `SessionHistoryStoreTest` 定向 Gradle 单测通过；随后重新构建普通 ARM64 Release 并使用
  `adb install -r -d` 覆盖安装到实体机 `6cb21282`，保留应用数据。APK `31,459,447` bytes，
  SHA-256 为 `71A022DE8C431E5C7640CDFE40C72AA9760B0BE26E657DF698E238C6D640FD72`，包版本仍为
  `1.0.0` / `targetSdk=36`。安装后没有启动或重试旧 session，也没有残留 worker。
- 随后只启动 `io.henry.codex/.MainActivity` 做 Release 冷启动烟测：Activity 成功进入前台，
  4 秒观察窗口内只出现 `io.henry.codex` 主进程，没有自动拉起旧 OpenAI session、Codex、PRoot、
  Node 或 Python worker；logcat 未出现 `FATAL EXCEPTION`、models-cache 或权限错误。测试结束后仅对
  本轮启动的 App 执行 `force-stop`，再次检查无残留进程。

## 2026-10-01 OpenAI 账号切换与第三方 provider 会话隔离

- 会话历史的自动恢复绑定现在按 provider 来源区分：OpenAI 会话继续要求
  `authGeneration` 与当前登录代次一致；第三方 provider 会话使用自身保存的 provider ID、地址和
  配置，不会因为 OpenAI 登录、退出或切换账号而被误判为过期。
- 第三方配置被删除或 ID 不再存在时仍保持历史可见，但不会静默回退到 OpenAI 或另一个 provider；
  只有恢复了匹配的 provider 配置后才会自动恢复其 Codex thread。
- 新增并通过回归覆盖：第三方 provider 历史在 OpenAI auth generation 变化后仍启动原生 Codex
  app-server 并发送 `thread/resume`；OpenAI 历史在账号代次变化后不启动旧 app-server；provider
  切换仍会保留 transcript 并为下一条消息建立正确来源的新 thread。
- 定向验证：`session_history_test.dart` 与 `local_session_conversation_test.dart` 共 `56/56`
  通过。第三方恢复测试使用条件泵送等待 CLI `debug models` 的异步指令探测，避免把固定短延时误当
  成真实的 app-server 启动完成。
- 针对本轮源码重新构建普通 ARM64 Release：APK `31,459,503` bytes，SHA-256 为
  `3B1B844646D8B2BDB1413D462F127EBE3FF881927D6A3DDB5489EAE38AF1DBC9`；通过 `adb install -r -d`
  覆盖安装到实体机 `6cb21282`，安装前后未清理应用数据。安装后只读包信息仍为 `versionName=1.0.0`
  / `targetSdk=36`，没有启动旧会话，也没有残留 Codex、PRoot、Node 或 Python worker。

## 2026-10-01 KernelSU R1 插件真机生命周期验收

- 使用仅含 `module.prop` 与 `ccpocket-plugin.json` 的元数据探针归档，SHA-256 为
  `1a3caea6ae327803e3eeac16687028b9122239a55d64f5335ff3109edd8b7927`。归档声明无脚本、无
  overlay、无 action、可回滚、无需重启；设置页校验结果为有效风险 `R1`，没有修改 KernelSU
  profile，也没有触碰 boot 或系统配置。
- 在实体机 `6cb21282` 的正式 App 运行态中通过设置页完成 `stage → install → enable`；随后
  “刷新已安装模块”读到 10 个模块，并显示 `ccpocket.plugin.r1probe` 已启用。点击“禁用”后，
  设置页显示已禁用，设备侧 `ksud module list` 同步返回 `enabled=false`。
- 点击“卸载”并确认后，KernelSU 正确返回 `remove=true` 的延迟移除状态；这是 KernelSU 的
  正常语义，实际目录会在模块管理器清理/重启时移除。为不留下本轮临时模块，随后只删除了已
  核验的两个精确路径 `/data/adb/modules/ccpocket.plugin.r1probe` 与
  `/data/adb/modules_update/ccpocket.plugin.r1probe`，并删除设备下载目录中的测试 ZIP；复查
  `ksud module list` 已无该 ID。没有重启设备，没有删除用户数据或现有会话。
- 修复设置页刷新后的状态投影：解析 `ksud module list` 时过滤 `remove=true` 条目，避免一个
  已标记卸载、尚待 KernelSU 清理的模块重新显示成“已禁用”。`PluginBrokerTest` 增加该反例，
  Android 定向单测成功（`BUILD SUCCESSFUL`）。随后使用 ASCII `SUBST` 路径完成正式 Release
  构建，APK 为 `31,460,099` bytes，SHA-256 为
  `77d5274a446fcf5e92315fa4711593edc0dbbcae29aaa1b403cea0278cf5bd2e`；只读 verifier 通过，
  四个 ARM64 Codex/PRoot native assets 齐全。已 `adb install -r -d` 覆盖安装到实体机并保留
  应用数据，启动后仍显示活动 CLI `0.159.2`、原有工作区和最近会话；logcat 没有 FATAL 或
  models-cache 错误。
- 本轮临时归档已从仓库 `tmp/` 删除，设备 App 私有 staging 中的
  `ccpocket.plugin.r1probe.zip` 也已精确删除；既有的 `ccpocket.plugin.font.zip` 回滚归档未动。
  应用私有目录中保留已校验归档是现有回滚设计的一部分，不属于设备上的已安装模块。重启 App
  后 R1 探针不再出现在设置页，原有工作区、历史会话和认证数据仍保留。

## 2026-10-01 实体机 Flutter 帧采样

- Android `dumpsys gfxinfo` 对 Flutter `SurfaceView` 返回 0 帧和 4950ms 哨兵值，不能用来判断
  本 App 的 Flutter 卡顿。临时用正式 Release 构建链加入 `CODEX_FRAME_TIMING_QA=true`，只用于
  采样，未改生产逻辑；在实体机 `6cb21282` 上采集 Home 与设置页各约 1200 帧后，重新构建并
  安装了不带 QA define 的普通 Release。
- Home 首个 120 帧窗口：`total p50/p95/p99 = 2.551/10.341/96.380 ms`，`>16 ms = 4`、
  `>32 ms = 3`；后续暖机窗口 `>32 ms = 0`，大多数窗口 `>16 ms = 0`。设置页首次进入/首轮
  资源加载窗口：`total p50/p95/p99 = 4.701/18.978/38.448 ms`，`>16 ms = 10`、
  `>32 ms = 3`；第二窗口后稳定到 `>16 ms = 0`。当前证据指向“设置页首次进入长尾”，不支持
  宣称全局随机卡顿已经完全解决。
- 普通 Release 已覆盖安装到真机，APK SHA-256 为
  `77d5274a446fcf5e92315fa4711593edc0dbbcae29aaa1b403cea0278cf5bd2e`；启动后只剩 App 主进程，
  原有工作区/会话保留，R1 临时探针和 Root approval 均未重新出现。该结论随后由下方的设置页
  惰性构建与普通 Release 复验继续推进。

## 2026-10-01 设置页惰性构建与 CLI 更新后普通 Release 复验

- 将 `CodexPocketSettingsPage` 的设置区块改为 `ListView.builder` 按区块惰性构建：运行时、登录、
  Codex、通用、编辑器、Root、关于、网络和页脚分别按视口进入时挂载。原有设置 key、层级、文案、
  操作回调和滚动入口保持不变；删除了旧的一次性 `ListView(children: ...)` 重复实现。
- 代理配置读取与 KernelSU 暂存归档恢复改为首帧后启动，避免设置页转场期间同时争用平台通道；这两项
  仍会在进入对应设置区块后完成，错误状态和保存行为不变。
- 定向 Flutter 回归 `network_proxy_settings_test.dart`、`settings_model_catalog_test.dart`、
  `local_ui_navigation_test.dart`、`home_host_access_widget_test.dart`、`widget_test.dart`、
  `root_security_notice_settings_test.dart`、`local_session_auth_test.dart`、
  `codex_mcp_settings_test.dart` 共 `28/28` 通过；两份改动文件的 Dart 分析无 error/warning，只有
  一条已有风格级 `use_null_aware_elements` info。
- 用 `CODEX_FRAME_TIMING_QA=true` 的正式 Release 采样包在实体机 `6cb21282` 设置页做了 8 个滚动窗口。
  首个窗口 total p50/p95/p99 为 `4.591/21.632/35.624ms`，`8/120` 帧超过 16ms、`3/120` 帧超过
  32ms；第二个窗口为 `3.922/10.705/14.762ms`，仅 `1/120` 帧超过 16ms；之后窗口 total p99 为
  `5.495–8.486ms`，均无超过 16ms 的帧。结论是设置页热滚动已稳定，首轮仍有可见长尾，不能据此
  宣称全局随机卡顿已经解决。
- 随后重新构建并安装无 QA 插桩普通 ARM64 Release：APK `31,459,203` bytes，SHA-256
  `D49CFCE6A982C7F0570C36949F868DCB7169A42F7293DB6E9BDBC6EB8C2ABEA1`；verifier 通过，四个 ARM64
  Codex/PRoot native assets 齐全，包 `io.henry.codex`、`versionName=1.0.0`、`flags=0x0`。覆盖安装
  保留应用数据，设备当前活动 CLI 仍为 `0.159.2`，现有工作区与历史会话未清理，最终进程仅有 App
  主进程；本轮没有打开或重试旧 session，也没有发送真实模型 turn。

### 2026-10-01 CLI 更新流程最新版本复核

- 主机通过 npm 官方 registry 查询 `@openai/codex` 的 latest 为 `0.159.2`；实体机 `6cb21282`
  设置页再次执行“更新 Codex CLI”并确认，完整等待检查流程结束后按钮恢复可用，没有产生新的版本目录，
  因此本次结果是已是最新的 no-op，而不是重复下载同一版本。
- 设备侧只读核对仍为 `current -> versions/0.159.2`，活动版本目录保留 `0.156.1`、`0.157.1`、
  `0.159.2`；实际执行版本化 ARM64 CLI 返回 `codex-cli 0.159.2`。过程中没有旧 session 被打开或
  重试，结束后进程列表只有 `io.henry.codex`，没有残留 Codex、PRoot、Node 或 Python worker。
- 这次复核同时确认了更新入口的幂等性：当 registry 版本等于活动 CLI 时不会改动 `current`，也不会
  破坏已有工作区、认证状态、历史或保留版本。下一次 registry 出现更高 SemVer 时，仍沿用已验收的
  “查询 → PRoot guest 安装到版本目录 → `codex --version` 校验 → 原子切换”链路。

## 2026-10-01 实体机图片附件回调验收

- 在实体机 `6cb21282` 的新建临时 `test-project` session 中点击“附加图片”，使用系统文件选择器选取
  一张设备上已有的 `1.25 MB` JPG；没有创建、覆盖或删除设备文件。选择器返回后，Android native
  `ACTION_OPEN_DOCUMENT` 回调成功，Flutter composer 显示图片预览和“移除图片”语义按钮，发送按钮也
  正确变为可用。
- 点击“移除图片”后附件从 composer 消失，随后直接返回会话列表；没有发送 prompt/真实 turn，首页未出现
  新的最近会话卡片。该结果确认了选择器、字节读取、MIME 校验、附件状态和清除回调的完整链路；本轮不
  触碰原图片，也没有留下临时媒体文件。

## 2026-10-01 Root/PRoot CLI 冒烟与账号切换回归固化

- 在实体机 `6cb21282` 的最新普通 Release 中创建临时 session，第一次启动 Root/PRoot 本地 Codex
  时通过一次“允许此会话使用 Root”授权；随后在会话 composer 输入 `/version`，真实返回
  `codex-cli 0.159.2`。本次只验证本地 CLI 版本和启动链，没有发送模型 turn，也没有消耗模型额度。
  临时 session 已从应用内删除，结束时设备没有残留 Codex、PRoot、Node 或 Python worker。
- 增加 Flutter 回归：历史记录属于旧 `authGeneration`、当前认证 generation 已递增时，仍显示本地历史，
  但不会启动 `app-server`，不会发送 `thread/resume`，也不会提供旧账号的自动恢复路径。该测试使用真实
  的 generation 变化夹具，避免把“页面参数变化”误当成全局账号切换。
- `local_session_conversation_test.dart` 全文件 `33/33` 通过；其中包括 OpenAI/第三方 provider 切换、
  session 自动恢复、隐藏 session 继续运行、CLI 命令、图片输入、停止/重试和本次旧账号隔离回归。
  本轮只增加测试保护，没有重新构建 APK 或改变设备上的认证数据、工作区和既有历史。

## 2026-09-30 Codex CLI 应用内更新真机验收

- 在实体机 `6cb21282`、正式 Release APK、无活跃 Codex worker 的条件下，从设置页点击“更新
  Codex 命令行工具”，确认对话框后完整走过 npm registry 查询、PRoot guest 内安装、暂存版本
  `codex --version` 校验和 `current` 符号链接原子切换；没有手动修改设备上的 launcher。
- 更新期间设备进程短暂出现 Root supervisor、PRoot 和 `codex@0.159.2`，随后维护进程正常退出。
  只读检查确认 `/data/user/0/io.henry.codex/no_backup/codex-compatibility-v1/home/.codex-cli/current`
  指向 `versions/0.159.2`，保留版本目录为 `0.156.1`、`0.157.1`、`0.159.2`；这证明新版本
  已激活，而不是只下载到临时目录。
- 设置页最终显示“已验证 · … · 活动 CLI 0.159.2”。强制停止并重新打开 App 后再次进入设置，
  仍显示活动 CLI `0.159.2`，说明应用设置中的版本状态和设备 launcher 都已持久化，没有启动旧
  session，也没有清理 workspace、历史或认证数据。
- updater 与设置目录刷新回归共 `17/17` 通过：包括版本比较、暂存校验失败保持旧版本、激活失败
  回滚、保留版本回退，以及更新后模型目录刷新。此次设备验收未发送真实模型 turn；运行中的
  session 不会因 CLI 更新被替换，后续新启动的 compatibility session 才解析新版本。

### 2026-09-30 更新后新 session 与 guest Python 网络验收

- 未打开或重试任何旧 session；从 Home 的 `test-project` 工作区创建了临时新 session，选择
  Root，接受一次绑定该 session 的 Root grant。通过会话内 `/version` 运行应用自己的本地 CLI
  路径，界面收到 `codex-cli 0.159.2`，证明新 session 实际解析了刚激活的 overlay，而不是只
  显示设置页保存值。
- 通过同一 session 的 `/network-test` 运行 Debian/PRoot guest 的 Python 探测。`chatgpt.com`
  返回 HTTP 403、`api.openai.com` 返回 HTTP 401、`auth.openai.com` 返回 HTTP 403，但三者均
  报告 DNS、连接和 TLS 可达（设备代理为 `127.0.0.1:7890`）；这是未携带凭据的探测结果，不是
  provider 登录失败。随后 Codex RPC 返回“可达（未发模型请求）”，说明更新后的 CLI、PRoot、
  Python guest 和 app-server 维护链路可用，未消耗模型额度。
- 命令完成后设备只剩 `io.henry.codex` 主进程，没有残留 Codex/PRoot/Node/Python worker。
  两个本轮临时 session 已通过应用自己的会话菜单删除；workspace、认证状态和原有历史 session
  未清理。此次验收仍未发送真实模型 turn，因此不把 provider 最终回复标记为本轮通过。

## 2026-09-30 账号切换后的旧 session 隔离

- 为 session history 增加本地 `authGeneration` 绑定。登录成功、退出登录和切换登录方式
  完成后递增 generation；记录只保存 generation，不保存 token、API key 或账号凭据。
- 首页启动恢复现在只恢复当前 generation 的记录。旧记录（包括升级前没有 generation 的
  legacy history）仍可打开查看，但不会自动启动旧 Codex thread、不会自动重连，也不会把
  旧 thread 的 auth failure 当作当前账号的可重试错误。
- 旧 session 发送新消息时保留本地历史，但清除旧 provider thread 身份，为当前账号创建
  新 thread；界面明确提示“历史保留，旧账号上下文不恢复”。旧 session 的恢复横幅也不再
  提供 Resume，避免误触旧账号服务。
- 增加认证失败识别：OpenAI refresh token 被撤销、未登录等错误会将 session 标记为账号绑定
  过期并停止自动重连，而不是继续反复请求旧账号。第三方 provider 的本地配置不受影响。
- 定向 Flutter 回归 `session_history_test.dart`、`local_session_auth_test.dart`、
  `local_session_conversation_test.dart` 共 `56/56` 通过，覆盖 generation 过滤、旧历史
  保留、provider 切换、隐藏运行中的 thread、停止/重试和恢复行为。
- 直接在中文 checkout 编译会触发既有 Flutter/Gradle `parent is null` 工具链问题；使用仓库
  现有 ASCII `SUBST` 构建脚本完成正式 Release：`31,460,083` bytes，SHA-256
  `299fb3e34eb94547595ebaa5e4856d108075161b323c58e69d6abf19720fe1fd`。APK verifier 通过，
  `io.henry.codex`、ARM64 PRoot/host/worker assets 齐全，签名仍是本机 QA/debug certificate，
  variant 是 Release 而不是商店签名包。
- 覆盖安装到实体机 `6cb21282` 并启动检查：旧账号 worker 先被停止；新版本启动后只有
  `io.henry.codex` 主进程，没有自动出现 Codex、PRoot、Node 或 app-server，证明旧历史没有
  被启动恢复。应用数据、workspace 和历史 session 均未清除。
- `flutter test` 编译并执行通过；`flutter analyze` 仍被本机 analysis server 的截断 LSP JSON
  输入崩溃阻断（`FormatException: Unexpected end of input`），不是源码诊断结果，需单独修复
  工具链/分析器环境后再补静态分析。

## 2026-09-30 清理后 Release 真机复验

- 在 2026-09-30 路线清理后的当前源码上重新运行核心 Flutter 回归：`67/67` 通过，覆盖
  capability refresh、OpenAI/第三方 provider 切换、模型与推理档位、session 并发/恢复、
  停止与重试、图片输入、CLI 命令、中文本地化、Root 行为和历史状态。
- Android Release Kotlin 编译成功；`CompatibilityRootLaunchScriptTest` `8/8`、
  `RootProfileProbeTest` `22/22` 通过，共 `30/30`，无 failure/error。测试通过 ASCII junction
  运行，并跳过仅用于 APK 生成的 Flutter task；随后完整 Release APK 构建也已成功。
- 当前源码 Release APK 已通过只读 verifier：`io.henry.codex`、`versionName=1.0.0`、
  `31,452,183` bytes，SHA-256
  `b500148167dbb3ce1555f7e49413d5c6a1774aca671f70f548028d053859287b`。四个 ARM64
  PRoot/host/worker 资产齐全，退役 Bridge/Bionic Codex 资产为空；签名为本机 QA/debug
  certificate，不是商店发布签名。
- 已使用 `adb install -r -d` 覆盖安装到实体机 `6cb21282`，未清理应用数据；设备端
  `base.apk` SHA-256 与构建产物完全一致。启动后 `MainActivity` 保持前台，采样 logcat
  没有 `FATAL EXCEPTION`。
- 真机 UI 冒烟确认首页保留工作区、最近会话和设置入口；设置页没有触发 Root approval，
  显示已登录、Root + Linux/PRoot 运行环境、`gpt-6-luna`、推理“低”、审批“从不审批”、
  沙盒“完全访问”。点击默认模型入口约 1 秒内打开真实 CLI 目录，显示包括
  `gpt-6-astra`、`gpt-6-sol`、`gpt-6-luna` 和 5.6 系列在内的 11 个模型。
- 模型目录关闭后 Root/PRoot app-server worker 正常退出，设备只剩 App 进程；回到首页后
  工作区和历史 session 仍可见。模型目录读取没有发送真实模型 turn。
- 上述条目是本节第一份 Release 检查点的记录；随后已在同一真机上补做真实 turn 尝试、
  历史错误显示和 worker 生命周期复验，结果见下方“补充复验”。KernelSU 写操作和手机
  帧级性能采样仍未宣称通过。

### 2026-09-30 补充复验：额度错误显示、正式版安装与 Root/PRoot 启动

- 针对上一轮真实 OpenAI turn 返回的账号额度限制，补充了中文/日文/韩文/英文额度错误
  显示映射，并修正历史 JSON transcript 绕过映射的问题。适配器只替换 CC Pocket 的
  显示投影，不改写本地原始记录；新的回归覆盖 JSON 错误记录不泄漏原始 URL。
- 相关定向 Flutter 回归最终为 `62/62` 通过，包含 CC Pocket session surface、会话恢复、
  provider 切换、并发切换、Root 路由、CLI 命令、图片输入、额度错误本地化和 JSON transcript
  显示投影。
- 重新构建并安装正式 Flutter Release APK：`31,454,847` bytes，SHA-256
  `474196cfb0498ce4167c45e25f75acbee08de5611e50771b15035fd6575178d1`。只读 verifier
  通过，包名 `io.henry.codex`、`versionName=1.0.0`；4 个 ARM64 PRoot/host/worker
  资产齐全，禁止的 Bridge/Bionic 资产为空。仍为本机 QA/debug certificate，不是商店签名。
- 设备 `6cb21282` 覆盖安装成功且保留应用数据；安装后 `MainActivity` 在前台，crash buffer
  没有新的 `FATAL EXCEPTION`。打开已保存的 OpenAI session 后，UI 无障碍树确认额度卡片
  显示“已达到 Codex 使用额度上限。请等待额度恢复，或升级 Pro/购买额外额度后重试。”，
  不再显示 `chatgpt.com` 原始链接。Root/PRoot/Codex worker 链也实际启动过。
- 本轮真实 provider turn 的最终回复仍受账号服务额度限制，服务端返回“已达到 usage limit，
  可在 2026-10-03 17:47 重试/升级或购买额度”；因此不能把“最终 assistant 回复成功”写成
  通过。该结果不等价于 Android runtime、Root 或 app-server 启动失败。
- 测试期间两次出现其他前台应用抢占：`com.fund2506.airconcontroller` 和
  `com.miui.securitycenter`。经前台 Activity、UI 包名和当前焦点核对，均不是
  `io.henry.codex` 崩溃或 APK 内容；已重新把 Codex 带回前台。为安装最终 APK，已只停止
  本轮由 QA 启动的 `io.henry.codex` worker，未清理 session/workspace 数据。

### 2026-09-30 thread 顶部密度收敛

- 压缩 thread 顶部的 CC Pocket 适配布局：AppBar 设为 52dp，状态行 20dp，额度槽位
  28dp，Token/上下文槽位 18dp，模式栏上下间距 2dp，模式 chip 高度 40dp；保留原有
  返回、会话设置、菜单、停止、模型、计划和 Root 交互。
- 保留额度/Token 固定槽位，避免异步数据返回时模型控制栏上下跳动；同时比原来的
  `48dp + 22dp` 顶部数据槽位少占 24dp。真机 `6cb21282` 的有数据 session 中，模式栏
  无障碍 bounds 从旧的约 `y=637..777` 上移到 `y=595..735`，额度和上下文仍正常显示。
- 相关 Flutter 回归 `55/55` 通过。最终 Release APK 已重新构建、verifier 通过并安装到
  真机：`31,455,443` bytes，SHA-256
  `e57440d6a597ef19cbdaec1e63e6a1786c3db62c60c6746789230875a79ebfb6`；4 个 ARM64
  PRoot/host/worker 资产齐全，禁止的 Bridge/Bionic 资产为空，启动后无新增 App crash。

## 2026-09-28 性能收敛与真机 UI 验收阶段

### 2026-09-28 当前收敛检查点（最新）

- **菜单响应续验（最新 Release）**：模型与权限 sheet 改为首帧先展示、再异步读取 CLI model/permission profiles；权限常用选项提前到 Root 软路由说明之前。provider 来源选择位于设置一级菜单，OpenAI 与第三方并列，第三方配置是子页。
- 最新 Release `artifacts/release/android-codex-1.0.0-arm64-release-menu-review-20260928.apk` 构建、verifier、AVD 覆盖安装及安装包 hash 核对通过：31,408,203 bytes，SHA-256 `997B502F59165BC82DA1CB6E13A0BEF60E94D30B7C823062BDCA09AD2F8145CC`。实体手机已断开，本次模拟器验收不替代前一版的真机真实 turn/provider 证据。
- Flutter 全量测试 `328/328` 通过。AVD 首个 250ms 检查点可见模型弹层，首个 200ms 检查点可见权限菜单；该 AVD 没有 PRoot rootfs，所以模型目录不可用并显示当前模型回退提示。provider/source/third-party 子页层级已目视确认，未在该空配置模拟器上伪造服务调用结果。
- 抽查工作区标题/卡片、session 长按和 thread 溢出菜单，分别确认动作留在对应对象层级；未触发任何删除。AVD `gfxinfo` 菜单开合样本为 21 帧/18 janky（p50 18ms、p90 34ms、p99 250ms），但设备使用 Google SwiftShader，GPU p90 是 4950ms 哨兵值且重复样本只返回 0 帧。这个结果不能代表手机性能，也不支持“随机卡顿已解决”；需要物理机有效帧样本继续定位。
- 测试后已停止 AVD 上本轮启动的 app；session/workspace 数据未删除。全部随机 UI 卡顿仍缺有效帧级样本，后续性能验收需在设备重新连接后采集。

- 修复全局设置页的推理档位本地化遗漏：`minimal` 现在在中文界面显示为“最小”，并补充
  `none`/`minimal` 到全局设置值映射；会话内档位弹层和全局设置弹层保持一致。
- Flutter 全量测试最终为 `336` 项通过。过程中发现并修复了代理设置 widget 测试的异步
  状态竞态：输入框滚动到可见后等待解锁帧，并断言用户输入确实写入保存路径。
- 最新 Release APK 已重新构建并通过只读 verifier，保留产物位于
  `artifacts/release/android-codex-1.0.0-arm64-release.apk`（构建输出随后已清理），
  `118,526,565` bytes，SHA-256
  `a69935375ce0b51e038b96569fb1f77408edd07915327aded9ecdbd530f475b5`；4 个 ARM64
  Codex/PRoot worker 资产齐全，禁止 broker 资产为空。
- AVD UI/交互验收证据已固化到
  `tmp/ui-audit-20260928-performance-optimized/AUDIT.md`；最新推理档位弹层为
  `18-effort-picker-fixed.png/xml`。本轮物理设备未连接，不能把 AVD 结果写成 Root/真实
  Codex turn 已通过。验收结束后 AVD 已关闭，5650/5651 端口已在共享登记表标记为
  `released`。

- 流式 app-server 事件现在只在 Flutter 帧边界刷新会话页；Home 快照和历史持久化也分别
  做了按帧合并与 350ms 静默合并，终态仍立即落盘。多 session 的根页面快照更新同样按帧
  合并，避免两个并行 turn 把整个 Home/IndexedStack 重建数十到数百次。
- `LocalSessionPage` widget 实例按 session 复用，不再因另一个 session 的快照更新而重新创建
  所有隐藏会话页；会话运行时和历史状态仍由各自 page state 独立持有。
- 会话消息列表现在缓存已解析的 CC Pocket `ChatEntry`，流式 token 刷新不再重复解析整段
  历史；Home/IndexedStack 外壳的活动快照刷新改为 120ms 节流，停止、失败和完成等生命周期
  转换仍立即刷新。这样多 session 并行时，选中的会话保持帧级流式显示，隐藏 Home 不再按帧
  重建。
- 定向 Flutter 回归 57 项通过，覆盖 Home、Session、会话恢复、并发切换、interaction state
  以及 CC Pocket 会话组件的中文显示；字体资源修复后追加的 session 回归 24 项也通过，
  且不再出现 `google_fonts` 联网下载失败日志。
- 清理后首次 Release 验收发现 Flutter 资源未完整进入 APK，Material 图标在真机/AVD
  上显示为方框；执行 `flutter clean`、`flutter pub get` 后重新构建，恢复了
  `FontManifest.json`、`AssetManifest.bin` 和 `MaterialIcons-Regular.otf`，因此这不是
  UI 代码层的图标缺陷。
- 当前性能优化后的 Release APK 已通过只读 verifier：`C:\codex_ascii_build\apps\codex\build\app\outputs\flutter-apk\app-release.apk`，
  118,526,529 bytes，SHA-256
  `2abacfa0e6be2d45257d978b8486b64d835c6d55b85173644294f400cee48746`；必需 Flutter 资源、
  7 个主题字体和 4 个 ARM64 PRoot/worker 资产齐全，禁止的 broker 资产为空。仍为本地
  debug certificate，仅用于真机 QA。
- 随后的 UI 收敛重新通过定向回归 `57/57`：工作区卡片与会话卡密度统一、恢复历史会话状态
  改为“已保存”、会话消息顶部留白收紧、模型设置面板移除无意义的拖拽把手占位，中文运行时
  错误和 App UID 受限状态改为可读文案，并移除 HomeContent 中空的 macOS banner 挂钩；
  Release APK verifier 仍通过。
- 当前 Release 已安装到 AVD `emulator-5554`，没有覆盖物理设备上的旧 APK：设备重新上线后
  只读检查仍发现 `libcodex_worker_guard.so`、`libcodex_proot.so` 和多个 `codex` worker
  存活，因此遵守安装前保护规则，不覆盖安装、不杀进程。AVD 已实际完成以下交互验收：打开
  工作区/新会话、模型设置入口、计划模式切换、Root 写入策略/完全访问/只读选择、图片选择器、
  设置页和中文文案；截图与无障碍树保存在 `tmp/ui-audit-20260928-release-post-cleanup/`。 
- 这次 AVD 数据面尝试真实启动 Root turn，Root 审批入口可用，但由于 AVD 没有 KernelSU
  和 App UID Android-native runtime，最终按预期显示“未安装应用 UID 可执行的 Android
  原生 Codex”，不能据此否定实体设备的 Root/PRoot turn。
- 运行时错误此前只在 fallback 文本路径汉化，app-server `error` 事件和旧历史记录仍会
  直接显示英文；现在统一处理了这两条路径。最新 APK 已在 AVD 上复验，错误卡片只显示
  一条中文诊断，不再出现英文/中文重复卡片。最新截图与 XML 保存在
  `tmp/ui-audit-20260928-final-data-plane/`，其中 `15-session-error-history-fixed.*`、
  `16-model-sheet-final.*`、`18-permission-sheet-final.*` 为最终证据。
- AVD Release smoke 的 `gfxinfo` 记录到 50th frame 17ms、90th 40ms、GPU 90th 16ms；
  本次没有再出现字体网络等待导致的 550ms 慢帧。AVD 仍不是物理设备性能基准，实体机
  需要在连接后做同样的帧耗时复测。
- 性能优化后的源码回归仍为 `57/57`，Release 构建和 ARM64 资产 verifier 通过；本轮没有
  物理设备连接，因此没有把新 APK 安装到真机，也没有把模拟器结果写成真机性能结论。

### 当前设备 UI 验收证据

早期物理设备审计截图和无障碍树保存在 `tmp/ui-audit-20260928-performance/`；本轮 AVD 的新增审计
截图和无障碍树保存在 `tmp/ui-audit-20260928-final-data-plane/`。本轮已实际检查首页、会话页、
模型选择底 sheet、计划/权限入口、图片选择器和设置顶部。仍不能把它写成物理真机全量验收：

- 会话页仍有标题/工具事件/Thinking 内容的中英文混排；旧历史会话页面会显示“已停止”，但
  下方仍保留完整历史，需区分“当前进程状态”和“历史消息状态”的视觉语义。
- 设置页的长说明仍使部分卡片纵向偏高，小屏需要继续做信息密度收敛；这属于下一轮 UI 优化，
  当前入口和滚动容器可用。
- 物理设备的真实 Codex turn、Root/PRoot 运行态、用量流和多 session 长时间并行仍需在现有
  worker 自然结束、允许安全安装新 Release 后复验；本轮不能用旧 APK 的结果替代新 APK。
- AVD 的系统图片选择器打开成功但目录为空，这是测试镜像数据状态，不是应用入口失效。

因此当前结论是：性能第一轮源码优化、字体离线化、关键 UI 交互验收和旧路线清理已完成一轮；物理真机的
真实 turn/Root 数据面回归仍未完成。旧 Bridge/多平台路线已从源目录、CI、npm workspace 和
专用脚本中移除。下一步是在现有 worker 自然结束后安全安装新 Release 做数据面回归，以及根据
本轮静态检查结果继续删除无效的旧 UI 生成残留，而不是重新引入旧架构。

## 2026-09-28 真机复核：第三方 provider 凭据不再进入 Root worker 命令行

- 真机只读进程检查发现旧实现把 provider 环境变量以内联 `env -i KEY=value ...`
  的形式放进 KernelSU/worker 启动命令；这会让密钥出现在进程 argv 中，与“凭据只作为
  子进程环境变量存在”的设计不一致。
- Root 和 App-identity compatibility 启动路径现在都先在应用私有目录生成权限收紧的
  一次性环境文件，由固定 `/system/bin/sh` 读取并导出，随后在 `exec` PRoot/Codex 前
  删除文件。启动命令只携带环境文件路径，不携带 provider 凭据；正常的 `CODEX_HOME`、
  proxy、模型目录和 Root marker 语义保持不变，环境文件创建/构造失败也会清理临时文件。
- 新增 `CompatibilityRootLaunchScriptTest` 回归，验证 provider 值不出现在 Root argv，
  Android Kotlin 单元测试 116 项中 115 项通过、1 项既有跳过项；Release APK 构建和只读
  verifier 通过：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，
  117,531,723 bytes，SHA-256
  `1812d33dfd009d3234af584bd5822e92acf3082dd913572be3da8fd34bdcf2c9`。4 个 ARM64
  PRoot/worker 资产齐全，禁止 broker 资产为空。
- 当前真机仍有多个活跃 worker，本轮没有覆盖安装新 APK；因此该凭据保护修复已完成
  源码、单测和产物验收，尚待 worker 自然结束后安装到真机做一次真实 provider turn
  与进程 argv 复核。

## 2026-09-28 PRoot CLI overlay 原子切换

- 将 `CodexCliUpdater` 的活动 `current` 指针从 `ln -sfn` 改为临时 symlink 后用
  `mv -Tf` 原子发布；升级或回滚验证失败时清理候选链接，并保留原活动 CLI。
- 这样更新只影响之后解析 `current` 的新 compatibility session；已经运行的 app-server
  继续持有自己的绝对可执行文件路径，不需要重启或抢占其他 session。
- `test/codex_cli_updater_test.dart` 10 项定向回归通过，并覆盖最终 `mv` 发布和失败回滚；
  `git diff --check` 通过。源码已重新构建 Release APK 并通过只读 verifier：
  `apps/codex/build/app/outputs/flutter-apk/app-release.apk`，117,530,631 bytes，
  SHA-256 `c36072415b5ba25c78c158daa142ac6044a3f834ab447446992dd41bbd3a732c`，
  必需的 4 个 ARM64 PRoot/worker 资产齐全且禁止 broker 资产为空。尚未覆盖安装 APK，
  避免中断当前真机 worker。

## 2026-09-28 真机覆盖安装中断行为：`--dont-kill` 不能作为安全保证

- 为验证版本化 rootfs 发布是否能与活跃 session 共存，在设备 `6cb21282` 上使用
  `adb install --dont-kill -r` 覆盖安装 Release APK，并保留应用数据。
- 安装命令立即返回 `Success`，短时检查还能看到旧的 Root/PRoot/Codex PID；但数秒后
  旧 app 进程和全部 worker PID 都消失。说明本机 Android 包管理更新会延迟终止旧进程，
  `--dont-kill` 不能保证活跃 turn 在覆盖安装期间继续运行。
- 随后只启动应用主界面，没有清理数据。应用恢复了已持久化的 workspace/session，并重新
  拉起 3 组独立 Root/PRoot/Codex worker；历史数据保留，但原先正在运行的 worker 只能算
  被中断后恢复，不能写成“无中断升级”。
- 结论：以后覆盖安装前必须先确认 `libcodex_worker_guard.so`、`libcodex_proot.so`、
  `codex` 和 `libcodex.so` 均无活跃 PID；发现活跃 worker 就拒绝安装并等待用户/会话自然
  结束。新增 `tools/install-android-codex.ps1` 执行该前置检查，不再依赖
  `--dont-kill` 的表面行为。该脚本不会自动停止 session，也不会自动启动应用。

## 2026-09-28 PRoot rootfs 版本化发布，更新不再要求停止活跃 session

- 修复了 rootfs 安装器与进程管理器之间的错误耦合：过去 `withRootfsMaintenance` 在任何
  session 存在时直接拒绝安装，且安装脚本会把整个固定 runtime 目录搬走，因此无法在
  活跃 session 运行期间更新。
- 新安装写入 `codex-compatibility-v1/rootfs-slots/<install-id>/`，完成 ARM64 PRoot、Node
  和 Codex 验证后，仅原子替换 `active-rootfs-slot` 指针。已有 worker 已经持有旧 slot 的
  绝对 rootfs 路径，会继续运行；新的 worker 从新指针解析新 slot。guest home、session
  数据和 CLI overlay 仍位于共享 app-private 目录，不再随 rootfs 更新被清空。
- Java 侧保留旧的 `rootfs/` 固定目录读取逻辑，现有安装无需重新导入；发现 active slot
  指针时优先读取版本化 slot，并拒绝 slot/pointer/rootfs 的符号链接穿越。
- Flutter 设置页文案已同步：更新期间不会停止活跃会话，更新只作用于新会话。
- 已完成静态 shell 语法检查与 Android Kotlin/JVM 编译验证；真机安装尚未执行，因为
  当前设备仍有多个 Codex worker 活跃，不能用 `adb install -r` 打断它们。待它们自然结束
  后再安装并做“旧 turn 继续、新 turn 使用新 slot”的设备验收。

## 2026-09-28 真机当前 rootfs 基线复核

- 设备 `6cb21282` 仍在线，应用进程及 3 组 Root/PRoot/Codex worker 仍在运行；本轮没有
  覆盖安装 APK，也没有停止任何 session。
- 通过只读 Root 查询确认当前设备仍使用 legacy 固定目录
  `/data/user/0/io.henry.codex/no_backup/codex-compatibility-v1/rootfs`，没有
  `active-rootfs-slot` 指针；当前 manifest 为 `debian-bookworm-node-24.19.0-codex-0.154.0-linux-arm64`。
- 该旧 rootfs 中实际存在 `git`、`node`、`npm`、`npx`、`python`、`python3` 六个入口。
  这证明工具文件已落在设备，但不替代新 APK 安装后的真实 guest 执行、rootfs slot
  切换和新旧 session 并行验收。
- 本工作树最新 Release APK 已构建并通过只读 verifier，尚待现有 worker 自然结束后
  再进行真机覆盖安装和数据面验证。

## 2026-09-28 独立 App 产物 broker 残留防回归

- 从独立 Android app 的 JNI 资产目录移除遗留的 root-read broker manifest；该 broker
  从未属于当前 Root/PRoot 运行链，Gradle 也一直将对应二进制排除在 APK 外。
- `tools/verify-android-apk.ps1` 现在把 `libcodex_root_read_broker.so` 作为禁止资产：若
  后续构建误把它重新打入 APK，verifier 会直接失败，而不是把产物误报为独立 Root worker。
- 当前 Release APK 重新运行 verifier 通过：4 个必需 ARM64 PRoot/worker 资产齐全，
  `forbiddenPresent=[]`；本次只读产物检查未覆盖安装真机。

## 2026-09-28 CLI 更新器维护目录解耦

- 修复 PRoot CLI 更新器仍要求先创建用户工作区的问题。更新命令现在使用
  native compatibility probe 返回的 app-private `noBackupFilesDir` 作为隐藏的
  runtime maintenance cwd，不把该目录加入用户工作区列表，也不把 CLI 更新伪装成
  用户会话。
- 该维护目录只用于 npm/CLI overlay 的下载、校验和切换；用户 workspace、Codex
  session、rootfs 和 APK 仍保持独立。更新器不会为了更新而停止现有 worker；已有
  app-server 继续持有当前可执行文件，新启动的 compatibility session 才使用切换后的
  `current` CLI。
- `linux_compatibility_backend_test.dart`、`linux_compatibility_runtime_test.dart`、
  `codex_cli_updater_test.dart` 定向回归通过，共 18 项；Android
  `CompatibilityCommandArgvTest` 通过，覆盖 Kotlin 原生执行器编译路径。
- 追加覆盖 Root 策略、session JSON-RPC/并发、历史恢复、CC Pocket 首页/会话和 updater
  的组合回归，Flutter 退出码为 0；没有发现本次维护目录改动引入的 session 路由或 UI 回归。
- 本项源码已通过测试；对应 Release APK 已重新构建并通过只读 verifier：
  `apps/codex/build/app/outputs/flutter-apk/app-release.apk`，117,528,939 bytes，
  SHA-256 `bb8aed6d36dd3509126a9e940232798e6de07fc44a002a2cd16dc14a48f20357`，
  包名 `io.henry.codex`，4 个 ARM64 PRoot native asset 全部存在。该包仍使用本地
  Android debug certificate，只用于本地安装验证；尚未覆盖安装到当前真机，因为设备上已有
  多个 Root/PRoot worker，不能为了覆盖安装主动终止用户未要求停止的 session。

## 2026-09-28 真机 Root 宿主完整根目录映射验收

- 在实体设备 `6cb21282` 上从首页新建 session，默认执行身份显示为 `Root`；真实
  Codex turn 中执行 `id` 返回 `uid=0(root) gid=0(root) groups=0(root),3003,3009`，
  证明 worker 沿 KernelSU 正常 profile 启动，没有被降级为 App UID 或只在 PRoot 内伪装
  root。
- 同一 Root/PRoot session 随后执行 `cat /android/etc/hosts`，返回真实宿主内容
  `127.0.0.1 localhost` 与 `::1 ip6-localhost`，退出码为 0。该路径由完整宿主根绑定
  `--bind=/:/android!` 提供，不是工作区或少数系统目录的白名单映射。
- 因此当前实现的实际语义是：Root session 在 guest `/android` 下可见 Android 宿主根目录，
  读取能力仍由设备实际 UID 0、SELinux、挂载和 ROM 决定；App UID session 不获得该映射，
  仍保持非 Root 语义。这条验证覆盖了“Root 默认完整可读”的核心数据面，不把 App UID 的
  `/android` 不可见误判为 Root runtime 失败。
- 页面在两次真实 turn 后均回到“就绪”，上下文用量从 3% 更新到 4%，没有出现 worker
  退出、`try_lock`、模型缓存失败或网络错误。未修改 KernelSU profile、组、SELinux 或
  任何宿主文件。

## 2026-09-28 继续回归：session 命令状态与 Release 真机验证

- 修复 `command/exec` 与 `command/exec --tty` 的状态展示：命令开始时将 session 状态置为 `running`，因此 thread 顶部、Home 快照和 CC Pocket 会话卡片不再把长时间命令显示成“就绪”；命令结束后根据连接、turn 和 client 状态恢复为 `ready`、`running`、`disconnected` 或 `stopped`。
- 定向 Flutter 回归共 56 项通过，包含会话对话、首页多 session、native session surface 和 interaction state；Google Fonts 下载失败仍只是测试环境日志噪声。
- Release APK 已重新构建：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，118,060,503 bytes，SHA-256 `f28666329296cefafd44e1194e2ddfb38e4e1b3a092808e3a1e3854870ce808a`；使用本地安装签名，仅用于当前真机验证。
- 通过 `adb install -r` 安装到实体设备 `6cb21282`，应用数据和历史 session 保留。覆盖安装会由 Android 终止旧 APK 进程及其 worker，这是升级过程的系统行为；随后重新打开历史 session 会自动恢复对应 app-server，不能把覆盖安装期间的旧 worker 持续运行写成已支持。
- 真机验证：`/exec sleep 12` 在命令子进程存活期间 thread 顶部显示“运行中”，完成后恢复“就绪”；从 Home 打开另一条历史 session 后，两棵独立 Root worker 同时存在，进程树分别包含 `libcodex_worker_guard.so`、PRoot 和 Codex app-server。第一条 session 标识 `01a0e456-0…`，第二条为 `01a0e452-f…`，没有发生路由串线或互相停止。
- 本轮仍未把“应用进程被系统杀死/升级后自动恢复全部未结束 session”定义为已完成能力；当前验证的是重新打开对应历史 session 后恢复，后续应单独设计后台恢复策略，避免把升级重启与用户手动停止混为一谈。

## 2026-09-28 真机多 session 回归与列表点击修复

- 修复 CC Pocket 首页懒列表在动态本地历史滚动后出现“卡片视觉内容与点击回调错位”的问题。根因是复制的 `HomeContent` 使用全局 `findChildIndexCallback` 维护可变历史条目的 key→index 映射；session 历史更新/复用后，卡片文本已经换成下一条记录，但 `Slidable` 保留了上一条 session 的点击闭包。移除这层全局索引映射，保留卡片自身稳定 key，让列表按当前 index 构建并保持视觉卡片与 session 回调一致。
- `_findSessionEntry` 现在把稳定的 app-owned `sessionId` 作为会话身份；已有稳定 ID 时不再回退到 provider `threadId`，避免同一 workspace 的历史记录因旧 thread 记录相同而重新打开第一条。
- `/exec` 设置 session 级 snapshot 的 active/turn 状态，隐藏页面时不主动停止 worker；当前 worker 仍由对应 session 的 runtime handle 持有。
- 定向 Flutter 回归 `ccpocket_native_home_test.dart` 与 `local_session_conversation_test.dart` 共 31 项通过。Release APK 已重新构建并安装到实体设备 `6cb21282`，包名 `io.henry.codex`，安装使用 `adb install -r`，未清理应用数据。
- 真机历史点击复测：同一 `privacy-investigation` workspace 下，第二条卡片打开后的页面标题为旧 session 的 `01a0e452-f…`，不再错误落到第一条 `01a0e456-0…`。同时观察到两个独立 Root worker，运行目录分别为 `local-hmoxffobm7` 与 `local-hmoxba03cr`，进程树各自包含独立的 `libcodex_worker_guard.so`/PRoot/app-server 链路，证明 app-server/session 进程可以并存。
- 设备触控验证必须以当前截图和 `uiautomator` bounds 为准：该真机高密度屏幕的 adb 输入坐标与截图/无障碍 bounds 存在缩放差异，不能直接把 bounds 中心当作 `input tap` 坐标。此项是测试坐标问题，不是 session 路由逻辑。
- 本次未把“长时间 `/exec` 子进程在首页卡片上显示为生成中”写成已验收；当前设备上可以观察到对应 `sleep` 子进程仍存活，但需要下一轮单独验证命令执行 RPC 的完成语义与首页状态快照是否一致。

## 2026-09-26 当前实现检查点

- 按新的总体路线移除了执行链对自定义 `codex_agent` 域、固定组/capability 和自定义 SELinux context 的硬依赖；Root launcher 只要求真实 UID 0，诊断字段不再成为启动门禁。
- Root 写入策略改为软路由：普通路径直接处理；启动链、boot、raw block 和 KernelSU 目标进行具体目标/恢复路径/用户授权提示，优先可回退 KernelSU 模块，但不把模块路径变成永久拒绝或唯一通道。用户选择的审批策略和沙盒设置会传递给本地 Codex session；只有显式只读 session 在应用层拒绝写入。
- 新建 session 不再等待可选的 provider 偏好通道，避免 Android 偏好存储异常让新建按钮无响应；provider 加载完成后再补充到新鲜 session。应用首帧使用已定义的中文默认语言，避免设置读取期间显示未翻译系统界面。
- 定向 Flutter 回归 `local_session_auth_test.dart`、`local_session_conversation_test.dart`、`local_ui_navigation_test.dart`、`root_security_notice_settings_test.dart`、`ccpocket_native_session_test.dart`、`kernelsu_plugin_settings_test.dart` 共 51 项通过；日志中的 Google Fonts 下载失败未造成测试失败。
- Release APK 已构建并通过只读 verifier：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，117,360,934 bytes，SHA-256 `298729bf7aa459d51b14a6f6f4b5aa2115f7fafd442e200223dc7b8177c609f1`，5/5 ARM64 runtime asset 齐全，签名为本地 Android debug certificate。
- 本检查点执行时 `adb devices -l` 没有在线设备，因此没有把安装、KernelSU Root、真实工具链或真实 Codex turn 写成已验证；待真机重新在线后继续设备侧验收。

### 2026-09-26 继续检查点

- 全量 Flutter 回归 `flutter test --no-pub` 通过，共 259 项；其中包含多 session 并发、隐藏会话继续流式输出、provider、图片、模型目录、权限和本地化回归。`google_fonts` 的网络字体下载错误仍只是测试环境日志噪声，未造成测试失败。
- Android `:app:testDebugUnitTest --offline --no-daemon --max-workers=1` 通过；本次改动后的 Kotlin 编译与 JVM 单元测试均成功。Gradle 仍有既有的 AGP/Kotlin/compileSdk 弃用提示，不影响本次结果。
- 原生 `readCodexModelCache` 将缺失的 `models_cache.json` 改为正常的可选缓存未命中；只有非普通文件、符号链接、超大或读取异常才返回错误。模型目录仍优先由当前 CLI 的 bundled/debug、在线/app-server 结果动态发现，缓存不会替代运行时能力。
- 本次源码对应的 Release APK 已重新构建并通过只读 verifier：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，最新产物 116,815,570 bytes，SHA-256 `52dfe6331f002249eb60b8e65be247227a65facf3ed329151648f99466e7ecac`；5 个 ARM64 Codex native asset 均存在，签名仍是本地 Android debug certificate，仅用于本地安装验证。构建前清理了一个残留的旧 `flutter_build.d` 路径清单和 Gradle Release 生成目录，未触碰源码或用户数据；随 APK 注入的 `tools/android-local-runtime/skills/AGENTS.md` 已同步为 Debian/PRoot guest 优先、Android ABI 按能力回退。
- 本检查点当时再次确认实体设备不在线；随后按用户允许启动 `codex_api35` AVD，安装上述 Release 成功并启动 `io.henry.codex/.MainActivity`。AVD 首页与设置页稳定，设置树显示新的 Root/PRoot 路由说明；过滤后的 logcat 没有 `failed to load models cache`、`model_cache_unavailable` 或 `FATAL EXCEPTION`。这只是 x86_64 AVD 的非 Root UI/进程烟测，不是实体设备 Root、ARM64 工具链或真实 Codex turn 验收。

## 本轮目标

本轮以“真实能力闭环”为验收单位，优先补齐基础工具、第三方模型、图片输入、root 权限规范、运行时诊断和 CC Pocket 会话层的未完成入口。多进程不再作为假设性限制：现有会话客户端已经按 session 持有独立进程，回归测试覆盖两个 session 同时存活。

## 当前状态

| 领域 | 当前结果 | 验证边界 |
| --- | --- | --- |
| 多 session | 已保留独立进程/状态模型 | Flutter 回归测试通过；多进程真机能力已由用户确认可用，本轮不再把它当作 app-server 限制 |
| Android 原生工具链 | `native-toolchain-0.7.0-arm64-v8a` 已在真机安装；root-owned 只读工具树标为 `system_file`，普通 App UID 现在可通过 PATH 执行，root 与 App UID 共用同一份工具 | 2026-09-23 真机设置页显示“App UID 可用”；Android 16 下逐项通过 PATH 探测 manifest 的 8 个工具。APK 仍未内嵌约 215 MB 工具包，干净安装需先导入 |
| PRoot guest 包安装 | 固定 `sudo apt install` shim 下载目标包及必需依赖，只解包到 App 私有 package prefix；不改 finalized rootfs、不运行 maintainer scripts、不调用 Android `su`；PATH 与包私有库路径已接通 | Kotlin/JVM、兼容后端回归和 Release APK 内 asset 检查通过；Docker daemon 未运行，Linux 容器包提取与真机验收仍待完成；不安装 recommends，也不处理要求 maintainer scripts 或写入 prefix 外绝对路径的包 |
| npm/npx | 使用官方 npm CLI JavaScript 包，由 Android/Bionic Node 执行；没有混入 Windows 或 glibc 可执行文件；HostToolProbe 已同时探测 npm/npx | 真机通过 `npm/npx --version`（10.9.2）、App UID/root 的 `npm prefix`，以及 App UID 私有目录中的 `npm init`、`npm pkg get`、`npm install --offline --ignore-scripts`、`npm pack --dry-run` 和 Node 执行 smoke；带真实依赖的网络/缓存安装仍需单独验收 |
| 第三方模型 | 自定义名称、HTTPS 地址、模型名和 API key；API key 通过 Android Keystore AES-GCM 加密；支持 OpenAI-compatible `/chat/completions` SSE、reasoning/content delta、usage、停止；重开 session 会恢复已保存的 user/assistant 上下文；DeepSeek 模型 ID 会把当前会话 reasoning effort 映射进请求；通用 provider 不接收 DeepSeek 专属字段 | 本地 HTTP SSE fixture 通过；2026-09-26 生产 Dart 客户端对 DeepSeek `deepseek-flash` 的真实文本/图片和 low-effort 请求通过；Release APK 在只读 AVD 中完成 Keystore 配置重启恢复、真实 provider turn，以及下述本地图片 fixture turn。实体手机上的设置/网络路径仍待验收 |
| 图片输入 | 复用 CC Pocket composer 的图片入口；Android `ACTION_OPEN_DOCUMENT` 多选、MIME/大小/数量上限；Codex app-server 使用 `{type: image, url: data:...}`，第三方 provider 使用 OpenAI-compatible `image_url` | Dart 请求映射、app-server wire-shape 回归、Android Kotlin 编译通过；Release APK 已在 API 35 AVD 验证 DocumentsUI 选图→OpenAI-compatible 图片请求→SSE 回复与 usage 闭环；实体手机选图、Codex app-server 图片 turn 和超大图片拒绝仍待验收 |
| root 规范 | 新增 Root 分层分类器、App UID/Root 选择、按 session 保持授权、Root 正常审批/沙盒设置透传，以及 `AGENTS.md`/`ROOT_ACCESS_POLICY.md`；高风险路径采用 KernelSU 模块优先的软路由，不再把完全访问或自定义域当作启动前提 | Root launcher/profile 与策略回归通过；KernelSU 模块校验/回滚能力仍保留为可选实现，真实设备 harmless stage/apply 尚未验收 |
| 读权限 | 架构合同允许全局读取，不设 app path allowlist；实际仍受 Android UID、SELinux、挂载和目标 ROM 约束 | 策略测试通过；不能把“可请求读取”误报成任意设备都可读 |
| Root 宿主可见性 | Root/PRoot 通过 `/android` 暴露完整 Android 宿主根目录；App UID 不获得该映射 | 2026-09-28 真机 Root session 实际 `uid=0(root)` 并成功读取 `/android/etc/hosts`；App UID 对照 session 仍不可见 |
| 写权限 | workspace/runtime 和普通外部路径按 Root session 当前策略直接处理；系统、init、boot image、KernelSU 目录及 raw block 走具体目标验证、恢复路径和授权提示，KernelSU 模块优先但授权后的直接路径不被架构永久封锁 | 分类器测试通过；高风险真实写入未执行，设备侧软路由仍待验收 |
| `try_lock` | 运行时将已知 native lock 能力错误识别为 compatibility fallback；对应噪声不再作为对话气泡显示 | Flutter 回归通过；这不是把 Android 原生 lock 原语伪装成已支持，native 不兼容时仍透明降级 PRoot |
| 计划/权限/CLI | 计划模式可在 setup/active mode bar 切换并同步到 Codex client；Root 权限入口覆盖常规 Root、完全访问和应用级只读，Root 当前选择的 approval/sandbox 会真实透传；补充 `/status`、`/plan`、`/permissions`、`/interrupt`、`/model`、`/effort`、`/refresh-models`、`/compact`、实际执行 `codex --help`/`--version`，以及隔离 runtime scope 的 `/cli <args>` 非交互 CLI 入口；禁止通过 `/cli` 另起未绑定的 app-server | 相关 UI/会话测试通过；仍不是把所有交互式 CLI 子命令重做成原生页面 |

## 已落地文件

- 工具链：`tools/android-native-toolchain/releases/native-toolchain-0.7.0-arm64-v8a/`
- 工具链说明：`tools/android-native-toolchain/README.md`
- 第三方 provider 配置与加密存储：`apps/codex/lib/core/domain/custom_provider.dart`、`apps/codex/lib/services/custom_provider_store.dart`、`apps/codex/android/app/src/main/kotlin/io/henry/codex/MainActivity.kt`
- provider SSE 客户端：`apps/codex/lib/core/application/custom_provider_session_client.dart`
- 图片输入：`apps/codex/lib/core/domain/image_attachment.dart`、`apps/codex/lib/services/local_image_picker.dart`
- root 策略：`apps/codex/lib/core/domain/root_access_policy.dart`、`docs/android-local-codex/ROOT_ACCESS_POLICY.md`
- KernelSU broker：`apps/codex/android/app/src/main/kotlin/io/henry/codex/PluginBroker.kt`、`PluginManifest.kt`、`PluginArchiveValidator.kt`、`KernelSuPluginBridge.kt`；设置页：`apps/codex/lib/kernelsu_plugin_settings.dart`、`services/kernelsu_plugin_service.dart`
- agent/runtime 约束：`tools/android-local-runtime/skills/AGENTS.md`
- 会话/CLI 入口：`apps/codex/lib/core/application/codex_session_client.dart`、`apps/codex/lib/main.dart`
- CLI 非交互兼容入口：`apps/codex/lib/main.dart`（`/cli <args>`）

## 已执行验证

以下验证在 2026-09-22 至 2026-09-23 完成：

1. 定向 Flutter 测试通过：root 分层、Codex JSON-RPC、两个 session 并发、provider SSE/usage/image、host tool probe，共 25 项；随后 root/provider 回归继续通过。
2. 全量 `flutter test --no-pub` 通过，共 134 项。测试期间 `google_fonts` 的网络字体下载有错误日志，但没有造成测试失败；这是测试环境网络噪声，不作为字体加载已验证的依据。
3. KernelSU broker 的 `:app:testDebugUnitTest --tests io.henry.codex.PluginBrokerTest` 通过，共 28 项；覆盖 ZIP/manifest 校验、路径/特殊文件拒绝、R1/R2/R3/R4、回滚、固定命令和 root 输出隔离。
4. Android `:app:compileDebugKotlin` 通过，覆盖 Keystore provider 存储、图片选择通道和 KernelSU method channel；Gradle 仍报告既有的版本/弃用警告。
5. `validate-manifest.py` 对 0.7.0 包的 manifest、完整文件树和哈希通过。
6. 最新 Dart/Kotlin 组合通过 Android `:app:assembleDebug`；由于中文 checkout 路径会触发现有 `jni`/CMake 产物检查错位，本次从 ASCII junction `C:\codex_ascii_build` 构建成功。APK 输出仍位于仓库的 `apps/codex/build/app/outputs/flutter-apk/app-debug.apk`；这证明源码可打包，但不把中文路径问题误报为已修复。
7. 最新同一源码通过 Android `:app:assembleRelease`，并通过只读 APK verifier：`io.henry.codex`、`versionName=1.0.0`、5 个 ARM64 PRoot/root-read native asset 全部存在、签名可验证。当前 release 为 116,213,071 bytes，SHA-256 为 `bfc25cf59bb8f0e1f37e52158907ab37d7f4a21e9d22d12482be5f6989868995`，使用 Android debug certificate（SHA-256 `3860f93ed80f5f60b536ffeb5033670d8a1aa78c46d45480f87fa768780ecfc0`），不能作为商店发布签名；该包已安装到真机，包含 KernelSU broker、图片选择超限拒绝、app-server 图片 wire-shape 和 provider SSE/中断隔离修复。
8. `flutter analyze --no-pub` 在 ASCII junction 下完成，无 analyzer error；当前仍有 83 条既有 lint/info，因此不能写成“零告警”。Flutter 命令因这些 lint/info 以非零状态结束。中文路径下分析服务返回截断 JSON 并退出，已确认是工具链路径问题。
9. 通过真机 `6cb21282`（arm64-v8a、Android 16）完成 0.7.0 归档导入；当前包 UID 为 10509。root manifest 为 0.7.0，App UID 下 `git 2.55.0`、`node v22.23.2`、`npm/npx 10.9.2`，root 下 `npm/npx 10.9.2`，两种身份的 `npm prefix` 均返回成功。App UID 私有目录中的 `npm init --yes`、`npm pkg get name`、`npm install --offline --ignore-scripts`、`npm pack --dry-run --json` 和 Node 执行也通过。归档导入曾暴露 manifest 被错误计入 payload 的计数 bug，已修复并重新构建验证；旧 0.6.0 在失败期间未被覆盖。
10. 本轮修复后全量 Flutter 测试为 134 项；新增 Codex app-server 图片 wire-shape、标准多行 SSE provider fixture、KernelSU broker 28 项回归，均通过。最新 release 已重新安装到真机并通过 `tools/verify-android-apk.ps1`。
11. 修复 native toolchain 探测误报：探测改为 Android 后台线程，Flutter 等待上限从 4 秒提高到 90 秒，并加入 30 秒结果缓存；0.7.0 的完整 SHA-256 探测不再阻塞 UI 或被过短超时误判为不可用。
12. 2026-09-23 在真机查明 App UID 仍不可用的根因：工具虽然 root-owned 且 mode 0755，但继承了 `/data/local/tmp` 的 `shell_data_file` SELinux 标签，Android 16 实际记录 `{ execute }` 拒绝。安装与启动探测现在会把经过完整校验的只读工具树标为 `system_file`；App UID 验收改为经与 Codex 相同的 PATH 按命令名执行 manifest 中所有 8 个工具。真机设置显示 `已验证 · 0.7.0 · App UID 可用`。Kotlin 编译、release 构建及 APK verifier 通过；APK SHA-256 `a88d86d6cf925474dc386c28c0342142443e1ca88744fdc1236fa3fe5e8ba53d`，大小 116,215,199 bytes，已安装到 `24031PN0DC`。

尚未通过或尚未执行的验证不能被本页的“通过”替代：`flutter analyze` 曾遇到 analysis server JSON EOF 并异常退出；它应在后续单独重试，但不阻塞本轮已通过的编译和测试结论。

## 下一次真机验收顺序

1. 用一个固定的小型第三方依赖验证网络/缓存 npm install，确认 Android/Bionic 工具链的缓存和 TLS 行为；本项已在 2026-09-28 真机 Root/PRoot session 中完成，见文末“真机 npm 依赖安装数据面验证”。
2. 实体手机上验证第三方 provider 设置与网络 turn；Release AVD 已通过 Keystore 保存/重启恢复、真实流式回复和 usage 验收。检查手机端 streaming、usage、停止和错误提示。第三方 provider 只提供模型对话，不获得本地 tool/root 权限。
3. 从 composer 选择一张图片，验证 Codex turn 和第三方 provider 各自的图片请求格式；再验证超过数量/大小上限时只拒绝该附件，不影响 session。
4. 分别验证 default/full/read-only 和 plan mode 的切换；高风险路径只验证“展示审批/转 KernelSU plugin”路径，不写 boot 或 raw block。
5. 继续记录真机 ROM、Android API、ABI、工具版本和失败日志，不把主机测试结果改写成设备结论。

## 明确未完成项

- （已完成）npm 依赖安装与 npx 临时包下载/执行已在真机 Root/PRoot session 中完成数据面验收；仍保留不同包、原生扩展和脚本生命周期的兼容性差异。
- 第三方 provider 的真实网络端点兼容性矩阵（不同厂商对 reasoning、usage、图片字段的差异仍需逐个适配）。
- KernelSU broker 的真实设备 harmless plugin stage/apply、list/rollback 仍待验收；普通 Codex worker 仍不能获得任意 `su` 命令、路径或环境变量。R3 系统凭据门控已接入，但没有在手机上触发验证。
- 所有 Codex CLI 交互命令的完整 parity。当前优先覆盖 app-server 能力和常用 slash commands，尚未把 CLI shell、全部 flags、所有 interactive subcommand 映射为 Android UI。
- native Android lock 能力本身仍可能受 ROM/运行时约束；现在的处理是诊断收敛和 PRoot fallback，不是虚假宣称 native 已完全兼容。
- 中文路径下 `flutter analyze` 的分析服务异常已定位为返回截断 JSON；源码检查可从 `C:\codex_ascii_build` junction 正常运行，但现有 lint/info 仍需后续按优先级收敛。
- native toolchain 尚未成为 APK 内置组件：当前安装包只包含导入器和运行时 PATH 接线，0.7.0 包仍需通过设置中的 tar/文件夹导入或独立部署脚本安装到 `/data/local/tmp/io.henry.codex/native-tools`。因此“重新安装 APK 后立即有 git/node/npm/python”目前不能宣称完成。
- 0.7.0 真机第一次导入曾因生成的 Android `sh` 脚本保留了 raw-string 的 `\$()` 转义而失败，旧 slot 未被覆盖；第二次导入又发现 toybox `cp -a` 试图保留 App UID owner，触发 `chown ... Operation not permitted`，因此改为 `cp -R` 后显式归一化 owner/mode。
- 为避免 SAF 对 npm 数千文件逐个查询，加入 tar 快速导入；第一次归档验收发现归档内 manifest 被重复计入 payload，修复为“staging 保留 manifest、bundle 去除 manifest”。正式包 `4fda0fcd...` 在真机归档导入后通过 root/App UID 的 git/node/npm/npx 验收。
- 2026-09-22 后续追踪发现“工具链在 app 中仍显示不可用”的直接原因是 probe 在主线程同步完成 215 MB/3153 文件校验，同时 Dart 只等待 4 秒；现已异步化、放宽超时并缓存。另补齐 PRoot fallback 对同一 root-owned native slot 的 bind/PATH/argv 解析，避免切换 fallback 后再次丢失 git/node/npm/python。
- 2026-09-23 真机复查发现另一个独立原因：即使文件 mode 为 0755，`shell_data_file` 标签仍禁止 App SELinux 域 `exec`；已改为 `system_file`，并让状态探测通过实际 PATH 启动工具，而非只测试绝对路径或 DAC 位。2026-09-23 APK 已安装，设置页实测 App UID 可用。
- 真机选择器对 ADB 写入的 `.tar` 索引不及时，本次用同内容 `.zip` 别名完成选择；Installer 按 tar 内容校验，不依赖文件扩展名。临时别名和验证截图已清理。
- 图片选择器此前在 `ClipData` 超过 4 项时静默截断；现改为在读取前明确拒绝超限选择，避免用户以为所有附件都已发送。debug/release 构建均通过，release 已安装到设备。
- Codex app-server 图片协议此前误用了 provider 的 `image_url` 字段；已按官方 SDK wire shape 改为 `type=image` + `url=data URL`，第三方 provider 仍使用 `image_url`。provider SSE 现在按空行聚合事件，并隔离中断后的旧 HTTP 流，避免旧响应污染新 turn。
- 将 CC Pocket 的 KernelSU typed broker 核心移植到独立 `io.henry.codex` 包：固定操作词、`ccpocket.plugin.*` 命名空间、ZIP/manifest/路径/特殊文件校验、R1-R4 风险、app-private staging、单级 previous rollback、固定 `ksud` root helper 和无诊断输出；设置页接入导入、风险预览和显式安装。method channel 不接受伪造的 `device_credential` 字符串。

## 2026-09-23 本轮续进工作日志

- 设置页增加 Codex CLI 应用内检查/更新入口：仅面向已验证的 Linux/PRoot runtime，从官方 npm registry 获取 stable 版本，在应用私有 home overlay 中按版本安装；验证 staged `codex --version` 后切换固定 launcher，失败时恢复之前 launcher，保留原始 rootfs 和 manifest。
- CLI 更新成功后自动重新加载模型目录，避免页面继续使用更新前的缓存；新增页面回归，验证升级后 GPT-6 Luna/Sol 会进入模型选择列表。更新与回滚模拟覆盖成功、已最新、stage 验证失败、激活失败回滚、首次更新失败清理。
- CLI one-shot 命令会把准备中、执行中、结果/退出码或错误写入会话 transcript；流结束但没有退出码明确视为失败。常用命令说明与反馈新增中文分支，并以会话内 `/version` widget test 验证命令执行与结果可见。
- 对本轮碰到的 root 权限提示和空 prompt 历史提示补齐中英文分支；设置中的 Codex 用量旧卡片未再使用，实际 quota 保持在 CC Pocket 对话界面/首页摘要。
- 继续为文件浏览和备份历史的标题、空态、错误、恢复确认及操作反馈补齐中文；不改变现有读写审批规则。
- Root 会话的一次性授权记录从页面 State 移到该 session 独有的 runtime handle，避免同一 session 页面重建/切换后重复询问；新 session ID 不复用旧批准。
- 首页继续用紧凑 workspace/project/session 列表承载运行状态，移除已隐藏“进行中”分区留下的旧 session 转换器和无用 pin 状态；状态仍随最近会话展示。
- 验证：最新源码全量 Flutter 测试 143 项通过；新增模型刷新、会话内 CLI 命令反馈回归通过。`:app:compileDebugKotlin` 和 `:app:testDebugUnitTest --tests io.henry.codex.PluginBrokerTest` 在本轮 Dart UI 文案改动前通过。全量 Dart analyze 最近一次报告 86 条 warning/info、未发现 analyzer error，并以非零退出；因此不标记为静态分析零告警。
- 后续补充 Root 授权 UI 回归：同一 session 多次刷新登录状态只批准一次；`/new` 后创建的新 session 会再次询问。定向测试通过，全量 Flutter 测试现为 144 项通过。
- 2026-09-23 真机只读复查：`6cb21282` 上 Codex App 位于前台且仍有本地运行时子进程；为避免更新安装中断当前工作，未覆盖安装。CLI 下载、模型目录真机确认继续列为待验收，不用主机模拟结果替代。
- 最新 ARM64 release APK 已重建并由只读 verifier 检查：包名 `io.henry.codex`，5 个 PRoot/root-read native assets 齐全，签名可验证；大小 116,227,979 bytes，SHA-256 `d9ae2ff41e6539762c03163acabb06d3d9aa83c24474414aaaa8a3cf18864a23`。此本地包使用 Android debug certificate，未安装到手机，也不等于商店发布签名。
- 尚待真机：从设置真实下载并切换 CLI、确认模型目录出现 GPT-6 Sol/Luna；KernelSU harmless plugin 的真实设备 stage/apply/list/rollback。JVM broker 通过不等于真机 root/KernelSU 验收。

## 2026-09-23 真机依赖安装 smoke

- 在已连接 ARM64 Android 真机上确认 Node `v22.23.2`、npm `10.9.2` 可执行；从 npm registry 安装 `is-number@7.0.0` 成功，随后由 Node 加载模块并输出 `installed-module-ok`。
- 首次安装因该 adb shell 未设置 `HOME`，npm 默认尝试创建 `/.npm` 而失败；通过将 `--cache` 指向本轮唯一临时目录后成功。这说明 runtime 启动环境必须提供可写 HOME/cache，不能只确认 npm 二进制存在。
- 设备 `adb shell id` 实际为 KernelSU `uid=0(root)`、SELinux `u:r:ksu:s0`，因此本项只记为 root-context Bionic 网络安装 smoke；release 包 `run-as io.henry.codex` 因非 debuggable 被拒绝，尚未证明 App UID 或 app 内 PRoot 的依赖安装。
- 已核对并删除本轮创建的 `/data/local/tmp/npm-smoke.cjNsgt`，再次 `ls` 确认不存在；未覆盖安装 APK，也未操作活跃 Codex 进程。
- 线程列表方面，官方当前协议的 `thread/list` 有 cursor/archived 等字段，但它读取发起 app-server 的 Codex home。当前实现按 session 隔离 `CODEX_HOME` 以保证并行进程互不冲突；不能将 per-home 列表误接成全局 workspace 列表，需在不打破 session 并发隔离的前提下设计发现路径。
- 下一步优先完成 App UID/PRoot 下的依赖安装验收（需在不打断用户活跃 session 的时机），同时推进尚缺的 provider 网络兼容和 app-server UI 能力；本 smoke 不代表整个项目或 native-first 阶段已完成。

## 维护规则

后续每个缺陷都按“代码闭环 → 定向测试 → 相关构建 → 真机验收边界 → 更新本页”记录。没有真机证据的项目只写“代码/主机已验证”，不写“设备已完成”。高风险 root 变更必须先有可回滚验证，再通过 KernelSU plugin 路径执行；普通 worker 不应获得绕过审批的系统写入口。

## 2026-09-22 本轮工作日志

- 补齐 Android/Bionic native toolchain 0.7.0 的 npm/npx 入口，继续沿用 Git、Node、Python、Bash、rg、jq 的 manifest、逐文件 SHA-256 和原子 root slot 导入合同；未把 Windows/glibc 可执行文件混入 Android 包。
- 将第三方 provider 的 session 历史恢复、无 key 请求、provider 删除后的 active 选择保持，以及图片/SSE/usage/停止链路纳入现有会话模型；provider 仍不获得本地 tool/root 能力。
- 扩展 root 写预检到 `sh/bash/su/toybox/busybox -c` 包装命令和 `insmod`，高风险/boot/raw block 路径继续 fail-closed；`/cli <args>` 使用独立 runtime scope，禁止通过它另起未绑定 app-server，并在 root 下经过策略和确认。
- 重新运行全量 Flutter 133 项、root/provider 定向回归、Kotlin 编译、debug/release APK 构建和 APK 只读验证；未把 host/ASCII-junction 证据升级为真机证据。
- 修正工具链导入脚本的 Android shell 变量转义；为 root 全局读 visibility 加入 `danger-full-access + on-request` 协议回归；普通 App UID 现在把只读 native slot 放入 PATH；工具链状态单独显示 App UID 是否可用；补充 npx 探测、root 权限选项收紧、离线无模型目录时的推理档位选择，以及切换第三方 provider 时保留历史并显式切换 transport。
- 重新运行全量 Flutter 133 项、定向 25 项、Kotlin 编译和 release APK；release 已安装到 `6cb21282`，首次 0.7.0 导入失败证据已记录，第二次导入尚未完成设备验收。

## 2026-09-23 持续推进：会话配置持久化

- 修复本地原生 session history 曾把所有模型和推理档位固定归一为旧默认值的问题：现在保存并恢复 CLI 当前提供的模型 ID 与 effort（包括 GPT-6 Sol/Luna 和未来模型名），未识别/空值仍有安全默认值。
- 将 Root execution identity 与一次性授权标记写入具名 session 的本地历史；恢复同一 session 时沿用该 session 授权，新 session 不继承。没有真实 session ID 的旧 workspace 记录不会获得 Root 授权。
- Flutter 定向回归 16 项、全量回归 145 项通过；Android `:app:testDebugUnitTest` 成功。测试日志仍有既有 Google Fonts 网络下载提示及 Gradle/Kotlin 插件弃用警告，不代表这些环境提示已解决。
- 以正式 release 模式重建 APK，并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 只读校验：包 `io.henry.codex`、version `1.0.0`、5 个 ARM64 PRoot/root-read native assets 齐全、签名校验通过；大小 116,229,651 bytes，SHA-256 `2f97e3c8f715e2bde471d2bdd9f5aa514d828bf208a4fcec40850f83c3d87983`。该本地包仍使用 Android debug certificate，不能作为商店发布签名。
- 当前真机 App 仍处于前台且有运行时进程；为免中断 session，本轮未安装 APK。真机上的 CLI updater/model refresh 和 KernelSU harmless plugin 验收仍未完成，不能由主机测试替代。
- 下一项沿 compatibility gap 继续推进：完成 native npm/npx 在 App UID PRoot 中的设备验收；之后继续处理 updater/model refresh、KernelSU 低风险插件验收和 app-server/UI 能力缺口。

## 2026-09-23 PRoot native npm/npx launcher 修复

- 核对已安装的 native npm/npx launcher，确认其 shebang 为 `#!/system/bin/sh`；真机 Debian guest 没有 `/system/bin/sh`，而兼容执行器原先会将该 wrapper 当普通可执行文件直接传给 PRoot。
- 现在只有当 `npm`/`npx` 命中 Android native toolchain slot 时，argv 才变为 guest `/bin/sh <固定wrapper路径> <原参数...>`；Linux guest 自带命令、Node 等原生可执行文件仍直接执行，参数继续按 argv 分隔，不拼接 shell 命令字符串。
- 新增 `CompatibilityCommandArgvTest` 两项回归；完整 Android `:app:testDebugUnitTest` 共 45 项、0 failures。此前全量 Flutter 145 项仍通过，Dart 源码未因本补丁变化。
- 修复后重新构建 release 并通过 APK verifier：`io.henry.codex` 1.0.0、5 个 ARM64 native assets 齐全、签名可验证；大小 116,229,787 bytes，SHA-256 `4728eecfbfaa2aa86c10b98c9bd6029b2c06d1da9bd5d53dd9741f3aa8e9f27b`。仍为本地 QA debug certificate。
- 曾尝试由 KernelSU ADB 上下文直接执行 guest `/usr/bin/true`，在 guest glibc 加载处因 `libc.so.6 ... Operation not permitted` 失败；这与真实 App UID 的 SELinux 域不同，不能判为 App PRoot 故障，也不能当成通过。其临时目录已删除并确认不存在。
- 真机 App PID `23322` 仍运行；未安装新 APK、未触碰活跃 Codex session。native npm/npx 的 App UID/PRoot 实际运行仍待 App 内验收。

## 2026-09-23 CC Pocket / app-server approval decision parity

- 按 CC Pocket 的批准卡片交互增加 Codex `acceptForSession` 操作；仅在 app-server 的 `availableDecisions` 明确提供时显示。旧协议未携带 choices 时，按当前 request family 的回退规则处理；JSON-RPC 客户端拒绝发送不受支持的选择。
- 支持服务端广告的 `acceptWithExecpolicyAmendment` 命令前缀规则和 `applyNetworkPolicyAmendment` 网络规则，按 JSON-RPC 结构原样回传；旧协议缺少 choices 时，仅从同一请求中的 proposed amendment 字段推导。
- Root execution identity 隐藏并在应用层拒绝整个 session/跨请求的持久批准规则；它不能绕过 per-write RootAccessPolicy 或 KernelSU 高风险路径。permission profile 仍可由显式用户操作选择 turn/session scope。
- 新增 UI、decision passthrough、未广告 session decision 拒绝及日/韩文按钮文案回归；最终全量 Flutter 测试 152 项通过。定向 Dart analyze 未发现 analyzer error，但仍有 35 条既有 warning/info，因此命令以非零状态结束。测试输出仍有无法下载 Google Fonts 的环境日志，未影响用例结果。
- 最新 release APK 通过只读 verifier：`io.henry.codex` 1.0.0、5 个 ARM64 PRoot/root-read native assets 齐全、签名验证通过；大小 116,276,179 bytes，SHA-256 `b426a03a1f95009e56205a8a746d395cbdb335d783f26e1088410ea5c740bcf2`。仍使用本地 debug certificate，不是商店签名。
- 本轮查询 `adb devices -l` 返回无在线设备；APK 未安装，审批 UI、CLI 更新和 KernelSU plugin 真机路径均未借主机测试冒充设备验收。
- 下一步继续完成 app-server request parity（优先 MCP elicitation/form），以及设备重新连接后的 PRoot/App UID npm install、CLI 更新/model refresh、KernelSU harmless plugin stage/apply/list/rollback 验收。

## 2026-09-23 MCP 表单与 CLI 命令交互续进

- 将 app-server `mcpServer/elicitation/request` 接入 CC Pocket 风格会话卡：支持常见 JSON Schema form 字段及约束校验、URL 显示/显式打开/二次继续确认；MCP 工具持久批准只显示服务端广告的 scope，Root session 隐藏持久批准。未知 schema、`openai/userVerification` 和未知 mode 只能拒绝/取消，不自动同意。
- URL 外跳由 Android `ACTION_VIEW` 处理，只接受 HTTPS 或 loopback HTTP，拒绝 userinfo/其他 scheme；启动外部页面和确认继续分成两个用户动作。
- `/cli` 参数现在以 argv tokenizer 处理单/双引号、空参数及有限反斜杠转义；不启动 shell，不做变量展开、管道、重定向或命令替换。未闭合引号在启动进程前给出会话内错误。
- 为避免一次性隔离 `CODEX_HOME` 让状态变更只写入临时 scope，登录/退出、CLI 更新、session 数据库操作、常驻 app-server 操作、MCP OAuth 以及 MCP/plugin 配置变更现改为明确转到应用 UI 或解释未接入，不再伪装为已完成；只读诊断仍由 CLI 运行。
- 连续 CLI 输入测试发现复用的 CC Pocket composer `AnimatedSwitcher` 为 Slash/Dedent child 重复使用固定 key；快速切回时触发 duplicate-key assertion。移除非必要固定 key，并将测试改为断言用户可见的 `/` 按钮。
- 验证：CLI argv/route 定向测试和会话交互测试 13 项通过；最终全量 Flutter 测试 162 项通过。日志中仍有 Google Fonts 在测试环境下载失败的提示，不影响用例结果。
- 最新源码重建的 Android release 已通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，5 个 ARM64 native assets 均存在，签名校验通过；116,504,895 bytes，SHA-256 `236f636e568f857bfac48dc69992b0d974fc7a7c7833795ad134725f53284e15`。仍为本地 QA debug certificate，不是商店签名。
- `adb devices -l` 当前没有在线设备；本 APK 未安装。MCP 外部 server/OAuth 返回、CLI updater/model refresh、KernelSU harmless plugin stage/apply/list/rollback 仍须设备验收。全量 CLI/TUI、MCP/plugin 管理 UI、设备端安全验证和 Android-native lock 限制仍未完成。

## 2026-09-23 SAF 标签与 release 模拟器复验

- 工作区历史和 CC Pocket 项目分组此前直接使用 SAF 编码 URI，首页会显示类似 `primary%3ACodex%2FWorkspaces%2F...` 的内部标识。现在仅归一化展示/分组路径；持久化路径和 resume identity 保持原值，避免破坏授权及会话恢复。
- 新增 SAF URI/文档 ID 解码单测和首页 widget 回归；验证显示名称为工作区末段，不再泄露编码 document ID。VM smoke 脚本加入编码 ID 拒绝条件，并检查首页、新会话页的关键交互入口。
- release VM 截图又发现中文首页的空会话摘要显示英文兜底；修复 CC Pocket session card 的首条消息空态分支，新增中文组件回归，截图现显示“（无描述）”。
- 全量 Flutter 测试 165 项通过。最终 release APK 通过 native asset/签名结构验证：116,507,175 bytes，SHA-256 `6ccb417ad64e3be1a8ab8880fbcc65a287e85101797e1693d83b6dddc47798ea`；包名 `io.henry.codex`，5 个 ARM64 native assets 齐全。签名仍是本地 Android debug certificate，不是 Play 商店发布签名。
- 最终 APK 安装并启动在 `codex_api35` Android 35 虚拟设备（ADB serial `emulator-5562`）：首页与会话页 UI smoke 均通过；首页截图确认卡片边距、可读工作区名和中文空态。结果与截图保存在 `C:\codex_ascii_build\tmp\codex-vm-smoke-20260923-localization-v4`。这不替代真机、真实 Codex turn、OAuth、native 工具链或 KernelSU 验收；当时主机只连着该模拟器，没有检测到实体设备。

## 2026-09-23 Android Root/PRoot instructions 注入

- 核对发现 Root policy 文档曾声称 runtime `AGENTS.md` 已注入，但代码和 APK 实际没有这份指令。现将 Android 操作规则作为 Markdown 内容保存在 `apps/codex/lib/core/application/android_codex_agents.dart`，每个新建及恢复的 Codex thread 都通过 app-server 的 `developerInstructions` 携带；不写入或覆盖用户工作区自己的 `AGENTS.md`。
- 规约覆盖 Root 全局读取但如实报告 OS/SELinux 拒绝、PRoot `uid=0` 不等于 Android root、低/中/高风险写入、逐项审批、KernelSU typed broker/健康检查/回滚，以及依赖只安装在选中的 PRoot guest，不提供任意 `su` 写系统区。
- 第一次通过 Flutter asset 异步读取规则，发现会延后 app-server 启动并使已有短时序会话测试出现竞态；现改成同步编译常量。会话客户端协议断言覆盖 `thread/start` 和 `thread/resume`，本地会话交互 5 项通过，全量 Flutter 测试 165 项通过。
- 当前 Codex app-server schema 明确包含 `developerInstructions`：[`thread.rs`](https://github.com/openai/codex/blob/main/codex-rs/app-server-protocol/src/protocol/v2/thread.rs)（start/resume 参数）。
- 最终 release APK 再次通过只读 APK verifier：116,509,751 bytes，SHA-256 `c1ee8189881833ce1fc9bbc29d3a624f619954f19ecfe1327483a785b74a59e6`，5 个 ARM64 native assets 齐全；签名为本地 Android debug certificate。协议行为由 Flutter fake app-server 测试验证，仍待 ARM64 真机真实 thread 验收。模拟器已关闭且 5562/5563 已释放。

## 2026-09-23 Codex CLI updater SemVer 修正

- 发现更新比较器只比较 `major.minor.patch`，会把同一基础版本的 prerelease（如 `0.156.1-beta.2`）误判为稳定版 `0.156.1` 已安装，可能跳过稳定版升级。
- 按 SemVer precedence 比较预发布标识（数字标识按数值顺序、稳定版高于预发布版），并忽略 build metadata；版本提取同时保留 prerelease/build metadata。
- 新增升级 prerelease→stable、prerelease 数字标识顺序、build metadata 等价及完整 CLI 输出提取回归。
- 定向 Flutter 测试 `test/codex_cli_updater_test.dart`：7 项通过；对更新器与对应测试执行定向 Dart analyze，0 issues。
- 同一源码的全量 Flutter 测试通过，共 167 项。
- release 首次失败的根因是旧 `flutter_build.d` 含已不存在的 `Y:` 映射盘输出路径；仅执行 `:app:clean` 后 ARM64 release 重建成功。APK verifier 通过：`io.henry.codex` 1.0.0、5 个 ARM64 PRoot/root-read assets 齐全、签名有效；97,782,013 bytes，SHA-256 `4fee5a63bdf1faaef69107361af9bc7b7b34c5257ed5d4e6b0dd127b448ef95a`，签名仍为本地 QA debug certificate。
- 当前没有在线实体设备；本项尚未进行设备端更新/模型目录验收。现有 `codex_api35` AVD 为 x86_64，不能安装本 ARM64-only APK；真机接入后仍需执行更新及 GPT-6 模型刷新验收。

## 2026-09-23 Codex thread 自动命名接入

- 接入 app-server `thread/name/updated` 通知：仅接受当前 session 的 `threadId`，过滤空标题及其他并发 thread 的通知；将 Codex 生成的名称展示在会话页和首页 session 卡片。
- 会话历史分开保存本地首条 prompt 兜底标题、Codex thread name 和手动改名标记；Codex 自动标题不会覆盖用户手动命名。旧版历史记录依据已有标题与首条 prompt 的差异尽量识别为手动标题。手动改名还会通过官方 `thread/name/set` 同步至当前 Codex thread；RPC 失败仍保留本地名称并提示。
- Flutter 定向会话/历史测试通过；新增 app-server 通知、当前会话 UI 更新、上下文用量环 80% 显示、手动改名 RPC、不为改名隐式启动空 thread、旧记录兼容和 Kotlin 原生存储 round-trip 回归。最终全量 Flutter 测试 171 项通过，`SessionHistoryStoreTest` 通过。
- 定向 Dart analyze 没有 error，但该分析范围报告 27 条既有 warning/info（集中在 `main.dart` 的其他位置、既有 API 风格提示）；本次自动命名代码本身未报告问题。
- ARM64 release 已按最终源码重建并通过 APK verifier：`io.henry.codex` 1.0.0，5 个必需 native assets 齐全；97,785,121 bytes，SHA-256 `e585abc6207e58abb925f2ab59633e800f58bb1cba4ced6a13f5d07977ac0386`。签名仍为本地 QA debug certificate。
- 真机 `6cb21282` 已连接；只读检查发现 `SessionForegroundService` 正在运行且伴随 `libcodex.so` 子进程，覆盖安装会中断现有 session，因此未安装新包。Codex 真正生成/重命名通知及持久化后重进会话的设备端验收仍待该 session 安全结束后进行。

## 2026-09-23 Root app-server 审批策略补齐

- 对照当前随包 Codex CLI 0.154.0 的 app-server 协议与执行策略，确认 Root session 不能使用 `danger-full-access + on-request`：该组合会让未匹配危险规则的命令直接执行。Root 的 thread start/resume 和每次 turn 现在固定使用 `approvalPolicy=untrusted`；普通 App UID 继续遵循用户选定的策略。
- `item/permissions/requestApproval` 现在按 legacy `fileSystem.write` 与 typed `fileSystem.entries` 分类；workspace/tmp 的低风险 scope 可直接通过，未知或 workspace 外 scope 仍需逐次确认，system/vendor/boot 只允许进入已验证的 KernelSU plugin 路径，raw block 和全盘写 scope 拒绝。显式只读诊断命令（含 grep/rg）可直接执行，但带 shell 运算符或 `rg --pre` 的命令不走该快速路径；任意解释器/非只读命令若提及 system、boot、raw block 或 KernelSU 目标，也不允许按普通命令审批绕过插件路由。
- Root 风险分类和 Root session app-server policy 定向 Flutter 测试共 28 项通过，覆盖 Python 解释器形式的 system/raw-block 写入预检、grep/rg 全局只读路径，以及 `rg --pre` 不走只读快速路径。Root 策略与测试文件定向 analyze 无问题；会话客户端另有 8 条既有 lint/info。
- 风险判断是应用层预检，不是内核沙箱；Codex sandbox policy 尚未接入兼容执行器，PRoot/root 执行仍没有独立于 app-server 的强制写隔离，不能据此宣称任意命令具备 OS 级安全边界。
- 真机 `6cb21282` 当前可见，`io.henry.codex` 的 `SessionForegroundService` 仍在前台运行（PID 23322）。为避免覆盖安装打断活跃 session，本轮未安装候选包；Root 审批新行为的真机验收需在该 session 结束后进行。
- 最新 ARM64 release 候选包已构建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：包名 `io.henry.codex`、5 个 ARM64 PRoot/root-read assets 齐全、签名有效；大小 97,787,105 bytes，SHA-256 `002cdb8bafe960df3b1a90b051f42fba23a901d39714b15cd33c473c44b65be6`。它使用本地 QA Android debug certificate，不是商店发布签名；尚未安装。

## 2026-09-23 真机 KernelSU 只读能力复核

- 实体设备 `6cb21282` 报告 Android 16 / API 36 / `aarch64`。ADB shell 实际身份是 `uid=0(root)`、SELinux `u:r:ksu:s0`；这只证明 ADB 侧 KernelSU 权限，不等于 `io.henry.codex` app UID 或 app broker 获得同样能力。
- 固定入口 `/data/adb/ksu/bin/ksud` 存在并指向 `/data/adb/ksud`；只读 `--version` 返回 `ksud 3.3.0 (uapi: 2)`，`module --help` 和 `module list` 均可正常返回。没有 stage/apply/enable/disable/uninstall 操作，也没有改写或删除设备模块。
- 设备的 Codex `SessionForegroundService` 仍以 PID 23322 运行，Codex Activity 在后台；没有启动 Codex UI、替换 APK 或打断活跃 session。设备 broker stage/apply/list/rollback 仍需后续通过应用自身的 KernelSU 插件界面验收。

## 2026-09-23 Root 写策略路径穿越回归与设备强制边界

- Root 路径分类原先只折叠重复斜杠，没有解析 `.`/`..`；因此 workspace/tmp 前缀内的路径可能在归一化后逃逸到 `/system`、`/dev/block` 或 KernelSU 模块目录。现已在 Dart classifier 中先做词法 canonicalization，保留大小写，并让低风险 workspace 匹配实际 Android `Codex/Workspaces` 根的精确大小写；未解析的相对 `..` 和 NUL 输入不会匹配低风险根。
- 新增 traversal、大小写伪装、permission-scope 逃逸回归；`test/root_access_policy_test.dart` 9 项通过，定向 `dart analyze` 0 issues。
- 设置页 Root 身份与权限说明现在明确显示 UID 0、应用层审批和缺少内核写隔离；新增 UI 回归。路径与设置安全测试合计 10 项通过。定向 analyzer 在策略文件无问题；设置文件另报 1 条既有 unused `_CodexUsageCard` warning。
- 按当前源码重建 ARM64 release，并通过 APK verifier：`io.henry.codex` 1.0.0、5 个 ARM64 native assets 齐全、签名校验通过；116,529,375 bytes，SHA-256 `5786f76ec55ae1f683c19cec11c360c6237bf465611bc79a07fbeef859067001`。签名仍是本地 QA debug certificate，候选包尚未安装。
- 连接真机 `6cb21282` 只读检查：Android 16，kernel `6.1.138-android14-11-g965475777129-mi`；`/proc/config.gz` 显示 `CONFIG_SECURITY_LANDLOCK is not set`。活动 Codex `libcodex.so` 进程 UID 0，有 `CAP_DAC_OVERRIDE`，`NoNewPrivs=0`、`Seccomp=0`。这证明当前显式 native Root session 仍缺少内核写隔离，应用层路径分类不能声称是安全强制边界。
- 另确认高风险目标目前在普通审批卡片中被拒绝，并不会自动生成或派发 KernelSU plugin 操作；Settings 的手动插件导入是另一条流程。Root policy 文档已修正这两个事实，并明确 symlink/TOCTOU 仍未解决。
- 最近一次成功读取时，SessionForegroundService PID 23322 仍活跃且 Codex Activity 在后台；随后 ADB 设备列表变为空，当前设备/进程状态未知。未打开应用、安装包或重启 ADB 服务；设备上的新代码验收仍待连接恢复且 session 可安全结束后执行。
- 尝试继续读取 `su -c` 启动 shell 的 capability 时，ADB 传输已断开，未取得该项证据。下一项仍是基于设备实际 KSU capabilities/SELinux 约束验证 Android-native 的降权或特权 broker 边界；只有低风险写、全局读取与高风险拒绝均能以设备实测证明，才可收窄此项限制。若设备无法提供满足要求的内核边界，需通过架构调整让 Codex 主进程不以 UID 0 运行，而不是继续依赖命令字符串扫描。

## 2026-09-23 Android 文件锁兼容性统一修复

- 确认 Android 上 `std::fs::File::{lock, try_lock, try_lock_shared}` 会出现不支持错误，问题不只在 rollout writer lock。新增 `codex-utils-file-lock`：Android 统一走 Bionic `flock`，其他平台继续使用 Rust 标准库文件锁，并统一把竞争状态映射为 `WouldBlock`。
- 已迁移 Codex arg0 临时目录/janitor、message history、gateway credential、managed CA lease、rollout writer/maintenance、MCP OAuth store/refresh、user-verification lifecycle 等生产文件锁调用点；rollout 旧的直接 `libc` 依赖已移除。
- 宿主机与 `aarch64-linux-android` 的 8 个受影响 crate `cargo check --locked` 均通过。文件锁 helper 在宿主机 5/5 通过；Android ARM64 独立测试程序在已连接真机上验证独占竞争、共享锁互斥、关闭文件释放，以及由独立子进程持锁时父进程确实收到 `WouldBlock`，5/5 通过。宿主机相关测试另覆盖 gateway auth、MCP OAuth、rollout 与 user-verification 锁路径；arg0 janitor 3 项和 message-history 12 项也通过。
- 真机 App `io.henry.codex` PID `23322` 仍在运行；release 包不可 `run-as`，且存在活跃 Codex session。没有替换 APK/runtime 或打断会话。因此本次证明的是 Bionic 文件锁原语和 Android target 编译，不是新 Codex binary 下多个 app-server/session 的端到端并发验收。
- 风险记录：本轮首次 helper 测试曾在未加 `--locked` 时触发 Cargo 更新已处于 dirty 状态的 `Cargo.lock`；此后的宿主机/Android 检查与相关测试均使用 `--locked` 并通过。当前锁文件相对 HEAD 仍含 17 行新增、364 行删除；由于本轮开始前就有 Cargo.lock 修改，提交前需单独复核该锁文件差异，不要用仓库版本覆盖。
- 下一步继续处理尚未闭环的应用 UID/PRoot 工具链与 Codex app-server 真机集成验收；只有在现有 session 安全结束后才安装包含此修复的新 runtime。

## 2026-09-23 Phase 1 session/settings UI 回归

- 会话权限栏原先把 `sandbox=read-only` 映射成 CC Pocket 的 `custom` 并显示“自定义”；独立 Codex mode bar 现按只读 sandbox 显示“只读”，不改共享 CC Pocket 包或协议。中文设置诊断中的 runtime 缺失原因、Codex home 和 App UID 探测状态也在 UI 层本地化，保留 native 返回值。
- `tools/build-android.ps1` 保留 `--no-tree-shake-icons`：CC Pocket 组件的部分 IconData 经包适配器间接引用，release 字体 tree-shaking 会将图标裁掉并显示缺字方框。
- Settings widget 回归现在实际点选并检查推理档位、审批策略、沙盒、主题、语言回调及状态；另测试 Android preferences MethodChannel 的主题/语言读写和无效值归一化。三个定向测试文件 19 项通过，完整 Flutter suite 181/181 通过。定向 `dart analyze` 无 error，但因既有未引用的 `_CodexUsageCard` warning 退出码为 1；更广分析另报告既有 null-aware 风格和旧 Radio API info，本次新增代码未出现诊断。
- 当前源码 release APK 通过 verifier：`io.henry.codex` 1.0.0，117,077,171 bytes，SHA-256 `a28b5bef65c4d5f4b6dfa596cc47dda61ffbb2ad7126dc32fac96cf06e525e7e`；5 个 ARM64 Codex native assets 全部存在，签名为本地 QA debug certificate。
- API 35 x86_64 `emulator-5580` 安装该 APK 后，Home 必需文案、workspace data、session 打开及 mode controls smoke 均通过；交互截图确认计划模式可开启、只读选择后 mode bar 显示“只读”，设置页 runtime 缺失诊断已本地化。截图与 hierarchy 位于 `tmp/phase1-ui-20260923-final/`（构建检查可经 `C:\codex_ascii_build\tmp\phase1-ui-20260923-final\` 访问）。
- 设备 `6cb21282` 只读确认 `io.henry.codex` PID `23322` 及 `SessionForegroundService` 仍活跃；未安装、停止或切换真机 App。故本轮只验证 Emulator UI，不代表真机 parity、真实 Codex turn 或 Phase 1 全合同已通过；Phase 1 继续冻结。

## 2026-09-23 多 Session 隐藏期间流式回归

- 扩充 `local_session_conversation_test.dart` 的多会话测试：第一条真实处于 turn-running 状态的 session 切回 Home 并打开第二条后，仍持续接收并保留 assistant streaming delta；同时断言两条 app-server process 均未停止。该测试覆盖“只检查旧进程尚存、未检查隐藏会话实际继续更新”的原有盲点。
- 定向测试文件 5/5 通过。测试模拟的是 app-server JSON-RPC 事件与独立 process owner，不替代 Android 真机上的双 Codex turn E2E。
- 真机 `6cb21282` 已重新在线；只读查询显示 `io.henry.codex` PID `23322` 的 `SessionForegroundService` 仍运行，当前前台应用是微信。未导航、停止服务或覆盖安装；真机 parity / 新版双 session 验收等当前 session 安全结束后再执行。
- Phase 1 仍未通过：本次强化了自动化回归，但没有声称真机通过，也没有进入 Phase 2 runtime 重构。

## 2026-09-23 中文登录诊断与当前 release VM 复验

- 当前 AVD 截图发现设置登录卡将 Android native 缺失错误直接展示为英文。`CcpocketNativeAuthCard` 现在通过本地 auth 文案适配器转换该已知 runtime 错误；新增中文 widget 回归。多 Session 隐藏期间 streaming delta 回归也保留。
- `local_session_auth_test.dart` 与 `local_session_conversation_test.dart` 合计 9/9 通过。测试运行时仍有既有 google_fonts 下载失败日志，但不影响测试结果。
- ARM64 release 重建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：117,077,407 bytes，SHA-256 `d7c57d9ae5df91c6ec8e69c7be14c0bfc97559eafa14b46f42b4aa87ec26d99d`；5 个 native assets 齐全，签名可验证但仍是本机 Android debug certificate。
- 将候选 APK 安装到 `codex_api35` AVD 后，Home / session 标签 smoke 通过；实际点开 Plan、权限菜单并选择只读，状态在 mode bar 更新；从 session 返回 Home、进入 Settings 的路径也通过。Settings UIAutomator 树确认英文 missing-runtime 错误已消失并显示中文文案。截图与层级位于 `tmp/phase1-ui-20260923-session-switch/`。
- 真机仍为 `6cb21282`；当时 Codex 前台服务 PID `23322` 继续运行且当前前台为微信。没有导航、停止服务或覆盖安装；本轮所有 UI 操作只发生在 AVD。AVD 随后正常关闭，端口 `5580/5581` 已登记释放且无 LISTEN。真机新包与双 session E2E 仍待现有 session 安全结束。

## 2026-09-23 Phase 1 连续输入、停止、重试与错误本地化

- 扩充 composer 回归：slash 命令、`@` 插入、缩进、提示历史选择均可操作；新增两条连续输入的队列测试，确认第二条等待第一条 turn 中断事件后按序发送，点击停止会向同一 thread 发出 `turn/interrupt`。
- 新增 provider 网络失败 Retry 回归：重试复用原 thread，不新建 thread；中文界面中的网络错误 transcript 与 Retry banner 已本地化为中文。真机无中断时本地化仅通过 widget/AVD 验证。
- `local_session_auth_test.dart` + `local_session_conversation_test.dart` 定向套件 12/12 通过。测试进程仍打印既有 Google Fonts 下载失败日志，但测试结果通过。定向 Dart 分析没有 error；`main.dart` 仍有未清理的既有 warnings/infos。Flutter `analyze` 包装命令本轮因 analysis server 收到截断的 LSP JSON 而崩溃，未把该工具异常记为代码通过。
- 重新构建 ARM64 release 并通过 APK verifier：117,070,895 bytes，SHA-256 `3ddcbef1b270e272bacf79d4616dad74d821e0d926336c7fc8847e82b1bb33a2`；5 个 native assets 齐全，签名为本机 Android debug certificate。
- API 35 `codex_api35` 安装上述 APK，Home / Session smoke 全部必需标签存在，session composer/控制栏可见。截图与 hierarchy 在 `tmp/phase1-ui-20260923-retry-localization/`；这不等同于真实 Codex turn、OAuth 或 approval/diff 真机验收。
- AVD 使用的 TCP 5580/5581 已按登记表预留、启动后记 active，并在关闭后确认无 LISTEN，最终标记 released。实体设备 `6cb21282` 的 `SessionForegroundService` PID `23322` 仍运行；没有安装、停止或导航真机，避免中断现有会话。
- Phase 1 仍未通过，Phase 2/3 尚未开始；下一步继续核对剩余 session 生命周期/无障碍验收缺口，等真机现有 session 安全结束后再安装并做双 session 本地回归。

## 2026-09-24 Phase 1 首页筛选、冷启动恢复与真机 UI 回归

- 修复 Home 适配器先前只把搜索/项目/已命名筛选状态传给 CC Pocket、却没有在本地过滤结果的缺陷；保留 CC Pocket 原有控件与分组/列表切换，新增可交互回归覆盖搜索、关闭搜索后恢复全部结果、项目筛选、仅已命名和分组/列表模式。
- 增加 app-private history 冷恢复 widget 集成测试：从 session-history channel 恢复稳定 session/thread identity、transcript 摘要、draft、queued prompt、prompt history、模型/effort/sandbox/plan；确认同一 thread 自动 resume、排队 prompt 恢复后投递一次，编辑 draft 后仍写回原 session。
- 首页、登录/root session、conversation、CC Pocket message/approval/diff 与 shell/navigation 共 5 个定向测试文件共 32/32 通过；`dart analyze lib/ccpocket_native_home.dart test/local_session_conversation_test.dart` 无诊断。测试输出仍有既有 `google_fonts` 网络下载失败日志，不影响通过结果。
- release APK 仍为本轮 UI 修复对应构建：`io.henry.codex` 1.0.0，117,088,667 bytes，SHA-256 `e522b7484918f06dbbc72557261ba97c915801661d5fd6e86e8d2b6d50920318`；APK verifier 已确认 5 个 ARM64 native assets 齐全、签名可验证但使用本机 QA debug certificate。API 35 AVD Home/Session smoke 通过，截图与层级在 `tmp/phase1-ui-20260924-home-filters/`。
- 真机 `6cb21282` 在确认没有 Codex/PRoot 子进程或 session foreground service 后，以 `adb install -r` 覆盖安装该 APK，应用数据保留。Home 的中文分区、workspace/session 卡、用量摘要和筛选控件存在；卡片范围 `[42,1398]` / 屏幕宽 1440，左右留白一致。Settings 可正常进入 Codex login/runtime 页面且没有 Root approval 弹窗；返回 Home 后未启动 Codex 子进程。真机 Home 截图及 UI hierarchy 在 `tmp/phase1-ui-20260924-phone/`。
- 真机搜索框在 IME surface 尚未就绪时拒收了第一次 ADB 文本注入；等待键盘实际显示后输入 `Python` 成功，列表精确缩至包含该词的会话。搜索关闭后 Home 只剩一个最近会话卡，而初始真机截图曾显示多个历史项；无法仅凭当前 hierarchy 判断这是当时会话索引/筛选状态还是清空路径问题。Home widget 回归现已明确断言清除查询后 alpha/beta 两组结果都恢复并通过；真机多历史完整恢复仍需用可确认的本地数据复测。本轮没有打开 session 或发送 prompt；应用留在 Home，PID `28966` 仅为 UI 进程。
- AVD PID `27136` 已关闭，端口 `5580/5581` 已确认无 LISTEN 并在共享端口表登记释放。Phase 1 仍未通过；本轮未宣布真机 session 恢复、搜索输入或真实 turn 验收通过，继续按 `PHASE_1_UI_FREEZE.md` 补足剩余 UI/session 验收。

## 2026-09-24 首页键盘避让与空状态边距

- 修复 Home 搜索键盘弹出后外层“新建”FAB 遮挡 CC Pocket 筛选栏：键盘 inset 非零时隐藏 FAB，键盘收起后恢复；新增 widget 回归覆盖显隐往返。另修复“没有最近会话”的 Home 分支未带横向 padding、工作区卡片贴屏幕边缘的问题，空状态改为与有历史列表相同的 12dp 左右留白，并新增卡片 bounds 回归。
- 五个定向测试文件共 33/33 通过；相关 UI/home 测试、适配器 Dart analyze 无诊断。Flutter 测试仍打印已有 `google_fonts` 网络字体拉取失败日志，但测试通过。
- ARM64 release APK 通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：117,055,271 bytes，SHA-256 `c222d7645cbfffc6c53c87a3ea8b4d4fcbae95d5a8d804a351909488dcbbcd6d`；5 个 native assets 齐全、签名可验证（本机 QA Android debug certificate，非商店签名）。该版本已通过 `adb install -r` 安装至真机 `6cb21282`，保留既有应用数据；冷启动 Home 成功，空状态工作区卡片实测两侧留白，截图为 `tmp/phase1-ui-20260924-phone/verified-home.png`。
- 当前真机本地有工作区但没有 Recent Sessions，因此 Home 不显示搜索入口；本轮没有新建测试 session 或发送 prompt。上一次有历史数据时曾输入 `Python` 并筛选成功；关闭搜索后历史数量曾不一致的疑点仍待可确认的多历史数据复核。键盘/FAB 逻辑由 widget inset 回归验证，但本次无法在真机历史列表上做修复后视觉复验。未留下 Codex/app-server/PRoot 子进程，仅 App UI 进程运行。
- Phase 1 继续未通过；不能以本轮空状态启动截图或 widget 通过代替真实 session、冷恢复、审批/diff 与无障碍合同验收。

## 2026-09-24 首页触控尺寸与设置页本地化真机回归

- Home 的设置、刷新、添加、项目筛选/切换等小图标操作目标统一提高到至少 48dp；调整 app bar 内边距，使设置操作在不增高工具栏的前提下达到 48dp。主要入口的无障碍节点与尺寸有回归覆盖；键盘出现时 Home 新建 FAB 隐藏、键盘收起后恢复由 widget 测试覆盖。
- 将当前 Settings 运行环境、更新策略、Android 原生工具链、工作区存储和运行时诊断中面向中文用户的混合英文说明本地化；登录错误适配同步为“应用或 Root 运行时目录中均未安装 Codex 运行环境。”；真机发现的 `App UID 可用` 也改为“应用 UID 可用”。
- 七个定向 Flutter 测试文件共 40/40 通过，覆盖 Home/导航、设置与模型目录、登录/root session、会话交互和冷恢复。定向 Dart analyze 退出码为 0（9 条 info，无 error）；包含 `main.dart` 的宽范围 analyze 另外报告 warnings/infos，未在本切片扩展清理。
- ARM64 release 构建成功并通过 APK verifier：`io.henry.codex` 1.0.0，117,055,007 bytes，SHA-256 `d9599f28b6eaa62b3c187b3d0e835a7156679cc215e342cd5a0a039f4ab84db0`；5 个 ARM64 Codex native assets 齐全，签名有效但使用本机 Android debug certificate。
- 在没有活跃 Codex turn 时以 `adb install -r` 安装到真机 `6cb21282`，保留应用数据。Home hierarchy 实测屏幕宽 1440px、workspace 卡片边界 `[42,1398]`（左右各 12dp）；设置、刷新、工作区菜单触控框为 48dp，添加工作区按钮为 78×48dp。设置页实际显示“Codex 运行环境”、Android 原生优先策略、工作区存储和 `Codex 登录 / 状态：已登录`，浏览器 OAuth 选项仍为选中状态，未弹 Root approval。这里只验证已保存登录状态可展示，不代表重新执行 OAuth 登录成功。
- 最新真机截图：Home `tmp/phase1-ui-20260924-phone/03-home-after-localized-release.png`、设置 `tmp/phase1-ui-20260924-phone/05-settings-localized.png`；设置 hierarchy `tmp/phase1-ui-20260924-phone/05-settings-localized.xml`。设置页短暂挂载登录面板时出现 `libcodex.so`；返回 Home 后只观察到 App UI 进程。未发送 prompt、未执行 OAuth 流程或触发 turn。
- 最终候选包在真机创建空白会话后显示会话专属空态“开始对话 / 输入消息，即可开始这个 Codex 会话”，没有显示登录或 Root approval；额度条、模型、计划/权限 chip、composer 均在会话内。composer 获得焦点后 Android IME 正常弹出并把输入区上推（UI hierarchy 确认 `mInputShown=true`）。本轮没有输入或发送 prompt，没有 Codex/runtime 子进程。空会话退出时 App 生成了一条 `test-project / （无描述）` 临时历史，本轮按会话菜单删除了该项；Home hierarchy 确认工作区保留、Recent Sessions 为空。截图为 `tmp/phase1-ui-20260924-phone/07-empty-session.png`、`08-session-keyboard.png`，清理后 Home `12-home-after-cleanup.png`。
- 真机会话控制回归：Plan chip 从“计划关闭”切到“计划开启”后再恢复；权限菜单可选择“只读”和“完全访问”，两种状态均更新可见 chip，再恢复“默认”。未发起 turn 或工具调用；由这些选择生成的第二条空历史也已删除，当前仅保留原工作区，Home Recent Sessions 为空。选项层级记录在 `tmp/phase1-ui-20260924-phone/13-session-controls.xml` 与 `14-permission-menu.xml`。这些结果只验证设置交互，不证明权限已经通过真实 turn 应用到 CLI。
- 当前真机只有一个本地工作区，没有 Recent Sessions，因此搜索入口未显示；真实键盘/FAB 修复无法在有历史列表时做设备级视觉复验。Approval/diff 完整 UI、旧 session 自动 resume 和真机真实 turn 仍未完成，本轮不宣布 Phase 1 通过。

## 2026-09-24 真机 Codex turn、session 恢复与系统提示去重

- 真机 `6cb21282` 在 Android 16 上完成本地 session 冷恢复：草稿 `phase1_resume_draft_test` 在返回 Home、强制结束 App UI 进程、重新启动并打开同一 session 后仍完整保留。测试草稿记录已删除，workspace 保留。
- 在临时 session 以 `gpt-5.6-luna · low` 发送真实 Codex turn（要求准确回复 `PHASE1_DEVICE_SMOKE_OK`）；最终回复完全匹配，session 状态回到“就绪”。真机显示账号用量、`in 12.3k / out 11` 上下文计数和完整回复。没有单独捕获中间 token delta，因此这里只确认真实 turn/最终回复，不声称已验收流式增量。
- 打开该真实 session 时发现旧历史含 3 条重复的中文可选 MCP 网络提示。修复历史恢复时对英文及已本地化提示统一识别并折叠为一条，同时标记提示已存在以阻止 resume 再追加；会话恢复回归以重复中文历史和新的 MCP stderr 事件覆盖此路径。
- 定向 Flutter 测试：会话交互/恢复 9 项、系统提示 2 项、额度摘要 1 项，共 12/12 通过；这 3 个测试文件 `dart analyze` 无问题。包含整个 `lib/main.dart` 的宽范围 analyze 仍以既有 warnings/info 退出非零（11 warnings、7 infos；未在本切片扩展清理）。Flutter 测试可能打印 `google_fonts` 字体网络拉取失败日志，不影响上述测试通过结果。
- 最新 ARM64 release APK 通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，117,067,943 bytes，SHA-256 `f0f571b29c748d025703af074ec67c057dacd15d96f2260908ea8cbda3dd7ff6`；要求的 5 个 ARM64 Codex native assets 全部存在。APK 已覆盖安装到真机且保留应用数据；证书为本机 Android debug QA certificate，不是商店签名。
- 真机复开原 session 后，旧 transcript、真实最终回复、上下文计数与账号用量仍存在；MCP 与 Code Mode 提示各一条，中文提示均完整显示。截图/hierarchy：`tmp/phase1-ui-20260924-phone/44-after-resume-latest.png`、`44-after-resume-latest.xml`。
- 验证完成后显式停止处于空闲“就绪”状态的测试 session，再从 Home 删除测试历史；最终 Home hierarchy 确认 `test-project` workspace 保留、测试 session 与 Recent Sessions 消失，设备上没有 `libcodex.so` 子进程（仅 App UI 进程）。最终 Home 截图：`tmp/phase1-ui-20260924-phone/56-home-clean.png`。
- Phase 1 仍未通过：AVD 上完整 approval/diff flow、session 关键操作的可访问性/触控审计，以及真实 turn 的中间流式增量仍需验收；本次没有开始 Phase 2 runtime 重构。

## 2026-09-24 Session 自动标题协议修复与真机复验

- 自动标题由首条 user prompt 驱动独立 ephemeral thread 生成，再通过 `thread/name/set` 写入原 Codex thread；不在可见 transcript 增加消息。标题请求强制 Luna/low、工具和继承 MCP 全关，用户手动重命名时取消待处理生成。
- 真机初次没有更新标题的根因是 `thread/start.threadSource` 发成对象；app-server schema 要求字符串。改为 `"system"` 后，Codex Session Client、title 和本地 conversation 三个定向测试合计 36/36 通过。
- release APK verifier 通过：`io.henry.codex` 1.0.0，117,096,875 bytes，SHA-256 `e727e98554403c5c21877f970b2d43ee80dd67035bca081809bcb3c0b3f96bd1`，5 个 ARM64 assets 存在；证书为本地 QA debug certificate。安装到 Android 16 真机 `6cb21282` 后，以 `5.6 Luna · 低` 完成真实 turn，Home 显示语义标题“Explain Android free storage”，原对话历史保留，标题 thread 未显示为对话消息，状态恢复就绪。
- `tools/build-android.ps1` 增加 Flutter release depfile 临时盘符陈旧引用的定点恢复，修复后 release 构建成功。验收后停止并删除测试 session，保留 `test-project` workspace，真机没有遗留 Codex 子进程。设备证据：`tmp/phase1-title-20260924-phone/title-success-home.xml`、`title-success.png`、`home-clean.png`。
- 覆盖此前“自动语义标题尚未实现”的历史结论：该项现已实现并在真机验证。Phase 1 仍未通过，session 次级菜单/approval/diff 控件的可访问性和动作反馈审计仍在进行；未进入 Phase 2。

## 2026-09-24 真机流式、Session 搜索与消息操作无障碍续验

- 真机 `6cb21282` 使用 `gpt-5.6-luna · low` 完成约 1,200 词的真实 Codex turn。发送约 1.2 秒时截图显示状态“运行中”、assistant 正文已出现且停止按钮可用；最终状态回到“就绪”，完整回复含精确结束标记 `STREAM_DELTA_ACCEPTED`。结果计时约 40 秒，界面显示 `in 41.9k (12.0k) / out 1.7k`、上下文 11%。中途与最终证据分别为 `tmp/phase1-ui-20260924-phone/65-realturn-stream-mid.png` 和 `66-realturn-stream-final.png`。
- 真机可访问性树发现 CC Pocket 原始消息操作栏的复制/纯文本/分享按钮仅约 30dp 且没有语义名。`packages/ccpocket_ui/lib/widgets/bubbles/message_action_bar.dart` 保留原视觉图标，把点击区域提升到 48×48dp，并添加英文、中文、日文、韩文 Tooltip/Semantics；可选分叉按钮也同样处理。新增 widget 回归后，`ccpocket_native_session_test.dart` 定向测试 16/16 通过。
- 新 ARM64 release 构建成功并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，117,072,259 bytes，SHA-256 `3d44f4f1eb622706b6dafd6012230ba908b1b1093dea6915bc5a44616d7aca5c`；5 个 ARM64 native assets 齐全，签名是本机 QA Android debug certificate。APK 覆盖安装到真机时没有运行中的 Codex 子进程，应用数据保留。
- 新版真机真实回复 `UI_ACTIONS_READY` 后，Android accessibility tree 中“复制 / 显示纯文本 / 分享”均为 168×168 px；设备密度 560 dpi，换算为 48×48dp。截图/hierarchy 为 `tmp/phase1-ui-20260924-phone/69-message-actions-accessibility.png`、`69-message-actions-accessibility.xml`。测试 prompt 经 ADB 文本输入时夹带了字面 `%` 转义错误，但 Codex 未调用工具或改文件，回复标记正确；该临时 session 已停止并删除。
- 在当前 release 上以仅含本地草稿的临时 session 验证 Home 有历史时的搜索：搜索 `no-match-xyz` 后历史卡隐藏并显示空状态；IME 弹出期间 Home“新建”FAB 隐藏，收起 IME 后 FAB 恢复；关闭搜索后原会话卡完整恢复。该临时 session 随即删除；`test-project` 工作区保留，Home Recent Sessions 为空，设备无 `libcodex.so` 子进程。证据：`tmp/phase1-ui-20260924-phone/71-home-search-restored.png`、`72-home-search-no-match-keyboard.png`、`73-home-search-empty-state.xml`、`74-home-search-restored.xml`、`75-home-clean-after-search-test.png`。
- Session 命名仍有明确限制：真实 turn 后设备标题仍是首条用户 prompt 的截断文本。当前本地 `generatedTitle` 从第一条用户输入取 36 个字符，不取最新 assistant 回复；app 仅监听 `thread/name/updated`，真实设备此次未观察到该通知，也没有发现独立的语义摘要生成请求。因此“不会把最新 Codex 回复当标题”已由实现和真机确认，但“自动生成语义化简介名”尚未实现/验证，需继续收敛命名策略。
- Phase 1 继续未通过；本轮没有启动 Phase 2。

## 2026-09-24 Phase 1 delete-only 收尾与冻结

- 独立 App 不再写入归档状态；CC Pocket Recent Session 的滑动 action 已从内部
  `onArchiveSession` 改为明确的 `onDeleteSession`，处理态同步改名为 deleting，并增加
  中文/英文/日文/韩文无障碍标签。旧 Android 历史仓库仍负责读取时删除旧版本残留的
  archived row，避免恢复归档会话列表。
- 新增真实 widget 路径回归：滑动 session card 后出现“删除会话”语义按钮，点击会把同一
  session 交给删除回调；同 workspace 双 session 互相独立测试保留。相关 Flutter 测试
  21/21 通过，改动范围内 Dart analyzer 无诊断。
- Android `SessionHistoryStoreTest` 全套和 App Android JVM 单测均通过（46 tests）；测试
  还断言新记录不保存 archive 标志、legacy archived row 在读取索引时被删除。
- ARM64 release APK 成功构建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：
  `apps/codex/build/app/outputs/flutter-apk/app-release.apk`，117,112,787 bytes，SHA-256
  `d537b2147e330092f01ca019b3a3a5b5fc2de5089f77427b975c3a7a9f4f53e6`；5 个 ARM64 native
  assets 齐全，签名为本机 Android debug certificate（非商店签名）。已覆盖安装到真机
  `6cb21282` 并保留 App 数据；冷启动首页仍显示 `/storage/emulated/0/Codex/Workspaces/test-project`，
  未显示归档会话区。设备 hierarchy/screenshot：
  `tmp/phase1-title-20260924-phone/phase1-final-release-home.xml`、`.png`。冷启动后的短暂
  `libcodex.so` 子进程自行退出；最终仅 UI 进程，没有 Codex/PRoot session 子进程。
- 结合此前已记录的真机中间流式增量、真实 Codex turn、session 冷恢复、模型/额度显示、
  两 session 独立历史、首页有历史时搜索恢复、工作区创建/删除确认，以及 API 35 AVD 的
  approval/diff、Settings、composer smoke，Phase 1 退出合同现已满足。

**Phase 1：Frozen / Passed。Phase 2：Active — Android-native-first runtime。**
本轮开始以真实 App UID 工具发现/调用链为第一个切片；不引入 Bridge，不更改已冻结的
session ownership contract。

## 2026-09-24 slash command 即时反馈真机回归

- 定位并修复本地 transcript 只落盘、不触发 conversation 重建的问题；`/status`、本地
  CLI 输出、状态和错误共用该追加入口。Flutter 会话交互测试 10/10 通过。
- Release SHA-256：`3270abe19f64a3e213ad4a46ff17666e82373ae5007c2ef2a136ccc7d898c749`；
  verifier 通过且 5 个 ARM64 native assets 齐全。真机覆盖安装后再次发送 `/status`，新
  状态 chip 立即可见；没有模型请求或 Codex/PRoot 子进程。只删除临时测试 session，保留
  `test-project` workspace。
- Phase 1 slash-command 条件已补齐，维持 Frozen / Passed；Phase 2 仍 active，下一步
  在真实 App UID 下逐一核验 Native Toolchain 的可发现、可启动和可使用状态。

## 2026-09-24 真机 PRoot SIGSYS 修复与 CLI 更新验收

- Android PRoot 从 upstream 5.4.0 切换到 Termux `v5.1.107.94`
  (`58c3b42849fac502c6c60a45c4d2a82da9e9f8d4`)；原因是旧版本没有处理
  Android seccomp 送给 guest tracee 的 `SIGSYS`，曾导致真机 PRoot worker 以 signal 31
  退出。按固定 commit 用 NDK 29 重建 ARM64 PRoot 与静态 loader，release APK 通过
  native asset verifier 并覆盖安装到 Xiaomi Android 16 真机 `6cb21282`。
- 真机 App UID PRoot guest 的 `/usr/bin/true` 与 `codex --version` 均退出 0，未再观察到
  signal 31；这只证明 PRoot/CLI 基本启动，不替代 Codex turn 全链路验收。
- 设置页“检查并更新”首次 npm metadata 请求达到 30 秒超时；未修改 CLI。保持相同设备网络
  重试后，registry 查询、CLI 安装、staged `codex --version`、活动 launcher 切换及切换后
  CLI 校验全部成功；再次检查仅执行当前版本与 registry 查询并正常结束，没有重复安装。
  因而应用私有 PRoot CLI 的更新/切换/幂等检查已在真机走通；首次超时的网络根因尚未定位，
  不能推断为已修复的确定性缺陷。
- 重要边界：这条更新链仅更新 Linux/PRoot home overlay，不会替换 APK 内 Android-native
  `libcodex.so`；当前 APK manifest 仍标记 native CLI `0.154.0`。设置完成后的模型刷新回调
  依附当前认证 session 的 runtime，因此更新 PRoot 后不能据此宣称默认 native runtime 或其
  模型目录已更新。下一步需要明确 native-compatible runtime 的构建/发布/签名来源，并让模型
  目录反映实际执行 runtime；在此之前不得把 PRoot OTA 描述成 native OTA。

## 2026-09-24 真机 Android-native 工具链真实 Codex turn 验收

- 在 Xiaomi Android 16 真机的 `test-project` 中新建临时 session，以 `5.6 Luna · low`
  完成真实 Codex turn。turn 展示 7 个 `commandExecution` 工具事件，状态回到“就绪”；
  Codex UI/进程仍由本地 App Server 持有，没有启动 PRoot worker。
- 命令均在 App UID `10509` 下成功，`pwd` 为
  `/storage/emulated/0/Codex/Workspaces/test-project`；逐项结果为：`git --version` →
  `git version 2.55.0`，`node --version` → `v22.23.2`，`npm --version` 与
  `npx --version` → `10.9.2`，`python --version` → `Python 3.14.7`。`id -u`、`pwd`
  和以上五个版本命令均 exit 0、stderr 为空。这证明这些 Android ABI 工具不只是安装/探针
  显示可用，而是能从真实 Codex turn 的直接工具执行路径调用。
- 本次提示明确禁止联网、安装与文件改动，因此只证明工具发现/启动/输出回传；不据此宣称
  Codex turn 内的 npm registry 依赖安装已验收。PRoot npm 更新安装则已由前一节独立验收。
  turn 中的 Code Mode 提示显示“不可用，已改用直接工具”，可选网络 MCP 也显示不可用；
  两者没有阻止上述本地命令。停止临时 session 后只删除了新建的“Run environment checks”
  历史，原有 `Check tool versions` 历史及 `test-project` workspace 均保留。

## 2026-09-24 真机模型目录刷新边界

- 在设置中只读打开模型选择器，看到 11 个模型；`gpt-6-astra` 存在，但用户要求的
  `gpt-6-sol` 与 `gpt-6-luna` 不在目录中。当前 APK 内 Android-native runtime 为
  `0.154.0`。没有选中模型，也没有改变会话设置。
- 源码确认更新成功后的刷新回调指向当前 auth session 的
  `refreshModelCatalog()`；`CodexModelCatalogClient.load` 再按该 session 的 active backend
  查询 CLI/app-server。Native-first session 因而刷新 APK 内 `0.154.0`，不会自动改为查询
  已升级的 PRoot overlay。这是已复现的目录来源错配，不是 registry 更新失败。
- `apps/codex` 当前没有 Android-native Codex runtime 的构建脚本或 OTA manifest endpoint；
  native runtime 只有经过 manifest/SHA-256 校验的本地导入路径。现有 Android Release 工作流
  针对旧 `apps/mobile` 包，不构建或发布独立 `apps/codex` native runtime。完成 native OTA
  仍需 Android/Bionic 兼容产物、可验证签名与项目自己的发布源；不能拿 npm 的 Linux/musl
  二进制覆盖 Bionic runtime。

## 2026-09-25 Android-native Codex 0.156.1 真机预检与设置状态修复

- 从官方 `rust-v0.156.1`（commit `b412ff32c417f855c2b2d1581b77058eed87c84b`）构建
  AArch64 Android/Bionic Codex CLI。针对 Bionic 不提供 `flock` 的差异应用了文件锁兼容补丁；
  release 构建成功。未经 strip 的 ELF 为 1,474,719,200 bytes，发布候选经
  `llvm-strip --strip-all` 后为 232,412,024 bytes，SHA-256
  `0fbf6589b47c1f8c2af07511bfa2597bd4c88762f8d301092ce13fdf76dbc025`。
- 在 Xiaomi Android 16 真机上验证该候选的 CLI `--version`、`app-server` 初始化、
  `model/list` 与 `thread/list`。隔离 CODEX_HOME 的 app-server 返回 11 项模型，包含
  `gpt-6-luna` 与 `gpt-6-sol`；空目录的 thread/list 为 0。随后通过 App 的 SAF 导入流程
  安装到 App UID native runtime slot 与固定 Root fallback slot；App UID probe 报告版本
  `codex-cli 0.156.1`、ABI `arm64-v8a`、SHA 与 manifest 一致。以上没有启动真实 turn，
  也没有改动用户现存 workspace/session。
- 真机只读检查设置中的模型选择器后确认 `gpt-6-astra`、`gpt-6-sol`、`gpt-6-luna`
  均可见；先前“Sol/Luna 缺失”的判断来自未滚到完整模型选择器的观察，现予以更正。
  模型选择器卡片显示 12 个 CLI 模型，未选择任何模型或改变会话配置。
- 修复运行时导入后的设置页状态滞后：导入回调现回传验证过的 runtime descriptor，设置页
  立即替换缓存 Future，不再要求用户额外点“刷新本地能力”。新增 widget 回归测试；
  `flutter test test/settings_model_catalog_test.dart` 6 项全部通过，`dart format` 无改动。
  `flutter analyze` 本轮仍被 Analysis Server 的 malformed/unterminated JSON 通道异常中断，
  不能记作分析通过；此前也出现过同类问题。
- 本版本仍通过用户可控的本地文件导入安装，不是自动在线更新。官方源码补丁与
  Windows/NDK 构建配方现已加入 `tools/android-codex-native/`；232 MB 候选二进制仍是
  本地 release candidate，没有提交进仓库。GitHub Releases 尚无此项目的 Android
  Codex-native runtime 资产，因此“应用内 native CLI 在线更新”仍未完成；PRoot 的 npm
  更新流程与此功能边界不同。
- 同日正式模式 APK 构建成功并通过只读交付校验：`io.henry.codex` 1.0.0，117,152,555
  bytes，SHA-256 `dbc457661d4a84c284e365a0ecd2b4078ef14f5812478970cb9f633a2db89f20`；
  PRoot/loader/trampoline/worker guard/root-read broker 5 项齐全，APK 签名有效。它使用
  本地 Android debug certificate，不是生产发布签名。无运行中的 Codex worker 时通过
  `adb install -r` 覆盖安装，workspace/session 数据仍在。
- 真机同时暴露了 APK 升级后的 runtime 槽位边界：安装包更新改变了
  `ApplicationInfo.nativeLibraryDir`，旧版本的 App UID 导入覆盖不再位于当前包目录；
  `/data/local/tmp/io.henry.codex/codex-runtime/bin/codex` 的持久 Root 回退副本仍为
  0.156.1 且 SHA 未变，但 App UID 预检暂时选中 APK 内置 0.154.0。随后从已下载的同一
  0.156.1 文件重新导入到当前包目录，App UID 预检和设置卡片均即时更新为 0.156.1，
  无需手动刷新。这确认了本次缓存状态修复，也确认“APK 升级后自动恢复持久导入 runtime”
  仍是需要处理的缺陷；全程未启动真实 turn 或修改既有会话。
- 构建配方脚本已通过 PowerShell parser 检查；包含 30 个上游 Android/Bionic 源码差异和
  新增文件锁 helper 的补丁在原构建树上通过反向 apply 检查与 whitespace 检查。构建树
  目前保留在本机临时目录，不删除，方便后续再次核对；脚本从干净的固定 upstream commit
  检出构建，不复用/覆盖项目 vendor 子仓库。

## 2026-09-25 Android-native runtime 应用内更新器

- 设置中新增独立的“更新 Android 原生 Codex”入口，与原有 Linux/PRoot npm 更新明确分开。
  用户确认后才检查/下载；只接受 `android-codex-native/vX.Y.Z` stable release 和固定的
  `codex-android-aarch64`、`codex.manifest.json` 两个资产。限制 HTTPS 主机/重定向、文件大小，
  校验 tag 与 manifest 版本、ABI、source、size、SHA-256，并复用 Root 与 App UID 原子安装。
  App 更新检查使用已有 runtime version hint；无发布/已最新路径不再额外调用可能清理 legacy
  cache 的完整 `probeCodexRuntime()`。GitHub API 403/429 会明确提示稍后重试。
- 增加 `.github/workflows/android-codex-native-release.yml`：仅在推送精确的
  `android-codex-native/v0.156.1` tag 后，用 Windows/NDK r29 构建并上传两个 release 资产。
  仅加入本地仓库，未推送 tag、未创建/修改 GitHub release；构建 workflow 尚未在线执行。
  当前 release 页面列出的最新发布为 Windows/macOS/Linux/iOS 系列，没有看到本项目 Android
  native tag；因此不能验收真实资产下载/升级路径。
- `flutter test test/settings_model_catalog_test.dart test/codex_native_runtime_updater_test.dart`
  9 项通过。定向 Kotlin metadata tests 和 `MainActivity` 编译通过：Gradle 单测命令需要排除
  Flutter 的 `compileFlutterBuildDebug`/`copyFlutterAssetsDebug`，否则现有 Flutter Gradle task
  在输出 parent 路径上抛 `File.exists()` parent=null；release APK 的完整构建随后通过。
- 最终正式模式 APK：`io.henry.codex` 1.0.0，117,168,039 bytes，SHA-256
  `57f1f6df63222ea72dd0dae91cdae6af09a010f98c92c7a034b836f3f902c2cd`；验证器确认签名有效、
  5/5 个 PRoot/guard/root-read native assets 齐全，但仍是本地 Android debug certificate，
  不是生产签名。无 Codex/PRoot worker 时覆盖安装到真机并重新启动 App；未发起任何 session。
- 本轮再次证实 APK 更新会清空版本化 `nativeLibraryDir` 中导入的 App UID runtime：真机设置页
  显示 APK 自带 `0.154.0`，而持久 Root fallback 经 ADB 只读 SHA-256 复核仍为
  `0.156.1`（`0fbf6589b47c1f8c2af07511bfa2597bd4c88762f8d301092ce13fdf76dbc025`）。更新器按钮/确认对话框出现；
  执行检查后回到设置且没有 runtime-update 错误日志，但 Snackbar 未及时捕获，故设备端 no-release
  UI 反馈只记为部分验证。操作中一次触点误落到 native-toolchain 导入确认框，立即点取消；没有
  批准、选文件或安装。未启动真实 turn、未更改 session/settings；临时 UI dump 已删除。
- 现存阻塞：尚无项目 Android-native Release 资产，API 未认证查询也可能遇到 GitHub 403 限流；
  release workflow 未跑、也未发布。APK 升级后自动把持久 Root runtime 安全提升到新 App UID 槽位
  仍未实现；不要把“在线更新 UI 已接入”描述成完整 OTA 验收。

## 2026-09-25 native runtime 恢复入口与 Root-first 可行性评估

- 设置新增“从本机备份恢复原生运行时”。它只在用户点击并确认后请求 Root：先探测固定 Root runtime
  候选并验证其 manifest，再按 manifest 路径/大小上限复制到私有暂存区，核对主程序及 companion
  SHA-256，复用原子安装器写入当前 APK 的 App UID 可执行目录，最后再次验证 App UID、版本和哈希。
  普通 runtime probe 和打开设置不会自动请求 Root 或改动 runtime，也不触碰会话历史。
- 能力判断：native Root app-server 走 `HostProcessManager` 的 `su` 通道。兼容层默认 App identity
  通过固定 guard 降回 App UID；Root identity 则已有单独的 Root Profile 门禁和
  `CompatibilityRootLaunchScript`，经固定 `su` helper 启动 PRoot，未调用 `setuidgid`，且只为 Root
  模式绑定固定 Android host paths。PRoot 的 `--root-id` 单独只影响 guest 身份，不能代替这条真实 UID 0 路径。
  Root PRoot 执行链已在代码中实现，剩余关键工作是用设备专用 Profile 验证整条 app-server/工具链的实际 UID、SELinux 和路径矩阵。
- 安全边界尚未满足“Root 默认可用、危险系统写入必被可靠拦截”的强保证。现有 `RootAccessPolicy`
  是 app-layer 命令/文件审批预检，不是任意 Root 子进程的 OS 强制写边界；本机 ROOT_ACCESS_POLICY
  记录的 2026-09-23 Xiaomi 进程观察为 UID 0、有效 `CAP_DAC_OVERRIDE`、`NoNewPrivs=0`、
  `Seccomp=0`，且设备未启用 Landlock。下一轮应把 Root Profile/capabilities/SELinux 和固定
  KernelSU 插件路径纳入可验证的执行隔离设计，不能只依赖命令文本分类。
- 本轮验证：新增 updater service 通道测试与显式确认 widget 测试后，`flutter test
  test/settings_model_catalog_test.dart test/codex_native_runtime_updater_test.dart` 共 11 项通过；
  `:app:compileReleaseKotlin` 在排除已知会因
  Flutter Gradle 输出 parent=null 而失败的 Flutter build/copy tasks 后通过；正式模式 APK 构建及
  `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 通过。产物 117,177,423 bytes，SHA-256
  `ccbb7f2baef07c0c232b3d66a9b47666ad909e250724c02e6e5e14df1ed73959`；本地 debug certificate。
  定向 `dart analyze` 返回非零，报告 19 条 warning/info、无 error-level diagnostic。
- APK 尚未安装到真机，本轮没有点击恢复、触发 KernelSU 授权、启动 session 或更改设备数据；因此
  Root 备份恢复的设备端可用性仍待验证。Root-first PRoot 方案也尚无当前设备的 supervisor/PRoot/
  Codex app-server 同链 UID、SELinux 与路径读写矩阵验证，不能标为已完成。

## 2026-09-25 Root/PRoot 代码核查与 Release 更新

- 对 `CompatibilityProcessManager` 做了精确链路核查：App identity 使用降权 launcher；`identity=root`
  会先运行 Root Profile 探针，再由 `CompatibilityRootLaunchScript` 通过已批准的 `su` helper 启动
  `libcodex_worker_guard.so` 与 PRoot。该固定 Root supervisor 路径不设置 App UID，也不调用
  `setuidgid`；源码测试验证命令中保留 `--root-supervisor`、marker/stop 管理且无降权参数。
  因此 Root PRoot 执行链不是待开发项，但只完成静态/主机侧验证，尚无设备上同一 app-server worker 的
  UID/context/capability 证据。PRoot `--root-id` 仍然只是 guest 映射，真实 Android Root 来自 `su`。
- 剩余可行性问题集中在 KernelSU 专用 enforcing Root Profile 与设备验收：Profile 必须通过 UID、组、
  capability、全局读取样本和核心路径写拒绝检查；之后还需证明 app-server/PRoot/子命令实际继承该身份，
  并验证中风险审批和 Boot/核心区仅走已审阅 KernelSU 插件。当前 `RootAccessPolicy` 是 app-layer
  预检，不能单独保证任意 Root 子进程无法绕过高风险写入限制。
- Release APK `ccbb7f2b...73959` 已于 2026-09-25 03:04 通过 `adb install -r` 覆盖安装到真机，
  `io.henry.codex` 仍为 1.0.0；安装前无 Codex/PRoot worker。遵照暂不做 UI 测试的要求，没有启动
  App、会话或触发 Root 授权。Root runtime 恢复按钮仍待用户在设置中显式确认后做设备端验证。

## 2026-09-25 Root 会话只读权限档位

- 修复此前 Root 权限选择中的假只读状态：设置值已保存，但 Root app-server 为保留全局读取始终使用
  `danger-full-access`，且低风险 workspace file-change 会被自动放行。现在 Root 会话选择“只读”后，
  审批层仅自动允许无 shell 运算符的显式只读诊断命令；文件变更、写入/未知命令及副作用不明的
  Root CLI 命令均被拒绝。`item/tool/requestUserInput` 与 MCP elicitation 仍可正常询问用户。
- Root 全局读取路径保持不变；只读档位明确标成“应用级”，不宣称是内核沙箱。默认 Root 档位仍允许
  已分类低风险写入直行、中风险逐项审批，并拒绝普通 shell 对高风险系统/boot 目标的写入。
- 定向 Flutter 测试 `root_access_policy_test.dart` 与 `codex_session_client_test.dart` 合计 34 项通过。
  对三个修改文件运行 `dart analyze` 无 error-level diagnostic；命令仍因 main.dart 中其余 18 条
  warning/info 以非零退出。未重新编译 Release 或操作真机 UI；设备端 Root 写入隔离仍未验收。
- 随后已用 Release 流程重新构建并验证 APK：117,179,179 bytes，SHA-256
  `e9d25d32f5353f90785c526133d2eb07725fb897dd8a6bc259d16465b5452be0`，签名仍为本地 debug
  certificate，5/5 ARM64 PRoot/guard/root-read native assets 齐全。2026-09-25 03:21 在确认无
  Codex/PRoot worker 后，`adb install -r` 成功；未启动 App 或 session。没有做设备端权限交互验收。
- 增加主页面集成测试，覆盖已恢复 Root + 只读权限档遇到写命令审批时，界面显示策略原因、禁用批准
  并且不向 app-server 回传 accept。合并运行 Root policy、session client、session conversation 三个
 测试文件共 45 项通过。Flutter 测试日志仍提示 Google Fonts 缓存未命中/网络字体下载失败，但退出码为 0；
该缺失只影响测试字体加载，不影响断言结果。

## 2026-09-25 真机 KernelSU su 身份与 SELinux 只读探测

- 真机 `6cb21282` 在线，Android 16 / API 36，SELinux 为 Enforcing。打开应用首页后，
  `io.henry.codex` PID `9000` 是 UID `10509`，域为
  `u:r:untrusted_app:s0:c253,c257,c512,c768`，`Seccomp=2`、`CapEff=0`。ADB shell 自身则是
  KernelSU 的 UID 0 / `u:r:ksu:s0`；这两种身份不可互相代替。设备上的 `ksud` 为
  `3.3.0 (uapi: 2)`。
- 通过 ADB root 启动只执行 `id`、读取自身 `/proc/self/status`、`test -r`/`test -w` 的
  子进程，没有写文件或读取文件内容。显式设为 UID 0、保留 App 的 `untrusted_app` SELinux
  域时，子进程获得完整 capability 集且 `Seccomp=0`，能读 `/system/build.prop`，但对
  `/data/system/packages.xml`、`/data/user/0`、`/data/local/tmp`、应用工作区
  `/storage/emulated/0/Codex/Workspaces` 和 `/dev/block/by-name/boot_a` 的读写检查均被拒绝。
- 显式设为 `u:r:su:s0` 的 UID 0 子进程同样有完整 capability 集和 `Seccomp=0`，但本次
  对上述路径的读写检查均被拒绝。显式设为 ADB 当前使用的 `u:r:ksu:s0` 后，读取检查通过，
  并且 `/data/system/packages.xml`、`/data/user/0`、`/data/local/tmp`、
  `/storage/emulated/0/Codex/Workspaces`、`/dev/block/by-name/boot_a` 的 `test -w` 也通过。
  没有对这些路径实际写入，也没有触碰启动分区。
- 相关 SELinux 对象类型只读取标签确认：`/system/build.prop` 是 `system_file`，
  `/data/system/packages.xml` 与 `/data/user/0` 是 `system_data_file`，
  `/data/local/tmp` 是 `shell_data_file`，应用工作区是 `fuse`，`boot_a` 是 `block_device`。
  这些标签为后续设计专用 Root domain 的窄规则提供了设备基线；尚未加载或安装任何
  sepolicy/module。
- 结论：在该设备上，单纯把 Codex 改为 UID 0 仍不够。App SELinux 域保留了部分隔离，无法
  满足全局读取；`ksu` 域可读的同时也可直接写 boot block，无法满足高风险操作只能经审批/插件。
  需要验证一个专用、Enforcing 的 Codex Root SELinux profile：允许所需的广泛读取和低风险写入，
  明确拒绝核心分区写入；中高风险写入仍需由独立受控 broker / KernelSU 插件执行。上述结果来自
  ADB root 下显式切换 SELinux context 的只读探测，不等同于 App 发起的 Root PRoot 或真实 Codex
  turn 验收。
- 源码核查发现 `sepolicy`/SELinux 变更被插件归类为 R3；当前 `KernelSuPluginBridge` 明确拒绝
  Dart 传入的 `device_credential` 字符串，设置页也只会把 R3 插件安装为禁用状态。因此专用
  SELinux profile 目前没有应用内的确认后启用路径。下一步依赖真实 Android 设备凭据认证，且
  认证结果必须绑定已审阅的模块摘要与 enable 操作，不能把普通按钮值当作认证证明。
- 打开应用首页后系统自动启动 `libcodex.so` PID `9442`，它仍是 UID `10509`、
  `u:r:untrusted_app:s0:c253,c257,c512,c768`、`CapEff=0`、`Seccomp=2`，不是 Root Codex。
此后 MIUI 计算器成为前台 Activity；没有启动 session/turn、没有调用模型、没有安装或覆盖 APK，
也没有更改 KernelSU profile。应用进程留在后台，未主动终止。所有 `test -w` 都只是权限检查。

## 2026-09-25 KernelSU 归档风险识别与审核预览

- 复核标准 KernelSU 模块布局时发现，归档成员 `sepolicy.rule` 未按文件名本身升级风险；低风险
  manifest 配合普通 `/data/adb/modules` overlay 声明可能漏掉 SELinux 策略变更的 R3 识别。现已把
  `sepolicy.rule`、`service.sh`、`post-mount.sh` 和 `initrc/` 启动配置纳入 R3；风险取自归档事实，
  不能由较低的 manifest `riskHint` 降级。原始模块字节、签名摘要与安装语义没有因此改写。
- 设置审核面现在呈现解析后的自述字段、全部归档成员名称，以及脚本、`sepolicy.rule`、
  `system.prop`、`initrc/*.rc` 的 UTF-8 预览。单文件预览上限 32 KiB、总预览上限 128 KiB；路径、
  描述及预览会把双向控制字符转义，非 UTF-8/截断文件明确标注。manifest 是插件自述，二进制和
  截断内容仍不可由此界面完整审计；SHA-256 仍绑定整个原始归档。
- `flutter test test/kernelsu_plugin_settings_test.dart` 通过；三个变更 Dart 文件 `dart analyze`
  无问题；` :app:testDebugUnitTest --tests io.henry.codex.PluginBrokerTest` 通过，覆盖低风险自报下
  SELinux/启动 hook 的 R3 分类、预览边界和 bidi 控制符转义。Gradle 给出仓库已有 Kotlin/AGP/Gradle
  版本弃用提示，不影响本次测试结果。
- 随后本地 Release 构建和只读 APK 验证通过：`app-release.apk` 为 117,243,799 bytes，SHA-256
  `49b8907a0aae11eccd9b693e2018d5b946f63462f0249c536b809daa7412aa26`，签名可验证且 5/5 ARM64
  runtime native assets 齐全；使用本机 debug certificate，不是商店发布签名。
- APK 未安装/启动；没有触发系统设备凭据、启用或安装 KernelSU 模块，也没有写入手机。设备侧真实
  凭据回调和 harmless module stage/install/list/rollback 仍待后续验收。

## 2026-09-25 KernelSU R3 模块凭据启用入口

- R3 插件安装后仍保持禁用；设置页新增显式“通过设备凭据启用”操作，并显示模块 ID、完整 SHA-256
  与是否需要重启。Native 端先重新校验私有暂存区中的 request/module/digest 和风险等级，再调用
  Android 11+ `BiometricPrompt`，只允许 PIN/图案/密码，不接受生物识别替代。系统回调确认类型正确后，
  才以进程内可信确认值调用固定 KernelSU broker；Dart 传入的 `device_credential` 仍会被拒绝。
  未设置安全锁屏、API 低于 30、用户取消或认证类型不符时均失败关闭。
- 更新了 Root 操作文档，明确设备凭据只证明用户确认了这一份已暂存模块，不代表模块 SELinux 规则安全，
  也不代表目标 Root profile 已实现全局读取与系统/boot 写入隔离。
- 定向 Flutter 测试覆盖 R3 安装保持禁用及启用请求不伪造设备凭据；与 Root policy、session client、
  session conversation 测试合并运行共 46 项通过。只读 Root 权限 UI 用例原先固定在 800×600 测试视口，
  弹层选项超出屏幕；将该用例视口改为 800×900 后用例通过。Google Fonts 测试时仍报告网络字体不可取，
  但测试退出码为 0。目标 Dart 文件 `dart analyze` 无问题；Android `:app:testDebugUnitTest` 通过。
- 官方 Release 构建脚本和 APK 验证通过，产物 117,191,611 bytes，SHA-256
  `7f0b383cb15f127be99e8d790b595d1ba23934af7aca701cdf0e9ce546130a5e`，5 个 ARM64 Codex native
  assets 齐全；仍是本地 debug certificate，不是商店签名版本。
- 未在真机触发 PIN/图案/密码弹窗，未安装本次 APK，未启用插件或写入设备策略。下一步需在用户准备好
  解锁时验证真实系统凭据回调与 KSU broker enable，再验证重启后的 profile 生效。Root-first PRoot/Codex
  同链执行、专用 Enforcing SELinux domain、广泛读取和 boot 写阻断仍是核心未完成项。

## 2026-09-25 KernelSU Root Profile 只读诊断入口

- 设置页新增显式点击的 `检查 KernelSU Root Profile`：显示实际 UID、SELinux context、capability
  masks、Linux `/proc` `NoNewPrivs`（仅作信息展示）、SELinux enforcing 状态，以及固定样例路径的存在/读/写
  权限检查。该诊断不会返回/记录文件内容或写设备路径，进入设置时不会自动调用 `su`。最初版本只做
  `test -r`；后续强化为固定文件样本读取 1 字节、目录样本枚举且丢弃结果，见本页较新的
  `Root Profile 探针权限集收紧`。
- 返回状态分为 denied、review_needed、smoke_passed；通过只代表固定样例符合预期，不构成全文件系统
  策略证明。仅 `u:r:codex_agent:s0` 和 capability masks `0x6`（仅 `CAP_DAC_OVERRIDE` 与
  `CAP_DAC_READ_SEARCH`）可通过 profile 检查；当时误把 Linux `NoNewPrivs=1` 作为必需条件，见下方更正。目标包含
  `/data/system/packages.xml`、应用 workspace、boot_a、KernelSU module roots、`/system/build.prop`；
  boot/module/system 的写权限要求保持拒绝。
- 当时的兼容进程 launcher 核查：PRoot `--root-id` 仅设置 guest identity；当时 Root-assisted launcher
  仍通过 `su -Z <app SELinux context> -g <app UID> ... <app UID>` 启动 worker。该结论后来被独立的
  Root identity `su → worker guard → PRoot` no-drop 启动路径取代；当前状态以本文件后面的
  `Root/PRoot 代码核查与 Release 更新` 和 `root-first + PRoot 方案可行性` 记录为准。设备实际 worker
  UID/profile 仍未验收。
- 验证：KernelSU Settings widget 2 项通过，`dart analyze` 目标文件无问题；JVM
  `RootProfileProbeTest` 与 `PluginBrokerTest` 通过。Gradle 仍报告已有 Android API/Gradle 弃用告警。
  本轮仅源码和主机测试，没有触发真机授权/探测、未安装或启动 APK、未安装 KernelSU 模块，也未写设备。
- 补充反例测试后再次构建并验证最终 APK：117,251,379 bytes，SHA-256
  `e5c27d18e791bb05a761682c384234d90bc8830f5ed228c372188e6895826fae`，package
  `io.henry.codex`，5/5 ARM64 runtime assets 存在，签名可验证但仍为本机 debug certificate；本轮未安装。
- 当前下一步是真机准备好并由用户解锁后，点击设置中的诊断，确认实际 `su` 子进程身份；之后再据设备
  证据实现受约束的 Root worker launcher。仅构建或探针 smoke 通过都不算 Root-first 验收。

## 2026-09-25 CLI 命令无响应回归检查

- 复核 `/version` 和 `/cli <args>` 路径：本地命令绕过模型 turn，先显示执行状态，再把结果作为会话记录呈现；
  参数 tokenizer 不经过 shell，并保留引号中的空格参数。
- 定向 Flutter widget 用例 `CLI version command shows progress and its result in the thread` 通过：
  `/version` 返回 fixture 版本，`/cli debug prompt-input "a prompt with spaces"` 得到 argv
  `['codex','debug','prompt-input','a prompt with spaces']`。测试日志有既有 Google Fonts 网络缓存告警，
  断言退出码为 0。本机模拟测试无法证明手机上当前安装的 runtime/CLI 能执行同一命令；仍需真机复测。

## 2026-09-25 Root-first Linux/PRoot 路线可行性复核

- 上游 `openai/codex` 当前为 Linux ARM64 提供 `aarch64-unknown-linux-musl` standalone/npm 二进制；
  因此可在 PRoot guest 内直接分发和更新官方 Linux CLI，不必每次交叉编译 Android 版。它不是 Android
  target；PRoot 只提供 Linux userspace/路径兼容，不能自行产生 Android UID 0 或绕过 SELinux。
- 项目已有真机证据：官方 `@openai/codex@0.154.0-linux-arm64` 在 ARM64 Debian PRoot 中以 App UID
  启动并通过 app-server ready/stop 与真实 turn。此证据证明 Linux CLI/PRoot 路线可运行，不证明 worker
  已拥有 Android root。该段原先关于 launcher 显式降到 App UID 的判断已被后续 Root identity no-drop
  launcher 实现与代码核查修正；Root worker 的同链设备证据仍缺。
- KernelSU 官方 Root Profile 支持为同一应用的 `su` 子进程配置 UID/GID/groups、capabilities、SELinux
  context/rules 和 KernelSU 自身的 `NO_NEW_PRIVS` 防重复提权标记。这使“UID 0 + 专用 enforcing domain +
  最小能力集”具备实现基础；本项目
  新增的 profile probe 只检查固定样例，仍不能证明全局读写策略或 app-server worker 本身的实际身份。
- Android SELinux 仍约束 UID 0 进程；用户未解锁时，凭据加密存储也不可访问。因此“读取全局文件”只能解释为
  在设备已解锁、挂载可用且设备 SELinux policy 明确允许的范围内尽可能读取，不能承诺绕过密钥/挂载状态。
  参考 [AOSP SELinux](https://source.android.com/docs/security/features/selinux) 与
  [Android Direct Boot](https://developer.android.com/privacy-and-security/direct-boot)。
- 核心设计约束：同包内安装器、Typed KernelSU broker、清理 helper 和 Codex worker 都会调用 `su`，不能
  假设给 Codex worker 设置 Root Profile 不影响其他受控 helper；需验证隔离/独立 broker 设计。若 Codex
  worker 得到任意 root shell，应用层低/中/高风险审批本身不能拦截其绕开 UI 的直接系统写入；危险设备节点、
  boot/raw-block 等必须由 SELinux/受限 broker 在 OS 边界拒绝或代理，不能只靠 AGENTS.md 或提示词。
- 结论：目标在已解锁 KernelSU、可部署专用 profile 的指定设备上有条件可实现；“所有 ROM/所有路径均能全局
  读取、普通 root shell 又绝不可能越过审批写危险区域”不能仅由 PRoot + root UID 保证。需要先定义设备策略，
  再真机验证 worker UID/context/capabilities、workspace/system-data 读取与写入边界、boot/block 拒绝、
  低风险命令和 KernelSU typed broker 操作；当前未安装或运行本轮 APK。
- 本轮 `:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest --tests io.henry.codex.PluginBrokerTest`
  通过；Release APK 重新构建并经 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 校验：
  117,251,379 bytes，SHA-256 `e5c27d18e791bb05a761682c384234d90bc8830f5ed228c372188e6895826fae`，
  `io.henry.codex`，5/5 ARM64 native assets 齐全，签名有效但为本机 debug certificate。未触碰手机。

## 2026-09-25 KernelSU `NO_NEW_PRIVS` 探针语义更正

- 对照 KernelSU 官方内核源码后确认：Root Profile capability 集会写入进程的 effective、permitted、bounding
  集；Root Profile `NO_NEW_PRIVS` 则设置 KernelSU 私有的 `TIF_KSU_DISABLE_ESCAPE_WITH_ROOT` 标记，阻止后续
  经 KernelSU 再提权，并不设置 Linux `/proc/self/status` 的 `NoNewPrivs` 位。Linux 字段因此不能用于判断
  KernelSU Profile 开关是否已启用。
- 修正探针字段名为 `linuxNoNewPrivs`，并从 `smoke_passed` 条件中移除 Linux `NoNewPrivs=1`。Settings 明确
  显示该字段仅供参考，并提示用户需在 KernelSU Manager 中单独确认 Profile 的 `NO_NEW_PRIVS` 开关；capability
  mask `0x6` 仍通过 KernelSU 源码得到支持，但实际 PRoot/插件操作能力尚待设备验证。
- 新增回归用例：Linux `NoNewPrivs=0` 时，只要其余 KernelSU profile 样本符合要求，探针仍返回
  `smoke_passed`；boot block 可写仍必须返回 `review_needed`。官方依据：
  [KernelSU app_profile.c](https://github.com/tiann/KernelSU/blob/main/kernel/policy/app_profile.c#L178-L194)
  与 [App Profile 文档](https://github.com/tiann/KernelSU/blob/main/website/docs/guide/app-profile.md)。
- 验证完成：`dart analyze lib/services/root_profile_probe.dart lib/kernelsu_plugin_settings.dart` 无问题；
  `flutter test --no-pub test/kernelsu_plugin_settings_test.dart` 2 项通过；
  `:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest --tests io.henry.codex.PluginBrokerTest` 通过。
- Release APK 已重建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：117,251,579 bytes，
  SHA-256 `88d84381cc7dae13b164167becc2fb9317ea976bfc18514b64ec7750d96b38cc`，5/5 ARM64 native assets 齐全，
  APK 签名有效但仍是本机 debug certificate。此前 SHA `e5c27d...` 包含错误判定门槛，不应用于 Profile 诊断。
- 未安装或启动本次 APK，未触碰手机；真机仍需验证 KernelSU Manager 的 profile 选项、探针实测和 Root worker 身份/权限。
- 同步修正注入每个 thread 的 Android 操作说明：Root 授权按命名 session 复用，不应每个 turn/页面切换重复询问；它不等于写入授权，且 app 层路径分类不构成内核强制边界。Root Profile 的 KernelSU `NO_NEW_PRIVS` 与 Linux `NoNewPrivs` 区分也已写入运行时指令和安装到 PRoot Codex home 的 `AGENTS.md`。
- 为 thread bootstrap 加入指令契约断言，`flutter test --no-pub test/codex_session_client_test.dart` 24 项通过，定向 analyzer 无问题。包含上述指令更正的最终 Release 已重建并验证：117,252,187 bytes，SHA-256 `cc78e524fe5dd19c9281deed4465c555ba8a5e6f1a386d0754a54f09d3d09423`；5/5 ARM64 assets、签名有效，仍为本机 debug certificate。未安装到手机。
- 续验 session 授权实际行为：`flutter test --no-pub test/local_session_auth_test.dart test/session_history_test.dart` 19 项通过，覆盖同一 session 重进设置不重复请求、切到新 session 重新授权、已命名 session 的批准状态从历史恢复，以及无 session ID 的旧 workspace 记录不得继承 Root 批准。
- 能力审计确认，项目对应的上游 Codex 提交包含 `thread/fork` app-server v2 RPC，但本 App 的每 session `CODEX_HOME`/SQLite/进程隔离意味着不能直接让 fork 后的新 session 共用源目录。兼容性文档已记录这一实现约束和正确后续方向（受支持的存储快照/转移，或同进程多 thread 管理），避免回退到共享 SQLite 并发设计；fork UI 仍未实现。

## 2026-09-25 Root worker 启动门禁与真机 profile 验证

- 修正真实 Root Profile probe 对 `/proc/self/status` 的 capability 解析：目标机的 Android Toybox 不包含 `awk` applet，故改用已在设备 shell 确认可用的 `toybox sed`；原错误会让探针以 exit 127 退出。现在 UI 能显示实际 `CapEff`，并同时展示 `CapPrm`/`CapBnd`。
- Native Root Codex worker 现仅在显式 profile probe 返回 `smoke_passed`、固定 `su` helper、UID 0、专用 Enforcing context、能力 mask 0x6、网络组 3003、workspace/app 目录读写、boot/KSU/system 写保护等样例均满足时才能启动；probe 失败会在 worker 创建前硬失败。不会将 PRoot `--root-id` 当作 Android Root，PRoot backend 对 `ExecutionIdentity.root` 明确报错；官方 CLI updater 改为使用 app identity 操作 app 私有版本目录。
- Root orphan cleanup 不再在 HostProcessManager 初始化/进入设置时自动调用 `su`；仅在用户明确启动 Root session 且 profile 通过后清理一次。启动、停止和 marker 清理复用通过 probe 的同一个固定 helper。
- 真机 `24031PN0DC` / Android 16 / `io.henry.codex` 只读检查结果仍为 `review_needed`：UID 0 但 context 为通用 `u:r:ksu:s0`，supplemental groups 为 `0`（缺少 3003）；CapEff/CapPrm/CapBnd 均为 `0000000400400022`（不符合 0x6）；workspace 与系统数据可读、workspace/app runtime 可写；boot block 与 KernelSU 目录可写，只有 `/system/build.prop` 写被拒绝。因此 Root worker 被门禁拒绝，未启动 Codex Root 进程；未写入系统或 boot 路径、未更改 KernelSU profile。
- 本轮定向验证：`:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest` 通过；Flutter `linux_compatibility_backend_test.dart` 与 `codex_cli_updater_test.dart` 共 12 项通过，`kernelsu_plugin_settings_test.dart` 2 项通过；定向 `dart analyze` 无问题。最终 Release APK 117,255,863 bytes，SHA-256 `b8ab94cbbd1682160907364700e1d0ee5e932b9156154378f1507ae22e808ca3`，签名有效但仍为 debug certificate，5/5 ARM64 native assets 齐全；通过 `adb install -r` 安装到真机且保留了 app 数据，并在安装版上复核到三组 capability 和同一 `review_needed` 结果。
- 仍未完成：用户设备上的专用 `codex_agent` SELinux Root Profile 配置和实际 worker UID/context 验证；真实 Root worker 的低风险全局读取、medium approval、boot/raw-block 拒绝、Root session 并行与停止/重启清理验证；PRoot 兼容模式下的明确 guest-admin 依赖安装入口也未完成。当前安装版本不能宣称 Root-first 已验收。

## 2026-09-25 PRoot Root worker 生命周期补强

- Linux compatibility 后端现在把 `root` identity 转交给原生启动门禁；profile 未通过时，在执行隔离目录创建/清理前就拒绝。通过时只用固定 `su` helper 启动真实 UID-0 PRoot，不经过 App UID 的 `setuidgid` 降权；Root 专属的 Android host binds 仍是固定路径表。
- 为每个 Root PRoot session 在 App `noBackupFilesDir` 建独立 PID 标记，worker guard 建立私有进程组后写入组长 PID。显式停止/超时通过同一已验证 helper 只终止这个进程组；发送信号前还会核对目标 `/proc/<pid>/environ` 中的随机 session 标记，避免信任可被 worker 篡改的 PID 文件。普通 App session 的启动和停止路径未改变。
- 定向验证通过：`flutter test --no-pub test/linux_compatibility_backend_test.dart` 5 项；对应 Dart analyzer 无问题；`:app:testDebugUnitTest --tests io.henry.codex.CompatibilityRootLaunchScriptTest` 通过，覆盖固定 launcher、marker 路径校验、仅按匹配 session marker 终止进程组以及固定 Android bind 列表。该 Gradle 用例同时完成了 Flutter debug assemble、Kotlin 主代码和单测编译。
- 首次 Gradle 尝试被旧生成的 `flutter_build.d` 中残留的 `Y:\apps\codex\...` 绝对输出路径卡住；保留旧 depfile 备份后从当前 checkout 重新生成，之后同一 Gradle 定向测试通过。没有改 Gradle 配置或清理源代码。
- 本次没有启动 ADB、安装 APK 或调用手机上的 `su`，因此 Root PRoot 的真实 UID/context/capability、共享存储映射、KernelSU 高风险路径拒绝、并发及停止行为仍未通过真机验收。最近一次设备证据仍是 `review_needed`；未修改 KernelSU profile，也未写设备数据。

## 2026-09-25 中文 checkout 路径导致的 JNI Release 构建失败

- 复查 `:jni:buildCMakeDebug[arm64-v8a]` 的 CMake `android_gradle_build.json` 后确认，CMake 将中文 checkout 路径写成乱码；AGP 因而检查了一个不存在的 `libdartjni.so` 路径。实际 JNI 输出存在，源码与链接目标正常。
- 通过机器上已有的 `X:` ASCII checkout 别名执行同一 JNI 目标后，`BUILD SUCCESSFUL`；随后使用 `tools/build-android.ps1 -Mode release`（该脚本使用临时 ASCII `subst` 映射）完成完整 ARM64 Release 构建。没有改 Gradle/CMake 配置或移动源码。
- 只读 APK verifier 通过：`io.henry.codex`、version `1.0.0`、签名有效、5/5 ARM64 Codex/PRoot assets 齐全；APK 117,259,091 bytes，SHA-256 `b0ef88906f14500e9d2ac4641f8b8e266cce9e5c1c9d59c5fba031e92af00873`。它仍使用本机 Android debug certificate，不是商店签名。
- 当前源码验证通过：`CompatibilityRootLaunchScriptTest` 与 `RootProfileProbeTest` 的 Gradle 定向单测通过；`flutter test --no-pub test/linux_compatibility_backend_test.dart` 5 项通过。
- 真机 `6cb21282` 在线，但只读检查发现 `io.henry.codex` 的 MainActivity 处于前台（PID 2912），已安装 APK 的更新时间早于本次构建。未覆盖安装、重启 App 或触碰会话，以免打断用户当前操作；本次候选包尚未安装。
- Root PRoot 的 UID/context/capability、Android host bind 可见性、KernelSU 高风险路径拒绝、并发与停止仍需设备端验收。最近的 Root Profile 结果仍为 `review_needed`，需要在继续 Root worker 设备验收前解决专用 `codex_agent` profile 配置。

## 2026-09-25 PRoot guest 包安装入口与 PATH 对齐

- 将独立 App 的固定 guest-admin `sudo` shim 放入 APK assets，并由兼容 runtime 安全复制到 app-private guest home。`sudo apt install [--yes] PACKAGE...` 只接受经过字符集校验的包名；下载的 Debian `.deb` 经 `dpkg-deb --extract` 放入 `/home/codex/.local/codex-pkgs`，不改 finalized rootfs、不执行 maintainer scripts，也不调用 Android `su`。
- 安装入口要求 PRoot 内 guest UID 为 1000（App identity）；Root PRoot 的 guest UID 0 会被拒绝。判定使用 `/usr/bin/id -u`，不使用可被会话命令伪造的环境变量。
- PATH 优先级改成共享的固定目录构造：`/opt/node/bin`、已验证 Android native toolchain、guest-admin/package prefix、rootfs 系统目录；显式 one-shot 命令解析使用同一顺序，并能从绑定的 app-private home 找到包目录中的可执行文件。
- Android AGENTS 说明同步为实际能力与限制：不支持 `apt update`、升级/卸载、任意 `dpkg`；基于 rootfs 内固定 snapshot index，当前不解析缺失的传递依赖。
- 验证：`CompatibilityGuestAdminInstallerTest`、`CompatibilityCommandArgvTest` 定向 JVM 测试通过；`flutter test --no-pub test/linux_compatibility_backend_test.dart` 5 项通过；`android_codex_agents.dart` 定向 analyzer 无问题；新 shim 与复用的 Docker 测试脚本 `bash -n` 通过。Docker Engine pipe 不存在，因此完整 Debian 容器测试未启动。
- Release 已重建并只读验包：`io.henry.codex` / version `1.0.0`，117,263,254 bytes，SHA-256 `67375418f3675b7cc2ccf33a714483576c2c1a13d0445805586ea6a0a84ff282`；5/5 ARM64 native assets 齐全，`assets/codex-guest-admin/sudo` 存在（5,539 bytes），签名有效但仍是本机 Android debug certificate，不是商店签名。
- 真机未覆盖安装：此前只读检查显示应用会话在前台，因此保留当前设备状态。设备侧 `sudo apt install tree`、实际 PATH 命中、Root 会话拒绝、包目录运行及不同 session 同时安装冲突仍未验收；Root worker 仍受独立 KernelSU `codex_agent` profile 门禁限制。

## 2026-09-25 PRoot guest 依赖下载与包私有库加载

- `sudo apt install PACKAGE` 现使用 pinned Debian 索引的 `apt-get --download-only install`，获取目标包及 APT 判定缺失的必需依赖，再将所有 `.deb` 数据解包到 App 私有 package prefix；关闭 recommends，不执行 maintainer scripts，不写 finalized rootfs，不调用 Android `su`。状态只在所有归档解包成功后登记；下载或解包失败不会登记完成状态。
- PATH 命中的包前缀 ELF 命令经 guest `/usr/bin/env` 注入 package-prefix 内的 multiarch/通用 library path；此变量只在 guest 命令进程中设置，不写入 Android 主机上的 PRoot/Node 环境。绝对 package-prefix 命令路径也走同一启动包装。
- guest-admin asset 版本提升到 v2，并允许安装器识别/原子升级此前受信任的 v1 helper；未知现存 helper 仍拒绝覆盖。
- 验证通过：`CompatibilityGuestAdminInstallerTest`、`CompatibilityCommandArgvTest` 定向 JVM 用例；`flutter test --no-pub test/linux_compatibility_backend_test.dart` 5 项；`dart analyze` 目标 AGENTS 文件；Git Bash `bash -n` 两个 shell 脚本；Release 构建及 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`。最终 APK 为 117,263,762 bytes，SHA-256 `00697774782c56e957a59a9e6be1e14fb352ab94bd3a55a0063fd2a3ae87f794`，含版本 v2 helper asset 和 5/5 ARM64 runtime assets，签名有效但为本机 debug certificate。
- WSL 本地启动报错，Docker Engine 不可用；因此容器端真实 `apt-get`/`dpkg-deb` 行为没有通过验证，不能把多包提取称为容器验收通过。当前设备 `6cb21282` 的 `io.henry.codex/.MainActivity` 仍在前台，本轮未覆盖安装；真机 App-UID `sudo apt install tree`、依赖 ELF 启动及并发冲突仍待验证。Root worker 仍受专用 KernelSU profile 门禁限制。

## 2026-09-25 app-server user verification 能力边界核查

- 按当前 upstream app-server 文档复核后，`openai/userVerification` 仍属 experimental，能力只向支持的 TUI/Desktop 客户端广告，移动端明确需要单独 rollout；不是普通的 Android BiometricPrompt 按钮即可接入。
- 完整客户端需要本机 device-authenticated key 的 status/enroll/delete/verify/cancel 生命周期、challenge 签名 proof、请求取消和迟到 proof 丢弃。当前 Android app-server 客户端不广告此能力，未知请求保持不可批准/失败关闭；未伪装成已支持，也未扩大 APK 的权限面。
- 依据：[Codex app-server upstream README](https://github.com/openai/codex/blob/main/codex-rs/app-server/README.md)。此处依据是 2026-09-25 的 upstream `main` 文档，可能新于项目当前固定 CLI；只有上游提供移动端 rollout 后才应重新评估。

## 2026-09-25 root-first + PRoot 方案可行性与 UI 回归

- 结论：目标在技术上可实现，但不是“把 `su` 接到 PRoot 后就完成”。官方 Codex CLI 提供 Linux ARM64 standalone 发行物；PRoot 可承载 Linux userland，但 `--root-id` 只伪装 guest 身份。只有 KernelSU 真正以 UID 0 启动进程时，进程才有真实 Android root 权限；本仓库已有不降权的 Root PRoot launcher，不过当前设备的 dedicated KernelSU profile 探针仍是 `review_needed`，Root worker 被门禁拒绝。
- 安全边界是当前主要未完成项：2026-09-25 设备只读探测显示 `untrusted_app` 域 UID 0 无法满足全局读取；`ksu` 域虽可读，但也能通过写权限检查访问 boot block。因此不能把 unrestricted UID-0 Codex worker 与“中风险审批 / boot 仅插件写入”同时视为已实现。需要设备强制的专用 Enforcing Root Profile 限制核心路径，并让中高风险写经过独立 broker / 已审阅 KernelSU 插件；应用内命令字符串分类不能替代内核边界。
- 官方依据：[PRoot 手册](https://github.com/proot-me/proot/blob/master/doc/proot/manual.rst)、[KernelSU App Profile 文档](https://github.com/tiann/KernelSU/blob/main/website/docs/guide/app-profile.md)、[Codex CLI README](https://github.com/openai/codex/blob/main/README.md)。发行物可用不等于 Android 目标设备上的 app-server、更新器、PTY/信号、文件挂载和 Root profile 已验收。
- 修复三条过期 Flutter UI 测试：设置页先滚动到登录区再断言；Root 警示测试匹配当前文案；移除排查时临时加入的 `debugPrint`。定向测试 4 项通过，全量 `flutter test --no-pub` 214 项通过。Google Fonts 下载错误只产生测试日志，未使测试失败。

## 2026-09-25 Root Profile 探针权限集收紧

- Root Profile 探针除 CapEff/CapPrm/CapBnd 外，现在也读取并要求 CapInh、CapAmb 均为 0；Android `id -G` 必须精确为 `0 3003`，即 root 主组和网络 `inet` 组，缺失或额外组都会 fail closed。此前只检查组 3003 存在，可能让未审查的 Android 组或继承能力进入 Root Codex worker。
- 新增代表性全局读取样本：`/data/system/packages.xml`、`/data/user/0`、`/data/app`、`/system/build.prop`、`/vendor/build.prop`、`/proc/1/status`、`/sys/fs/selinux/enforce`；文件样本实际读取 1 字节后丢弃，目录样本枚举结果丢弃，不回传内容/名称。系统/vendor 配置与 SELinux enforce 节点必须有明确的不可写证据。字段缺失也会 fail closed。该结果是样本检查，不等于证明每一条 Android 路径都可读或安全。
- Settings 显示全局读取样本汇总、应用数据/安装目录、系统与 vendor 配置、proc 和 SELinux 节点证据；新增单测覆盖不可读样本、可写 SELinux 节点及缺失写拒绝证据。
- `ROOT_ACCESS_POLICY.md` 同步记录该 profile 合同，并继续区分 KernelSU `NO_NEW_PRIVS` 标志与 Linux `/proc` 位；后者仍是信息项，前者仍需用户在 KernelSU Manager 确认。
- `:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest` 通过（18 项），覆盖额外 Android 组、非空/缺失的继承与 ambient capability 拒绝、代表路径可读和 protected-write evidence 门禁。Android 16 shell 身份下的只读 smoke 确认 `toybox head -c 1` 与 `toybox ls -A` 可用（均 exit 0）；这不是 `codex_agent` profile 验证。Gradle 有既有 Kotlin/AGP 版本警告，无测试失败。
- 复核并更正早期 Root/PRoot 结论：Root identity 已由 `su → worker guard → PRoot` 不降 UID 启动，不应与 App identity 的 `setuidgid` 路径混为一谈。`:app:testDebugUnitTest --tests io.henry.codex.CompatibilityRootLaunchScriptTest --tests io.henry.codex.RootProfileProbeTest` 通过；这证明构造器/门禁行为，不证明设备上 Codex app-server 实际继承 UID 0。

- `flutter test --no-pub test/codex_session_client_test.dart test/kernelsu_plugin_settings_test.dart` 26 项通过；5 个相关 Dart 文件的定向 `dart analyze` 无问题。UI 显示新增 capabilities/groups 与权限样本，thread bootstrap 也注入同一 Root Profile 合同。
- 当前 Release APK 已重建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：117,273,698 bytes，SHA-256 `8d905bf1f6735f536f7cc6626ae584f85408bf592812aac16784b88e90e3153c`；`io.henry.codex`、5/5 ARM64 native assets 齐全，签名有效但仍为本机 debug certificate。
- 构建后先未安装 APK；后续在确认设备无活跃 Codex/PRoot worker 后完成覆盖安装，具体见本页后续 `Root Profile 探针 Release 真机部署与启动`。整个续进过程未调用设备 `su`、未修改 KernelSU 配置，也未启动真实会话。最近一次已记录的 Root Profile 状态仍是 `review_needed`；新版本设置页探针尚未在设备触发，Root→PRoot 身份与分层写入未验收。

## 2026-09-25 设备安装当前 Release 候选

- 设备 `6cb21282` / `24031PN0DC` 安装前仅有 `io.henry.codex` UI 进程，没有 Codex worker；执行 `adb install -r` 覆盖安装并保留应用数据，随后重新启动 `MainActivity`。
- APK verifier 与设备 `pm path` 后的 SHA-256 一致：`00697774782c56e957a59a9e6be1e14fb352ab94bd3a55a0063fd2a3ae87f794`；`versionName=1.0.0`、5/5 ARM64 native runtime assets 齐全、签名有效但为本机 Android debug certificate。
- 设备侧确认 MainActivity 已恢复到前台。此项只证明 APK 部署与启动，不代表 Codex turn、guest `sudo apt install` 或 Root Profile 通过；本轮未调用 `su`、启动 Codex worker、修改 KernelSU profile 或写系统路径。
- 核实 `io.henry.codex` 实际打包的 guest-admin 程序是 `apps/codex/android/app/src/main/assets/codex-guest-admin/sudo`（v2，`apt-get --download-only install` 并解包依赖）；`tools/android-local-runtime/rootfs/sudo` 是另一条旧 helper，不能用其 Docker 测试结果替代 App 资产验收。真机 App-UID/PRoot 安装依赖和依赖 ELF 启动仍待验证。

## 2026-09-25 Root Profile 样本探针 Release 重建（未安装）

- 为纳入全局读取样本和 fail-closed 写拒绝条件，重建 Release APK；Gradle Release 编译成功，用 APK verifier 确认签名有效、`io.henry.codex` 与 5/5 ARM64 native assets 完整。产物 117,273,698 bytes，SHA-256：`8d905bf1f6735f536f7cc6626ae584f85408bf592812aac16784b88e90e3153c`。
- 本轮未覆盖安装；只读 ADB 检查确认设备仍停留在 `io.henry.codex/.MainActivity`，进程列表只有 UI 进程，没有 Codex、PRoot 或 app-server 进程。新探针尚未经过设备侧执行，因此不能把本地单测/构建当作 Root Profile 真机验收。

## 2026-09-25 Root Profile 探针 Release 真机部署与启动（未探测 Root）

- 再次确认设备 `6cb21282` 在线且安装前只有 `io.henry.codex` UI 进程，没有 Codex/PRoot/app-server worker；使用 `adb install -r` 安装当前 Release，保留原 App 数据。
- `pm path` 指向设备上的 `base.apk`，设备端 SHA-256 与本机 APK 完全一致：`8d905bf1f6735f536f7cc6626ae584f85408bf592812aac16784b88e90e3153c`。`versionName=1.0.0`，启动后 `MainActivity` 回到前台；进程列表仍只有 UI 进程，最近 1200 条 AndroidRuntime error 过滤无输出。
- 这只验证了 APK 部署和启动，不代表 Root Profile 探针、Root worker、真实 Codex turn 或权限边界通过。本轮未点击会调用 `su` 的诊断操作，未修改 KernelSU Profile，未触碰会话数据。

## 2026-09-25 Root PRoot 启动时重验执行身份

- Root Profile 设置探针与后续会话启动是两次独立的 `su` 调用；现在 Root PRoot launcher 会在实际启动 shell 中、创建 session PID 标记之前，再核验四态 UID 全为 0、`u:r:codex_agent:s0` 域、SELinux Enforcing、Android groups 仅 `0`/`3003`，以及 capability mask `CapEff/Prm/Bnd=0x6`、`CapInh/Amb=0`。任何字段不匹配都会以 exit 126 终止，不创建标记、不启动 PRoot/Codex。
- 定向验证通过：`:app:testDebugUnitTest --tests io.henry.codex.CompatibilityRootLaunchScriptTest --tests io.henry.codex.RootProfileProbeTest`。覆盖脚本生成顺序和策略片段、Root Profile 探针解析/门禁；没有设备 Root worker 执行证据。
- 真机当时连接，但前台已切到其他应用；为避免抢占用户手机，本轮停止 UI 操作，没有触发 `su` 探针、修改 KernelSU Profile 或安装 APK。此前的临时 UI hierarchy 文件已确认不存在。
- 该复核缩小了“探针通过后到真实 worker 启动前 profile 变化”的窗口，但不构成 SELinux 完整路径矩阵或内核写隔离，也不弥补当前应用层 Root 写分类不能约束任意命令的问题。Root `codex_agent` profile、真实 app-server UID/context、分层写入与 KernelSU 插件设备验收仍未完成。
- 正式构建脚本 `tools/build-android.ps1 -Mode release` 使用临时 ASCII `SUBST` 路径后构建成功；直接从含中文的 C: 路径构建时，Flutter `gen_snapshot` 无法重读 `app.dill`，同一文件复制到 ASCII 临时路径后 AOT 成功。为恢复旧工作区盘符指向，仅删除了精确的生成文件 `apps/codex/build/app/intermediates/flutter/release/flutter_build.d`；构建脚本已自动处理此类旧盘符 depfile。
- 当前 Release APK 经 verifier 检查：`io.henry.codex` 1.0.0，116,593,703 bytes，SHA-256 `fca2b72750b3657cdc13ab4a5cdfb087d0dd679a36fc38143ac2a7c7f1bc732a`，5/5 ARM64 native assets 齐全、签名有效但仍使用本机 debug certificate。由于手机当时正由用户使用，本轮未安装此候选包。

## 2026-09-25 Root Profile App-originated 真机探测

- 真机 `6cb21282` 在线，`io.henry.codex/.MainActivity` 前台且没有 Codex/PRoot worker。进入设置后显式点击只读 `检查 KernelSU Root Profile`；探测完成，没有出现需要处理的 KernelSU 授权对话框，也没有启动 Root worker 或修改 profile/文件。
- App-originated 探测返回 `review_needed`：UID 0、`u:r:ksu:s0`、SELinux Enforcing；groups 白名单检查失败且缺少网络组 3003；CapEff/CapPrm/CapBnd 均为 `0000000400400022`，CapInh/CapAmb 为 0；全局读取样本通过、workspace 与 app runtime 可写；boot block 与 KernelSU 目录可写；`/system/build.prop` 不可写，Vendor 配置不可写，但 SELinux enforce 控制样本可写。该结果意味着当前默认 `ksu` Root Profile 具备超出目标边界的写能力，按设计必须继续拒绝 Root session。
- 设置页此前仅显示 `groups` 白名单布尔值，无法直接辨认实际 Android group ID。现在 Kotlin probe 将 `id -G` 的规范化数字列表一并返回，Flutter 诊断卡展示实际组；增加解析与 UI 定向断言。
- 仍未完成：该仓库没有可供设备安装、且已经在目标机验证的 `codex_agent` SELinux policy artifact；不能仅把 KernelSU context 手动改成 `u:r:codex_agent:s0` 来假装完成隔离。下一步需准备和审阅专用 enforcing policy，再由用户在 KernelSU Manager 中应用相应 Root Profile，复跑只读探测后才可启动 Root worker。
- 对照 `KernelSuPluginSettingsSection.initState()` 与 native `ProcessPluginKsudRootHelper.probe()` 发现，进入设置页此前会自动通过 `su` 执行 `ksud module list`，可能造成与 session 无关的 KernelSU 授权提示。现改成只显示“尚未检查”，仅用户点刷新时运行固定 capability probe；设置页重新打开不再调用该 root helper。
- 定向验证：Flutter `test/kernelsu_plugin_settings_test.dart` 2 项通过（包括设置页首次显示不调用插件 root probe、显式刷新仍调用）；Gradle `:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest` 18 项通过；`dart format` 对相关 3 个 Dart 文件检查无改动。Gradle 通过临时 `Y:` ASCII checkout 映射运行并已释放；设备临时 UI hierarchy 文件已移除。
- 此次源码修改尚未打入新的 Release APK，也未重新安装。真机仍只有 App UI 进程，无 Root Codex/PRoot worker；当前 KernelSU Root Profile 仍为 `review_needed`，不可启动 Root session。
- 架构审查确认一个此前未明确的冲突：KernelSU Root Profile 对同一已安装 App 的所有 `su` 子进程生效；Root Codex launcher 与 `ProcessPluginKsudRootHelper` 都属于 `io.henry.codex`。而当前门禁要求 agent 看不到可写的 KernelSU 模块目录，插件安装又必须写该目录。直接把 App profile 改为 `codex_agent`/`0x6` 会同时限制插件安装。因此不要求用户现在修改 Profile；`ROOT_ACCESS_POLICY.md` 已记录需要由固定可信 native supervisor 启动并降权 Codex child、另由固定 broker 执行用户批准的插件操作，且当前缺少的实现和设备验证项。

## 2026-09-25 KernelSU per-invocation SELinux context 接入

- 查到 KernelSU upstream 在 2026-08-22 合入 `su -Z/--context` 与 `--ksu-no-new-privs`（[PR #3653](https://github.com/tiann/KernelSU/pull/3653)）。它允许单次 `su` 为目标进程选择 SELinux context，同时仍使用 app-wide Root Profile 的 UID/GID/groups/capabilities；因此 worker 与固定插件 broker 不必再共享同一个 SELinux domain，但 capability 仍共享。
- `CompatibilityRootLaunchScript` 与只读 Root worker 探针现在共用固定参数：`-Z u:r:codex_agent:s0 --ksu-no-new-privs`。不接受调用者自选 context，不支持时也不退回普通 `su -c`；设备缺少对应 enforcing policy 时仍无法启动 Root worker。插件 broker 的调用路径没有改动。
- 增加回归用例验证探针和 session launch 使用同一 context、KSU no-new-privileges 标志及固定 helper。`CompatibilityRootLaunchScriptTest` 和 `RootProfileProbeTest` 经 Android Gradle `testDebugUnitTest` 通过，Kotlin 源码/测试编译成功。
- 随后正式 Release 构建成功；APK verifier 确认签名有效、5/5 ARM64 native assets 完整，大小 117,277,066 bytes，SHA-256 `5e24f5cb59edc4290b53294b43a791a8506afa91a6f99c0087a5c1a509eb32e8`，签名仍为本机 debug certificate。
- 真机安装前确认没有 Codex/PRoot/app-server worker，前台为 Twitter；使用 `adb install -r` 覆盖安装并保留 App 数据。设备 `base.apk` SHA-256 与候选包相同。没有启动 App、调用设备 `su` 或触发 KernelSU 授权，因此尚未证明设备 `su -Z` 参数可用。
- `codex_agent` policy 是否存在、Root PRoot worker 的 UID/context/capabilities 与 protected-write 样本仍未验证；该变化不等于 capability 分离或 medium-risk 写入的内核强制审批。

## 2026-09-25 设备侧 KernelSU `su` 参数与 context smoke

- 只读确认实体设备 `24031PN0DC` 在线，Android ADB root context 为 `u:r:ksu:s0`，当前前台是 Twitter；未启动 Android Codex、未触发 App-originated Root Profile 探针、未修改 KernelSU profile 或设备文件。
- 设备 `/system/bin/su -V` 返回 version code `32601`，`-h` 明确列出 `-Z/--context` 与 `--ksu-no-new-privs`。在 ADB root shell 下，用 `u:r:ksu:s0` 做临时子进程 smoke 成功；Linux `/proc/self/status` 的 `NoNewPrivs` 仍为 `0`，这与 KernelSU 自己的“禁止经 KernelSU 再提权”标志是不同机制，不能以该字段判定该选项失效。该 smoke 不代表 App UID 所应用的 KernelSU Root Profile 或 Codex worker 已通过。
- 同一设备上将临时子进程目标设为 `u:r:codex_agent:s0`，`su` 在 `setcontext` 阶段以 `EINVAL` 退出；因此当前系统策略并未接受该目标 context。结合仓库尚无专用 policy artifact，Root worker 仍保持 fail-closed，不安装或猜测一组未经验证的 SELinux 规则。
- 依据：[KernelSU v3.3.0 `su.rs`](https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/su.rs)（`-Z` 与 KernelSU no-new-privileges 实现）。剩余验收仍包括：经审阅的 enforcing policy、App-originated profile、真实 app-server/PRoot 进程身份，以及读写边界样本；本次只验证了设备侧命令行参数可见性和 context 拒绝结果。

## 2026-09-25 Root context failure 的可操作诊断

- `AndroidRootProfileProbe` 现在将固定 `codex_agent` context 的 `setcontext` 拒绝归类为 `context_unavailable`，不再与 KernelSU 未授权/普通 UID 失败混为一类；Android 设置页中英文提示明确要求先安装并启用经审阅的 enforcing policy，同时不回显原始 `su` 错误、不放宽 Root gate。
- 定向验证通过：Flutter `kernelsu_plugin_settings_test.dart` 3 项、Dart 对两个改动文件的 analyze 无问题；Android `:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest` 成功，覆盖真实错误样例分类与现有 Root profile gate。
- Gradle 从 ASCII junction 启动时在 `compileFlutterBuildDebug` 遇到已知 `File.exists()` parent-null 路径错误；改用临时 `Y:` SUBST checkout 后同一测试通过，映射已释放。Gradle 仅有既有 Kotlin/AGP/Gradle deprecation warnings。
- 当前手机由用户在前台使用，本轮未覆盖安装 APK 或抢占 UI。新诊断尚未在手机界面显示验收；当前设备上的 `codex_agent` context 仍被拒绝，Root worker 仍不可用。

## 2026-09-25 Root worker capability reducer 编译与定向验证

- 新增 immutable ARM64 worker guard 路径：仅 Root Codex supervisor 和显式只读 profile probe 会在 exec 子 shell 前移除 bounding/effective/permitted capability 中除 `CAP_DAC_OVERRIDE`、`CAP_DAC_READ_SEARCH`（mask `0x6`）之外的能力，清空 inheritable/ambient，并设置 Linux `NoNewPrivs=1`；独立 KernelSU plugin broker 模式不经过该 reducer。capability 不足或任一系统调用/回读校验失败时 fail closed，不启动 PRoot。
- Profile probe 改为观察 reducer 后的 child，并增加当前 app 进程 `/proc/<pid>/status` 读取样本；设置页新增 `profile_incompatible` 的可操作说明。`ROOT_ACCESS_POLICY.md` 明确了能力边界与未完成的产品契约。
- 使用 NDK `29.0.13846066` 编译 ARM64 PIE，ELF 类型/架构校验通过；产物 SHA-256 `7fab8fb669092d9963ea0cc44b8a7d4044a2d52ba30f9781032545eaceb94f05`。Flutter `kernelsu_plugin_settings_test.dart` 4 项通过；Android 定向 `CompatibilityRootLaunchScriptTest` + `RootProfileProbeTest` 共 25 项通过，Kotlin 与测试源码编译成功。
- 这不是设备侧 capability/SELinux 证明：未安装 APK、未触发 KernelSU 授权或真实 Root session。手机当时由用户在前台使用；`codex_agent` SELinux policy 仍缺失且设备此前拒绝该 context，Root worker 仍不可用。
- 产品适配限制：`UID 0 + mask 0x6` 是刻意收窄的中间实现，不具备完整日常 root tinkering 能力（例如 `CAP_CHOWN`、`CAP_FOWNER`、`CAP_SYS_ADMIN` 工作流不在此 capability set）。因此不能把这轮 reducer 称为 root-first 目标完成；下一步需先定义并验证“常规 root 操作可用、boot/system 危险写由 enforcing SELinux/固定 KernelSU broker 阻断”的实际能力合同。
- KernelSU 官方 Root Profile 文档确认可以给当前应用的 root context 添加自定义 SELinux type/enforcing 规则（示例的 `allow app1 * * *` 被明确标注为演示，不应照搬）。因此缺失的 `codex_agent` type 可能通过 App Root Profile 定义，并非天然必须单独安装 module；但设备实际规则矩阵尚未审阅，设置页现明确指向 KernelSU Manager 的 Android Codex Root Profile，并禁止以 `ksu`、Permissive 或 allow-all 替代。来源：[KernelSU App Profile](https://github.com/tiann/KernelSU/blob/main/website/docs/guide/app-profile.md)。
- 将上述设置说明纳入 Release 后重建成功；只读验包通过：`io.henry.codex` 1.0.0、117,283,842 bytes、SHA-256 `f3c5e088cb290486fd03d33a4ee58e297e96aca144ece7a91cd1b13fbfc18bcd`，5/5 ARM64 native assets 齐全、签名有效但仍是本机 debug certificate。未安装到手机。

## 2026-09-25 被动运行时探测移除 Root 副作用

- 定位到设置/前台恢复时潜在的重复 KernelSU 授权根因：被动 `probeCodexRuntime()` 会调用 `repairLegacyDirectModelCache()`；即使 `models_cache.json` 不存在，旧条件也会继续执行 `su -c rm -f`。同一探测还会尝试 Root-owned `arg0` 修复，并在 App UID runtime 不可用时自动探测 Root runtime。
- 被动 runtime probe 现仅检查 App UID Android-native slot，不调用 `su`，不触碰 Root-owned legacy 文件；`codex --version` 改用 app-private 随机临时 HOME/TMP，避免对持久登录目录产生副作用。Root slot 检查仅留在用户明确发起的运行时导入回退和“恢复 Android 原生运行时”操作中。缺少 App UID runtime 时设置页明确提示需要显式恢复 Root 副本。
- 同步增加中文诊断映射与设置页回归测试。Android `:app:testDebugUnitTest` 通过；Flutter `capability_refresh_test.dart`、`settings_model_catalog_test.dart`、`codex_native_runtime_updater_test.dart` 合计 12 项通过，新增诊断用例后 `settings_model_catalog_test.dart` 9 项再次通过。
- 定向 `dart analyze` 仍以既有未引用 `_CodexUsageCard` 警告退出（`ccpocket_local_settings.dart:1242`）；该声明未由本次改动引入。设备端“设置刷新不再触发 Root 授权”仍待 UI 验收。
- `local_session_auth_test.dart` 4 项通过，覆盖同一 session 复用 Root 批准、切换到新 session 后重新授权，以及 session 恢复时刷新 runtime probe。
- 使用 `tools/build-android.ps1 -Mode release` 构建并通过只读 APK verifier：`io.henry.codex` 1.0.0，117,283,998 bytes，SHA-256 `7480dd75518ba3b5e23ef1c5487a3d65fe846011e530fb17e3e48ce2e374cc4c`，签名有效但为本机 debug certificate，5/5 ARM64 native assets 齐全。实体设备 `6cb21282` 在线且没有 Codex/PRoot 进程；`adb install -r` 成功，设备 APK SHA-256 与构建产物一致。手机仍由 Twitter 占据前台，因此没有启动 App 或打断用户；安装已验证，运行时弹窗行为仍待设备 UI 验收。

## 2026-09-25 被动 Native toolchain 探测移除 Root 副作用

- 继续追查设置刷新仍可能弹 KernelSU 授权的问题：`_refreshLocalCapabilities()` 会触发 `NativeToolchainProbe`；其 30 秒缓存过期后，旧 `probeUncached()` 通过 `su` 对工具链全量做 SHA-256 校验，并递归 `chcon` 修复标签。因此即使 Codex runtime 探测已改为 App UID，工具链状态刷新仍会碰 Root。
- 被动工具链探测现在仅以 App UID 读取 manifest 并启动工具版本入口，返回 `available`，UI 明确与导入时完成的 `verified` 区分；不再调用 `su`、全量哈希校验或修复标签。用户明确导入时，固定 Root installer 仍会对 staging 和激活目录执行内容哈希/版本校验与标签设置，导入返回 `verified`，且不再紧接着重复触发完整 Root probe。
- 更新 Root 操作约定及 Flutter probe 注释。六个相关 Flutter 测试文件联合回归 25 项通过，覆盖被动能力刷新、KernelSU 设置首次显示不触发 Root 探测、session Root 批准复用及 native toolchain 的 `available`/`verified` 区分；Android Gradle `:app:testDebugUnitTest` 通过，且重新编译了 Kotlin 主代码。静态复核设置刷新链路中的 App host、runtime、toolchain 与 PRoot 探测；KernelSU 设置 `initState` 为空，Root Profile 检查仅由显式点击触发。首轮 Gradle 发现缺少 `java.nio.file.Files` 导入，补齐后复跑成功。设备侧设置页是否不再出现授权弹窗仍待实际启动 App 后验证；本轮没有抢占手机前台。
- 正式 Release 构建与只读 verifier 通过：`io.henry.codex` 1.0.0，117,283,266 bytes，SHA-256 `363db1c250b643ba3ce57760c2447133ab960ac408789ab605841204b881fb57`，5/5 ARM64 native assets 齐全，签名有效但仍为本机 debug certificate。重新确认手机前台为 Twitter 且没有 Codex/PRoot worker 后，`adb install -r` 覆盖安装成功；设备 `base.apk` SHA-256 与产物一致。没有启动 App，设置页弹窗行为仍待用户空闲时进行真机 UI 验收。

## 2026-09-25 CLI 命令分发回归检查

- 接续“输入 CLI 命令无反馈”问题，复查本地 slash 命令、`/version` 与 `/cli <args>` 的实际分发：本地命令写入 transcript；CLI one-shot 执行显示准备/运行状态及输出或错误；参数按 argv 解析，不经过 shell。`codex_cli_arguments_test.dart` 与 `local_session_conversation_test.dart` 共 19 项通过，覆盖 `/status`、`/version`、带引号参数的 `/cli debug ...` 和命令弹出菜单。测试期间 Google Fonts 外网下载报错只产生日志，未导致测试失败。
- 范围限制仍在：测试使用 mock executor，不等同于实体设备 CLI 执行验收；MCP/plugin 配置变更目前明确显示“未接入”提示并拒绝写入隔离的一次性 `CODEX_HOME`，后续仍需基于 app-server/会话配置适配，而不是声称所有上游 CLI 命令已支持。

## 2026-09-25 Root Profile 块设备写权限探针扩展

- 真机 ADB shell 只读确认 `24031PN0DC` 的 `/dev/block/by-name` 暴露 `boot_a`、`boot_b`、`vendor_boot_a/b`、`vbmeta_a/b`、`super` 等分区别名；用 Android shell 的 `-b` 检查对标准块设备别名目录计得 174 个匹配项。这只确认当前设备路径和 shell 检查语法，不是 KernelSU Root context 的访问结果。
- Root Profile Settings 探针现在枚举 `/dev/block/*`、`by-name`、`bootdevice/by-name`、`mapper` 下可见块设备别名，要求目录枚举完整、存在别名且每个 `test -w` 均失败；仅返回枚举完成标志与数量，不返回分区名称。解析器对缺失、格式错误或与计数矛盾的字段 fail closed。
- 新增 `codex_protected_write_samples_passed()` 共享检查，覆盖可见块别名、boot_a、system/vendor 配置、SELinux enforce 控制和存在的 KernelSU/module 根目录；它同时用于 Settings 探针与 PRoot 启动前的即时重检，Root launcher 在检查失败时不写 PID marker、不启动 PRoot。仍是只读 access 检查，不尝试打开写描述符或执行任何写操作。
- 设置诊断卡展示枚举是否完整、别名总数、可写数及受保护写样本汇总状态。增加 Kotlin fail-closed、互相矛盾计数、launch preflight 断言和 Flutter 显示回归。
- 验证：Android 定向 Gradle `:app:testDebugUnitTest --tests io.henry.codex.RootProfileProbeTest --tests io.henry.codex.CompatibilityRootLaunchScriptTest` 成功；Flutter `kernelsu_plugin_settings_test.dart` 4 项通过。首轮 Gradle 测试发现解析器没有把可写计数与汇总布尔值交叉校验，修正后全数通过。
- 限制：当前设备的 `codex_agent` context 仍被 KernelSU 拒绝，尚未运行 App-originated Root 版枚举；`test -w` 是访问权限检查，并不证明对所有替代路径、设备节点或内核操作都有拒绝效果。Root worker 的 `0x6` 能力集仍不是用户要求的常规 Root tinkering 契约；本次没有修改 KernelSU Profile。
- Release 验证/部署：`tools/build-android.ps1 -Mode release` 成功。只读 verifier 确认 `io.henry.codex` 1.0.0、117,286,318 bytes、SHA-256 `b1ed01e758dc1f151d3801617a4756e73e2b4e497440a8bd041465a2ac7a7d81`、5/5 ARM64 native assets、签名有效但使用本机 debug certificate。安装前设备前台为 Twitter 且没有 Codex/PRoot worker；`adb install -r` 成功，设备 `base.apk` SHA-256 与候选包一致。没有启动 App或触发 Root 授权，因此新诊断 UI 和真实 Root preflight 尚未在设备运行态验收。

## 2026-09-25 KernelSU Root Profile 可行性与设备策略证据

- 只读 ADB 复核真机 Android 16 / SDK 36、SELinux `Enforcing`、`su -V=32601`；当前 ADB shell 是 UID 0、`u:r:ksu:s0`，不等同于 App 的 Root Profile 或 Codex worker。`/data/adb/ksud profile get-sepolicy io.henry.codex` 返回文件不存在；没有写入或应用任何策略。
- 解析 `/dev/block` 下 236 个物理块设备节点，观察到 29 种 SELinux type；`boot_a`、`boot_b`、`vendor_boot_a`/`b` 归入 `boot_block_device`，`super` 为 `super_block_device`，`vbmeta_a` 为 `vendor_custom_ab_block_device`。这验证了设备间/分区间标签并不统一；探针依旧是 `test -w` 访问检查，不是写入尝试。
- 设备端 `/data/adb/ksud sepolicy check` 对一个 `codex_agent` 定义/enforce/`mlstrustedsubject` 与三种已观察 block-device type 的 `deny` 语句返回 exit 0。对照 upstream `ksud` 源码确认该子命令仅执行严格文本解析，不会应用规则、解析有效权限或证明访问被拒；因此该结果只算语法 smoke，不构成可部署策略或安全验收。
- upstream 源码还确认 `deny` 是清除匹配 AVTAB allow 位，而不是可凌驾其他直接/attribute-derived 授权的通用 `neverallow`。`ksud profile set-sepolicy` 会先持久化文本再调用非严格 live-patch，CLI 返回成功不能证明规则完整生效。相关边界和官方源码链接已补到 `ROOT_ACCESS_POLICY.md`，避免 Settings 自动应用未经设备验证的策略。
- 结论：KernelSU 支持 UID-0 子进程和自定义 enforcing domain，Root-first 运行在原理上可行；但当前手机仍拒绝 `codex_agent` context，且 worker 只有 `0x6` capabilities，既未完成目标日常 Root 能力，也没有验证高风险写入边界。下一步需要经审阅的 Root Profile 在 KernelSU Manager 中明确应用，再由 App-originated probe 和真实 Codex worker 验证；本轮没有启动 App、抢占手机前台、调用 `su` 或修改 profile。

## 2026-09-25 第三方模型错误信息凭据脱敏

- 检查 provider 会话链路后发现，非 2xx HTTP 响应会把服务端原始 body 显示到会话错误中；若服务端回显 Authorization/API key，可能泄漏已保存的凭据。现在先精确替换当前 provider key，再屏蔽错误 body 中的 Bearer token；OpenAI-compatible SSE `error` event 也会作为可重试的 provider failure 显示，而不是静默结束成空回复。
- provider endpoint 现在拒绝 URL userinfo、query 和 fragment，避免把凭据意外放进会在设置页显示或错误中暴露的 URL；基地址仍支持追加 `/v1/chat/completions`，完整 endpoint 与 `/v1` 基址的路径映射保持不变。
- 定向 Flutter 用例覆盖原有 SSE 流式文本、图片 content 映射、usage 和 idle 状态，以及 HTTP/SSE 错误回显 secret 的脱敏、含凭据/查询参数/fragment 的 URL 拒绝；`dart analyze` 对两个生产文件和该测试文件无问题。local fixture 仅证明协议映射，不等于真实第三方服务商联调。
- 本地测试监听端口 55000/55001 已登记并释放；同一测试进程 PID 42884，绑定 `127.0.0.1`，结束后确认没有 LISTEN socket（仅短暂 `TIME_WAIT`）。

## 2026-09-25 同 ID 第三方模型配置编辑生效

- 定位到从设置编辑当前 provider 时，provider ID 保持不变，但会话页仅比较 ID，导致改过的地址、模型、名称或 API key 被误判成原配置，空闲 session 仍继续使用旧 transport。
- 切换判断现比较完整配置字段；任一字段变化都走已有的 provider transport 重建路径，完全相同的配置仍不触发重建。turn 正在运行时仍保留现有行为：提示先停止或等待，不在请求中途替换 transport。
- 新增配置相等性单测，覆盖相同配置、同 ID 下分别编辑名称/地址/模型/API key，以及 null；`flutter test --no-pub test/custom_provider_config_test.dart` 通过，domain 与新测试文件的 `dart analyze` 无问题。
- 对包含整个大型 `main.dart` 的 analyzer 检查仍返回该文件既有的 18 条 lint/info（未引用成员、冗余空断言及 async context 等），本次没有触碰这些无关项；新改动本身无 analyzer 诊断。没有在真机或真实 provider 服务上验证此设置交互。

## 2026-09-25 第三方模型失败重试复用待发送消息

- 复核 HTTP/SSE provider 请求生命周期发现：请求失败后客户端保留了末尾 user message；UI 的“重试”再次发送同一文本时，客户端会把它重复追加到上下文，并再发一次 user transcript event，导致服务端上下文和可见记录都可能重复。
- 现在当下一次请求与末尾尚未完成的 user content 完全相同时，复用既有 pending message 且不重复发用户事件；前一轮已经有 assistant 回复后，即使文本相同也会正常作为新消息追加。比较包含图片 data URL 内容。
- 新本地 HTTP 回归用例先返回 503、随后成功；断言两次请求中的 messages 都只含同一个 user prompt、UI user event 只发一次且成功重试会流出回复。与第三方 provider 配置相等测试一并运行，5 项全部通过；相关四个 Dart 文件定向 analyzer 无问题。没有连接真实 provider 或在设备上验收。
- 本地 fixture 端口 55002 已登记并释放；测试 listener 为 `flutter_tester` PID 5588。结束后无 TCP LISTEN/UDP endpoint，仅存在连接的 `TIME_WAIT` 记录。

## 2026-09-25 Codex session 重试去重并保留图片

- 将重试链路继续追到 `CodexSessionClient` 与 session transcript：app-server 每次重新发送都会再发一次 user event，UI 会重复渲染失败提示词。现在 retry event 与原提示匹配时不再重复插入气泡；新一轮用户输入不受影响。
- retry state 现在暂存原始图片附件；网络失败后可在同一会话里连同文本/图片重发，image-only 请求也不会因空文本被 retry guard 拒绝。新会话、显式停止及客户端退出会释放这份临时附件状态；附件仍不落盘到历史记录。
- 同一回归又确认 CC Pocket composer 原先仅在文本非空时启用发送按钮，空文本的图片附件因此无法提交。修正在 Codex 实际依赖的 `packages/ccpocket_ui` `ChatInputBar`：附件存在时启用发送，保留独立的文本编辑/换行状态。
- 扩展 app-server widget 回归：本地 picker fixture 返回项目内有效 PNG，分别覆盖“文本+图片重试”和“仅图片首发失败后重试”；确认发送按钮启用、同一 session thread、只渲染一条 user bubble，且原图 data URL 在每次 `turn/start` input 中保留。两个定向 Flutter widget 用例均通过；格式检查通过；测试/provider Dart 文件 analyzer 无问题。
- 随后整组运行 `flutter test --no-pub test/local_session_conversation_test.dart`，12 项全通过，涵盖启动、审批、排队、停止后续发、session 恢复/切换时保留后台 turn、CLI 命令、文本/图片重试与 composer 交互。
- 对整个大型 `main.dart` 的 analyzer 仍报告同样 18 条既存 lint/info（unused members、冗余空断言、async context 等），本轮没有引入新的诊断类别或触碰无关代码。测试日志里的 Google Fonts 外网获取错误是已知网络噪声，不影响该用例通过。
- 真机 UI 与真实 Codex/provider 网络重试尚未执行；本轮验证的是 Flutter widget + fake app-server 协议路径。

## 2026-09-25 Android Root 指引的实际注入边界核对

- 复核 `CodexSessionClient` 的 `thread/start`/`thread/resume` 后，确认真正进入 interactive app-server 对话的是 `android_codex_agents.dart` 中的 `developerInstructions`；线程指令契约已有协议测试。`tools/android-local-runtime/skills/AGENTS.md` 并没有被 rootfs builder 或 active app 的 session-home seeding 安装到 `/home/codex/.codex/AGENTS.md`。
- 因此修正该 Markdown 顶部的过期声明：它是独立 PRoot 操作参考，不能宣称独立 CLI 进程自动读取。Codex interactive turns 当前由 Dart 指令注入；直接启动的额外 CLI/agent 子进程是否获得同一指引尚未实现/验证。
- 这次只校准文档和当前代码事实，没有改 Root Profile、rootfs 或设备状态。下一步若要让 PRoot 中的独立 Codex CLI 也读取规则，需在各 session `CODEX_HOME` 建立不会覆盖用户文件的受管指引，并加 JVM 安装/override 测试。

## 2026-09-25 per-session CODEX_HOME 指引注入与兼容路径修复

- 复核当前源码时发现，较早的进度记录曾声称 PRoot Codex home 已安装 `AGENTS.md`，但当前 builder 和 APK source set 并没有该安装路径；上一条“需 seed 指引”的记录才符合当时实际状态。现在 Android app 直接打包 canonical `tools/android-local-runtime/skills/AGENTS.md`，并在 native 与 PRoot session home 准备阶段只在 `CODEX_HOME/AGENTS.md` 缺失时创建；已有用户文件或符号链接均不覆盖。app-server 的 `developerInstructions` 仍单独保留。
- 首个 JVM 回归测试同时发现 `CodexSessionHome.resolveGuest` 默认前缀是 `/home/codex/`，而 UI 实际为每个 compatibility session 传 `/home/codex/sessions/<id>`。默认检查因此静默返回 null，导致兼容 session home 准备及其 model-cache 路径查询被跳过。已把 compatibility guest-home 默认值与真实 session 路径对齐，并加入缓存路径断言。
- `:app:testDebugUnitTest --tests io.henry.codex.CodexSessionHomeTest` 通过；覆盖 native/PRoot 两种 session home 指引 seed、现存自定义 AGENTS 文件保留、共享 home 不被写入，以及 compatibility model-cache 路径解析。Gradle 仅报告既有 Kotlin/AGP/Flutter 版本 deprecation 警告。
- Android Gradle merge 输出已包含根级 `AGENTS.md` asset（7355 bytes）；尚需检查 APK 条目和 Release 构建。未安装到手机；真实 CLI 对该 global instructions 的读取及 Root 执行仍需设备验证。

### Release 与整组 Android JVM 回归

- `tools/build-android.ps1 -Mode release` 成功。APK verifier 确认包名 `io.henry.codex`、版本 `1.0.0`、5/5 ARM64 Codex native assets 齐全、签名有效但为本机 debug certificate；大小 117,292,290 bytes，SHA-256 `4b2ee35ead28ae61210540b5e313567936925e5f37fdd4878cadef240b361f1e`。
- 直接从 Release APK 读取 `assets/AGENTS.md`，其 7,355 bytes 与 canonical `tools/android-local-runtime/skills/AGENTS.md` 的 SHA-256 均为 `e2786e51f09b50d9f06fd45f55d5b3ce0ed530b8317741f09e0f9f9c940be127`。全量 `:app:testDebugUnitTest` 87 项通过，0 failures/errors/skips。
- 部署前只读检查发现当前 ADB server 已按端口表占用 5037，但 `adb devices -l` 没有连接设备；因此未尝试安装或启动 APK。设备端对真实 CLI global AGENTS 读取、session-home 准备和 Root worker 的验证仍未完成。

## 2026-09-25 Root / PRoot 设置能力文案校准

- 复核 Root Profile 失败证据后发现，执行身份选择页把“PRoot 也会以真实 Android UID 0 启动”写成了无条件事实，容易把 guest root 与 KernelSU profile 授权混淆。现改为明确说明：PRoot guest root 本身不授予 Android root；Root identity 只有在专用 profile 和 SELinux 检查通过后才请求/启动 UID 0。
- 同时把 Root 设置摘要从“无内核写隔离”改为“应用审批不是完整内核写入沙箱”，准确区分 app-side approval 与 SELinux/capability 边界；这不宣称当前设备已具备可用 profile。
- `dart format` 无需改动格式；`flutter test --no-pub test/root_security_notice_settings_test.dart` 通过。当前可执行的 ADB 工具返回空设备列表，因此没有应用或修改手机 KernelSU 配置；真机 Root Profile 和 PRoot UID 0 仍未验证。

## 2026-09-25 KernelSU 控制状态写入 fail-closed

- Root 写入分类原先只把 `/data/adb/ksu/modules`、`modules_update` 和 `bin` 送入插件流程；其他 `/data/adb/ksu/**` 状态（包括 profile/allowlist 一类控制数据）会落入普通中风险审批，存在绕开 KernelSU Manager/profile 管理流程的路径。首次修复后又发现命令预检的 protected-path 列表漏掉这类路径，解释器命令会退回普通审批；现已统一纳入拒绝路径。
- 现在这些未明确支持的 KernelSU 控制状态默认 `blocked/denied`；文件/权限请求与显式命令目标使用同一策略，已支持的 module/bin 目录仍走 typed KernelSU plugin，raw block/boot 分区继续拒绝。同步更新 Codex 的 Android/PRoot 操作指引与 Root 策略文档，说明 profile/control state 由 KernelSU Manager 管理。
- 为避免错误暗示，设置里的 PRoot 文案也明确 guest root 不等于 Android root；只有 Root identity 的专用 KernelSU profile 与 SELinux 检查通过后才启动 UID 0，并说明 app-side 审批不是内核沙箱。
- 验证：Root path policy、设置安全提示和 session 指令协议定向 Flutter 测试 35 项通过；新增命令预检回归后 Root path policy 11 项再次通过；相关 Dart analyzer 检查无问题。ADB 工具正常但设备列表为空；未修改设备 profile。该分类仍是 app-side fail-closed，不能约束任意 UID-0 子进程，真机 SELinux 强制边界仍未验证。
- 随后重新构建 `tools/build-android.ps1 -Mode release` 并运行 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，117,295,030 bytes，SHA-256 `0398bb2d8cfd422eeccc8db372fe410bce3ae270b75de73d9388c675a1e19e15`，5/5 ARM64 native assets 齐全、签名校验通过但证书仍为本机 debug certificate。ADB 设备列表为空，未安装或启动；这只是当前 Release 候选，不是 Root 真机验收。

## 2026-09-25 首轮 native `try_lock()` 失败回退

- 处理 Android-native app-server 通过 runtime probe、但新 thread 的首轮 `turn/start` 因 `try_lock() not supported` 失败的情形。仅在没有初始/恢复历史、transcript 中没有既有对话内容、且 Linux Compatibility 已验证可用时，才透明切换并重试首条 turn；重放时保留原文本和内存图片附件，并过滤兼容端重复发出的 user event，避免重复气泡。
- 已恢复/非空会话不会跨 native 与 PRoot 的独立 `CODEX_HOME`/SQLite 自动迁移；新增 widget 回归确认新会话可成功回退、文本与图片均重送且只显示一条 user bubble，同时恢复会话仍留在 native backend、compatibility backend 不启动且历史回复保留。
- `flutter test --no-pub test/local_session_conversation_test.dart` 14 项通过；`dart analyze test/local_session_conversation_test.dart` 无问题。`main.dart` 定向 CLI analyzer 的 18 条 warning/info 均位于既有代码区，不涉及新增回退逻辑；Flutter LSP analyzer 在当前中文 checkout 路径崩溃，未将其当作源码失败。
- 已用 `tools/build-android.ps1 -Mode release` 重建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，117,297,930 bytes，SHA-256 `3cfa9b6edaee1547dba21d6174a9564460ec21fc31861b175488dfe4b5fada91`，5/5 ARM64 native assets 齐全，签名有效但仍为 debug certificate。ADB 设备列表为空，本轮未安装、启动或进行真机 Codex turn 验收。

## 2026-09-25 KernelSU 控制文件的 Python 写模式预检

- 新增用例先复现一个策略缺口：Python `open(..., "wb")`、追加/排他创建及读写模式会被旧正则当作普通 Root 命令审批，未能把 `/data/adb/ksu/**` 控制状态送入 fail-closed 拒绝路径。
- `_hasExplicitWriteIntent` 现在识别 Python 二进制/追加/排他/`+` 打开模式、`Path.open`、常见 `chmod/chown`、目录与链接操作、`shutil` copy/move 操作，以及 `O_CREAT/O_APPEND` 等标志。对明确写入 KernelSU profile/allowlist/control state 的命令仍拒绝；普通 Python 读取没有被改成敏感路径 denylist。
- `root_access_policy_test.dart` 11 项通过，新增模式覆盖；Root session UI 拒绝测试通过；生产策略与测试文件 `dart analyze` 无问题。Flutter 测试日志仍会出现 Google Fonts 外网获取失败，但用例通过。
- 这是 argv 文本上的 app-layer preflight，不是任意解释器/动态命令的完整静态分析，也不是内核写隔离；混淆/动态拼接仍须由有效 SELinux domain 约束。Release APK 重新构建并通过 verifier：`io.henry.codex` 1.0.0，117,298,238 bytes，SHA-256 `6a4f421d0d1fd6c7ef340503e962e3077b74fc7253e13290a77ba866ce970527`，5/5 ARM64 native assets，签名有效但为 debug certificate。ADB 设备列表为空，未安装或进行设备级 Root 测试。

## 2026-09-25 PRoot OTA 接受分块清单并恢复离线 JVM 测试

- OTA 清单下载原先要求 HTTP `Content-Length` 必须已知，合法的 chunked/未知长度响应会被拒绝。现在允许 `-1`（长度未知），同时保留流式读取的 64 KiB 上限、Ed25519 签名校验和 artifact digest 校验；0、其他负数及超限长度仍拒绝。
- 当前机器的 `apps/mobile/android/local.properties` 指向已不存在的 C 盘 rootfs/native staging 文件，导致 Gradle 在普通 JVM 单测阶段也强制创建大型 runtime Sync 任务。现在仅 APK/安装/Build 类任务同步并强制校验这些资产；单元测试仍编译真实 Kotlin 控制面但不打包 runtime。测试任务识别覆盖 assemble、bundle、package、install、connected 和 build 前缀。
- 使用现有 pubspec.lock 离线恢复 Flutter 包配置（未升级依赖），`:app:testDebugUnitTest --tests com.k9i.ccpocket.runtime.RuntimeOtaManifestTest` 通过，覆盖未知长度、合法边界、空/非法/超限长度。Gradle 首次全量运行 2m08s，随后回归 15s。
- OTA 下载/续传、签名到 RootfsArchiveInstaller 激活的端到端流程尚无当前 host/JVM 集成测试；本次不声称已验证网络更新或设备安装。APK 打包仍被本机缺失的 runtime 输入阻止；`adb devices -l` 当前无真机。

## 2026-09-25 Root PRoot 日常能力基线扩展

- 将固定 Root Codex worker 的 capability 合同从中间态 `0x6` 扩展为 `0xcf`：仅保留 `CAP_CHOWN`、`CAP_DAC_OVERRIDE`、`CAP_DAC_READ_SEARCH`、`CAP_FOWNER`、`CAP_SETGID`、`CAP_SETUID`，并继续清空 inheritable/ambient、移除 `CAP_SETPCAP` 和其余 bounding capabilities、设置 Linux `NoNewPrivs=1`。旧 `0x6` profile 继续 fail-closed；额外 capability 也不接受。明确不包含 `CAP_SYS_ADMIN`、`CAP_SYS_MODULE`、`CAP_SYS_BOOT`、`CAP_SYS_RAWIO`。
- 同步更新 Android worker guard、Settings profile parser 与启动前 shell preflight、Root capability 诊断、Android Codex `AGENTS.md` 以及 Root policy/PRoot 文档。日常能力合同本身不构成高危写入隔离；Root 仍要求专用 SELinux Enforcing domain，并需真实设备证明普通路径可写、boot/system 等目标被拒。没有自动应用 KernelSU policy。
- NDK 29 重新编译 ARM64 guard，ELF64/AArch64/PIE 校验通过；源码资源、manifest 和 Release APK 内 guard 的 SHA-256 均为 `b2a062ab14bc688296d9c78388793069cb532a8a44b77bbd585d437615f3b891`。修正构建脚本在 Git Bash 缺少 `shasum` 时不能生成 manifest 的问题，优先使用 `sha256sum` 并兼容 `shasum`。
- Flutter `kernelsu_plugin_settings_test.dart` 4 项通过；Android `RootProfileProbeTest` 与 `CompatibilityRootLaunchScriptTest` 定向测试通过（经临时 Y: 映射避开中文 checkout 的 Flutter/Gradle NPE）。`tools/build-android.ps1 -Mode release` 成功；APK verifier 确认 `io.henry.codex` 1.0.0、117,298,850 bytes、SHA-256 `123772462927c4f65b33b3284cba3d3d7ede4ccfae1da77d4deddb29be181f84`、5/5 ARM64 native assets 齐全、签名有效但仍是本机 debug certificate；APK 内 `assets/AGENTS.md` 与 canonical 文件 hash 一致。
- 当前 `adb devices -l` 没有设备；本轮未安装、启动 App、调用 `su` 或改写 KernelSU profile。该 capability 合同尚未在手机运行；当前设备是否接受 `codex_agent` context、SELinux policy 是否确实阻断保护目标、真实 Root Codex/PRoot 的日常文件操作均仍待真机验收，因此整体 Root-first 目标尚未完成。

## 2026-09-25 App-UID PRoot Android/Bionic 动态加载路径

- 对照 native-toolchain `0.7.0` 中的 `node`、`git`、`python` ELF 头确认它们都请求 `/system/bin/linker64`，并动态依赖 Android Bionic system libraries；`python` 的 `$ORIGIN/../lib` 依赖也在工具包内。此前 App-UID PRoot 只 bind native-toolchain 目录，没把 `/system`/`/apex` 映射进 guest；Root PRoot 已通过其固定 Android host map 带入这些 OS 路径。因此 App-UID guest 可能“PATH 找到工具但 exec 时找不到 Bionic loader”。
- App-UID PRoot 现仅 bind 存在的 `/system` 与 `/apex`，不改变 Android UID、工具目录权限或 SELinux 判定；Root identity 使用的原固定 host bind 列表保持不变。同步更新 Codex 操作指南和 compatibility capability 表，并加纯 Kotlin 路径映射测试。
- `CompatibilityCommandArgvTest`、`RootProfileProbeTest`、`CompatibilityRootLaunchScriptTest` 定向 JVM 回归通过；此前本轮 Flutter KernelSU 设置 4 项通过且相关 Dart analyze 无问题。Release APK 成功重建并通过 verifier：`io.henry.codex` 1.0.0，117,299,082 bytes，SHA-256 `5cecf027d9c7f453a665bee6e4a2a3ad32b1e61d9702e2d2786464fb59eb3cca`，5/5 ARM64 native assets 齐全，签名有效但为本机 debug certificate。APK 中 worker guard 与 manifest SHA-256 相同；打包的 `assets/AGENTS.md` 与 canonical 源文件 SHA-256 同为 `7365db9ecdeebf4fbbe41df538f223fdffd3940262621c822e480158f687167e`。
- 当前 ADB 设备列表为空，App-UID PRoot 中 `git/node/npm/npx/python` 的实际动态加载/命令 smoke 仍未验证；本修改是基于 ELF interpreter 和构造参数的根因修复，不等于设备端通过。PRoot 不是安全沙箱，绑定路径仍受实际 App UID、DAC 与 SELinux 约束。

## 2026-09-25 Root-first PRoot 路线可行性评估

- 结论：在已 Root、KernelSU 可为本 App 授权并允许专用 enforcing SELinux domain 的具体设备上，技术上可行；这不是“PRoot 自带 root”，而是 KernelSU `su` 先以实际 UID 0/受控 capability 与 `codex_agent` context 启动 supervisor，再由其启动 PRoot/Codex。PRoot 只负责 Linux 用户空间兼容与路径映射，不会自行提权，也不是安全边界。KernelSU 官方 Root Profile 支持 UID/GID/groups、capabilities 和 SELinux context/rules；上游 Codex 提供 Linux ARM64 musl package。Android 上通过 PRoot 执行该上游产物属于合理但尚未设备验证的兼容性推断。
- 当前 Android Root PRoot 已有固定 `su -Z u:r:codex_agent:s0 --ksu-no-new-privs` 启动路径与 APK 内不可变 worker guard；Codex 子进程能力被收窄到 `0xcf`，并设置 Linux `NoNewPrivs=1`。因此它可以是实际 UID 0 的受限 Root worker，但不能等同于 unrestricted `u:r:ksu:s0` / full-capability shell。是否覆盖日常全局读取与普通文件修改，必须由目标设备上实际 SELinux policy 和路径测试证明。
- 关键缺口不是 PRoot，而是安全策略：目前 app 的路径分类/命令预检只能提供 app-layer approval，无法约束任意或混淆后的 Root 子进程。若要求 boot/block-device、系统关键状态只能经验证后由 KernelSU 插件修改，必须由 enforcing `codex_agent` policy 在内核访问控制层拒绝这些目标的直接写入；插件通道需单独验证，并确保 Root worker 无法借其他路径绕过。不能用 permissive、`u:r:ksu:s0` 或 `allow *` 达成便利性。Android 的 SELinux、FUSE、加密/解锁状态和设备挂载差异也意味着“任何设备上的每个路径都可读”无法作普遍保证，只能对指定设备与可见文件系统建立实测范围。
- 本次仅做源码/官方机制评估和只读检查，没有改动 KernelSU 设置或设备。当前主机 ADB server 在登记的 5037 端口运行，但 `adb devices -l` 返回空列表；这只代表本轮没有可用的 ADB 设备通道，不代表设备本体状态。Root PRoot 的 UID/context/capability、日常读写、boot/block 写拒绝、插件暂存/回滚和进程停止行为仍待真机验收。
- 架构选择暂不改变：Android/Bionic 仍为默认，官方 Linux ARM64 musl Codex + Root PRoot 可作为更新更直接的兼容执行路径；只有真机确认官方 app-server、会话工具和全部所需 host binds 正常后，才能决定是否扩大其使用范围。来源：[KernelSU App Profile](https://kernelsu.org/guide/app-profile.html)、[PRoot](https://proot-me.github.io/)、[Codex Linux ARM64 package targets](https://github.com/openai/codex/blob/main/codex-cli/scripts/build_npm_package.py)。

## 2026-09-25 `/cli mcp list` 改为读取当前会话配置

- `/cli mcp list` 不再进入使用隔离 `CODEX_HOME` 的一次性 CLI，而是通过活动会话的 Codex app-server `config/read` 查询 `config.additional.mcp_servers`，与当前会话的认证和网络路径保持一致；第三方 provider 或没有本地 Codex session 时会明确说明不可用。
- 输出仅包含服务器名、启用状态、stdio/HTTP 类型、可选的可执行文件名和参数数量、HTTP origin。URL userinfo/path/query/fragment、命令参数、环境变量值、HTTP headers 和 OAuth 数据都不会复制到 transcript 或持久历史。
- `codex_cli_arguments_test.dart`、`codex_mcp_server_summary_test.dart`、`codex_session_client_test.dart` 共 37 项通过，覆盖路由、app-server 请求和凭据脱敏。定向 `dart analyze` 未发现本次新增代码诊断；`main.dart` 仍有 11 条既有 warning 和其他既有 info。
- `tools/build-android.ps1 -Mode release` 成功；APK verifier 确认 `io.henry.codex` 1.0.0、117,309,350 bytes、SHA-256 `0af97cf2b53dc4c499aee7cb264f0adb33391c699dd664bb0ad027b6321f2f4c`、5/5 ARM64 native assets 齐全、签名有效但为本机 debug certificate。当前 `adb devices -l` 为空，本轮未安装或做设备端 MCP 测试。
- 仍未实现：MCP 实时连接健康状态、`mcp add/remove`、MCP OAuth 登录和插件配置；本次只完成安全的当前会话配置读取，不把它描述成完整 MCP 管理界面。

## 2026-09-25 MCP `get`/JSON 变体与 Release 真机 smoke

- 在前一条 `/cli mcp list` session-config 读取基础上，增加 `mcp get <name>`、`mcp list --json` 与 `mcp get <name> --json`。JSON 仍使用字段白名单摘要，不输出 secret-bearing 配置；MCP 状态/健康检查、配置变更与 OAuth 没有伪装成已支持。
- `codex_cli_arguments_test.dart`、`codex_mcp_server_summary_test.dart`、`codex_session_client_test.dart` 共 37 项通过；覆盖 list/get 路由、JSON-safe summary、app-server `config/read` 和环境变量/URL/headers/参数凭据脱敏。定向 analyzer 未发现本次新增代码诊断，`main.dart` 的 11 条 warning 与其他 info 均在既有代码处。
- `tools/build-android.ps1 -Mode release` 成功；verifier 确认 `io.henry.codex` 1.0.0、117,313,918 bytes、SHA-256 `a1e08f4fdd501632a2c63c485c3670e5ff6d6f941d0f7921f92e1ae5bb93a1c2`、5/5 ARM64 assets 齐全且签名有效（本机 debug certificate）。已覆盖安装到真机 `6cb21282`，安装版 `base.apk` SHA-256 与构建产物相同；Android 报告版本 1.0.0。冷启动 `MainActivity` 返回 `Status: ok`，进程保持运行，最近 1200 条 logcat 未见 FATAL EXCEPTION。
- 本轮未操作会话 UI、未发送模型 turn，也未修改设备会话数据；MCP list/get 尚未以真实配置在设备内端到端操作。继续缺口：`mcp add/remove`、MCP OAuth、插件管理以及实际 MCP connection status。

## 2026-09-25 Android runtime updater 版本比较溢出修复

- Android/Bionic runtime updater 从 GitHub release API 读取外部版本字符串；`compareVersions` 原先将每个 semver 分量解析为 `Long`，超出 64-bit 的合法数字会令候选 release 排序抛异常。现在对规范化十进制分量按长度、再按字典序比较，不受整数范围限制。
- 扩展现有 `AndroidCodexReleaseMetadataTest`，覆盖普通多位次版本、大型数字分量、release 列表最高稳定版本选择以及 prerelease 排除；` :app:testDebugUnitTest --tests io.henry.codex.AndroidCodexReleaseMetadataTest -x :app:compileFlutterBuildDebug` 通过。
- 未排除 Flutter task 的 Debug JVM 测试在 `:app:compileFlutterBuildDebug` 遇到无栈信息的 `NullPointerException`；排除该 Flutter 生成 task 后，Kotlin 主源码编译和 updater 定向 JVM 测试通过。随后 `tools/build-android.ps1 -Mode release` 完整成功，并由 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 验证：`io.henry.codex` 1.0.0，117,299,070 bytes，SHA-256 `a2576b8b4a19fecbdfd41a83caa56c1418b645b0571df36b1357b05b7826ad79`，5/5 ARM64 native assets 齐全，APK 签名有效但仍为本机 debug certificate。故目前剩下的是 Debug 测试任务的 Flutter 生成器异常，不影响本次 Release 构建结论。ADB 设备列表为空，本轮未安装或做真机验收。

## 2026-09-25 独立 Codex 的 MCP 实时状态查询

- 在 `apps/codex` 增加 Android 扩展命令 `/cli mcp status [--json]`，显式调用活动 thread 的 `mcpServerStatus/list`，使用 `toolsAndAuthOnly` 并跟随 cursor 分页；不做自动/周期轮询。该命令是 app-server 能力入口，不声称是上游 `codex mcp` CLI 子命令。
- 输出通过白名单摘要，只保留服务器名、连接状态、认证类别、工具数量和工具发现是否失败；不保留工具名、原始错误、MCP capabilities 或凭据。第三方 provider/非本地 Codex session 明确提示不可查询。
- `codex_cli_arguments_test.dart`、`codex_mcp_server_summary_test.dart`、`codex_session_client_test.dart` 共 41 项通过，包括活动 thread 参数、低详情模式、分页和 secret-redaction。Release 构建成功并由 APK verifier 验证：`io.henry.codex` 1.0.0，117,321,730 bytes，SHA-256 `6d8c2a2f6c9197b61678af911a4916492da41149bd5919d1601481b7807dcac2`，5/5 ARM64 native assets 齐全，签名有效但仍为本机 debug certificate。
- 定向 `dart analyze` 未发现新增代码诊断；仍有 `main.dart` 既有 11 条 warning 和其他既有 info。真机当前由用户保持在 `io.henry.codex/.MainActivity` 前台，未覆盖安装、抢占 UI 或启动 MCP worker；因此该命令仍需用用户配置的真实 MCP server 做设备端联调。
- 总目标继续开放；下一步优先推进独立 app 中 Android-native ABI 工具链设备验收和 Root-first 缺口，不把本次 MCP 子项视为阶段完成。

## 2026-09-25 ARM64 工具链设备 smoke 与 ABI 边界

- 发现当前系统 PATH 未包含 `adb`，但 Android SDK 默认 `adb.exe` 存在；连接到端口表已登记的现有 ADB server（5037），没有启动第二个 server。物理设备 `6cb21282` 在线，前台为其他应用，Codex 没有活跃 worker；未切换前台、覆盖安装或修改手机会话。
- 物理设备已安装的 ARM64 native-toolchain 通过 PATH 执行 `bash --version`、`git --version`、`jq --version`、`node --version`、`npm --version`、`npx --version`、`python --version` 和 `rg --version` 全部成功。执行 shell 的既有身份是 KernelSU UID 0 / `u:r:ksu:s0`，所以这是 root-context 二进制 smoke，不是 App UID 或 PRoot 验收；没有额外请求 `su`，没有写入文件或安装 npm 包。
- 为尝试 App UID 验证启动已存在的 `codex_api35` AVD并安装临时 debug APK；实测该 AVD 是 x86_64，ARM64 工具通过翻译器运行，出现 wrong-ELF/动态库错误，因此这些错误不能归因于 App UID 集成。临时 debug 包、ADB staging 和工具归档已移除，AVD 已停止；端口 5554/5555 已登记 released 并确认无监听。真机包从未被替换。
- 结论：ABI 工具包本身及 root-context PATH 已在物理 ARM64 设备验证；普通 App UID 和 PRoot 中的实际工具执行仍未验证。后续应使用 ARM64 虚拟设备或在用户允许 App 短暂切前台/测试包后，通过应用真实 `Backend.execute` 与工具探测闭环，不得用 x86_64 翻译层结果冒充验收。

## 2026-09-25 当前 session 的 MCP remove

- 独立 Codex app 的 `/cli mcp remove <name>` 现在走活动 session 持有的 app-server，而不是一次性隔离 CLI。先读取 `config/read(includeLayers=true)`，只允许删除 base user layer 中的条目；若同名服务器出现在项目、profile 或其他层则拒绝，避免删除后仍被高优先级覆盖。写入使用限定到服务器名的 JSON-quoted key path、user-layer `expectedVersion` 和 `reloadUserConfig:true`，并重新读取 effective config 确认已消失。
- `config/read` 摘要兼容 app-server 将额外配置字段扁平化到 config 顶层的 JSON 形状，也保留旧嵌套 `additional` 形状；错误输出不转发 server raw error 或凭据。命令提示明确指出只影响当前 session 的独立 `CODEX_HOME`。
- 三个定向文件 `codex_cli_arguments_test.dart`、`codex_session_client_test.dart`、`local_session_conversation_test.dart` 共 52 项通过，包含 UI 命令端到端 fixture、带点号名称的 key-path、版本化写入、effective-state 验证，以及同名项目层冲突时不写入。尚未在真实配置设备上执行该变更；MCP add/OAuth/plugin 管理仍未接入。当前真机在 Play Store 评价页，本轮没有抢占前台或启动 app-server worker。
- 随后完成 Release 模式编译（`assembleRelease`，89.2 秒）。只读 APK verifier 确认包名 `io.henry.codex`、版本 `1.0.0`、5/5 Codex ARM64 native assets 齐全且 APK 签名结构有效；产物 117,334,546 bytes，SHA-256 `cb03e3caa3660f95e6f0fbd052c3276aed83e523a5daeba11165ae2401a91614`。但签名类型为 Android debug certificate；`-RequireReleaseSigning` 按预期失败。项目已支持通过 `CODEX_RELEASE_STORE_FILE/PASSWORD` 与 `CODEX_RELEASE_KEY_ALIAS/PASSWORD` 在仓库外注入正式签名，本机此次未提供，因此产物仅供本地 QA，不是可升级/分发的正式签名包。Gradle 8.14、AGP 8.11.1 与 Kotlin 2.2.20 有未来兼容性升级提示，未影响此次编译。

## 2026-09-25 当前 session 的 MCP add

- 将 `/cli mcp add <name>` 从“隔离 CLI 无法影响会话配置”的拒绝提示改为活动 app-server 配置写入，支持 upstream CLI 的常用 stdio `--env KEY=VALUE -- COMMAND [ARGS...]` 与 streamable HTTP `--url URL [--bearer-token-env-var ENV_NAME]` 形式。HTTP(S) URL 禁止 userinfo 和 fragment；env key 校验且拒绝重复。
- 添加仅对当前 session 的 base user layer 生效：如果名称已存在于 user、project/profile 或其它配置层就拒绝；写入带 `expectedVersion`、JSON quoted key path 与 `reloadUserConfig:true`，再读取 effective config 验证。只读会话拒绝添加；Root session 复用 session 级 Root 授权；第三方自定义 provider 不伪装为本地 Codex MCP 管理。
- stdio `--env KEY=VALUE` 按 Codex CLI 当前行为以明文写入该 session 的本地 `CODEX_HOME/config.toml`，没有转存到 Android Keystore；命令不会把完整 argv 或值写入操作进度信息。OAuth client-registration/login/logout 和插件生命周期仍未接入。
- 官方源码核验了当前 `codex mcp add` 的 stdio/HTTP 参数形式及 app-server `config/batchWrite` 的用户配置写入/重载协议。`codex_cli_arguments_test.dart`、`codex_session_client_test.dart` 与 `local_session_conversation_test.dart` 共 58 项通过，覆盖解析、两种 transport、版本化写入、层冲突、写入后验证失败及 UI 命令接线；本次定向 analyzer 无 warning/error，余下 9 项为既有 info。此实现尚未在真机实际 MCP 服务配置上运行。
- 追加改动后重新构建 Release（`assembleRelease`，87.8 秒），并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，117,354,306 bytes，SHA-256 `e1824896e5e7fa5c76b8f065bdd23b8aaeb7ca7338bb9be9a5432a9b5d12188b`，5/5 Codex ARM64 native assets 齐全、APK 签名结构有效；证书仍为 Android debug certificate，因此不是正式分发签名。当前设备前台仍由用户控制，本轮未安装、启动或改变其 UI 状态。

## 2026-09-26 当前 session 的 MCP OAuth 登录

- `/cli mcp login <server>` 改走当前 session 的 app-server `mcpServer/oauth/login`，而非启动一次性 CLI。仅允许 app-server 返回的 HTTP(S) URL（拒绝 userinfo/非 HTTP(S)/无主机），并通过 Android 系统浏览器打开；若无法打开则复制链接到剪贴板。Root identity 会先请求 Root 操作确认，只读会话拒绝写入认证状态。
- 接收 `mcpServer/oauthLogin/completed` 后在会话记录中展示完成/未完成状态；不将服务端原始 OAuth 错误或授权 URL写入 transcript。MCP OAuth logout 暂不支持，因为已锁定的 app-server 协议没有 logout RPC；不会借用隔离 CODEX_HOME 的 CLI 假装登出。
- app-server 0.156.1 的 OAuth handler 自己在回环地址开启 OS 分配的临时 callback 端口，并异步完成凭据交换。本次代码不另起 listener/process；真实 Android 浏览器返回与 MCP 服务认证仍待真机验收。协议以官方锁定 tag 的 `mcp.rs`、`mcp_processor.rs` 为依据。
- `codex_cli_arguments_test.dart`、`codex_session_client_test.dart`、`local_session_conversation_test.dart` 共 61 项通过，覆盖 RPC thread 绑定、异步 completion 脱敏、拒绝不安全授权 URL、系统浏览器 handoff 和不进入 one-shot CLI。定向 analyzer 未在本次新增代码行报告 warning/error；`main.dart` 仍有 11 条已存在 warning，另有既有 info。Flutter 测试会打印 Google Fonts 网络不可用告警，但所有用例通过。
- 此功能尚未用真实 MCP 服务完成 Android 浏览器回跳和设备凭据存储验收；协议与 widget fixture 通过不等于设备端验收。随后完成的 Release 构建已包含该实现，但本轮没有覆盖安装。
- 2026-09-26 `tools/build-android.ps1 -Mode release` 成功；APK verifier 确认 `io.henry.codex` 1.0.0、117,368,270 bytes、SHA-256 `aeab239cf1b48a4d63638dd809c31c0fc0c3600e8a5f2346ee4eea0e7d944b20`、5/5 ARM64 native assets 齐全且签名结构有效。证书仍为 Android debug certificate。ADB 只读检查发现真机当前停留在 `io.henry.codex/.MainActivity`，因此本轮未安装、抢占前台或打断可能存在的会话。

## 2026-09-26 DeepSeek 真实服务商短请求验收

- 对照 DeepSeek 当前官方文档，使用 OpenAI-compatible base URL `https://api.deepseek.com` 和现行低成本模型名 `deepseek-flash`；旧 `deepseek-chat`/`deepseek-reasoner` 名称已进入停用周期。文档也确认 Flash 支持 vision、Chat Completions SSE 和 usage 字段。
- 通过 `CustomProviderSessionClient` 生产实现各发出一次短文本与一次项目自带小图请求。两次均返回预期确认文本、正常进入 idle，并解析到 usage event；验证范围包括 HTTPS Bearer 鉴权、SSE 累积、图片 `image_url` wire shape 与用量事件。API key 只在 SecureString 输入提示转入本次测试进程的临时环境变量，没有写入代码、配置、测试输出或进度文档；对话中没有保留回复正文或 token 用量明细。
- 真实网络 smoke 在 Windows 主机执行，不是 Android 设备端证据。Android Keystore 加密/重启恢复、设置页保存流程、真机系统图片选择器和真机网络路径仍需单独验收；这两次调用也不授予第三方模型任何本地文件、工具或 Root 能力。

## 2026-09-26 DeepSeek Android provider 端到端 AVD 验收

- 使用 Release APK 安装到 `codex_api35` API 35 x86_64 AVD，启动时采用 `-read-only` 临时快照。通过 Settings 添加 DeepSeek（OpenAI-compatible base URL、`deepseek-flash` 和用户提供的 API key）；强制停止并重开 App 后，provider、活动选择及模型仍正确恢复，设置 UI 不回显 API key。该验证覆盖 Android Keystore/MethodChannel 的运行时保存与读取。
- 在同一 AVD 创建独立会话并发起真实 provider turn，Android 网络/SSE 收到准确回复 `ANDROID_DEEPSEEK_OK`；会话回到 Ready，并显示实际 usage（该轮输入 82、输出 104 tokens）。只验证普通聊天/usage，不把第三方服务描述为具有 Codex tools、workspace 文件或 Root 权限。
- 测试结束后通过 ADB 正常关闭 AVD；由于它以只读快照运行，临时 APK、provider 密钥和会话状态随虚拟机退出丢弃。端口 5600/5601 已登记 released 并核对无监听。实体手机仍在用户前台 Codex 页面，本轮没有覆盖安装、切换界面或停止其会话。
- AVD 是 x86_64，不能验证 ARM64 native toolchain、PRoot/rootfs 或 KernelSU；本次 APK 证书也是本机 debug certificate。真实 provider UI/网络已在 Android 虚拟机闭环；实体手机验收、图片选择器/上传链路和停止/错误恢复仍未做（图片链路随后于本记录末尾在 AVD 完成）。

## 2026-09-26 DeepSeek 推理档位与会话设置对齐

- AVD 真 turn 暴露了 UI/请求不一致：mode bar 显示 `low`，但 provider 请求此前只带 `model/messages/stream`；DeepSeek 因而使用其默认 high effort。按[官方 Thinking Mode 文档](https://api-docs.deepseek.com/guides/thinking_mode/)修复：`deepseek-*` 模型 ID 现在显式发送 `thinking.type=enabled` 与 `reasoning_effort`；minimal/low 映射 low，medium/high/xhigh 映射 high，max/ultra 映射 max，none 则关闭 thinking。修改会话档位后会更新 provider client。非 DeepSeek 的 OpenAI-compatible provider 请求不添加这些字段，避免破坏兼容性。
- provider SSE 回归 5/5 通过，覆盖 low/high/none 请求体和 generic endpoint 不收到 DeepSeek 参数；定向 analyze 无本次新增 warning/info，`main.dart` 仍有 11 条既有 warning 与 7 条既有 info。真实 DeepSeek API 使用 low effort 完成短请求，确认返回标记与 usage。
- 新 Release 构建通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，117,370,074 bytes，SHA-256 `74fed66edde40e5a35ad00649d852509e214a9b623539a37a58e1066367c998c`，5/5 ARM64 native assets 齐全；签名有效但为本机 debug certificate。真机仍在用户前台，本轮未安装；该版本尚未在 AVD 上做设备级复验。

## 2026-09-26 第三方 session 隐藏无效 Codex 控件

- 第三方 provider 是 chat-only transport，不支持 app-server 的计划模式、执行权限或本地工具。会话模式栏隐藏这些 Codex 专属控件；模型入口打开活动 provider 设置。DeepSeek 才显示独立 reasoning-effort 入口并复用 CC Pocket 设置面板；其他兼容 provider 不暴露当前 transport 不会发送的通用 effort 参数。Codex app-server session 原有计划与权限控件保持不变。
- `ccpocket_native_session_test.dart` 18 项通过，验证第三方模式栏保留模型入口且隐藏计划/权限入口；`local_session_conversation_test.dart` 14 项通过，会话创建/恢复/流式生命周期回归正常。定向 `dart analyze` 完成，报告 11 条 warning 和 16 条 info，未报告 analyzer error；Google Fonts 网络下载告警不影响测试通过。
- 同一 APK 随后已装到 `codex_api35` API 35 x86_64 `-read-only` AVD。通过界面创建不含真实 key 的临时 provider、打开新会话并目视/检查无障碍层级：只显示 `Deepseek Flash · 低` 模型入口，没有计划/执行权限 chip；点击模型入口确实返回“第三方模型”设置并显示对应配置。截图为 `tmp/modebar-avd-third-party-session-20260926.png`。AVD 正常关闭、5600/5601 已确认无监听并在端口表释放；实体手机仍保持在线，本轮未向其发送命令。
- AVD 上这项验证只覆盖 provider mode-bar 显示与设置路由，不代表 x86_64 AVD 能验证 ARM64 runtime/PRoot/Root，也没有发起 provider 网络请求。APK 仍是 debug certificate 签名测试包。

## 2026-09-26 DeepSeek 会话推理档位入口与 AVD 验收

- 修复前一轮 UI 验收发现的可操作性缺口：第三方模型 chip 只打开 provider 编辑页，DeepSeek 会话档位仍不可改。现在模型和推理档位分开呈现；DeepSeek 的 `none/low/high/max` 使用 CC Pocket `CodexSettingsSheet`，选择后更新当前 session 与 provider client；generic OpenAI-compatible provider 隐藏其当前不会发送的 effort 控件。计划/执行权限仍只在本地 Codex app-server session 显示。
- 新增 widget 回归：chat-only provider 的 effort 控件显示条件、打开回调及通过 CC Pocket advanced picker 选择 high 并通知 session。三个定向 Flutter 测试文件共 38 项通过。定向 `dart analyze` 未报 error，仍显示 `main.dart` 的 11 条既有 warning 与 16 条既有 info；`git diff --check` 通过。Google Fonts 下载外网错误仍只出现在测试日志，不影响用例结果。
- 新 Release 构建与 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 通过：`io.henry.codex` 1.0.0，117,373,822 bytes，SHA-256 `e4b5000beeff4b81647e49b3f35020e5011433436491289fdcef480b5af52b15`，5/5 ARM64 native assets 齐全，签名有效但使用 Android debug certificate。
- 将该 APK 安装到 `codex_api35` API 35 x86_64 `-read-only` AVD；用临时 DeepSeek provider 配置验证新会话：模型与“低”是两个独立入口，计划/权限控件不存在；effort sheet 显示 `None/Light/High/Max`，点选 `High`、关闭面板后会话 chip 更新成中文“高”。没有发起网络请求。截图为 `tmp/modebar-avd-effort-high-20260926.png`。AVD 正常停止，5600/5601 已确认无监听并释放；ADB 列表只剩实体设备 `6cb21282`，本轮未对它发命令。
- 设备验收只证明该 x86_64 AVD 的 UI/状态回写；不代表 ARM64 runtime、PRoot/Root 或真实 DeepSeek turn 在此新 APK 上已复验。DeepSeek wire 参数的真实服务短请求已在前一节通过，实体设备 UI/网络路径仍待用户设备验收。

## 2026-09-26 Android 图片选择器到第三方请求闭环

- 在同一 Release APK 的 `codex_api35` API 35 x86_64 `-read-only` AVD 中，通过会话 composer 的“附加图片”启动 Android `ACTION_OPEN_DOCUMENT`；从系统文件选择器的 `Pictures` 目录选取 `codex-fixture.png`（PNG，15,114 bytes）。附件以图片-only 消息发送，用户文本为空。
- AVD 通过 `10.0.2.2` 请求仅绑定主机 `127.0.0.1:55003` 的本地 SSE fixture；fixture 记录到 `/v1/chat/completions`、`imageCount=1`、MIME `image/png`、base64 长度 `20,152`、模型 `fixture-vision`，并确认请求未带 Authorization。fixture 不保存或输出图像内容；没有使用 DeepSeek/API key，也没有第三方计费请求。
- fixture 返回 SSE `AVD_IMAGE_FIXTURE_OK` 和 usage（输入 12、输出 3）。Android 会话收到完整回复、显示 usage，user turn 显示一张附件。截图：`tmp/avd-image-picker-turn-20260926.png`。这验证了本 APK 在 AVD 上从原生选择器到 provider wire payload、流式接收和界面呈现的完整路径。
- 测试后关闭 AVD 与 fixture，端口 55003/5600/5601 在 2026-09-26 01:40 +08:00 确认无监听并登记 released；ADB 仅剩物理设备 `6cb21282` 在线，本轮未向手机发送命令。保留的 APK SHA-256 为 `e4b5000beeff4b81647e49b3f35020e5011433436491289fdcef480b5af52b15`。
- 验证边界：这是本地模拟服务，不验证真实第三方视觉理解或实际账单；也不验证 ARM64 native runtime/PRoot/Root、真机 picker、Codex app-server 的图片 turn、超大文件拒绝或图片 picker 多选上限。

## 2026-09-26 新目标重建与第三方模型改为原生 app-server

- 旧 goal 删除后，已创建新的持续 goal（active），明确包括 Root-first Android 本地执行、KernelSU 启动关键目标保护、Codex CLI 独立升级、原生 `model_providers`/Responses API、session 并发与进度文档；当前实现不涉及 Bridge。
- 纠正本文件较早记录的状态：chat-only transport 与隐藏 Codex 控件是本次改动前的历史实现/验收，不再代表当前源码目标。生产 session 现在使用同一个 `CodexSessionClient` 和每 session Codex app-server；第三方选择通过 `-c model_provider=android_custom`、Responses wire API、`requires_openai_auth=false` 与配置模型接入。API key 保存在现有 Android Keystore store，只注入该 session 进程环境，未写入 argv、Codex 配置文本、日志或 transcript。
- provider URL 会把历史存储的完整 `/chat/completions` 或 `/responses` 地址归一化成 base URL；若服务端仅支持 Chat Completions，仍不能直接接入，因为当前 Codex CLI 不再接受 `wire_api="chat"`。计划、权限、MCP、审批与 thread/turn 由 Codex app-server 提供，不再绕过它直接发 chat 请求。OAuth 仍保存在原账户状态供用户切回，但 custom session 的 provider 配置明确不要求 OpenAI 登录；会话里隐藏 OAuth 专属的 5h/weekly account quota，继续显示 app-server 返回的 token usage。
- 自定义 provider 的 model list 尚无通用发现接口，因此 model picker 只列设置中配置的模型，不会混入 OpenAI CLI catalog。DeepSeek 继续提供已实现的 effort 入口；其他 provider 只暴露 `low`，并在设置说明具体模型能力依赖服务商。保留旧 chat-only client 与测试代码供历史回归，但当前 `main.dart` 不再实例化它。
- 验证：provider launch/config 测试、session app-server 集成测试、CC Pocket mode-bar 与 session regression 共 38 项通过；另一次六文件合并回归共 77 项通过。定向 `dart analyze` 无新增代码错误；整体仍返回既有 unused/deprecation/info diagnostics。测试中 Google Fonts 因当前网络无法获取字体而打印告警，不影响 Flutter tests 通过。
- 尚未完成：本轮没有构建 APK，也没有在 AVD/真机对新代码执行第三方真实 turn；历史 chat-only session 的合成 `custom:` thread ID 没有 Codex rollout，自动迁移其上下文还未实现。第三方模型用量/额度 API、provider 能力协商，以及不同 Codex CLI 版本的启动兼容性也待实测。上游协议依据：[Codex provider implementation](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs)，[DeepSeek Responses API](https://api-docs.deepseek.com/guides/responses_api/)。

## 2026-09-26 Root ordinary-write routing and protected host paths

- Root sessions now route resolved ordinary absolute write paths directly, including app-private `/data/user/0`, `/data/data`, and `/data/misc`; unresolved/broad scopes still require the visible app-server approval path. `/`, raw block/MTD/UBI/mapper devices, KernelSU control state, and protected system/boot destinations remain denied or plugin-only. The explicit Root-session confirmation remains session-scoped; this change removes the repeated prompt for ordinary writes, not the separate session authorization gate.
- The Root path classifier understands a planned `/android` host-root prefix: Android host `/android/etc`, `/android/system*`, `/android/vendor*`, `/android/apex`, `/android/init*`, and `/android/dev/block/...` follow host system/boot rules, while guest paths such as `/etc` remain writable for normal Debian package configuration. Important boundary: the live PRoot launcher still binds only selected host directories at their original pathnames; `/android` and the complete Android host `/` are not yet mounted. The command preflight no longer canonicalizes the entire shell command as a filesystem path: doing so had stripped the trailing slash from `rm -rf /`; command text is preserved and extracted targets are normalized individually.
- The Root authorization and settings messages now match behavior: ordinary paths are auto-approved by app policy, unknown/high-risk requests retain handling, full-access mode stays unavailable, and the UI explicitly says this path preflight is not kernel isolation. The conversation permission chip now says “Root” instead of misleadingly mapping Root direct-write mode to CC Pocket's generic “Default”; its sheet states which targets auto-approve, which retain approval, and the current kernel-boundary limitation. `flutter test test/root_access_policy_test.dart --reporter expanded` passes (11 tests); the five-file provider/session/root/UI regression now passes (85 tests), covering app-data direct writes, host-vs-guest path separation, planned Android host mapping, root-directory denial, boot/system plugin routing, block-device denial, KernelSU boundaries, custom provider app-server launch, Root UI, and concurrent/resumed sessions.
- Follow-up integration testing found Root file-change auto-approval still entered the workspace-only managed-backup path, which could block writes to Android app data before sending the decision. Ordinary Root direct-write approvals now bypass that workspace-specific backup step; the targeted `root_access_policy_test.dart` + `local_session_conversation_test.dart` run passes (27 tests), including a session-level `/data/user/0/...` file-change request that is accepted without a preview/backup prompt.
- Corrected the injected and bundled Android Codex operating guides to match the actual backend: App UID remains the current default pending Root profile acceptance; PRoot still binds only selected host directories (not all of `/`); Root guest package management is not yet available; and third-party providers now use native Codex Responses/app-server rather than the retired chat-only route. The `/android` policy tests cover the planned host-root mapping but do not imply that it is deployed.
- No APK build or device write test was performed. This remains an app-layer best-effort classifier: it cannot constrain arbitrary shell/API writes, symlink traversal, or a compromised/bypassing child. KernelSU enforcing policy and actual Root worker acceptance remain unverified on the target device; do not present the classifier as the root-safe OS boundary.

## 2026-09-26 Custom provider key inheritance boundary

- Review of the bundled Codex source showed shell tools build their child environment from the app-server environment and, by default, the global config does not enable the `*KEY*`/`*SECRET*`/`*TOKEN*` exclusions. The custom provider key was therefore not in argv/config text, but could still be inherited by ordinary shell children.
- Keyed custom-provider sessions now set `shell_environment_policy.ignore_default_excludes=false` as a session-only app-server override. The native Responses provider still reads the key from its environment; Codex shell children now apply its standard sensitive-variable filters. No-key provider sessions do not modify shell env policy. Added tests assert both paths.
- This reduces accidental inheritance, not Root confidentiality: the API key remains in the app-server process environment, and a same-UID/Root process may inspect that environment through platform process interfaces. The injected agent guide forbids inspecting/disclosing it and does not claim OS isolation; the provider settings page now warns about this boundary in Chinese and English. Preventing a Root-capable agent from reading its own provider process environment would require a separate OS-enforced identity/boundary, which is not currently verified and conflicts with broad Root visibility.
- Provider launch config, settings warning in both locales, and conversation lifecycle regression pass together (21 Flutter tests); test logs still contain non-fatal Google Fonts download errors. Release APK build and `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` passed: package `io.henry.codex` 1.0.0, 117,349,418 bytes, SHA-256 `bf58164836144433c75523eaf44b29331477c6ff53d32bad353e89c54a00b4f8`, all five required ARM64 runtime assets present, signature valid with the local debug certificate. Installed with `adb install -r` on physical ARM64 device `6cb21282` without clearing app data; cold launch returned `Status: ok` and the foreground Activity/version were verified. No provider request or billing occurred. The app-server has not yet been started with the new environment filter on-device, so the spawned-command behavior remains validated by the pinned upstream config implementation and generated-argv tests, not device runtime evidence.

## 2026-09-26 Root PRoot Android host-root visibility mapping

- Root PRoot previously exposed only selected Android directories at their original guest paths, despite `/android/...` already being recognized by the host-path risk classifier. Root launch now creates a dedicated real `/android` mountpoint inside the verified app-private Debian rootfs and adds `--bind=/:/android!`; existing `/data`, `/system`, `/vendor`, `/storage`, `/proc`, `/sys`, `/dev`, and related direct binds remain for compatibility. The bind is added only for the Root identity; App-UID PRoot remains unchanged.
- The mountpoint helper rejects an invalid/symlink rootfs or a symlink/non-child `/android` destination. Root session launch remains behind the existing KernelSU Root Profile probe and immediate preflight; this path mapping does not grant root or bypass SELinux.
- Validation: `:app:testDebugUnitTest --tests io.henry.codex.CompatibilityCommandArgvTest -x :app:compileFlutterBuildDebug` passed, covering the exact Root bind, mountpoint creation, and absence of the bind/mountpoint for App identity. Without the exclusion, the Flutter Gradle `compileFlutterBuildDebug` task fails with a bare `NullPointerException` before Kotlin/unit-test tasks; this is not a complete APK build. Device Root Profile still rejects the required `codex_agent` context, so no real Root PRoot process or `/android` file read was claimed or tested in this change.

## 2026-09-26 Root host-root APK build and device smoke

- Build diagnosis: `apps/codex/build/app/intermediates/flutter/release/flutter_build.d` was a generated 202,530-byte depfile containing paths from a removed `Y:` mapping as well as the CJK checkout path. With it present, Gradle's Flutter task failed with a bare NPE; moving this exact file aside let Flutter reach AOT, where the CJK path failed to read `.dart_tool/flutter_build/.../app.dill`. Re-running `flutter pub get --offline` and the Release build from the existing ASCII `X:` SUBST path regenerated build metadata and succeeded. This is a machine/path-state workaround; the project still needs a durable build-path fix if that mapping is absent.
- `flutter build apk --release --no-pub` from `X:\apps\codex` completed in 86.4s. Read-only APK verification passed: `io.henry.codex` 1.0.0, 116,669,359 bytes, SHA-256 `b532e2d6a64716dc9c29b5dcfab4f4265093676c83bd22960922588d17fd656c`, valid signature using the local Android debug certificate, and all five required ARM64 Codex/PRoot native assets present.
- Physical device `6cb21282` remained online and was showing Codex before installation; `ps -A` showed no PRoot worker. `adb install -r` succeeded without clearing app data. Starting `io.henry.codex/.MainActivity` returned normally and the Codex Activity remained foreground. This is a package/install/launch smoke, not a Root-session test.
- A post-install read-only KernelSU query still returned `Error: No such file or directory` for `ksud profile get-sepolicy io.henry.codex`; the device reports Android API 36 and SELinux Enforcing. No profile or device policy was changed. Therefore the new Root-only `/android` bind is compiled and installed but cannot yet be exercised through the app's gated Root worker; full host-tree read, normal Root writes, and protected boot/system write denials remain unverified on-device.

## 2026-09-26 Root-default session UI and device verification

- New sessions opened from the local workspace now initialize as Root; restored history continues to use the identity persisted by that session. Root sessions prefer the verified Linux Compatibility/PRoot backend only when creating a new Codex provider thread; restoring an existing thread does not silently change its runtime. Runtime fallback preserves the draft, queued prompts, and prompt history.
- Updated settings copy to accurately describe Root defaults, ordinary-path policy, protected boot-chain targets, and the KernelSU profile gate. The session settings page exposes both Root and App UID. Three targeted Flutter groups passed: `test/local_ui_navigation_test.dart`, `test/local_session_conversation_test.dart`, and `test/root_security_notice_settings_test.dart`. `dart analyze` still reports repository-existing warnings/infos; it found no new compile error at the changed paths.
- Release APK built from the ASCII `X:` checkout and installed over the existing app without clearing data. Verifier: package `io.henry.codex` 1.0.0, 116,813,930 bytes, SHA-256 `9bc41c856a081db626147b63ca550d526cbf8bcbab1fad03a6ff635c62260960`, all five ARM64 runtime assets present; the APK uses the local debug certificate and is QA-only, not a formally signed distributable.
- On physical device `6cb21282` (Android 16/API 36, SELinux Enforcing), the newly opened session visibly defaulted to Root. Settings visibly offered App UID; switching the test session to App UID updated the identity tile, and it was restored to Root afterward. The app reported that KernelSU rejected the fixed `codex_agent` SELinux context; no Root worker started. No model turn was sent, no profile/policy was changed, and no user workspace/session data was deleted. Full UID-0 execution, host `/` reads/writes, and protected boot/system denial are still unverified.
- Device UI also exposed a session-history reopen defect: after returning Home, opening a recent-session card for the fresh blank session produced `找不到该会话对应的本地 workspace。` A second older card did the same. Both records and workspaces were preserved. The exact `backendId`/`workspacePath` mismatch is not yet observable through the release UI, so do not guess at a path-relaxation fix; investigate the history-to-workspace lookup before claiming session resume acceptance.
- The device Settings page reported compatibility Codex CLI `0.154.0`, and the session model label was `gpt-5.6-luna`; runtime updater/model-catalog freshness remains a separate unresolved check. This was observed only; no CLI update was initiated in this smoke test.

## 2026-09-26 Fix reopening Root sessions on the compatibility backend

- Read only the two newly created session-history records' metadata on device (not transcript contents). Both recorded `backendId=linux-compatibility` and the existing `/storage/emulated/0/Codex/Workspaces/privacy-investigation` host path. The Home resolver searched only its primary `local-android` workspace list, causing a false “workspace not found” even though the correct compatibility backend was configured as its fallback.
- Home now selects the primary or configured fallback backend by the saved `backendId`, lists workspaces from that backend, and retains the exact backend-id plus host-path match before opening. Added a widget regression proving a PRoot-backed history reopens through its own compatibility workspace instead of being misrouted to App UID. The targeted `ccpocket_native_home_test.dart` passes all 8 tests; the combined home/navigation/session/Root-settings regression also passes.
- Rebuilt Release APK and verified signature/assets: `io.henry.codex` 1.0.0, 116,814,406 bytes, SHA-256 `5065094d3107591fa4c1f6e72413ba88c1da0991c691f1e9eac8d6b378b4751c`, five required ARM64 assets present, local debug certificate (device QA only). Installed with `adb install -r` without clearing app data.
- Physical-device acceptance after reinstall: both the fresh blank Root session and the earlier Root history card now reopen from Home and show the persisted Root transcript/status; the workspace-not-found snackbar is gone. No user prompt or model turn was sent. The session transcript correctly still reports KernelSU rejecting the app's `codex_agent` SELinux profile, so neither record proves a working UID-0 Codex worker. A separate read-only `adb shell su -c id` returned UID 0 in `u:r:ksu:s0`; that does not establish that the app worker is permitted or has host-tree access.
- This supersedes the preceding entry's “exact mismatch not observable / do not guess” note: the mismatch was verified from record metadata and fixed at the backend-aware resolver. Full thread resume still requires a persisted real Codex `threadId`; these test sessions had none because the Root worker never started.

## 2026-09-26 Provider/session binding and Responses-only cleanup

- Closed a cross-session routing defect: session-history rows now persist the custom provider ID (never the API key), and reopening resolves that exact saved provider rather than inheriting whichever provider is globally active. If the saved provider was deleted, the session displays an actionable error and blocks turn start instead of silently sending the conversation to OpenAI. A user can explicitly select another provider or OpenAI to continue.
- Added an upgrade guard for legacy `custom:` synthetic thread IDs created by the retired chat-only client. The saved transcript remains visible, but the app-server never receives that synthetic ID, prompt input is blocked, and the recovery banner offers a clean new session. Starting that new session uses a fresh history key; the older history record is not deleted.
- Confirmed the runtime path is native Codex app-server, not a parallel chat client: each session scopes `HOME`, `CODEX_HOME`, SQLite and temporary files; provider selection is applied only to that app-server via `model_provider=android_custom`, `wire_api=responses`, and `requires_openai_auth=false`. The API key is injected only in that session process environment and is not serialized into history, argv, config text, or transcript. OpenAI account quota is hidden for custom-provider sessions; app-server token usage remains available.
- Removed the unused legacy `/chat/completions` client and its tests. Provider settings now validate the same Responses base URL the Codex CLI will use. Historical saved endpoint URLs ending in `/chat/completions` are still normalized to their API base, but the provider must implement Responses. The official Codex CLI accepts only `wire_api="responses"`; DeepSeek now documents a native Responses API intended for Codex, including streaming and function tools. This does not imply every model/provider capability is supported; the UI continues to expose only capabilities the configured model can use.
- Verification: 5 focused Flutter test files passed (41 tests), covering session history, native provider launch/key isolation, missing-provider behavior, legacy chat-only history, settings copy, config normalization, and existing concurrent-session behavior. `flutter analyze` reported 20 info/warning diagnostics across the selected files (no analyzer errors); Google Fonts emitted network-fetch warnings during widget tests. No APK build, device install, real provider request, or billing occurred in this follow-up.
- Sources: [Codex model provider implementation](https://github.com/openai/codex/blob/main/codex-rs/model-provider-info/src/lib.rs), [DeepSeek Responses API guide](https://api-docs.deepseek.com/guides/responses_api/).

## 2026-09-26 Follow-up release install and Root gate readback

- Built `apps/codex` Release through `tools/build-android.ps1 -Mode release`. Read-only verifier passed: package `io.henry.codex` 1.0.0, 116,683,151 bytes, SHA-256 `8d2e14062ff647f4c659514e540e1b03bcce0bb281e4f78dca330a1a6dd2e14a`, valid local Android debug-certificate signature, and all five required ARM64 PRoot/worker assets present. The artifact is for device QA, not a production signing claim.
- Device `6cb21282` is online (24031PN0DC, API 36, SELinux Enforcing). Installed with `adb install -r` without clearing app data; `io.henry.codex/.MainActivity` starts and remains foreground. Installed package reports version 1.0.0. No prompt, provider request, billing, Root worker launch, or KSU policy change occurred.
- Rechecked `ksud` 3.3.0 read-only: `ksud profile get-sepolicy io.henry.codex` returns `No such file or directory`, which only means the supplemental SELinux rule file is absent; it does not report the KernelSU App Profile. A later app-originated probe independently confirmed that the fixed `codex_agent` context is rejected at `setcontext` (`context_unavailable`), which is the reason the Root gate remains closed. No template/profile/policy was applied. Do not replace the missing enforcing domain with `u:r:ksu:s0`, permissive mode, or an unreviewed allow-all rule. UID-0 Codex worker execution and kernel-enforced protected-write behavior remain unverified.

## 2026-09-26 KernelSU profile command semantics and device mismatch

- Corrected the interpretation of the preceding `ksud profile get-sepolicy io.henry.codex` result. On the installed KernelSU `ksud 3.3.0 (uapi: 2)`, `profile get-sepolicy` is a supported command, but it reads the supplemental SELinux rule file `/data/adb/ksu/profile/selinux/<package>`. The official implementation directly calls `read_to_string` on that path; the observed `No such file or directory` means the Codex supplemental rule file is absent, not that the KernelSU profile interface/command is unsupported. The installed CLI does not expose `profile get`; its profile subcommands are only SELinux rule/template operations.
- The device's `/data/adb/ksu/profile/selinux` directory currently contains no `io.henry.codex` file. KernelSU App Profile data itself is retrieved/set through the Manager's native `getAppProfile`/`setAppProfile` calls to the kernel profile interface, not through `ksud profile get-sepolicy`. Therefore do not use that missing file as a proxy for the app's UID/groups/capabilities/context configuration.
- Read-only inspection of KernelSU Manager home showed Manager `v3.3.0 (32601-2)` and driver `32525-2`, with an explicit version-mismatch warning. This is a real device compatibility condition worth addressing, but this observation alone does not prove App Profile operations fail: the manager and kernel UAPI values were not independently read, and no Manager profile setting was changed. No KernelSU profile, SELinux policy, module, or device configuration was modified in this check.
- Official upstream references: [`ksud profile` command implementation at v3.3.0](https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/profile.rs), [`ksud` command definitions at v3.3.0](https://github.com/tiann/KernelSU/blob/v3.3.0/userspace/ksud/src/cli.rs), [`Natives.kt` App Profile/UAPI API at v3.3.0](https://github.com/tiann/KernelSU/blob/v3.3.0/manager/app/src/main/java/me/weishu/kernelsu/Natives.kt), and [KernelSU Root Profile behavior](https://github.com/tiann/KernelSU/blob/v3.3.0/website/docs/guide/app-profile.md).
- Follow-up: the app-originated `probeRootProfile` has since run on the connected phone and classified the `su -Z u:r:codex_agent:s0` `setcontext` rejection as `context_unavailable`. KernelSU's Manager and driver version display mismatch remains a device condition, but the reported UAPI v2 and this error do not establish that the App Profile API itself is unsupported. The next useful step is a reviewed enforcing policy candidate and a device-effective access test; no profile, module, or SELinux rule was changed. Keep Root launch blocked until the context is accepted and protected-write denials are demonstrated.

## 2026-09-26 Physical ARM64 PRoot toolchain repair and verification

- The Release APK was already installed on device `6cb21282` with `adb install -r`; application data was preserved. Inspection of the app-private compatibility runtime found an older Debian Bookworm rootfs (`Codex 0.154.0`) where dpkg claimed `libexpat1` was installed but the shared-library payload was absent, and `/usr/bin/python` was missing even though `/usr/bin/python3` existed. This explained why the source-level `python-is-python3` change had not fixed the already-installed rootfs.
- Recovered the exact `libexpat1` ARM64 `.deb` already cached in that rootfs. The extracted library MD5 matched the rootfs dpkg metadata; its SHA-256 was checked again after staging on device. Restored the missing library and SONAME symlink with root ownership and the app-private SELinux label, and added `/usr/bin/python -> python3`. No package database or user workspace/session data was changed.
- Using the installed device PRoot/loader and this Debian guest, the following commands each exited 0: `python --version` / `python3 --version` -> 3.11.2; `git --version` -> 2.39.5; `node --version` -> v24.19.0; `npm --version` and `npx --version` -> 11.17.0. The tested PATH placed Debian guest tools ahead of Android ABI fallback tools. This proves the guest binaries can execute on the physical ARM64 device, but the invocation came from an ADB KernelSU root shell, not the Codex App's gated `codex_agent` worker; it is not proof of app-originated Root execution or a real Codex turn.
- The reproducible rootfs builder already includes Debian `python-is-python3`, and `bash tools/android-local-runtime/builder/test-offline.sh` passed. A fresh rootfs artifact was not produced: WSL downloads of the pinned Codex 0.154.0 npm archive repeatedly stalled, so no incomplete download was installed. The device-local repair does not upgrade the installed CLI or provide newer model catalog entries; the existing runtime remains 0.154.0 until a complete verified runtime artifact is installed.
- Root Profile remains `context_unavailable`; no KernelSU profile, SELinux policy, module, or boot/system file was modified. Full app-originated Codex execution, host `/` read/write behavior, protected boot/system write denial, and guest package installation through the app remain unverified.

## 2026-09-26 KernelSU App Profile live UI inspection

- Read-only inspection of the connected phone's `io.henry.codex` App Profile showed `自定义`, UID/GID `0`, groups `root,readproc`, capabilities `DAC_OVERRIDE,KILL,SYS_BOOT,SYSLOG`, and SELinux context `u:r:ksu:s0`. The SELinux editor currently shows that same domain and an empty Rules field. No profile value or rule was edited or saved.
- This confirms that selecting the Manager's “Custom” profile is not sufficient: the current context is not the `u:r:codex_agent:s0` domain required by the app, and the active custom values do not match the launch contract. The worker requires Android groups exactly `0` and `3003` (`root,inet`), and its post-launch effective/permitted/bounding capability masks must be `0xcf` with inheritable/ambient masks empty. The fixed native launcher needs `CAP_SETPCAP` plus the routine capability set in the app-wide Root Profile so it can reduce the child before Codex starts. The currently listed `SYS_BOOT` must not be granted to the Codex worker; the current worker guard removes it, but the broader App Profile is also used by app-originated `su` helpers and therefore must be reviewed.
- The SELinux domain/rules editor provides the route to define an enforcing `codex_agent` domain, but no policy candidate has yet been applied or validated for broad reads, ordinary writes, and denied system/boot/block-device writes. Keep the Root gate closed; do not change the context to `codex_agent` without the corresponding reviewed policy, and do not substitute permissive or `u:r:ksu:s0` execution.

## 2026-09-26 KernelSU `codex_agent` context rejection recheck

- Rechecked the connected physical device `6cb21282` (`24031PN0DC`, Android 16/API 36): `ro.product.device=aurora` and SELinux remains `Enforcing`.
- Directly invoked the same fixed, read-only context request used by the app: `/system/bin/su -Z u:r:codex_agent:s0 --ksu-no-new-privs -c "/system/bin/id -Z; /system/bin/id -u"`. KernelSU still exits before the command with `Error: setcontext u:r:codex_agent:s0` / `Invalid argument (os error 22)`. This independently reproduces the app's `context_unavailable` gate failure; it is not evidence that the phone lacks general root access.
- Read-only `ksud` help confirms that this installed CLI exposes `sepolicy check`, `patch`, and `apply`; the `profile` commands only manage SELinux policy text/templates. No `patch`, `apply`, Profile write, or device file write was run. A successful `check` would establish parser acceptance only, not that a rule is installed or effective.
- No profile or SELinux policy was changed. The Root worker remains blocked. Next work is a device-specific, reviewable policy candidate with the App Profile's shared `su`/plugin-broker scope accounted for, followed by an explicitly authorized Manager save and effective worker access tests; do not substitute permissive mode or allow-all rules.
- Corrected the Settings diagnostic copy: the Codex worker requests `codex_agent` with fixed `su -Z`, while the fixed KernelSU plugin helper uses ordinary `su -c` and therefore the App Profile's default context. The UI now warns against changing the default Domain just to pass the worker probe. Pinned Root Profile and `su` source links to KernelSU v3.3.0, matching the connected Manager/`ksud` release. `flutter test --no-pub test/kernelsu_plugin_settings_test.dart` passes (4 tests); no APK was rebuilt or installed.

## 2026-09-26 Runtime-route copy follow-up Release and AVD smoke

- Fixed the last misleading runtime-route copy: Settings, runtime details, and the import confirmation now state that the Android host owns workspaces, new Root sessions prefer a verified Linux/PRoot guest, and Android native is the fallback when the guest is missing or fails a concrete capability probe. App UID sessions continue to use Android native directly. No new backend or Bridge path was introduced.
- The full Flutter regression passed with `+259`. A flaky `home_host_access_widget_test` was made deterministic by giving that test a 800×900 viewport before tapping the settings storage tile; the production widget behavior was unchanged. Google Fonts download failures remain non-fatal test-environment warnings.
- Release build and verifier passed: `io.henry.codex` 1.0.0, 116,815,570 bytes, SHA-256 `52dfe6331f002249eb60b8e65be247227a65facf3ed329151648f99466e7ecac`, valid local Android debug-certificate signature, and all 5 required ARM64 native assets present. This is a local QA artifact, not a store-signed production package.
- Installed to the `codex_api35` AVD (`emulator-5554`) without clearing data; Activity launch, Chinese Home, Settings, and the new execution-strategy text were visible. Filtered logcat contained no `failed to load models cache`, `model_cache_unavailable`, or `FATAL EXCEPTION`. The AVD was then stopped cleanly; TCP 5554/5555 were confirmed released in the shared port registry.
- Physical ADB remained offline. This checkpoint therefore verifies cache-miss handling, app startup, and non-Root settings UI only; it does not verify KernelSU Root, ARM64 guest execution, host `/` visibility, OAuth, or a real Codex turn.

## 2026-09-26 Runtime route copy and model-cache miss handling

- The optional native model-cache bridge now treats a missing `models_cache.json` as a normal cache miss and lets the live CLI/app-server model discovery continue. It still reports malformed, symlinked, oversized, or unreadable cache files as real failures. This removes the misleading `failed to load models cache` noise without hiding an actual cache corruption or permission error.
- Settings and runtime-install copy now match the implemented route: the Android host remains the workspace owner; a new Root session prefers a verified Linux/PRoot guest and falls back to the Android-native runtime when the guest is missing or a concrete capability probe fails; an App UID session uses Android native directly. The session boundary, rather than opening Settings or switching Home tabs, owns this decision.
- Targeted Flutter regression command (`local_session_conversation_test.dart`, `settings_model_catalog_test.dart`, and `capability_refresh_test.dart`) passed with exit code 0; the Root-session case still proves that a new Root turn selects the compatibility backend when it is verified, while a restored thread is not silently moved. Google Fonts download messages remain non-fatal test-environment warnings.
- The latest Release APK before this copy-only follow-up was verified and installed on the `codex_api35` AVD. The non-Root launch/home/settings smoke stayed stable: no fatal exception and no `failed to load models cache` log entry were observed. The AVD is only a UI/process smoke surface; physical KernelSU Root, host-root visibility, and a real Codex turn remain unverified because the physical device is offline.

## 2026-09-26 Active app-server plugin listing

- Added `/cli plugin list` as a read-only app-owned route. It now reuses the current session's Codex app-server and session workspace instead of launching an isolated one-shot `CODEX_HOME`; this keeps authentication, provider selection, and per-session state aligned with the visible conversation.
- Added a forward-compatible parser for `plugin/list` that retains only marketplace/plugin identity, install/enable state, version, and featured status. Local paths, source descriptors, and unrelated marketplace metadata are not copied into the transcript or JSON output. Plugin mutation commands remain explicitly reported as not integrated rather than being routed to a misleading isolated writer.
- Added route, protocol-fixture, safe-output, and active-session request tests. `flutter test --no-pub test/codex_cli_arguments_test.dart test/codex_session_client_test.dart` passed all 49 tests. This was a host-side protocol check only; no APK build, device install, KernelSU Root worker, or real plugin marketplace request was claimed.

## 2026-09-26 Plugin route main-entry compile regression

- The main-entry widget regression (`local_ui_navigation_test.dart` and `local_session_conversation_test.dart`) also passed all 22 tests after adding the new route and transcript action. Google Fonts network-load messages remain the existing non-fatal test-environment warning. The static analyzer process itself crashed while serializing its LSP response (`FormatException: Unterminated string`), so that command is recorded as infrastructure-unavailable rather than a source failure.

## 2026-09-26 Root default approval and history restoration

- Corrected the Root permission default to match the project route: a fresh Root session starts with `danger-full-access` and app-server `approvalPolicy=never`, so ordinary commands do not create one approval card per command. App UID and explicit read-only sessions retain their existing approval behavior; the permission picker still exposes an explicit read-only mode.
- Fixed session-history decoding so `danger-full-access` is preserved instead of being silently downgraded to `workspace-write` after reopening. This keeps Root execution settings stable across Home navigation and app restarts.
- Targeted history/auth/conversation regression passed all 40 tests. Google Fonts download messages remained non-fatal test-environment warnings. No APK/device/Root-worker validation was claimed in this source-only change.

## 2026-09-26 Active app-server plugin mutations

- Completed the plugin command path that was previously only listed as a gap. `/cli plugin list` and `/cli plugin marketplace list` read the active session's app-server; `/cli plugin add/remove` and `/cli plugin marketplace add/remove/upgrade` now call `plugin/install`, `plugin/uninstall`, `marketplace/add`, `marketplace/remove`, and `marketplace/upgrade` on that same process and session home.
- Added parser coverage for marketplace source/ref/sparse options, plugin selectors, JSON output, and invalid/ambiguous mutations. Installation resolves a local marketplace path from the app-server catalog or uses a remote marketplace name; UI-safe output excludes local paths and raw installation metadata.
- `flutter test --no-pub test/codex_cli_arguments_test.dart test/codex_session_client_test.dart` passed all 53 tests after Dart formatting. This is host-side protocol/fixture evidence only; no APK build, device install, KernelSU Root worker, or live marketplace request was claimed.

## 2026-09-26 Active app-server thread listing

- Added the Android-specific `/cli thread list` route. It uses the active
  session's `thread/list` RPC, filters to that session workspace, supports
  current or archived threads and an optional title search, follows opaque
  pagination cursors, and provides human-readable or safe JSON transcript
  output. The parser retains thread identity, title/preview, model/provider,
  status, effort, timestamps, and active flags while excluding the rollout
  storage `path`.
- Added forward-compatible thread metadata parsing and fixture coverage for
  active status objects, preview fallback titles, archive/search request
  parameters, two-page pagination, repeated-cursor protection, and malformed
  entries. This does not yet import external CLI history or open an arbitrary
  listed thread into another isolated App session; the existing app-owned
  workspace/session history remains the primary browser.
- Focused Flutter protocol/model tests passed: the thread summary, CLI parser,
  and active session client groups completed with 58 tests; the main-entry
  navigation/session regression completed with 22 tests. Google Fonts network
  fetch messages remained non-fatal test-environment warnings. No APK build,
  device install, Root worker, or live app-server history request is claimed
  here.

## 2026-09-26 Root approval reuse and current launcher audit

- The standalone Host command panel no longer asks for the same Root approval
  before every command or tool probe. After the user approves Root for that
  panel, subsequent actions in the same panel reuse the grant; the Codex
  conversation session already persists its equivalent session-scoped grant.
- Audited the active `apps/codex` Android launcher: Root PRoot uses the normal
  KernelSU `su -c` path and the immediate launch gate checks only a usable
  helper plus real UID 0. The custom `codex_agent` context, fixed group or
  capability gate, `--ksu-no-new-privs`, and protected-write sample gate are
  not required for the current launch path. The similarly named legacy
  `apps/mobile` launcher remains historical and was not changed.
- Validation passed: current Root launch-script and Root profile Kotlin unit
  tests completed successfully; the Host command and local navigation Flutter
  tests completed successfully. No device was online, so no Root worker or
  host-file operation is claimed here.
- The main CC Pocket-style local-session widget fixture now exercises
  `/cli thread list --json` end to end: the composer route reaches the active
  app-server fixture, sends the expected archived/sort/state-db parameters,
  and renders the returned thread metadata. The full local conversation
  regression passed 19 tests, with only the existing non-fatal Google Fonts
  network warnings.

## 2026-09-26 Thread list default invocation

- Fixed the `/cli thread list` parser to accept the valid no-option form. The
  previous minimum-argument check accidentally rejected the default command
  before it could call the active app-server; optioned, archived, searched,
  and JSON forms are unchanged.
- Added a regression for the default request and reran the CLI parser plus
  local-session conversation suites: all 38 tests passed. Google Fonts
  network-load messages remain non-fatal test-environment warnings.

## 2026-09-26 Thread-list protocol downgrade

- Made `CodexSessionClient.readThreads()` tolerate an older app-server that
  rejects newer `thread/list` fields. The normal path keeps workspace,
  search, updated-at ordering, and state-db hints; only an explicit JSON-RPC
  invalid-parameter response retries with the core archive/cursor/limit
  shape. If that fallback cannot accept server-side search, the client filters
  the returned summaries locally instead of silently dropping the request.
- Added a fixture for the older protocol shape and verified that the fallback
  does not trigger on unrelated transport/server errors. CLI/session client
  regression passed 58 tests. No device, APK, or live app-server upgrade was
  claimed in this source-level compatibility change.

## 2026-09-26 Plugin-list protocol downgrade

- Applied the same narrow compatibility handling to `plugin/list`: workspace
  and refresh hints remain enabled for current servers, while an explicit
  invalid-parameter response retries the base request without optional params.
  Method-not-found, authentication, transport, and marketplace errors still
  propagate normally.
- Added an older-server fixture and reran the full session-client protocol
  suite: 40 tests passed. This is source/fixture evidence only; no live plugin
  catalog or device update was claimed.

## 2026-09-26 Overall route and execution principle frozen

- Reconfirmed the project-wide route in `PROJECT_GOAL.md`,
  `PROJECT_DIRECTION.md`, and `ENGINEERING_EXECUTION_POLICY.md`: the product is
  a local Android Codex using the user's normal KernelSU Root path, PRoot Linux
  ARM64 and an independently updatable official Codex CLI/app-server. PC,
  Bridge and a custom SELinux/broker architecture are not part of the normal
  Android product path.
- Reconfirmed the implementation priority: functionality, completeness and
  delivery speed come first. Every defect is handled as actual failure →
  restore availability → assess concrete risk → add protection that does not
  block the feature → targeted validation. Generic or unverified risk is not a
  reason to abandon a capability.
- The only continuously prioritized safety outcome is loss of bootability or
  an unrecoverably bricked device. Boot-related changes use a soft route of
  target verification, recovery assessment and concrete user authorization;
  ordinary Root work, file visibility and application configuration are not
  converted into per-command approval gates. No implementation or build was
  performed for this documentation checkpoint.

## 2026-09-26 MCP settings UI connected to app-server

- Added the CC Pocket-style `MCP & plugins` settings page for the selected
  local session. It uses the existing app-server client rather than a second
  configuration format: redacted MCP config, live status, stdio/HTTP add,
  removal, and browser OAuth login are all wired to the existing RPC methods.
- The page labels changes as session-scoped because each app session owns an
  isolated `CODEX_HOME`; it does not claim to edit every workspace. Secret
  values are not returned by the existing summary parser or rendered in the
  server list. The same page now renders the active app-server plugin catalog
  and exposes install/uninstall actions for the current session.
- Settings initialization now shares one in-flight client-start Future when
  config and status are loaded concurrently, preventing duplicate app-server
  launches for the same session.
- Validation: MCP/plugin settings widget tests passed 4; the existing settings model
  suite passed 9; the main-importing local auth/conversation suite passed 24.
  The existing non-fatal Google Fonts network warnings remain in the test
  environment. No device or APK acceptance was performed.

## 2026-09-26 MCP plugin marketplace settings UI

- Completed the remaining marketplace part of the CC Pocket-style `MCP &
  plugins` page. The selected session can now read empty or populated
  marketplace identities, add a Git/local source with optional ref and sparse
  paths, refresh one marketplace or all marketplaces, and remove a marketplace.
  All mutations use the existing app-server RPCs and remain scoped to the
  session's isolated `CODEX_HOME`; no marketplace storage layout is recreated
  in Flutter.
- Added safe marketplace metadata parsing that preserves empty markets and
  load-error summaries without exposing local paths or raw source descriptors.
  Read-only sessions still reject marketplace mutations; Root sessions reuse
  the existing session-scoped approval grant rather than prompting for every
  marketplace action.
- Focused validation passed: plugin summary, MCP settings, and active session
  client suites completed with 46 tests. No APK build, device install, or live
  marketplace request is claimed; physical ADB is currently offline.

## 2026-09-26 Custom provider effort capability configuration

- Replaced the remaining DeepSeek-only effort gate for native Codex custom
  providers. Provider records now persist an explicit `reasoningEfforts` list;
  old records migrate to `none/low/high/max` for `deepseek-*` and `low` for
  other models. The settings editor validates compact labels, shows them in the
  provider card, and the selected session's model catalog/top effort control
  uses the persisted list.
- Android Keystore provider persistence now round-trips the list through the
  existing encrypted document. The app-server launch path and OpenAI/custom
  auth exclusivity are unchanged; arbitrary providers are not claimed to have
  capabilities the user did not configure. The installed Codex runtime remains
  authoritative and may reject a provider-specific label.
- Flutter provider, settings, CC Pocket mode-bar, launch configuration, and
  local-session regression completed with 48 tests. Android `:app:compileDebugKotlin`
  also passed. These are host/source checks only; the physical ADB endpoint is
  currently offline, so no new device provider turn is claimed.

## 2026-09-26 App-owned CLI session resume routing

- `/cli resume`, `/cli r` and their `--last` form now resume the saved thread
  belonging to the visible app session through its existing `CodexSessionClient`.
  This keeps the same process, `CODEX_HOME`, provider, Root identity, and
  history instead of launching a second unbound CLI operation home.
- A requested thread ID is accepted only when it matches the current session;
  cross-session resume, fork, archive, unarchive, delete, and external
  `migrate-rollouts` remain explicit Home/session-menu operations or documented
  non-parity because importing them would violate the independent-process
  boundary. The generic misleading “standalone CLI session store” message was
  replaced with command-specific guidance.
- `codex_cli_arguments_test.dart` and `local_session_conversation_test.dart`
  passed together with the existing provider regression. No APK/device claim
  was made; physical ADB remains offline.

## 2026-09-26 Plugin enablement control

- Closed the remaining plugin-control gap in the active CC Pocket-style session:
  installed plugins now expose an enable/disable action in `MCP 与插件`.
  The action writes `plugins.<plugin>@<marketplace>.enabled` through the active
  Codex app-server `config/value/write` RPC, so it stays inside that session's
  isolated `CODEX_HOME` and does not recreate `config.toml` parsing in Flutter.
- Added `/cli plugin enable` and `/cli plugin disable` with the same active
  app-server route, JSON-safe result, read-only-session handling, and Root
  session-scoped approval reuse. Overridden config writes are reported as
  failures rather than presented as successful changes; Settings refreshes the
  catalog after a successful mutation.
- Focused Flutter protocol, parser, and settings tests passed all 65 tests.
  This is source/fixture evidence only: no APK rebuild, device install, or live
  plugin mutation was claimed; physical ADB remains offline.
## 2026-09-26 Root helper App-UID 预检误判修复

- 修复 `AndroidRootProfileProbe` 在调用 KernelSU 前使用 App UID 检查
  `/data/adb/ksu/bin/su` 的 `isFile/canExecute` 门禁。该目录可以对 App UID
  不可见，但仍允许通过 `ProcessBuilder` 进入 KernelSU Root 边界；旧门禁会把
  已授权的正常 KernelSU profile 错误显示为 Root 不可用。
- 现在按固定候选路径直接尝试 `su -c`，由 Root 子进程自身返回的真实 UID 0
  证据决定是否可用；没有新增自定义 SELinux 域、组、capability 或 per-command
  审批要求。
- `RootProfileProbeTest` 与 `CompatibilityRootLaunchScriptTest` 定向 JVM 回归
  通过，Gradle `BUILD SUCCESSFUL`。本轮 ADB 仍离线，尚未把该修复称为真机验收。

## 2026-09-26 App-server permission profile 接入与惰性探测回归修复

- 将 CC Pocket 风格权限选择接到 Codex app-server 的真实能力：新增
  `permissionProfile/list` 解析、内置 `:read-only`、`:workspace`、
  `:danger-full-access` 映射、会话设置同步和下一次 `turn/start` 的
  `permissions` 参数。已暴露的自定义 profile 会在权限选择器中显示；未知字段
  会被忽略，不在 UI 中泄露原始配置或密钥。
- 为兼容旧版或裁剪版 app-server，正常启动不再自动探测可选的
  `permissionProfile/list`。只有用户主动打开权限选择器时才惰性读取，失败时保持
  原有 `sandboxPolicy` 路径；因此可选能力缺失不会阻塞普通会话，也不会因为等待
  一个旧 server 的无响应请求而制造假死。
- 会话历史现在保存并恢复选中的 permission profile；Root/PRoot 默认仍沿用现有
  全局可读与会话级 approval 语义。该改动没有新增 per-command Root 审批、SELinux
  域或自定义 broker。
- 验证通过：`codex_permission_profile_test.dart`、`codex_session_client_test.dart`
  与 `session_history_test.dart` 共 57 项；`local_session_conversation_test.dart`
  共 19 项。此前由自动探测引入的会话 turn/UI 回归已消失。Google Fonts 下载失败
  仍只是测试环境警告；本轮没有 APK/device 验收，物理 ADB 仍离线。

## 2026-09-26 旧路线文档覆盖标记

- `INDEPENDENT_APP_ROADMAP.md` 的历史 Phase 2 正文仍把 native-first 写成当前主路线，
  与 2026-09-26 已确认的 Root → PRoot Linux ARM64 → 官方 Codex CLI/app-server 路线
  冲突。已在该文档加入明确的覆盖标记，并将当前下一步改为以
  `PROJECT_DIRECTION.md` 为唯一实施入口；旧 native ABI 条目保留为证据，不再作为
  阻断可工作的 Root/PRoot 主路径的前置条件。
- 本项只修正文档路由，未改变运行时、KernelSU 配置或 Bridge 依赖；没有把文档一致性
  当成产品功能完成。

## 2026-09-26 独立 session fork 与 rollout 恢复

- 补齐 `/cli fork` 和 session 菜单此前“只提示、不执行”的真实功能缺口。
  `CodexSessionClient` 现在调用 app-server `thread/fork`，保存 provider 返回的
  child thread id 与 rollout path；`SessionHistoryRecord` 同步持久化
  `threadPath`，因此 fork 后的 session 不再只靠前端 transcript 冒充上下文。
- 新 session 使用自己的 `CODEX_HOME`、SQLite、临时目录和 app-server 进程。fork
  产生的 rollout 由当前 backend 通过固定 argv `mkdir -p` 与 `cp -p` 复制到目标
  session；不共享源 session 的 SQLite，也不另起未绑定的全局 CLI。打开目标 session
  时通过 `thread/resume.path` 恢复 provider 历史；native→PRoot fallback 递归重启时
  也会继续传递该 path，避免恢复时错误创建新 thread。
- 如果当前 CLI 没有返回位于当前隔离 `CODEX_HOME` 内的有效 rollout path，应用会明确
  报错并不创建伪 fork；这是版本能力缺失提示，不是回退到共享 session 的理由。Root
  approval 仍保持已有的“每个 session 一次”语义，本项没有新增逐命令审批或 KernelSU
  配置改动。
- 定向验证：`codex_session_client_test.dart` 与 `session_history_test.dart` 共 56 项
  通过；包含 `main.dart` 的 `local_session_conversation_test.dart`、
  `ccpocket_native_home_test.dart`、`local_session_auth_test.dart` 共 30 项通过。
  `dart analyze --format=machine --no-fatal-warnings` 退出码为 0，输出仍包含仓库既有
  warnings/infos；Flutter analyze 包装器仍会遇到已知的截断 LSP JSON 异常。Google Fonts
  测试下载失败仍只是环境日志，不影响上述测试结果。本切片未重建 APK，也未声称真机
  fork/恢复已经验收；当前物理 ADB 仍离线。

## 2026-09-27 Root session 登录态继承与网络失败误报修复

- 根因确认：设置页的兼容层登录命令不设置 `CODEX_HOME`，Codex 按默认规则把
  `auth.json` 和 `config.toml` 写入共享 `HOME/.codex/`；而真实 Root/PRoot
  会话会把 `CODEX_HOME` 隔离到 `/home/codex/sessions/<id>`。旧的 session-home
  初始化只从共享目录根部寻找 seed 文件，导致新会话没有 bearer。app-server 的
  认证失败随后被前端统一归类成“网络连接失败”，造成网络故障的假象。
- `CodexSessionHome` 现在同时识别共享 home 根部和 `.codex/` 下的 seed 文件，
  在两种布局同时存在时选取最近修改的有效文件，并复制到隔离会话根部。这样
  OpenAI 登录、模型配置和 Root/PRoot app-server 使用同一份登录态，同时保留每个
  session 独立的 SQLite、rollout、临时目录和事件流；没有把 session 再合并回共享
  `CODEX_HOME`。
- 回归验证：`CodexSessionHomeTest` 通过，包含 `.codex/auth.json` 与
  `.codex/config.toml` 到兼容 session 根目录的 seed 场景；正式 Release 构建成功，
  APK SHA-256 为 `6449656CCA380E9E41A46E0EDCE68E215FD602AE4ACD6371AA8677092FAB1450`，
  已通过 ADB 安装到 `6cb21282` 且保留应用数据。
- 真机数据面已验证：新建 Root session 后目标目录存在会话专属 `auth.json`；
  KernelSU → PRoot → Codex app-server 进程链保持 UID 0，真实 turn 返回
  `REAL_ROOT_AUTH_OK`，界面从“运行中”进入“就绪”，上下文 `10%`、Codex 用量和
  assistant 回复均正常显示。app-server 同时报告过一次独立的 models catalog
  refresh timeout；它没有阻断该真实 turn，当前仍作为非阻断的模型目录刷新问题留在
  后续诊断项，不再把它等同于会话认证失败。

## 2026-09-27 Root session 模型缓存冷启动修复

- 继续追踪模型目录超时后确认：兼容层共享 `home/.codex/models_cache.json` 已存在，
  但每次 session 初始化都会删除隔离目录里的缓存，再让新 app-server 从网络冷启动
  模型目录。Root turn 本身已经可用，因此这个删除动作只增加了模型发现的脆弱窗口。
- session-home 现在按执行身份处理 derived cache：Root session 保留已有缓存，并在
  新 session 没有缓存时从共享 CLI cache 复制一份作为离线起点；App UID session
  继续清理 Root-owned cache，避免权限错误。CLI 仍可在后台刷新缓存，动态模型发现
  和 session 隔离没有被硬编码列表替代。
- `CodexSessionHomeTest` 通过新增 Root cache seed/保留场景，`codex_model_catalog_test.dart`
  通过分页模型目录场景。正式 Release 已编译，SHA-256 为
  `DA1A6AF8A1591D1093B4CB61ED05A1A1C88480729E63B41287E63AEA932D5888`；由于真机上仍有
  一个已成功完成且保持运行的 Root session，本次未强制替换安装，避免无用户停止动作
  破坏活跃会话。待该 session 正常结束后再做真机冷启动模型缓存复测。

## 2026-09-27 网络失败误报收敛与空闲诊断隔离

- 继续从“网络连接失败”提示反查事件流，确认 app-server 启动阶段和模型目录后台刷新也会
  通过 stderr 输出 transport 诊断；旧逻辑不区分 turn 是否存在，可能把空闲会话直接标成
  provider failed，并留下可误导的重试状态。
- 现在只有正在发送或运行中的 turn 才会把 provider transport 错误升级为会话失败；启动阶段
  的失败仍由启动异常路径给出真实错误，空闲阶段的非 turn 诊断不再杀死可用 session。turn
  完成后清除 in-flight prompt，避免上一轮 prompt 让后续空闲诊断获得错误的重试上下文。
- `codex_models_manager::manager: failed to refresh available models` 被统一视为非致命的
  derived-cache/模型目录 housekeeping 诊断；模型目录客户端仍按 live CLI、app-server、
  bundled/cache fallback 合并，不用该诊断覆盖可工作的会话。
- 定向验证：`session_history_test.dart` 与 `local_session_conversation_test.dart` 共 37 项
  通过；新增用例覆盖 idle provider diagnostic 不进入失败态，以及 request-timed-out 模型
  刷新不污染会话预览。Android `CodexSessionHomeTest` 通过，`dart analyze --format machine`
  无 error（仅仓库既有 warnings/infos）；Flutter analyze 包装器仍遇到已知 LSP JSON 截断，
  不把该工具故障当成代码失败。正式 Release 已重新编译，APK SHA-256 为
  `DEBF21E463E060C8B8077916713AD3F9BED4730568B5AB03F91653A416AF45C2`；补丁尚未安装到真机，
  当前成功 Root session 未被中断。
- 随后完整 `flutter test` 共 290 项全部通过。真机当前会话的最终 PATH 解析也已核对：
  Debian guest 提供 `git`、`python/python3`、`node`、`npm`、`npx`；绑定的 Android ARM64
  native toolchain 提供 `rg`、`jq`，并作为 guest 缺项的 PATH fallback。当前版本不需要为
  这些命令再引入 Bridge 中间层或改变 Codex CLI 的调用协议。

## 2026-09-27 PRoot Android-native 工具的动态链接路径修复

- 真机对照复现了 native-toolchain fallback 的启动缺陷：PRoot 可找到 Android ABI
  Node/npm，但默认环境下 Bionic linker 报 `libc++_shared.so not found`；仅设置
  `/data/local/tmp/io.henry.codex/native-tools/lib` 后，Node `v22.23.2` 与 npm
  `10.9.2` 均能正常启动。
- `compatibilityGuestCommandArgv` 现在仅为从 Android native toolchain 解析出的命令
  注入专用 `LD_LIBRARY_PATH`；npm/npx 仍通过 guest `/bin/sh` 运行 Android wrapper，
  并继承该路径。Debian guest 和用户安装的 Linux 包命令仍保持原有环境，不会被
  Bionic 库目录污染。
- 定向 `CompatibilityCommandArgvTest` 通过。真机在同一 PRoot/rootfs 中使用 native npm
  经现有代理安装 `debug@4.4.0`（2 个包），确认安装产物版本正确；两次临时目录均已
  清理。当前 Root Codex/app-server 会话仍在运行且未被中断。
- Release APK 已重建并由 `verify-android-apk.ps1 -RequireCodexNativeAssets` 通过签名、
  包名与 PRoot/native 资产检查；SHA-256 为
  `A9A175197B6D0563B4E103EEBC6192C8F6C474D121752D5284EA4931F57A9339`。产物使用本地
  Android debug certificate（不是发布签名），尚未覆盖安装；待活跃 session 结束后
  再做更新版真机回归。

## 2026-09-27 第三方 Responses 模型目录与真机连通性验证

- 使用隔离的临时 `CODEX_HOME` 在真机通过自定义 Responses provider 完成一次真实
  DeepSeek turn，返回预期标记，证明该设备当前 Root/PRoot 网络链路能到达第三方服务；
  这不等价于已验证 OpenAI OAuth 路径或新版 App UI。
- 真实 turn 暴露出 Codex 对 `deepseek-flash` 使用 fallback metadata 的警告。现在每个
  provider session 在自己的 `CODEX_HOME/models.json` 生成模型目录，并在 app-server
  启动参数中指定该文件。自定义 API key 仍只通过进程环境变量传递；目录 JSON 仅作为
  session 启动期传输，Android process manager 写盘后会从子进程环境中移除该传输变量。
- DeepSeek Flash 元数据按官方 Codex 接入示例填入图像输入、上下文、推理档位和工具
  能力；任意 OpenAI-compatible provider 使用 Codex 要求的基础模型字段，未知上下文
  不猜测。补齐 `priority`、`experimental_supported_tools`、`support_verbosity` 与
  `truncation_policy` 后，后续真机 CLI 检查仍发现模型目录缺少必需的 Codex 指令模板；
  因而该次静态测试和 APK 构建并不足以证明 metadata 可被当前 CLI 完整接受。
- 已改为从当前安装 CLI 的 `codex debug models --bundled` 动态选取指令模板，优先匹配
  当前模型，找不到时使用 bundled catalog 中首个带模板的模型，不在 APK 中复制某版本
  的大型 GPT 指令文本。该模板与自定义模型 metadata 写入 session 隔离的 `models.json`；
  UTF-8 总大小超过 64 KiB 时明确报错，不传 API key 到目录文件。
- 真机 Root/PRoot 中使用当前安装的 Codex CLI 对该目录执行 `debug models`，退出码为 0，
  实际读回 `deepseek-flash`、上下文 `1048576`、推理档位 `low`。这是 CLI 目录解析验证，
  不等于新版 Android UI/app-server 已安装或完成第三方真实 turn。验证期间现有 App、
  Node 和 Codex/app-server PID 均保持运行，未中断活跃会话。
- 针对先前“网络连接失败”提示做了只读真机补测：在 Root/PRoot 中使用 Android 当前
  resolver、CA bundle 和显式代理，对 OpenAI 与 DeepSeek 的无凭据 models endpoint 均收到
  HTTP 401 且 TLS 验证成功。这证明当前 DNS/代理/TLS 传输可达；401 是未附认证的预期响应，
  不证明账户认证、Codex app-server 请求或完整真实 turn 成功。该探针没有使用 API key，
  现有 App/Root Codex 进程仍保持运行。
- Flutter provider 定向测试现为 10 项通过；Android `CodexSessionHomeTest` 此前通过，
  本轮 Kotlin 未改动。直接从中文仓库路径构建时，Flutter Gradle 插件因 Windows 非 ASCII
  路径报 `parent is null`；使用仓库既有 `tools/build-android.ps1` 的 SUBST ASCII 路径后
  Release 构建成功。APK 经 `verify-android-apk.ps1 -RequireCodexNativeAssets` 验证，
  SHA-256 为 `36d870c14825c80b0ef9b514008c5cad87b5d8a1f765625dd11616e680b19c60`，五项
  PRoot/native 资产齐全、签名有效，仍为本地 Android debug certificate（非发布签名）。
- 新 APK 尚未覆盖安装：真机 Codex/app-server 会话仍运行，当前进程未被打断。后续仍需在
  活跃会话自然结束后安装，验证新版 App 启动时的动态模板读取、无 fallback metadata
  警告，以及新版 UI 发起的真实第三方流式 turn。

## 2026-09-27 PRoot 常用包运行依赖与安装目录一致性

- 为诊断网络提示尝试启动 rootfs 自带 curl 时，观察到 `/usr/bin/curl` 在发起任何请求前
  就因缺少 `libkeyutils.so.1` 无法加载。Python 使用相同 Android resolver、CA 和代理对
  OpenAI/DeepSeek endpoint 完成 TLS 并得到无凭据预期 401，故 curl 缺库是工具包缺口，不是
  Codex 网络探针失败的原因。
- Debian ARM64 rootfs 构建清单已显式包含 `libkeyutils1`；用户包安装脚本的 prefix 已从
  `/home/codex/.local/ccpocket-pkgs` 对齐为运行时实际搜索的
  `/home/codex/.local/codex-pkgs`，Agent 指引也区分用户包层与 Root PRoot 内直接 apt。
  真机当前共享 guest home 下尚无旧 `ccpocket-pkgs` 数据，因此无需迁移或删除现有包。
- Shell 语法检查通过，包安装器容器测试因本机 Docker Desktop daemon 未运行而未执行；本轮
  未重建/部署 rootfs，也未更改手机文件。Rootfs 更新需在当前活跃 Codex session 自然结束后
  单独构建、校验并替换；当前真机 worker 仍保持原 PID。

## 2026-09-27 官方 npm 更新源连通性探测

- 在真机 Root/PRoot 中使用 guest 自带 npm 与显式 `https://registry.npmjs.org` registry
  查询 `@openai/codex`，命令成功并返回版本 `0.157.1`。这验证了 CLI updater 所需的
  npm registry 查询路径当前可达，不代表该版本已安装或已执行升级。
- 查询期间现有 app、worker、PRoot、Node 与 Codex PID 未变化；仅删除本轮创建的
  `/data/local/tmp/codex-update-probe-20260927` 隔离临时目录。活跃 session 保持运行，
  新 APK 仍待 session 自然结束后再安装验证。

## 2026-09-27 正常 KernelSU Root 与 Android 宿主视图真机复核

- 活跃 Codex worker `14506` 的 `/proc` 证据为 UID/GID 0、groups `0 3003 3009`、
  `CapEff=CapBnd=000001ffffffffff`、SELinux `u:r:ksu:s0`；它运行的 CLI 为
  `0.156.1`。当前 npm registry 查询到 `0.157.1`，仅确认新版本可见，未在活跃进程中切换。
- 活跃 PRoot argv 明确包含 `--root-id` 和 `--bind=/:/android!`。另用同一设备 rootfs
  执行隔离只读探针，成功读取 Android `/system/build.prop`、`/data/system/packages.xml`，
  并成功枚举 `/data/user/0`、`/data/app` 与 `/dev/block/by-name`；未输出文件内容，也未写入
  这些路径。五个检查结束后 app、worker、PRoot 与 Codex 原 PID 均未变化。
- 源码复核确认 `RootProfileLaunchGate` 只验证受支持的 KernelSU `su` helper 和真实 UID 0；
  不强制 `codex_agent`、固定 groups/capabilities 或 boot 写拒绝样例。`u:r:ksu:s0` 在探针
  和 Android `RootProfileProbeTest` 中均可通过。新 Root session 默认使用
  `danger-full-access` + `approvalPolicy=never`；显式选择应用级只读时才拒绝写操作。
- 验证：`RootProfileProbeTest` Android JVM 测试通过；`root_access_policy_test.dart` 11 项、
  provider metadata 测试 10 项、CLI updater/model catalog 测试 16 项通过。Node/npm updater
  通过真机 registry 只读查询发现 `0.157.1`，尚未执行正式应用内升级。
- Rootfs 离线测试脚本的 Bash 语法检查通过；后续在 Windows Git Bash 环境因缺少 `python3`
  命令别名而停止，WSL 也无法启动 `/bin/bash`。锁文件校验已改用本机 Python 3.11 单独运行并
  通过（282 个 pinned packages）。本轮没有构建或替换 rootfs，也没有安装 APK；新版真机 UI、
  CLI 升级后的真实 turn，以及 KernelSU 插件设备操作仍待后续验证。

## 2026-09-27 R4 KernelSU 插件安装/启用路径恢复

- 移除 broker 对 R4 启用、回滚、停用、卸载和声明式 action 的永久拒绝；安装/启用/回滚
  仍要求用户在 UI 明确确认。R4 首次安装和回滚恢复后保持 disabled，启用需要独立确认；
  不依赖自定义 SELinux 域，也不要求系统凭据弹窗。
- 设置页对 R4 展示模块摘要、boot 条目、目标根目录、SHA-256 和重启标记；R4 安装后不自动
  启用。用户可以通过现有固定 KernelSU 操作停用或卸载。归档格式、模块 ID、路径和哈希验证
  未移除。
- `PluginBrokerTest` 定向 Gradle 测试通过，覆盖 R4 安装、单独启用、确认后回滚且恢复为禁用、
  停用和卸载；`kernelsu_plugin_settings_test.dart` 5 项通过，覆盖 R3/R4 UI 确认流程。
- 尚未安装新版 APK，也未在真机实际触发 KernelSU 插件操作；设备验证推迟到当前活跃 Codex
  session 自然结束后，避免中断运行中的会话。

## 2026-09-27 R4 改动的 Release 产物

- 使用仓库 `tools/build-android.ps1 -Mode release` 从当前源码重建 Release APK；
  `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 验证包名 `io.henry.codex`、签名有效，
  且 PRoot、loader、host trampoline、worker guard、root-read-broker 五项 ARM64 资产齐全。
- APK SHA-256：`00275fa050aabbb9f636d020eb43f75e1e3f8944d995dca7777bdf78bf604f5e`，大小约 112.2 MiB。
  当前使用 Android debug certificate 签名，不是发布证书；尚未配置/验证正式发布签名。
- 真机仍运行 app PID `9140`、worker guard `14470`、PRoot `14473`、Node `14485`、Codex
  `14506`；安装时间早于当前 APK 构建。本轮没有覆盖安装，保留活跃 session，待其自然结束后
  安装并做新 APK 的真机回归。

## 2026-09-27 Root 未分类操作与第三方 provider 启动回归

- 将 Root 策略落到代码：普通绝对路径、相对路径、未知命令和缺失/未知权限 scope 不再仅因
  “分类器无法识别”而进入通用逐条审批；新建 Root 会话保持普通 Codex 执行路径。显式只读
  session 仍拒绝写入；`/`、KernelSU 控制文件、raw block 等已识别目标继续保留授权路由，
  system/boot 目标优先提示可撤销 KernelSU 模块，但不永久拒绝获明确授权的必要操作。
- 会话 widget 回归测试覆盖 `npm install debug@4.4.0` 未分类命令自动接受；现有 Root 普通
  文件变更不要求额外备份审批、只读 session 拒绝写入、CLI 与 DeepSeek/custom provider
  隔离测试均通过。Root 策略 11 项 + 会话交互 21 项，共 32 项通过。
- 修复 custom-provider 对话测试的 runtime probe fixture：补齐绝对 `home` 字段，以便实际
  构造 session 隔离的 `CODEX_HOME`；此前该字段缺失会在 app-server 启动前触发
  `An isolated absolute Codex session home is required for a custom provider.`。这属于测试夹具
  与本地 runtime descriptor 不完整，不是网络或 DeepSeek 响应错误。
- 同步 `ROOT_ACCESS_POLICY.md` 的当前契约，明确普通/未知 Root 操作直通、已识别高风险目标软
  路由、KernelSU profile 仍由用户管理，并将旧实现说明留作历史记录，避免过期的
  `codex_agent`/unknown approval 方案被误当现行要求。
- 使用 `tools/build-android.ps1 -Mode release` 构建，并由 APK verifier 验证包名
  `io.henry.codex`、签名有效、五项 ARM64 Codex runtime 资产齐全。APK SHA-256：
  `3b7d127b90fe036ba2da6b840afec19438ee8136b23423bae8b8c98600e31a18`，大小 112.2 MiB；
  仍由本机 Android debug certificate 签名，不是发布证书。
- 构建期间真机 worker guard/PRoot/Node/Codex 仍运行；本轮未安装 APK、未停止 App 或会话。
  APK 已就绪，仍需在活跃会话自然结束后覆盖安装并做真机 Root 命令与 provider turn 验证。

## 2026-09-27 Android 宿主命令直连指引

- 确认 Root PRoot 的既有启动参数除完整宿主根目录 `/android` 外，还会把存在的
  `/system`、`/vendor`、`/data` 等宿主目录挂载在 guest 的原路径；未增加新的命令 broker。
- 真机只读检查确认 `/system/bin/pm`、`settings`、`cmd`、`dumpsys`、`getprop`、`logcat`、
  `am` 都存在。已把 `/system/bin/...` 直接调用方式写入 app-server 注入指引和会话
  `AGENTS.md`，同时保留 `/android/<path>` 作为宿主文件路径；要求 Codex核对命令结果、按需
  查询，不把 Linux guest 工具与 Android framework 命令混淆。
- `CompatibilityRootLaunchScriptTest` 定向 Gradle 测试通过；新增 Android Codex Agent 指引
  测试通过，Root policy 11 项也通过。该证据验证了绑定规则和指引内容，不等于已从 PRoot
  内成功执行这些 Android 命令。
- 真机仍有 app PID `9140` → Root worker guard `12653` → PRoot `12655` → Node `12664` → Codex
  `12672` 活跃，故未导航离开会话或覆盖安装。新版 Release APK 已重建并校验：SHA-256
  `d5ac4f2dae69c7d680d422f1640b90e08a003b8105fbe918eee10a20af75e094`，五项 ARM64 runtime
  资产齐全，签名有效但仍为 debug certificate。待活跃会话自然结束后安装，验证 PRoot 内
  `/system/bin/getprop` 与 package 查询，再验证 provider turn 和 CLI updater。

## 2026-09-27 可重试网络错误误报为会话失败

- app-server 的 `error`/`warning` 通知会把消息放在嵌套的 `params.error.message`；
  解析器现已读取该字段。`willRetry=true` 表示当前是可恢复的中间错误，UI 保持 turn
  运行，不再弹出“网络连接失败/重试”；stderr 的 WebSocket 诊断也不再被当作终态错误。
  `willRetry=false` 仍按终态网络失败展示错误和重试入口。
- 两个定向 widget 测试通过：新增的重试中继续运行/终态失败回归测试，以及既有的
  provider 网络重试同 thread 重发测试。`dart analyze` 完成但报告 38 条既有 warning/info，
  没有针对本次改动的 error；`flutter analyze` 的 analysis-server 管道异常退出，因此以
  直接 Dart analyzer 结果为准。
- Release APK 已构建并通过只读 APK 验证：包名 `io.henry.codex`、签名有效、五项 ARM64
  Codex runtime native assets 齐全；SHA-256：
  `72c24897be0aef05a39a6bbbd1c6b652396f9e188af9c6f64a578a785361400b`，大小 117,669,302 字节。
  当前仍由 Android debug certificate 签名，不是发布证书。
- 构建后 ADB 未发现真机，未尝试覆盖手机或触碰其 session。改用只读 `codex_api35`
  x86_64 AVD 安装并启动该 Release APK；首页正常出现、App 进程存活、最近日志无 FATAL
  crash。该 AVD 无 Root，且本 smoke 未发起 provider turn，因此不代表 Root 或真实网络验收。
  AVD 已停止并确认 5590/5591 无监听。此修复尚未在真机真实网络 turn 中验证；手机重新连接后
  再验证自动恢复与终态错误展示。

## 2026-09-27 ARM64 PRoot rootfs 更新与工具安装期验证

- 使用 WSL2/Linux x86_64 生成独立 Debian Bookworm ARM64 foreign rootfs，Codex 升至官方
  `@openai/codex@0.157.1-linux-arm64`，Node 为 24.19.0；Debian snapshot 仍固定为
  `20260821T000000Z`。Codex npm integrity 与 SHA-256、Node 官方 SHA-256 均校验通过。
- 产物放在仓库外：
  `C:\Users\Henry\Documents\个人项目\android_codex-runtime-artifacts\rootfs-20260927\`；
  gzip tar 为 315,178,811 字节，12,093 个条目、展开 787,091,782 字节，SHA-256
  `f979fef284cb5b82cc8f95864ac1ef6b57c51c92c31b9b37cebc1792c30fb970`。构建器自己的 archive
  safety 和 manifest schema 验证均通过；Debian 首阶段缓存含 ARM64 curl、git、python3、
  python-is-python3、libkeyutils1 等已校验包，`python-is-python3` 包含 `python -> python3`。
- WSL 的 `/tmp` 是随发行版实例退出而重置的 tmpfs；将本次 `--keep-work` 诊断目录改放到
  `/home/henry` 持久文件系统后，先前 `/dev` 清理错误不再复现，rootfs 归档成功。没有改动
  KernelSU 配置或启动本地监听。
- PRoot 二阶段 finalizer 现会在设备端确认 `curl/git/python/python3/npm/npx --version` 均可
  实际启动，并确认 CA bundle 存在；离线回归增加对应契约与 rootfs 包集检查。更新后
  `tools/android-local-runtime/builder/test-offline.sh` 全部通过，Bash 语法与 `git diff --check`
  通过。构建器默认 Codex 版本与 README 示例同步更新到 0.157.1。
- 产物仍是待设备二阶段 finalize 的 foreign rootfs，**尚未证明这些命令已经在手机运行**。
  本轮 `adb devices` 为空；唯一可用 AVD 为 x86_64，无法执行此 ARM64 rootfs，也没有
  KernelSU。待 ARM64 手机重新连接后，用独立安装器推送并运行二阶段，再实际验证工具版本、
  HTTPS 与真实 Codex turn；因此本轮不宣称原网络错误已在真机最终解决。

## 2026-09-27 session 并发与 Root 启动回归续测

- 对当前 `apps/codex` 运行涵盖 session 历史/生命周期、CC Pocket session UI、第三方 provider
  启动、CLI 更新、模型目录和 provider 配置的定向 Flutter 回归，共 83 项通过。测试环境的
  Google Fonts 网络请求仍会输出失败日志，但未导致测试失败。
- 进一步运行 `codex_session_client_test.dart` 与 `ccpocket_native_home_test.dart` 时发现一个
  旧断言仍要求注入指引把“unknown or broad writes”列为需批准范围，这与 2026-09-26 用户确认的
  普通/未分类 Root 直通路线矛盾。将断言改为验证“ordinary and unclassified Root operations
  remain direct”；改后两文件 47 项全部通过，含两个会话进程独立存活、分别停止/继续，以及同一
  workspace 下独立打开多个 session 的回归。
- Android `RootProfileProbeTest` 与 `CompatibilityRootLaunchScriptTest` 定向 Gradle JVM 测试通过：
  `:app:testDebugUnitTest --offline --no-daemon --max-workers=1`，`BUILD SUCCESSFUL`。这仅验证
  Android 侧代码/合同，不证明设备的 KernelSU 或 PRoot 运行状态。
- 本轮 ADB 仍无设备；唯一 AVD 为 x86_64，不执行 ARM64 Rootfs 安装或伪称 Root 验收。当前缺口仍是
  新 rootfs 的 ARM64 二阶段安装、工具实际运行、HTTPS 和真实 Codex turn；测试断言修正不改变 APK，
  未为它重复编译 Release 包。

## 2026-09-27 rootfs 更新保留 guest home

- 检查独立兼容 rootfs 安装器时发现：更新会在新 slot 创建空 `/home/codex`，切换后删除整个旧
  slot，因此旧 home 内的用户包、npm/pip 数据和隐藏状态可能随更新丢失。
- 安装器现会在激活新 slot 前，将旧 home 的全部内容（包括 dotfiles）复制到新 home；这会保留
  `/home/codex/.local/codex-pkgs` 等用户前缀包数据。若旧 home 是符号链接或非目录则停止安装，避免
  在迁移路径异常时直接丢弃旧用户数据。README 和离线合同检查已同步。
- PowerShell 脚本 AST 解析、`git diff --check` 及 Git Bash 下的嵌套包目录/隐藏文件复制 fixture
  通过。完整 `builder/test-offline.sh` 未跑完：WSL 当前缺少 `/bin/bash`，Git Bash 在本工作区路径
  下的既有绝对符号链接 archive fixture 报错；这与本次 home 迁移无关。ADB 仍无设备，因此该安装器
  改动尚未在 ARM64 手机执行；没有触碰设备或其活跃 session。

## 2026-09-27 PRoot Codex CLI 用户回退入口

- 补齐应用内 CLI 更新的人工回退路径：设置页新增“回退 Codex 命令行工具”，仅改变之后新启动
  的 session 使用的 launcher，不终止或切换现有进程；回退成功后刷新模型目录。
- 回退只会选择经实际执行 `--version` 验证、且版本低于当前 CLI 的候选项，优先选最高的旧 overlay；
  若没有旧 overlay，则尝试 rootfs 自带的 `/usr/local/bin/codex`。没有更旧版本时保持当前链接不变。
  切换后会再次核对实际版本；执行或核对失败时恢复原 launcher。该路径与 Android/Bionic CLI 更新相互独立。
- 定向 Flutter 回归 `codex_cli_updater_test.dart` + `settings_model_catalog_test.dart` 共 20 项通过，
  覆盖最近旧版本选择、rootfs fallback、无旧版本不变更、设置确认/模型刷新，以及更新器既有验证失败
  回滚。定向 Dart analyze 没有 error；输出 22 条项目已有 warning/info（未落在新增逻辑上）。
- 当前 `adb devices -l` 无设备；本轮未构建/安装 APK，也未做 ARM64 设备实测。后续仍需真机验证
  launcher 路径解析、PRoot 内的实际版本切换及更新后真实 turn；模拟器或 widget 回归不能代替该验收。

## 2026-09-27 Root PRoot 的 sudo 直通与 guest apt

- 找到基础工具链使用中的身份不匹配：安装进 guest home 的 `sudo` helper 只接受 guest UID 1000，
  所以真实 Android UID 0 的 Root PRoot 执行常见 `sudo apt install` 会被 helper 拒绝，即使 Root
  worker 本身已能直接管理 Linux guest。现在 helper 版本升为 v3：真实 Root guest UID 0 下 `sudo`
  透明执行原命令；App UID guest 1000 仍使用原有用户前缀下载/解包路线，其他 guest UID 明确报错。
- Kotlin 安装器现在能升级已知 v1/v2 helper 到 v3；同步修正 App 注入和 runtime `AGENTS.md`，区分
  App UID 用户包前缀与 Root PRoot 对 Debian guest rootfs 的常规 apt 操作，不把 guest apt 写入误认成
  Android host 写入。
- 验证：helper `bash -n` 与模拟 UID 0 的透明命令转发 fixture 通过；Android
  `CompatibilityGuestAdminInstallerTest` Gradle JVM 定向测试通过（包括 v1/v2 helper 升级）；Flutter
  `android_codex_agents_test.dart` 与 `root_access_policy_test.dart` 共 13 项通过；`git diff --check`
  通过。ADB/ARM64 设备尚未连接，本轮未构建或安装 APK，Root PRoot 内真实 apt 及 App UID 包安装尚待
  真机验证。

## 2026-09-27 应用内安装/更新 Linux 兼容 rootfs

- 设置页新增 Linux/PRoot rootfs 安装与更新入口，通过 SAF 选择本地目录；导入前校验配套 manifest、
  ARM64 目标、压缩包长度与 SHA-256，并流式检查 tar 路径、链接、文件类型及权限位。只接受固定
  rootfs installer/finalizer，安装期间锁住 runtime 启动/探测并拒绝打断仍在运行的 Codex sessions。
- Root 安装器把新 rootfs 安装到应用私有 staging slot，验证 guest 内 Node/Codex 后原子切换；保留
  现有 `/home/codex`（包括隐藏状态及用户包目录），不把升级所需文件写到 Android 公共目录。
- 对真实构建归档运行 App 自己的 manifest + streaming tar 检查时，发现两个原本由小型 fixture
  遗漏的合法格式：PAX `atime/ctime` 字段，以及 tar 约定的符号链接 `0777` mode。已只放行并忽略
  这类不影响解包路径/权限的标准 metadata；路径、特殊文件、硬链接、未支持的 PAX/xattr 字段，
  以及目录/普通文件的 set-id 与 world-write 检查仍保留，并加入回归用例。
- 验证：Kotlin 检查器 5 项定向测试通过，其中包括直接读取 315 MB 实际 ARM64 rootfs；manifest 与
  App 扫描结果精确一致：12,093 members、9,651 regular files、787,091,782 unpacked bytes，实际
  SHA-256 与 manifest 相同。Flutter rootfs installer/runtime/backend 测试通过，installer 脚本
  `bash -n` 通过。修复后 Release APK 重建成功，签名/包信息及五个 ARM64 native assets 验证通过
  （SHA-256 `d9ae1b3168387eea55772b09cb7b2844c5bf33aeb110c859de215ee411546a3f`）。
  x86_64 API 35 AVD 上安装启动成功，Settings 入口、确认弹窗和 SAF 文件夹选择器可达，取消后进程仍在，
  未观察到应用崩溃；临时 AVD 已关闭并释放 5560/5561。APK 使用 Android debug certificate。
- 尚未在 ARM64 真机执行 KernelSU/PRoot rootfs 安装、更新、guest 工具或真实 Codex turn；模拟器 UI
  smoke 不能证明这些设备侧能力。当前 ADB 无真机连接，因此这些仍是本功能的真实验收缺口。

## 2026-09-27 设置页模型目录冷启动异常

- 完整 Flutter 回归首次发现 Home/Settings 导航测试在 runtime 不可用时产生未处理的
  `Codex runtime is not ready for model list`。根因是打开设置路由前，父页面 eager 启动 CLI
  模型目录 Future；runtime 错误可能早于设置页 `FutureBuilder` 订阅而完成。
- 设置路由现在只传递已缓存的模型目录；未加载时由模型 tile 在用户点击后启动并立即 await
  当前 CLI 查询。模型列表仍动态读取，失败仍显示设置页重试状态；不再为打开设置而额外启动 CLI。
- 两个原失败 Home/Settings 测试及模型目录/更新设置回归共 14 项通过；随后完整 Flutter 测试
  `306/306` 全部通过。
- 修复后 Release APK 重建并通过 `verify-android-apk.ps1 -RequireCodexNativeAssets`：包名
  `io.henry.codex`、签名有效、五个 ARM64 PRoot/native assets 齐全；SHA-256
  `1c4b6bb6b0fedb17966fc1bebe53f84dcf2a8056e81142f291c901906796a08d`。仍使用本机 Android
  debug certificate。当前 ADB 无真机，本包尚未安装到手机；设备端 Root/PRoot 验收缺口仍在。

## 2026-09-27 Android 本地回归汇总

- 独立 App 完整 Flutter suite：306 项全部通过。Android `:app:testDebugUnitTest`：106 项、0 失败、
  0 error；其中 1 项可选的真实 rootfs artifact 测试因未设置外部 artifact 参数而跳过，该项此前已
  单独对本地生成的 315 MB rootfs 执行并通过。
- 最新 Release APK 仍为上一节记录的 `1c4b6bb6...`；包内 ARM64 资产完整。ADB 当前无连接设备，
  因此没有安装或打断任何手机 session；KernelSU 真机安装、并行真实 turn 和更新后网络路径仍待设备侧验收。

## 2026-09-27 设置页模型目录重试 Release UI 烟测

- 最新 Release APK 安装到 `codex_api35` x86_64 API 35 AVD 并启动成功。设置页未自动启动 CLI 模型
  进程；模型行显示“点击读取 CLI 模型目录”。点击后，AVD 因没有 Root/runtime 显示明确的
  `Codex runtime is not ready for model list` 和重试提示，App PID 仍存活，logcat 无 `FATAL EXCEPTION`。
- 此结果直接验证错误停留在可重试 UI，而不是无处理 Future；它不证明模型查询或 Root 运行时可用。
  AVD 已停止，5570/5571 无监听，端口登记已释放。实体手机仍未连接。

## 2026-09-27 新会话模型默认与网络失败诊断

- 新会话与缺失模型字段的旧记录默认值从过时的 `gpt-5.6-luna` 调整为用户指定的
  `gpt-6-luna` / `low`。用户已经明确选过模型或恢复既有 session 时保留原选择；未显式选模型时，
  成功读取 CLI 实时目录后自动采用目录中第一个可见 Luna，若没有 Luna 则采用第一个可见模型，
  并跟随该模型支持的 effort。隐藏模型不会成为自动默认。
- 模型目录不再为未显式选择的 session 强行插入过时当前值；仅用户已选/历史 session 需要保留
  当前值时才继续将其加入 picker。新增目录推荐选择测试，覆盖 Luna 优先、隐藏模型过滤和无 Luna 回退。
- 网络失败 retry banner 和会话错误现在显示脱敏后的根因类别（TLS/证书握手、DNS、超时、拒绝、
  重置、网络不可达或 WebSocket），仍保留原有重试操作；不直接展示或持久化 app-server 原始诊断。
  新增本地化/密钥不回显测试，并在真实会话 widget 回归中确认 TLS 分类可见。
- 定向模型/session 测试 62 项通过；新增网络诊断和完整会话测试 26 项通过。合并后完整 Flutter
  suite `311/311` 通过。`dart analyze` 对所选文件报告 47 条 warning/info、没有 error；其中包含
  多个仓库既有未使用声明和 lint 提示，本轮未扩大清理范围。
- Release APK 重建并经 `verify-android-apk.ps1 -RequireCodexNativeAssets` 验证：包名
  `io.henry.codex`、签名有效、五项 ARM64 PRoot/native assets 齐全，大小 117,751,063 字节，
  SHA-256 `6f05be99f4f65e4596250fda0af3322b9200a4f5761071195af97fef09e57309`。仍为本机 debug
  certificate。构建后 ADB 仍为空；因此这次默认模型请求及根因 banner 尚未在真机上验证，
  原始网络故障也未宣称已修复。

## 2026-09-27 OpenAI app-server Android HTTP/SSE fallback

- 为 Android 的 OpenAI OAuth/API-key app-server 启动参数注入 Codex 原生 provider 配置：使用
  `model_provider=android_openai_http`、Responses wire API、`requires_openai_auth=true`，并关闭
  `supports_websockets`。provider 保留 CLI 识别的一方名称 `OpenAI` 且不覆写 `base_url`，因此登录态
  继续决定 ChatGPT Codex 或 OpenAI API endpoint；组织/项目环境头和 standalone web search 能力保留。
  该配置只应用于本地 Codex app-server 的 OpenAI 模式，用户选中的第三方 provider 仍走它自己的
  provider/API-key 配置。目标是绕开 Android PRoot 中 WebSocket 握手失败后未必回退 HTTP 的路径；
  不改 CLI 二进制或 auth.json，不声称已由真机请求证明网络故障消失。
- 新增启动参数单测，并在完整 session widget 测试中核对普通 OpenAI 线程确实带入 HTTP/SSE 配置，
  第三方线程不被 OpenAI 配置覆盖；完整 Flutter suite `313/313` 通过。
- Release 构建和 APK 验证通过：包名 `io.henry.codex`，5 项 ARM64 runtime assets 齐全，大小
  117,753,223 字节，SHA-256 `fdc5aef5ebc9c2d31adfa27b01481ee90aad4f1ac3135de5290bb42d54523381`；
  签名仍为本机 Android debug certificate。只读 `codex_api35` x86_64 API 35 AVD 安装启动通过，
  首页与中文无障碍树可读，App PID `3468`、无 `FATAL EXCEPTION`。AVD 无 Root/ARM64 app-server，未登录、
  未发起 OpenAI 请求；临时 AVD 已停止，5620/5621 已确认无 LISTEN 并释放。
- 当前没有连接的实体 ADB 设备；OpenAI OAuth 真实 turn、Root/PRoot 下 HTTP/SSE 网络路径以及
  网络故障是否消失，仍待手机连接后验收。

## 2026-09-27 VPN 本地 HTTP 代理配置与新会话注入

- 针对 Root/PRoot worker 无法保证继承 VPN 按 UID 路由、Android `LinkProperties` 未必公开
  VPN 应用私有代理端口的问题，Settings 底部新增可选 HTTP proxy endpoint。用户可填写
  `host:port` 或 `[IPv6]:port`（支持 `http://` 前缀）；空值清除手动代理并恢复 Android
  系统代理自动探测。手动值优先于系统代理，并由现有 `httpProxyEnvironment` 统一注入
  App UID Host 与 Root/PRoot 新进程，运行中的 session 不被重启或改写。
- 该设置只接受 HTTP/Mixed 代理，不接受 SOCKS-only 端口或代理凭据；输入内容存入 App 私有
  preferences，不写入进程日志。若 VPN 应用只提供 SOCKS，需要其 HTTP/Mixed 端口或后续增加
  对应协议支持。
- 验证：Kotlin `CompatibilityNetworkConfigurationTest` 覆盖 host/port、IPv6、scheme 规范化和
  非法地址；Flutter 代理设置 widget 测试验证读取、保存和恢复自动探测；设置模型测试 `10/10`
  和会话交互/网络错误测试 `23/23` 通过。Android 定向 Gradle 单测成功。定向 Dart analyze
  对旧设置文件报告 2 项既有 warning（未使用的 import/声明），新增代理 service/test 无新增问题。
- Release APK 构建并经 `verify-android-apk.ps1 -RequireCodexNativeAssets` 校验通过：包名
  `io.henry.codex`、签名有效、5 项 ARM64 PRoot/native assets 齐全，大小 `117,766,707` 字节，
  SHA-256 `c72abccb30e54abda677da08c91d30ce406fa6881230a573dd42182a3c3b9387`；仍为本机 Android
  debug certificate。`codex_api35` Android 15 x86_64 AVD 安装/启动通过，Settings 能输入并保存
  `127.0.0.1:7890`，离开再打开后仍读回该值；无 `FATAL EXCEPTION`。临时 AVD 已停止，5630/5631
  已确认无 LISTEN 并释放。
- AVD 没有 KernelSU/ARM64 rootfs，本轮没有发起外网请求。手动代理环境变量注入已由代码路径和
  单测覆盖，但 Root/PRoot 的 VPN 代理连通性、OpenAI OAuth HTTP/SSE 真实 turn 仍需手机连接后
  验证；不得把 Settings 持久化或 APK 构建称为网络故障已解决。

## 2026-09-27 系统代理发现回退与 Release 重建

- 修复第三方模型设置页的 Dart 语法回归：已保存 provider 的推理档位文本现在正确拼接；定向
  provider、网络探测、网络错误本地化和第三方设置测试共 `21/21` 通过。
- 修正 Android 网络注入遗漏：除 `ConnectivityManager` 的 `LinkProperties.httpProxy` 外，现会
  回退读取 JVM/Android `ProxySelector` 暴露的系统 HTTP 代理。仅接收 HTTP、已解析、无凭据的
  host/port；手动设置仍优先，SOCKS 和 DIRECT 不会被误注入。这样部分 Clash/VPN/全局代理在
  `LinkProperties` 不可见时，Root/PRoot worker 仍能得到与 App 相同的 HTTP(S) 代理环境。
- Android `CompatibilityNetworkConfigurationTest` 通过，`BUILD SUCCESSFUL`；Release APK 已重建
  并通过 `verify-android-apk.ps1 -RequireCodexNativeAssets`：包名 `io.henry.codex`，大小
  `117,809,347` 字节，SHA-256
  `4c01c372c13d2e298b98fb50f7a0eaaabf1513a19c1197cb07c46591f0526a59`，五项 ARM64 runtime
  assets 齐全，签名有效但仍是本机 Android debug certificate。
- 当前 ADB 仍无实体设备，本轮没有安装或发送真实 provider 请求；ProxySelector 回退和网络故障
  是否消失仍需手机上先执行 `/network-test`，再执行一个真实 turn 验收。

- 补跑独立 App 完整 Flutter suite：`321/321` 通过。测试期间 Google Fonts 的外网字体下载失败
  仅为测试环境日志，不影响断言或退出码。

## 2026-09-27 会话内 Root/PRoot 网络连通性探测

- 会话新增 `/network-test`，在与当前会话相同的 App UID 或 Root/PRoot 执行身份下启动 Python
  一次性探测，并继承新进程会使用的 DNS、CA 与 HTTP proxy 环境。OpenAI 模式检查 API 与认证
  域名；第三方模式只检查当前 provider 的 origin。
- 探测只发送不带凭据的 HTTPS/HTTP GET，不传 API key、OAuth token、prompt，也不调用模型；HTTP
  401/403 作为“网络/TLS 已到服务端，但该端点要求认证”显示，DNS、超时、TLS 与连接拒绝分别呈现，
  并展示实际注入代理的 scheme/host/port（不展示 URL user-info），不保存底层异常原文。命令加入
  会话 `/help`，不另开 app-server、不重启当前 session。
- 验证：新增网络探测参数/响应解析单测 5 项通过；包含真实 slash command 路径的会话测试与该组
  测试共 28 项通过。定向 Dart analyzer 没有本次新增代码问题；其余 20 条是 `main.dart` 的既有
  warning/info。Google Fonts 在测试时无法联网加载仍只是测试环境日志。
- 当前 ADB 无实体设备，x86_64 AVD 不具备 ARM64 Root/PRoot runtime；因此新命令尚未在手机执行，
  原网络故障仍未宣称已修复。下一步在真机运行 `/network-test` 与一个真实 Codex turn，按同一进程
  的探测结果继续定位并修复网络路径。
- 新 Release APK 已构建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：
  `io.henry.codex`、117,796,315 bytes、SHA-256
  `0fe5ea5aaf3527bf79dd5d2ab83042594c6463c3791af522bd26e0735526a3f4`，5/5 ARM64 native assets
  齐全、签名有效但仍为本机 debug certificate。构建后 `adb devices -l` 仍为空；APK 尚未安装。

## 2026-09-27 网络探测补充 Codex app-server RPC

- `/network-test` 在 Python DNS/TLS 探测之外，现在还读取当前 OpenAI 会话的
  `account/rateLimits/read`。已有会话复用活跃 app-server；尚未启动 thread 的新会话使用同一
  Root/App 执行身份、runtime 和环境运行一次性本地 app-server quota RPC。该检查不创建 thread、
  不发送 prompt 或模型请求；第三方 provider 分支不调用 OpenAI 认证/额度接口，也不发送其 API key。
- 结果分别呈现 Python endpoint 与 Codex RPC 状态，避免多个结论被 CC Pocket 单行 system chip
  截断；OpenAI 认证失败、RPC 超时和传输问题会与“guest Python 可达”分开显示。之前版本提示
  “不使用登录凭据”的说法仅适用于 Python GET；当前 UI 已明确说明 OpenAI quota RPC 使用本地
  app-server 登录态。
- 定向 Flutter 网络探测和 session slash-command 回归 `29/29` 通过，覆盖已有 session 复用活跃
  app-server，以及新 session 在创建 thread 前通过一次性 quota RPC 检查 Codex transport；不会为
  网络检查创建 thread；同一会话还覆盖了 TLS 握手错误 fixture 并验证诊断分支。定向 analyze 未发现本次
  代码新增诊断，报告的既有 warning/info 位于其它代码行。Release APK 待本条代码合入后重建。
- 真机 ADB 仍无设备；认证 quota RPC 与真实 Codex turn 的设备网络路径仍未验证。此增强提供
  下一次连接手机后定位的诊断入口，不代表此前“网络连接失败”已解决。
- 后续 Release 已构建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：
  `io.henry.codex` 1.0.0，117,802,943 bytes，SHA-256
  `794b91aff0923ae0663b2c0499c40458a3ca417fc90461ee53069fb299434234`；5/5 ARM64 assets 完整、
  APK 签名有效但为本机 debug certificate。构建后 ADB 仍无设备，未安装；真机网络验收未做。

## 2026-09-27 Root 普通系统文件软路由范围修正

- 将 Root 软路由从“整个 `/system`、`/vendor` 等分区及其配置目录”收窄到启动关键路径：init/SELinux
  配置、fstab、早期启动 kernel modules、boot 镜像/块设备与明确的分区刷写命令。普通字体、hosts、
  build.prop、vendor/app 配置及 Root 可写的其他 Android 路径继续由 Root 直接执行，不再因目录前缀
  被强制送入 KernelSU 插件路径。
- 同时移除仅凭 `mount`、`reboot`、`setprop`、`dd`、`insmod`、`mkfs`、`rmmod` 命令名就软路由的
  规则；仍按目标路径识别真实 boot/raw-block 风险。更新 Root 模式说明、Android agent 指引与打包的
  runtime `AGENTS.md`，明确常规 Root 编辑与启动关键操作的区别。
- 定向 Flutter 测试 `root_access_policy_test.dart` + `local_session_conversation_test.dart` 共
  35 项全部通过，覆盖普通 `/system/fonts` 编辑直接自动批准、普通系统配置和常用命令直达，以及
  init/fstab/boot/raw-block/flash 路由。`git diff --check` 无空白错误；定向 analyzer 未发现本次
  修改引入的问题，`main.dart` 其余诊断为既有 warning/info。
- 已重新构建 Release（`tools/build-android.ps1 -Mode release`）并通过
  `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：包名 `io.henry.codex`，
  117,803,919 bytes，SHA-256 `ddb02707cfc353dcaa9e968fcec5df98b832de4abe3c0d8a56c091953edb9c4c`；
  签名有效，5/5 ARM64 runtime assets 齐全。该包使用本机 Android debug certificate，不是商店签名。
- 构建后再次检查 `adb devices -l` 仍无设备，因此没有安装或 KernelSU 实测。此修正尚未验证设备上
  的 Root 进程和实际文件操作；设备连接后可安装此 APK，并分别验证普通字体/配置编辑和启动关键路径
  的软路由行为。

## 2026-09-27 DeepSeek Responses provider 地址与设置表单

- 对照 DeepSeek 当前官方 Codex 接入说明，provider `base_url` 应使用 `https://api.deepseek.com/`
  并由 Codex 请求 `/responses`。应用以前把常见 OpenAI Chat Completions 写法
  `https://api.deepseek.com/v1` 原样传给 CLI，可能导致拼出错误的 `/v1/responses` 路径。
- `CustomProviderConfig.responsesBaseUri` 现在只对官方 `api.deepseek.com` 主机把精确 `/v1` 路径
  规范到 API 根地址；其他 provider 的自定义路径不变，已有 DeepSeek `/responses` 和
  `/chat/completions` 完整 URL 也会正确归一化。第三方模型编辑表单补充 DeepSeek 正确地址/模型示例、
  Responses API 要求，并修复表单控件中英文随系统语言切换不完整的问题。
- 定向 Flutter 回归 `custom_provider_config_test.dart` + `codex_provider_launch_configuration_test.dart`
  共 `14/14` 通过；定向 Dart analyzer 退出码 0，仅报告表单原有两个 Flutter `RadioListTile`
  弃用提示。`builder/test-offline.sh` 全检查通过，覆盖工具链 lock、rootfs 包/命令契约、归档校验、
  安装路径和无网络帮助行为。
- Release APK 已重建并通过 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：
  `io.henry.codex` 1.0.0，117,807,859 bytes，SHA-256
  `fdf6f8ea94c28a4ed361651b03904879379b81718bb32d1a87bea9ec98984698`，5/5 ARM64 native assets
  齐全，签名有效但仍为本机 debug certificate。构建时 Gradle/AGP/Kotlin 仅有版本升级提示。
- ADB 再次无实体设备，未安装本 APK，也未发送 DeepSeek API 请求；provider 的真实 Codex app-server
  turn 及实际收费响应仍待设备安装后验证。官方协议/端点依据：
  https://api-docs.deepseek.com/quick_start/agent_integrations/codex/ 。

## 2026-09-27 旧 rootfs 的 Python 命令兼容回退

- 兼容执行器以前只按字面查找 `python`。较早构建的 Debian ARM64 rootfs 可能只有
  `python3`（尚未安装 `python-is-python3`），因此 `/network-test` 和用户直接输入
  `python` 会在进入网络探测前失败，并被上层误显示为网络不可用。
- `CompatibilityProcessManager` 现在仅在 guest PATH 查找阶段把 `python` 顺序解析为
  `python`、`python3`；其它命令和 Android host 工具路径不变，不引入 host-side shell
  或新的权限路径。新 rootfs 仍优先使用已有的 `python` alias。
- 新增 Kotlin 回归覆盖：原生 guest 只有 `/usr/bin/python3` 时，`python` 会落到该文件，
  `node` 等其它命令不产生别名。`:app:testDebugUnitTest --tests
  io.henry.codex.CompatibilityCommandArgvTest` 通过；未重建 Release，也未安装 APK。
- 当前 ADB 仍无在线设备，因此实际手机上的 DNS、代理、Python 网络探测与 Root worker
  仍需下一次真机连接后验证；本修复本身只消除一个可复现的旧 rootfs 命令兼容错误。

## 2026-09-27 第三方模型设置本地化与网络问题虚拟机复查

- 英文版第三方模型设置页发现空状态仍硬编码中文；现已补齐空状态、删除确认、已保存 provider 的
  reasoning 标签及编辑/删除菜单中英文，并增加两种语言下的空状态与添加表单回归断言。
- 定向 `custom_provider_settings_test.dart` 通过（2/2）。重建 Release 并通过 APK verifier：
  117,808,747 bytes，SHA-256 `8051286b585e6850883a3ae8fc8bc9ab83055a7ffcdd0d36e3a74ce912e50432`；
  `io.henry.codex`、5/5 ARM64 runtime assets 齐全，签名有效但为本机 debug certificate。
- 将该包安装到 `codex_api35` x86_64 AVD，覆盖安装保留本地设置；App 能启动并进入设置/第三方模型表单，
  英文空状态、DeepSeek Responses endpoint helper 和表单按钮实测为英文。启动后 logcat 未见
  `FATAL EXCEPTION`。AVD 不具备 ARM64 Codex/PRoot/KernelSU runtime，因此没有进行真实 Codex turn。
- 同时检查 AVD 默认网络：Android Connectivity 报告 active default network 为 validated；ICMP ping
  没有响应，不能据此判定 HTTPS 不通。由于虚拟机没有可运行的本地 Codex runtime，仍未复现用户报告的
  “网络连接失败”会话错误；真机 ADB 当前未连接，不能宣称该问题已解决。下一次应在有 runtime 的真机
  会话中运行 `/network-test` 并保留其脱敏诊断，再据此修复实际失败层。

## 2026-09-27 Android-native 网络探测改走 guest Python

- 发现 `/network-test` 在 Android-native 会话中仍把 Python 探测发送给当前 native backend；
  Android app 进程并不保证自带 `python`，因此可能在真正检查 DNS/TLS 前就失败，并被显示成泛化的
  “网络连接失败”。
- `LocalSessionPage` 现在只在当前 backend 已经是 Fake/PRoot 时沿用它执行 Python；native backend
  会优先探测已验证的 Linux Compatibility backend，并在 guest 中以独立 operation scope 运行 Python，
  不切换会话的 active backend。没有可用 guest 时，OpenAI 模式明确跳过 Python 辅助探测但仍以真实
  Codex RPC 结果判定；第三方 provider 则显示缺失 guest Python 能力，而不是伪造成功。
- `_runOneShotCommand` 支持为一次性命令指定 backend，workspace 映射仍经过原有 backend 边界；
  现有 Fake/PRoot 网络测试契约保持不变。
- 定向 Flutter 回归 `local_session_conversation_test.dart`、`codex_network_probe_test.dart`、
  `codex_model_catalog_test.dart` 通过，共 `33/33`；`dart format` 无改动，定向 Dart analyzer
  仅报告 main.dart 原有 warning/info。
- 全量 Flutter 回归 `flutter test --no-pub` 通过，共 `321/321`。Release APK 已重建并通过
  `tools/verify-android-apk.ps1 -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，
  `117,813,751` bytes，SHA-256
  `0e194382f7f0d71a80c7ee22ad690079f453b5f02cd6ac951f42cff50270142c`，5/5 ARM64 runtime
  assets 齐全，签名有效但仍为本机 debug certificate；未安装 APK。
- ADB 当前仍无在线设备，因此 native→guest 的实际手机执行路径、Root worker 和真实第三方 provider
  网络仍待真机复测。

## 2026-09-27 Root profile 探测去重

- 发现兼容层和 Android-native Host backend 在每次启动 Root 进程时都会重新运行完整的
  `AndroidRootProfileProbe`。这不会改变 KernelSU 配置，但会额外启动一次 `su`，容易被误认为
  每条命令都要重新请求 Root。
- 两个 process manager 现在在当前 manager 生命周期内缓存首次成功、真实 UID 0 的 helper 路径；
  后续 Codex session/CLI 命令仍通过用户配置的正常 KernelSU helper 启动，但不重复做整套 profile
  预检。失败探测不缓存，仍保持原有失败行为；未引入自定义 SELinux 域、固定 group/capability
  门禁或权限 broker。
- Kotlin 定向单测与编译通过：`:app:testDebugUnitTest --tests
  io.henry.codex.CompatibilityRootLaunchScriptTest --tests
  io.henry.codex.RootProfileProbeTest`，`BUILD SUCCESSFUL`（98 actionable tasks，10 executed）。
- 包含该修复的 Release APK 已重建并通过 `tools/verify-android-apk.ps1
  -RequireCodexNativeAssets`：`io.henry.codex` 1.0.0，`117,813,731` bytes，SHA-256
  `05e12c33c35addc9b3d41f72a7d31e75f23a80648d99a479c7238f4f551fce77`，5/5 ARM64 runtime
  assets 齐全，仍为本机 debug certificate；未安装 APK。
- 这仍需真机确认 KernelSU Manager 是否因实际 worker 启动而弹出审批；当前 ADB 无在线设备，不能
  把本地编译证据写成真机 Root 验收。

## 2026-09-27 移除 Host execution 的逐命令 Root 审批

- 发现运行时工具页 `HostExecutionPage` 仍保留旧的 “Approve root command?”
  对话框。它与当前 Root-first 路线冲突：用户已经主动点击了明确的 Run/Probe 操作，
  不应再被同一面板的逐命令 Root 弹窗阻断。
- Root 模式现在直接执行显式 argv；会话级 Root 授权仍由 Codex 会话入口处理，
  Codex app-server 的真实 user-input、文件变更和工具交互仍保持原有协议路径。
  非 Root 模式本来就不需要该弹窗。
- 定向 Flutter 回归：`host_execution_page_test.dart`、`local_session_auth_test.dart`
  共 `8/8` 通过。该改动未改变 KernelSU profile，也未引入新的 broker 或权限门禁。
- 当前 ADB 仍无在线设备；Root worker、真实 Android host 命令和 KernelSU 弹窗行为仍需
  真机连接后验证，不能将本地 Fake backend 测试写成设备验收。

## 2026-09-27 真机 Root/PRoot 与第三方 provider turn 验证

- 补齐 Android-native 传输失败到 Linux Compatibility 回退的识别：新增 WebSocket 断开、连接
  reset/refused/timeout 等 transport markers；HTTP 401/403 和 provider 业务错误不被误判为
  runtime 故障。定向 Flutter provider/network 与 Host execution 回归 `6/6` 通过。
- 使用 Release APK 覆盖安装到真机 `24031PN0DC`（Android 16），不清理应用数据；APK 包名为
  `io.henry.codex`，SHA-256 `476516716fca8a19ba4366581f06f4a73f78cf62ba6d21789f108c6b242c2663`，
  5/5 ARM64 runtime assets 齐全。
- 在已有第三方 provider 配置下创建 Root session：Root 会话授权只出现一次；随后
  `libcodex_worker_guard.so`、`libcodex_proot.so` 和 guest `codex` 均在设备进程表中显示为
  UID 0，应用侧 worker 通过 KernelSU `u:r:ksu:s0` 启动，没有第二次逐命令 Root 审批。
- 真实 turn 已完成流式工具执行并返回最终 assistant 回复。回复中的脱敏身份结果确认：真实
  Android UID 0、`/android` 主机根目录 bind 存在、`CapEff` 为完整集合、`NoNewPrivs: 0`；
  这不是单纯 PRoot 内部伪装的 root 标签。
- 随后在同一 session 执行 `/network-test`，结果为 `api.deepseek.com: HTTP 401`，并明确标注
  DNS、连接与 TLS 可达、服务端要求认证。由此确认第三方服务的网络链路正常，401 是探测请求未
  注入 API key 的预期认证响应，不是“网络连接失败”。UI 最终回到“就绪”，未见崩溃日志。
- 当前已验证 Root worker、PRoot 主机视图、第三方 provider turn 和网络探测；多 session 并行、
  Git/Node/npm/npx/Python 工具完整性及其它未覆盖 CLI 功能仍需继续单独验收。

## 2026-09-27 真机 Debian ARM64 工具链验收

- 在同一 Root/PRoot session 中让真实 Codex 检查 guest 工具链，确认 Git `2.39.5`（`/usr/bin/git`）、
  Node `v24.19.0`（`/usr/local/bin/node -> /opt/node/bin/node`）和 npm `11.17.0`
  （`/usr/local/bin/npm -> /opt/node/bin/npm`）可执行。
- 第二个真实 turn 确认 npx `11.17.0`（`/usr/local/bin/npx -> /opt/node/bin/npx`）和 Python
  `3.11.2`（`/usr/bin/python -> /usr/bin/python3.11`）可执行；全部解析到 Debian ARM64 guest，
  没有落回 Android/Bionic host。当前工具链缺失问题在这台真机上未复现。
- 两个 turn 均在 UI 中完成并回到“就绪”，Root/PRoot worker 未被切换会话或返回首页行为终止。
- 本轮回归通过：Flutter 定向 session/network/Host 测试 `30/30`；Kotlin
  `CompatibilityRootLaunchScriptTest`、`RootProfileProbeTest`、`CompatibilityCommandArgvTest`
  均通过；`git diff --check` 无空白错误。测试日志中的 Google Fonts 下载失败仍是既有离线测试噪声，
  不影响测试退出码。

## 2026-09-27 真机多 session 并行与恢复噪声修复

- 在同一设备、同一工作区的两个不同 session 中同时启动 Root/PRoot/Codex：进程表同时出现两套
  独立的 `libcodex_worker_guard.so`、`libcodex_proot.so`、guest `codex`，第一条 session 的
  `sleep 30` turn 未因返回列表或打开另一条 session 而被杀掉。
- 打开另一条已有 session 会自动恢复其历史并启动自己的 app-server；发送第二条真实 turn 后，
  两条 session 都回到就绪，未复现“全局只能一个活跃进程”的旧现象。该证据覆盖设备真实 Root
  worker，不只是 Flutter fake backend。
- 发现恢复旧 thread 时 Codex app-server 会把旧 `thread/read` 流被新连接接管的非致命信息写成
  `read interrupted by close() on another thread`。新增精确的 benign runtime diagnostic 过滤与
  session history 回归；不改变 client 生命周期、进程保活或重连逻辑。
- `session_history_test.dart` + `local_session_conversation_test.dart` 共 `42/42` 通过；Release
  APK 重建并安装到真机，SHA-256 `7c375bfcdf708ef2b7fe674b7fd65709551b50c97113ddf2d3941da2fdf5ee5a`，
  APK verifier 通过且 5/5 ARM64 native assets 齐全。覆盖安装后工作区/session 数据保留，重新打开
  历史 session 后 UI 显示就绪且不再显示该噪声。

## 2026-09-27 真机 CLI 更新与动态模型目录

- 在 Release 设置页实际执行“更新 Codex 命令行工具”：从 guest rootfs 自带的 `codex-cli 0.154.0`
  查询 npm 官方源并暂存更新，校验后切换到 `0.157.1`；设置页返回“Codex CLI 已是最新版本
  0.157.1”，旧版本 overlay 保留，未终止已有 session。
- 通过更新后的 app-private Linux/PRoot CLI 真实执行 `/version`，UI 返回
  `codex --version codex-cli 0.157.1`，证明更新不只是修改设置文本。
- 真实 Codex turn 检查了 `codex debug models` 的动态目录，返回最新 5.6 系列、Daybreak、Astra、
  `codex-auto-review` 及退休模型迁移信息；模型能力来自实际 CLI，不再由 Android UI 固定一份旧
  模型列表。当前 session 使用第三方 DeepSeek provider，因此该 provider 的选择器只展示配置的
  DeepSeek 模型，这是 OpenAI/第三方互斥路径下的预期行为。
- 更新后新 session 仍可创建并启动；更新前已存在的 session 保持原进程和上下文，不被 updater 强制
  重启。后续的 OpenAI provider 动态目录实体机验收、更新失败/回滚路径和 active CLI 版本展示
  持久化回归已在本文件后续条目完成。

## 2026-09-27 Release 设置持久化真机验收

- 将 app-private Compatibility CLI 的活动版本纳入 Android `SharedPreferences`，与主题和语言一起
  由 Flutter shell 读写；空值不写入旧版本兼容字段，不改变已有设置通道格式。
- Flutter 定向设置测试 `14/14` 通过；Android `:app:testDebugUnitTest --tests
  io.henry.codex.*` 通过，`BUILD SUCCESSFUL`。Release APK 已重新构建并通过 verifier：
  `io.henry.codex` 1.0.0，`117,814,951` bytes，SHA-256
  `14dabaac0698d745cf119141a23f148fe612b28b198fb1f0ecfcd0258506c69a`，5/5 ARM64 runtime
  assets 齐全。
- APK 已用 `adb install -r` 覆盖安装到真机 `24031PN0DC`，保留应用数据；安装后无
  `FATAL EXCEPTION`/`AndroidRuntime` 崩溃记录。
- 在设置页执行“检查并更新”后，UI 显示 `活动 CLI 0.157.1`，并提示 `Codex CLI 已是最新版本
  0.157.1`。随后强制停止并重新启动 App，再次进入设置页仍显示 `活动 CLI 0.157.1`，证明
  版本展示不是仅保留在当前 Flutter 页面状态，而是完成了持久化闭环。

## 2026-09-27 真机 CLI 回退/恢复与 bundled sandbox PATH 修复

- 在真机设置页实际确认回退：活动 CLI 从 `0.157.1` 切换到保留的 `0.156.1`，UI 提示仅影响
  后续新会话；随后再次执行更新并恢复到 `0.157.1`，没有清理应用数据。
- 用新建 Root session 执行 `/version`，UI 返回 `codex --version codex-cli 0.157.1`，证明
  恢复更新后的实际 guest CLI 已被后续会话使用，而不是只更新版本标签。
- 真机会话暴露了 Codex bundled `codex-resources/bwrap` 不在 PATH 的运行时噪声。Compatibility
  worker 现在同时把 active CLI 的 `codex-path`、`codex-resources` 和 rootfs 自带 ARM64
  `codex-path`、`codex-resources` 放入 guest PATH；旧 session 中保留的历史 bubblewrap 诊断不
  作为新启动结果。新建 Root session 的 `/version` 验收未再产生缺失 bwrap/namespace 诊断。
- 新增 `CompatibilityCommandArgvTest` 对 bundled resource/path 目录顺序的回归；定向 Kotlin
  测试 `CompatibilityCommandArgvTest`、`CompatibilityRootLaunchScriptTest`、
  `RootProfileProbeTest` 通过，Release APK 已重新安装到真机，SHA-256
  `a7ec61c227d87e4946669683aa44f84c6d897974a0a8d81243f07e80dc012892`，5/5 ARM64 runtime
  assets 齐全。

## 2026-09-27 第三方 provider 与 OpenAI 模式切换真机验收

- 第三方模型设置页新增明确的“OpenAI 登录”选项。选择它只清除 active provider，不删除已保存
  的第三方配置；因此 OpenAI auth 与第三方 provider 的请求路径保持互斥，同时允许用户保留并
  随时重新启用已有 provider。
- Flutter 定向页面测试 `3/3` 通过，覆盖中文/英文说明、provider 能力保存，以及选择 OpenAI
  后向 Android `SharedPreferences` 写入空 active provider 并回调上层状态。
- Release APK 通过 ASCII staging 构建和只读 verifier：包名 `io.henry.codex` 1.0.0，
  `117,816,815` bytes，SHA-256
  `706123a16d533bbd4bc74b4f7889e8fb83be2e6bfff4071d3c8bfe593c6c289b`，5/5 ARM64 runtime
  assets 齐全；已用 `adb install -r` 覆盖安装到真机，未清理应用数据。
- 真机 UI 首次显示第三方配置为选中状态；点击“OpenAI 登录”后 OpenAI radio 变为选中、
  第三方配置仍保留但取消选中；强制停止并重新打开 App 后再次进入该页面，状态仍保持为
  OpenAI 模式且第三方配置仍存在。此次验证没有发起新的模型请求，也没有读取或输出 API key。
- 在 OpenAI 模式下打开设置中的模型选择器，等待 CLI 目录读取完成后，真机 UI 显示了
  `gpt-6-astra`、`gpt-6-sol`、`gpt-6-luna`、`gpt-5.6-sol`、`gpt-5.6-terra`、
  `gpt-5.6-luna` 以及 Daybreak 条目；这确认当前选择器已走动态 CLI/app-server 目录，
  不再只依赖旧的静态模型列表。当前选择仍保持 `gpt-6-luna` + 低档位，没有被本轮验收改变。

## 2026-09-27 OpenAI 实际 turn 网络诊断与重试路径

- 真机新建 OpenAI session 后确认 UI 使用 `6 Luna`、低推理档位和 Root；会话启动期间同时存在
  旧 DeepSeek session 与新 OpenAI session 的两套独立 Root/PRoot/Codex 进程树，未复现并发
  session 被互相杀掉的问题。该 OpenAI turn 在当前设备网络下未完成，已按测试规则手动 Stop，
  没有把外部网络失败写成 runtime 崩溃。
- 同一 session 的 `/network-test` 返回：ChatGPT/OpenAI 访问路径中 `api.openai.com` 连接超时，
  `auth.openai.com` DNS、连接与 TLS 可达但未认证 GET 返回 HTTP 403；设备侧 root curl 对
  `chatgpt.com/backend-api/codex` 也复现连接超时。当前没有显式 HTTP 代理注入，DeepSeek
  之前的 HTTP 401 可达证据仍成立。因此当前阻断点是设备到 OpenAI/ChatGPT endpoint 的网络
  路由，不是 KernelSU Root、PRoot、session 并发或 OpenAI auth 文件未复制。
- 网络探测现在加入实际 OAuth 使用的 `https://chatgpt.com/backend-api/codex`，同时保留 API 和
  auth origin，以区分 ChatGPT OAuth、API key 和认证服务路径；app-server 的 `RPC request
  timed out` 也归类为 provider 网络故障并保留重试入口。Flutter 定向 network/provider 测试
  `8/8` 通过。真机要完成 OpenAI turn 仍需可达的 Android VPN/HTTP 代理或可直连网络；应用已有
  设置中的手动 HTTP proxy 入口，未在本轮替用户改动代理配置。
- 真机重新打开该历史 OpenAI session 后 Root/PRoot/app-server 可回到“就绪”，并观察到稳定的
  bubblewrap/user-namespace capability warning 不影响 session 启动。该诊断现在按精确文本加入
  benign runtime 过滤；新增 session-history 回归测试，避免把 Android/PRoot 的预期能力探测
  显示成会话错误。

## 2026-09-27 诊断过滤改动 Release 构建与真机替换

- `session_history` 与 network probe 定向 Flutter 测试通过，累计本轮输出 `27` 项通过；新增的
  PRoot bubblewrap/user-namespace 能力探测过滤不会吞掉普通运行错误，只匹配该稳定诊断文本。
- 使用仓库 Release 脚本重新构建并通过只读 APK verifier：包名 `io.henry.codex` 1.0.0，
  `117,816,863` bytes，SHA-256
  `ab8827440d4a713a2098f2954640c9c0bbc44bd44e4774fdd99f37370859b041`，5/5 ARM64 runtime
  assets 齐全。
- 已在真机 `24031PN0DC` 上用 `adb install -r` 覆盖安装，保留应用数据；安装后
  `io.henry.codex/.MainActivity` 正常位于前台，未启动残留 Codex worker。手机侧默认模型与推理
  档位未改动，仍保持 `gpt-6-luna` + low。
- 随后在现有工作区创建了一个新 Root session，首次授权后执行本地 `/version`；UI 返回
  `codex-cli 0.157.1`，同时显示 PRoot 后端选择。新 session 的事件中没有新增
  `bubblewrap/user namespaces` 诊断，验证过滤改动已进入运行包；测试结束后确认设备侧没有
  `codex_worker_guard`、`codex_proot` 或 Codex trampoline 残留进程。

## 2026-09-27 Root worker Android 主机命令 PATH 真机验收

- 在刚安装的 Release 真机版本中，以 DeepSeek provider 创建新的 Root/PRoot session，执行
  Android 主机命令 `/system/bin/getprop ro.build.version.release`，真实 Codex turn 流式
  完成并返回 Android 版本 `16`；会话 UI 同时显示真实 context usage、token usage 和 tool
  事件，结束后回到“就绪”。这证明 `/android` 主机视图与直接 Android 命令路径已经进入实际
  worker，而不是只存在于文档或 fake backend。
- 继续执行 `/system/bin/pm path ...` 时，Codex 侧确认 `/system/bin/pm` 是调用 `cmd package`
  的 Android shell wrapper；此前 worker PATH 缺少 `/system/bin` 会造成 wrapper 内的 `cmd`
  查找失败。当前安装包把 `/system/bin:/system/xbin:/vendor/bin` 追加到 Root worker PATH，
  并保持 Debian guest 工具目录优先；真机结果确认 PATH 修复已生效，`pm` 已能找到并调用
  `cmd`。一次后续 UI 输入把包名 `io.henry.codex` 误注入成 `i.henry.codex`，因此该次退出码
  1 是包名不存在，不是 PATH 或 Root 执行失败。
- 将 PATH 拼接提取为 `compatibilityGuestPath(identity, nativeToolchainAvailable)`，新增回归
  断言：只有 Root identity 暴露 Android host command 目录，且 `/usr/bin` 仍优先于
  `/system/bin`。`CompatibilityCommandArgvTest` 与 `CompatibilityRootLaunchScriptTest`
  定向 Gradle 单测通过（`BUILD SUCCESSFUL`）。随后使用 Release 脚本重新构建并通过 APK
  verifier：包名 `io.henry.codex` 1.0.0，`117,816,891` bytes，SHA-256
  `5f85f4d05b48a1ac7b93289cb1e51b807f4ccc644eb13bc0bc1c1c20511d6323`，5/5 ARM64 native
  assets 齐全。已用 `adb install -r` 覆盖安装到真机，应用数据保留，Activity 正常回到前台，
  安装后没有残留 worker/proot/Codex 进程。

## 2026-09-27 Android host `pm` wrapper 真实执行修复

- 上一轮 PATH 修复之后，Root worker 已能看到 Android host command 目录，但真机进一步
  验证发现显式执行 `/system/bin/pm` 仍会在 PRoot guest 中失败：Android 的 `pm` 是一个
  依赖同目录 `cmd` 的 shell wrapper，单纯把 `/system/bin` 放入 PATH 不能保证 wrapper
  内部按绝对路径/同目录规则找到 `cmd`。
- 当前实现把 app-server 的 shell environment policy 设置为继承完整 Android host 环境，
  同时在 Root guest 的 admin bin 中安装 `cmd`、`pm`、`settings`、`appops`、`wm` 以及
  `device_config`、`dpm`、`ime`、`input`、`locksettings` 等常见 Android shell wrapper
  的轻量 shim。它们分别执行等价的 `/system/bin/cmd` service 调用，不经过旧的
  root-read broker，也不改变 Root worker 的实际 UID 或 KernelSU 配置。
- `CompatibilityProcessManager` 仅对 Root PRoot 映射
  `guest-admin/bin/{pm,settings,appops,wm,device_config,dpm,ime,input,locksettings}` 到
  对应的 `/system/bin` 路径，因此用户在 Codex 中输入的真实 Android 命令仍保持原路径
  和原语义；非 Root session 不获得这些映射。shim 安装器、命令 argv 和 Root launch
  script 的定向 Kotlin 单测均已通过，Flutter provider launch configuration 定向测试
  为 `35/35`。
- 最新 Release 已重新构建并覆盖安装到真机：APK `117,812,823` bytes，SHA-256
  `832cb2d7bcdc41b936c4f28e6b9f9888077d29c38c9f07ede1dfbf7dafeb6565`，包名
  `io.henry.codex`，4/4 独立 Codex ARM64 runtime assets 齐全，APK 内没有旧的固定范围
  `root-read-broker` native asset。
- 真机以 DeepSeek provider 创建新的 Root/PRoot session，发送精确命令
  `/system/bin/pm path io.henry.codex`，真实 Codex turn 流式完成并返回
  `package:/data/app/.../base.apk`，随后回到“就绪”。之后只通过 UI 手动停止 session，
  worker、PRoot 和 Codex 子进程均已清理；这证明修复不会把生命周期控制重新绑定到页面
  切换或旧的全局 broker。
- 随后在同一正式 APK 上执行 `/system/bin/settings get system screen_brightness`，真实
  Root turn 返回当前亮度值 `194`、`exit=0`，并显示 `tools 1`、上下文用量和最终回复。
  输出中的 linker configuration warning 仅是 PRoot guest 路径诊断，不影响命令结果；该次
  session 最后也通过 UI 手动停止，设备侧仅保留主 App 进程，没有残留 worker、PRoot、Node
  或 app-server 子进程。
- 为覆盖同类窗口服务 wrapper，随后又加入 `wm -> cmd window` 映射，并重新构建正式 APK：
  `117,813,219` bytes，SHA-256
  `9cdab0d6afb229b96f56fdb07f0843d3c1e705cd07dbcccdd69e62a6e3d2c31f`；APK verifier 仍
  报告 4/4 独立 ARM64 assets 完整。真机 Root turn 执行 `/system/bin/wm size` 返回
  `Physical display size: 1440x3200`、`exit=0`；同样只出现不影响结果的 linker warning，
  UI 回到“就绪”后已手动停止 session，设备侧没有残留 worker 子进程。
- 根据设备 `/system/bin` 的真实脚本内容，又补齐了 `device_config`、`dpm`、`ime`、
  `input` 和 `locksettings` 这五个纯 `cmd` wrapper；带特殊分支的 `am`、`svc` 未被错误
  简化，仍由 guest PATH 中的 `cmd` shim 提供依赖。安装器测试覆盖这些固定脚本内容，避免
  以后把任意脚本误当成可直接映射的 service wrapper。重新构建的正式 APK 为
  `117,814,487` bytes，SHA-256
  `23c186637980cde75ab23ac89de26bf449fd65073182edccc19800eba3781558`，已通过 verifier
  并用 `adb install -r` 覆盖安装到 `24031PN0DC`；安装后 Activity 正常位于前台，设备侧仅有
  `io.henry.codex` 主进程，没有残留 worker/PRoot/Codex 子进程。

## 2026-09-27 独立 App 不再打包旧 root-read broker

- 独立 Android Codex APK 的 native contract 已收敛为 PRoot、loader、host trampoline 和
  worker guard 四项资产。APK verifier、jniLibs 说明和独立 App roadmap 已同步；历史目录
  中残留的旧 broker 文件即使存在，也通过 Gradle packaging exclude 明确排除，不会进入
  APK，不再成为运行时架构的一部分。
- 当前 Root 能力来自用户已配置的 KernelSU Root + PRoot worker，普通 Android host
  command 通过 guest PATH/必要 shim 衔接；没有恢复固定路径、固定范围、逐条审批的
  root-read broker。

## 2026-09-28 DeepSeek provider 旧 session 路由竞态修复

- 修复 `CodexHomePage` 启动期间异步加载自定义 provider 时，用户立即打开旧 session
  可能拿到空 provider 的竞态。旧 session 现在会等待 provider 配置加载完成再恢复；对于
  历史记录中没有 `customProviderId` 的旧数据，如果其模型名与当前唯一配置 provider
  精确匹配，也会恢复到该 provider；只有无法唯一匹配时才保持原有 OpenAI 路径，避免误
  把 OpenAI session 改投第三方服务。
- Flutter 定向回归通过：`52 tests passed`，覆盖 provider turn、provider 缺失、
  network-test、旧 session 自动恢复、session 切换和 CC Pocket session UI。
- 以正式 Release APK 覆盖安装到真机 `24031PN0DC`，应用数据和历史 session 保留。该版
  APK 为 `117,811,411` bytes，SHA-256 为
  `f8ab5255600abd31ccd66d40493c7de820c6a10e9e64f95711c58294eada7b9e`；verifier 确认
  4/4 独立 Codex ARM64 runtime assets 存在，包内没有旧 root-read broker asset。
- 真机打开已有的 `Run /system/bin/wm size` session 后，顶部恢复为 `Deepseek Flash`、
  `低`、`计划开启`、`Root`，说明该历史 session 已使用自定义 provider 路径，而不是
  之前错误回退到 OpenAI。
- 在同一个恢复后的 session 中重新执行 `/network-test`，得到：
  `api.deepseek.com：HTTP 401（DNS、连接与 TLS 可达；经代理 127.0.0.1:7890；服务端要求认证）`。
  该结果证明 app-server/PRoot 到第三方服务的网络路径正常，401 是探测请求未携带业务
  API 认证的预期结果，不是网络超时。
- 随后发送短真实 turn `Reply OK`，真机收到流式 thinking、最终文本 `OK`，顶部显示
  context usage `3%`、输入/输出 token 计数并回到“就绪”。这同时验证了旧 session provider
  恢复、第三方模型请求、流式事件、用量更新和最终回复链路。
- 旧历史中的 `Codex command timed out after 35 seconds` 与模型 metadata warning 保留
  为历史消息，未被清理；本次新 network-test 和真实 turn 均未产生新的 35 秒 OpenAI
  超时。后续若要处理 metadata warning，应单独补齐自定义模型 metadata，不与本次路由
  竞态修复混为一项。

## 2026-09-28 Root/PRoot 应用内基础工具链真机验收

- 在上述同一个真实 Root/PRoot/Codex session 中，要求 Codex 使用 shell tool 依次执行
  `git version`、`node --version`、`npm --version`、`npx --version` 和
  `python --version`，所有命令都实际产生了 command execution 事件并以 `exit code: 0`
  完成。这是应用内 worker 的数据面验收，不是仅对 APK 或 rootfs 文件存在性的检查。
- 真机返回的版本为：Git `2.39.5`、Node `v24.19.0`、npm `11.17.0`、npx `11.17.0`、
  Python `3.11.2`。因此此前“CLI 命令输入后没有反应/工具缺失”的主路径在当前
  KernelSU Root + PRoot session 中已恢复。
- 该轮未安装额外 npm 包，也未修改 workspace；依赖安装、包缓存隔离和 apt/dpkg 的
  更广泛写入行为仍需单独验收，不能由版本命令结果代替。

## 2026-09-28 Root/PRoot 临时 npm 依赖安装 smoke

- 继续在同一 Root/PRoot worker 中执行 `npm exec`，请求临时缓存中的
  `is-number@7.0.0`，并让 Node 加载它验证 `is-number(42)`。实际返回
  `is-number(42) = true`、`typeof result: boolean`、`exit code: 0`。
- Codex 同时确认该操作没有修改 workspace；测试没有向项目目录写入 `package.json` 或
  `node_modules`。这证明当前 guest 不仅能找到 npm/npx，还能在网络可用时完成一次真实
  的第三方依赖解析、缓存和执行。
- 仍未把 apt/dpkg、系统级包安装或长期依赖写入宣称为完成；它们需要独立的目录、权限和
  回滚验收，不能由这次临时 npm smoke 代替。

## 2026-09-28 guest apt 依赖断裂下的 prefix 安装真机验收

- 在真实 Root/PRoot session 中请求安装 Debian `tree` 时，Codex 发现当前 guest rootfs
  的 apt/dpkg 数据存在 `usr-merged` 依赖断裂。它没有直接执行会改写 guest `/bin`、
  `/sbin`、`/lib` 布局的修复，而是展示了三种方案并等待选择；选择推荐的 prefix extraction
  后又因 session 处于计划模式而拒绝写入，直到用户可见地关闭本 session 的计划模式。
  这证明计划/执行状态确实影响真实写操作，而不是 UI 假开关。
- 关闭计划模式后，Codex 实际下载并提取 `tree 2.1.0` 到
  `/home/codex/.local/codex-pkgs`，随后执行该绝对路径的 `tree --version`；返回完整版本
  文本和 `exit code: 0`。
- Codex 同时验证 `dpkg-query -W tree` 仍报告未安装，且没有引用或修改 `/workspace` 文件。
  因此当前普通 guest 依赖可以通过不改写 finalized rootfs 的 prefix 层安装并立即使用；
  标准 dpkg 数据库安装仍受 rootfs 的 usr-merge 状态影响，不能误报为已修复。后续应继续
  完善 prefix 安装的依赖解析、持久化和 UI 状态，而不是默认执行 guest 布局迁移。
- 随后在同一 session 中不使用绝对路径执行 `command -v tree` 和 `tree --version`：
  PATH 命中 `/home/codex/.local/codex-pkgs/usr/bin/tree`，版本为 `2.1.0`，退出码为 0。
  这确认新 worker 的 PATH 会自动包含 prefix 层；安装结果不是只能通过一次性绝对路径调用。
- 在没有运行中 turn 的情况下强制关闭并重新启动 `io.henry.codex`，Home 仍恢复原有
  workspace 与 session 列表；重新打开同一 `Run /system/bin/wm size` session 后，历史消息、
  DeepSeek provider、Root/PRoot 配置和 prefix PATH 均恢复，`command -v tree` 仍命中上述
  路径且 `tree --version` 返回 `2.1.0`、退出码 0。这证明该普通依赖层跨 App 重启持久化。

## 2026-09-28 第三方 provider 新版模型 metadata 兼容修复

- 对照仓库内随附 Codex `ModelInfo` 定义确认：较新的 CLI 从
  `model_messages.instructions_template` 读取模型指令模板，旧实现只写入兼容用的
  `base_instructions`，会使自定义模型被按缺失 metadata 的 fallback 路径处理。
- 第三方 provider 的每 session `models.json` 现在同时写入新版结构化
  `model_messages.instructions_template` 和旧版 `base_instructions`；不改变 API key、模型
  或 OpenAI/第三方互斥路由。provider launch 定向测试 `11/11` 通过，并覆盖新版字段、旧版
  兼容字段及 generic Responses 模型路径；该文件当前 `12/12` 通过。
- 真机现有 session 的 `models.json` 已确认仍是旧字段形态，因此本项代码修复需要下一次
  正式 APK 安装后通过新的第三方 session 观察 warning 是否消失；当前手机存在活跃 worker，
  暂不为了安装打断该 session。
- 随后完成正式 Release 编译与只读 APK 校验：`io.henry.codex`，117,812,583 bytes，
  SHA-256 `6a8c57d3b1e8cc1fcca7ab7c23f9313112594e7fb0daf7589bf09ef31b32253a`，4/4 ARM64
  Codex/PRoot native assets 齐全。该包尚未覆盖安装，等待当前真机 worker 由用户结束后再做
  保留数据的 `adb install -r` 和第三方新 session 验收。

## 2026-09-28 第三方 session 自动语义命名闭环

- 原自动命名入口只允许当前会话模型名包含 `luna`；DeepSeek 等第三方 session 因而只能
  使用首条 prompt 截断标题，无法得到 CC Pocket 风格的语义简介名。
- `CodexSessionClient` 增加独立的隐藏标题模型/推理档位：OpenAI session 固定使用手机默认
  `gpt-6-luna + low`，第三方 session 使用该 provider 已配置的模型，并优先使用其 `low`
  档位（没有 `low` 时使用配置中的第一档）。隐藏 turn 仍关闭工具、MCP、权限和计划能力，
  不把标题请求写入可见 transcript；手动重命名仍会取消它。
- 新增第三方自动标题协议回归；provider、session client 两组定向测试合计 `53/53` 通过。
  Flutter analyzer 本轮因现有 analysis server 的 LSP JSON 截断异常退出，未报告源代码诊断；
  该工具故障与测试通过结果分开记录。

## 2026-09-28 新版 Release 真机安装与第三方 metadata/turn 验收

- 在没有进行中 turn 的情况下，对 `io.henry.codex` 执行保留数据的 `adb install -r`，随后
  启动 `MainActivity`。包版本仍为 `1.0.0 (code 1)`；安装后 workspace、session 历史和
  provider 配置均保留。启动日志没有 `FATAL EXCEPTION`、`failed to load models cache` 或
  `model_cache_unavailable`。
- 打开已有第三方 session 后，真机 UI 同时显示 `Deepseek Flash`、`低`、`计划关闭`、`Root`，
  以及上下文用量环和输入/输出 token 计数；这确认新版 metadata 代码已经进入真实 APK，
  不是只在 Dart 单测中成立。
- 在该 session 中发送真实请求 `Reply METADATA_OK only`，流式 turn 完成并显示最终回复
  `METADATA_OK`，UI 回到“就绪”；上下文/输入输出计数正常更新。该请求没有产生模型 metadata
  warning、models cache 错误或 Android 崩溃日志。
- 该项现在从“代码和定向测试完成”推进为“Release APK + 真机第三方真实 turn 完成”。
  OpenAI 外部 endpoint 的网络超时仍是独立的设备网络问题，不能由本次 DeepSeek provider
  验收替代。
- 回到 Home 后，该会话标题已从原始的 `Run /system/bin/wm size` 更新为语义化的
  `Run wm size command`；标题生成没有把最新 assistant 回复直接当标题，且 session 的
  `Deepseek Flash` provider 仍保持不变。这给出了第三方自动命名在真实 UI 中生效的证据。

## 2026-09-28 PRoot CLI 应用内更新检查真机验收

- 在 Release 设置页实际进入“更新 Codex 命令行工具”，确认对话说明指向官方 npm 源；
  继续确认后，设备端 updater 完成版本检查并返回用户可见的 `Codex CLI 已是最新版本
  0.157.1`。
- 设备侧只读检查确认 `.codex-cli/current` 仍指向 `versions/0.157.1`，版本目录没有被
  无意义地重复安装，应用偏好中的活动 CLI 版本也仍为 `0.157.1`。这验证了“检查无更新”
  不会改写当前 runtime；旧版本 `0.156.1` 仍保留，可供回退流程使用。
- 本次检查没有停止或切换已有 session，也没有清理 guest home；Android native runtime
  与 PRoot CLI 的更新入口仍保持独立。

## 2026-09-28 中文本地化补齐与 Release 真机回归

- 补齐批量文本变更、宿主命令执行、登录/OAuth 状态、设置中的运行时诊断和原生工具链
  状态等界面的中文分支；Android 原生探测层返回的
  `App UID availability checked; full content hashes are verified during explicit import.`
  现在也会按应用语言显示为中文，不再把内部英文诊断直接暴露在设置页。
- Flutter 定向回归 `local_session_conversation_test.dart`、`settings_model_catalog_test.dart`、
  `codex_provider_launch_configuration_test.dart`、`codex_session_client_test.dart` 共
  `86/86` 通过。测试中仍有既有的 Google Fonts 网络加载告警，但没有测试失败。
- 重新构建 Release APK 并完成只读校验：`117,819,231` bytes，SHA-256
  `4fba8d598d7716d12ac7d9141a66818397fb4f9db60534cc7efcafb691addaa8`，包名
  `io.henry.codex`，4/4 ARM64 Codex/PRoot native assets 齐全；随后用 `adb install -r`
  保留应用数据覆盖安装，MainActivity 正常启动。
- 真机设置页 UI dump 已确认 `Android 原生工具链 · 应用 UID 可用性已检查；完整内容哈希会在显式导入时校验。`，
  同时没有出现 `full content hashes`、`failed to load models cache`、
  `model_cache_unavailable` 或 `FATAL EXCEPTION`。workspace、session 和既有 provider 数据
  保持不变。
- 当前包仍使用 Flutter Release 编译模式但 APK 签名为 Android debug certificate；这不影响
  本轮功能和真机覆盖安装，但若要对外分发仍需接入正式签名 keystore，不能把本包称为最终
  发布签名包。
- 覆盖安装后重新打开原有第三方 session，等待状态从“启动中”恢复为“就绪”，随后发送
  `Reply LOCALIZATION_OK only`；真机收到用户消息、最终回复 `LOCALIZATION_OK`，上下文
  环和输入/输出 token 计数继续更新，UI 回到“就绪”。这确认本轮设置页本地化改动没有
  破坏已有 session 的 provider、PRoot worker 或真实流式 turn。

## 2026-09-28 真机图片附件与第三方视觉模型回归

- 通过真实 Android 系统文件选择器选择 `/sdcard/Download/codex-real-image-smoke.png`，
  应用正确显示图片预览、`移除图片` 操作和可发送状态；这确认 picker、URI 读取、data URL
  转换及 composer 状态闭环均可用。
- 首张图片是接近全黑的会话空屏，DeepSeek Flash 返回 `Empty`；随后用明显的彩色
  `cc-pocket-icon.png` 做第二次真实 turn，模型返回 `Sparkles`，UI 回到“就绪”，上下文
  用量从 `11%` 保持可见且输入/输出 token 计数继续更新。该结果确认图片已经实际进入
  第三方 Responses turn，不是只验证了前端预览。
- 第二次回归同时覆盖了已有会话历史中的图片消息、连续附件发送和 Release worker；未出现
  `FATAL EXCEPTION`、`failed to load models cache` 或 turn 失败。图片 wire shape 仍保持
  Codex app-server 原生的 `type=image, url=data:*`，没有在客户端额外改造成 provider 专用
  协议，因而继续保持与 CLI 版本解耦。
- 两个仅用于本次回归的设备文件随后已按显式路径清理；没有触碰用户相册或其他下载文件。

## 2026-09-28 Root worker、宿主根目录与基础工具真机验收

- 在同一真实第三方 session 中执行只读诊断并展开 Codex 的真实
  `commandExecution` 结果。设备 UI 报告 worker 为 Android UID `0`、KernelSU
  `u:r:ksu:s0` context，session 状态回到“就绪”，没有产生新的 approval 或异常退出。
- guest 中的 Android 宿主根目录映射已被真实命令读取：`/android`、`/android/system`、
  `/android/vendor`、`/android/data` 与 guest 侧 `/system`、`/vendor`、`/data` 均返回目录
  metadata；随后代表性文件读取报告成功：`/android/system/build.prop`、
  `/android/data/system/packages.xml`、`/system/build.prop`。
- 同一 turn 的真实工具输出确认：`git 2.39.5`、`node v24.19.0`、`npm 11.17.0`、
  `npx 11.17.0`、`Python 3.11.2`，以及 prefix 中的 `tree 2.1.0`；命令解析分别命中
  `/usr/bin/git`、`/usr/local/bin/node`、`/usr/local/bin/npm`、`/usr/local/bin/npx`、
  `/usr/bin/python` 和 `/home/codex/.local/codex-pkgs/usr/bin/tree`。
- 该证据把 Root worker 和基础工具链从“进程存在/设置页显示”推进为真实 Codex turn
  数据面通过；本次只读诊断没有验证写入 boot 或关键启动配置，也没有执行任何写操作。

## 2026-09-28 app-server 最终 assistant item 兼容修复

- 补齐 `CodexSessionClient` 对另一种合法 app-server 事件顺序的处理：当某些 CLI 版本不发
  `item/agentMessage/delta`、只在 `item/completed` 的 `agentMessage.text` 中给出最终文本时，
  客户端现在会把该文本作为 assistant 消息投递；正常 delta 流按 item/turn 去重，不会重复显示。
- 新增协议回归 fixture，覆盖 completion-only 响应；`codex_session_client_test.dart` 定向测试
  `43/43` 通过。该改动没有绑定具体 CLI 版本，也不改变图片、provider 或 Root 路由。

## 2026-09-28 真机权限策略 turn 与最终消息兼容 Release 安装

- 在已有 Root/DeepSeek session 中实际打开权限菜单并选择“完全访问”，随后发送真实请求
  `Reply PERMISSION_MODE_OK only`；最终回复为 `PERMISSION_MODE_OK`，状态恢复“就绪”，没有
  新增逐条 Root approval、网络错误或 worker 退出。该选择与 Root 常规在当前协议中都映射为
  `danger-full-access + approvalPolicy=never`，因此顶部统一显示 `Root` 是同一后端策略的正确
  展示，而不是选择未生效。
- 将 `item/completed` 只带最终 `agentMessage.text` 的兼容修复纳入 Release APK。定向
  `codex_session_client_test.dart` 仍为 `43/43`；APK 校验通过，大小 `117,820,435` bytes，
  SHA-256 `fb22167feb731a131cde07e30fefb04c0bc9d417f223863bc94fbab19fdca92d`，4/4 ARM64
  Codex/PRoot native assets 齐全。
- 通过 `adb install -r` 保留应用数据覆盖安装并启动 `MainActivity`。workspace、session 标题、
  最近会话和用量卡片仍在；启动后未发现 `FATAL EXCEPTION`、`failed to load models cache` 或
  `model_cache_unavailable`。本包仍是 Release 编译但使用 Android debug certificate，正式
  分发签名仍待提供 keystore。
- 覆盖安装后重新打开原有 `Deepseek Flash` session，等待自动恢复到“就绪”，并发送真实请求
  `Reply RELEASE_COMPAT_OK only`；UI 收到最终回复 `RELEASE_COMPAT_OK`，上下文环和 token
  计数继续更新。该回归确认覆盖安装没有丢失第三方 provider、Root worker 或 session 历史。

## 2026-09-28 KernelSU 插件真机 stage/风险审阅

- 在设置页实际打开 KernelSU 插件区域，刷新能力检查返回“KernelSU 模块工作流可用”；该检查
  没有修改 KernelSU profile、模块或 session。
- 从 Android 系统文件选择器导入仓库内的无 payload 字体 fixture，仅执行归档验证与 stage。
  真机 UI 显示模块 `ccpocket.plugin.font`、有效风险 `R3`、2 个归档成员、需要重启和
  SHA-256 `81ed516f60f2f7c04db7de84890947ef731d623ad75de2631bfdf4cd311c3dec`，并显示“审批
  安装为禁用状态”。这证明 ZIP/manifest/路径/摘要/风险分类已经进入真实设备数据面。
- 本次明确没有点击安装/启用，没有写入 `/data/adb`、没有重启，也没有改变用户的 KernelSU
  配置；临时测试 ZIP 已从设备 Download 删除。R3 安装、禁用态 list/rollback 和设备凭据启用
  仍是后续独立动作，不能由本次 stage 验收替代。
- 随后点击设置中的“检查 KernelSU Root Profile”，真机返回 `Root 可用 · UID 0 · u:r:ksu:s0`，
  SELinux 为 Enforcing，组为 `0 3003 3009`，全局读取样本和工作区写入样本通过，应用数据/安装
  目录可读，系统配置写样本与 vendor 写样本未通过；该只读检查没有弹出新的逐条 Root approval。
  这确认当前用户配置的正常 `ksu` profile 已满足 Root worker 启动条件，同时没有把样本结果误报
  为所有系统路径都可写。
- 在同一新 Release 真机会话中输入 `/version`，UI 产生系统结果 `codex --version codex-cli
  0.157.1` 并回到“就绪”。这确认 slash command 入口确实调用活动 PRoot CLI，而不是只在前端
  显示命令文本；当前 `/cli`、`/status`、`/network-test` 仍应继续按命令族逐项补设备验收。

## 2026-09-28 `/cli --version` 真机复测与回归覆盖

- 针对上一轮真机中曾出现的 `$ /cli --version` 被第三方模型当成 shell 命令执行的问题，
  先在 Flutter widget 测试中补齐精确用例：`/cli --version` 必须走本地 slash handler，
  最终 argv 为 `['codex', '--version']`，不能启动普通 Codex turn。完整的
  `local_session_conversation_test.dart` 共 `24/24` 通过；定向测试同时通过，保留既有的
  Google Fonts 离线加载告警但没有测试失败。
- 在已连接真机上直接通过 Android 输入链路输入 `/cli`，得到本地用法提示；随后输入
  `/cli --version`，UI 产生系统结果 `codex --version codex-cli 0.157.1`，状态回到“就绪”。
  本次没有出现模型消息、`$ /cli --version` 工具卡片、`/bin/bash: /cli` 或网络请求。
- 结论：当前 Release 的本地命令路由和 PRoot CLI 执行链路可用；上一轮现象未能在同一安装包、
  同一真机输入链路上复现，暂不扩大到 app-server 或多进程架构改动。后续继续按 CLI 命令族
  逐项设备验收，发现可复现缺陷再做窄改。

## 2026-09-28 本地 `/status` 与 `/network-test` 真机验收

- 在同一真机、同一已恢复 session 中输入 `/status`，UI 返回本地系统结果：会话为 `idle`，
  运行环境为 `Linux Compatibility (PRoot)`，传输为 `Codex app-server（DeepSeek test
  Responses provider）`，消息数正常累计；没有启动新的模型 turn。
- 随后输入 `/network-test`，UI 返回 `api.deepseek.com：HTTP 401（DNS、连接与 TLS 可达；
  经代理 127.0.0.1:7890；服务端要求认证）`。这代表网络诊断本身已到达服务端，401 被正确解释
  为认证状态，而不是误报为“网络连接失败”；该命令同样没有创建新的 Codex turn。

## 2026-09-28 计划模式真机状态机验收

- 在同一 session 通过本地 `/plan` 命令切换一次，真机顶部状态从 `计划关闭` 变为 `计划开启`；
  再次执行 `/plan` 后恢复为 `计划关闭`。两次操作均停留在本地 session 状态路径，没有发送
  第三方模型 turn。

## 2026-09-28 非交互 CLI EOF 与模型目录真机验收

- 定位到上一轮 `codex debug models` 可能让本地命令状态无法收尾的原因：Android/PRoot
  的非交互子进程虽然不读取输入，但如果 stdin 一直保持打开，CLI 可能不会结束；同时
  `/cli` 执行路径和启动时的模型目录刷新路径都没有统一主动关闭 stdin。
- 在 `_runOneShotCommand` 和 `CodexModelCatalogClient` 两条路径统一使用已有的
  `StdinClosableExecution.closeStdin()`，保留 app-server、登录等交互进程的 stdin，不改变
  会话协议或 CLI 版本耦合方式。测试 fixture 也改为只有收到 EOF 才结束，以防回归。
- `local_session_conversation_test.dart` 完整回归 `24/24` 通过。Release APK 构建并通过
  ARM64 native asset 校验：`117,828,351` bytes，SHA-256
  `e8ee280c2d653a7a049368f57a59c0cde5e278a52d1757e1ce254e27e680bfa0`，4/4 Codex/PRoot
  native assets 齐全；通过 `adb install -r` 覆盖安装，未清除应用数据。
- 真机启动后原有会话从“启动中”恢复为“就绪”。实际输入 `/cli debug models`，UI 收到
  `codex debug {"models":[...]}` 模型目录结果，输入框保持可编辑；随后再次输入
  `/cli --version`，收到 `codex --version codex-cli 0.157.1`。两条命令均未启动普通模型
  turn，也没有出现 `/bin/bash: /cli`、`FATAL EXCEPTION` 或卡死后只能重启应用的现象。
- 随后手动执行 `/refresh-models`；当前会话使用 DeepSeek 第三方 provider，因此 UI 正确提示
  “第三方 provider 未提供模型目录；当前配置模型保持不变”，而不是伪造 OpenAI 模型列表；
  输入框仍保持可编辑。`codex_model_catalog_test.dart` 定向回归 `5/5` 通过。
- 新 Release 再执行 `/network-test`，真机继续返回第三方 endpoint 的 `HTTP 401`，并明确显示
  DNS、连接与 TLS 可达、服务端要求认证；命令结束后输入框仍可编辑，当前 transcript 没有
  `failed to load models cache` 或 `model_cache_unavailable`。
- 新增模型目录专用 EOF 回归夹具：CLI 目录 fixture 只有在收到
  `StdinClosableExecution.closeStdin()` 后才会发送 JSON/退出；`codex_model_catalog_test.dart`
  现为 `5/5` 通过，后续 CLI 更新不能在不知不觉中移除该收尾动作。
- 本轮没有修改 KernelSU profile、Root 组、rootfs 内容或用户数据；Android debug
  certificate 的正式签名限制仍与前述记录一致。

## 2026-09-28 KernelSU 插件管理 UI 闭环补齐

- 设置页此前只接通了导入、审阅、安装和高风险启用；安装成功后没有把已有的
  `disable`、`uninstall`、`rollback` native 操作暴露出来，导致 UI 看起来像只能单向安装。
- 现在安装状态由 native 操作返回的真实 operation 更新，已安装模块在设置页显示启用/禁用状态，
  并提供禁用、重新启用、卸载和单级回滚按钮；卸载前有明确确认，R4 回滚仍复用启动链目标审阅，
  不修改 KernelSU profile、组或 SELinux 配置。
- 回滚后保留当前 stage 的已校验身份；页面提示重新导入归档即可审阅恢复版本，避免伪造未知的
  `ksud module list` 输出。native `list` 目前仍只报告固定命令是否成功，未被当作模块清单显示。
- `kernelsu_plugin_settings_test.dart` 已覆盖 R3 安装为禁用、启用、禁用、回滚和卸载的真实方法调用，
  定向 Flutter 回归 `5/5` 通过；本轮未在真机执行安装/启用/卸载，未触碰设备 KernelSU 状态。
- 同一设置页现在也对 manifest 声明的插件 action 提供二次确认后执行入口，并保持 action ID
  只能来自已校验归档，定向测试覆盖 `runAction` method-channel 调用。

## 2026-09-28 本轮 Release 回归与编译阻塞修复

- 全量 Flutter 回归第一次运行暴露 `batch_text_change_page.dart` 的既有编译阻塞：
  `_text()` 依赖运行时 locale，却被放在 `const Text`/`const InputDecoration` 中。移除这些错误的
  const 约束后，批量替换页定向测试通过，全量 Flutter 测试恢复为 `328/328`。
- 本轮 UI 改动已完成 Release 构建并通过只读 APK verifier：包 `io.henry.codex`，
  `117,844,787` bytes，SHA-256 为
  `75f777ee3c095a6503f9a5f8479ec1887d18a7384d51831ed24897f6d2ac5dfc`，4/4 ARM64
  Codex/PRoot native assets 齐全。签名仍是本地 Android debug certificate，不是商店分发签名。
- 真机 `6cb21282` 仍有 `libcodex`/PRoot/Codex worker 运行；为避免覆盖安装打断当前 session，
  本轮只完成构建和静态 APK 验证，未覆盖安装。下一次 worker 空闲后再安装并复验设置页管理按钮。

## 2026-09-28 KernelSU 已安装模块清单数据面接通

- 通过真机只读执行 `ksud module list` 确认当前 KernelSU 返回的是 JSON 数组，包含模块的
  `id`、`name`、`version`、`author` 和字符串形式的 `enabled` 状态；本次没有修改模块、profile、
  组或 SELinux 配置。
- 原生 `PluginBroker` 现在只对固定的 `list` 操作有限捕获 stdout，最大 512 KiB，并解析为安全的
  模块摘要；控制字符和超长字段会被丢弃，原始 root 输出不会进入 Flutter 层。其他插件操作仍不
  捕获 root 输出，保持原有边界。
- 设置页的“刷新已安装模块”现在会显示真实模块清单及启用状态；刷新是显式动作，不会在打开设置
  页面时自动触发 root 操作，也不会新增逐条 Root approval。Flutter bridge、Kotlin parser 和
  safe-field 过滤均已覆盖测试。
- 全量 Flutter 回归 `329/329` 通过。原生 `PluginBrokerTest` 通过；Release APK 构建及只读校验
  通过：`117,850,683` bytes，SHA-256 为
  `f1d551660caca0869000b5ffe5358c85d72a7cd7c851d42cd6b64ad056543e36`，4/4 ARM64
  Codex/PRoot native assets 齐全。
- 由于真机上仍检测到现有 Codex worker/PRoot 进程，本轮没有强制停止或覆盖安装，避免打断用户的
  活跃会话；该 APK 待 worker 空闲后安装，再进行设置页模块清单的真实 UI 验收。

## 2026-09-28 KernelSU 模块清单真机 UI 验收

- 通过 ADB UI 状态确认现有会话为“就绪”、输入框可用且没有进行中的 turn 后，使用本轮 Release
  执行保留数据的 `adb install -r`，安装成功并重新启动 `MainActivity`；workspace、session、
  provider 和历史数据仍然存在。
- 设置页滚动到 Root 能力区域，点击“刷新已安装模块”后真实调用 KernelSU `ksud module list`，
  UI 显示“已读取 9 个模块”。展开清单后显示真实的模块名称、ID、版本、作者及启用状态，包含
  `MFGA`、`WorkSettingPro`、`RescueBrick`、`meta-overlayfs`、`zygisksu`、三个
  `ccpocket.plugin.*` 模块和一个已禁用模块；没有把原始 root 输出泄露到 transcript。
- 本次只读清单操作没有安装、启用、禁用、卸载或回滚任何 KernelSU 模块，也没有改动 profile、组、
  SELinux 或 boot。最近 400 行 logcat 未发现 `FATAL EXCEPTION`、`failed to load models cache`、
  `model_cache_unavailable` 或 native runtime update 错误。
- 这项能力已从“代码/单测完成”推进为“Release APK + 真机设置页真实数据闭环完成”；插件归档的
  harmless stage/apply/rollback 仍保持未执行，避免把只读验收误报成写操作验收。

## 2026-09-28 KernelSU 校验归档在 App 重启后恢复

- 新增 app-private 的 `restoreStage` 路径：App 启动设置页时只扫描自己的 staging 目录，按最新归档
  重新校验 ZIP、manifest、模块 ID 和摘要后恢复最近一次已验证的插件归档；不调用 Root、不会读取
  `ksud module list`，也不会因为打开设置而弹出 KernelSU 授权。
- 当前安装/启用状态仍必须由用户显式点击“刷新已安装模块”读取真实 KernelSU 状态，避免把本地归档
  恢复误认为设备模块状态。恢复失败时保留手动导入入口，不阻塞设置页。
- Kotlin `PluginBrokerTest` 定向通过；KernelSU 设置 Flutter 定向回归 `7/7` 通过；全量 Flutter
  回归 `330/330` 通过。
- 新 Release APK 已构建并通过只读校验：包 `io.henry.codex`，`117,852,727` bytes，SHA-256
  `bdad8daff3785ed29055d14c38920b54deafa2ef975a3dafe4f733a899d2c728`，4/4 ARM64
  Codex/PRoot native assets 齐全；签名仍为本地 Android debug certificate。
- 真机 `6cb21282` 已保留数据增量安装并启动成功；旧工作区、会话和登录状态仍在。进入设置的 Root
  能力区域后，页面真实恢复上次校验的 `ccpocket.plugin.font` 归档并显示 R3 摘要，过程未触发
  Root 授权。未执行模块安装、启用、禁用、卸载、回滚，也未修改 KernelSU profile、组、SELinux
  或 boot；安装后日志未发现应用崩溃、模型缓存失败或 native runtime 更新错误。

## 2026-09-28 新 Release CLI 命令真机复测

- 在新建 Root session 中首次执行 `/cli --version` 时出现一次会话级 Root 授权；确认“允许此会话”
  后命令真实走 Linux/PRoot 活动 CLI，返回 `codex-cli 0.157.1`，没有再次逐条 Root 审批。
- 同一 session 随后执行 `/cli debug models`，返回真实模型目录 JSON，未出现历史记录中的
  `unexpected argument '--json'`，也没有 `failed to load models cache`；输入框仍保持可用。
- 该复测只新增了一个本地测试 session 和 CLI 结果，没有发起模型 turn、没有触碰 KernelSU
  模块/配置、没有修改 workspace 文件；当前会话保持空闲，可继续由用户使用。

## 2026-09-28 Root/PRoot guest 依赖安装链路修复

- 真机 Root/PRoot 依赖烟测确认了 `sudo` 映射后的下一个真实缺口：guest 的 `/usr` 已经是
  merged 布局，但 dpkg 状态缺少 `usr-is-merged`，导致 `init-system-helpers` 的依赖未满足，
  `sudo apt install` 退出 100。
- 修复 `device/proot-finalize-rootfs.sh` 和 `builder/finalize-on-device.sh`：保留 Debian 的
  `usr-is-merged` 第二阶段包，并按 Debian 约定写入
  `/etc/unsupported-skip-usrmerge-conversion`，跳过不必要的转换而保留完整 dpkg 依赖状态。
  删除了此前从 debootstrap 元数据移除该包的逻辑；离线检查新增了对应回归断言。
- 在当前真机 guest 内先按同一规则恢复包状态，随后只在 guest 中执行真实安装：
  `sudo apt-get install --yes file` 成功，安装 `file`、`libmagic-mgc`、`libmagic1`，返回码为 0；
  `apt-get check` 也返回 0。出现的 `Fake ldconfig called` 是 PRoot guest stub 的提示，不是安装失败。
- 本次没有读取或修改 `/android`、Android 宿主分区、KernelSU profile、组、SELinux 或 boot；
  现有设备 rootfs 的包状态已修复，新的 rootfs 需要使用更新后的 finalizer 才能从安装阶段直接继承该状态。
- 随后完成 Release 构建并通过 APK 只读校验：包 `io.henry.codex`，`117,853,047` bytes，
  SHA-256 `5b539f5a388896dc1c8c68de8d40869ba80795154e90bea21ad97e6989c555e4`，4/4 ARM64
  Codex/PRoot native assets 齐全；保留数据增量安装到真机成功，workspace、session、provider
  和首页历史仍在，启动后未发现崩溃、模型缓存失败或 native runtime 错误。

## 2026-09-28 Root 宿主 linkerconfig 绑定修复

- 真机宿主只读检查发现 `/android/system/bin/id` 和 `getprop` 能执行并返回正确结果，但
  Android/Bionic 曾提示找不到绝对路径 `/linkerconfig/ld.config.txt`。设备本体确认该目录和
  文件存在；根因是 App UID 在构造 Root argv 时无法可靠探测该目录，把它从固定绑定列表中过滤掉。
- Root PRoot 绑定列表加入 `/linkerconfig`，并在 Android 10+ 的 Root 构造路径中显式保留该目录，
  不依赖 App UID 的可见性探测。`CompatibilityRootLaunchScriptTest` 和相关 Kotlin 定向单测通过。
- 新 Release APK 只读校验通过：`117,853,079` bytes，SHA-256
  `206b57c06365d670a9ae7fc8337ed3dc33b3b63afadcfbff311d195f30c13771`；已增量安装到真机。
  新 Root session 中再次验证真实 Android UID 0、`getprop ro.product.device=aurora` 及
  `/android/data/adb/ksu` 目录可读，输出不再出现 linkerconfig 警告；没有写入宿主或 KernelSU 状态。

## 2026-09-28 Root/PRoot Android 命令无 PATH 真机闭环

- 第一次只把 Android bin 目录加入启动时 `PATH`，但真实 Codex 子 shell 会重建自己的 PATH，
  因此 `pm` 和 `settings` 仍然出现 `command not found`。这确认问题不是 KernelSU profile、Root
  身份或命令内部权限，而是 CLI 子进程环境没有继承启动器 PATH。
- Root guest 现在把经过校验的 `cmd`、`pm`、`settings`、`appops`、`wm`、`device_config`、
  `dpm`、`ime`、`input`、`locksettings` shim 同时映射到 guest 的 `/usr/bin`（保留原有
  `/system/bin` 映射），让普通 Debian shell 在自身默认 PATH 下也能解析 Android 命令。shim
  仍只转发到 Android `/system/bin/cmd`，没有新增通用 Root broker 或逐命令审批。
- 最新 Release APK 构建并通过校验：包 `io.henry.codex`，`117,853,131` bytes，SHA-256
  `8bc08ba41f4fd4ac149452d165ffd53bcc542aec7db2d7e29289d72e2ccbc112`，4/4 ARM64 Codex/PRoot
  native assets 齐全；已保留数据增量安装到真机。
- 真机 Root session 在不手工设置 `PATH` 的条件下复测通过：`command -v pm`/`command -v settings`
  解析到 `/usr/bin` shim，`pm list packages` 返回设备包清单（包含 `io.henry.codex`），
  `settings get system screen_off_timeout` 返回 `600000`；整个复测为只读操作，没有修改 Android
  宿主、KernelSU profile、组、SELinux、boot 或 workspace 文件。

## 2026-09-28 Root/PRoot Android 宿主诊断命令闭环

- 真机验证发现 `getprop`、`dumpsys`、`logcat` 的 Android 宿主二进制都能执行，但在 Codex
  子 shell 重建 PATH 后无法按命令名解析；绝对路径并没有问题。这与前一项 `pm/settings`
  是同一类 guest 命令发现缺口。
- Root guest 现在为 `getprop`、`dumpsys`、`logcat` 安装固定、可校验的 `/usr/bin` shim，分别
  直接转发到 `/android/system/bin` 下的真实 Android 二进制；没有增加通用 shell broker、
  逐条 Root approval 或新的 KernelSU 限制。
- 最新 Release APK 只读校验通过：包 `io.henry.codex`，`117,853,391` bytes，SHA-256
  `804a6044e97d19a088bb39a6e506182595da47f536cccef1cbbb25df700b58ef`，4/4 ARM64 Codex/PRoot
  native assets 齐全；保留数据增量安装到真机成功，旧 workspace、session 和 provider 均保留。
- 真机 Root session 无手工 `PATH` 复测通过：`command -v getprop`、`command -v dumpsys`、
  `command -v logcat` 均解析成功；`getprop ro.product.device` 返回 `aurora`，`dumpsys battery`
  能读取电池状态，`logcat -d -t 1` 能读取一行并退出。全程只读，没有修改 Android 宿主、
  KernelSU profile、组、SELinux、boot 或 workspace 文件。

## 2026-09-28 Root/PRoot 基础开发工具真机复测

- 在最新 Release 的 Root session 中对 guest 子 shell 做了无写入版本探测，`git`、`node`、`npm`、
  `npx`、`python` 和 `python3` 均能按命令名解析并执行。
- 真机返回：git `2.39.5`（`/usr/bin/git`），Node `v24.19.0`（`/opt/node/bin/node`），npm/npx
  `11.17.0`，Python `3.11.2`；`python` 与 `python3` 都解析到 guest 的 Python 3.11 解释器。
  npm/npx 的 `/usr/local/bin` 入口正确指向已验证的 `/opt/node/bin` toolchain。
- 该复测只读取版本和解析路径，没有安装包、写 workspace 或改变 Android/KernelSU 状态；此前的
  “基础工具不可用”缺口在当前真机运行时已经闭环。

## 2026-09-28 实体真机图片输入与第三方模型闭环

- 在 `6cb21282` 真机的真实 Root session 中打开 composer 图片入口，选择设备相册图片并完成
  真实 DeepSeek provider turn；会话返回了对电路板图片的图像描述，流式回复和 usage/context
  统计均正常，发送后会话回到“就绪”。这证明实体手机上的选择器、图片读取、provider
  `image_url` 映射和实际网络请求均已连通。
- 同一入口对一张约 9.52 MiB 图片按预期拒绝，并在 composer 显示“每张图片不得超过 8 MiB”类
  提示，没有静默截断或发送超限附件；随后用约 3.29 MiB 图片完成成功路径。
- 测试期间临时推送到 `/sdcard/Download/codex-android-image-test.png` 的文件已删除，设备侧
  `ls` 确认不存在；没有留下用户存储垃圾，也没有修改 workspace、KernelSU、SELinux 或 boot。

## 2026-09-28 Root 普通路径可逆写入真机验收

- 在同一实体真机 Root session 中执行了明确限定到 `/data/local/tmp` 的可逆 smoke：UID-0 worker
  创建临时文件、写入一行、读取回原内容并删除；会话返回每一步成功，文件删除后设备侧复查不存在。
- 该结果证明普通 Android host 路径的 Root 写入没有被应用架构层强制改成只读或逐条 Root 审批；
  仅代表这个普通临时路径，不外推到 boot、raw block 或其他分区，也没有触碰这些目标。

## 2026-09-28 Session 模式控件真机验收

- 在实体机现有 Root session 的真实会话页打开 effort 菜单，UI 能显示当前 provider/model 的
  effort 状态；切换计划模式后顶部状态从“计划关闭”变为“计划开启”，再次切回恢复“计划关闭”。
  这次没有发送受模式影响的额外 turn，避免改变用户会话语义。
- 打开权限入口后真实显示三种当前后端选项：普通 Root（完整宿主可见、普通命令不逐条询问）、
  完全访问（`danger-full-access + 不询问`）和应用级只读；保留原来的普通 Root 选择并关闭菜单，
  没有伪造“默认”状态或修改 KernelSU 配置。

## 2026-09-28 Root/PRoot apt 依赖安装真机复测

- 在实体真机的 Root/PRoot guest 中真实执行 `sudo apt-get install --yes tree`，命令链正常完成；
  `tree` 已存在于 Debian guest，apt 正确解析为无需变更，没有额外安装或改动其他包。
- 随后执行 `tree --version` 返回 `tree 2.1.0`；这确认当前 guest 的 apt 依赖路径已经能够正常工作，
  不再被此前的 usr-merge/基础环境问题阻断。测试没有修改 Android 宿主、KernelSU、SELinux、boot
  或用户 workspace。

## 2026-09-28 CLI 独立更新入口真机复测

- 在实体真机设置页打开“更新 Codex 命令行工具”，确认对话框明确说明只更新应用私有
  Linux/PRoot CLI、保留旧版本且不替换 APK 内 Android native runtime；随后真实点击“检查并更新”。
- 操作完成后设置页仍可正常显示并重新读取运行时信息：活动 CLI 保持为 `0.157.1`，没有出现更新异常、
  `failed to load models cache`、`FATAL EXCEPTION` 或 native runtime 错误。由于当前活动 CLI 已是可用版本，
  本次没有发生不必要的替换；更新入口、版本探测和模型刷新路径均实际执行。
- 该操作没有清理 workspace/session/provider 数据，也没有修改 KernelSU profile、组、SELinux、boot
  或宿主文件；当前设备仍停留在设置页，可继续进行后续能力验收。

## 2026-09-28 Root/PRoot 常用 Android 宿主命令补齐与冲突修正

- 扩展 Root guest 的固定宿主命令 shim：`am`、`content`、`svc` 与既有的 `getprop`、`dumpsys`、
  `logcat` 一样映射到 `/usr/bin`，解决 Codex 子 shell 重建 PATH 后的命令发现问题；它们仍直接
  执行 `/android/system/bin/*`，没有新增 broker 或逐条审批。
- 真机初次复测发现 `service` 与 Debian `/usr/sbin/service` 同名。最终实现没有覆盖这个 Linux
  标准命令：`content`/`svc` 命中 `/usr/bin` 的 Android shim，`service` 保持 `/usr/sbin/service`；
  需要 Android `service` 时使用明确的 `/android/system/bin/service`，避免破坏 guest 的系统工具语义。
- 定向 Kotlin 单测通过；最终 Release APK 只读校验通过：包 `io.henry.codex`，`117,853,435` bytes，
  SHA-256 `02baba2f5bcfa49311f5f2a362c92149b7165c6fcff23d408def08cfe7824b0c`，4/4 ARM64 native
  assets 齐全；已保留数据增量安装到实体真机并重新启动。
- 真机 Root session 复测返回 `am` 的宿主 shim、`content` 为 `/usr/bin/content`、`svc` 为
  `/usr/bin/svc`，`service` 为 `/usr/sbin/service`；会话回到“就绪”，上下文/用量继续显示，
  最近日志没有 `FATAL EXCEPTION`、模型缓存错误、`try_lock` 或网络错误。测试只读取解析路径和
  shim 内容，没有执行宿主写操作，也没有修改 KernelSU、SELinux、boot 或 workspace。

## 2026-09-28 Android 原生运行时更新器 GitHub API 限流回退

- 真机设置页首次点击“更新 Android 原生 Codex”真实暴露了此前未覆盖的故障：GitHub Releases API
  返回 HTTP 403，UI 显示 `GitHub release API rate limit reached or request forbidden`，而不是无响应。
- 更新器现在在 API 403/429 限流时回退到公开 Releases HTML 页面，解析严格匹配的
  `android-codex-native/vX.Y.Z` tag；再按固定仓库、固定资产名读取 `codex.manifest.json`，从 manifest
  获取二进制大小并校验版本、ABI、来源、SHA-256，随后才允许下载二进制。没有 Android release 时
  返回正常的“尚无 Android 原生 Codex 发布版本”，不把 macOS/Linux/Windows release 当作候选，也不
  放宽任意 URL 或完整性校验。
- 新增公开 Releases tag 解析单测并通过；最终 Release APK 只读校验通过：包 `io.henry.codex`，
  `117,854,687` bytes，SHA-256 `5934d1128e524d8f6a32710d6b15b08aedb59026feb06dd9159fab915c6bdb36`，
  4/4 ARM64 native assets 齐全；已保留数据增量安装到实体真机。
- 真机设置页再次执行更新后返回“尚无 Android 原生 Codex 发布版本；可继续使用本地导入的运行时”，
  不再出现 API 403；workspace/session/provider 未清理，日志无崩溃、模型缓存错误或 native updater 错误。

## 2026-09-28 工作区文件管理入口补齐

- `WorkspaceFilesPage` 和批量文本替换页面此前已有后端实现与 widget 回归，但首页工作区卡片没有任何入口，
  因此这条能力在实际 App 中不可达。
- 复用现有 CC Pocket 工作区卡片的溢出菜单，新增“浏览文件 / Browse files”，从首页把当前 workspace
  路由到 `WorkspaceFilesPage`；兼容 backend 会按 workspace 的 backend ID 选择，不改变 session 或
  app-server 生命周期。文件页继续提供目录浏览、托管文件变更预览，并在 AppBar 暴露“批量替换 /
  Batch replace”入口。
- 菜单项改为可收缩文本，避免新增入口后在手机窄屏上发生 `RenderFlex` 横向溢出。
- 新增首页菜单和文件页批量替换入口的可达性回归；`ccpocket_native_home_test.dart`、
  `workspace_files_page_test.dart`、`batch_text_change_page_test.dart` 共 9 项通过。此前的横向
  溢出失败已修复并由同一组测试复验。
- 本轮未构建或覆盖安装 APK；下一次真机 Release 验收应从首页工作区菜单进入“浏览文件”，确认真实
  workspace 的目录列表、单文件预览和批量替换入口均可见。

## 2026-09-28 工作区文件入口 Release/真机验收

- 重新构建 Release APK 并通过只读校验：包 `io.henry.codex`，`117,949,755` bytes，SHA-256
  `a764da1ce596342976aabe67e1233e8e81b67f81d36e966b810f92e398afb00c`，4/4 ARM64
  Codex/PRoot native assets 齐全；签名仍为本机 Android debug certificate。
- 通过 `adb install -r` 增量安装到实体设备 `6cb21282`，workspace、session、provider 和历史
  数据仍在；Activity 启动成功。首页工作区卡片真实显示与之前一致，未出现崩溃、模型缓存失败、
  `try_lock` 或 native updater 错误。
- 真机从首页工作区菜单打开“浏览文件”，页面真实显示“文件”、当前 workspace 路径、`README.md`
  条目和“批量替换”按钮；随后返回首页。该链路没有启动模型 turn，也没有改写 workspace 文件。

## 2026-09-28 工作区文件工具入口补齐

- 复用现有文件页接入两个此前只有实现、没有生产入口的能力：工作区工具菜单现在可打开“宿主命令 / Host
  command”，在支持本地 Android backend 时同时显示“备份历史 / Backup history”。
- 宿主命令页继续使用当前 backend 和 workspace，不改变 Root/PRoot 运行策略；备份页仅对
  `LocalAndroidBackend` 暴露，避免对不支持备份语义的兼容 backend 伪造入口。
- 定向回归通过：文件浏览、批量替换、宿主命令路由、首页工作区入口及相关 CC Pocket session 测试共 9 项全部通过。
- Release 构建和只读 APK 校验通过：包 `io.henry.codex`，`117,997,135` bytes，SHA-256
  `2e632f4e18535029fe6b78da9dc353a9607233778c258c1aaada020c597d488f`，4/4 ARM64 native assets
  齐全；已通过 `adb install -r` 增量安装到实体设备 `6cb21282`，没有清理 workspace/session/provider 数据。
- 真机从首页工作区菜单进入“浏览文件”，文件页真实显示“批量替换”和“工作区工具”；打开工具菜单可见“宿主命令”
  和本地 backend 的“备份历史”，再进入“宿主命令”后真实显示显式 argv、应用 UID/Root 助手、运行命令和原生工具
  探测控件。当前测试没有执行宿主写操作或命令，只验证导航和控件可达性。
- 重新启动 App 后再次进入同一工作区的“备份历史”，真实读取到已有备份元数据并显示“恢复”入口；页面说明
  备份位于应用私有目录、恢复前会重新检查版本。未点击恢复，因此没有改写 workspace 文件。
- 随后执行完整 Flutter 回归，`330` 项全部通过；测试期间 Google Fonts 的远程字体加载提示仍是非致命
  网络警告，不影响测试结果和 APK 内置字体/真机运行。
- 在宿主命令页选择“Root 助手”执行默认无写入命令 `id`，真机返回 `uid=0(root)`、
  `context=u:r:ksu:s0`、`[exit 0]`；这确认该入口确实走当前 KernelSU Root worker，而不是只显示
  静态的 Root 状态。测试没有触碰文件、boot、KernelSU profile 或系统配置。
- 全量 `flutter test` 之后重试静态检查：Flutter analysis server 仍因工具链返回截断的 LSP JSON 而异常退出；
  直接运行同一 Flutter SDK 的 Dart analyzer 成功完成，未发现 error，只有既有 unused/dead-code、空安全和
  API deprecation 警告。该工具链问题不影响本轮 Release 编译或测试结果，暂不把全仓库无关 warning 扩大成返工范围。

## 2026-09-28 工具能力状态语义与本地化修正

- 修正 `HostToolProbe` 的状态语义：探测会通过当前选择的 backend/identity 实际执行命令并收到退出码 0，
  因此结果标为 `Verified`；`Available` 保留给仅知道已安装但尚未完成执行验证的状态，`Missing` 和 `Failed`
  继续区分缺失与执行错误。
- 宿主命令页的工具状态按当前语言显示：中文为“已验证/可用/缺失/失败”，英文保持
  `Verified/Available/Missing/Failed`，不再在中文页面显示英文 `Available`。
- 定向 `host_tool_probe_test.dart` 与工作区文件页测试通过；Release APK 重新构建并校验：包 `io.henry.codex`，
  `117,998,131` bytes，SHA-256 `f2b958d89af5084267af6355a4111a383ab34bff1ab56160ac03298f826790d0`，
  4/4 ARM64 native assets 齐全；已增量安装到实体设备 `6cb21282`。
- 真机 Root 工具探测再次完成，git、node、npm、npx、python、jq、curl、bash、ripgrep 和 Android shell
  均显示“已验证”；未执行写操作。
- 状态语义修正后的全量 Flutter 回归再次通过，`330` 项全部通过；Google Fonts 远程字体加载提示仍为
  非致命测试环境网络告警。

## 2026-09-28 真机第三方模型真实 turn 回归

- 使用当前设备已保存的第三方 Responses provider 会话，从真机 UI 发送无副作用测试提示
  `Reply with REAL_TURN_OK only`；Codex app-server 正常完成真实 turn，并返回 `REAL_TURN_OK`。
- 会话状态从“启动中”进入“就绪”，没有回到失败或断开状态；当前会话仍保留 Root、模型
  `Deepseek Flash`、低 effort 和计划关闭等状态。
- 会话顶部上下文指示器真实显示 `Context usage 15%`，turn 后用量从约 `in 4.9M / out 24.6k`
  更新到 `in 5.0M / out 24.6k`，证明流式回复、用量/上下文更新和最终回复均通过 UI 数据面闭环。
- 本次真机日志过滤没有发现网络连接失败、`failed to load models cache`、`try_lock`、权限错误或
  `FATAL EXCEPTION`。当前 Release 仍为包 `io.henry.codex`、SHA-256
  `f2b958d89af5084267af6355a4111a383ab34bff1ab56160ac03298f826790d0`；该证据不代表总体 Goal 已完成，
  仅确认当前第三方真实会话链路可用。

## 2026-09-28 会话内 CLI 登录状态命令接入

- 修复 `/cli login status` 路由仍被当作普通账户设置提示的问题。现在该命令复用当前
  session 的真实 `codex login status` 探测，结果以系统消息写回当前会话；不会创建第二个
  app-server，也不会把凭据或原始认证输出写入 transcript。
- `/cli login`、`/cli logout` 仍沿用设置页的认证流程，避免在会话输入框中绕过现有 API key/
  浏览器 OAuth 状态管理；因此本次只补齐无副作用的状态查询，不改变登录架构。
- 新增会话交互回归，验证命令参数、真实 one-shot 调用和“Codex login status: Logged in”结果；
  针对 `codex_cli_arguments_test.dart` 与 `local_session_conversation_test.dart` 的 43 项测试全部通过。
- Release APK 已通过只读校验并增量安装到实体设备 `6cb21282`：包 `io.henry.codex`，大小
  `118,000,363` bytes，SHA-256
  `6f70db06abb4ec1ccfc7841296da00c717c3812fd14fe6a96c7b2a8a77ab4eff`，4/4 ARM64 native assets
  齐全。真机重新打开既有 session 后执行 `/cli login status`，UI 实际显示“Codex 登录状态：Logged in”，
  session 保持“就绪”，原有历史、模型、上下文和用量没有丢失。

## 2026-09-28 会话内 MCP OAuth 登出接入

- 上游 CLI 的 `mcp logout <server>` 现在可从会话 composer 的 `/cli mcp logout <server>`
  调用。实现使用当前 session 的 `CODEX_HOME` 和已验证的 Codex runtime 执行一次受控 argv，
  不启动第二个 app-server、不走 shell 解析，也不把凭据内容写入 transcript。
- 只读 session 会明确拒绝凭据删除；Root session 继续使用已有的 session 级授权，不增加逐命令
  Root 弹窗。命令输出仅保留退出状态和 CLI 的非敏感摘要。
- 新增参数解析与会话交互回归；本轮 CLI/MCP 定向测试 44 项全部通过。真机 Release 安装与
  `/cli login status` 已验证，MCP logout 代码路径尚待在有可注销 OAuth MCP 的真机配置上做
  一次实际凭据数据面验收，不能用当前没有可注销 MCP token 的设备状态冒充完成。
- 本轮 Release APK 通过校验并安装到实体设备 `6cb21282`：包 `io.henry.codex`，大小
  `118,009,159` bytes，SHA-256
  `da5ad8b5ee1df15482cf891e0717052cfd99ef4cb9c467819a3b5a081f5d8113`，4/4 ARM64 native
  assets 齐全。安装后首页仍显示原有两个 workspace、最近会话和 Codex 用量；启动日志没有
   `FATAL EXCEPTION`、模型缓存失败、`try_lock`、网络连接失败或权限错误。

## 2026-09-28 会话内 app-server command/exec 接入

- 当前 session client 新增 `command/exec` buffered RPC 封装；它复用已有的 Codex
  app-server、CODEX_HOME、workspace cwd 和当前 permission profile/sandbox，不再为会话内命令
  另起一个 Codex CLI 进程。
- composer 新增 `/exec <argv...>` 入口。输入仍经过现有 argv tokenizer，拒绝控制字符，
  不执行 shell 管道、重定向或命令替换；输出和退出码以当前会话 transcript 显示，最多保留
  6000 个字符，避免异常命令把 UI 撑爆。PTY、stdin streaming 和后台 job 列表仍未实现。
- 新增会话交互 fixture，覆盖请求参数、session cwd、返回 stdout/退出码和 UI transcript；
  `codex_cli_arguments_test.dart` 与 `local_session_conversation_test.dart` 定向测试共 44 项全部通过。
- 真机 Release 构建通过并覆盖安装到 `6cb21282`，保留原 workspace/session/provider 数据：包
  `io.henry.codex`，大小 `118,025,979` bytes，SHA-256
  `56855f7147bfb3bc0c872ad1cd494acdb495984da7412d5df26811fec78c7cf9`，4/4 ARM64 native
  assets 齐全；该构建还包含会话命令菜单中的 `/exec <argv>` 入口。
- 真机在既有 Root/DeepSeek session 中执行 `/exec /system/bin/id -u`，UI 返回退出码 0 和结果
  `0`；进程表仍只有该 session 的一个 Codex/PRoot worker 链，没有因为 `/exec` 启动第二个
  Codex。最近 600 条 logcat 过滤未发现 `FATAL`、`try_lock`、网络连接失败、模型缓存失败或
  `command/exec` 异常。

## 2026-09-28 会话内 command/exec 流式输出与终止

- 将同一条 session 的 `command/exec` 从仅缓冲返回扩展为流式 argv 执行：请求携带连接级
  `processId` 和 `streamStdoutStderr`，session client 接收上游
  `command/exec/outputDelta` 的 Base64 stdout/stderr 分片并按原顺序合并；最终响应仍校验退出码，
  不会为命令创建第二个 Codex app-server。
- `/exec <argv...>` 在当前 CC Pocket 会话中原位更新 `command/exec` 工具结果，输出到达即显示，
  结束后保留退出结果；既有 `/interrupt` 路径会调用 `command/exec/terminate`。shell 语法、PTY stdin、
  窗口 resize 和后台 job 列表仍未实现，本轮不把这些缺口标记为完成。
- `codex_cli_arguments_test.dart` 与 `local_session_conversation_test.dart` 定向测试共 `44` 项全部通过；
  Google Fonts 远程字体提示仍是非致命测试环境网络告警。
- Release APK 已通过只读校验并覆盖安装到实体设备 `6cb21282`，未清理已有 workspace/session/provider
  数据：包 `io.henry.codex`，大小 `118,027,283` bytes，SHA-256
  `0b10efd7434bcfed0e033f9a0c701a63a770a4ee4ae7b385c7a88cc38729345f`，4/4 ARM64 native assets
  齐全，仍为 debug certificate 的 release 构建。
- 真机在已有 Root/DeepSeek session 中执行 `/exec /system/bin/id -u`，会话保持“就绪”，UI 显示
  `command/exec` 与退出码 `0`；输出为 `0`，进程表仍只有该 session 的单一 Codex/PRoot worker 链。
  最近 `800` 条 logcat 过滤未发现 `FATAL EXCEPTION`、`try_lock`、网络连接失败、模型缓存失败、
  权限错误或 `command/exec` 异常。

## 2026-09-28 command/exec PTY 协议原语

- `CodexSessionClient` 新增 PTY/流式命令的连接级 `writeCommandInput()` 和
  `resizeCommand()`，并允许 `executeCommand(..., tty: true)` 携带 `streamStdin`、初始行列数和已有
  `processId`；输入按 UTF-8 Base64 写入，不经过 shell。已有 `interrupt()` 继续复用同一
  `processId` 调用 `command/exec/terminate`。
- 新增协议级 fixture，验证一个 app-server 连接内的 `command/exec`、`outputDelta`、`write`、`resize`
  和 `terminate` 请求/响应，确认 PTY 命令不会派生第二个 Codex 进程；定向测试（session client、CLI
  参数、UI session）共 `87` 项全部通过。用户可见的交互式 PTY 面板、键盘输入绑定和 resize 事件尚未接入，
  因此本轮只标记协议客户端能力，不标记“完整终端”完成。
- Release APK 重新构建、校验并覆盖安装到实体设备 `6cb21282`，未清理 workspace/session/provider 数据：
  包 `io.henry.codex`，大小 `118,027,283` bytes，SHA-256
  `061cbfb8970dc90656b652a5aaf24aa50ffb3913015f14444d3e2d3d9a9e9220`，4/4 ARM64 native assets
  齐全，仍为 debug certificate 的 release 构建。
- 安装后真机首页仍显示原有两个 workspace、最近会话和 Codex 用量（`5h 65%, 1w 68%`）；
  首页状态与历史 session 条目存在，最近 `500` 条启动日志过滤未发现 `FATAL EXCEPTION`、
  `try_lock`、模型缓存失败、网络连接失败或权限错误。

## 2026-09-28 会话内交互式 PTY 面板真机验收

- 在上一节 Release 基础上接入 `/exec --tty <argv...>`：当前 session 中打开交互式命令面板，
  使用同一个 app-server 连接、workspace、Root/PRoot worker 和 permission profile；不会为
  PTY 命令另起 Codex app-server 或第二条 worker 链。
- 真机 `6cb21282` 覆盖安装本轮 Release 成功，应用数据保留。APK `io.henry.codex` 大小
  `118,066,979` bytes，SHA-256
  `0f3f014a952bd2da948b4f4a1a0025e8abb432fc6483a76d1dc65fe76317782b`；4/4 ARM64
  Codex/PRoot native assets 齐全，签名仍为本机 Android debug certificate 的 Release 构建。
- 在已有 Root/DeepSeek session 中真实打开 `/system/bin/sh` 面板。发送 stdin `id` 后收到
  `uid=0(root) gid=0(root) groups=0(root),3003,3009`；调整终端大小菜单显示并执行
  `80 × 24`、`120 × 40` 两个协议预设，面板保持可用。随后输入 `sleep 60` 并点击“中断”，
  面板显示 `退出码: 1` 并切换为“关闭”，关闭后原 session 回到“就绪”。
- 真机进程表在整个流程中保持单一 App + `libcodex_worker_guard.so` → `libcodex_proot.so`
  → `codex` worker 链。启动、面板、stdin、resize、interrupt 后，过滤的 app 日志没有发现
  `FATAL EXCEPTION`、`try_lock`、模型缓存失败、网络连接失败、权限错误或
  `command/exec` 异常。
- `codex_session_client_test.dart` 与 `local_session_conversation_test.dart` 本轮定向测试
  `67/67` 通过；此前协议 fixture 已覆盖同一连接内的 `command/exec`、`outputDelta`、`write`、
  `resize`、`terminate`。因此本项已从“仅协议原语”升级为“受限交互式 PTY 面板已实现并真机验证”，
  但完整 Codex CLI TUI、后台 job 浏览/恢复仍保留在未完成项。

## 2026-09-28 真机图片附件与第三方 provider turn 验收

- 在同一个 Root/DeepSeek session 中从真机 composer 打开系统文件选择器，选择相机图片；文件选择器
  能展示最近图片、勾选和确认，返回 App 后图片缩略图进入 composer，并保留“移除图片”动作。
- 选择 `9.52 MiB` 图片时，App 按当前附件合同明确提示 `Each image must be at most 8 MiB.`，
  没有把超限数据发送到 provider；换用 `3.29 MiB` 图片后附件保留并允许发送。
- 发送 `Reply IMAGE_ATTACHMENT_OK only` 后，当前第三方 Responses provider 完成真实 turn，
  assistant 返回精确的 `IMAGE_ATTACHMENT_OK`；会话从运行中回到“就绪”，上下文计数从约
  `in 5.0M / out 24.6k` 更新到 `in 5.2M / out 24.6k`，证明附件进入了真实请求而不是仅停留在本地预览。
- 设备 `6cb21282` 的 App 仍为 `io.henry.codex`，会话继续使用 Root、Deepseek Flash、低 effort、
  计划关闭；该次选择、发送与恢复没有清理 workspace/session/provider 数据。过滤的 App 日志没有
  发现崩溃、网络连接失败、模型缓存失败或权限错误。
- 本项只验证图片附件真实发送与大小边界；不同 provider/model 对图片内容的能力差异仍以实际协议
  和返回错误为准，不能因为 DeepSeek 本次通过就宣称所有 CLI 模型都支持视觉输入。

## 2026-09-28 普通真实 turn 中断收敛真机回归

- 修复 `turn/interrupt` 被客户端当作裸写入的问题。上游 app-server 会在 TurnAborted/终态之后
  返回这个 deferred RPC；客户端现在登记 pending request，立即展示“停止中”，由终态通知或成功的
  RPC 响应清理当前 turn。若兼容实现只返回 RPC 而不转发终态通知，也会回到 `idle`；请求超时则进入
  可见错误态，不会永久卡在 `interrupting`。
- 页面层不再在 `await client.interrupt()` 之后把已经收到的终态重新覆盖成 `interrupting`。
  测试 fixture 同步遵循真实协议顺序；`codex_session_client_test.dart` 与
  `local_session_conversation_test.dart` 定向回归共 `68/68` 通过。
- Release APK 已重新构建、校验并安装到实体设备 `6cb21282`，保留现有应用数据：包
  `io.henry.codex`，大小 `118,067,635` bytes，SHA-256
  `242853007a5f3409bfa919ff69d8ea696810cb853146110a2591b9ca01299359`；4/4 ARM64 native assets
  齐全，仍为本机 debug certificate 的 Release 构建。
- 真机在 Root/DeepSeek session 中发送真实长命令 turn，运行中点击“中断”后 5 秒内恢复为“就绪”，
  输入框重新可用；随后发送下一条真实 turn，返回 `AFTER_STOP_OK`，没有出现旧 turn 继续输出或
  session 被杀。设备进程表仍保持单一 App + Root/PRoot/Codex worker 链，未发现残留的 `sleep`
  进程；过滤 App 日志未发现崩溃、`try_lock`、网络失败或权限错误。
- 本项只修复普通 Codex turn 的停止状态收敛；PTY 面板的 stdin/terminate 仍按上一节独立验证，完整
  Codex CLI TUI 和后台 job 浏览/恢复仍是未完成项。

## 2026-09-28 CLI overlay 实际版本与更新语义复核

- 真机检查确认当前应用私有 overlay 的 `current` 符号链接指向
  `versions/0.157.1`，其 `bin/codex` 真实解析到该版本的 npm launcher；活动 Root/PRoot
  worker 的 app-server argv 也使用 `/home/codex/.codex-cli/current/bin/codex`。
- 在现有 Root/DeepSeek session 中执行 `/version`，UI 返回 `codex-cli 0.157.1`。此前看到的
  `0.154.0-linux-arm64` 来自显式调用 rootfs 的 `/usr/local/bin/codex`，不是当前 session 的
  Codex 入口；因此没有对已正确工作的 resolver 做无效改动。
- 设置页补充说明：CLI 更新只切换未来新 session 的入口，运行中的 worker 不会被静默替换；更新
  成功提示也显示这一点，避免把 overlay 版本和活动进程版本混为一谈。

## 2026-09-28 Release 覆盖安装后的工具链回归

- Release APK 校验通过并覆盖安装到实体设备 `6cb21282`，未清理已有 workspace、session 或
  provider 数据；本轮 APK 为 `118,068,267` bytes，SHA-256
  `dc4b839a75552bfd601fa399c9d872a7bb9e5f69299ea5cb80e443f197f53531`，4/4 ARM64 native
  assets 齐全。
- 重新打开既有 Root/DeepSeek session 后，session 恢复到“就绪”，历史和用量仍在；实际 `/version`
  返回 `codex-cli 0.157.1`。
- 同一 session 通过 `/exec` 实际执行并返回退出成功：`git version 2.39.5`、`node v24.19.0`、
  `npm 11.17.0`、`npx 11.17.0`、`Python 3.11.2`。这确认工具链经由当前 Root/PRoot app-server
  数据面可用，不是仅由 rootfs manifest 或静态状态推断。
- 覆盖安装后的启动日志未发现 App 崩溃、`try_lock`、模型缓存失败、网络连接失败或权限错误。

## 2026-09-28 应用重启后的 session 自动恢复

- 持久化历史记录新增 `SessionHistoryRecord.shouldAutoResume` 判定：只有具备稳定本地
  `sessionId`、Codex `threadId` 且最后状态不是用户明确写入的 `stopped` 时，才会在 App
  启动时自动重建 session entry；旧记录和没有稳定 session ID 的记录不会被误绑定到其他会话。
- Home 启动阶段现在按历史记录恢复对应 workspace/backend，并复用现有页面的自动 thread
  resume 流程。每条记录仍拥有独立的 `_LocalSessionRuntimeHandle`，不会把多个 session 合并
  到一个 client；用户返回 Home 只隐藏页面，不触发 stop。显式 Stop 仍会写入 `stopped`，因此
  不会在下次启动时被重新拉起。
- 定向 Flutter 回归通过：`session_history_test.dart`、`ccpocket_native_home_test.dart`、
  `local_session_conversation_test.dart`、`session_interaction_state_test.dart` 共 `56/56`。
  Dart analyze 能完成源码诊断；工程现有的 unused/lint 警告仍存在，Flutter analyzer 的 LSP
  服务另有既存 JSON 解析崩溃，但没有产生本轮新增的编译错误。
- Release 构建成功，APK `112.6 MB`，SHA-256
  `32C6342071BEE305DE269887580F7E47D9FD1C01597D92A812696053F913025F`；已用
  `adb install -r` 安装到实体设备 `6cb21282`，应用数据保留。
- 真机回归：覆盖安装后没有打开历史会话，Home 仍显示历史；其中一条保持 `ready` 的
  `test-project` session 自动启动了子进程 `libcodex.so`。随后再次执行“强制停止 App → 启动
  App”，等待 10 秒后设备侧观察到新的 App PID `21898` 及其子进程 `libcodex.so` PID `32645`，
  证明恢复不依赖用户再次点击历史卡片。
- 同时抽查设备历史索引：该条状态为 `ready`；其余近期记录为用户主动停止后的 `stopped`，
  没有被自动启动。本项完成了“App 重启后自动恢复非主动停止 session”的缺口；完整系统级
  后台保活、被系统低内存杀死期间的 turn 级精确续接仍需单独验证，不能由本次启动恢复等同推断。

## 2026-09-28 Root/PRoot 启动恢复竞态与真机复验

- 启动恢复不再只对 Linux/PRoot backend 做一次即时探测；现在使用总计约 3 秒的有限重试，
  覆盖 rootfs、PRoot 和 KernelSU worker 在 Android 冷启动时的正常启动窗口，同时不会让 Home
  无限等待不可用的兼容环境。失败时保留历史记录，等待用户后续显式打开或下一次启动重试。
- 定向回归 `session_history_test.dart` 与 `local_session_conversation_test.dart` 共 `44/44`
  通过；此前完整 session/UI 定向回归 `56/56` 也已通过。Google Fonts 下载失败仍只是测试环境
  的非致命告警，Flutter analyzer 的既存 LSP JSON 解析异常未被本轮改动触发。
- 最新 Release APK 构建成功并覆盖安装到实体设备 `6cb21282`，未清理应用数据；APK 大小
  `112.6 MB`，SHA-256
  `8D65F8E571BB56112FF4F18005E6874A099CBA4672AE98F7647ED081D7F80B10`。
- 真机新建 Root/DeepSeek session 后发送只读 `id` turn，UI 实际返回
  `uid=0(root) gid=0(root) groups=0(root),3003,3009`，并显示 KernelSU 上下文
  `u:r:ksu:s0`、`SELinux: Enforcing` 和上下文用量 `4%`。设备进程链为独立的
  `libcodex_worker_guard.so → libcodex_proot.so → codex`，均为 UID 0；同一页面完成后回到“就绪”。
- 随后执行“强制停止 App → 启动 App”，等待 15 秒后同时观察到本地 Android session 的
  `libcodex.so` 和该 Root/PRoot session 的 UID 0 worker 链，Root 历史自动恢复不依赖再次点击
  会话卡片。历史索引中该 Root 记录已保留 `threadId` 并进入可恢复状态。
- 设备上更早生成的两条 `linux-compatibility/disconnected` 记录没有 `threadId`，因此按合同被
  `shouldAutoResume` 跳过；它们没有可续接的 Codex thread，不能伪造绑定到新 session。这属于
  旧失败记录的数据完整性限制，不是当前 KernelSU profile 或 Root worker 启动失败。
- 随后在同一 `privacy-investigation` workspace 创建第二条 Root session；只在该新 session
  首次启动时出现一次 session 级 Root 授权，批准后真实执行 `id` 并回到“就绪”。此时设备同时
  存在两条独立的 UID 0 `libcodex_worker_guard.so → libcodex_proot.so → codex` 链，以及原有的
  本地 Android `libcodex.so` 链；第一条 Root session 未被停止，证明多 Root session 与本地
  session 可以并存，切换页面不会因为启动另一条 worker 而杀掉旧 worker。

## 2026-09-28 持久化断开记录的首页语义

- Home 现在区分实时 session snapshot 与持久化历史状态：实时 worker 仍按当前状态显示并按
  session ID 打开；历史中残留的 `disconnected`、`failed`、`error` 或 `exit` 只作为卡片状态
  展示，不再因为 `localStatus` 非空而被误判成仍在运行的进程。
- 点击这类旧记录会继续走 `onOpenHistory`，由正常的历史/恢复流程决定是否能够重新建立
  provider thread；不会调用活跃 session 回调，也不会凭空创建或绑定另一个 worker。没有
  `threadId` 的旧记录仍不可自动恢复，但可以被明确打开或删除。
- 新增 Home 回归用例验证“显示 Disconnected + 历史打开路径”，与 legacy/compatibility
  workspace 打开测试合计 `28/28` 通过。
- 本轮源码已成功构建 Release APK，大小 `118,069,007` bytes，SHA-256
  `425B0639F13BC585D3D95342136355265174AD2F98A97456D38CC2EA0696EFF6`。构建后主机的
  `adb devices -l` 暂无设备条目，因此本轮只完成源码/构建验证，尚未把该 APK 覆盖安装到真机。
- 随后将 CC Pocket HomeContent 的左滑删除条件与“是否仍有活跃 worker”分离：断开/失败的
  持久化历史卡片现在保留直接删除入口，运行中的卡片仍要求先显式停止。重新构建并通过 APK
  verifier：`118,070,043` bytes，SHA-256
  `D9AED71B2429DF017FE123985A08A8A3F37E3DB729A750AF8DF300CD23FBB82C`，4/4 ARM64 native
  asset present；ADB 仍无设备，未安装验证。
- 本轮随后执行 `flutter test --no-pub`，全量 Flutter 回归 `335/335` 通过；测试期间
  `google_fonts` 无法从网络下载字体，但没有造成测试失败。全量通过覆盖了 provider、模型
  目录、Root/session、图片、MCP、设置、本地化、并发会话和隐藏页面继续流式等已有路径。

## 2026-09-28 本地化回归与真机覆盖安装

- 将本轮新增的 Home 历史 workspace 缺失、删除历史失败、首个 workspace 不存在、运行中切换
  provider/执行身份等提示统一接入当前语言；中文仍显示原有中文文案，英文环境不再混入
  测试阶段中文提示。
- 修复局部 `_uiText` 调用冲突后，`flutter test --no-pub` 全量回归再次通过 `335/335`。
  `google_fonts` 的网络下载告警仍为测试环境非致命告警。
- Release APK 构建并通过校验：`118,070,479` bytes，SHA-256
  `54C525D4CE679B68DC58C2298741A8CB5BB322CBD16F2211E234540BC88F0024`，包名
  `io.henry.codex`，4/4 ARM64 Codex native assets present。
- 真机 `6cb21282` 恢复在线后，已用 `adb install -r` 覆盖安装并保留应用数据；启动后主进程
  `io.henry.codex` 正常运行，设备侧同时观察到 Root/PRoot 的两条
  `libcodex_worker_guard.so → libcodex_proot.so → codex` 链和本地 `libcodex.so` 链。
  本次安装没有进行数据清理，也没有观察到覆盖安装导致 worker 被终止。

## 2026-09-28 宿主命令工具环境补全

- 修复显式宿主命令和工具探测路径：当调用方没有传入环境时，Android 子进程现在自动使用
  app-private `codex-direct-home/host-command-home`，并提供独立可写的 `TMPDIR/TMP/TEMP`。
  这避免 Android shell 未设置 `HOME` 时 npm 把缓存退回到 `/.npm`，也让 git、node、python
  等依赖 HOME 的常规工具拥有正常用户态运行环境；调用方显式传入的 session 环境仍优先。
- 新增 JVM 回归覆盖空环境默认值、可写目录创建和显式环境优先级；`testDebugUnitTest
  --tests io.henry.codex.HostProcessEnvironmentTest` 通过。
- Release APK 重新构建并通过 verifier：`118,070,659` bytes，SHA-256
  `70974199BF75DDDFFF209AA390DBA3B898AE7B444C0AA17C8D7545BEE51E8C23`，4/4 ARM64
  Codex native assets present。
- 已覆盖安装到真机 `6cb21282` 并保留数据；启动后前台为 `io.henry.codex/.MainActivity`，
  设备侧仍同时存在两条 Root/PRoot `libcodex_worker_guard.so → libcodex_proot.so → codex`
  链和本地 `libcodex.so`。本项的 npm 网络依赖安装仍需通过 App 内真实宿主命令或 session
  做一次数据面验证，不能仅由 JVM 回归宣称完成。
- 覆盖安装后的设备 logcat 未发现 `FATAL EXCEPTION`、`try_lock`、模型缓存失败、网络连接
  失败或权限错误；这只证明启动/进程层健康，不替代 npm 网络安装和真实 turn 验收。
- 随后在真机现有 Root session 中发送只读请求“运行 `npm --version`”。真实 Codex turn
  产生了 `commandExecution`，返回 `11.17.0`，页面回到“就绪”，上下文用量从 4% 更新到
  5%；这确认 npm 已经能从真实 session 的 Android/PRoot 工具链中执行，不再是仅由设置页
  探针或 JVM mock 得出的结论。真实依赖下载/安装仍需单独验证，避免把版本命令等同于完整
  package install 能力。
- 同一真机 Root session 随后只读执行 `git/node/python/npx` 版本探针，真实 transcript 返回
  `git version 2.39.5`、`v24.19.0`、`Python 3.11.2`、`11.17.0`，页面回到“就绪”，工具
  计数显示为 5。至此五项基础工具均完成了真实 Codex commandExecution 验证；带真实依赖的
  npm install、npx 临时包下载仍保持为单独未完成项。

## 2026-09-28 真机 npm 依赖安装数据面验证

- 在同一实体设备 `6cb21282` 的 Root/PRoot Codex session 中真实发送 npm 依赖安装请求：
  `npm install is-number@7.0.0`，安装在临时目录内，未修改工作区项目文件。
- Codex transcript 实际返回 `added 1 package`；随后用设备侧 Node 加载该包，确认
  `require('is-number')` 返回函数、`package.json` 版本为 `7.0.0`，并完成行为校验：
  `isNumber(3) → true`、`isNumber("3") → true`、`isNumber("abc") → false`。
- 临时目录 `/tmp/codex-is-number-vEEPUw` 已由同一 turn 删除，页面回到“就绪”，上下文用量
  从 3% 增长到 5%，工具计数达到 5。该结果证明 npm 的真实网络下载、包解压、Node 加载和
  清理链路在当前 Root/PRoot runtime 中可用，不再只是版本探针或 JVM mock。
- 首次 Node 校验因嵌套引号被 shell 解析破坏而返回 SyntaxError；Codex 随后使用修正后的
  quoting 自动重试并完成验证。该问题不阻断依赖安装，但说明复杂嵌套 shell 字符串仍是
  当前 CLI/Android shell 兼容性边界，后续应优先通过脚本文件或更稳定的参数传递降低影响。

## 2026-09-28 真机 npx 临时包下载与执行数据面验证

- 在同一实体设备 Root/PRoot session 中真实执行 `npx --yes --cache <临时目录>/npm-cache
  cowsay "Hello from Codex"`；npm registry 下载并运行 `cowsay@1.6.0`，transcript 收到
  cowsay 输出，证明 npx 不仅能解析入口，还能完成临时包下载与执行。
- npx cache 和临时目录均放在本次 smoke 的临时路径内；Codex 随后用非递归强制删除方式完成
  清理，并确认默认 `~/.npm/_npx` 没有留下本次产物。Root/PRoot session 回到“就绪”。
- 这项验证覆盖当前 guest 的 npx registry、缓存目录、Node 执行和清理链路；不同包的原生扩展、
  postinstall 脚本以及长期缓存策略仍应按实际项目需要单独验证，不能由 `cowsay` 推断全部
  npm 生态兼容。

## 2026-09-28 Root 路线文档收敛与 CLI 命令回归

- `ROOT_ACCESS_POLICY.md` 的现行操作规则已与 2026-09-26 冻结路线及当前实现对齐：Root
  通过用户配置的普通 KernelSU `su` 获取真实 UID 0，不要求 `codex_agent` 域、固定组、
  capability mask、Linux `NoNewPrivs` 或通用 broker；启动链、raw-block 和 KernelSU 控制
  目标采用可见的软路由，具体授权后不被应用层永久封锁。此前的专用 profile/能力裁剪内容
  仍保留在历史快照中，但不再属于现行规则。
- 连接真机 `6cb21282` 的 Root session 内实际发送 `/cli --version`，返回
  `codex-cli 0.157.1`，页面保持“就绪”。这确认当前安装的官方 CLI 非交互命令入口能够从
  会话内返回结果；此前“CLI 命令无反应”的旧结论不适用于当前 APK/runtime。
- Flutter 定向回归通过：`root_access_policy_test.dart`、`codex_session_client_test.dart`、
  `session_history_test.dart` 共 `76/76`。覆盖 Root 软路由、真实 app-server 命令/PTY
  协议、模型目录/额度兼容、并发 session、自动标题、历史恢复、审批和中断竞态。
- 本轮没有修改 KernelSU profile、组、SELinux、boot 或任何设备文件，也没有重建 APK；设备上
  仍是上一轮已验证的 Release 包 `70974199BF75DDDFFF209AA390DBA3B898AE7B444C0AA17C8D7545BEE51E8C23`。

## 2026-09-28 Release 候选 UI 与旧工具链清理续记

- 清理宿主命令页中误导性的 Android 原生工具矩阵（bash/rg/python/git/node/npm/npx）；保留 App UID/Root
  宿主 argv 执行器，并明确说明开发工具属于 Debian/PRoot guest。删除对应的旧探测类与单测，补充
  页面文案回归，避免将 Android 宿主与 Linux guest 能力混为一谈。
- `PROJECT_DIRECTION.md`、CLI 兼容说明、Root policy、清理清单和本验收记录均更新为不再维护 Android ABI
  开发工具包；设置页仅显示 Linux/PRoot 与 Debian guest 路线。CC Pocket 的活跃 session、composer 和
  消息组件保留。
- Flutter 全量测试 `326/326` 通过；定向 Kotlin 测试 `CompatibilityCommandArgvTest`、
  `CodexSessionHomeTest`、`HostProcessEnvironmentTest` 通过。旧工具探测移除后 Release APK 重新构建及
  verifier 均通过：31,379,607 bytes，SHA-256
  `32B02CF9B28D61E8F4D8B02F3E3B7FD742747D33034442E53FBB9920EFDDE1E6`；四个 ARM64 PRoot/host 资产齐全，
  没有 `libcodex.so`、Root Read Broker 或 Android ABI 工具包；签名仍为本机 Android debug certificate。
- 候选 APK 安装到 x86_64 AVD，实看首页、session、设置、第三方模型页和 provider 表单。缺少 ARM64
  rootfs 时 session 明示“Linux 兼容运行环境尚未验证”并禁用发送；provider 表单只打开、未提交真实 key。
  候选页面截图见 `artifacts/ui-smoke/20260928-avd-candidate-*.png`。
- 实体设备 `6cb21282` 已连接。只读看到旧 APK 首页的真实额度和 session 数据，设置页可打开且未弹 Root
  approval；但旧 APK 仍显示已退役的 Bionic/ABI 入口。设备上仍有三条旧包 worker（两条 PRoot session 与
  一条本地 Bionic Codex）；没有覆盖安装或终止，候选包的真机 Root、turn、OAuth、provider 与帧时延验收
  因此未完成。待现有 worker 自然退出后再安装候选包续验。
- `tools/android-native-toolchain`（未跟踪旧目录，约 0.97 GiB）无活动代码/构建引用，已从仓库移至
  `C:\Users\Henry\AppData\Local\Temp\android-codex-obsolete-native-toolchain-20260928`。临时隔离目录
  尚未清空，因此本次完成了仓库移除但没有释放对应磁盘空间；带本地修改的 `vendor/codex-upstream-android-native`
  源码快照继续留在仓库中，不参与当前构建。

## 2026-09-28 模型弹层异步目录刷新与 provider 来源真机复测

- 复现冷启动模型选择缺陷：模型 picker 初始只显示当前模型，模型目录返回后已打开的嵌套 picker 保持旧快照；关闭并再次打开才出现完整目录。改为让 CC Pocket 子 picker 立即显示当前项/加载态，并订阅共享目录 future，完成后原地刷新；目录失败时给出状态文案。
- provider 配置与来源分离：父级“模型来源”在 OpenAI 订阅和第三方之间切换，第三方配置子页只存服务商/模型/key。实体机验证保存的 DeepSeek 显示“已配置、未启用”；临时切为第三方后再切回 OpenAI，OpenAI 被选中且 DeepSeek 仍保留。此切换未发网络请求、未使用 key。
- 新增/更新异步模型列表时序回归；`ccpocket_native_session_test.dart`、`custom_provider_settings_test.dart`、`codex_model_catalog_test.dart`、`local_session_conversation_test.dart` 共 `58/58` 通过，包含显式 OpenAI 覆盖历史第三方配置断言。
- 最新 Release 已覆盖安装至真机 `6cb21282`，APK `31,416,363` bytes，SHA-256 `5A8AAB29642E61A03C4FD6380CF1391445D21544BE9B0E661D713C35E35E77B6`；verifier 通过，ARM64 runtime assets 齐全，`flags=0x0`，应用数据和 session 历史保留。真机模型 picker 在约 `250ms` 检查点已显示完整 CLI 目录；本次窗口 4 帧、0 janky、p50/p95 `10ms`，由于样本极少不代表全局随机卡顿已解决。
- 最新 Release 再做 8 次连续开合，6 个不含截图/拉取开销的 tap-to-capture 样本为 `325–401ms`（包含固定 `220ms` 等待）；两端截图都显示完整目录。另一轮设备 `gfxinfo` 返回 0 帧/4950ms 哨兵，性能验收继续标记为局部通过、全局随机卡顿未结论。
- 关键截图见 `artifacts/ui-smoke/20260928-provider-performance/`；详细边界与菜单审查见 `UI_PERFORMANCE_ACCEPTANCE_2026-09-28.md`。对所有页面的随机卡顿、其他菜单子路径仍未完成全面帧级验收；后续需要扩大有效设备采样，不能以这一条 picker 通过宣称整体性能完成。
- 本轮停止的是由本轮测试启动的 idle Codex app/worker；未清除任何 workspace/session 数据，也未修改 KernelSU profile、groups 或其他设备权限设置。

## 2026-09-29 Provider 历史隔离、停止竞态与 Release 设备续验

- 修复手动 Stop 与异步退出清理/自动恢复之间的竞态：手动停止会使旧操作 generation 失效并取消 reconnect；迟到的退出回调不得重新启动 session。新增慢退出清理回归测试。
- 修复显式切换模型来源后错误恢复旧 provider rollout 的问题。跨 OpenAI/第三方时保留本地可见 transcript，但发送时在当前 provider 下新建 thread；明确告知服务端上下文不会跨 provider 自动迁移。第三方→OpenAI 真机真实 turn 返回 `chatbot_OPENAI_SWITCH_OK`；本轮稍早的 DeepSeek 真 turn 返回 `chatbot_DEEPSEEK_SWITCH_OK`。历史消息与提示均保留，当前来源不会被旧 session 偷偷覆盖。
- 定向回归：`local_session_conversation_test.dart` 30 项、`custom_provider_settings_test.dart` 5 项、`local_ui_navigation_test.dart` 4 项均通过。Dart analyzer 未报错误；仍有 17 条既有 warning/info，未扩展修理无关项。
- 当前安装的普通 Release APK 为 31,430,991 bytes，SHA-256 `6F5AE6809C6A7923C07E78B608813CE96373BFD78D00E251D49B0DBDEAAD4B08`；真机安装包 SHA 一致，`flags=0x0`，QA 本机签名。thread 模型面板及高级模型列表在 300ms 固定截图检查点可见，保留 `6 Luna / low`。菜单截图与帧统计边界记录在 `UI_PERFORMANCE_ACCEPTANCE_2026-09-28.md`。
- 测试后通过应用内 Stop 停止本轮 OpenAI marker session；确认 app 仍在前台、Codex app 进程之外无 worker guard/PRoot/Node/app-server。没有清除应用数据、历史 session 或 workspace，没有改动 KernelSU profile/groups。
- 仍未完成的整体工作：全局随机卡顿与首次首页滚动长尾尚未通过有效帧验收；冷启动/长 transcript/多页面性能还需采样定位；全部菜单子路径未穷举；旧 Bridge/旧 UI/旧 runtime 仓库清理未完成。本记录不把局部模型弹层响应宣称为整体性能完成。

## 2026-09-29 设置层级与 thread 控件真机续验

- 当前 Release 真机打开设置没有触发 Root approval。CODEX 设置显示新会话默认 `gpt-6-luna / low`、审批 `never`、完全访问；“模型来源”页把 OpenAI 订阅和 DeepSeek 服务商并列，当前选中 OpenAI；第三方配置子页仅编辑 provider，并明确显示 DeepSeek 已保存但请求仍使用 OpenAI。没有修改 provider/key。
- thread 内计划模式实机切换“关闭→开启→关闭”，状态即时变化并恢复原值。Root 写入策略菜单展示 Root 常规、完全访问、应用级只读及软路由文案；只读检查，没有选中其他权限级别。
- 打开一条手动停止的历史 thread 会因为用户明确选择该 thread 而恢复 Codex 进程，这是既有 `opens a saved session by automatically resuming its thread` 行为，不是 App 启动时的自动恢复；后者仍只恢复 `shouldAutoResume` 为真的记录。显式 Stop 后 UI 显示“已停止”，root worker、PRoot、Node、app-server 退出。该区分防止将预期的手动打开行为误改成禁止恢复。
- 当前模型保持 `6 Luna / low`。未触发新 turn、未调用第三方服务、未改 app data 或 KernelSU 设置。打开设置和子菜单时没有 Root 弹窗。

## 2026-09-29 Android 主线程进程启动冻结修复

- 真机冷启动复现模型菜单首开等待：250ms 截图检查点无弹层，约 5.25 秒后出现。根因不是菜单层级或 provider 网络请求，而是模型目录异步加载启动本地 Codex/PRoot 进程时，Android `MainActivity` 在 MethodChannel 回调中同步执行进程准备；PRoot 的 rootfs/session 环境准备阻塞 Activity 主线程，UI 无法及时绘制。
- 已将 `startProcess` 与 `startHostProcess` 中的进程准备和启动移到后台线程，成功/错误结果通过 `runOnUiThread` 返回；进程管理器和现有 session 生命周期语义保持不变。此次编译同时覆盖 Kotlin 与 Flutter Release。
- QA Release 真机复测：模型快捷弹层、Advanced 页、完整模型列表均在 250ms 固定截图检查点可见；完整目录含 `6 Astra/Sol/Luna`、`Reserve`、5.6、5.5。最终普通 Release 复测弹层可见，设置来源在真机上切换 OpenAI → 第三方 → OpenAI 后恢复正确，DeepSeek 配置仍保存且没有触发网络请求。测试保持模型 `6 Luna / low`。
- 普通 Release 设置菜单逐项实机选择并恢复：新会话 effort `low → medium → low`、审批 `never → failure → never`、沙盒 `full → workspace-writable → full`、主题 `system → light → system`、语言 `简体中文 → English → 简体中文`。UI 与持久化摘要均回到原值，没有提交新的会话或调用模型服务。
- Flutter 定向测试 `local_ui_navigation_test.dart` + `local_session_conversation_test.dart` `35/35` 通过，包含 provider 全局同步和历史第三方 thread 显式回到 OpenAI 路由用例。
- 普通 Release APK `31,432,083` bytes，SHA-256 `3CEFEF98D8A76A6758CBEAE5CC39F0BC2F73AB4F128F5EE38F638C038BE105DF`，verifier 确认签名有效与 ARM64 assets 齐全；`adb install -r` 安装到真机后 `flags=0x0`、`versionName=1.0.0`。归档于 `artifacts/release/android-codex-1.0.0-arm64-release-mainthread-fix-20260929.apk`。本机 QA debug certificate 仅是签名证书，不代表 Debug variant；该 Release APK不是商店签名包。
- 性能未整体验收通过：QA 帧采样的首个 120 帧窗口 `10/120` 超过 8ms、`3/120` 超过 32ms；设置页面交互采样也出现长帧，且与 ADB 自动化截图/层级抓取有重叠，不能归因到单一组件。后续仍需无截图干扰的首页、设置、长 transcript 与跨 session 测量，再按实测热点优化。
- 当前设备除前台 Android App 外没有 Codex worker、PRoot 或 app-server 进程。没有清除 session/workspace、没有清理 app data、没有改 KernelSU 配置。

## 2026-09-29 后台 I/O 与 workspace backend 路由修复

- 会话历史 JSON load/save/list 与宿主 filesystem/SAF channel 现在线程隔离到串行后台队列，降低大历史/慢存储调用卡住 Android UI 的概率；picker、前台服务与通知权限弹窗仍在 Activity 主线程调用，避免把 UI API 放到后台线程。
- 真机复现首页“添加”无反应发生在打开历史 session 后：Home 的 Add/Create/Delete 误以为当前 execution backend 一定是 Android 存储 backend；切到 Linux/PRoot workspace backend 时返回前就提前退出。现在通过 selector 独立解析 Android host backend；删除时将兼容层 workspace reference 还原为 host reference，再走既有确认/删除方法。添加入口在 QA Release 与最终普通 Release 都打开了 DocumentsUI。删除路径未做破坏性设备实测；没有删工作区。
- provider 来源回归继续通过：`36/36` 定向 Flutter tests，其中包含显式 OpenAI 覆盖历史第三方配置及 session source 改变后下条 turn 使用 OpenAI 的断言。真机 OpenAI → 第三方 → OpenAI 只改来源 UI 状态后恢复，未发送请求；当前最终选中仍是 OpenAI，DeepSeek 保留为配置项。
- 最终普通 Release artifact：`artifacts/release/android-codex-1.0.0-arm64-release-ui-performance-workspace-20260929.apk`，31,432,015 bytes，SHA-256 `DE85A9F76002CE42922591B79168FFD3CF19CF68BA9611EEC8CD2FDD4AF6A340`；APK verifier 确认包名/版本、签名有效及所需 ARM64 PRoot/host assets；`flags=0x0`。已覆盖安装至真机，设备 APK hash 一致，原有工作区/session 数据仍可见。证书是本机 QA debug certificate，但 variant 是 Release，不是商店签名包。
- 普通 Release thread 模型弹层在 250ms 截图检查点可见；Android 系统 picker 打开后按返回取消，没有授予新的目录。工作区总菜单/单卡菜单及删除确认层级已真机打开检查；删除确认按返回取消，未删文件。
- 不截屏帧采样：首页首个滚动窗口 `5/120` 帧超过 32ms，p99 total `71.378ms`；紧接的两个首页窗口没有 >16ms 帧。设置两窗口各有 `3/120`、`1/120` 帧超过 16ms，没有 >32ms。首页长尾落在 raster/vsync，设置窗口 build p99 约 `8.9–11.0ms`。因此模型弹层与暖机滚动局部通过，但首轮首页和全局随机卡顿仍未解决/验收。
- 设备上只有前台 `io.henry.codex` App 进程，没有由本轮运行遗留的 Codex worker、PRoot 或 app-server。未删除用户数据、session、workspace，也未改 KernelSU profile。整体性能/UI 验收和旧 Bridge/旧 UI/旧 runtime 清理继续保持未完成。

## 2026-09-29 模型目录响应、provider 菜单和 Release 帧采样

- 模型目录现在有按 CLI 版本/runtime 标识区分的持久 metadata cache，不含任何凭据；缓存命中时 thread 模型菜单不需要启动 PRoot。定向测试 `codex_model_catalog_cache_test.dart`、`custom_provider_settings_test.dart`、`local_ui_navigation_test.dart` 共 `14/14` 通过。
- 来源设置重排为“模型提供方”父层，OpenAI 与第三方并列；第三方配置位于其来源卡片下层，并注明只编辑配置、不切换当前来源。真机 provider 子页显示 DeepSeek 已配置但未启用、OpenAI 当前生效。对历史 DeepSeek thread 切回 OpenAI 后发送真实 marker turn，进程参数确认为 `model_provider=android_openai_http`，回复 `OPENAIAFTERSWITCHOK`；本轮未复现路由仍留在第三方的问题。
- 普通 Release 固定 250ms 检查点显示完整缓存模型目录，即使当前没有 PRoot、Node、Codex worker 或 app-server。QA Release 的 thread 冷路径目录也在 250ms 检查点显示。无 worker 缓存截图与设置层级截图记在 `artifacts/ui-smoke/20260929-perf-followup/`。
- QA Release 帧日志：首页滚动 720 帧中 14 帧 >8ms、4 帧 >16ms、3 帧 >32ms；首个 120 帧 p99 48.292ms，后续暖机窗口无 >16ms。设置滚动 720 帧中 28 帧 >8ms、1 帧 >16ms、无 >32ms；thread 模型目录 120 帧中 12 帧 >8ms、1 帧 >16ms、无 >32ms。模型弹层五秒冻结已解决；首页冷/首轮长尾与全局随机卡顿仍未完成优化/验收。
- QA instrumentation variant 是 Release（`flags=0x0`）；测试后恢复并覆盖安装普通 Release `artifacts/release/android-codex-1.0.0-arm64-release-model-catalog-provider-menu-20260929.apk`（31,443,615 bytes），SHA-256 `BC81A3A9A4B2482F85CC17FB3F699B6BD637F86A2E6232AB972152AC11277903`。`run-as` 确认安装包 non-debuggable。测试启动的 thread worker 已由应用内“停止会话”停止，ADB 进程检查仅剩 Android App；没有删除 session/workspace 或清除 app data。
- 当前 UI 菜单验收仍是局部覆盖，不宣称全 app 菜单完成；旧 Bridge/旧 UI/旧 runtime 清理及其余页面/交互验收继续未完成，overall goal 保持 active。

## 2026-09-29 Thread 卡顿与来源菜单续修

- 修复两项可定位的 UI 阻塞来源：模型/计划/Root 控件上方的账号额度与 context 摘要现在使用固定高度槽位，避免异步 usage 更新推移 controls；Android `stopProcess` / `stopHostProcess` 在后台执行，避免进程停止与来源切换占用主线程。
- 验证：`local_session_conversation_test.dart` 30/30（含 usage 事件前后模型控件位置不变）；provider/navigation tests 10/10；模型目录加载用例 1/1。普通 Release 真机模型目录 250ms 检查点可见，provider 菜单切换响应，测试 worker 退出后无残留。几何稳定性有 widget 回归覆盖；本轮真机旧 thread 未产生新的 usage 事件，因此设备侧 usage 到达后的布局尚非独立设备验收。
- 菜单结构为 CODEX → 模型来源（OpenAI / 第三方并列）→ 第三方配置子页；真机切回 OpenAI 并重启后仍选中 OpenAI，DeepSeek 只保留为已保存配置。未调用第三方 API，也未读取或打印 key。
- 已生成并安装普通不可调试 Release：`artifacts/release/android-codex-1.0.0-arm64-release-stable-thread-controls-20260929.apk`，31,444,371 bytes，SHA-256 `FC49429CBFF3E06838ECA13C4EE8CA0DA4CBA209F611ECC229C77772A324E68`；设备 hash 一致、`flags=0x0`、non-debuggable，应用数据 inode 未变。本机 QA certificate 签名，不是商店签名。
- 开发测试 spawn 的 Codex worker 已停止；没有删除 session/workspace 或清理 app data。剩余：全局随机卡顿的有效帧验收、冷启动/长 transcript/composer 与其余菜单逐项检查、旧 Bridge/旧 UI/旧 runtime 清理。局部修复与 Release 安装不代表总体目标完成，goal 保持 active。

## 2026-09-29 最新 Release 首轮滚动长尾复测

- 普通 Release 的最新布局改动后，临时安装帧计时 QA Release，在真机完成 6 组首页上下滚动、共 13 个 120 帧窗口；无截图干扰。首个滚动窗口 total p99 `72.024ms`，`3/120` 帧 >32ms；分项 build/raster/vsync p99 `7.130/14.872/37.190ms`。后续 12 个窗口全部无 >16ms 帧，total p99 最高 `8.967ms`。结论：首轮 jank 仍存在且不是单纯 Flutter build 过慢，raster/vsync 是当前证据指向的调查面，根因仍未确定。
- QA 包是 Release variant（`flags=0x0`），31,453,391 bytes，SHA-256 `4DFB9EED9CA9FCDA3A2E4F5640B7554BDFF2648B15C00AC089342F42C2F52B32`；测试后已恢复普通 Release `android-codex-1.0.0-arm64-release-stable-thread-controls-20260929.apk`，设备与归档 hash 一致，data inode 未变。Codex 留在前台，只剩 App 进程，测试 worker 均已退出。
- 下一步继续定位首轮 raster/vsync 长尾与长 transcript 渲染成本，再逐项完成剩余页面/菜单验收；目前性能优化和 UI 验收都没有整体完成，旧 Bridge/旧 UI/旧 runtime 清理仍待后续阶段。

## 2026-09-29 真机菜单层级复核与首页卡片遮挡修复

- 运行 Release 真机菜单审查，覆盖模型来源父子层级、第三方/OpenAI 往返、thread 模型/计划/Root 控件、thread overflow、workspace 全局与单卡菜单、项目筛选。证据截图及步骤记录：`artifacts/ui-audit/20260929-menu-hierarchy/REPORT.md`。来源父子层级合理，第三方只编辑配置；模型、计划、Root 的 tap targets 可用，计划可开关，Root 策略未被意外改变。没有发 API 请求。
- 真实 usage 更新前后 top controls 的 Android semantic bounds 相同；模型弹层在固定 250ms 截图点出现。注意：该检查是设备 UI 响应样本，不是完整动画时长/全局无卡顿证明。
- Home 滚到底时最后一张 session card 与“新建”FAB 有实际像素重叠。为共享 CC Pocket `HomeContent` 新增可选 `bottomContentInset`，仅 Codex host 传 `88dp`，使最后一张卡可以滚到 FAB 上方。`ccpocket_native_home_test.dart` 8/8 通过，Release 真机滚动到底复验通过。
- 新普通 Release `artifacts/release/android-codex-1.0.0-arm64-release-home-scroll-inset-20260929.apk`：31,447,367 bytes，SHA-256 `2DFAF878CF0214CEB28095A9D00FB0C75ED244A8031B32466A52B4FA1494318A`；APK verifier 通过，已覆盖安装到真机，device hash 一致、`flags=0x0`，package non-debuggable，数据 inode 未变。
- 开发 audit 打开的本地测试 session 已通过 App 内 Stop 停止，确认无 worker/PRoot/Node/app-server；仅保留 App 前台与 session 历史。总体待办仍包括首轮 raster/vsync 长尾、composer/设置剩余菜单的完整验收，以及旧 Bridge/旧 UI/旧 runtime 清理；goal 保持 active。

## 2026-09-29 模型入口直达与 composer 菜单续验

- 将 thread 模型 chip 的首开状态设为 CC Pocket `CodexSettingsSheet` 的 advanced 面板：模型行直接可见，去掉“快捷 effort 面板 → 高级 → 模型”的隐藏层。该设置是可选参数，CC Pocket 其他调用仍保持原默认行为。冷目录测试验证弹层和模型行不等待目录 future；选择模型行后目录继续异步填充。
- 定向 Flutter 回归 `ccpocket_native_session_test.dart`、`custom_provider_settings_test.dart`、`local_ui_navigation_test.dart`、`local_session_conversation_test.dart` 共 `64/64` 通过，覆盖冷目录呈现、OpenAI/第三方来源切换、所有已打开 session 更新和历史第三方 session 显式切换后下一条 turn 走 OpenAI。
- 新普通 Release `artifacts/release/android-codex-1.0.0-arm64-release-thread-model-entry-20260929.apk`，31,447,939 bytes，SHA-256 `C36AFCEE924AECADECAEA6B97D382973A800D27CF46BACD6C815D48695BA46B9`；APK verifier 检查签名和 ARM64 runtime assets 通过。真机覆盖安装后拉回设备 APK 比对 hash 相同，`flags=0x0`、`run-as` 返回 `package not debuggable`，未清除应用数据。
- 真机模型 chip 首次弹层在 tap 后固定 250ms 检查点可见，首屏包含“模型”行；第二步模型目录能显示 `6 Astra/Sol/Luna`、5.6 与 5.5 系列。本轮没有复现 5 秒级模型弹层停顿；这只是局部交互证据，不能据此宣称全局随机卡顿已解决。
- Release 菜单审查追加覆盖 slash 命令说明、`@` 插入、提示词历史只回填、图片入口切入 Android picker。未触发 `/clear`、未选取照片/文件、未发起新模型请求。报告与截图位于 `artifacts/ui-audit/20260929-provider-switch/REPORT.md`。
- 本轮 `Inspect IDIDID` 为开发测试 session：通过 App 内 Stop 终止其 Codex/Node/PRoot worker，设备仅剩 Android App 进程；历史保留、测试时插入的单字符草稿已移除。没有清除 workspace/session 或改动 KernelSU。
- 未完成：首屏滚动 raster/vsync 长尾和全局随机 jank、长 transcript/冷启动的持续帧级采样、所有设置子项与图片真实上传验收、旧 Bridge/旧 UI/旧 runtime 清理。总体 goal 继续 active。

## 2026-09-29 模型目录按需读取与 Release 烟测

- 将 OpenAI CLI 模型目录加载从会话模型设置的首层弹层延迟到用户实际展开模型列表之后；目录返回时回写模型描述符，避免新模型因缺少能力信息而回退到 `none` 推理档。测试中先发现并修复了该能力状态同步问题。
- 定向验证：`ccpocket_native_session_test.dart` 24/24、`custom_provider_settings_test.dart` 5/5、`local_session_conversation_test.dart --plain-name provider` 9/9。OpenAI/第三方互斥和配置层级测试通过；当前层级为“模型来源（OpenAI / 第三方）→ 第三方配置”。
- 普通 Release 产物 `artifacts/release/android-codex-1.0.0-arm64-release-model-picker-lazy-20260929.apk`，31,446,135 bytes，SHA-256 `65D4A3F8DC7B64C3F345E139958CEE7D0734711BB0AFE1EA08EEB5E71AE268AC`；APK 签名和 ARM64 runtime assets 校验通过，`flags=0x0`（不可调试）。已安装到唯一在线设备 `emulator-5651`，设备 APK hash 完全一致。
- 模拟器 thread UI 中首层设置弹层约 350ms 检查点可见，展开模型列表后显示当前模型及 runtime 未验证提示。物理手机未连接，本轮不将模拟器渲染表现当作真机性能结论；没有真实模型 turn、没有清除数据，最终无 Codex worker/PRoot/Node/app-server 残留。
- 尚未解决：全局随机长帧根因和首轮 raster/vsync 长尾；真机复验、剩余 UI/交互验收，以及按当前路线最后清理旧 Bridge/旧 UI/旧 runtime 均继续待办。Goal 保持 active。

## 2026-09-29 首页菜单本地化与重命名弹窗修复

- 将最近会话长按菜单、重命名弹窗、首页读取错误/重试、设置说明确认按钮和无详情模型目录错误文案补齐英语显示，减少界面切换语言后遗留的中文。
- 英文 Widget 测试捕获到 rename dialog controller 在退出动画结束前被 dispose 的异常；将 `TextEditingController` 所有权移入弹窗 `State`，在真正卸载时释放。
- 验证：`ccpocket_native_home_test.dart` 10/10，`network_proxy_settings_test.dart` 2/2。当前覆盖英文菜单呈现、重命名真实回调、错误重试，以及设置说明弹窗。
- 普通 Release `artifacts/release/android-codex-1.0.0-arm64-release-home-menu-localization-20260929.apk`，31,451,127 bytes，SHA-256 `547345DFB937D56FE3026040A625787A5BB5C677A199C73AC0C0B3A81E341ABD`；APK verifier 确认签名与 ARM64 Codex assets 正常，包 `flags=0x0`。覆盖安装到唯一在线设备 `emulator-5651` 后，device APK hash 相同，首页正常启动且原 workspace/session 仍可见。
- 未启动任何 session worker；当前物理手机未出现在 ADB。全局随机卡顿、真机和其余交互验收、最后的旧 Bridge/旧 UI/旧 runtime 清理仍未完成，goal 保持 active。

### 2026-09-29 provider 启动恢复竞态与 Release 模型弹层复核

- 修复启动时 provider 偏好异步恢复覆盖用户刚选择来源的竞态：并发读取互相独立的偏好项；显式切换递增 revision，旧恢复结果不再写回；打开来源页前先完成初始恢复，返回后再刷新持久状态。选择 OpenAI 时保留第三方配置，但当前请求来源与 session provider 均切回 OpenAI。
- 新增延迟启动恢复回归用例，覆盖“恢复仍在等待时切回 OpenAI、随后打开新 session”的状态；`local_ui_navigation_test.dart`、`ccpocket_native_session_test.dart`、`custom_provider_settings_test.dart`、`local_session_conversation_test.dart` 定向套件共 `66/66` 通过。
- 普通 Release：[`android-codex-1.0.0-arm64-release-provider-source-race-20260929.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-provider-source-race-20260929.apk)，31,452,863 bytes，SHA-256 `66D2DE3784733D57B6C403C477274E75F95026E343944F8AE41120C083BBCA01`。APK 签名和 ARM64 runtime assets 验证通过；设备包 `versionName=1.0.0`、`flags=0x0`，`run-as` 确认 non-debuggable。使用本机测试证书签名，不是商店签名。
- 已安装在唯一在线设备 `emulator-5651`；设备内 `base.apk` SHA-256 与归档产物一致。thread 模型首层弹层、模型列表分别在固定 `250ms` 检查点可见；软键盘打开时弹层也能出现。截图和边界记录见 [`20260929-model-popup-release`](../../artifacts/ui-smoke/20260929-model-popup-release/REPORT.md)。模拟器没有已验证的 ARM64 Linux/PRoot 模型目录运行环境，因此本轮不宣称动态 CLI 模型目录或真实 turn 已在该模拟器验证。
- UI smoke 检查时仅有 Android App 主进程；按用户要求，本轮最后已 force-stop 我启动的空闲 App。当前没有 App、Codex worker、PRoot、Node 或 app-server 进程；没有活动 session 需要停止，也没有删历史/工作区或清除 App 数据。本轮未发真实模型请求。
- 菜单父子关系保持为“模型来源（OpenAI / 第三方并列）→ 第三方服务商配置”；现有真机菜单报告已覆盖 thread 模型/effort/plan/Root、session/workspace/project 主菜单。全部设置子项、系统 picker 的真实图片上传和所有 slash 命令实际执行仍未逐项验收，菜单总体审查不标记完成。
- 性能结论不变：模型弹层局部等待已由按需加载和异步读取消除；模拟器 `250ms` 烟测不代表真机帧时。真机当前未出现在 ADB，首轮 raster/vsync 长尾与全局随机卡顿仍未定位。性能优化、全面 UI 验收和旧 Bridge/旧 UI/旧 runtime 清理均未完成，goal 保持 active。

### 2026-09-29 CLI updater 逻辑续验

- 重新核对当前 `CodexCliUpdater`：查询官方 npm registry 版本，在 app-private PRoot guest 的版本化 prefix 暂存 CLI，运行暂存二进制核对版本后原子切换 `current` launcher；升级或激活校验失败会恢复旧链接，已有 worker 不被 updater 重启。
- 当前工具链 staging 路径下重跑 `codex_cli_updater_test.dart` `10/10`、`settings_model_catalog_test.dart` `7/7` 通过。覆盖版本排序、升级暂存、模型刷新、launcher 激活失败回滚、无旧版/回退到 rootfs 等路径。
- 这是主机端 fake-backend/widget 回归，不是本轮手机上的实际 npm 下载升级。当前 ADB 仍只有 x86_64 emulator、没有可用 PRoot/rootfs；最新实体设备 updater 下载、CLI 版本切换和新模型目录刷新仍需真机验证。未触发网络包下载、未启动 Codex worker，也未重新构建 APK。

### 2026-09-29 正常 KernelSU Root 身份门槛 JVM 复验

- 对 Android Root 识别和启动脚本只运行 JVM 单测：`RootProfileProbeTest` `22/22`、`CompatibilityRootLaunchScriptTest` `8/8`，Gradle XML 结果均为 0 failures/errors。覆盖 `u:r:ksu:s0`、额外/缺少组、广泛 capabilities、boot/block 写样本仍为诊断，以及 UID 0 才允许 Root PRoot 启动。
- 该命令为 `testDebugUnitTest` JVM 测试任务；没有生成、安装或启动 Debug APK，也未调用手机 `su` 或改 KernelSU 配置。它验证的是当前源码门槛，不替代真机 UID/context/file-visibility 的运行时验证。
- 设备状态没有变化：当前只有 x86_64 emulator，Root Profile 实机与全局性能实测仍待手机在线。整体 Goal 保持 active。

### 2026-09-30 旧路线与死代码清理

- 按当前 PROJECT_DIRECTION 移除旧 Firebase/FCM Bridge relay、商店 JWT/Git
  演示脚本、失效 agent skills 链接、旧 macOS/iOS execpolicy、重复 UI 状态文件。
- 无调用的 RootProbe、同步 native Root 探测、旧设置额度动画组件、旧 delta
  拼接/单 session 转发/备份恢复函数及无读者状态已删除。Root profile 的不可达
  分支已去除；当前 PRoot、宿主文件功能和模块安装实现保留。
- 旧 Bionic fork（带本地补丁及约 73.52 GB 构建缓存）、Kotlin MVP、无调用的
  桌面迁移脚本及旧 MVP 架构计划已移出活动仓库，恢复位置和保留理由见
  [清理记录](REPOSITORY_CLEANUP_2026-09-30.md)。移动不释放磁盘空间。
- 删除死代码后 60/60 Flutter 回归通过；Release Kotlin 编译、22/22 Root profile
  JVM 单测通过。改动文件没有 analyzer error 或 unused 项；既有 lint 未全量修复。
  本轮未打包/安装 APK，未触碰手机数据或 KernelSU 设置。

### 2026-09-29 Release 真机：流式更新、模型入口与来源切换

- 针对长回复流式渲染路径，将逐 token 的整段字符串复制改为 `StringBuffer` 累积，并通过帧回调合并可见快照更新；当前以 `local_session_conversation_test.dart` 31/31、四个相关套件合计 `66/66` 覆盖回归。此为热点优化，不等于所有随机卡顿已解决。
- 普通 Release 包 `artifacts/release/android-codex-1.0.0-arm64-release-stream-buffer-20260929.apk`，31,452,291 bytes，SHA-256 `D6DA8EAABE8C9C2B793D4DD5EB7E372DA32ED5B43CD693E4953CD516FAD67D2F`；APK verifier 签名与 ARM64 runtime assets 校验通过。覆盖安装至实体机 `24031PN0DC` 并校验设备包 hash 一致，`run-as` 确认为 non-debuggable；保留原 App 数据。
- 真机 Release 上 thread 模型设置弹层在 250ms 检查点可见；模型目录显示 6 Astra/Sol/Luna、5.6 系列与 5.5。设置页验证“模型来源 → OpenAI / 第三方并列 → 第三方服务商配置”层级；第三方选择状态确实变为“当前启用”，再切回 OpenAI 后为“已配置，未启用”。手机侧未发送模型请求、未触碰 API key。截图与记录见 [`20260929-live-flow-performance-provider`](../../artifacts/ui-audit/20260929-live-flow-performance-provider/REPORT.md)。
- `dumpsys gfxinfo` 的本轮进程累计数据为 80 帧、2 janky（2.50%）、99th percentile 42ms。采样范围有限且非受控 benchmark，因此仍将用户报告的全局随机卡顿列为未解决，不把局部弹层通过当成性能验收完成。
- 检查时发现一个既有 QA thread 的 worker（Root guard → PRoot → Node → Codex），经 App 内停止按钮结束；事后设备仅剩 App 主进程。未清理历史、workspace 或 session，未更改 KernelSU。
- 未完成：全局随机卡顿与长 transcript/持续流式压力测试、所有设置/菜单/图片上传与命令交互的系统验收、设备侧真实 provider turn、最终旧 Bridge/旧 UI/旧 runtime 清理。Goal 保持 active。

## 2026-10-01 历史 transcript 本地化投影保持原文

- 修复历史恢复路径把 `localizeCodexTranscriptEntry` 的显示结果写回 `_transcript` 的问题。恢复后的 transcript 现在保留原始 JSON/旧版文本行，CC Pocket 消息列表只在渲染时做本地化；后续草稿、usage 或生命周期持久化不会把中文/日文显示文案反写进历史，也允许切换语言后重新投影原始内容。
- 在冷恢复回归中加入中文 locale 和 `System: MCP request accepted.` 原文，验证持久化记录仍包含英文源行且不包含 `System: MCP 请求已接受。` 显示行。
- 验证：ASCII junction 下 `local_session_conversation_test.dart` `34/34`；`ccpocket_native_session_test.dart` 与 `codex_runtime_error_localization_test.dart` 合计 `34/34`；`flutter analyze --no-pub lib/main.dart test/local_session_conversation_test.dart` 无 error，保留当前文件已有的 11 条 warning/info。
- 本轮未重新构建或安装 APK，未触碰实体设备、KernelSU、活跃 Codex worker；Release 性能/首轮 raster-vsync 长尾、完整真机 UI 菜单验收和其余总体 Goal 缺口仍未完成，Goal 保持 active。

## 2026-10-01 流式消息局部重建与长 transcript 缓存

- 将本地会话的 assistant/reasoning 流式快照从页面级 `setState` 拆到 `CcpocketNativeStreamingSnapshot` `ValueNotifier`。高频 delta 现在只重建 CC Pocket 消息列表；app bar、模式栏、composer 和保留的其他 `IndexedStack` session 仍只在状态、工具、审批或 turn 生命周期事件变化时重建。普通事件的页面刷新语义保持不变。
- 将消息投影缓存键从“本地化后的显示文本”改为原始 transcript 行；同一可见历史在持续输出期间不再重复执行本地化/JSON 投影，不同原文也不会因显示文本相同而错误共享 `ChatEntry`。locale 变化仍会清空展示缓存。
- 为 Home 摘要的最后可见 transcript 行增加按原始行复用的 memo，避免每个流式帧发布摘要时重新解析上一条长 JSON assistant 记录。
- 新增回归：验证流式快照更新不重建模式栏，以及本地化投影按源行缓存。验证：ASCII junction 下 `ccpocket_native_session_test.dart` `33/33`；`local_session_conversation_test.dart`、`ccpocket_native_home_test.dart`、`codex_runtime_error_localization_test.dart` 合计 `49/49`；`flutter analyze --no-pub lib/main.dart test/local_session_conversation_test.dart` 无 analyzer error，仍保留当前主文件已有的 11 条 warning/info。
- 本轮没有重新构建或安装 APK，没有触碰实体设备、KernelSU 或活跃 Codex worker；首轮真机 raster/vsync 长尾是否下降、长 transcript 真机滚动及持续真实 token stream 仍需 Release 帧采样验证。模型/provider/session 切换未发现需要同步重建的新增具体根因，现有 provider 停止/重建路径保持不变；总体 Goal 继续 active。

## 2026-10-01 CLI 更新后的现有 session 模型目录失效修复

- 定位到具体生命周期缺口：Home shell 为减少 IndexedStack 重建而复用同一个 `LocalSessionPage` widget 实例，CLI updater/rollback 更新 `_activeCompatibilityCliVersion` 后，已有 session 不会触发 `LocalSessionPage.didUpdateWidget`，因此继续持有旧 CLI 版本的 `_modelCatalogFuture`。
- 为 `_LocalSessionEntry` 记录 page 使用的 CLI 版本；只有版本变化时才用同一个 `GlobalKey` 创建新的 `LocalSessionPage` widget。State/运行中的 session worker 保持不变，但 `didUpdateWidget` 能按既有逻辑丢弃旧模型目录 Future，下一次打开模型选择器读取新版本目录。
- 新增 Home 集成回归：先加载 `0.154.0` 的旧缓存，再把现有 Home session 更新到 `0.155.0`，确认第二次读取得到新模型而不是旧 Future。定向验证：该回归 `1/1`；`codex_cli_updater_test.dart` 与 `codex_model_catalog_cache_test.dart` 合计 `17/17`；`flutter analyze --no-pub lib/main.dart test/local_session_conversation_test.dart` 无 error，保留已有 11 条 warning/info。
- 本轮未重新构建或安装 APK；上一份 Release 产物不包含本轮 follow-up 修改。未触碰真机、KernelSU 或活跃 worker；真实手机上的 CLI 下载/激活、app-server 新模型目录和 provider turn 仍未验证，session/provider 切换的设备侧生命周期行为仍需后续真机验收。

## 2026-10-01 性能修复 Release 产物交付

- 使用 `tools/build-android.ps1 -Mode release` 成功构建最新 Release APK：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，大小 `31,487,739` bytes，SHA-256 `DBE09227F762E6BC7C70622AB40695B89CD80802DD35D93F45C17F09F55A2BA3`。
- 使用 `tools/verify-android-apk.ps1 -RequireCodexNativeAssets` 只读校验通过：包名 `io.henry.codex`、version `1.0.0`、签名校验通过；四个独立 ARM64 assets 均存在（`libcodex_proot.so`、`libcodex_proot_loader.so`、`libcodex_host_trampoline.so`、`libcodex_worker_guard.so`），缺失项和旧 Bridge/Bionic 禁止 assets 均为 0。
- Manifest 没有 `android:debuggable` 属性，判定为 non-debuggable；当前使用本机 Android debug certificate 签名，不能作为商店 release signing 证明。
- 本轮未安装 APK、未连接或操作真机、未停止/重启活跃 Codex worker；仍未完成设备侧首轮 raster/vsync、长 transcript 和真实持续 token stream 帧采样，当前 Release 产物仅完成主机侧构建与静态校验。

## 2026-10-01 性能与 CLI 更新修复后的直接回归

- 主机侧重新运行 CLI updater/model cache、session/provider、Root 路径、长 transcript 和 CC Pocket 流式 UI 相关定向测试：`83/83` 全部通过。
- 重新构建当前工作树 Release APK：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，大小 `31,488,199` bytes，SHA-256 `96480181B1BC115A3041AB6ED936CF364CBEC7BD44511E2339374DBF91B4BD99`。
- APK verifier 通过：包名 `io.henry.codex`、版本 `1.0.0`、non-debuggable、四个 ARM64 Codex native assets 齐全，旧 Bridge/Bionic assets 缺失；签名仍为本机 Android debug certificate，不代表商店签名。
- 本轮未安装 APK、未重启或停止真机上的 root Codex worker。首轮 raster/vsync、长 transcript 持续真实 token stream、CLI 更新后的设备侧 app-server 模型目录和 provider turn 仍需在 worker 可安全切换时做真机验收。

## 2026-10-01 Release 真机安装与真实 turn 验收

- 在确认旧 worker 由本项目创建并获得中断授权后，执行 `am force-stop io.henry.codex`，确认旧 PRoot/Codex/worker guard 进程全部退出；保留应用数据后覆盖安装当前 Release APK并启动 `io.henry.codex/.MainActivity`。
- 真机 UI smoke check 通过：工作区、多个 session、最近会话、中文控件、用量显示、上下文进度环、模型/计划/Root 控件、图片入口、命令入口和历史消息均可见；会话状态显示 `Linux Compatibility (PRoot)` + `Codex app-server`，实际 CLI 版本显示 `codex-cli 0.159.2`。
- 真实 turn 通过：发送 `FRESH_RELEASE_TURN_OK` 后收到相同的最终 assistant 回复，状态从“运行中”回到“就绪”；上下文使用量从 `12%` 更新到 `15%`，输入/输出用量同步更新。
- 模型选择弹层在约 800ms 内可见，动态目录包含 `6 Astra`、`6.1 Sol`、`6 Sol`、`6 Luna`、`5.6 Sol`、`5.6 Terra`、`5.6 Luna` 及其他当前 CLI 模型；没有出现 `failed to load models cache`。
- `dumpsys gfxinfo io.henry.codex` 本轮累计采样：251 帧、2 个 janky frame（0.80%）、90/95 分位 10ms、99 分位 113ms、2 次 Missed Vsync。该结果证明本轮 Release 基本渲染链路可用，但不替代长时压力测试。
- 本轮未清除 workspace/session 数据，未修改 KernelSU 配置；停止旧 worker 是经用户明确授权的可逆测试操作。provider 实际切换、图片真实上传、并行 session 长时运行和 CLI 在线更新下载仍需继续验收。

## 2026-10-01 冷门路径与窄屏排布验收

- 真机验证了模型来源冷门路径：已配置的 DeepSeek provider 可从“模型来源”单独启用，页面显示 `当前启用: DeepSeek test · deepseek-flash`，OpenAI radio 同步取消；切回后显示 OpenAI 已选中、第三方 `已配置，未启用`。该轮没有重复发送 provider turn，保留前一轮真实 OpenAI turn 结果。
- 真机设置页核对了新会话默认模型、默认推理档位、默认审批策略、完全访问沙盒、模型来源、MCP/插件、自动命名、主题和语言入口，均有真实可操作控件；恢复 OpenAI 后设备保持原默认路径。
- 修复窄屏/大字体模式栏：模型、独立 effort、计划和权限控件放入横向可滚动容器，长模型名不会触发 Row 溢出，同时所有控件仍可访问。
- 修复排队 prompt strip 的纵向挤压：排队消息改为单行横向滚动，长 prompt 保留删除入口和省略显示，不再通过 Wrap 持续扩大 composer 上方高度。
- 新增窄屏大字体回归，`ccpocket_native_session_test.dart` `33/33` 通过；随后已将该改动纳入并安装 Release APK，详见本节末尾的产物记录。
- 随后已重新构建并安装 Release APK：`31,488,827` bytes，SHA-256 `E619C3A35E143B66FFC8D5913E14D7EBE86894824932197826AAED7B54D3890F`。APK verifier 通过，包名 `io.henry.codex`、non-debuggable、四个 ARM64 native assets 齐全；覆盖安装保留了现有 workspace/session 数据。
- 安装后的真机视觉检查确认：会话顶部模式栏在 1440×3200 屏幕内保持紧凑，模型、计划、Root 三个入口位于同一横向容器；空会话的 composer 没有被排队区或模式栏挤压。当前截图处于历史 test-project 的 DeepSeek 配置会话，未重新发起旧账号 turn。
- 真机冷路径：从会话点击“附加图片”进入系统文件选择器，再点击“取消”，约 0.9 秒内回到原会话；会话仍为“已停止”，图片列表为空，输入框、附加图片和发送入口均恢复可用，未写入或上传文件。

## 2026-10-01 图片导入异常路径

- 修复 `LocalImagePicker` 对非法原生返回的处理：非列表、非 Map 项、空图片和错误 MIME 不再被静默过滤或作为空附件继续发送，而是立即抛出格式错误；原生 `PlatformException` 仍原样传递，下一次选择可以正常重试。
- 会话层对格式错误新增中文/英文即时提示，避免错误延迟到 Codex 请求阶段。
- 新增 `local_image_picker_test.dart` 3 个回归测试；与 `local_session_conversation_test.dart` 合计 `38/38` 通过，覆盖取消后重选、损坏数据、原生读取失败恢复，以及 provider/session/image 相关现有路径。
- 重新构建并安装 Release APK：`31,489,887` bytes，SHA-256 `2090BB0FC3468752F9BF5FFDD0969F37DD57FF934D1F818D6CA5BAD9380134BE`。APK verifier 通过，四个 ARM64 native assets 齐全；真机安装时间 `2026-10-01 14:59:43`，应用数据保持不变。
- 真机额外打开并取消提示词历史弹层，空历史正确显示“当前会话没有历史提示词”，未遮挡输入控件；取消系统图片 picker 后也已恢复会话输入状态。

## 2026-10-01 KernelSU / MCP 低频路径复核

- `kernelsu_plugin_settings_test.dart`、`codex_mcp_settings_test.dart`、`local_ui_navigation_test.dart` 合计 `19/19` 通过，覆盖插件归档恢复、R3 禁用安装、Root 调用拒绝说明、MCP 增删/OAuth/市场回调、provider 切换和延迟启动恢复。
- 真机设置页复核了 KernelSU 插件区：归档摘要、R3 风险/重启提示、禁用安装入口、Root Profile 只读检查和已安装模块刷新入口均可见；没有自动执行 Root，也没有修改用户的 KernelSU profile。
- 真机设置页复核了模型/推理/审批/沙盒/模型来源/MCP/自动命名/主题/语言等分层入口；当前已登录状态和活动 CLI `0.159.2` 正确显示。

## 2026-10-01 MCP 异常本地化

- MCP 设置页对常见 session/thread 未就绪、MCP 配置格式错误、状态格式错误、无效服务器名和无效插件 ID 增加中文错误映射；未知错误仍保留原始技术细节，避免丢失诊断信息。
- 新增 `codex_mcp_error_localization_test.dart`，与既有 MCP 设置测试合计 `7/7` 通过；定向 analyzer 无 error，仅保留 Flutter SDK 的既有 deprecated hint。
- 重新构建并安装 Release APK：`31,491,107` bytes，SHA-256 `B34BC4751E64266D7BAD50FC6B5B394791B0DB77532959C6397C20DCA06285FB`。APK verifier 通过，四个 ARM64 native assets 齐全；真机 `lastUpdateTime=2026-10-01 15:12:04`，应用数据保持不变。

## 2026-10-01 多 session 前台服务 owner 回归

- 检查了本地 session 生命周期：页面离开只改变可见性，Home 持有 session runtime；Android 前台服务通过共享 owner 计数管理，不应因切换 session 而停止其他 session 的 worker。
- 新增 `session_lifecycle_test.dart`：两个 session 并发 start 时只启动一次前台服务；释放一个 owner 不会调用 stop；最后一个 owner 释放才停止；前台权限失败后 owner 会正确回收。测试 `2/2` 通过。
- 本轮只增加生命周期回归覆盖，没有修改已经验证过的 worker 生命周期实现，也没有重新构建 APK；上一个 Release 产物仍是当前真机安装版本。

## 2026-10-01 浏览器 OAuth 失败重试清理

- 修复 `CodexAuthClient.start()` 失败路径：登录初始化、浏览器授权 URL 校验或 API-key RPC 失败后，会完整取消事件订阅、停止旧 app-server、清空 pending 请求和登录状态，再把错误交给 UI；重试不会叠加旧进程或复用旧 localhost callback 状态。
- 新增回归：第一次登录失败后旧 process 已停止，第二次启动使用新的 process；`codex_auth_client_test.dart` 当前 `13/13` 通过。
- 定向 analyzer 无 error，保留该文件原有 lint/info；`git diff --check` 通过。
- 重新构建、校验并安装 Release APK：`31,488,875` bytes，SHA-256 `DEE92384CBEED7414D6B74F49BFF311D7169A3C757FC1D9D24388B632767170B`。四个 ARM64 native assets 齐全；真机 `lastUpdateTime=2026-10-01 15:21:20`，应用数据保持不变。

## 2026-10-01 冷门运行态状态栏与窄屏排布

- 补全会话顶部状态栏的 `reconnecting`、`resuming`、`queued`、`error`、`cancelled` 等低频状态颜色和中文显示，避免异常恢复时直接暴露英文内部状态。
- 状态文本现在限制为单行并使用省略号；长状态值不会在窄屏、长字号或异常诊断文本下撑破顶部布局。
- 新增 `ccpocket_native_status_line_test.dart` 两个回归；与现有 `ccpocket_native_session_test.dart` 合计 `35/35` 通过，覆盖窄屏状态栏和模式栏/会话控件排布。
- `dart format --set-exit-if-changed` 通过且无格式改动。Flutter analyzer 本次因本机 analysis server 输出 LSP JSON 截断而异常退出，未产生 Dart 诊断；已记录为工具环境限制，后续构建/分析窗口会再复核。
- Release 编译成功（`68.3s`），APK verifier 通过；产物 `31,489,415` bytes，SHA-256 `386CB0DCE2CF093440CA826D97C51B9774F44BA1441BF04FDE6FC04924D4B300`，包 `io.henry.codex`、non-debuggable、四个 ARM64 native assets 齐全。本轮未覆盖安装，避免打断当前真机工作会话。

## 2026-10-01 冷门模块集中排布修复与全量回归

- 批量文本替换页的 diff 预览改为默认折叠，避免大量匹配文件把提交/恢复操作推到长页面底部；预览仍可逐项展开。
- 交互式 PTY 弹窗改为根据键盘占用和剩余视口动态计算内容高度，避免软键盘打开时固定高度造成底部溢出；中断调用失败后会解除 `_stopping`，输入和重试入口不会永久锁死。
- 先集中扫描固定尺寸、弹层、键盘/大字号、异步生命周期、错误恢复和本地化路径，再批量修改；没有为每一项重复构建 APK。
- 全量 Flutter 测试一次性通过 `379/379`，包含批量替换窄屏、CC Pocket 首页/会话、并发 session、provider 切换、自动恢复、异常退出重连、图片、MCP、Root、CLI 更新和本地化回归。
- Release 编译成功（`62.5s`），APK verifier 通过；产物 `31,490,375` bytes，SHA-256 `6B4914DD9141E281E96DF223D044E828B29BE5F8E85D6B82677D9981A40CFD76`，包 `io.henry.codex`、non-debuggable、四个 ARM64 native assets 齐全。本轮仍未覆盖安装真机，避免打断正在运行的 worker/session。
