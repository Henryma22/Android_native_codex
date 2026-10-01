# Android Codex 性能与页面验收（2026-09-28）

## 本轮变更

- 长会话 transcript 按可见行惰性构建并解析，避免流式刷新时重新物化完整历史；解析缓存改为 512 项 LRU。
- 新增 600 条历史滚动回归，覆盖超出缓存容量后从最新消息滚动到最早消息。
- 所有 Codex CLI/app-server session 都走本机 Linux/PRoot；PRoot 不可用时展示安装/验证状态，不启动 Android/Bionic Codex。
- 清除 Android ABI 工具链的设置入口、导入器、宿主/PRoot PATH 注入及旧 runtime 被动探测。Android 宿主命令使用系统原生命令，git/node/npm/npx/python 由 Debian guest 提供。
- 移除旧 Codex Bionic CLI 的 APK 资产、宿主导入/Root 安装与回滚实现、旧 ADB 安装脚本；APK 验证器拒绝 `libcodex.so` 和 Root Read Broker。
- 修正旧 session 中缓存的过期 Bionic 提示的显示映射，不改写本地历史内容。

## 页面与交互

| 范围 | 结果 | 证据边界 |
|---|---|---|
| 首页 | 候选 APK 在 AVD 实际打开；工作区卡片等宽，session 按 workspace 分组并可浏览 | `vm-demo` 是 AVD 合成测试数据；AVD 未登录，因此没有用量数值 |
| 会话页 | 从首页打开已保存 fixture；CC Pocket mode bar、composer 与历史布局显示正常 | 缺少 ARM64 PRoot rootfs 时明确提示未验证并禁用发送；不代表真实 turn 已通过 |
| 设置 | Linux/PRoot、登录、模型、effort、权限、主题与语言入口可见；打开页面未出现 Root approval | AVD 不验证 KernelSU 能力；候选 UI 不再暴露 Android/Bionic Codex 或 ABI 工具链入口 |
| 第三方模型 | provider 信息页与新增表单打开，Responses API 地址、model、effort、key 字段可见 | 没有保存密钥或发起 provider 请求 |

Release APK 页面证据：

- [候选包首页](../../artifacts/ui-smoke/20260928-avd-candidate-home.png)
- [候选包会话页](../../artifacts/ui-smoke/20260928-avd-candidate-session.png)
- [候选包设置页](../../artifacts/ui-smoke/20260928-avd-candidate-settings2.png)
- [候选包第三方模型页](../../artifacts/ui-smoke/20260928-avd-candidate-providers.png)
- [候选包 provider 表单](../../artifacts/ui-smoke/20260928-avd-candidate-provider-editor.png)

## 验证结果

- 全量 Flutter tests：328 项通过；另有 settings/provider、宿主命令页定向 UI 用例通过。
- Kotlin 定向测试：`CompatibilityCommandArgvTest`、`CodexSessionHomeTest`、`HostProcessEnvironmentTest` 均通过。
- Release APK：构建及 verifier 通过；包名 `io.henry.codex`，31,406,299 bytes，SHA-256
  `395DFFDAB309FA1E308BBBC2A4C22C10588FE9CE992D9DEF68E0FEEFE84ED881`。该 Release variant 使用本地 debug certificate，可本地覆盖安装，不是商店签名。
- APK 包含 4 个 ARM64 PRoot/host 资产；没有 Bionic Codex executable、旧 Android ABI 工具或 Root Read Broker。
- 签名为 Android debug certificate：可本地覆盖安装，不是商店发布签名。
- 旧 AVD 的 `gfxinfo` 小样本受虚拟 GPU 异常影响，不作为性能结论；该阶段的性能收益由惰性 transcript 解析/512 项 LRU、隐藏 session 避免 Home 高频重建和 600 条历史滚动回归覆盖。

## 真机检查与未完成项

Release 实机验收结果与剩余限制见下方“Release APK 实机验收”。此前“手机仍安装旧 APK、未验证真实 turn”的记载属于早期检查点，已被后续验收取代。

### 2026-09-28 旧 APK 检查（历史检查点）

- 按用户此前授权将既有 `io.henry.codex/.MainActivity` task 切回前台；系统确认是恢复原 task，没有重启 App。首页截图观察到工作区卡片等宽、session 直接列在“最近会话”、没有独立“进行中”面板；真实额度为 5h 57%、1w 44%。未打开或切换任何 session。
- 旧安装回前台后的 `dumpsys meminfo` 读数约 PSS 289,021 KiB / RSS 418,824 KiB。`gfxinfo` 小样本 30 帧中 7 帧标为 janky（23.33%），p90 为 150 ms；紧接着的累计读数为 35 帧、8 帧 janky。包含前后台恢复、样本很小，不能视为受控滚动性能结果或候选 APK 的性能结论。
- 尝试清空 `gfxinfo` 计数并在首页上下滚动后，前台 app 仍确认是 `MainActivity`，但计数为 0 帧；该次受控采样无效，不纳入性能通过率。后续已安装 Release APK 并完成真机功能验收，但有效的 Flutter 帧时延采样仍缺失。

### 2026-09-28 Release APK 实机验收

- 实体设备 `6cb21282`（ARM64）已覆盖安装正式 Release variant；设备 `base.apk` 与本地构建产物 SHA-256 完全一致：`395DFFDAB309FA1E308BBBC2A4C22C10588FE9CE992D9DEF68E0FEEFE84ED881`。安装版本 `1.0.0`，保留了应用数据；没有清除 workspace/session。
- 设置页确认 OpenAI 登录状态为“已登录”。新 Root session 获得一次绑定该 session 的授权，启动本机 Linux/PRoot Codex/app-server。
- 模型来源菜单层级实测：全局设置中的“模型提供商”是来源选择父级，OpenAI 订阅与第三方服务商并列；第三方配置列表作为其子页，不再把 OpenAI 放在第三方配置表单里。第三方配置列表保留 DeepSeek 配置；选中 DeepSeek 后父级标记“当前启用”。切回 OpenAI 后父级标记 OpenAI 已选、DeepSeek“已配置”；强制停止并重新启动 App 后仍保持此状态。
- 保持 OpenAI 模式时完成一次真实 Codex turn，回复为 `OPENAI_RELEASE_TURN_OK`，页面展示真实用量信息；本轮没有向 DeepSeek 发送请求。该结果验证了切回 OpenAI 后新 session 实际走 OpenAI 订阅路径，而不只是 radio 状态变化。
- 模型选择响应：Release 真机上模型设置面板 6 次连续打开耗时为 893、930、906、957、1034、986 ms（主机端从点击到设备截图完成，包含 120 ms 固定等待与 ADB 开销）；动态 CLI 模型列表一次打开并截图为 691 ms。当前模型一直保持 `6 Luna / low`，没有切换到其他模型。
- 该结果覆盖了此前每次模型弹窗等待超过 5 秒的确定性路径；本次重复操作没有复现长停顿。它不能证明所有页面都无随机卡顿：Flutter 画面未提供可用的 `gfxinfo` frame stats，SurfaceFlinger `--latency` 只返回刷新周期、没有帧样本；因此尚不能报告全页面 jank 百分比或 p90/p99 帧时延。
- 页面截图和流程记录：[本次 Release 真机验收截图目录](../../artifacts/ui-smoke/20260928-release-device-acceptance/)。本轮重点检查设置主分组、模型来源父子层级、第三方已配置/未启用状态、进程重启持久化、会话模型列表和真实 OpenAI turn。未逐项完成整个 App 所有菜单的无障碍或全部页面导航验收。
- 测试完成后已 force-stop 本轮由 Agent 启动的 App/Codex worker；未清除或删除 session 历史。KernelSU profile 与组权限均未改动。

### 2026-09-28 Release 菜单响应续验（最新构建）

- 真机此时已断开，改用 ARM64-compatible AVD `emulator-5651`；没有把模拟器结果记作真机验证。最新 Release variant 构建并安装成功，包 `io.henry.codex` / `1.0.0`，`31,408,203` bytes，SHA-256 `997B502F59165BC82DA1CB6E13A0BEF60E94D30B7C823062BDCA09AD2F8145CC`。从模拟器拉回的 `base.apk` hash 完全一致。使用本地 debug certificate，非商店签名。
- 全量 Flutter tests：`328/328` 通过。一个旧 UI 断言仍要求 Root 说明出现在选项前；现已改为验证说明文案存在，而菜单把常用权限选项优先展示在说明前。
- 模型面板在点击后的首个 250ms 检查点已显示；本 AVD 未安装 Linux/PRoot rootfs，模型目录读取不可用，弹层保留当前模型并给出重试提示。该结果证明慢 RPC 不再阻塞弹层出现，但不证明模型目录可用。前一版 Release 真机对模型设置面板 6 次的 0.89–1.03 秒响应记录仍是当前唯一的真机响应采样。
- 权限菜单在首个 200ms 检查点已显示，标题/简短说明之后直接列出“默认、完全访问、只读”；Root 软路由说明放在常用选项之后。全局设置中“模型提供商”位于 CODEX 设置一级，打开后 OpenAI 订阅与第三方服务商并列，第三方配置只出现在其子页。
- 模拟器没有已保存的第三方 provider、OpenAI 登录或 PRoot guest，因此本次仅验收菜单结构与显示，不做 provider 请求、模型列表真实性、Root 操作或真实 turn 的断言。早先 `395D...` Release 的 provider 往返/进程重启与真实 OpenAI turn 仍单独保留为真机证据；最新 APK 上这几项未重新跑，因为设备断开。
- 菜单层级抽查还覆盖工作区标题菜单（创建/刷新）、工作区卡片菜单（新会话/浏览/删除）、session 长按菜单（打开/置顶/重命名/删除）和 thread 右上角菜单（详情/重命名/新建/分叉）；删除动作没有触发。主要设置/会话菜单的相对层级清楚；这不等于逐项检查 App 中每一个 composer 或系统 picker 子菜单。
- AVD `gfxinfo` 菜单开合样本只有 21 帧，其中 18 帧标记 janky，p50 18ms、p90 34ms、p95 34ms、p99 250ms；GPU p90 返回 4950ms 哨兵值，SurfaceFlinger 标明模拟器使用 Google SwiftShader，另一次 reset 后复测只返回 0 帧。此结果表现出该软件渲染 AVD 的采样不稳定，不能归因成真机 App 帧率，但也不能拿来宣布随机卡顿解决；物理设备重新连接后仍需采集有效帧样本。
- 新版构建产物：[Release APK](../../artifacts/release/android-codex-1.0.0-arm64-release-menu-review-20260928.apk)；AVD 截图与流程：[菜单复核目录](../../artifacts/ui-smoke/20260928-release-avd-followup/)。测试后已 force-stop 可访问模拟器上的 App；没有清理 session/workspace 数据。
- 随机卡顿仍未取得有效帧级计量：当前有模型/权限弹窗不再等候 app-server 完成目录 RPC 的实现与定向响应证据，但没有合格的 Flutter frame-time 样本，因此不能宣称所有随机卡顿都已解决。

