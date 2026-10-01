# Android Codex 总体路线冻结记录

确认日期：2026-09-26  
记录性质：项目路线与执行原则的固化快照，不代表功能已经完成或通过设备验收。

## 1. 产品目标

Android Codex 是一个完全运行在手机本地的 Codex 产品，核心用途是让用户用自然语言完成 rooted Android 上原本繁琐的操作，例如替换字体、修改应用内部配置、安装依赖和诊断系统。PC、远程服务器和 Bridge 不属于本项目的正常运行链路。

## 2. 固定实现链路

```text
CC Pocket 前端信息架构与 session 交互
        ↓
Android 本地 session / process 生命周期
        ↓
用户配置的正常 KernelSU Root（非 Root 为可选模式）
        ↓
PRoot Linux ARM64 用户空间
        ↓
可独立升级的官方 Linux ARM64 Codex CLI / app-server
        ↓
OpenAI auth 或用户启用的第三方 provider
```

- Linux guest 提供官方 CLI 及 git、node、npm、npx、python 等依赖，并允许 Codex 按任务安装依赖。
- Android 宿主文件系统与 Linux guest 的 `/` 必须明确区分；宿主命令通过最薄的本地环境衔接执行。
- CLI、rootfs/依赖和 APK 独立升级，不能把 UI 锁死在某一个 CLI 版本或旧模型列表。
- OpenAI auth 与已启用的第三方 provider 是互斥请求路径；第三方 provider 按 Codex 原生配置和实际协议接入。

## 3. 不可改变的核心原则

**功能完整、功能可用和快速实现是最高优先级，不能因为存在风险就放弃功能实现。**

遇到问题必须按以下顺序处理：

```text
实际故障
  → 定位根因
  → 优先恢复功能可用性
  → 评估具体风险的后果、概率和可逆性
  → 在不妨碍功能的范围内加入保护
  → 定向验证并记录证据
```

风险评估不能把抽象、低概率或未经证实的风险升级成永久拒绝门禁、逐条 Root 审批、能力裁剪或整个 runtime 的功能禁用。保护措施必须服务于功能，而不能替代功能。

## 4. Root 与文件可见度

- Root 是日常默认运行方式，非 Root 是用户可选模式；正常 Root 命令不逐条重复审批。
- Codex 应看到 Root 实际允许读取的 Android 宿主文件，不设置泛化的敏感目录读取黑名单。
- 普通文件、应用配置和依赖安装不因为抽象风险被全局禁止；实际能力以设备内核、UID、SELinux 和用户配置为准。
- 不强制自定义 `codex_agent` SELinux 域、固定 group/capability 清单、通用特权 broker 或人为缩减 Codex 正常能力。

## 5. 唯一持续重点评估的风险

安全目标是避免破坏启动能力、导致设备变砖及相关不可恢复损失。boot、启动分区和关键启动配置采用软路由：

1. 识别真实目标、设备/slot、影响范围和恢复办法；
2. 向用户说明具体后果并取得这一次操作授权；
3. 能用可撤销 KernelSU 模块时优先使用，但不把模块路线变成永久硬限制；
4. 必要时允许授权后的直接实现，并记录验证结果和剩余风险。

这是一种行为规范、具体验证和具体授权的软路由，不承诺绝对安全，也不允许 Agent 因担心风险而取消用户需要的合法功能。KernelSU profile、组、capability 和 SELinux 配置由用户操作，Agent 不擅自修改。

## 6. 前端与 session 完成标准

复用 CC Pocket 的信息架构、交互逻辑和 session 状态模型，而不只是复用图标或视觉样式。workspace 下的每个 session/thread 必须拥有独立历史、草稿、上下文和运行进程；切换页面不能终止其他 thread，多个 thread 必须可以并行工作。模型、effort、计划、权限、图片、tool call、approval、diff、停止/重发、用量和上下文等 UI 控件都必须接入真实后端；不可用时明确显示原因，不能保留无响应的假功能。

## 7. 后续工程纪律

- 先做功能可用性和完整性，再做不妨碍功能的保护。
- 一个局部阶段完成不是总体停止条件；仍在本路线范围内就继续推进下一个可完成部分。
- 真机优先；无真机时可用模拟器，但模拟器结果不能冒充真机 Root 验收。
- 构建成功、静态检查通过或 UI 显示“可用”不能替代真实数据面验证。
- 手机 App 内 Codex 遵守用户指定的 `luna low`；该设备端限制不约束独立开发对话。开发对话按用户对该对话的单独指定执行；不得擅自更改手机端模型/推理档位。

本快照由以下文档解释和细化：

- [PROJECT_DIRECTION.md](PROJECT_DIRECTION.md)：权威架构路线；
- [PROJECT_GOAL.md](PROJECT_GOAL.md)：当前 active goal 与总体验收方向；
- [ENGINEERING_EXECUTION_POLICY.md](ENGINEERING_EXECUTION_POLICY.md)：执行与验证纪律；
- [ROOT_ACCESS_POLICY.md](ROOT_ACCESS_POLICY.md)：Root/文件操作策略。
