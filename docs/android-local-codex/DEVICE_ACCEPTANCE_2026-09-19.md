# 独立 App 实体设备验收补充（2026-09-19）

设备：Xiaomi `24031PN0DC`，Android 16 / API 36 / `arm64-v8a`，ADB serial
`6cb21282`。本记录只覆盖 `io.henry.codex`，不包含 Bridge 或旧 CC Pocket 远程链路。

## 本次产物

- release APK：`apps/codex/build/app/outputs/flutter-apk/app-release.apk`
- 包名：`io.henry.codex`
- 大小：`24,557,279` bytes
- SHA-256：`cf4c631a0df93744f659586952e4abb98eb0c487dce66f1931b05e90a87f26d2`
- 五个 ARM64 native asset 均存在：PRoot、loader、host trampoline、worker guard、
  root-read broker。

## 已验证

- `flutter test`：89/89 通过；Android `testDebugUnitTest`：12/12 通过；session bootstrap 与 conversation-first history preview 断言确认
  `skipGitRepoCheck=true` 会随 `thread/start` 发送。
- `flutter analyze`：无 error；仍有 24 条既有 lint/info 建议。
- `flutter build apk --release`：成功。
- APK 已重新安装到实体设备，包名、版本和数据目录正常，临时 native 直跑探测文件已清理。
- Runtime 页面已把两条证据分开显示：当前设备的 App UID direct runtime 未安装/不可用，
  `Linux Compatibility (PRoot)` 已选中且为 `Verified`；不会把 Root helper 的结果伪装成
  App UID 原生执行。
- 最新 APK 上恢复已有 thread 后，真实 local command turn `pwd` 返回 `/workspace`，
  `ls -la` 返回 guest workspace 内容；Stop 后 Codex/PRoot 进程退出，Recent Sessions
  仍保留 thread、transcript 和 Resume 入口。
- 同一 session 随后完成 provider-backed real turn：发送
  `Reply exactly REALTURNOK and nothing else.`，transcript 收到精确 `REALTURNOK`；
  这次验证使用的模型和推理档位仍为 `gpt-5.6-luna · low`。
- Session 页面上的 `Check login` 在同一 PRoot/App UID 路径返回 `Status: Logged in`，
  登录入口和状态检查可从本地 UI 操作。
- 最新 APK 安装后再次完成 `REALTURNOK` provider-backed turn；Local Android 的 App UID/
  Root helper 进程现在也继承 Android 当前显式 HTTP proxy，避免 direct/root 与 PRoot 使用
  不同网络环境。
- Session 页面显示 `gpt-5.6-luna · low`，本次验证没有切换到其他模型或推理档位。
- 最新 APK 已在真机恢复同一 session，确认历史中的 transcript、draft、prompt history、
  sandbox/approval/plan 设置以及 `gpt-5.6-luna · low` 会被本地持久化；旧记录中的其他模型
  或推理档位会被规范化为当前固定配置。
- 当 App UID direct runtime 不可用但 PRoot 已 Verified 时，session setup 中的 `Start device
  login` 与 `Check login` 仍保持可用并复用本地 fallback；不会因为 direct probe 失败而把
  已验证的本地登录入口错误地禁用。
- 活动 session 返回 Home 后仅保留在 Running 卡片，不会在 Recent Sessions 重复展示；从
  Running 卡片执行 Stop 后，`codex`、PRoot 与 worker guard 进程均退出，历史工作区卡片仍
  保留 `REALTURNOK` 和 Resume 入口。
- 在同一真机 session 中精确终止当前 `codex app-server` 后，活动页仍保留 thread、transcript
  和 composer；断线期间输入 `Queue local prompt` 会显示 `Queued until local reconnect`，
  点击 `Reconnect` 后队列自动投递，transcript 收到该 prompt 及 assistant 回复；随后 Stop
  清理了 Codex、PRoot 和 worker guard 进程。
- 多 session 历史已在同一工作区真机验证：从断线恢复卡执行 `New session` 后，原 session
  仍保留，Home 的 Recent Sessions 出现独立的新空 session 卡片；两条记录均提供各自的
  Resume 入口，不再由 workspace 单键覆盖。
