import 'package:codex/codex_mcp_settings.dart';
import 'package:codex/core/application/codex_mcp_server_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

void main() {
  testWidgets('localizes common MCP load errors in Chinese', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('zh'),
        supportedLocales: const <Locale>[Locale('zh'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: CodexMcpSettingsPage(
          onLoadServers: () async => throw const FormatException(
            'Codex MCP server config is not an object.',
          ),
          onLoadStatuses: () async => const <CodexMcpServerStatusSummary>[],
          onAddServer: (_) async {},
          onRemoveServer: (_) async {},
          onLogin: (_) async {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MCP 服务器配置格式无效。'), findsOneWidget);
    expect(
      find.text('Codex MCP server config is not an object.'),
      findsNothing,
    );
  });
}
