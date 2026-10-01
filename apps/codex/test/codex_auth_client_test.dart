import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/codex_auth_client.dart';
import 'package:codex/core/domain/execution.dart';

void main() {
  test('accepts only the fixed device-auth URL and labelled code', () {
    final challenge = CodexAuthOutputParser.parse(
      '\u001b[32mOpen https://auth.openai.com/codex/device?user_code=AB12-34\u001b[0m\n'
      'Verification code: AB12-34\n',
    );

    expect(
      challenge,
      const CodexAuthChallenge(
        verificationUrl:
            'https://auth.openai.com/codex/device?user_code=AB12-34',
        oneTimeCode: 'AB12-34',
      ),
    );
  });

  test('accepts a code printed on the line after its label', () {
    final challenge = CodexAuthOutputParser.parse(
      'Open this URL: https://auth.openai.com/device.\n'
      'One-time code\n'
      'WXYZ-9876.\n',
    );

    expect(
      challenge,
      const CodexAuthChallenge(
        verificationUrl: 'https://auth.openai.com/device',
        oneTimeCode: 'WXYZ-9876',
      ),
    );
  });

  test('rejects arbitrary URLs and generic code diagnostics', () {
    expect(
      CodexAuthOutputParser.parse(
        'callback https://evil.example/device?user_code=AB12-34\n'
        'status code: 500\n',
      ),
      isNull,
    );
    expect(
      CodexAuthOutputParser.parse(
        'https://auth.openai.com/device?token=secret-token\n',
      ),
      isNull,
    );
  });

  test(
    'accepts a validated browser OAuth URL but rejects unsafe callbacks',
    () {
      final challenge = CodexAuthOutputParser.parse(
        'Continue in browser: '
        'https://auth.openai.com/oauth/authorize?'
        'client_id=codex&response_type=code&scope=openid%20profile&'
        'code_challenge=challenge&code_challenge_method=S256&state=state&'
        'redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback\n',
      );

      expect(challenge?.oneTimeCode, isNull);
      expect(challenge?.verificationUrl, contains('/oauth/authorize'));
      expect(
        CodexAuthOutputParser.parse(
          'https://auth.openai.com/oauth/authorize?client_id=codex&'
          'response_type=code&scope=openid&code_challenge=x&'
          'code_challenge_method=S256&state=y&'
          'redirect_uri=https%3A%2F%2Fevil.example%2Fcallback',
        ),
        isNull,
      );
    },
  );

  test('accepts additional browser OAuth query parameters', () {
    final challenge = CodexAuthOutputParser.parse(
      'https://auth.openai.com/oauth/authorize?client_id=codex&'
      'response_type=code&scope=openid&code_challenge=x&'
      'code_challenge_method=S256&state=y&foo=server-added&'
      'redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback',
    );

    expect(challenge?.verificationUrl, contains('/oauth/authorize'));
  });

  test(
    'emits a safe challenge and never forwards raw process output',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _FakeInteractiveExecution();
      final client = CodexAuthClient(
        backend: backend,
        workspace: workspace,
        command: 'codex',
        identity: ExecutionIdentity.app,
        processFactory: (_) => process,
      );
      final events = <CodexAuthEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start();
      await Future<void>.delayed(Duration.zero);
      final challenge = events
          .where((event) => event.type == CodexAuthEventType.challenge)
          .single
          .challenge;
      expect(challenge?.oneTimeCode, 'AB12-34');
      expect(
        events.where(
          (event) => event.message?.contains('private-token') ?? false,
        ),
        isEmpty,
      );

      process.emit(const ExecutionEvent.error('private-token=must-not-leak'));
      await Future<void>.delayed(Duration.zero);
      expect(
        events.where(
          (event) => event.message?.contains('private-token') ?? false,
        ),
        isEmpty,
      );
      expect(
        events
            .lastWhere((event) => event.type == CodexAuthEventType.error)
            .message,
        'Login process failed.',
      );

      process.emit(const ExecutionEvent.exit(0));
      await Future<void>.delayed(Duration.zero);
      expect(
        events
            .where((event) => event.type == CodexAuthEventType.exit)
            .single
            .exitCode,
        0,
      );

      await client.dispose();
      await subscription.cancel();
    },
  );

  test('uses app-server API-key RPC without leaking it in events', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _FakeInteractiveExecution();
    final client = CodexAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => process,
    );
    final events = <CodexAuthEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret');
    final envelopes = process.writes
        .map((value) => jsonDecode(value) as Map<String, dynamic>)
        .toList();
    final login = envelopes.singleWhere(
      (value) => value['method'] == 'account/login/start',
    );
    expect(login['params'], <String, dynamic>{
      'type': 'apiKey',
      'apiKey': 'sk-test-secret',
    });

    await Future<void>.delayed(Duration.zero);
    // The start response only acknowledges the request. The app-server must
    // stay alive until the persisted-credential completion notification.
    expect(
      events.where((event) => event.type == CodexAuthEventType.exit),
      isEmpty,
    );
    process.emit(
      ExecutionEvent.stdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'account/login/completed',
          'params': <String, dynamic>{'loginId': null, 'success': true},
        })}\n',
      ),
    );
    await Future<void>.delayed(Duration.zero);
    expect(
      events
          .where((event) => event.type == CodexAuthEventType.exit)
          .single
          .exitCode,
      0,
    );
    expect(
      process.writes.where((value) => value.contains('private-token')),
      isEmpty,
    );

    await client.dispose();
    await subscription.cancel();
  });

  test('completes browser OAuth from the app-server completion event', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _FakeInteractiveExecution();
    final client = CodexAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => process,
    );
    final events = <CodexAuthEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start(mode: CodexAuthMode.browser);
    await Future<void>.delayed(Duration.zero);
    expect(
      events
          .singleWhere((event) => event.type == CodexAuthEventType.challenge)
          .challenge
          ?.verificationUrl,
      contains('/oauth/authorize'),
    );

    process.emit(
      ExecutionEvent.stdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'account/login/completed',
          'params': <String, dynamic>{'loginId': 'browser-login-1', 'success': true},
        })}\n',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .where((event) => event.type == CodexAuthEventType.exit)
          .single
          .exitCode,
      0,
    );
    expect(process.writes, isNot(anyElement(contains('account/login/cancel'))));

    await client.dispose();
    await subscription.cancel();
  });

  test('accepts account updated as a successful login completion', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _FakeInteractiveExecution();
    final client = CodexAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => process,
    );
    final events = <CodexAuthEvent>[];
    final subscription = client.events.listen(events.add);

    await client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret');
    process.emit(
      ExecutionEvent.stdout(
        '${jsonEncode(<String, dynamic>{
          'jsonrpc': '2.0',
          'method': 'account/updated',
          'params': <String, dynamic>{'authMode': 'apiKey'},
        })}\n',
      ),
    );
    await Future<void>.delayed(Duration.zero);

    expect(
      events
          .where((event) => event.type == CodexAuthEventType.exit)
          .single
          .exitCode,
      0,
    );

    await client.dispose();
    await subscription.cancel();
  });

  test('reads the account mode through the active app-server', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _FakeInteractiveExecution(accountReadType: 'apiKey');
    final client = CodexAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => process,
    );

    await client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret');
    expect(await client.readAccount(), CodexAuthMode.apiKey);

    await client.dispose();
  });

  test(
    'does not lose an API-key completion in the same stdout batch',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _FakeInteractiveExecution(
        apiKeyCompletesImmediately: true,
      );
      final client = CodexAuthClient(
        backend: backend,
        workspace: workspace,
        command: 'codex',
        identity: ExecutionIdentity.app,
        processFactory: (_) => process,
      );
      final events = <CodexAuthEvent>[];
      final subscription = client.events.listen(events.add);

      await client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret');
      await Future<void>.delayed(Duration.zero);

      expect(
        events
            .where((event) => event.type == CodexAuthEventType.exit)
            .single
            .exitCode,
        0,
      );

      await client.dispose();
      await subscription.cancel();
    },
  );

  test('surfaces a safe API-key RPC rejection', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final process = _FakeInteractiveExecution(apiKeyRejectsRequest: true);
    final client = CodexAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => process,
    );
    final events = <CodexAuthEvent>[];
    final subscription = client.events.listen(events.add);

    await expectLater(
      client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret'),
      throwsA(isA<StateError>()),
    );
    await Future<void>.delayed(Duration.zero);

    final error = events.lastWhere(
      (event) => event.type == CodexAuthEventType.error,
    );
    expect(error.message, contains('External auth is active'));
    expect(error.message, isNot(contains('sk-test-secret')));

    await client.dispose();
    await subscription.cancel();
  });

  test('cleans up a failed login before the next retry', () async {
    final backend = FakeBackend();
    final workspace = (await backend.listWorkspaces()).single;
    final first = _FakeInteractiveExecution(apiKeyRejectsRequest: true);
    final second = _FakeInteractiveExecution();
    var factoryCalls = 0;
    final client = CodexAuthClient(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      processFactory: (_) => factoryCalls++ == 0 ? first : second,
    );

    await expectLater(
      client.start(mode: CodexAuthMode.apiKey, apiKey: 'sk-test-secret'),
      throwsA(isA<StateError>()),
    );
    expect(first.stopped, isTrue);

    await client.start(mode: CodexAuthMode.browser);
    expect(factoryCalls, 2);
    expect(second.stopped, isFalse);

    await client.dispose();
  });
}

