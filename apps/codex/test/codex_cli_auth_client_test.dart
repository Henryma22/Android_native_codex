import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/codex_auth_client.dart';
import 'package:codex/core/application/codex_cli_auth_client.dart';
import 'package:codex/core/domain/execution.dart';

void main() {
  test(
    'browser login keeps the CLI process and emits its verified URL',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _FakeInteractiveExecution();
      final client = CodexCliAuthClient(
        backend: backend,
        workspace: workspace,
        command: 'codex',
        identity: ExecutionIdentity.app,
        processFactory: (_) => process,
      );
      final events = <CodexAuthEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start(mode: CodexAuthMode.browser);
      process.emit(
        const ExecutionEvent.stdout(
          'Starting local login server\n'
          'https://auth.openai.com/oauth/authorize?client_id=codex&'
          'response_type=code&scope=openid&code_challenge=x&'
          'code_challenge_method=S256&state=y&'
          'redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback\n',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(client.isLoginPending, isTrue);
      expect(process.stdinClosed, isFalse);
      expect(
        events
            .singleWhere((event) => event.type == CodexAuthEventType.challenge)
            .challenge
            ?.verificationUrl,
        contains('/oauth/authorize'),
      );

      process.emit(const ExecutionEvent.exit(0));
      await Future<void>.delayed(Duration.zero);
      expect(
        events
            .singleWhere((event) => event.type == CodexAuthEventType.exit)
            .exitCode,
        0,
      );

      await client.dispose();
      await subscription.cancel();
    },
  );

  test('API key login sends the key only through stdin', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _FakeInteractiveExecution();
    final client = CodexCliAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => process,
    );
    final events = <CodexAuthEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret');
    expect(process.writes, <String>['sk-test-secret\n']);
    expect(process.stdinClosed, isTrue);
    expect(
      events.where((event) => event.message?.contains('sk-test') ?? false),
      isEmpty,
    );

    process.emit(const ExecutionEvent.exit(0));
    await Future<void>.delayed(Duration.zero);
    expect(
      events.where((event) => event.type == CodexAuthEventType.exit),
      hasLength(1),
    );

    await client.dispose();
    await subscription.cancel();
  });
}

class _FakeInteractiveExecution
    implements InteractiveExecution, StdinClosableExecution {
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  var stdinClosed = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  void emit(ExecutionEvent event) => _events.add(event);

  @override
  Future<void> write(String value) async => writes.add(value);

  @override
  Future<void> closeStdin() async => stdinClosed = true;

  @override
  Future<void> stop() async => _events.close();
}
