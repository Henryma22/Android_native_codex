# Android Codex 安全边界

Android Codex 是本地 Android 应用，不通过 Bridge 或 WebSocket 中转执行命令。

## 执行边界

- KernelSU Root 是常态执行身份；普通文件读取和常规 Root 操作由本地 Codex runtime 直接处理。
- Android native runtime 可用时优先使用；需要 GNU/Linux 用户空间时使用 PRoot 和官方 Linux ARM64
  Codex/工具链。
- boot 镜像、raw block、启动链配置和 KernelSU 模块等目标使用应用层软路由：先识别目标、确认
  恢复路径和具体命令，再取得对应操作授权。该策略是行为规范，不是内核级写隔离。
- 本项目不维护通用文件 broker，也不把普通 Root 命令强制拆成逐条审批；需要防止不可逆损坏时，
  优先使用验证、备份和明确授权，而不是让整个 Root runtime 失去可用性。

## 凭据与第三方 provider

OpenAI 登录状态和自定义 provider API key 保存在应用本地配置中。自定义 provider 只有在用户
显式启用后才接管模型请求；启用后不与 OpenAI auth 路径同时使用。请求内容是否发送到第三方
服务商由用户配置决定，测试 key 不应提交到仓库、日志或端口登记表。

## 报告问题

报告安全问题时请附上 Android 版本、应用版本、runtime 类型、最小复现步骤和脱敏日志。不要
上传 API key、OAuth token、KernelSU 私密配置或完整个人 workspace 内容。
