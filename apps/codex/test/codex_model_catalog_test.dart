import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/application/codex_model_catalog.dart';
import 'package:codex/core/domain/execution.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'loads every paginated model from the local app-server catalog',
    () async {
      final backend = FakeBackend();
      final workspace = (await backend.listWorkspaces()).single;
      final process = _ModelCatalogProcess(emitCacheWarning: true);

      final catalog = await CodexModelCatalogClient.load(
        backend: backend,
        workspace: workspace,
        command: 'codex',
        identity: ExecutionIdentity.app,
        processFactory: (_) => process,
      );

      expect(catalog.modelIds, ['gpt-5.6-luna', 'gpt-5.5']);
      expect(catalog.models.last.hidden, isTrue);
      expect(catalog.modelEfforts['gpt-5.6-luna'], ['low', 'high']);
      expect(process.modelListRequests, 2);
    },
  );

  test(
    'uses one app-server catalog before spawning CLI catalog commands',
    () async {
      final backend = _FastModelCatalogBackend();
      final workspace = (await backend.listWorkspaces()).single;

      final catalog = await CodexModelCatalogClient.load(
        backend: backend,
        workspace: workspace,
        command: 'codex',
        identity: ExecutionIdentity.app,
      );

      expect(catalog.modelIds, ['gpt-5.6-luna', 'gpt-5.5']);
      expect(backend.appServerStarts, 1);
      expect(backend.cliCatalogStarts, 0);
    },
  );

  test('uses the bounded CLI catalog when there is no active thread', () async {
    final backend = _FastModelCatalogBackend();
    final workspace = (await backend.listWorkspaces()).single;

    final catalog = await CodexModelCatalogClient.load(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
      preferCliCatalog: true,
    );

    expect(catalog.modelIds, ['gpt-6-luna']);
    expect(backend.appServerStarts, 0);
    expect(backend.cliCatalogStarts, 1);
  });

  test('closes stdin before reading the CLI model catalog', () async {
    final backend = _EofModelCatalogBackend();
    final workspace = (await backend.listWorkspaces()).single;

    final catalog = await CodexModelCatalogClient.load(
      backend: backend,
      workspace: workspace,
      command: 'codex',
      identity: ExecutionIdentity.app,
    );

    expect(catalog.modelIds, ['gpt-6-luna']);
    expect(backend.cliProcesses, isNotEmpty);
    expect(
      backend.cliProcesses.every((process) => process.stdinClosed),
      isTrue,
    );
  });

  test('keeps the selected model when the server catalog omits it', () {
    const catalog = CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: 'gpt-5.6-luna',
          displayName: 'Luna',
          reasoningEfforts: <String>['low'],
        ),
      ],
    );

    expect(catalog.withCurrentModel('local-test').modelIds, [
      'local-test',
      'gpt-5.6-luna',
    ]);
  });

  test('recommends the first visible Luna from the current CLI catalog', () {
    const catalog = CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: 'gpt-6-sol',
          displayName: 'GPT-6 Sol',
          reasoningEfforts: <String>['low', 'high'],
        ),
        CodexModelDescriptor(
          id: 'gpt-6-luna',
          displayName: 'GPT-6 Luna',
          reasoningEfforts: <String>['low'],
        ),
        CodexModelDescriptor(
          id: 'gpt-5.6-luna-preview',
          displayName: 'GPT-5.6 Luna Preview',
          reasoningEfforts: <String>['low'],
          hidden: true,
        ),
      ],
    );

    expect(catalog.recommendedDefaultModel?.id, 'gpt-6-luna');
  });

  test('falls back to the first visible CLI model without a Luna option', () {
    const catalog = CodexModelCatalog(
      models: <CodexModelDescriptor>[
        CodexModelDescriptor(
          id: 'hidden-model',
          displayName: 'Hidden',
          reasoningEfforts: <String>['low'],
          hidden: true,
        ),
        CodexModelDescriptor(
          id: 'provider-model',
          displayName: 'Provider model',
          reasoningEfforts: <String>['low'],
        ),
      ],
    );

    expect(catalog.recommendedDefaultModel?.id, 'provider-model');
  });
}

