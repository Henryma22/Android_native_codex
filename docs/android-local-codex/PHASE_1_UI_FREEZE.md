# Phase 1：CC Pocket UI / Session 交互移植冻结

状态：**Frozen / Passed**（2026-09-24；最终验收记录见本文末尾）

本文件是独立 Android Codex App 的 Phase 1 权威范围和退出合同。它适用于
`apps/codex`，不适用于旧的 `apps/mobile` 集成线，也不把 `packages/bridge`
纳入本产品。

## 阶段目标

让用户在不关心底层 runtime 的情况下，使用独立 App 完成一套与 CC Pocket
一致的信息架构和 session 交互：

> 看起来像 CC Pocket，操作方式像 CC Pocket，session 状态变化也像 CC Pocket；
> 底层暂时使用 Fake、PRoot 或 Direct backend 不应改变这层体验。

Phase 1 的完成标准不是“页面存在”，而是 session owner、状态机、历史恢复、
队列、composer、tool/approval 事件和设置层级已经稳定，后续替换 runtime 时
不需要重写 UI。

## 允许修改的范围

只允许修改独立 App 的 Flutter UI、session application layer、本地持久化适配、
测试 fixture 和为这些交互必要的最小协议适配：

- App shell、底部导航、Home、Workspaces、Runtime、About 的信息层级；
- workspace 卡片、Recent Sessions、Grouped、搜索、筛选、置顶、删除、
  重命名、长按和滑动操作；不提供归档会话列表或恢复入口；
- 新建 session、打开历史 session、Resume、New session 和 session identity；
- session 页面 header、状态胶囊、模型/effort 显示、设置面板和菜单层级；
- `Starting / Running / Idle / Stopping / Stopped / Disconnected / Reconnecting /
  Failed` 的显示和转换；
- transcript、assistant/user/tool block、运行中 block、审批卡、用户输入卡、
  diff/change/backup 卡和可读错误卡；
- composer、draft、prompt history、slash/@ 操作、发送、停止、失败 Retry、
  断线队列和 Reconnect 后按序投递；
- session 历史、草稿、队列、设置和 session identity 的本地持久化；
- 以 Fake backend 或已有 PRoot backend 作为可重复验收 fixture；
- Android Emulator 上的 UI/交互验收和必要的真机 UI 回归。

复用优先级：先复用 `apps/mobile` 中已经打磨过的 CC Pocket widget、状态语义、
交互顺序和测试意图，再在 `apps/codex` 中做本地数据模型适配。旧目录只读参考，
本阶段不得把 Bridge、远程连接或旧 machine data-plane 引回独立 App。

## 明确冻结的范围

以下问题全部记录到 Phase 2/3 backlog，Phase 1 不主动处理：

- Android App UID direct Codex 的 `flock`、SELinux、sandbox、PTY、signals、
  DNS、代理和 provider 网络问题；
- Android-native runtime 重构、PRoot/rootfs 重构、root helper 和进程监督；
- 官方 Codex 二进制继续补丁、重新交叉编译或替换 APK native runtime；
- Bridge、WebSocket 中转、旧 `apps/mobile` 产品集成和 `packages/bridge`；
- Codex OTA、release endpoint、签名、更新密钥和自动更新；
- GitHub clone、后台 session、通知、share sheet、外部编辑器和其他新功能；
- 任何不影响 Phase 1 UI/session 验收的底层性能或跨 OEM 兼容性问题。

允许的例外只有一个：如果某个底层问题直接阻止 Fake/PRoot fixture 展示正确
的 UI 状态或事件，可做最小修复；修复后立即回到 Phase 1，不借机扩展 runtime。

## Session 交互合同

UI 只依赖 `Session` application contract，不依赖具体 backend：

1. 一个打开的 session 有稳定的 `workspaceId + sessionId + threadId` 身份；
   新建 session 不覆盖同 workspace 的历史 session。
2. 当前活动 session 由唯一 owner 管理。Home 的 Running 卡、session 页面和
   Recent Sessions 读取同一份状态，不能各自维护互相矛盾的副本。
3. 返回 Home 不销毁活动 session；Stop 明确终止它；Reconnect 只恢复同一身份；
   New session 才创建新身份。
