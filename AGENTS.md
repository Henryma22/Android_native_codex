CLAUDE.md

## 当前 Android Codex 路线（2026-09-26）

实施前遵循 [PROJECT_GOAL.md](docs/android-local-codex/PROJECT_GOAL.md) 和 [PROJECT_DIRECTION.md](docs/android-local-codex/PROJECT_DIRECTION.md)。
功能完整、可用和快速实现是不可改变的核心原则：先解决功能问题，评估具体风险，在功能基础上做适度保护，不能因泛化风险取消功能或阻断整个 Root runtime。
默认 KernelSU Root + PRoot + 官方 Linux ARM64 Codex；不强制自定义 SELinux 域，不增加通用权限 broker 或逐条 Root 审批。boot 风险走行为规范、具体验证和明确授权，保留批准后的实施能力。
本文件下方的旧设备/只读 broker 记录仅为历史证据，不是当前产品架构要求；冲突时以新路线和用户最新指令为准。不得擅改路线或用户的 KernelSU 配置。

## 本地端口与进程登记规则

- 共享端口登记表位于 `C:\Users\Henry\Desktop\重要信息文件夹\本地串口表.md`。启动 Bridge、Web 服务、测试服务、隧道源站或其他长期进程前，必须先参考该表，并用 `Get-NetTCPConnection -State Listen` 或 `netstat -ano` 核对实时监听状态。
- 端口使用前先登记项目、进程、协议、绑定地址、用途和预计释放时间；不得静默占用已登记端口，也不得把不确定用途的端口当作可用端口。
- 修改固定端口时，必须同步更新 tunnel/反向代理、客户端地址和端口表；停止服务后把端口状态更新为“已释放”，保留历史记录。
- Codex 拉起的长期进程记录在 `C:\Users\Henry\Desktop\重要信息文件夹\Codex-拉起进程记录.md`，至少包含命令或路径、项目、PID、端口、启动时间和停止时间；严禁记录 API key、token 或密码。

## Android 设备本体状态与工具边界

- ADB 连接状态不等于 Android 设备本体状态。ADB offline、断开或当前主机没有
  `adb`，只能说明当前主机没有可用的 ADB 观察通道，不得据此断言设备没有
  Android 命令、没有 root，或设备内状态不可知。
- `getprop`、`pm`、`wm`、`dumpsys`、`ps`、`id`、`ls` 是设备侧 Android shell
  命令；它们不能直接在 Windows PowerShell 或 PRoot Linux guest 中代替执行。
  `adb` 是主机到设备的传输工具，不是设备本体命令。没有 live Android shell
  时，必须把结论标记为“最近一次设备侧已验证”并带时间，不得写成“设备没有该命令”。
- 最近一次设备侧基线（2026-09-10，可能随 ROM、KernelSU、APK 或用户操作变化）：
  设备 `24031PN0DC`，board `pineapple`，Android 16，活动显示刷新率约
  120 Hz；正式包 `com.k9i.ccpocket.local` 的 UID 为 `10503`。Root supervisor
  和独立 root read broker 可为 UID 0，但 PRoot、Node、Codex、MCP worker 仍为
  UID 10503；`Root helper: Available` 不等于 worker 本身是 root。
- 当前已验证的 root 工具是固定范围的只读数据面，不是 Android shell：Bridge 对外名称
  为 `root_read`、`root_list`、`root_stat`，设备 socket 内部方法为
  `root.read`、`root.list`、`root.stat`。它们只允许经过 UI approval 的
  `/data/adb/ksu/modules` 和 `/data/adb/ksu/bin` 相对路径，拒绝 shell、任意绝对路径、
  符号链接穿越和写操作；不能用来执行 `getprop`、`pm`、`wm` 或 `dumpsys`。
- 工具名称出现在 Android MCP 的 `tools/list` 或旧对话记录中，不代表它已经注册为
  当前 Codex 主机的顶层可调用工具。顶层调用列表由当前 MCP 配置决定；本项目
  `.mcp.json` 当前只配置 `marionette` 和 `dart-mcp`。使用工具前必须确认当前运行时、
  socket、Activity 解锁/附着状态和 UI approval，而不能只根据历史文本推断可调用。