class _ModelCatalogProcess implements InteractiveExecution {
  _ModelCatalogProcess({this.emitCacheWarning = false});

  final bool emitCacheWarning;
  final _events = StreamController<ExecutionEvent>();
  var modelListRequests = 0;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {
    final request = jsonDecode(value) as Map<String, dynamic>;
    final id = request['id'];
    if (id is! int) return;
    if (emitCacheWarning && !_warningSent) {
      _warningSent = true;
      _events.add(
        const ExecutionEvent.error(
          'failed to load models cache: Permission denied (os error 13)',
        ),
      );
    }
    final result = switch (request['method']) {
      'initialize' => <String, dynamic>{},
      'model/list' => _modelPage(request['params']),
      _ => <String, dynamic>{},
    };
    if (_events.isClosed) return;
    _events.add(
      ExecutionEvent.stdout(
        '${jsonEncode(<String, dynamic>{'jsonrpc': '2.0', 'id': id, 'result': result})}\n',
      ),
    );
  }

  var _warningSent = false;

  Map<String, dynamic> _modelPage(Object? rawParams) {
    modelListRequests++;
    final params = rawParams is Map ? rawParams : const <String, dynamic>{};
    if (params['cursor'] == 'page-2') {
      return <String, dynamic>{
        'data': <Map<String, dynamic>>[
          <String, dynamic>{
            'id': 'gpt-5.5',
            'model': 'gpt-5.5',
            'displayName': 'GPT-5.5',
            'hidden': true,
            'supportedReasoningEfforts': <Map<String, String>>[
              <String, String>{'effort': 'low'},
            ],
          },
        ],
        'nextCursor': null,
      };
    }
    return <String, dynamic>{
      'data': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'gpt-5.6-luna',
          'model': 'gpt-5.6-luna',
          'displayName': 'GPT-5.6 Luna',
          'hidden': false,
          'supportedReasoningEfforts': <Map<String, String>>[
            <String, String>{'effort': 'low'},
            <String, String>{'effort': 'high'},
          ],
        },
      ],
      'nextCursor': 'page-2',
    };
  }

  @override
  Future<void> stop() async {
    if (!_events.isClosed) await _events.close();
  }
}

class _EofModelCatalogBackend extends FakeBackend {
  final cliProcesses = <_EofModelCatalogProcess>[];

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    if (request.argv.contains('debug') && request.argv.contains('models')) {
      final process = _EofModelCatalogProcess();
      cliProcesses.add(process);
      return process;
    }
    return super.startInteractive(request);
  }
}

class _FastModelCatalogBackend extends FakeBackend {
  var appServerStarts = 0;
  var cliCatalogStarts = 0;

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    if (request.argv.contains('app-server')) {
      appServerStarts++;
      return _ModelCatalogProcess();
    }
    if (request.argv.contains('debug') && request.argv.contains('models')) {
      cliCatalogStarts++;
      return _EofModelCatalogProcess();
    }
    return super.startInteractive(request);
  }
}

class _EofModelCatalogProcess
    implements InteractiveExecution, StdinClosableExecution {
  final _events = StreamController<ExecutionEvent>();
  var stdinClosed = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> closeStdin() async {
    if (stdinClosed) return;
    stdinClosed = true;
    _events.add(
      ExecutionEvent.stdout(
        jsonEncode(<String, Object?>{
              'models': <Map<String, Object?>>[
                <String, Object?>{
                  'id': 'gpt-6-luna',
                  'display_name': 'GPT-6 Luna',
                  'supported_reasoning_levels': <Map<String, String>>[
                    <String, String>{'effort': 'low'},
                  ],
                },
              ],
            }) +
            '\n',
      ),
    );
    _events.add(const ExecutionEvent.exit(0));
    await _events.close();
  }

  @override
  Future<void> stop() async {
    if (_events.isClosed) return;
    _events.add(const ExecutionEvent.exit(-1));
    await _events.close();
  }
}