## 保留的兼容边界

旧 Bionic runtime 探测和启动入口、Android ABI 工具链导入/PATH 与宿主原生工具矩阵已从候选应用路径移除；宿主命令页保留并说明 git/node/npm/python 来自 Debian guest。旧工具链源码已移出仓库到本机 Temp quarantine（尚未删除）。历史 transcript/会话记录未被清理。CC Pocket UI 源码继续保留，因为 session、composer 和消息组件仍在使用；生成式 `AppLocalizations` 中未被当前页面引用的 Bridge/Claude 文案仍只是共享类型数据。

### 2026-09-28 实体机 Release 模型弹层与 provider 来源修复

- 真机 `6cb21282` 已安装最新 Flutter Release：`io.henry.codex` `1.0.0+1`，安装后 `flags=0x0`（不是 debuggable APK），`adb install -r` 保留工作区和历史 session。APK `31,416,363` bytes，SHA-256 `5A8AAB29642E61A03C4FD6380CF1391445D21544BE9B0E661D713C35E35E77B6`；签名是本地 Android debug certificate，不是商店签名。APK verifier 确认 4 个必需 ARM64 PRoot/host 资产齐全、无缺失。
- 根因：CC Pocket `CodexSettingsSheet` 的模型子选择器只捕获打开瞬间的 `models` 列表。冷启动并在目录 RPC 尚未完成时打开第三层模型 picker，会先出现只含当前模型的快照；之后父设置面板更新，但已打开的子 picker 不会刷新，关闭后重开才看到完整目录。
- 修复：子 picker 自己订阅同一个缓存中的异步模型目录 future，先立即显示当前模型与加载指示，目录返回时在当前弹层内更新选项；失败时显示可理解的状态。未等待模型目录完成才打开弹层，也未额外启动 CLI 进程。新增回归测试覆盖“先打开模型列表、后完成目录 future”的时序。
- 真机 Release 回归：在有效当前 thread 上点开模型列表，首个约 250ms 检查点已显示完整的 `6 Astra`、`6 Sol`、`6 Luna`、`Reserve`、`5.6 Sol/Terra/Luna` 和 `5.5`；没有等待 5 秒。该交互的 `gfxinfo` 窗口记录 4 帧、0 janky，p50/p95 均为 10ms；样本帧数很少，只能作为本次菜单响应证据，不能推断全 App 的随机卡顿已消失。主机端 tap-to-capture 约 997ms，包含 ADB 往返和 220ms 固定等待。
- 再做 8 次连续模型列表开合，6 次不含首尾截图/ADB 拉取的 tap-to-capture 为 325–401ms（均包含 220ms 固定等待）；首尾截图均确认完整模型列表。对应的第二次 `gfxinfo reset` 返回 0 帧及 4950ms 哨兵百分位，说明该设备/Flutter surface 的 gfxinfo 样本会间歇不可用，不能把哨兵值当作真实卡顿时长，也不能用零帧结果宣称无 jank。
- provider 来源页面真机实看：Settings → 模型来源中 OpenAI 订阅与第三方服务商并列；第三方 API/模型配置通过第三方卡片内的齿轮进入子页。当前 DeepSeek 配置明确标为“已配置/已保存，未启用”；仅切换来源时显示“当前启用”。实测本地切换“第三方→OpenAI”后 OpenAI 圆点选中、DeepSeek 仍保存但未启用；未发送第三方请求、未使用 API key。`local_session_conversation_test.dart` 覆盖显式 OpenAI 来源覆盖历史第三方配置，确保 OpenAI app-server 参数路径。
- 相关 Flutter 定向测试 `58/58` 通过：`ccpocket_native_session_test.dart`、`custom_provider_settings_test.dart`、`codex_model_catalog_test.dart`、`local_session_conversation_test.dart`。截图目录：[真机模型/来源流程](../../artifacts/ui-smoke/20260928-provider-performance/)；关键截图：[模型目录](../../artifacts/ui-smoke/20260928-provider-performance/49-model-correct-250ms.png)、[模型来源父页](../../artifacts/ui-smoke/20260928-provider-performance/29-provider-source-250ms.png)、[第三方配置子页](../../artifacts/ui-smoke/20260928-provider-performance/31-provider-config-250ms.png)、[切回 OpenAI](../../artifacts/ui-smoke/20260928-provider-performance/34-source-openai-restored.png)。
- 菜单检查覆盖设置中的模型默认值/来源层级、第三方配置子页、thread 模型/effort 子面板及工作区/session 主要入口；没有逐项验收应用所有 composer、系统选择器和设置子菜单。用户报告的全局随机卡顿仍需扩大有效帧样本和跨页面实测；本次仅能确认 Release 与模型 picker 这条路径，不宣称所有卡顿已解决。
- 测试结束后 force-stop 本轮启动的 Codex app/worker；没有清除应用数据、workspace 或 session 历史。KernelSU 配置未更改。

### 2026-09-28 真机 Release 菜单/模型续验与帧 trace

- 复核设备 `6cb21282` 当前安装的是 Release：`io.henry.codex` `1.0.0`，package flags `0x0`（非 debuggable）；设备 `base.apk` SHA-256 与 [release APK](../../artifacts/release/android-codex-1.0.0-arm64-release-model-picker-20260928.apk) 同为 `5A8AAB29642E61A03C4FD6380CF1391445D21544BE9B0E661D713C35E35E77B6`。没有重建或覆盖安装，因为本轮源码未改动。
- 模型路径在真机逐层操作：thread mode bar → CC Pocket effort 面板 → 高级设置 → 模型列表。首个 220ms 检查点已显示完整模型目录；实际选为 `6 Sol` 后又恢复 `6 Luna / low`，没有发送 turn。截图：[弹层首帧](../../artifacts/ui-smoke/20260928-menu-perf-followup/29-model-settings-220ms.png)、[完整模型列表](../../artifacts/ui-smoke/20260928-menu-perf-followup/31-model-options-220ms.png)。权限选择、计划开关、会话设置和 thread overflow 均已操作；thread overflow 项目为详情/重命名/新会话/分叉。此前首次权限点击异常跳转未能复现，当前控件中心点击正常打开权限底 sheet，原因仍未确认。
- 首页/设置/模型来源父页与第三方配置子页、工作区与 session 菜单也有本轮真机截图，集中在[验收目录](../../artifacts/ui-smoke/20260928-menu-perf-followup/)。层级符合“模型来源”与“第三方配置”父子关系；OpenAI 与第三方是来源页同级选项。没有确认删除工作区，也没有发起第三方 API 请求。
- 重新运行 `custom_provider_settings_test.dart`、`ccpocket_native_session_test.dart`、`local_session_conversation_test.dart`：52/52 通过；其中 OpenAI 覆盖历史第三方设置并检查 app-server 参数的用例通过。
- 当前屏幕刷新率为 120Hz。一次包括三轮模型列表开合及权限/计划/设置菜单的 `gfxinfo` 样本：854 帧、3 帧被该统计标为 janky（0.35%），p95 20ms、p99 24ms；高输入延迟计数为 1689。该统计口径与 Perfetto 的 frame timeline 不一致，不能用 0.35% 宣称全局不卡。
- 另抓取 8 秒 Perfetto trace：[真机菜单 trace](../../artifacts/ui-smoke/20260928-menu-perf-followup/39-real-device-menu-trace.pftrace)。它包含该短暂菜单动画窗口内 54 条本 App actual-frame-timeline 记录，其中 28 条 on-time、26 条 late（混有 App deadline、Display HAL、SurfaceFlinger 分类）；App 主线程最大一次 Running 23.7ms，Raster 最大 slice 2.58ms、RenderThread 最大 slice 4.44ms。此小样本说明 120Hz 转场仍存在掉帧，但没有捕捉到 5 秒级 UI 线程停滞；不能外推到首页滚动、长 transcript 或随机卡顿。
- 本轮没有发新 prompt。结束时已 force-stop 测试启动的 App；设备上未见 Codex/PRoot worker，数据 inode 未变、workspace/session 历史未清理。设备 `/data/local/tmp` 中的临时 trace 副本已删除；本地分析使用的官方 Perfetto 14MB trace processor 留在用户缓存，工作区 trace 保留用于下一轮分析。
- 下一步应在同一 Release 上分别抓首页列表滚动与长 transcript 流式更新的 frame trace，再将 App/Raster 的长 frame 与相同时间窗的 Android compositor/GPU 事件对齐；目前模型弹层的 5 秒确定性等待已不复现，但全局随机卡顿仍未通过验收。

### 2026-09-28 Release 模型菜单收尾