4. 断线时 transcript、draft 和 queued prompts 保留。Reconnect 成功后队列按
   原顺序投递；无法恢复时显示可操作错误，不伪装为普通 assistant 消息。
5. provider turn 失败保留原 prompt，并提供 Retry；Retry 不创建重复的 session。
6. approval、user input、diff 和 tool event 都是结构化 block，不能把原始 JSON
   或 ANSI/MCP 诊断直接当作对话内容展示。
7. 默认模型和推理档位仍为 `gpt-5.6-luna · low`；设置页的模型目录必须来自
   当前安装 CLI 的真实目录并展示全部可解析模型。当前仍只暴露 `low` 推理档位，
   不把未完成的 per-model effort 映射伪装成可用设置。

## Phase 1 退出验收

只有下列项目全部通过，才能把状态改为 **Frozen / Passed** 并进入 Phase 2：

### 信息架构

- Home、Workspaces、Runtime、About 的导航和返回层级与 CC Pocket 一致；
- workspace、Recent Sessions、Grouped、搜索和筛选的行为一致；
- 新建、打开、Resume、Rename、Pin、Delete 和 Stop 的入口位置与
  操作反馈一致；
- session 页面不再以 runtime/debug 信息作为主要内容，首次进入即是 transcript
  和 composer；runtime 信息在设置/详情层级展示。

### Session 状态和数据

- 启动、运行、停止、断线、重连、失败和重试状态均有可观察的状态转换测试；
- Home Running 卡与 session 页面状态同步；
- 冷启动后 session identity、transcript、draft、队列、prompt history、设置、
  pin/rename 均可恢复；删除会移除该 session 的本地历史；
- 同 workspace 至少两个 session 可以互不覆盖地创建、打开和恢复；删除其中一个
  不影响另一个；
- 断线队列、Reconnect、Retry 和 New session 的边界分别验证。

### 交互组件

- composer、prompt history、slash/@ 操作、Stop、Retry、Reconnect 均可操作；
- tool call、approval、user input、diff/change/backup 使用 CC Pocket 对应的
  卡片层级和动作语义；
- loading、empty、error、disconnected、queued 和 running 均不是静态占位文字；
- accessibility/content-description 覆盖主要操作，触控目标适合手机屏幕。

### 验收方式

- Flutter tests 覆盖上述状态机和关键 widget flow；
- `flutter analyze` 无 error；
- API 35 x86_64 Emulator 完成冷启动、Home、workspace、session、resume、
  composer、approval、diff、settings smoke；
- 真机只做 UI parity 和本地历史恢复回归；不把 direct runtime/provider 网络
  未通过误报为 Phase 1 UI 未完成；
- 没有新增 Bridge、监听端口或旧 App/Bridge 依赖。

## 工作纪律

- Phase 1 未通过前，禁止开始 Phase 2 runtime 重构和 Phase 3 功能扩展；
- 发现阶段外 bug 只记录到 backlog，除非它阻止上述 UI 验收；
- 每个实现切片必须先对应本文件中的一个退出条件，再修改代码；
- 阶段通过后冻结 session application contract，再允许替换 backend/runtime；
- 任何“完成”结论必须同时给出支持（Supported）、可用（Available）和已验证
  （Verified）的区分，以及 Emulator/真机证据。

## 当前判定

**最终判定以本文末尾的 2026-09-24 验收记录为准。** 以下内容按时间保留当时的
未通过项和证据；较新的记录覆盖较旧结论。Phase 1 通过后，session application
contract 冻结，Android-native-first runtime 工作进入 Phase 2。

2026-09-24 后续回归：键盘显示时隐藏 Home 外层新建 FAB、键盘收起后恢复，以及无历史
空状态的工作区卡片左右留白均有回归。新 ARM64 release（SHA-256
`c222d7645cbfffc6c53c87a3ea8b4d4fcbae95d5a8d804a351909488dcbbcd6d`）已安装到真机；
空状态边距已目视确认。当前真机没有 Recent Sessions，Home 因此不显示搜索入口；键盘/FAB
修复尚未在真机有历史列表时目视复验，不能把 widget 结果记作设备级验证。

