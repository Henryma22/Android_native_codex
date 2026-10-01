# Android Codex 总体 Goal

确认日期：2026-09-26  
状态：active  
对应系统 Goal：当前 Codex 任务中的 active goal  
权威路线：[PROJECT_DIRECTION.md](PROJECT_DIRECTION.md)；本次冻结快照：[ROUTE_FREEZE_2026-09-26.md](ROUTE_FREEZE_2026-09-26.md)

## 本轮路线固化确认（2026-09-26）

本项目后续以“先实现完整、可用、快速的功能，再在具体风险范围内补保护”为不可改变的执行原则。遇到问题先定位根因并恢复功能，随后区分风险后果、发生概率和可逆性；不能仅因为存在抽象、低概率或未经证实的风险，就放弃功能、缩减正常 Root 能力、增加逐条审批，或把可工作的 runtime 改成演示版。唯一持续优先评估的结果风险是破坏启动能力、导致设备变砖和相关不可恢复损失；保护措施必须服务于功能而不能替代功能。

本段是本次总体路线的固化记录。它与下文的实现链路、权限模型和后续推进约定一起作为新 Goal 的依据；文档固化本身不代表总体功能已经完成。

## 最终目标

把本项目做成一个真正运行在 Android 手机上的本地 Codex：用户可以在 Root 环境下直接用自然语言完成替换字体、修改应用内部配置、安装依赖、诊断系统等原本繁琐的 Android tinkering 工作。PC、远程服务器和 Bridge 不属于 Android Codex 的正常运行链路。

## 固定实现链路

```
CC Pocket 前端信息架构与 session 交互
        ↓
Android 本地 session / process 生命周期
        ↓
用户配置的正常 KernelSU Root（可选非 Root）
        ↓
PRoot Linux ARM64 用户空间
        ↓
可独立更新的官方 Linux ARM64 Codex CLI / app-server
        ↓
OpenAI auth 或用户启用的第三方 provider
```

### 运行与依赖

- Root 是日常默认模式，非 Root 是可选模式。
- PRoot guest 提供官方 Linux ARM64 CLI 及 git、node、npm、npx、python 等工具，允许 Codex 在任务中安装依赖。
- Android 宿主命令和 Android 宿主文件系统与 Linux guest 的 / 明确区分；需要宿主能力时使用最薄的本地环境衔接。
- CLI、Linux rootfs/依赖和 APK 独立升级；不把 UI 锁死在某一个 CLI 版本或硬编码旧模型列表。

### 文件可见度与权限

- Codex 应能够看到 Root 实际允许读取的 Android 宿主文件，不设置泛化的敏感目录读取黑名单。
- 普通文件、应用配置和依赖安装不设置逐条 Root approval；Root 不应在每个命令上重复审批。
- boot、启动分区和关键启动配置属于唯一需要持续重点评估的风险类别。采用软路由：识别目标、确认设备/slot 和恢复办法、向用户说明并取得这一次具体授权；能使用可撤销 KernelSU 模块时优先，但不能永久阻断批准后的合法操作。
- 不强制 codex_agent SELinux 域、固定 group/capability 清单、通用特权 broker 或人为缩减 Codex 正常功能。KernelSU profile、组、capability 和 SELinux 配置由用户操作，Agent 只提供所需信息。

### 前端与后端

- 复用 CC Pocket 的信息架构、交互逻辑和 session 状态模型，而不只是复用图标或视觉样式。
- workspace 下的每个 session/thread 必须独立保存历史、草稿、上下文和运行进程；切换页面不能终止其他 thread，多个 thread 可以并行工作。
- UI 中出现的模型、effort、计划、权限、图片、tool call、approval、diff、停止/重发、用量和上下文等能力都必须连接真实后端；不可用时明确显示具体原因，不保留无响应的假控件。
- OpenAI auth 和已启用的第三方 provider 是互斥的请求路径。第三方 provider 按 Codex 原生配置和实际协议工作，不把“OpenAI 兼容”误报成完全兼容。

## 不可改变的工程原则

**功能完整、功能可用和快速实现是最高优先级。**

遇到问题必须按以下顺序处理：

```
实际故障
  → 定位根因
  → 优先恢复功能可用性
  → 评估具体风险的后果、概率和可逆性
  → 在不妨碍功能的范围内加入保护
  → 做能回答问题的定向验证
  → 记录证据和剩余缺口
```

不能仅因为存在抽象风险、低概率风险或未经证实的风险，就放弃功能、缩减正常 Root 能力、引入永久拒绝门禁，或把完整 runtime 改成无法工作的演示版。保护措施必须服务于功能，而不能取代功能。

安全目标是避免手机启动能力被破坏、设备变砖和相关不可恢复损失；普通应用配置错误、依赖失败、服务退出或可恢复数据问题应通过提示、备份、回退和重试处理，不得因此扩展成全局限制。

## 后续推进约定

- 2026-09-26 的初始检查点只完成了路线文档和 Goal 固化；这只是历史基线，不代表后续继续实施时不能修改实现或构建验证。
- 收到继续实施指令后，按 PROJECT_DIRECTION.md 的顺序持续推进：先恢复 Root/runtime/工具可用性，再补齐 UI 与后端闭环，最后完成独立更新和 Android 集成。当前已继续落地插件市场、第三方 provider 能力配置以及 app-owned CLI resume，后续仍以实际缺口为准。
- 完成一个局部检查点不是停止条件；只要仍在该总体 Goal 范围内，就继续推进下一个可完成部分。
- 真机优先；模拟器结果只能作为模拟器验证。构建成功、静态检查或 UI 显示不能替代真实数据面验收。
- 所有关键改动、验证证据和剩余缺口持续记录到 DEFECT_REMEDIATION_PROGRESS.md。
