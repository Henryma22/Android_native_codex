# Android Codex 仓库清理记录

更新时间：2026-09-28

## 当前保留的产品链路

- `apps/codex`：独立 Android Codex App、Root/PRoot runtime 接入和本地 session。
- `packages/ccpocket_ui`：已复制并适配到本地 Codex 的 CC Pocket 展示组件。
- `tools/android-local-runtime`：PRoot、Linux rootfs、安装辅助和 Codex 操作说明。
  Debian guest 提供开发工具；Android 宿主命令使用 Android 系统自带程序。
- `docs/android-local-codex`：当前路线、设备验收、缺陷进度和历史证据。

## 本次移除的旧路线

以下目录不再属于当前 Android Codex 产品，也不参与 `apps/codex` 的编译或运行：

- `apps/mobile`：旧的多平台 CC Pocket 主应用，包含远程机器/Bridge 数据面和旧 Android runtime 控制面。
- `packages/bridge`：Windows/Linux Bridge server、WebSocket 数据面和 Claude/Codex 远程进程编排。
- `apps/menubar`：依赖 Bridge 的 macOS 菜单栏应用。
- 旧的 Bridge、移动端、桌面端、商店发布和跨平台 CI 工作流及其专用脚本。
- 旧 Android/Bionic Codex CLI 的交叉编译补丁、发布 workflow、更新器、恢复入口、安装器和 APK 资产。
- Android/Bionic native-toolchain 导入器、PATH/PRoot fallback 接线及其旧 bundle/source tree。
- GitHub issue/PR 模板中针对 Bridge、iOS/macOS Mobile 和 Claude Code 的旧入口。
- 根目录 `.claude` 旧 Bridge/mobile 发布技能、旧 `.vscode` 启动配置、`.gtrconfig` 和
  `SOURCE-ONLY-TRANSFER.md`。
- 根目录仅为 Bridge workspace 服务的 `package.json` / `package-lock.json`。
- 根目录旧 npm `node_modules` 以及 `packages/bridge` 中未被 Git 跟踪的残留源码也已移除。
- `docs/` 中只服务于旧 Bridge/Claude、多平台移动端、桌面端、商店发布、远程控制或旧
  native-first PoC 的设计、迁移、验收和调试文档也已移除；当前文档目录不再把这些路线
  当作可继续实施的选项。
- 旧 CC Pocket 官网、商店下载页、Sparkle appcast、安装二维码、发布卡片和截图等
  `docs/` 静态资源也已移除；它们不属于 Android Codex App 产物。
- 本轮继续移除未被独立 App 引用的旧 `tools/android-local-runtime/device/runtime.sh`
  Bridge/chroot 控制面、其包装脚本、旧脚本测试与 `tools/ssh-jump-smoke`；保留当前
  Kotlin 安装器实际调用的 `install-proot-rootfs.sh` 和 `proot-finalize-rootfs.sh`。
- 移除未被构建或运行时引用的旧 UI 同步脚本和 `tools/bridge-fixtures` 测试夹具；
  共享 CC Pocket 组件本身保留，避免把正在使用的 UI 误删。
- 清除 `jniLibs/arm64-v8a` 中旧的 216 MB `libcodex.so`、Root Read Broker 二进制及
  worker-guard 临时副本；当前只保留 PRoot launcher/loader、host trampoline 和 worker guard。
  APK verifier 现同时拒绝 Root broker 与 Android/Bionic Codex executable。
- 根目录未被任何源码、构建脚本或 APK 打包输入引用的 `codex-native-candidate-stripped`
  （228,484,304 bytes）和空的 `wget-log` 已移出仓库到
  `C:\Users\Henry\AppData\Local\Temp\android_codex-cleanup-20260928`；这是可恢复的
  清理，不影响当前 APK 的 ARM64 资产。确认最终回归无误后可再从该临时目录删除。
- `apps/apps` 的嵌套构建目录、`apps/packages/ccpocket_ui` 的未引用旧组件副本，以及
  `apps/codex` 下的 `build`、`.gradle`、`.kotlin` 生成缓存已移到该临时目录的
  `repo-residuals` / `generated-caches`；当前仓库只保留 `apps/codex` 和顶层
  `packages/ccpocket_ui` 的源码。

历史文档不作为当前构建输入保留，避免丢失迁移依据；其中出现的 Bridge、`apps/mobile` 或旧
架构描述均标记为历史，不得据此重新接回当前 Android 运行链路。

## 清理后的验证要求

1. `apps/codex` 的 Flutter 定向测试和 Release APK verifier 通过。
2. `apps/codex/pubspec.yaml` 仍能独立解析 `packages/ccpocket_ui`，不依赖旧 `apps/mobile`。
3. Android/Bionic Codex release workflow 已移除；本地 Release APK 与 Linux CLI/rootfs 保持独立。
4. `rg` 检查当前 app 源码和构建脚本，不再出现 `packages/bridge`、`apps/mobile`、旧 Bridge
   服务入口或 Claude runtime 依赖；历史文档中的命中单独标记，不作为运行时依赖。

