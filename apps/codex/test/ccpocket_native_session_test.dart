import 'dart:async';

import 'package:ccpocket_ui/l10n/app_localizations.dart';
import 'package:ccpocket_ui/models/messages.dart';
import 'package:ccpocket_ui/theme/app_theme.dart';
import 'package:ccpocket_ui/widgets/bubbles/assistant_bubble.dart';
import 'package:ccpocket_ui/widgets/bubbles/error_bubble.dart';
import 'package:ccpocket_ui/widgets/bubbles/message_action_bar.dart';
import 'package:ccpocket_ui/widgets/bubbles/permission_request_bubble.dart';
import 'package:ccpocket_ui/widgets/bubbles/result_chip.dart';
import 'package:ccpocket_ui/widgets/bubbles/streaming_bubble.dart';
import 'package:ccpocket_ui/widgets/bubbles/todo_write_widget.dart';
import 'package:ccpocket_ui/features/chat_session/widgets/usage_summary_bar.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/ccpocket_native_session.dart';
import 'package:codex/core/application/codex_auth_client.dart';
import 'package:codex/core/application/codex_model_catalog.dart';
import 'package:codex/core/application/agent_file_change_preview.dart';
import 'package:codex/core/domain/session.dart';
import 'package:codex/core/domain/transcript.dart';