- 修正会话模型面板两个无效/未本地化项：把 Effort/Light 等当前值按中文、日文、韩文显示；Fast/Speed 仅在当前模型能力明确包含 `fast` 或 `priority` 时显示。Codex app-server 集成尚未提供 service-tier 能力且回调为空，因此其 UI 不再展示一个看似可用却无效的控件；即使旧状态保留 `Fast`，也不会伪装成后端已支持。
- 新增中文 widget 回归，检查快捷与高级模型面板中的“低/推理强度”，并断言无速度入口。`custom_provider_settings_test.dart`、`ccpocket_native_session_test.dart`、`local_session_conversation_test.dart` 共 `53/53` 通过；包含第三方配置下切回 OpenAI 的 provider 选择及 app-server 参数测试。
- 本次仅构建 Release：APK verifier 验证包 `io.henry.codex` / `1.0.0`、4 个 PRoot/host ARM64 资产齐全、无退役 Bridge/Bionic Codex 资产；大小 `31,423,927` bytes，SHA-256 `05D888B0276695F8CE74768DDA4914102B7FF0280071651CF1251515D75D42CA`。本机验收包使用 Android debug certificate，非商店签名。已覆盖安装到实体机 `6cb21282`，`base.apk` 哈希与构建产物一致，package flags `0x0`（Release、不可调试）；保留现有数据，没有清理 workspace/session。
- 真机复测时，线程里的模型设置弹层在首个约 `220ms` 检查点可见，推理档位为“低”；高级菜单只有“模型/推理强度”，无“速度/Standard”；打开模型子列表时完整选项（含 6 Astra/Sol/Luna 与 5.6、5.5 系列）也在约 `220ms` 检查点可见。之后恢复为 `6 Luna / low`，未发送 prompt。截图：[Release 快捷模型面板](../../artifacts/ui-smoke/20260928-menu-perf-followup/46-release-model-picker-220ms.png)、[高级面板](../../artifacts/ui-smoke/20260928-menu-perf-followup/47-release-advanced-settings.png)、[模型目录](../../artifacts/ui-smoke/20260928-menu-perf-followup/48-release-model-options-220ms.png)、[最终恢复状态](../../artifacts/ui-smoke/20260928-menu-perf-followup/51-release-restored-model.png)。新 APK：[Release 包](../../artifacts/release/android-codex-1.0.0-arm64-release-model-settings-20260928.apk)。
- 打开旧验收 thread 时，UI正确保留缓存消息并显示“saved thread expired”；该 session 的服务端 thread 已不在当前本地 runtime，故未尝试续跑或发送消息。这不影响模型菜单可用性，但说明旧 transcript 不保证对应的服务端 thread 仍可恢复。
- 额外 [Perfetto trace](../../artifacts/ui-smoke/20260928-menu-perf-followup/52-release-model-menu-app-trace.pftrace) 已用 `-a io.henry.codex` 重抓，但处理结果没有 Codex surface 的 frame timeline 或 Flutter 主线程 slice（仅有 SurfaceFlinger/System UI 层及 ScoutStat 线程）；该 trace 不纳入 App 帧率统计，不能据此声称菜单掉帧或不卡顿。模型菜单的 220ms 截图是交互响应证据，不等价于稳定帧时延。全局随机卡顿、首页滚动与长 transcript 的有效帧采样仍未完成。
- 重新安装后没有切换模型来源或调用第三方 API；OpenAI/第三方来源层级与持久化真机证据沿用前一 Release 的验收，当前变更只涉及 Effort/Speed 菜单呈现。已 force-stop 本轮启动的 App；未见 Codex worker/app-server，未清除 session/workspace 数据或改动 KernelSU 设置。

### 2026-09-28 最终 Release 本地化续验

- 真机打开过期 thread 后发现的英文失效提示已本地化；同时覆盖新产生的 stale-resume 错误和已写入历史的英文系统记录。新增失效 `thread/resume` 场景回归。三组相关 Flutter tests：`54/54` 全通过。
- 最终 Release APK：[下载](../../artifacts/release/android-codex-1.0.0-arm64-release-ui-l10n-followup-20260928.apk)，`31,425,251` bytes，SHA-256 `E50F142B81F965AB55A490504125A5BD14FFC831426E80B20F63EC5BB945FF1D`。verifier 确认 package/version、4 个 ARM64 PRoot/host 资产和签名正常，无旧 Bridge/Bionic Codex 资产；仍是本机 QA 用 debug certificate 签名，不是商店签名。
- 已用 `adb install -r` 覆盖安装至 `6cb21282`；设备 `base.apk` SHA-256 与上述产物一致，`flags=0x0` 且版本 `1.0.0`。安装前后 app data inode 未变，现有 workspace/session 数据保留。
- 当前最终 Release 真机截图：[中文过期 thread 提示](../../artifacts/ui-smoke/20260928-menu-perf-followup/57-final-release-thread-retry.png)、[220ms 模型面板](../../artifacts/ui-smoke/20260928-menu-perf-followup/58-final-release-model-settings-220ms.png)、[高级模型菜单](../../artifacts/ui-smoke/20260928-menu-perf-followup/59-final-release-advanced-settings.png)。失效 session 的缓存消息仍显示，诊断提示已中文化；模型与推理强度保持 `6 Luna / 低`，高级菜单不再出现无回调的速度项。
- OpenAI/第三方 provider 的互斥和切回 OpenAI 参数用例包含在这次 `54/54` 测试中；前一 Release 已完成真机切回 OpenAI、重启后保持选择和真实 OpenAI turn。本轮未切换来源、未调用第三方 API；provider 路径实现未被本轮 UI 呈现改动触碰。
- 此版 Release 上模型设置面板在点击后 `220ms` 截图检查点可见；这是本轮模型菜单响应验证，不是全局性能通过。Perfetto 没有捕获可归属 Flutter 主线程的帧片段，`gfxinfo` 复测也返回零帧/4950ms 哨兵；全局随机卡顿、首页滚动和长 transcript 的真实帧时延仍未完成有效验收。
- 验收完成后已停止本轮启动的 App；没有活跃 Codex worker/app-server，设备端临时截图/trace 副本已移除，本地截图和 trace 作为验收证据保留。没有删除 workspace/session 或改动 KernelSU 配置。

### 2026-09-28 Provider 切换修复与真机 Release 续验

- 最新 Release 包：[`android-codex-1.0.0-arm64-release-provider-switch-20260928.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-provider-switch-20260928.apk)，SHA-256 `D28C28502C90130820DBC6316AD3CD4510DFF8DE6FF6C8AA5CD0313E7820B452`，31,425,707 bytes。真机 `6cb21282` 的安装包 hash 一致，`versionName=1.0.0`、`flags=0x0`；是 Release variant，不可调试，使用本机 QA debug certificate（不是商店签名）。覆盖安装保留了 app data inode、workspace 和 session。
- 根因是设置父页已写入新的来源，但 session 遇到活跃 turn 时拒绝切换 client，导致界面显示 OpenAI、旧第三方 client 仍继续使用。现在切换来源会停止旧来源的活跃 turn、保留可见 transcript，并让下一次发送按新来源重新启动；页面明确提示这一行为。回归用例检查第三方活动 turn 被停止以及下一次请求使用 OpenAI app-server provider，不依赖 radio 外观断言。
- `local_session_conversation_test.dart`、`custom_provider_settings_test.dart`、`ccpocket_native_session_test.dart` 本轮定向测试 `55/55` 通过。真机来源父页再次确认 OpenAI 已选中、DeepSeek 仅为已配置；当前 app-server 参数为 `android_openai_http`。本续验没有发送新 turn、没有调用第三方 API，也没有读取或暴露 key。
- 真机逐层复测模型菜单：thread mode bar → 快捷模型/effort 面板 → 高级 → 完整模型列表。稳定 thread 中快捷面板和完整目录都在点击后的首个约 250ms 检查点可见，包含 `6 Astra`、`6 Sol`、`6 Luna`、`Reserve`、5.6 与 5.5 系列；没有复现 5 秒等待。首次进入恢复 session 时 status 和用量栏高度会改变，测试时先等布局稳定再点，避免把旧坐标点到空白区。
- 主要导航层级复核：Settings → CODEX → 模型来源；来源页内 OpenAI 订阅与第三方服务商并列；第三方表单/配置只从第三方项进入。thread 模型/effort 是会话级快捷设置；高级页再进入模型与推理强度选择。工作区、session 与 thread overflow 的创建/浏览/删除/重命名/分叉位置沿用本日真机菜单抽查；未触发任何删除。MCP、KernelSU 等各自领域内的管理页仍是独立设置入口，没有被塞进第三方模型配置层级。
- 本轮帧采样仍不可用于判定整体流畅度：`gfxinfo reset` 前的累计摘要混入先前交互；reset 后的菜单循环/首页滑动窗口返回 0 个可用帧及 4950ms 哨兵值。它既不证明不卡顿，也不足以定位剩余随机卡顿。当前确认的是模型弹层不再等待模型 RPC；首页列表和长 transcript 的有效帧 trace 仍需独立采集，随机卡顿尚未通过全局验收。
- 验收结束后已对 `io.henry.codex` 执行 force-stop，并确认设备上没有遗留 app、worker guard、PRoot 或 Codex app-server 进程；只停止本轮进程，没有删除历史 session/workspace、没有清除 app data、没有改动 KernelSU profile。

### 2026-09-29 Release 性能与菜单续验

- 首页适配层原先每次重建时，对每张最近会话卡片线性查找整份历史，并为每个项目重复过滤会话列表。改为一次生成 session/active-snapshot 索引并单次汇总项目计数，避免历史数量增加时出现 O(n²) 重建成本；session ID、legacy history 和活动状态匹配规则保持不变。
- 定向 Flutter tests：`83/83` 通过，覆盖 `ccpocket_native_home_test.dart`、`session_history_test.dart`、`local_session_conversation_test.dart`、`custom_provider_settings_test.dart`、`ccpocket_native_session_test.dart`。Dart CLI analyzer 对首页文件退出码 0、无错误，报告 1 条既有 INFO：`SORT_CHILD_PROPERTIES_LAST`。Flutter 封装的 `flutter analyze` 曾因 analysis-server 收到截断 LSP JSON 异常退出；改用 CLI analyzer 得到有效结果。Release 构建也成功。
- 真机 `6cb21282`（120Hz）上用只在 `CODEX_FRAME_TIMING_QA=true` 时编译启用的采样器记录 build/raster/vsync/total p50/p95/p99；最终用户安装包关闭了采样器。主页首次滚动窗口：total p95 `13.494ms`、p99 `142.591ms`，`16/120` 帧超过 8ms、`5/120` 超过 16ms、`4/120` 超过 32ms，vsync p99 `49.215ms`。随后稳定滚动窗口 total p95 约 `5.76–7.05ms`，没有超过 16ms 的帧。说明冷启动/首轮交互仍有长尾，不能宣布全局随机卡顿已解决。
- thread 模型面板、进入高级设置和完整模型列表均在 250ms 取帧检查点已出现。最终普通 Release 也实测了快捷模型面板；截图：[最终 Release 模型弹层](../../artifacts/ui-smoke/20260928-menu-perf-followup/64-final-release-model-picker-20260929.png)。QA Release 上再做 10 次模型弹层开合；第一个转换窗口 total p95 `7.391ms`、p99 `31.4ms`（`2/120` 超过 16ms）；后续窗口 p95 约 `7.35–8.42ms`，没有超过 16ms 的帧，但仍有少量帧超过 8ms。这里的 250ms 是设备端固定延时后截图，不等于整段动画完成时间。
- 菜单层级复核：设置分成“设备与运行时/登录、CODEX、通用、编辑器”；CODEX 一级的“模型来源”页将 OpenAI 订阅与第三方服务商并列，第三方凭据/模型配置只在第三方子页。真机显示 OpenAI 已选、DeepSeek `已保存，未启用`；thread 当前仍显示 `6 Luna / 低`。未在本轮发送新 turn、未调用第三方 API、未读取或打印 API key。线程来源切换停止旧来源活跃 turn、让下一条消息走新来源的回归用例在 83 项测试中通过。
- 最终普通 Release：[android-codex-1.0.0-arm64-release-performance-20260929.apk](../../artifacts/release/android-codex-1.0.0-arm64-release-performance-20260929.apk)，`31,422,983` bytes，SHA-256 `888720775d938c44c62c49d5f2ccb38f8c60033e32f8c01dae09329907f9201a`。Verifier 确认 package/version、4 个 ARM64 PRoot/host assets 齐全且无旧 Bridge/Bionic Codex assets；签名是本机 QA debug certificate（不是商店签名）。已覆盖安装到真机，设备 APK hash 相同，package flags `0x0`、version `1.0.0`；data inode `1482824/1462743` 保持不变。
- 最终菜单检查沿用前述真机工作区/session/thread overflow、权限/计划与 CODEX 设置抽查；本轮再次实看来源父子页和登录、运行时、模型默认值、推理档位、审批、沙盒、MCP、主题、语言分组。仍未逐一测试每个 composer 子菜单和 Android 系统 picker。测试结束后 force-stop 本轮启动的 App，并确认没有残留 Codex/PRoot worker；没有删除 session/workspace、没有清除 app data、没有改动 KernelSU 设置。

### 2026-09-29 Provider 竞态修复与最终 Release 验收

- 修复会话级 provider 切换竞态：停止旧 app-server 期间继续记录用户最后一次来源选择（包含重新选 OpenAI）；旧进程停止后只应用最新选择，避免设置界面已切回 OpenAI、下一条 turn 仍发往第三方。新增 gated-process 回归覆盖“OpenAI → 第三方 → 停止未完成时选回 OpenAI”，断言下一次请求走 `android_openai_http` 且不携带第三方 key。
- 模型来源菜单保持在 CODEX 一级设置下，OpenAI 订阅和第三方服务商为并列项；第三方子页只负责配置供应商。子页将“已选配置”与“当前正在使用”分开显示：当前来源为 OpenAI 时用书签图标标记已保存配置，并明确写出“当前使用 OpenAI”，避免误认为 provider 已生效。真机来源/子页证据见 `artifacts/ui-smoke/20260929-menu-audit/15-final-model-source.png`、`20-final-installed-provider.png`。
- `local_session_conversation_test.dart`、`custom_provider_settings_test.dart`、`ccpocket_native_session_test.dart` 及相关 home/history 测试定向组在来源竞态修复后 `84/84` 通过；provider 子页指示器改动后的 `custom_provider_settings_test.dart` `5/5` 通过。没有发送第三方请求，也未读取、展示或记录 API key。
- 最终普通 Release APK：[`android-codex-1.0.0-arm64-release-provider-source-20260929.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-provider-source-20260929.apk)，`31,420,991` bytes，SHA-256 `2E3D5F27CF577604E28BB56C19B396C8F8240F757D27BCD70676197068575E6C`。Verifier 已通过；包为 `io.henry.codex`、版本 `1.0.0`、`flags=0x0`（不可调试 Release），含 4 个 ARM64 PRoot/host assets。签名仍为本机 QA debug certificate，不是商店签名。真机安装 APK 的 SHA-256 与产物一致；覆盖安装前后 app data inode `1482824/1462743` 未变。
- 在此最终 Release 的真实 thread 中，模型弹层截图在注入点击后 250ms 检查点已经可见：[真机模型弹层](../../artifacts/ui-smoke/20260929-menu-audit/22-final-release-popup-250ms.png)。本次没有复现“点击后等待五秒”的模型弹层故障；截图检查点不是完整动画帧率测量，也不能证明所有设备状态下都不存在延迟。点击返回后已停止本轮打开的 App/thread，确认没有遗留 `io.henry.codex`、worker guard、PRoot 或 app-server 进程；workspace/session 与 app data 均保留。
- 全局随机卡顿仍未解决/验收通过：此前有效采样仍显示首页首次滚动有长尾（total p99 `142.591ms`，`4/120` 帧超过 `32ms`），尽管后续稳定窗口与模型菜单开合更顺畅。当前只能确认这次 Release 的模型弹层快速出现，以及首页重建已由重复全量查找改为一次建索引；长 transcript、冷启动首轮交互及跨页面随机卡顿还需有效帧采样和针对性优化，不能以 Release 构建成功替代。