class _FakeInteractiveExecution implements InteractiveExecution {
  _FakeInteractiveExecution({
    this.apiKeyCompletesImmediately = false,
    this.apiKeyRejectsRequest = false,
    this.accountReadType,
  });

  final bool apiKeyCompletesImmediately;
  final bool apiKeyRejectsRequest;
  final String? accountReadType;
  final _events = StreamController<ExecutionEvent>();
  final writes = <String>[];
  var stopped = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  void emit(ExecutionEvent event) => _events.add(event);

  @override
  Future<void> write(String value) async {
    writes.add(value);
    final envelope = jsonDecode(value) as Map<String, dynamic>;
    final method = envelope['method'];
    final id = envelope['id'];
    if (id is! int) return;
    final params = envelope['params'];
    final loginType = params is Map ? params['type'] : null;
    if (apiKeyRejectsRequest &&
        method == 'account/login/start' &&
        loginType == 'apiKey') {
      if (!_events.isClosed) {
        _events.add(
          ExecutionEvent.stdout(
            '${jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'id': id,
              'error': <String, dynamic>{'code': -32600, 'message': 'External auth is active for sk-test-secret. Use account/logout first.'},
            })}\n',
          ),
        );
      }
      return;
    }
    final result = switch (method) {
      'initialize' => <String, dynamic>{},
      'account/read' => <String, dynamic>{
        'account': accountReadType == null
            ? null
            : <String, dynamic>{'type': accountReadType},
        'requiresOpenaiAuth': false,
      },
      'account/login/start' => switch (loginType) {
        'apiKey' => <String, dynamic>{'type': 'apiKey'},
        'chatgpt' => <String, dynamic>{
          'type': 'chatgpt',
          'loginId': 'browser-login-1',
          'authUrl':
              'https://auth.openai.com/oauth/authorize?client_id=codex&'
              'response_type=code&scope=openid%20profile&'
              'code_challenge=challenge&code_challenge_method=S256&'
              'state=state&redirect_uri=http%3A%2F%2Flocalhost%3A1455%2Fauth%2Fcallback',
        },
        _ => <String, dynamic>{
          'type': 'chatgptDeviceCode',
          'loginId': 'login-1',
          'verificationUrl': 'https://auth.openai.com/device?user_code=AB12-34',
          'userCode': 'AB12-34',
        },
      },
      _ => null,
    };
    if (result != null && !_events.isClosed) {
      final completion =
          apiKeyCompletesImmediately &&
              method == 'account/login/start' &&
              loginType == 'apiKey'
          ? '\n${jsonEncode(<String, dynamic>{
              'jsonrpc': '2.0',
              'method': 'account/login/completed',
              'params': <String, dynamic>{'loginId': null, 'success': true},
            })}'
          : '';
      _events.add(
        ExecutionEvent.stdout(
          '${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result})}$completion\n',
        ),
      );
    }
  }

  Future<void> closeStdin() async {}

  @override
  Future<void> stop() async {
    stopped = true;
    await _events.close();
  }
}