void main() {
  Widget app(Widget child, {Locale? locale}) {
    return MaterialApp(
      locale: locale,
      theme: AppTheme.lightTheme,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );
  }

  testWidgets('narrow large-text mode bar keeps every control accessible', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    var openedPermissions = false;
    await tester.pumpWidget(
      app(
        MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(1.8)),
          child: CcpocketNativeModeBar(
            model: 'custom-provider-with-a-very-long-model-name',
            effort: 'low',
            approvalPolicy: 'never',
            sandbox: 'danger-full-access',
            planMode: false,
            onOpenSettings: () {},
            onOpenEffortSettings: () {},
            onOpenPermissions: () => openedPermissions = true,
            onTogglePlan: () {},
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    final permissions = find.byKey(
      const ValueKey('local_codex_execution_mode_chip'),
    );
    await tester.ensureVisible(permissions);
    await tester.tap(permissions);
    expect(openedPermissions, isTrue);
  });

  testWidgets('uses the original CC Pocket composer affordances', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      app(
        CcpocketNativeComposer(
          controller: controller,
          status: 'ready',
          inputBlocked: false,
          onSend: () {},
          onStop: () {},
          onInterrupt: () {},
          onSlashCommand: () {},
          onMention: () {},
          onShowPromptHistory: () {},
          onIndent: () {},
          onDedent: () {},
        ),
      ),
    );

    expect(find.byKey(const ValueKey('local_codex_composer')), findsOneWidget);
    expect(find.text('/'), findsOneWidget);
    expect(find.byKey(const ValueKey('mention_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('send_button')), findsOneWidget);
  });

  testWidgets('localizes permission request presentation in Chinese', (
    tester,
  ) async {
    const commandRequest = PermissionRequestMessage(
      toolUseId: 'permission-command',
      toolName: 'Bash',
      input: <String, dynamic>{
        'command': 'id',
        'additionalPermissions': <String>['network'],
      },
    );
    await tester.pumpWidget(
      app(
        const PermissionRequestBubble(message: commandRequest),
        locale: Locale('zh'),
      ),
    );

    expect(find.text('命令审批'), findsOneWidget);
    expect(find.text('允许执行命令'), findsOneWidget);
    expect(find.text('额外权限：network'), findsOneWidget);
    expect(find.text('Command Approval'), findsNothing);
    expect(find.text('Additional permissions: network'), findsNothing);

    const fileRequest = PermissionRequestMessage(
      toolUseId: 'permission-file',
      toolName: 'FileChange',
      input: <String, dynamic>{
        'changes': <Map<String, String>>[
          <String, String>{'file': 'lib/main.dart'},
          <String, String>{'file': 'lib/app.dart'},
        ],
      },
    );
    await tester.pumpWidget(
      app(
        const PermissionRequestBubble(message: fileRequest),
        locale: Locale('zh'),
      ),
    );
    expect(find.text('文件变更审批'), findsOneWidget);
    expect(find.text('允许修改 2 个文件'), findsOneWidget);
    expect(find.text('lib/main.dart 还有 1 项'), findsOneWidget);
    expect(find.text('Allow changes to 2 files'), findsNothing);
  });

  testWidgets('localizes native auth status and challenge details in Chinese', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      app(
        CcpocketNativeAuthCard(
          status: 'Logged in',
          loginStatus: 'Browser authorization completed.',
          error: 'Codex did not return a browser login URL.',
          busy: false,
          pending: false,
          authenticated: true,
          selectedMode: CodexAuthMode.browser,
          apiKeyController: controller,
          challenge: const CodexAuthChallenge(
            verificationUrl: 'https://example.test/login',
            oneTimeCode: 'ABCD-EFGH',
          ),
          onModeChanged: (_) {},
          onStart: () {},
          onRefresh: () {},
          onCancel: () {},
          onLogout: () {},
          onCopyCode: () {},
          onOpenUrl: () {},
        ),
        locale: const Locale('zh'),
      ),
    );

    expect(find.text('状态: 已登录'), findsOneWidget);
    expect(find.text('浏览器授权已完成。'), findsOneWidget);
    expect(find.text('Codex 没有返回浏览器登录地址。'), findsOneWidget);
    expect(find.text('代码：ABCD-EFGH'), findsOneWidget);
    expect(find.text('Browser authorization completed.'), findsNothing);
    expect(find.text('Code: ABCD-EFGH'), findsNothing);
  });

  testWidgets('session composer controls have labeled 48dp phone targets', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    Widget composer(String status) => app(
      CcpocketNativeComposer(
        controller: controller,
        status: status,
        inputBlocked: false,
        onSend: () {},
        onStop: () {},
        onInterrupt: () {},
        onSlashCommand: () {},
        onMention: () {},
        onShowPromptHistory: () {},
        onIndent: () {},
        onDedent: () {},
      ),
      locale: const Locale('zh'),
    );

    await tester.pumpWidget(composer('ready'));
    await tester.pumpAndSettle();
    expect(find.bySemanticsLabel('输入命令或技能'), findsOneWidget);
    expect(find.bySemanticsLabel('提及文件或插件'), findsOneWidget);
    for (final key in <String>[
      'slash_command_button',
      'indent_button',
      'mention_button',
      'attach_image_button',
      'prompt_history_button',
      'send_button',
    ]) {
      final control = find.byKey(ValueKey(key));
      expect(control, findsOneWidget, reason: key);
      final size = tester.getSize(control);
      expect(size.width, greaterThanOrEqualTo(48), reason: key);
      expect(size.height, greaterThanOrEqualTo(48), reason: key);
    }
    expect(find.byTooltip('输入命令或技能'), findsOneWidget);
    expect(find.byTooltip('附加图片'), findsOneWidget);
    expect(find.byTooltip('发送消息'), findsOneWidget);

    controller.text = 'draft';
    await tester.pumpAndSettle();
    final dedent = tester.getSize(find.byKey(const ValueKey('dedent_button')));
    expect(dedent.width, greaterThanOrEqualTo(48));
    expect(dedent.height, greaterThanOrEqualTo(48));

    controller.clear();
    await tester.pumpWidget(composer('running'));
    await tester.pumpAndSettle();
    final stop = tester.getSize(find.byKey(const ValueKey('stop_button')));
    expect(stop.width, greaterThanOrEqualTo(48));
    expect(stop.height, greaterThanOrEqualTo(48));
    expect(find.byTooltip('点按：中断，长按：停止'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('projects the local transcript into CC Pocket message bubbles', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const CcpocketNativeMessageList(
          entries: <String>[
            'You: inspect the workspace',
            'Assistant: I will inspect it locally.',
          ],
          status: 'ready',
          reverse: false,
        ),
      ),
    );

    expect(find.text('inspect the workspace'), findsOneWidget);
    expect(find.text('I will inspect it locally.'), findsOneWidget);
  });

  testWidgets('localizes Codex tool result names in Chinese', (tester) async {
    final entry = CodexTranscriptEntry(
      id: 'tool-result-1',
      kind: CodexTranscriptKind.toolResult,
      text: 'command output',
      timestamp: DateTime(2026, 10, 1),
      toolName: 'commandExecution',
    ).toStored();

    await tester.pumpWidget(
      app(
        CcpocketNativeMessageList(
          entries: <String>[entry],
          status: 'ready',
          reverse: false,
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('命令执行'), findsOneWidget);
    expect(find.text('commandExecution'), findsNothing);
  });

  testWidgets('localizes structured error titles and hints in Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const ErrorBubble(
          message: ErrorMessage(
            message: 'The local Codex CLI is not installed.',
            errorCode: 'codex_cli_not_found',
          ),
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未安装 Codex CLI'), findsOneWidget);
    expect(find.text('请安装本地 Codex 运行时后重试'), findsOneWidget);
    expect(find.text('Codex CLI Not Installed'), findsNothing);
  });

  testWidgets('localizes image generation status in Chinese', (tester) async {
    const message = AssistantServerMessage(
      message: AssistantMessage(
        id: 'image-generation-1',
        role: 'assistant',
        model: 'gpt-6-luna',
        content: <AssistantContent>[
          ToolUseContent(
            id: 'image-tool-1',
            name: 'ImageGeneration',
            input: <String, dynamic>{'status': 'in_progress'},
          ),
        ],
      ),
    );

    await tester.pumpWidget(
      app(const AssistantBubble(message: message), locale: const Locale('zh')),
    );
    await tester.pumpAndSettle();

    expect(find.text('正在生成图片'), findsOneWidget);
    expect(find.text('Generating image'), findsNothing);
  });

  testWidgets('localizes usage, result, and todo labels in Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const UsageSummaryBar(
              totalCost: 0,
              totalDuration: null,
              inputTokens: 1200,
              cachedInputTokens: 50,
              outputTokens: 42,
              toolCalls: 2,
              fileEdits: 1,
              contextTokens: 500,
              contextWindow: 4000,
            ),
            const ResultChip(
              message: ResultMessage(
                subtype: 'success',
                inputTokens: 1200,
                cachedInputTokens: 50,
                outputTokens: 42,
              ),
            ),
            TodoWriteWidget(
              input: <String, dynamic>{
                'todos': <Map<String, String>>[
                  <String, String>{
                    'content': 'Inspect the workspace',
                    'status': 'completed',
                    'activeForm': '',
                  },
                ],
              },
            ),
          ],
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('输入'), findsWidgets);
    expect(find.textContaining('完成'), findsOneWidget);
    expect(find.text('任务'), findsOneWidget);
    expect(find.textContaining('工具'), findsWidgets);
    expect(find.textContaining('in '), findsNothing);
    expect(find.text('Done'), findsNothing);
  });

  testWidgets('keeps long live responses on the lightweight preview path', (
    tester,
  ) async {
    final longResponse = '${'x' * 2050}\n**still streaming**';

    await tester.pumpWidget(app(StreamingBubble(text: longResponse)));

    expect(find.byType(MarkdownBody), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) => widget is Text && widget.data == longResponse,
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('isolates streaming snapshot rebuilds to the message list', (
    tester,
  ) async {
    final controller = TextEditingController();
    final streaming = ValueNotifier(const CcpocketNativeStreamingSnapshot());
    addTearDown(controller.dispose);
    addTearDown(streaming.dispose);
    var modeBarBuilds = 0;

    await tester.pumpWidget(
      app(
        CcpocketNativeSessionSurface(
          entries: const <String>[],
          status: 'running',
          controller: controller,
          header: null,
          streamingSnapshot: streaming,
          modeBar: Builder(
            builder: (_) {
              modeBarBuilds++;
              return const SizedBox(height: 1);
            },
          ),
          onSend: () {},
          onStop: () {},
          onInterrupt: () {},
          onSlashCommand: () {},
          onMention: () {},
          onShowPromptHistory: () {},
          onIndent: () {},
          onDedent: () {},
        ),
      ),
    );
    await tester.pump();
    expect(modeBarBuilds, 1);

    streaming.value = const CcpocketNativeStreamingSnapshot(
      assistant: 'isolated live response',
    );
    await tester.pump();

    expect(find.text('isolated live response'), findsOneWidget);
    expect(modeBarBuilds, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('caches localized message projections by source row', (
    tester,
  ) async {
    var localizationCalls = 0;

    Widget messageList() {
      return app(
        CcpocketNativeMessageList(
          entries: const <String>['System: MCP request accepted.'],
          status: 'ready',
          reverse: false,
          localizeEntry: (entry) {
            localizationCalls++;
            return 'You: localized projection';
          },
        ),
      );
    }

    await tester.pumpWidget(messageList());
    await tester.pump();
    final callsAfterInitialProjection = localizationCalls;
    expect(callsAfterInitialProjection, greaterThan(0));

    await tester.pumpWidget(messageList());
    await tester.pump();

    expect(localizationCalls, callsAfterInitialProjection);
    expect(find.text('localized projection'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('keeps long session history virtualized while scrolling', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final entries = List<String>.generate(
      600,
      (index) => 'You: transcript message $index',
      growable: false,
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeMessageList(
          entries: entries,
          status: 'ready',
          reverse: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // The adapter initially follows the newest item. Older entries are built
    // as they enter the viewport, preserving ListView.builder virtualization.
    expect(find.text('transcript message 599'), findsOneWidget);
    expect(find.text('transcript message 0'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('transcript message 0'),
      -1000,
      scrollable: find.byType(Scrollable),
      maxScrolls: 80,
    );
    expect(find.text('transcript message 0'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('CC Pocket message actions have labeled 48dp touch targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        MessageActionBar(
          textToCopy: 'assistant response',
          onTogglePlainText: () {},
          onFork: () {},
        ),
        locale: const Locale('zh'),
      ),
    );

    for (final entry in <(String, String)>[
      ('copy_button', '复制'),
      ('plain_text_toggle', '显示纯文本'),
      ('share_button', '分享'),
      ('fork_button', '分叉对话'),
    ]) {
      final target = find.byKey(ValueKey(entry.$1));
      expect(target, findsOneWidget, reason: entry.$1);
      expect(tester.getSize(target).width, greaterThanOrEqualTo(48));
      expect(tester.getSize(target).height, greaterThanOrEqualTo(48));
      expect(find.byTooltip(entry.$2), findsOneWidget, reason: entry.$1);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('empty conversation invites a message, not a new session', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        const CcpocketNativeMessageList(entries: <String>[], status: 'stopped'),
        locale: const Locale('zh'),
      ),
    );

    expect(find.text('开始对话'), findsOneWidget);
    expect(find.text('输入消息，即可开始这个 Codex 会话。'), findsOneWidget);
    expect(find.text('点击 + 按钮创建新会话，并开始用 Codex 编码。'), findsNothing);
  });

  testWidgets('keeps the local mode bar and original settings entry point', (
    tester,
  ) async {
    var opened = false;
    var openedPermissions = false;
    await tester.pumpWidget(
      app(
        CcpocketNativeModeBar(
          model: 'gpt-5.6-luna',
          effort: 'low',
          approvalPolicy: 'on-request',
          sandbox: 'workspace-write',
          planMode: false,
          onOpenSettings: () => opened = true,
          onOpenPermissions: () => openedPermissions = true,
          onTogglePlan: () {},
        ),
      ),
    );

    for (final key in <String>[
      'local_codex_model_chip',
      'local_codex_plan_mode_chip',
      'local_codex_execution_mode_chip',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        greaterThanOrEqualTo(48),
        reason: key,
      );
    }
    expect(find.textContaining('5.6 Luna'), findsOneWidget);
    await tester.tap(find.textContaining('5.6 Luna'));
    expect(opened, isTrue);
    await tester.tap(
      find.byKey(const ValueKey('local_codex_execution_mode_chip')),
    );
    expect(openedPermissions, isTrue);
  });

  testWidgets('model catalog loads only after opening the model picker', (
    tester,
  ) async {
    final catalog = Completer<CodexModelCatalog>();
    var catalogLoadCount = 0;
    String? selectedModel;
    String? selectedEffort;

    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showCcpocketNativeCodexSettings(
                  context: context,
                  model: 'gpt-6-luna',
                  effort: 'low',
                  loadModelCatalog: () {
                    catalogLoadCount++;
                    return catalog.future;
                  },
                  onModelChanged: (value) => selectedModel = value,
                  onEffortChanged: (value) => selectedEffort = value,
                ),
                child: const Text('Open model settings'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open model settings'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(
      find.byKey(const ValueKey('codex_settings_advanced_panel')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('codex_model_advanced')), findsOneWidget);
    expect(catalogLoadCount, 0);
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.tap(find.byKey(const ValueKey('codex_model_advanced')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    expect(catalogLoadCount, 1);
    expect(
      find.byKey(const ValueKey('codex_model_gpt-6-luna_option')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('codex_model_gpt-6-sol_option')),
      findsNothing,
    );
    expect(find.byType(LinearProgressIndicator), findsWidgets);

    catalog.complete(
      const CodexModelCatalog(
        models: <CodexModelDescriptor>[
          CodexModelDescriptor(
            id: 'gpt-6-luna',
            displayName: '6 Luna',
            reasoningEfforts: <String>['low'],
          ),
          CodexModelDescriptor(
            id: 'gpt-6-sol',
            displayName: '6 Sol',
            reasoningEfforts: <String>['medium', 'high'],
          ),
        ],
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('codex_model_gpt-6-sol_option')),
      findsOneWidget,
    );
    await tester.tap(
      find.byKey(const ValueKey('codex_model_gpt-6-sol_option')),
    );
    await tester.pumpAndSettle();

    expect(selectedModel, 'gpt-6-sol');
    expect(selectedEffort, 'high');
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Chinese model settings localize effort and hide unsupported speed',
    (tester) async {
      await tester.pumpWidget(
        app(
          Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: FilledButton(
                  onPressed: () => showCcpocketNativeCodexSettings(
                    context: context,
                    model: 'gpt-6-luna',
                    effort: 'low',
                    onModelChanged: (_) {},
                    onEffortChanged: (_) {},
                  ),
                  child: const Text('Open model settings'),
                ),
              ),
            ),
          ),
          locale: const Locale('zh'),
        ),
      );

      await tester.tap(find.text('Open model settings'));
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('codex_settings_effort_label')),
        findsOneWidget,
      );
      expect(find.text('低'), findsWidgets);
      expect(find.text('Light'), findsNothing);
      expect(find.byKey(const ValueKey('codex_speed_button')), findsNothing);

      expect(find.text('推理强度'), findsOneWidget);
      expect(find.text('低'), findsWidgets);
      expect(find.text('速度'), findsNothing);
      expect(find.text('Standard'), findsNothing);
      expect(find.byKey(const ValueKey('codex_speed_advanced')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows Codex controls for providers running through app-server', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CcpocketNativeModeBar(
          model: 'Deepseek Flash',
          effort: 'low',
          approvalPolicy: 'on-request',
          sandbox: 'workspace-write',
          planMode: false,
          onOpenSettings: () {},
          onOpenPermissions: () {},
          onTogglePlan: () {},
          showCodexControls: true,
        ),
      ),
    );

    expect(
      find.byKey(const ValueKey('local_codex_model_chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('local_codex_plan_mode_chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('local_codex_execution_mode_chip')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('local_codex_effort_chip')), findsNothing);
    expect(find.textContaining('Deepseek Flash'), findsOneWidget);
  });

  testWidgets('labels Root path-routed access distinctly from Default', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CcpocketNativeModeBar(
          model: 'gpt-6-luna',
          effort: 'low',
          approvalPolicy: 'untrusted',
          sandbox: 'workspace-write',
          rootMode: true,
          planMode: false,
          onOpenSettings: () {},
          onOpenPermissions: () {},
          onTogglePlan: () {},
        ),
      ),
    );

    expect(find.text('Root'), findsOneWidget);
    expect(find.text('Default'), findsNothing);
  });

  testWidgets('DeepSeek exposes app-server controls and CC Pocket effort', (
    tester,
  ) async {
    var openedEffort = false;
    await tester.pumpWidget(
      app(
        CcpocketNativeModeBar(
          model: 'deepseek-flash',
          effort: 'low',
          approvalPolicy: 'on-request',
          sandbox: 'workspace-write',
          planMode: false,
          onOpenSettings: () {},
          onOpenPermissions: () {},
          onTogglePlan: () {},
          onOpenEffortSettings: () => openedEffort = true,
          showCodexControls: true,
        ),
      ),
    );

    expect(find.text('Deepseek Flash'), findsOneWidget);
    expect(find.text('Light'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('local_codex_plan_mode_chip')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('local_codex_execution_mode_chip')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey('local_codex_effort_chip')));
    expect(openedEffort, isTrue);
  });

  testWidgets('DeepSeek effort picker writes the selected effort', (
    tester,
  ) async {
    String? selectedEffort;
    late BuildContext modeBarContext;
    await tester.pumpWidget(
      app(
        Builder(
          builder: (context) {
            modeBarContext = context;
            return CcpocketNativeModeBar(
              model: 'deepseek-flash',
              effort: 'low',
              approvalPolicy: 'on-request',
              sandbox: 'workspace-write',
              planMode: false,
              onOpenSettings: () {},
              onOpenPermissions: () {},
              onTogglePlan: () {},
              onOpenEffortSettings: () {
                unawaited(
                  showCcpocketNativeProviderEffortSettings(
                    context: modeBarContext,
                    model: 'deepseek-flash',
                    effort: 'low',
                    onEffortChanged: (value) => selectedEffort = value,
                  ),
                );
              },
              showCodexControls: true,
            );
          },
        ),
        locale: const Locale('zh'),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('local_codex_effort_chip')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('codex_settings_advanced')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('codex_effort_advanced')));
    await tester.pumpAndSettle();

    expect(find.text('低'), findsWidgets);
    expect(find.text('高'), findsOneWidget);
    expect(find.text('最大'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('codex_effort_high_option')));
    await tester.pumpAndSettle();

    expect(selectedEffort, 'high');
  });

  testWidgets('labels the read-only execution mode explicitly in Chinese', (
    tester,
  ) async {
    await tester.pumpWidget(
      app(
        CcpocketNativeModeBar(
          model: 'gpt-5.6-luna',
          effort: 'low',
          approvalPolicy: 'on-request',
          sandbox: 'read-only',
          planMode: false,
          onOpenSettings: () {},
          onOpenPermissions: () {},
          onTogglePlan: () {},
        ),
        locale: const Locale('zh'),
      ),
    );

    expect(find.text('只读'), findsOneWidget);
    expect(find.text('自定义'), findsNothing);
  });

  testWidgets('uses the original CC Pocket question widget for user input', (
    tester,
  ) async {
    String? answer;
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'question-1',
      requestMethod: 'item/tool/requestUserInput',
      params: <String, dynamic>{
        'questions': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'language',
            'header': 'Language',
            'question': 'Which language should Codex use?',
            'options': <Map<String, String>>[
              <String, String>{'label': 'Dart', 'value': 'Dart'},
            ],
          },
        ],
      },
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeUserInputPanel(
          request: request,
          onAnswer: (value) => answer = value,
          onCancel: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local_codex_user_input_panel')),
      findsOneWidget,
    );
    expect(find.text('Which language should Codex use?'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('ask_option_0_Dart')));
    await tester.pumpAndSettle();
    expect(answer, 'Dart');
  });

  testWidgets('renders and submits an MCP elicitation form', (tester) async {
    String? submittedAction;
    Map<String, dynamic>? submittedContent;
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'elicitation-form-1',
      requestMethod: 'mcpServer/elicitation/request',
      params: <String, dynamic>{
        'serverName': 'fixture-mcp',
        'mode': 'form',
        'message': 'Choose a deployment target',
        'requestedSchema': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{
            'target': <String, dynamic>{
              'type': 'string',
              'title': 'Target name',
            },
            'confirmed': <String, dynamic>{
              'type': 'boolean',
              'title': 'Confirm',
              'default': true,
            },
          },
          'required': <String>['target'],
        },
      },
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeMcpElicitationPanel(
          request: request,
          onRespond:
              ({
                required String action,
                Map<String, dynamic>? content,
                String? persist,
              }) async {
                submittedAction = action;
                submittedContent = content;
              },
          onOpenUrl: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local_codex_mcp_elicitation_panel')),
      findsOneWidget,
    );
    expect(find.text('fixture-mcp requests input'), findsOneWidget);
    expect(find.text('Choose a deployment target'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('local_codex_mcp_field_target')),
      'test-device',
    );
    await tester.tap(find.byKey(const ValueKey('local_codex_mcp_accept')));
    await tester.pumpAndSettle();

    expect(submittedAction, 'accept');
    expect(submittedContent, <String, dynamic>{
      'target': 'test-device',
      'confirmed': true,
    });
  });

  testWidgets('MCP tool approval only offers advertised persistence scopes', (
    tester,
  ) async {
    String? submittedAction;
    String? submittedPersist;
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'elicitation-approval-1',
      requestMethod: 'mcpServer/elicitation/request',
      params: <String, dynamic>{
        'serverName': 'fixture-mcp',
        'mode': 'form',
        'message': 'Run this tool?',
        '_meta': <String, dynamic>{
          'codex_approval_kind': 'mcp_tool_call',
          'persist': <String>['session'],
          'tool_name': 'write_record',
          'tool_params': <String, dynamic>{'id': 'A-17'},
        },
        'requestedSchema': <String, dynamic>{
          'type': 'object',
          'properties': <String, dynamic>{},
        },
      },
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeMcpElicitationPanel(
          request: request,
          onRespond:
              ({
                required String action,
                Map<String, dynamic>? content,
                String? persist,
              }) async {
                submittedAction = action;
                submittedPersist = persist;
              },
          onOpenUrl: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local_codex_mcp_allow_session')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('local_codex_mcp_allow_always')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('local_codex_mcp_allow_session')),
    );
    await tester.pumpAndSettle();

    expect(submittedAction, 'accept');
    expect(submittedPersist, 'session');

    await tester.pumpWidget(
      app(
        CcpocketNativeMcpElicitationPanel(
          request: request,
          allowPersistentApprovals: false,
          onRespond: ({
            required String action,
            Map<String, dynamic>? content,
            String? persist,
          }) async {},
          onOpenUrl: (_) async => true,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local_codex_mcp_allow_session')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('local_codex_mcp_allow_always')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('local_codex_mcp_allow_once')),
      findsOneWidget,
    );
  });

  testWidgets('MCP URL elicitation requires explicit open before continue', (
    tester,
  ) async {
    String? submittedAction;
    var openCount = 0;
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'elicitation-url-1',
      requestMethod: 'mcpServer/elicitation/request',
      params: <String, dynamic>{
        'serverName': 'fixture-mcp',
        'mode': 'url',
        'message': 'Authorize access in the browser',
        'url': 'https://example.test/oauth',
        'elicitationId': 'login-1',
      },
    );
    await tester.pumpWidget(
      app(
        CcpocketNativeMcpElicitationPanel(
          request: request,
          onRespond:
              ({
                required String action,
                Map<String, dynamic>? content,
                String? persist,
              }) async {
                submittedAction = action;
              },
          onOpenUrl: (_) async {
            openCount++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final continueButton = tester.widget<FilledButton>(
      find.byKey(const ValueKey('local_codex_mcp_url_continue')),
    );
    expect(continueButton.onPressed, isNull);
    await tester.tap(find.byKey(const ValueKey('local_codex_mcp_open_url')));
    await tester.pumpAndSettle();
    expect(openCount, 1);
    await tester.tap(
      find.byKey(const ValueKey('local_codex_mcp_url_continue')),
    );
    await tester.pumpAndSettle();
    expect(submittedAction, 'accept');

    var unsafeOpenCount = 0;
    const unsafeRequest = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'elicitation-url-unsafe',
      requestMethod: 'mcpServer/elicitation/request',
      params: <String, dynamic>{
        'serverName': 'fixture-mcp',
        'mode': 'url',
        'message': 'Unsafe URL fixture',
        'url': 'javascript:alert(1)',
      },
    );
    await tester.pumpWidget(
      app(
        CcpocketNativeMcpElicitationPanel(
          request: unsafeRequest,
          onRespond: ({
            required String action,
            Map<String, dynamic>? content,
            String? persist,
          }) async {},
          onOpenUrl: (_) async {
            unsafeOpenCount++;
            return true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('local_codex_mcp_open_url')),
      findsNothing,
    );
    expect(
      find.text('Only HTTPS or loopback HTTP URLs can be opened.'),
      findsOneWidget,
    );
    expect(unsafeOpenCount, 0);
  });

  testWidgets('renders a CC Pocket diff preview for file approval', (
    tester,
  ) async {
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'file-1',
      requestMethod: 'item/fileChange/requestApproval',
      params: <String, dynamic>{
        'changes': <Object?>[
          <String, String>{'path': 'lib/main.dart'},
        ],
      },
    );
    const preview = AgentFileChangePreview(
      path: 'lib/main.dart',
      kind: 'modify',
      diff:
          '--- a/lib/main.dart\n+++ b/lib/main.dart\n@@ -1 +1 @@\n-old\n+new\n',
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeApprovalPanel(
          approval: request,
          fileChanges: const <AgentFileChangePreview>[preview],
          onApprove: () {},
          onReject: () {},
        ),
        locale: const Locale('zh'),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('local_codex_file_change_preview')),
      findsOneWidget,
    );
    expect(find.text('lib/main.dart'), findsNWidgets(2));
    expect(find.text('文件变更预览'), findsOneWidget);
    expect(find.text('文件变更审批'), findsOneWidget);
    expect(find.text('允许修改 lib/main.dart'), findsOneWidget);
    expect(find.text('File Change Approval'), findsNothing);

    final changeTile = find.byKey(
      const ValueKey('local_codex_file_change_lib/main.dart'),
    );
    expect(tester.getSize(changeTile).height, greaterThanOrEqualTo(48));
    await tester.tap(changeTile);
    await tester.pumpAndSettle();
    expect(find.text('- old'), findsOneWidget);
    expect(find.text('+ new'), findsOneWidget);
  });

  testWidgets('shows the session approval only when Codex offers it', (
    tester,
  ) async {
    var approvedForSession = false;
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'command-1',
      requestMethod: 'item/commandExecution/requestApproval',
      params: <String, dynamic>{
        'command': 'npm test',
        'availableDecisions': <String>['accept', 'acceptForSession', 'decline'],
      },
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeApprovalPanel(
          approval: request,
          onApprove: () {},
          onApproveForSession: () => approvedForSession = true,
          onReject: () {},
        ),
      ),
    );

    final button = find.byKey(
      const ValueKey('local_codex_approve_for_session_button'),
    );
    expect(button, findsOneWidget);
    for (final key in <String>[
      'local_codex_reject_button',
      'local_codex_approve_for_session_button',
      'local_codex_approve_button',
    ]) {
      expect(
        tester.getSize(find.byKey(ValueKey(key))).height,
        greaterThanOrEqualTo(48),
        reason: key,
      );
    }
    await tester.tap(button);
    expect(approvedForSession, isTrue);
  });

  testWidgets('hides session approval when unsupported or for Root sessions', (
    tester,
  ) async {
    const unavailable = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'command-2',
      requestMethod: 'item/commandExecution/requestApproval',
      params: <String, dynamic>{
        'command': 'npm test',
        'availableDecisions': <String>['accept', 'decline'],
      },
    );
    const available = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'command-3',
      requestMethod: 'item/commandExecution/requestApproval',
      params: <String, dynamic>{
        'command': 'npm test',
        'availableDecisions': <String>['accept', 'acceptForSession', 'decline'],
      },
    );
    const key = ValueKey('local_codex_approve_for_session_button');

    await tester.pumpWidget(
      app(
        CcpocketNativeApprovalPanel(
          approval: unavailable,
          onApprove: () {},
          onApproveForSession: () {},
          onReject: () {},
        ),
      ),
    );
    expect(find.byKey(key), findsNothing);

    await tester.pumpWidget(
      app(
        CcpocketNativeApprovalPanel(
          approval: available,
          onApprove: () {},
          onApproveForSession: () {},
          onReject: () {},
          allowPersistentApprovals: false,
        ),
      ),
    );
    expect(find.byKey(key), findsNothing);
  });

  testWidgets('renders and returns the advertised command-prefix rule', (
    tester,
  ) async {
    Map<String, dynamic>? selectedDecision;
    const decision = <String, dynamic>{
      'acceptWithExecpolicyAmendment': <String, dynamic>{
        'execpolicy_amendment': <String>['npm', 'test'],
      },
    };
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'command-policy-1',
      requestMethod: 'item/commandExecution/requestApproval',
      params: <String, dynamic>{
        'command': 'npm test',
        'availableDecisions': <Object>['accept', decision, 'cancel'],
      },
    );

    await tester.pumpWidget(
      app(
        CcpocketNativeApprovalPanel(
          approval: request,
          onApprove: () {},
          onApplyPolicyAmendment: (value) => selectedDecision = value,
          onReject: () {},
        ),
      ),
    );

    final ruleButton = find.byKey(
      const ValueKey('local_codex_persistent_approval_0'),
    );
    expect(ruleButton, findsOneWidget);
    await tester.tap(ruleButton);
    expect(selectedDecision, decision);
  });

  testWidgets('localizes persistent approval choices in Japanese and Korean', (
    tester,
  ) async {
    const decision = <String, dynamic>{
      'acceptWithExecpolicyAmendment': <String, dynamic>{
        'execpolicy_amendment': <String>['npm', 'test'],
      },
    };
    const request = CodexSessionEvent(
      type: CodexSessionEventType.approval,
      requestId: 'command-policy-localized',
      requestMethod: 'item/commandExecution/requestApproval',
      params: <String, dynamic>{
        'command': 'npm test',
        'availableDecisions': <Object>['accept', decision, 'cancel'],
      },
    );

    Widget panel() => CcpocketNativeApprovalPanel(
      approval: request,
      onApprove: () {},
      onApplyPolicyAmendment: (_) {},
      onReject: () {},
    );

    await tester.pumpWidget(app(panel(), locale: const Locale('ja')));
    expect(find.text('今後このコマンド接頭辞を許可：npm test'), findsOneWidget);

    await tester.pumpWidget(app(panel(), locale: const Locale('ko')));
    expect(find.text('이 명령어 접두사를 계속 허용: npm test'), findsOneWidget);
  });
}