### 2026-09-29 长回复渲染优化与最终安装

- 代码检查发现另一处可复现的渲染复杂度热点：每个 app-server assistant delta 都会刷新当前 thread，而 `StreamingBubble` 原先对增长中的整段响应重新构建 `MarkdownBody`。超过 2,048 个字符后，活动流改用轻量 `Text` 预览，避免每帧解析越来越大的 Markdown 文档；turn 完成后仍走原有完整 CC Pocket Markdown 渲染与链接/消息操作。新增 widget 回归确认长流走轻量路径。
- 格式化后运行 `flutter test --no-pub test/ccpocket_native_session_test.dart`：`24/24` 通过，其中包含新增长回复预览用例、长历史 ListView 虚拟化及模型设置菜单用例。
- 最新普通 Release：[android-codex-1.0.0-arm64-release-streaming-preview-20260929.apk](../../artifacts/release/android-codex-1.0.0-arm64-release-streaming-preview-20260929.apk)，`31,421,975` bytes，SHA-256 `E139D85C76D683B2EB822E1D79B41195335172410670C433897A6F4326F1DF47`。APK verifier 通过：签名有效、包名/版本正确、4 个 ARM64 runtime assets 齐全、无禁止资产；仍以本机 QA debug certificate 签名，非商店签名。
- 已覆盖安装到真机 `6cb21282`。设备 `base.apk` SHA 与产物一致、`flags=0x0`、版本 `1.0.0`；安装前后 app data inode 均为 `1482824/1462743`，session/workspace 数据保留。最终 Release 的模型弹层实机截图：[800ms 检查点](../../artifacts/ui-smoke/20260929-menu-audit/26-final-release-popup-state.png)。未发送新 turn，也未调用第三方 API。
- 测试后已 force-stop App 并核实没有 `io.henry.codex`、worker guard、PRoot 或 app-server 进程。长流优化是针对已定位的 Markdown 重解析热点，不代表所有随机卡顿已消失；尚需对冷启动、长 transcript 滚动和真实流式长回复做有效 Release 帧采样，再按采样定位后续热点。
- 另以 `CODEX_FRAME_TIMING_QA=true` 构建并临时安装 Release 采样包（非 Debug、`flags=0x0`），在真机做首页滚动与 6 次 thread 模型弹层开合，随后重新安装上方无采样正式 Release。启动/首轮交互窗口为 total p95 `10.510ms`、p99 `54.037ms`，`4/120` 帧 >32ms；其 raster p99 `20.134ms`、vsync p99 `37.250ms`、build p99 `6.028ms`。后续两个稳定首页窗口 p99 `10.501ms`、`6.567ms`，没有 >16ms 帧。首次进入 thread 的混合窗口 p99 `41.466ms`（`2/120` 帧 >32ms），不能单独归因于模型弹层。
- 稳定状态下模型面板连续开合的 5 个 120 帧窗口，total p99 依次约 `14.923/11.033/8.233/10.144/9.331ms`；只有首个窗口有 1 帧 >16ms，后 4 个均无 >16ms 帧，5 个均无 >32ms 帧。Release 采样截图显示快捷模型面板在约 800ms 检查点已打开：[模型弹层](../../artifacts/ui-smoke/20260929-menu-audit/28-release-qa-model-popup.png)。采样窗口按操作序列取得，不能完全将首轮长尾归到某个单一 UI 事件。
- 已恢复安装普通 Release 并复核设备 APK SHA-256 `E139D85C76D683B2EB822E1D79B41195335172410670C433897A6F4326F1DF47`、数据 inode `1482824/1462743`。最后再次 force-stop，设备无 App、worker、PRoot 或 app-server 进程。

### 2026-09-29 当前 Release 真机模型菜单与会话停止复核