## 当前执行结果

- Bridge/mobile/旧 Android-native Codex release workflow 已从当前构建路径移除；
  `.github/workflows/` 当前不含 Android/Bionic Codex 发布任务。
- `.github/dependabot.yml` 和 PR 模板已切换到 Android Codex 测试/发布入口。
- issue 模板的组件选项已切换到 Android Codex、CC Pocket UI 和本地 runtime/toolchain。
- 根 `README.md`、`CLAUDE.md` 和 `.gitignore` 已改为 Android Codex 入口；旧的多语言上游
  README、旧 Claude/Bridge 开发技能和 source-only 迁移入口已移除。
- 根 `SECURITY.md` 与 `PRIVACY_POLICY.md` 已改为本地 Android/Root/PRoot 和可选第三方
  provider 说明；旧 Bridge 隐私/安全文档及韩文副本已移除。
- `packages/ccpocket_ui` 中已删除 HomeContent 的空 macOS banner 挂钩；当前首页只保留
  本地 workspace、session、运行态和用量插槽。上游生成的 `AppLocalizations` getter
  仍因共享 CC Pocket widget 的类型契约保留，但未被当前页面引用的旧文案不构成可达
  运行时组件。

`packages/ccpocket_ui/lib/l10n` 仍保留上游生成的完整 getter 集合，因为共享 CC Pocket widget
通过同一个 `AppLocalizations` 类型编译；其中未被当前 Android App 使用的 Bridge/Claude 文本
只是生成数据，不是可达的页面、服务或运行时入口。后续若上游 UI 同步，再单独裁剪生成资源。
- CC Pocket 主题字体已从共享包的动态资源依赖收敛到 `apps/codex/assets/fonts/`，
  Release APK 会明确携带 IBM Plex Sans 和 Space Grotesk 变体，避免冷启动或离线时
  触发 Google Fonts 网络请求。
- 仍未提交 commit；所有删除和修改保留在当前工作树，便于在最终回归前检查和回滚。

## 2026-09-28 性能与 Release 页面验收续记

- transcript 改为可见行惰性构建/解析，使用 512 项 LRU；600 条历史滚动回归已通过。
- 所有 Codex session 走 Linux/PRoot；旧 Bionic CLI 探测和启动入口均已退休。历史会话记录保留，但旧 Bionic thread 不再承诺可由已退役 runtime 恢复。
- 旧 session 的持久错误文案会在显示时映射到当前 PRoot 说明，不改写本地历史。
- 全量 Flutter 测试 `326/326` 通过；CompatibilityCommandArgv、CodexSessionHome、HostProcessEnvironment 三组 Kotlin 定向测试通过；Release APK verifier 通过，候选包安装目标为 x86_64 AVD `emulator-5651`。
- 候选包页面 smoke 覆盖首页、session、设置、第三方模型列表和 provider 编辑表单；session 在缺少 ARM64 rootfs 的 AVD 上正确提示 runtime 未验证并禁用发送。
- 真机 `6cb21282` 已连接，仍运行 3 个旧包 worker（其中包含旧 Bionic CLI）；未覆盖安装以免中断会话。手机现有页面显示真实额度，但不代表候选包的 Root/真实 turn/OAuth/provider 验收通过。
- 当前产物、hash、截图和性能限制见 `UI_PERFORMANCE_ACCEPTANCE_2026-09-28.md` 与 `artifacts/release/README.md`。

### Release 真机验收状态更新

本节上方关于“手机仍运行旧包 worker、候选包尚未安装”的描述是早先检查点，现已被以下结果取代：

- 已构建并安装 Release variant 到 `6cb21282`；拉取设备安装的 `base.apk` 后，SHA-256 与本地候选 APK 一致。应用数据保留，没有清除工作区或 session。
- 该 Release 上完成模型来源 OpenAI/第三方往返切换及进程重启持久性验证；DeepSeek 配置保留但在 OpenAI 模式下不参与请求。
- 完成一个 OpenAI 订阅真实 Codex turn，收到 `OPENAI_RELEASE_TURN_OK` 和实际用量显示；模型选择弹窗重复开启 6 次，端到端截图耗时 0.89–1.03 秒。尚未获得 Flutter 有效 frame stats，因此随机卡顿的全页面帧率/卡顿率仍未量化，不把本次定向无卡死测试描述为完整性能认证。
- 本轮结束时已停止由 Agent 启动的 app/Codex worker；保留已创建 session 历史，未改 KernelSU 设置。Release 文件与截图路径及 hash 见 `artifacts/release/README.md` 和 `UI_PERFORMANCE_ACCEPTANCE_2026-09-28.md`。
