import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/backends/fake/fake_backend.dart';
import 'package:codex/core/domain/execution.dart';
import 'package:codex/main.dart';

void main() {
  const probeChannel = MethodChannel('io.henry.codex/native_probe');
  const localChannel = MethodChannel('io.henry.codex/local_backend');

  testWidgets('thread surface does not expose the login panel', (tester) async {
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      probeChannel,
      (call) async {
        if (call.method == 'probeCodexRuntime') {
          return <Object?, Object?>{
            'state': 'verified',
            'command': 'codex',
            'version': 'codex fixture',
            'identity': 'app',
          };
        }
        return null;
      },
    );
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      localChannel,
      (_) async => null,
    );
    addTearDown(() async {
      tester.binding.defaultBinaryMessenger
        ..setMockMethodCallHandler(probeChannel, null)
        ..setMockMethodCallHandler(localChannel, null);
    });

    final backend = _LoginBackend();
    final workspace = (await backend.listWorkspaces()).single;
    await tester.pumpWidget(
      MaterialApp(
        home: LocalSessionPage(backend: backend, workspace: workspace),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('local_codex_auth_card')), findsNothing);
    expect(
      find.byKey(const ValueKey('local_codex_login_button')),
      findsNothing,
    );
  });
}

class _LoginBackend extends FakeBackend {
  final process = _LoginProcess();
  ExecutionRequest? request;

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    this.request = request;
    return process;
  }
}

class _LoginProcess implements InteractiveExecution {
  final _events = StreamController<ExecutionEvent>();
  final stoppedFuture = Completer<void>();
  var stopped = false;

  @override
  Stream<ExecutionEvent> get events => _events.stream;

  void emit(ExecutionEvent event) => _events.add(event);

  @override
  Future<void> write(String value) async {}

  @override
  Future<void> stop() async {
    stopped = true;
    if (!stoppedFuture.isCompleted) stoppedFuture.complete();
    await _events.close();
  }
}