- 当前安装包为普通 Flutter Release：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`，31,430,991 bytes，SHA-256 `6F5AE6809C6A7923C07E78B608813CE96373BFD78D00E251D49B0DBDEAAD4B08`。真机 `6cb21282` 的 `base.apk` SHA 完全一致，`versionName=1.0.0`、`flags=0x0`，不是 Debug variant；签名仍是本机 QA debug certificate（不是商店签名）。
- 从真实 thread 点模型控件后，固定等待 300ms 再截图时快捷面板已经可见；继续进入高级设置、模型子菜单，目录包含 `6 Astra`、`6 Sol`、`6 Luna`、`Reserve`、5.6 与 5.5 系列。实际临时选择 `6 Sol` 后界面立即反映新值，再切回并核对 `6 Luna / low`；没有发送 turn。截图：[模型快捷面板](../../artifacts/ui-smoke/20260929-menu-audit/30-current-release-model-popup-350ms.png)、[完整模型列表](../../artifacts/ui-smoke/20260929-menu-audit/31-current-release-model-list.png)。这证明该 Release 上没有复现每次等待五秒的 popup 故障，且选择回调生效；不代表全局帧率通过。
- 本轮 `dumpsys gfxinfo` 在 reset 后未捕获 Flutter SurfaceView 可用帧（返回 0 帧/4950ms 哨兵），因此不把它作为性能结论。可用的先前 QA Release 采样仍显示冷启动/首次首页滚动长尾：p99 `142.591ms`，`4/120` 帧超过 `32ms`；全局随机卡顿没有验收通过。模型菜单响应局部通过，冷启动、首页滚动、长 transcript 和跨页面随机卡顿仍需基于 Flutter 帧时序继续定位。
- 菜单层级沿用并复核：Settings → CODEX → 模型来源；OpenAI 订阅和第三方服务商并列，第三方配置独立为子页；thread 快捷设置 → 高级 → 模型/推理强度。OpenAI/第三方切换后的真实 turn 路由、DeepSeek 与 OpenAI marker turn 以及历史不迁移提示见本轮修复记录。其他 composer 子菜单与 Android 系统 picker 尚未逐项完整验收。
- 本次再从设置首页逐层实机打开“模型来源”和“第三方服务商配置”：OpenAI radio 为已选，DeepSeek 只标记为“已选配置，当前使用 OpenAI”；第三方配置页明确说明仅编辑 provider，不负责切换来源。进入设置和这些子页未触发 Root approval。Codex 默认模型/档位仍为 `gpt-6-luna / low`，默认审批“从不审批”、沙盒“完全访问”。
- thread 级“计划”控件实机切到开启后再关闭，界面状态即时变化并恢复原值；Root 写入策略菜单实际显示 Root 常规、完全访问、只读（应用级）三项与软路由说明，没有选择其他权限级别。手动点击已停止的历史 thread 会按现有产品行为恢复它；应用启动时是否自动恢复仍由持久化 stopped 状态决定。随即使用 thread 内 Stop，worker/PRoot/app-server 退出而 App 保持前台。
- 点按会话内“停止会话”后，等待两秒确认没有 `codex_worker_guard`、PRoot、Node 或 Codex app-server 进程；Android App 自身保持前台。只停止本轮由开发测试启动的 worker，没有删除 session/workspace、清除 app data 或改 KernelSU 设置。

### 2026-09-29 首次模型弹层阻塞定位与 Release 复验

- 冷启动 QA Release 上复现：点 thread 顶部模型控件，首个约 250ms 检查点尚无弹层；约 5.25 秒后才出现。追到目录加载会调用 Android MethodChannel 启动一次性 Codex/PRoot 命令；`MainActivity` 原先把 `CompatibilityProcessManager.start()` 和 App UID 的 `HostProcessManager.start()` 同步执行在 Activity 主线程。PRoot start 还会准备 rootfs 挂载点、session home、证书与网络环境，启动延迟期间 Android UI 无法绘制。
- 将 compatibility 与 host 两条 `startProcess` 通道的进程准备/启动移到后台线程，成功和错误结果仍回到 UI 线程交给原有 Dart backend；session/worker 所有权与 stop 语义不变。相关入口位于 `apps/codex/android/app/src/main/kotlin/io/henry/codex/MainActivity.kt`。
- 补丁后的 QA Release 中，点击模型控件后首个 250ms 检查点已能看到弹层和目录加载指示；目录加载期间打开“高级”及模型子菜单也正常，完整列表包含 `6 Astra`、`6 Sol`、`6 Luna`、`Reserve`、5.6 与 5.5 系列。最终普通 Release 再验，首个 250ms 检查点弹层可见；tap-to-screenshot 主机耗时约 958ms，含 ADB 和截图往返，不能当作真实点击延迟。模型最终保持 `6 Luna / low`。对应图：[最终普通 Release 模型弹层](../../artifacts/ui-smoke/20260929-menu-audit/40-final-release-picker-250ms.png)、[完整模型目录](../../artifacts/ui-smoke/20260929-menu-audit/31-postpatch-models-250ms.png)。
- `local_ui_navigation_test.dart` 与 `local_session_conversation_test.dart` 共 `35/35` 通过；其中包含所有打开 session 同步 provider 来源、显式 OpenAI 覆盖历史第三方 provider 的回归。真机设置页实际切换 OpenAI → DeepSeek → OpenAI，最终 OpenAI 选中且 DeepSeek 配置保留；没有发出网络请求或使用/显示 API key。来源层级确认是 Settings → CODEX → 模型来源；OpenAI 与第三方并列，第三方配置是其下独立配置入口，而不是将 OpenAI 放进“第三方模型配置”。[OpenAI 恢复后的来源页](../../artifacts/ui-smoke/20260929-menu-audit/37-source-openai-restored.png)
- 普通 Release 的设置菜单也逐项点开并验证可选项：新会话默认推理强度、审批、沙盒，通用主题和语言。临时将 effort 设为“中”、approval 设为“失败时审批”、sandbox 设为“工作区可写”、theme 设为“浅色”、language 设为 English，随后逐项恢复并读取确认最终为 `low / 从不审批 / 完全访问 / 跟随系统 / 简体中文`；本轮没有留下设置变更。
- 构建 QA Release（`CODEX_FRAME_TIMING_QA=true`）的首个 120 帧窗口记录 `10/120` 帧超过 8ms、`7/120` 超过 16ms、`3/120` 超过 32ms，total p99 `60.266ms`；之后若干模型菜单窗口为 `0/120` 超过 8ms。设置导航/切换窗口仍分别出现 `20/120`、`14/120` 帧超过 8ms。采样与 ADB 截图/UIAutomator 操作重叠，无法将这些长帧精确归因到某个 widget；全局随机卡顿仍未通过验收。
- 最终普通 Release 使用 `tools/build-android.ps1 -Mode release` 构建，APK `31,432,083` bytes、SHA-256 `3CEFEF98D8A76A6758CBEAE5CC39F0BC2F73AB4F128F5EE38F638C038BE105DF`。Verifier 确认签名有效、4 个 ARM64 PRoot/host assets 齐全；安装到 `6cb21282` 后 `versionName=1.0.0`、`flags=0x0`。签名为本机 QA debug certificate，不是商店签名；`adb install -r` 保留 app data。归档：[最终普通 Release APK](../../artifacts/release/android-codex-1.0.0-arm64-release-mainthread-fix-20260929.apk)。
- 结论：模型弹层的五秒 UI 冻结已修复并在普通 Release 真机通过首屏响应复验；目录仍可后台加载。随机长帧尚存，首页冷启动、设置滚动与其他页面仍需无截图干扰的帧级采样；composer 子菜单和 Android 系统 picker 尚未全部逐项验收。此次没有清理 session/workspace 或改动 KernelSU 配置。

### 2026-09-29 后台 I/O 与首页工作区操作 Release 复验

- `SESSION_HISTORY_CHANNEL` 和宿主文件/SAF 使用的 `LOCAL_BACKEND_CHANNEL` 改为串行后台 task queue，避免历史 JSON、workspace/SAF 查询与文件读写占用 Android UI 线程；SAF picker 和 session foreground service / notification permission 操作仍显式回到 Activity 主线程。Codex/PRoot 进程启动仍由既有后台线程处理。
- 真机发现首页“添加”会随刚打开的历史 thread 改变执行后端而静默 no-op：本地工作区入口错误地只接受当前 backend 为 `LocalAndroidBackend`。现在从设备 backend selector 始终取得宿主存储 backend；创建工作区同样修正，删除时把兼容后端引用转换为宿主 workspace 引用后仍经过原有确认。只验证删除路径代码，未实际删除任何 workspace。
- QA Release 安装后从 thread 返回首页，点击“添加”成功打开 Android DocumentsUI；普通 Release 再次实测也成功打开。均只按返回取消，没有选择目录或改文件。证据：[普通 Release picker](../../artifacts/ui-smoke/20260929-menu-audit/84-final-release-saf-picker.png)。
- 普通 Release thread 模型弹层在点击后的 250ms 截图检查点已经出现，保持 `6 Luna / low`：[弹层](../../artifacts/ui-smoke/20260929-menu-audit/83-final-ordinary-release-model-popup.png)。这是快速出现的设备检查点，不是完整动画的逐帧时延证明。
- 普通 Release 设置来源页实看 OpenAI 订阅为当前选择，DeepSeek 只作为已保存配置；QA Release 实际切换到第三方再切回 OpenAI，最后 OpenAI 选中且 DeepSeek 配置仍保存。没有发请求、没有读取或展示 key。证据：[普通 Release 来源页](../../artifacts/ui-smoke/20260929-menu-audit/85-final-release-model-source.png)。
- 真机菜单抽查：工作区总菜单含“创建本地工作区/刷新列表”，workspace 单卡菜单含“开始新会话/浏览文件/删除本地工作区”；打开删除确认后按返回取消，没有执行删除。[总菜单](../../artifacts/ui-smoke/20260929-menu-audit/86-workspace-actions-menu.png)、[单卡菜单](../../artifacts/ui-smoke/20260929-menu-audit/89-workspace-card-actions.png)、[删除确认](../../artifacts/ui-smoke/20260929-menu-audit/90-delete-workspace-confirm.png)。
- 重新清空 logcat 后，在 QA Release 上不截屏采样滚动：进程启动后首页首个滚动 120 帧 total p50/p95/p99 `4.075/11.214/71.378ms`，`11/120` 超过 8ms、`5/120` 超过 16ms、`5/120` 超过 32ms；build/raster/vsync p99 分别 `6.541/45.032/38.313ms`，长尾偏 raster/vsync 而非 build。接下来两个首页窗口 total p95/p99 为 `6.424/7.819ms` 与 `5.832/7.977ms`，均无 >16ms 帧。设置页两个窗口 total p95/p99 为 `8.823/16.325ms` 与 `8.718/13.599ms`，分别有 `3/120`、`1/120` 帧超过 16ms，无 >32ms 帧；设置长尾主要表现为 build p99 `8.929–10.979ms`。这些是有限的 120Hz 手机窗口，随机长帧仍未全局验收通过。
- 定向 Flutter 测试 `local_ui_navigation_test.dart`、`local_session_conversation_test.dart`、`home_host_access_widget_test.dart`：`36/36` 通过。最终普通 Release verifier 通过，APK `31,432,015` bytes、SHA-256 `DE85A9F76002CE42922591B79168FFD3CF19CF68BA9611EEC8CD2FDD4AF6A340`；package `io.henry.codex`、version `1.0.0`、`flags=0x0`，4 个 ARM64 PRoot/host assets 齐全。已 `adb install -r` 覆盖安装到 `6cb21282`，设备 `base.apk` hash 与产物一致；工作区与历史会话仍可见。签名为本机 QA debug certificate，不是商店签名。
- 首页抽查仍看到最近会话卡片重复展示会话名与 workspace 标签，且一些历史条目标题为“（无描述）”；记为后续 UI 信息密度/标题生成验收项，没有在本轮扩展改动。composer 子菜单、长 transcript、多页面冷启动帧时延以及旧 Bridge/旧 UI/旧 runtime 清理仍未完成；总体 goal 保持 active。帧采样结束后又覆盖安装了上述普通 Release，设备 `base.apk` SHA 与归档一致，`flags=0x0`；当前只运行 Android App，无 worker/PRoot/app-server。

### 2026-09-29 模型目录缓存、来源菜单与追加帧采样

- 为 OpenAI CLI 模型目录增加轻量持久缓存，按 CLI 版本和 runtime 标识校验；仅保存模型 id、展示名、推理档位和隐藏状态，不保存 auth/API key。CLI 版本变化或缓存损坏时回退到 Codex 权威目录加载；第三方 provider 不使用 OpenAI CLI 缓存。
- 设置改为“模型提供方”父菜单：OpenAI 订阅与第三方 API 是并列且互斥的来源；第三方配置入口缩进放在第三方卡片内。子页只管理已保存的第三方配置，不会暗中改变当前来源。真机 Release 层级证据：[来源父菜单](../../artifacts/ui-smoke/20260929-perf-followup/79-provider-parent-release.png)、[第三方配置子页](../../artifacts/ui-smoke/20260929-perf-followup/80-provider-config-child.png)。切回 OpenAI 后同一历史 thread 的真实 turn 使用 `android_openai_http` 并返回指定 marker；本轮没有复现继续走 DeepSeek 的路由错误。
- 定向 Flutter 测试 `codex_model_catalog_cache_test.dart`、`custom_provider_settings_test.dart`、`local_ui_navigation_test.dart`：`14/14` 通过。普通 Release 已安装；停止会话后重新打开模型目录，缓存列表在固定 250ms 检查点可见，进程表只有 App，没有 PRoot/Node/app-server：[无 worker 的缓存模型列表](../../artifacts/ui-smoke/20260929-perf-followup/90-cached-model-list-stopped-session-250ms.png)。QA Release 在活跃 thread 中点开完整目录，同样在 250ms 检查点显示 `6 Astra/Sol/Luna`、Reserve、5.6、5.5：[thread 模型目录](../../artifacts/ui-smoke/20260929-perf-followup/101-model-catalog-250ms.png)。该检查是固定延迟屏幕快照，不等同逐帧动画测量。
- 额外 QA 构建仍是 Release variant（`flags=0x0`），只启用帧计时日志。首页手势滚动采样 6×120 帧：合计 `14/720` 帧超过 8ms、`4/720` 超过 16ms、`3/720` 超过 32ms；首个窗口 p99 `48.292ms`，后续 5 个暖机窗口均无 >16ms 帧。设置滚动 6×120 帧：`28/720` 超过 8ms、`1/720` 超过 16ms、无 >32ms 帧。thread 模型目录窗口 `12/120` 超过 8ms、`1/120` 超过 16ms、无 >32ms。样本来自 120Hz 真机且首轮含进页/启动长尾；它们说明弹层阻塞已解决，但首页冷/首屏长尾仍存在，整体随机卡顿不能标记完成。
- 当前普通 Release 已重新覆盖安装，已保存用户数据；产物 `artifacts/release/android-codex-1.0.0-arm64-release-model-catalog-provider-menu-20260929.apk`（31,443,615 bytes），SHA-256 `BC81A3A9A4B2482F85CC17FB3F699B6BD637F86A2E6232AB972152AC11277903`，`run-as io.henry.codex` 返回 `package not debuggable`。QA 帧计时版本未留在手机上。
- 此次菜单抽查仅覆盖 provider 父子层级、thread 模型选择与先前记录的权限/会话溢出菜单；不代表整个 app 所有菜单均已逐项验收。首页冷启动/首轮滚动长尾、长 transcript、composer 子菜单、其他设置子路径以及旧 Bridge/旧 UI/旧 runtime 清理仍待继续。

### 2026-09-29 最新 thread 布局补丁后的 Release 帧样本

- 在普通 Release 上做了 6 组首页上下滚动，用仅开启 `CODEX_FRAME_TIMING_QA=true` 的 Release 采样包收集 13 个 120 帧窗口；采样期间没有截图或 UIAutomator 抓取。首个滚动窗口 build/raster/vsync/total p99 为 `7.130/14.872/37.190/72.024ms`，`6/120` 帧 >8ms、`3/120` 帧 >16ms 且 >32ms。之后 12 个窗口均没有 >16ms 帧（也没有 >32ms 帧），total p99 最高 `8.967ms`。首窗长尾不等于已找到根因：build p99 较低，raster/vsync 长尾更明显；首轮列表/纹理/raster 与系统调度仍需进一步定位。
- 采样 APK `artifacts/qa/android-codex-1.0.0-arm64-release-frame-qa-20260929.apk`，31,453,391 bytes，SHA-256 `4DFB9EED9CA9FCDA3A2E4F5640B7554BDFF2648B15C00AC089342F42C2F52B32`；它是 `flags=0x0` 的 Release QA variant，不是 Debug。帧样本后重新安装普通 Release `artifacts/release/android-codex-1.0.0-arm64-release-stable-thread-controls-20260929.apk`，设备 APK SHA 与归档完全一致；应用数据 inode `1482824/1462743` 保持不变。
- 最终手机前台为 Codex，只有 Android App 进程，没有 worker guard、PRoot、Node 或 app-server。全局“随机卡顿”仍不能判定完成；当前可复现/可量化的是首个滚动窗口长尾，重复滚动趋稳。后续应继续围绕首轮 raster/vsync 和长 transcript 取样，不把一次暖机后的平滑误当成全局通过。

### 2026-09-29 Release 菜单交互审查与首页 FAB 遮挡修复

- 本轮真机截图审查覆盖：Home 工作区/最近会话、设置运行时与 Codex 分组、模型来源父子页、第三方/OpenAI 来源往返、thread 模型快捷/高级/完整列表、计划与 Root 菜单、thread overflow、workspace header/card actions、项目过滤菜单。审查记录和逐步截图位于 `artifacts/ui-audit/20260929-menu-hierarchy/REPORT.md`。
- 源选择层级正确：CODEX → 模型来源；OpenAI 订阅与第三方服务商平级，第三方配置仅位于第三方卡片内。配置子页明确说明不会替用户切来源，并显示“已选配置，当前使用 OpenAI”。真机无 API 请求；切换 DeepSeek 后 UI 标记“当前启用”，再切回 OpenAI 恢复原状态。
- 真实 thread 中额度与 context 用量到达前后，模型、计划、Root 控件的语义 bounds 均保持不变：`[349,739][607,907]`、`[611,739][858,907]`、`[861,739][1091,907]`。模型快捷弹层在固定 250ms 截图检查点已出现；计划可开/关往返，Root 写入策略菜单正常展开。Root 菜单未选择新策略；会话经应用内 Stop 结束，worker/PRoot/Node/app-server 退出，历史保留。
- 视觉检查发现 Home 末尾会话卡片在滚动到底后仍被外层“新建”FAB覆盖（当时卡片 bounds `[2805,3130]` 与 FAB `[1047,2948][1384,3144]` 重叠）。现在复用的 CC Pocket `HomeContent` 支持可选 `bottomContentInset`，Codex 外壳传入 88dp，最后一张卡片可完整停在按钮上方。`ccpocket_native_home_test.dart` `8/8` 通过；Release 真机滚到末尾截图确认遮挡消失，见 `10-home-end-before.png` 与 `11-home-end-after.png`。
- 新普通 Release：[android-codex-1.0.0-arm64-release-home-scroll-inset-20260929.apk](../../artifacts/release/android-codex-1.0.0-arm64-release-home-scroll-inset-20260929.apk)，31,447,367 bytes，SHA-256 `2DFAF878CF0214CEB28095A9D00FB0C75ED244A8031B32466A52B4FA1494318A`。Verifier 通过；真机覆盖安装 hash 一致，`flags=0x0`、`run-as` 报 `package not debuggable`，应用数据 inode 不变。本机 QA certificate 签名，不是商店签名。
- 帧表现仍有未完成项：最新布局版的 QA Release 首次滚动窗口 `3/120` 帧 >32ms、total p99 `72.024ms`，之后 12 窗无 >16ms 帧。因果方向仍指向首轮 raster/vsync 长尾，不能宣称随机卡顿已整体解决。其余 composer 子菜单、个别设置项与系统 picker 仍未全量逐项验收；旧 Bridge/旧 UI/旧 runtime 清理未开始。

### 2026-09-29 Thread 控件稳定布局与来源切换 Release 复验

- 定位到 thread 顶部模型/计划/Root 控件偶发位移：账号额度摘要和 token context 摘要会异步出现，原来会改变控件上方布局高度。现在为额度和 context 摘要保留固定高度槽位。新增 widget 回归在真实 `thread/tokenUsage/updated` fixture 到达前后比较模型控件几何位置，断言不再跳动；相关会话测试 `30/30` 通过。真机两个采样截图中控件位置一致，但当时旧 thread 的 app-server 已过期、未收到新的 usage 事件，不能把这两张图当作设备端 usage 更新的独立证明。
- Android `MainActivity` 中 `stopProcess` 和 `stopHostProcess` 原先同步执行进程停止，可能让 stop/来源切换等待期间占用 UI 线程；已改为后台线程停止，结果再回 UI 线程。来源切换 UI 在 250ms 固定检查点已更新；本轮启动的 worker 在 4 秒内退出，进程检查未发现遗留 worker。模型弹层/完整目录在普通 Release 固定 250ms 检查点可见。
- 来源菜单标题统一为“模型来源”；OpenAI 订阅与第三方配置作为同级来源，第三方配置页明确为配置子页、不承担来源切换。父子菜单与 thread 入口测试 `10/10`，冷目录加载菜单测试 `1/1`；真机完成 OpenAI → 第三方 → OpenAI 后，关闭并重启 App 再检查仍选中 OpenAI，DeepSeek 配置保留且未启用。本轮未发 provider API 请求。
- 最终普通 Release：[android-codex-1.0.0-arm64-release-stable-thread-controls-20260929.apk](../../artifacts/release/android-codex-1.0.0-arm64-release-stable-thread-controls-20260929.apk)，31,444,371 bytes，SHA-256 `FC49429CBFF3E06838ECA13C4EE8CA0DA4CBA209F611ECC229C77772A324E68`。APK verifier 通过；真机安装包 hash 一致、`flags=0x0` 且 `package not debuggable`，既有应用数据 inode 保持不变。使用普通 Release variant，签名是本机 QA certificate，非商店签名。
- 本轮结束后已停止由开发测试启动的 Codex worker，真机仅剩 App 进程；session/workspace 历史、应用数据未删除。全局随机卡顿仍未验收通过；首页首轮长尾、长 transcript、composer 子菜单和其他页面/菜单仍待针对性采样与交互验收。旧 Bridge/旧 UI/旧 runtime 清理也未完成。

### 2026-09-29 thread 模型入口和 composer 菜单续测

- 普通 Release 的 thread 模型 chip 首次打开现在直接显示模型行与 effort 行。Flutter 冷目录测试在 250ms widget 检查点确认弹层/模型行已见，CLI 模型目录继续异步加载；真机检查也在显式等待 250ms 后看到了首屏，再点模型行可进入完整动态目录。当前没有复现 5 秒模型菜单等待，但这不是对任意设备状态的全局性能证明。
- 本次菜单路径只采集交互截图与语义层级，没有给当前普通 Release 加帧计时插桩；主机端 ADB tap-to-capture 的总耗时包含工具往返，不能当作应用延迟。
- 全局随机长帧仍未通过：现有无截图干扰 QA Release 样本显示首页冷/首轮滚动 `3/120` 帧超过 32ms、total p99 `72.024ms`，后续暖机滚动无 >16ms 帧；raster/vsync 长尾仍待定位。settings、长 transcript、首启冷状态的帧级测量继续未完成。
- composer 本轮确认 slash 命令列表可见、`@` 是输入前缀、历史项只回填以及图片入口交给 Android picker；picker 只打开后取消，未挑选图片，因此不属于附件真实 turn 验收。

### 2026-09-29 设置页能力探测复用与首帧长尾复测

- 设置页原先在 App 启动/恢复时已有一次 Linux/PRoot `/usr/bin/true` 能力探测的同时，进设置又无条件新开一次 guest probe。现在设置页复用最近的 probe Future；App 启动、恢复和“刷新本地能力”仍会启动新探测，不改变 Root 会话授权语义。相关改动在 `apps/codex/lib/main.dart` 与 `apps/codex/lib/backends/compatibility/linux_compatibility_backend.dart`。
- 定向 Flutter 回归：`local_session_auth_test.dart`、`custom_provider_settings_test.dart`、`local_ui_navigation_test.dart`、`ccpocket_native_session_test.dart` 共 `38/38` 通过。单测另外发现窄测试视口下空会话欢迎态溢出 20px；将欢迎态内边距从 32dp 收到 16dp 后，该 Root 授权用例单独重跑通过。
- 帧采样使用 Release QA（非 Debug）真机 `6cb21282`，屏幕 1440×3200。首个混合启动/进入设置/滚动窗口 total p99 `77.231ms`，`3/120` 帧 >32ms，build/raster/vsync p99 为 `6.569/27.441/44.026ms`。后续三个窗口 total p99 `6.772/6.190/5.480ms`，均无 >16ms 帧。
- 第二次设置页进入与滚动的首个混合窗口 total p99 `64.190ms`，`10/120` 帧 >16ms、`3/120` >32ms；build/raster/vsync p99 `27.128/14.377/42.959ms`。之后两个窗口 p99 `13.498/14.133ms`，分别 `1/120` 与 `0/120` 帧 >16ms。说明启动/首轮交互仍有明显长尾；后续窗口多数稳定。操作窗口包含页面转场与手势，不能把峰值归因于某个单一设置控件；性能优化仍未通过全局验收。
- 初始设置页固定检查点正常显示运行时状态与“已登录”，打开设置本身没有弹出 Root approval（截图 `112-qa-settings-after-entry.png`）；对应的设置/帧采样阶段尚未启动真实 turn，也没有调用第三方 API。后续的真实 OpenAI turn 单独按 session 展示的 Root 授权流程启动并已停止。相关证据均位于 `artifacts/ui-smoke/20260929-perf-followup/`。
- 在刚安装的普通 Release 上，从已停止的历史 thread 打开模型快捷设置，固定 250ms 检查点已显示“模型 / 推理强度”行（截图 `114-final-release-model-popup-250ms.png`）；过程没有启动 worker/PRoot/app-server。OpenAI/第三方切换回归本轮通过 Flutter tests，但没有重复调用真实第三方 API。
- 随后在同一普通 Release 真机上创建测试会话，模型面板连续 4 次在点击后 250ms 截图点可见；再发送真实 OpenAI `gpt-6-luna / low` turn，收到精确标记 `ACTIVE_MODEL_MENU_QA_OK`，会话页的模型面板仍在 250ms 检查点显示，额度和 context 摘要也出现。该次 turn 已通过会话内 Stop 停止；检查只剩 Codex App 进程，没有 worker guard、PRoot、Node 或 app-server。证据截图 `119-new-session-model-sheet-250ms.png`、`120-model-sheet-repeat-*.png`、`127-real-turn-start.png`、`130-active-turn-model-sheet-250ms.png`、`131-real-turn-stopped.png`。本轮未调用第三方 API；模型弹层检查发生在真实回复完成后，不代表对正在持续 token stream 时的性能已验收。
- composer/media 补测：会话命令 sheet 可打开；`@` 快捷键按设计插入输入前缀；Android 安全文件选择器可返回图片。为真实验证上传，只从本轮空白 UI 截图生成临时图片并选中，真实 OpenAI turn 准确描述了截图且返回 `IMAGE_UPLOAD_QA_OK`。发图过程中再次打开模型 sheet，250ms 检查点可见。测试图片 `/sdcard/Pictures/android-codex-qa-image.png` 已精确删除；Stop 后 worker/PRoot/Node/app-server 均退出。证据为 `132-slash-menu.png`、`133-android-image-picker.png`、`136-image-picker-selected.png`、`138-image-upload-prompt-ready.png`、`141-image-turn-result-check.png`。本轮没有从手机原有照片中选择或上传文件。仍未验证 `@` 后续候选项选择、所有 slash 命令逐一执行以及长 token stream 中的模型切换。
- 最新无 QA 插桩普通 ARM64 Release：[android-codex-1.0.0-arm64-release-settings-probe-cache-20260929.apk](../../artifacts/release/android-codex-1.0.0-arm64-release-settings-probe-cache-20260929.apk)，31,447,579 bytes，SHA-256 `0D15C0CF2D9392CCE81E1C083EDBEDA1DFD0FBFE658520A8AED70F8146E8447C`。APK verifier 确认签名与 ARM64 runtime assets 正常；已 `adb install -r` 安装真机，设备 APK hash 一致，`run-as` 显示 package not debuggable。应用数据保留，手机前台为 Codex，仅有 App 主进程；没有 worker、PRoot、Node 或 app-server。签名仍为本机 Android debug certificate，不是商店签名。
- 同步采集 Perfetto 8 秒系统 trace 并用 Trace Processor 查询 FrameTimeline：22 条帧记录只归属 SurfaceFlinger/SystemUI，缺少 `io.henry.codex` 可归因的 app-layer 帧轨迹；SurfaceFlinger 有最大 26.21ms 的 `CPU Deadline Missed`，另见 Display HAL 约 18.31ms 与 system_server power-whitelist broadcast 约 67.12ms。它说明设备合成/系统负载与卡顿窗口重叠，但 trace 不足以证明系统是唯一根因，也不足以排除 Flutter raster/vsync 问题。原始 trace：`artifacts/ui-smoke/20260929-perf-followup/115-settings-jank-perfetto.pftrace`，1,833,295 bytes，SHA-256 `3D4FA6DD661FC03B1C0D96D85BE12B8087B4F1F14513ACF0904A7241B4DB15E2`。
- 尚未定位首轮 Flutter build/vsync 长尾的最终根因；全局随机卡顿、剩余页面/菜单的交互验收及旧 Bridge/旧 UI/旧 runtime 清理仍未完成，总体 goal 保持 active。

### 2026-09-29 普通 Release 模型弹层与 provider 往返真实 turn

- 真机仍运行普通 ARM64 Release：`artifacts/release/android-codex-1.0.0-arm64-release-settings-probe-cache-20260929.apk`，SHA-256 `0D15C0CF2D9392CCE81E1C083EDBEDA1DFD0FBFE658520A8AED70F8146E8447C`；设备包 `versionName=1.0.0`、`flags=0x0`，应用数据 inode `1482824/1462743` 未变。不是 Debug 包；签名仍为本机 QA certificate，非商店签名。
- 从 thread 打开模型快捷面板、再进入完整模型列表，均在各自点击后固定 250ms 检查点可见，列表含 `6 Astra / 6 Sol / 6 Luna / Reserve / 5.6 / 5.5`。本次没有复现 5 秒弹层等待；250ms 截图点不是完整动画/帧时延测量。截图：`149-provider-current.png`、`169-model-menu-open-250ms.png`、`170-model-list-open-250ms.png`。
- 普通 Release 真机真实来源往返：在“模型来源”父页启用已保存的 DeepSeek 配置，真实 turn 返回精确 `DEEPSEEK_CURRENT_RELEASE_OK`；随后选择 OpenAI 订阅，页面显示第三方已配置但未启用。新 session 使用 `6 Luna / low` 并返回 `OPENAI_AFTER_DEEPSEEK_OK`。再重开此前的 DeepSeek session，历史保留且出现“模型来源已切换”记录；该旧 session 的下一条新 turn 同样使用 `6 Luna / low`，返回精确 `OPENAI_IN_REOPENED_THREAD_OK`。这验证来源切换不仅更新单选状态，也覆盖此前第三方 session 的后续新 thread。证据截图 `145-provider-source-parent.png`、`146-third-party-selected.png`、`151-deepseek-turn-result.png`/`156-app-refocused.png`、`161-openai-source-selected.png`、`167-openai-turn-18s.png`、`173-reopen-deepseek-thread-after-openai.png`、`177-openai-reopened-thread-32s.png`。
- 第三方配置只在 OpenAI 未选用时保持保存；切回 OpenAI 后没有再使用第三方路径。未读取、复制或展示 API key。测试用 session 历史保留；所有本轮测试 Codex worker 均通过 App 停止，最终 `ps` 未发现 worker guard、PRoot、Node 或 app-server；没有删除 workspace/session 或清空 App 数据。
- 模型入口与 provider 行为的设备局部验收通过；随机卡顿仍未全局通过。前序 Release 帧样本存在首页/设置首轮长尾，Perfetto 只能看到与系统合成负载重叠而不能归因唯一根因；后续继续做页面定向长帧采样和优化。

### 2026-09-29 设置首屏构建优化与最终普通 Release

- `apps/codex/lib/ccpocket_local_settings.dart` 将屏幕外的 Codex、通用、编辑器、Root、关于和网络设置卡片改为进入列表视口时构建；布局及动作不变。定向设置/导航测试 `20/20` 通过。
- QA Release（仅用于帧采样，`CODEX_FRAME_TIMING_QA=true`，设备包仍为 `flags=0x0`）重复热进入设置的两个 120 帧窗口 total p99 为 `11.799ms`、`14.747ms`，均无 `>32ms` 帧。滚动设置页的 7 个窗口 total p99 在 `5.365–16.165ms`；6 个窗口无 `>32ms` 帧，另 1 个窗口为 `1/120` 帧 `>32ms`。首次跨页混合窗口仍有长尾（total p99 `77.894ms`，`6/120` 帧 `>32ms`，raster p99 `34.485ms`），所以不能把设置懒构建当作全局卡顿已解决。
- 同一 QA Release 首页热滚动 4 个窗口 total p99 为 `5.899–7.610ms`，没有 `>16ms` 帧。该结果只覆盖热滚动；首次启动/首次页面转场和所有随机卡顿仍需继续定位。
- 普通无 QA 插桩 Release 已重新构建并安装到真机 `6cb21282`：[`android-codex-1.0.0-arm64-release-settings-lazy-20260929.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-settings-lazy-20260929.apk)，`31,448,763` bytes，SHA-256 `35D700D78118564DEBA8B90DFE6B03BBBBFB17E5F393325C52ECBEC7437FC6DE`。设备 `versionName=1.0.0`、`flags=0x0`，应用数据 inode 仍为 `1482824/1462743`；确认为普通 Release，非 Debug、非 QA 插桩包。
- 最终普通 Release 中，打开历史 thread 后点击模型控件，固定 250ms 检查点已显示快捷面板，当前仍为 `6 Luna / 低`；截图：[最终 Release 模型弹层](../../artifacts/ui-smoke/20260929-perf-followup/196-final-release-model-popup-250ms.png)。模型来源父页仍为 OpenAI 已选、DeepSeek 已配置但未启用，第三方配置入口嵌套于第三方卡片：[最终 Release 模型来源](../../artifacts/ui-smoke/20260929-perf-followup/198-final-release-provider-source.png)。此前真实 DeepSeek→OpenAI turn 往返结果见上节，未再次消耗第三方额度。
- 本轮打开的历史测试 thread 已通过 App 内 Stop 停止；最终 `ps` 未发现 worker guard、PRoot、Node 或 app-server。没有删除 session/workspace 或清除应用数据。
- 仍未通过：全局随机长帧根因、完整冷启动/冷页面采样、未覆盖的 composer 与系统 picker 交互，以及旧 Bridge/旧 UI/旧 runtime 清理。继续按总目标推进，不把单页改善视为阶段完成。