- 最新修复后的 APK 已重新安装到同一真机：点击不含 `sessionId` 的旧历史记录时，页面会
  正确切换到该记录并显示 `289 local messages`、对应 thread 和 `Resume`，不再复用前一个
  空 session；若历史没有 thread，则卡片显示 `Open` 而不是误导性的 `Resume`。
- 最新修复后的 APK 新建本地 session 后完成 provider-backed real turn：发送
  `FINALMULTI`，transcript 收到 `What would you like me to do with “FINALMULTI”?`；页面显示
  `gpt-5.6-luna · low`，随后 Stop 清理 Codex、PRoot 和 worker guard 进程。
- 最新 APK 已在真机验证 CC Pocket 风格的 session 长按操作：长按 Recent Session 打开
  底部操作面板，可执行 `Resume session`、`Pin session` 和 `Archive session`；Pin 状态在
  强制停止并重新打开 app 后仍显示 `Unpin session`，证明状态写入 Android 私有历史索引。
  Archive 后 session 从默认 Recent 列表隐藏，`Archived` 筛选器可找回并显示
  `Restore from archive`；本次测试结束后已恢复原有 session 状态。
- 当前 release 还包含 provider turn 的 CC Pocket 风格失败提示：保留失败 prompt，显示
  `Retry turn`，在本地 app-server 仍存活时可重试同一条 prompt；本次未人为制造 provider
  失败，真实 provider 成功回合仍以本记录前述 `REALTURNOK`/`FINALMULTI` 验证为准。
- 同一长按面板现已加入 `Rename session`：真机实际写入临时标题、确认 Home 卡片显示新标题，
  再清空标题并强制停止/重启，确认恢复为工作区默认名称；标题保存在 Android 私有历史索引，
  不依赖 Bridge 或 provider thread rename API。
- 真实 session 返回 Home 后，Running 卡的 `Pin session` 可直接切换为 `Unpin session`，
  再切回未置顶；随后 Stop 清理 Codex、PRoot 和 worker guard，恢复为仅应用进程。
- Recent Session 支持 CC Pocket 风格的右向左滑动归档：真机滑动后默认列表隐藏，
  `Archived` 筛选器可找回，长按显示 `Restore from archive`；恢复后冷启动仍回到默认列表。
- 强制停止并重新打开 APK 后，Home 仍显示该 session 的 Resume；进入 setup 可见 `255 local
  messages`、PRoot `Verified` 和可用的登录按钮，Resume 后 mode bar、transcript、composer
  与 prompt history 均恢复，prompt history sheet 中可重新选取上一条真实提示词。
- 之前的实体设备验收仍有效：PRoot rootfs probe、Local Session ready/stop、thread resume、
  `/workspace` 下的 `pwd`/`ls -la`、Home 保活、Running 卡片、Stop 和断线恢复 UI。

## Android-native 边界证据

同一份官方 `@openai/codex@0.154.0-linux-arm64` 二进制：

1. 在 KernelSU shell 中切到 App UID `10509` 后，可执行 `--version`，并完成 JSON-RPC
   `initialize` 与 `thread/start`；模型/推理档位为 `gpt-5.6-luna / low`。
2. 在真实 App 的 `u:r:untrusted_app:s0` SELinux 域下，从
   `/data/local/tmp` 或 `apk_data_file` 直接 `execve` 会收到 `entrypoint` 拒绝。

因此 shell 结果不能当作 App UID 原生执行证据；本次没有把普通 Linux standalone binary
复制进 APK 或 app data 作为伪原生方案。当前产品保持：真实 App UID 可验证 runtime 优先，
否则使用已验证的本地 Linux Compatibility/PRoot fallback。

## 当前限制

- 当前设备此前曾出现 Clash/VPN 代理链路导致 provider TLS/WebSocket `tls handshake eof`；
  这是外部网络路径风险，不是 Bridge 缺失或 session JSON-RPC 问题。本次最新 APK 已成功
  完成一次 provider-backed real turn，但仍需在不同网络/OEM 条件下做稳定性复测。
- 真实 App UID 的 Codex native launcher 仍未补齐；需要找到 SELinux 允许的 Android-native
  入口后再实现，不能用 root shell UID 探测替代。
- APK 仍使用 debug certificate，尚未进入正式签名/发布验收。
