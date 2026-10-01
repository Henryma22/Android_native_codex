# 2026-09-30 当前路线代码清理

依据：PROJECT_DIRECTION.md。保留 KernelSU Root → PRoot → 官方 Linux ARM64
Codex、本地并发 session 和 CC Pocket 展示组件。

## 移除

- `functions/`、Firebase 部署配置和 Firestore rules：旧远程 Bridge 的 FCM
  推送 relay，当前 APK 没有相关依赖。
- `scripts/generate-jwt.py`、`scripts/setup-test-repo.sh`：旧商店发布和上游 Git
  演示脚本，当前构建与测试未引用。
- `.agents/skills`：指向已删除 `.claude/skills` 的失效链接文件。
- `.codex/rules/default.rules`：旧 CC Pocket 的 macOS/iOS/npm execpolicy；当前
  Android 工程遵循用户的 AGENTS 执行策略，保留实际开发 MCP 配置。
- 重复的 `packages/packages/ccpocket_ui` 和无引用的 `SessionListState`。
- 未被页面调用的 `RootProbe`、对应测试、Android `probeRoot` 同步处理器。
- 设置页废弃额度卡片、动画条和 pace 指示器；实际会话额度组件继续使用。
- 未调用的旧流式拼接、单会话 snapshot 转发、备份恢复函数和 session getter，
  以及没有读取者的备份 receipt map、模型缓存旧常量。
- Root profile 中不可达的 `review_needed` 分支及“受限 worker / 启动写保护门禁”
  的过期注释。Root 判断继续只看真实 UID 0。
- `packages/ccpocket_ui/lib/l10n` 中未被当前 Android Dart 源码引用的旧 Bridge、
  Claude、Firebase、远程 machine 和其他上游页面文案；当前活跃的 Codex 错误/重连
  文案保留并改成 Android 本地语义。
- `HomeContent` 中遗留的逐项目会话分页状态、load-more 回调、加载 spinner 和
  `showMore` 本地化入口；Android 本地历史已经一次性提供 workspace 的全部 session，
  保留分页只会造成“还有会话未显示”的错误认知。

## 移出仓库但保留恢复副本

恢复目录：`C:\Users\Henry\AppData\Local\Temp\android-codex-route-cleanup-20260930`。

- `codex-upstream-android-native`：旧 Bionic fork，带本地补丁和嵌套 Git；约
  73.52 GB（包含旧 Rust 构建缓存）。没有删除补丁。移动不会释放磁盘空间。
- `android-local-codex-mvp`：旧 Kotlin MVP、独立 Gradle 工程和示例模块。
- `codex-migration`：无当前产品调用者的旧桌面 Stage 5 数据迁移脚本。
- `MVP_ARCHITECTURE_AND_INTEGRATION_PLAN.md`：旧计划仍声明自己为架构依据，
  与当前路线冲突，移出活动文档目录。
- `stale-hooks-runner`：Flutter 生成缓存仍引用失效 `X:` 盘，移走后重新生成。
- `tools/android-local-runtime/builder/finalize-on-device.sh`：旧的 mount-based
  finalizer，仍带有已退役 Bridge/旧包路径；生产 manifest 与独立安装器只使用
  `device/proot-finalize-rootfs.sh`，因此将旧脚本删除而不是继续维护两套合同。

旧历史验收文档保留证据价值；不能按其中的旧路径恢复退役架构。

## 保留理由与验证边界

- `LocalAndroidBackend` 提供宿主 workspace、SAF 和文件功能；不是另一条 Codex
  runtime。FakeBackend 为测试提供模拟进程，保留。
- `PluginBroker` 是当前 KernelSU 模块安装、关闭、卸载、回退功能的实现，
  不代理 Codex 的日常 shell，也不在每个 Root 命令前审批，保留。
- `probeCodexRuntime` 作为历史 local-backend 状态适配仍保留；Android 直接返回
  “已退役”，移除扫描函数、旧 binary 路径常量和专用探测线程。最初尝试删除
  Dart 状态适配会破坏既有可注入运行时测试，已恢复；没有恢复 Bionic executable。
- CC Pocket 活跃本地化类型和 UI 组件继续保留；仅按当前 Android App 的真实调用者
  删除不可达键，不按关键词误删仍在使用的 session/composer/approval/diff 文案。
- 项目列表仍复用 CC Pocket 的 workspace/session 卡片与交互，只去掉 Android 本地路径
  不需要的旧分页层；现有的 session 分组和空 workspace 展示保持不变。
- CONTRIBUTING、README、mise 和 Dependabot 已改成当前 Android/Flutter 入口。

## 验证结果

- 第一组 Flutter 定向回归 41/41；删除死代码后的第二组 60/60，包括模型弹层、
  设置、模型缓存、并发 session、停止/恢复和 provider 路径。
- `compileReleaseKotlin` 成功，`RootProfileProbeTest` 22/22，0 failures/errors。
  使用已有 JDK 17；仅编译 Kotlin/运行 JVM 单测，跳过有旧失效盘符 depfile 的
  Flutter APK 打包任务，本轮未构建或安装新 APK。
- 随后针对本轮本地化和项目列表清理重新构建 Release APK；只读 verifier 通过，包为
  `io.henry.codex` / `1.0.0`，包含四个 ARM64 Codex runtime asset，且没有退役的
  Bionic/Bridge asset。由于设备上的 Root worker 仍在运行，该 APK 未覆盖安装。
- 修改的 Dart 文件经 analyzer 检查：0 error、0 unused declaration/import/field。
  仍有既有非空断言、类型检查及 lint 提示，不将其误报为全仓库 analyze 零告警。
- 当前源码/工具未找到已删除 RootProbe、SessionListState、native binary 路径、
  Firebase relay 或商店 JWT 工具的调用。`codex_agent` 字符串仅出现在说明
  “不要求自定义域”的操作文档中。
- 全部变更保留在工作树；不操作手机、不清除 workspace/session。