### 2026-09-29 Slash 菜单一致性修正与最新 Release

- 菜单承诺“选择后填入输入框；按发送执行”，但原先 `/clear` 在选择菜单项时立刻清空 transcript。已改为与其他命令一致：选择只填 composer，用户发送后才执行清空；同时把已有实现和 `/help` 均支持的 `/network-test` 加入可视命令列表。
- 新增回归测试验证 `/network-test` 菜单项可见、选择后只填入输入框，以及选择 `/clear` 时 transcript 仍完整。完整 `local_session_conversation_test.dart`：`31/31` 通过。
- 最新普通 ARM64 Release：[`android-codex-1.0.0-arm64-release-session-menu-20260929.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-session-menu-20260929.apk)，`31,448,807` bytes，SHA-256 `0A135EEC47606E345137B7988FEE72FB090FA999F25AF5F790DBE9E90FF3F39F`；APK verifier 确认签名有效、四个 Codex ARM64 native assets 齐全。Android 包为 `versionName=1.0.0`、`flags=0x0`，是普通 Release（本机 debug certificate 签名，不是商店签名）。
- 构建时真机 `6cb21282` 从 ADB 断开，依用户既定规则改在模拟器 `emulator-5651` 安装验证。设备 `base.apk` SHA 与产物完全一致，安装保留模拟器数据 inode `566168/401925`；最终 Release 正常启动，在历史 thread 的 Slash 菜单中看到 `/network-test`，选择后准确填入 composer、未发送命令。测试草稿已清空；模拟器最终没有 worker guard、PRoot、Node 或 app-server。截图：`202-final-release-emulator-home.png`、`203-final-release-emulator-thread.png`、`205-final-release-emulator-slash-network.png`、`206-final-release-emulator-network-filled.png`。
- 最新 Release 在模拟器的模型快捷面板也可打开；该模拟器显示 Linux compatibility runtime 未验证，因此模型目录提示暂不可用并保留当前模型，这是模拟器运行环境限制，不能外推成真机目录失败。真机此前已验证模型列表与当前模型读取；最新菜单改动不涉及该路径。截图：`212-final-release-emulator-model-popup.png`。
- 同一模拟器的 QA Release 对照采样：home 首轮滚动两个窗口 total p99 分别 `795.102ms`、`89.534ms`，raster p99 `418.366ms`、`46.425ms`；设置/首页转场窗口 total p99 `248.119ms`，raster p99 `168.344ms`。与此同时 build p99 分别仅 `26.406ms`、`6.448ms`、`17.415ms`。该 x86_64 模拟器通过 `libndk_translation` 跑 ARM64 包，raster 每个窗口 `120/120` 帧都超过 `8ms`，显示此 VM 图形路径严重受限；不作为 ARM64 真机性能结论，也不据此增加 UI 特效/绘制规避。测试后已恢复上方普通 Release，并确认模拟器 `base.apk` hash 与正式产物一致、`flags=0x0`、数据 inode 不变。
- 最新 Release 的这两项 UI 修正在模拟器上完成运行时验证；真实手机仍需在下次连接时安装该 APK 做同样 smoke check。模型 popup 与第三方/OpenAI 真实路由此前已在真机普通 Release 通过；本轮未重新调用 DeepSeek。

### 2026-09-29 模型目录按需读取续修

- 会话模型快捷设置不再在第一层弹层出现后立即启动 CLI/app-server 模型目录查询；仅在用户点开“模型”列表时读取，避免目录冷启动与弹层首帧争用资源。目录返回后同步更新模型能力映射，确保选择新模型仍按服务端声明选取有效推理档位。
- `ccpocket_native_session_test.dart` `24/24`、`custom_provider_settings_test.dart` `5/5`、`local_session_conversation_test.dart --plain-name provider` `9/9` 通过。回归覆盖模型列表加载时机、能力同步、模型选择，以及 OpenAI/第三方菜单层级和历史 thread 的来源切换。
- 普通 Release：[`android-codex-1.0.0-arm64-release-model-picker-lazy-20260929.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-model-picker-lazy-20260929.apk)，`31,446,135` bytes，SHA-256 `65D4A3F8DC7B64C3F345E139958CEE7D0734711BB0AFE1EA08EEB5E71AE268AC`。APK verifier 确认签名有效、四个 ARM64 Codex native assets 齐全；包 `flags=0x0`，普通 Release variant（本机 debug certificate，不是商店签名）。
- 真机当前未出现在 ADB；Release 已覆盖安装至 `emulator-5651`，设备 `base.apk` SHA 与产物相同。会话首层弹层在 tap 后约 `350ms` 的 UI 检查点可见；点击模型行后模型列表即时打开。模拟器未验证 Linux compatibility runtime，因此列表只有当前模型并显示目录不可用提示；该结果只证明菜单可见，不能作为真机目录/性能验收。截图 `213`–`217` 位于 `artifacts/ui-smoke/20260929-perf-followup/`。
- 安装与 UI smoke 未清除 App 数据；结束时只有 Android App 主进程，没有 Codex worker、PRoot、Node 或 app-server。未发起真实 turn。
- 全局随机卡顿/首轮 raster-vsync 长尾仍未定位，物理真机本轮不可用；其余页面/交互验收和旧 Bridge/旧 UI/旧 runtime 清理仍未完成，总体 goal 继续 active。