仍未通过的项目包括：真机有历史状态下搜索/FAB 修复视觉复验与搜索关闭后完整列表恢复；
真机打开旧 session 并检查完整历史/自动 resume、真正杀进程后的本机 draft/queue 恢复、
AVD approval/diff 的完整 UI flow，以及 Session 层主要操作的 content-description 与
触控尺寸逐项核查。本轮没有启动真实 turn；不得把 widget 测试、空状态 Home 截图或 APK
安装等同于全合同验收。以上缺口完成前，Phase 1 继续冻结，后续 runtime 架构工作保持暂停。

2026-09-24 后续：首页主要入口的最小 48dp 触控目标和 Settings 中文运行时/登录文案经
回归后，新的 ARM64 release（SHA-256
`d9599f28b6eaa62b3c187b3d0e835a7156679cc215e342cd5a0a039f4ab84db0`）已通过 verifier
并安装至真机，保留应用数据。实测 Home 左右边距各 12dp、设置/刷新/菜单触控框 48dp、
添加工作区 78×48dp；Settings 显示 `Codex 登录 / 状态：已登录`，浏览器 OAuth 仍为所选
方式且未触发 Root approval。此次冷启动后第一次点 Settings 即进入设置（观察窗口 2 秒），
返回 Home 正常。此观察仅确认已保存状态展示，不是新的 OAuth 或 Codex turn 验收。最终包
真机空白会话显示会话专属空态，输入框能唤起 IME 且位置随键盘上移；测试生成的空历史项
已删除，工作区保留且 Recent Sessions 恢复为空。未发送真实 prompt，Phase 1 继续未通过。
另外在临时会话中验证计划模式开启/还原、只读/完全访问/默认权限选择的可见状态更新，
随后恢复默认并删除测试记录；这不等于真实 Codex turn 对这些策略的应用验收。

### 2026-09-24 最新真机回归（覆盖上文较早的未验证状态）

- 真机 `6cb21282` 的 session 冷恢复和一条真实 Codex turn 已完成：先前保存的草稿在强制结束 App UI 进程并重新打开 session 后恢复；真实 turn 使用 `gpt-5.6-luna · low` 返回精确内容 `PHASE1_DEVICE_SMOKE_OK`，状态回到“就绪”。完整 transcript、上下文计数和账号用量在重新安装 release 后仍保留。未捕获中间 token delta，因此不将 streaming 增量记为已验收。
- 真机发现旧历史有 3 条相同的本地化 MCP 网络提示；现已修复历史恢复去重，并在 12 项定向测试中覆盖重复中文历史、resume 新 stderr、system chip 和额度提示。修复版安装后重新打开旧 session，MCP 与 Code Mode 各显示一条，最终回复和用量仍在。
- 最新 release SHA-256 为 `f0f571b29c748d025703af074ec67c057dacd15d96f2260908ea8cbda3dd7ff6`，5 个 ARM64 native assets 齐全，证书为 QA debug certificate。测试 session 已显式停止并删除；workspace `test-project` 保留、Recent Sessions 为空，Codex 子进程已退出。设备证据位于 `tmp/phase1-ui-20260924-phone/44-after-resume-latest.png`、`44-after-resume-latest.xml` 和 `56-home-clean.png`。

**Phase 1 仍未通过。** 下一步继续完成 API 35 AVD 的 approval/diff 完整交互、session 操作的 content-description/触控范围核查，并补捕获一次真实 turn 的中间流式增量。已完成的冷恢复/最终回复/历史提示去重不能替代这些剩余验收，也不允许据此开始 Phase 2。

### 2026-09-24 后续真机续验（覆盖上条未完成的 approval/diff 与 streaming 状态）

- API 35 AVD 的 FileChange approval/diff fixture 已实测：原 CC Pocket 审批卡本地化、diff 展开/收起、增删行呈现和批准回调均可用。该 fixture 是 UI 组件路径验收，不等价于 Codex 真 turn 发出的文件写审批 E2E。
- 真机 `6cb21282` 的真实 Codex turn 中途截图显示 `运行中` 且已显示 assistant 增量；最终回复的 `STREAM_DELTA_ACCEPTED` 与 `就绪` 状态均已确认。消息操作条复制/纯文本/分享新增 48dp 目标和 TalkBack 标签，定向 widget 测试 16/16 通过，并在正式 ARM64 release 真机层级中实测为 48×48dp。
- 真机有历史状态下搜索无匹配词、键盘/FAB 显隐、关闭搜索后完整历史恢复已实测；测试会话已清理，`test-project` 工作区保留。真实 turn 完成、停止和删除测试 session 均未影响其它 session。
- 最新 release SHA-256：`3d44f4f1eb622706b6dafd6012230ba908b1b1093dea6915bc5a44616d7aca5c`；APK verifier 确认 5 个 ARM64 native assets 齐全。发布签名仍是本机 QA debug certificate，非商店签名。

