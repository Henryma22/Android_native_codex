import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/codex_permission_profile_summary.dart';
import 'package:codex/core/application/codex_session_client.dart';
import 'package:codex/core/domain/execution.dart';

void main() {
  test(
    'parses permission profile metadata without exposing unknown fields',
    () {
      final profiles = CodexPermissionProfileSummary.parseResponse(
        <String, dynamic>{
          'data': <Map<String, dynamic>>[
            <String, dynamic>{
              'id': ':danger-full-access',
              'description': null,
              'allowed': true,
              'filesystem': <String, dynamic>{'unexpected': true},
            },
            <String, dynamic>{
              'id': 'android-dev',
              'description': 'Android development',
              'allowed': false,
            },
          ],
          'nextCursor': null,
        },
      );

      expect(profiles, hasLength(2));
      expect(profiles.first.isBuiltIn, isTrue);
      expect(profiles.first.allowed, isTrue);
      expect(profiles.last.description, 'Android development');
      expect(profiles.last.displayLine(chinese: true), contains('不可用'));
    },
  );

  test(
    'uses named permission profiles when the app-server exposes them',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _PermissionProfileProcess();
      final client = CodexSessionClient(
        backend: backend,
        workspace: workspace,
        argv: const <String>['codex', 'app-server', '--listen', 'stdio://'],
        settings: const CodexTurnSettings(permissions: ':danger-full-access'),
        processFactory: (_) => process,
      );

      await client.start();
      final profiles = await client.readPermissionProfiles();
      expect(profiles.map((profile) => profile.id), contains(':workspace'));

      final start = process.messages.firstWhere(
        (message) => message['method'] == 'thread/start',
      );
      final startParams = start['params'] as Map<Object?, Object?>;
      expect(startParams['sandbox'], 'workspace-write');
      expect(startParams.containsKey('permissions'), isFalse);

      client.updateSettings(
        const CodexTurnSettings(
          permissions: ':read-only',
          sandbox: 'read-only',
        ),
      );
      await process.settingsUpdated.future;
      final update = process.messages.firstWhere(
        (message) => message['method'] == 'thread/settings/update',
      );
      final updateParams = update['params'] as Map<Object?, Object?>;
      expect(updateParams['permissions'], ':read-only');
      expect(updateParams.containsKey('sandboxPolicy'), isFalse);

      await client.sendPrompt('use the selected permission profile');
      final turn = process.messages.firstWhere(
        (message) => message['method'] == 'turn/start',
      );
      final turnParams = turn['params'] as Map<Object?, Object?>;
      expect(turnParams['permissions'], ':read-only');
      expect(turnParams.containsKey('sandboxPolicy'), isFalse);

      await client.dispose();
    },
  );
}

class _PermissionProfileProcess implements InteractiveExecution {
  final _events = StreamController<ExecutionEvent>();
  final messages = <Map<String, dynamic>>[];
  final settingsUpdated = Completer<void>();

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    final message = jsonDecode(value) as Map<Object?, Object?>;
    final normalized = <String, dynamic>{
      for (final entry in message.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
    messages.add(normalized);
    final method = normalized['method'];
    final id = normalized['id'];
    if (id == null) return;
    final params = normalized['params'] is Map
        ? (normalized['params'] as Map).cast<Object?, Object?>()
        : const <Object?, Object?>{};

    if (method == 'permissionProfile/list') {
      _respond(id, <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': ':read-only',
            'description': null,
            'allowed': true,
          },
          <String, dynamic>{
            'id': ':workspace',
            'description': null,
            'allowed': true,
          },
          <String, dynamic>{
            'id': ':danger-full-access',
            'description': null,
            'allowed': true,
          },
          <String, dynamic>{
            'id': 'android-dev',
            'description': 'Android development',
            'allowed': true,
          },
        ],
        'nextCursor': null,
      });
      return;
    }
    if (method == 'thread/start' || method == 'thread/resume') {
      _respond(id, <String, dynamic>{
        'thread': <String, String>{'id': 'profile-thread'},
      });
      return;
    }
    if (method == 'thread/settings/update') {
      if (!settingsUpdated.isCompleted) settingsUpdated.complete();
      _respond(id, <String, dynamic>{});
      return;
    }
    if (method == 'turn/start') {
      _emit(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/started',
        'params': <String, dynamic>{
          'threadId': params['threadId'],
          'turn': <String, String>{'id': 'profile-turn'},
        },
      });
      _emit(<String, dynamic>{
        'jsonrpc': '2.0',
        'method': 'turn/completed',
        'params': <String, dynamic>{
          'threadId': params['threadId'],
          'turn': <String, String>{'id': 'profile-turn', 'status': 'completed'},
        },
      });
      _respond(id, <String, dynamic>{
        'turn': <String, String>{'id': 'profile-turn'},
      });
      return;
    }
    _respond(id, <String, dynamic>{});
  }

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }

  void _respond(Object id, Map<String, dynamic> result) {
    _emit(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result});
  }

  void _emit(Map<String, dynamic> message) {
    _events.add(ExecutionEvent.stdout('${jsonEncode(message)}\n'));
  }
}
