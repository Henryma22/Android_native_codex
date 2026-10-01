import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/ccpocket_local_settings.dart';
import 'package:codex/core/application/codex_model_catalog.dart';
import 'package:codex/core/domain/runtime.dart';
import 'package:codex/backends/compatibility/linux_compatibility_backend.dart';
import 'package:codex/services/codex_cli_updater.dart';

void main() {
  testWidgets('settings presents local Linux/PRoot as the only Codex runtime', (
    tester,
  ) async {
    const runtime = CodexRuntimeDescriptor(state: CodexRuntimeState.missing);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          compatibilityRuntime: Future.value(
            CompatibilityRuntimeDescriptor(
              state: CompatibilityRuntimeState.verified,
              version: 'rootfs-test',
            ),
          ),
          onInstallCompatibilityRootfs: () async => null,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings_runtime_tile')), findsOneWidget);
    expect(
      find.textContaining('Codex CLI 与 app-server 在本机 Linux/PRoot 中运行'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings_compatibility_rootfs_install')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('settings_android_codex_native_update')),
      findsNothing,
    );
    expect(
      find.byKey(const ValueKey('settings_android_codex_native_restore')),
      findsNothing,
    );
    expect(find.textContaining('导入 Codex 运行环境'), findsNothing);
  });

  testWidgets('settings do not expose the retired Android toolchain route', (
    tester,
  ) async {
    const runtime = CodexRuntimeDescriptor(state: CodexRuntimeState.missing);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('settings_native_toolchain_tile')),
      findsNothing,
    );
    expect(find.textContaining('原生工具链'), findsNothing);
    expect(find.textContaining('Debian guest 工具'), findsOneWidget);
  });

  testWidgets('does not expose native Codex probe or restore diagnostics', (
    tester,
  ) async {
    const runtime = CodexRuntimeDescriptor(state: CodexRuntimeState.missing);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('No App UID'), findsNothing);
    expect(find.textContaining('恢复 Android 原生运行时'), findsNothing);
    expect(
      find.byKey(const ValueKey('settings_android_codex_native_restore')),
      findsNothing,
    );
  });

  testWidgets('reasoning effort, theme, and language choices update', (
    tester,
  ) async {
    String? selectedEffort;
    String? selectedApproval;
    String? selectedSandbox;
    ThemeMode? selectedTheme;
    Locale? selectedLocale;
    const runtime = CodexRuntimeDescriptor(state: CodexRuntimeState.missing);
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          modelCatalog: Future.value(
            const CodexModelCatalog(
              models: <CodexModelDescriptor>[
                CodexModelDescriptor(
                  id: 'gpt-5.6-luna',
                  displayName: 'GPT-5.6 Luna',
                  reasoningEfforts: <String>['minimal', 'low', 'high'],
                ),
              ],
            ),
          ),
          onEffortChanged: (value) => selectedEffort = value,
          onApprovalPolicyChanged: (value) => selectedApproval = value,
          onSandboxChanged: (value) => selectedSandbox = value,
          onThemeModeChanged: (value) => selectedTheme = value,
          onLocaleChanged: (value) => selectedLocale = value,
          approvalPolicy: 'on-request',
          sandbox: 'workspace-write',
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('新会话默认推理档位'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新会话默认推理档位'));
    await tester.pumpAndSettle();
    expect(find.text('最小'), findsOneWidget);
    expect(find.text('minimal'), findsNothing);
    await tester.tap(find.text('高'));
    await tester.pumpAndSettle();
    expect(selectedEffort, 'high');
    expect(find.text('高'), findsOneWidget);

    await tester.ensureVisible(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('主题'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('深色'));
    await tester.pumpAndSettle();
    expect(selectedTheme, ThemeMode.dark);
    expect(find.text('深色'), findsOneWidget);

    await tester.dragUntilVisible(
      find.text('新会话默认审批策略'),
      find.byKey(const ValueKey('codex_settings_scroll')),
      const Offset(0, 450),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新会话默认审批策略'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('失败时审批'));
    await tester.pumpAndSettle();
    expect(selectedApproval, 'on-failure');

    await tester.dragUntilVisible(
      find.text('新会话默认沙盒'),
      find.byKey(const ValueKey('codex_settings_scroll')),
      const Offset(0, -300),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('新会话默认沙盒'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('只读'));
    await tester.pumpAndSettle();
    expect(selectedSandbox, 'read-only');

    await tester.dragUntilVisible(
      find.text('语言'),
      find.byKey(const ValueKey('codex_settings_scroll')),
      const Offset(0, -500),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('语言'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English'));
    await tester.pumpAndSettle();
    expect(selectedLocale, const Locale('en'));
    expect(find.text('Settings'), findsOneWidget);
  });

  testWidgets('model setting loads the CLI catalog on demand', (tester) async {
    var changed = '';
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(
            const CodexRuntimeDescriptor(
              state: CodexRuntimeState.verified,
              command: 'codex',
              version: 'fixture',
            ),
          ),
          onRefresh: () => Future.value(
            const CodexRuntimeDescriptor(
              state: CodexRuntimeState.verified,
              command: 'codex',
              version: 'fixture',
            ),
          ),
          model: 'gpt-5.6-luna',
          onRefreshModelCatalog: () => Future.value(
            const CodexModelCatalog(
              models: <CodexModelDescriptor>[
                CodexModelDescriptor(
                  id: 'gpt-5.6-luna',
                  displayName: 'GPT-5.6 Luna',
                  reasoningEfforts: <String>['low'],
                ),
                CodexModelDescriptor(
                  id: 'gpt-5.5',
                  displayName: 'GPT-5.5',
                  reasoningEfforts: <String>['low'],
                ),
              ],
            ),
          ),
          onModelChanged: (value) => changed = value,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings_model_tile')));
    await tester.pumpAndSettle();

    expect(find.text('新会话默认模型'), findsNWidgets(2));
    expect(find.text('gpt-5.5'), findsOneWidget);
    await tester.tap(find.text('gpt-5.5'));
    expect(changed, 'gpt-5.5');
  });

  testWidgets('CLI update refreshes models before the next model selection', (
    tester,
  ) async {
    var refreshCount = 0;
    const updatedCatalog = CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: 'gpt-6-luna',
          displayName: 'GPT-6 Luna',
          reasoningEfforts: <String>['low'],
        ),
        CodexModelDescriptor(
          id: 'gpt-6-sol',
          displayName: 'GPT-6 Sol',
          reasoningEfforts: <String>['low', 'high'],
        ),
      ],
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(
            const CodexRuntimeDescriptor(
              state: CodexRuntimeState.verified,
              command: 'codex',
              version: '0.154.0',
            ),
          ),
          onRefresh: () => Future.value(
            const CodexRuntimeDescriptor(
              state: CodexRuntimeState.verified,
              command: 'codex',
              version: '0.154.0',
            ),
          ),
          model: 'gpt-5.6-luna',
          modelCatalog: Future.value(
            const CodexModelCatalog(
              models: <CodexModelDescriptor>[
                CodexModelDescriptor(
                  id: 'gpt-5.6-luna',
                  displayName: 'GPT-5.6 Luna',
                  reasoningEfforts: <String>['low'],
                ),
              ],
            ),
          ),
          onRefreshModelCatalog: () async {
            refreshCount++;
            return updatedCatalog;
          },
          onUpdateCompatibilityCodex: () async => const CodexCliUpdateResult(
            installedVersion: '0.156.1',
            availableVersion: '0.156.1',
            updated: true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('settings_codex_cli_update')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('检查并更新'));
    await tester.pumpAndSettle();

    expect(refreshCount, 1);
    await tester.tap(find.byKey(const ValueKey('settings_model_tile')));
    await tester.pumpAndSettle();
    expect(find.text('gpt-6-luna'), findsOneWidget);
    expect(find.text('gpt-6-sol'), findsOneWidget);
  });

  testWidgets('CLI rollback is explicit and refreshes the model catalog', (
    tester,
  ) async {
    var rollbackCount = 0;
    var refreshCount = 0;
    const runtime = CodexRuntimeDescriptor(
      state: CodexRuntimeState.verified,
      command: 'codex',
      version: '0.158.0',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: CodexPocketSettingsPage(
          runtime: Future.value(runtime),
          onRefresh: () async => runtime,
          onRollbackCompatibilityCodex: () async {
            rollbackCount++;
            return const CodexCliUpdateResult(
              installedVersion: '0.157.0',
              availableVersion: '0.157.0',
              updated: true,
              rolledBack: true,
            );
          },
          onRefreshModelCatalog: () async {
            refreshCount++;
            return const CodexModelCatalog(models: <CodexModelDescriptor>[]);
          },
          locale: const Locale('zh'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('settings_codex_cli_rollback')),
    );
    await tester.tap(find.byKey(const ValueKey('settings_codex_cli_rollback')));
    await tester.pumpAndSettle();
    expect(find.text('回退 Codex CLI？'), findsOneWidget);
    expect(find.textContaining('正在运行的会话不会被终止'), findsOneWidget);

    await tester.tap(find.text('确认回退'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(rollbackCount, 1);
    expect(refreshCount, 1);
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Codex CLI 已回退至 0.157.0'), findsOneWidget);
  });
}