**Phase 1 尚未通过。** 尚需补齐 session 层其余菜单/审批/diff 等次级控件的逐项无障碍核查；更关键的是，真机只观察到首条用户 prompt 作为截断标题，没有 Codex 语义化自动命名。当前实现不会以最新 assistant 回复命名，但它只是一段 prompt 摘录，不满足“自动生成语义化简介名”的严格解释。Home 搜索恢复已有 widget 和真机验收。全部退出条件完成前不得进入 Phase 2。

### 2026-09-24 语义标题修复与真机验收（覆盖上条标题限制）

- 自动标题现通过独立 ephemeral app-server thread 生成并写回原 thread metadata，不把生成内容插入可见 transcript；使用所选 Luna 模型、强制 low effort、只传首条用户 prompt，关闭工具和继承的 MCP server。手动重命名会取消待处理自动标题。
- 真机首次未命名的原因已定位为 `thread/start` 的 `threadSource` 形状错误：协议要求字符串，旧实现发送对象。改为 `"system"` 并增加协议回归后，36 个 session/title 定向测试通过。
- Release APK 已通过 verifier（117,096,875 bytes，SHA-256 `e727e98554403c5c21877f970b2d43ee80dd67035bca081809bcb3c0b3f96bd1`，5 个 ARM64 native assets；本机 QA debug certificate）。真机 `6cb21282` 使用 `5.6 Luna · 低` 完成真实 turn；Home 最终显示语义标题“Explain Android free storage”，对话历史完整保留，隐藏标题 thread 未污染 transcript，session 回到就绪。此前的 prompt 截断标题限制已解决并有设备验证。
- 顺手修正 release builder 对 Flutter depfile 中旧 SUBST 盘符的窄范围恢复；只会移走确认引用过期临时盘符的生成 depfile，不碰源码或用户数据。修正后的 ARM64 release 构建成功。
- 验收后停止并删除本轮临时测试 session，保留 `test-project` workspace；设备未遗留 Codex 子进程。设备截图和 Home hierarchy 保存在 `tmp/phase1-title-20260924-phone/`。

**当前仍未通过 Phase 1。** 下一项聚焦 session 菜单及 approval/diff 等次级控件的语义名称、触控目标和真实动作反馈审计；标题自动生成不再是阻塞项。不得据此进入 Phase 2。

### 2026-09-24 slash command 即时反馈回归（最新验收）

- 真机曾复现 `/status` 已写入本地 transcript，却因 `_addStructuredTranscript` 未通知
  Flutter 重建，当前对话继续显示空态。共享追加入口现已在挂载状态下调用 `setState`。
- 完整 `local_session_conversation_test.dart` 10/10 通过，包含发送 `/status` 后立即显示
  系统提示；Dart analyze 无 error（仍报告该文件已有 warnings/infos）。
- Release APK SHA-256：
  `3270abe19f64a3e213ad4a46ff17666e82373ae5007c2ef2a136ccc7d898c749`；verifier 确认
  签名有效、5 个 ARM64 native assets 齐全。覆盖安装到 Android 16 真机 `6cb21282` 并
  保留应用数据。重新打开历史测试 session 后再次发送 `/status`，新增状态 chip 立即显示
  （“会话状态：已停止……消息数：1”）；命令未启动 Codex/PRoot 子进程。
- 验证后删除临时测试 session；`test-project` workspace 保留，Home 无 Recent Sessions，
  设备进程检查仅见 App UI 进程。证据：
  `tmp/phase1-title-20260924-phone/slash-fixed-result.png`、
  `slash-fixed-result.xml`、`slash-fixed-home2.xml`。

**最新判定：Phase 1 Frozen / Passed；Phase 2 Active。** 下一切片实际审计 Android
Native Toolchain 从 App UID 的发现、PATH 注入到命令执行，逐个验证 `git`、`node`、
`npm`、`npx`、`python`，并区分 Supported / Available / Verified。