### 2026-09-29 首页会话菜单本地化与重命名生命周期

- 修复首页英文模式残留的中文：最近会话长按菜单、重命名弹窗标题/输入提示/按钮、会话读取失败提示与重试按钮、设置“代码字体”说明弹窗确认按钮；模型目录无错误详情时的默认错误文案也按语言切换。
- 英文会话菜单测试在关闭重命名弹窗时捕获到一个真实生命周期缺陷：`TextEditingController` 在弹窗 reverse transition 尚会重建 `TextField` 时已被外层 dispose。改为由 `_RenameSessionDialog` 自身 State 管理 controller，使其在弹窗真正卸载时释放。
- 定向 Flutter 测试：`ccpocket_native_home_test.dart` `10/10`、`network_proxy_settings_test.dart` `2/2` 通过。覆盖英文长按菜单、重命名提交、读取错误/重试及设置说明确认按钮。
- 新普通 Release：[`android-codex-1.0.0-arm64-release-home-menu-localization-20260929.apk`](../../artifacts/release/android-codex-1.0.0-arm64-release-home-menu-localization-20260929.apk)，`31,451,127` bytes，SHA-256 `547345DFB937D56FE3026040A625787A5BB5C677A199C73AC0C0B3A81E341ABD`；签名与 ARM64 assets 验证通过，`flags=0x0`。安装到在线模拟器后设备 APK hash 一致，保留原应用数据，启动首页可见已有 workspace/session。
- 当前只有 `emulator-5651` 在线；此轮未做真机帧率结论，未启动 Codex worker/PRoot/Node/app-server。全局随机 jank、剩余 UI/真实数据验收和旧 Bridge/旧 UI/旧 runtime 清理仍未完成，goal active。

### 2026-09-29 provider race 修复后的 Release 弹层复核

- 在普通 Release 模拟器检查 thread 模型弹层、模型列表以及软键盘打开时的弹层；三者均在点击后固定 `250ms` 检查点可见。截图和限制说明见 [`20260929-model-popup-release`](../../artifacts/ui-smoke/20260929-model-popup-release/REPORT.md)。
- provider 延迟恢复与 OpenAI 明确选择由 4 个定向 Flutter 测试文件共 `66/66` 覆盖；来源菜单层级仍为 OpenAI/第三方并列，第三方配置是子入口。
- 这是菜单响应烟测，不是帧时间测试。当前 ADB 只有 x86_64 emulator，且该模拟器缺少已验证的 ARM64 Linux/PRoot runtime；它不能替代真实手机的冷启动、首轮 raster/vsync 和随机卡顿测量。全局性能验收继续未通过。
