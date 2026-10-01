import 'package:codex/backends/local/local_android_backend.dart';
import 'package:codex/core/domain/backend.dart';
import 'package:codex/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const methodChannel = MethodChannel('io.henry.codex/local_backend');
  const eventChannel = EventChannel('io.henry.codex/host_events');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(methodChannel, null);
    messenger.setMockStreamHandler(eventChannel, null);
  });

  test('creates a direct Host workspace with a validated contract', () async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (_, events) => events.endOfStream()),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'createHostWorkspace');
      expect(call.arguments, <String, Object?>{'name': 'demo-project'});
      return <String, Object?>{
        'name': 'demo-project',
        'relativePath': 'demo-project',
        'path': '/storage/emulated/0/Codex/Workspaces/demo-project',
      };
    });

    final workspace = await LocalAndroidBackend().createHostWorkspace(
      '  demo-project  ',
    );

    expect(workspace.backendId, 'local-android');
    expect(workspace.filesystemOwnerId, 'android-host');
    expect(
      workspace.hostPath,
      '/storage/emulated/0/Codex/Workspaces/demo-project',
    );
    expect(workspace.backendLocator, 'host://demo-project');
  });

  test('rejects traversal before crossing the platform channel', () async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (_, events) => events.endOfStream()),
    );
    var invoked = false;
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      invoked = true;
      return null;
    });

    await expectLater(
      LocalAndroidBackend().createHostWorkspace('../outside'),
      throwsA(
        isA<BackendException>().having(
          (error) => error.message,
          'message',
          contains('safe directory name'),
        ),
      ),
    );
    expect(invoked, isFalse);
  });

  test('parses durable Host and SAF backup metadata without content', () async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (_, events) => events.endOfStream()),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'listBackups');
      return <Object?>[
        <String, Object?>{
          'backupId': 'host-backup',
          'kind': 'host',
          'valid': true,
          'workspacePath': '/storage/emulated/0/Codex/Workspaces/demo-project',
          'relativePath': 'README.md',
          'sizeBytes': 12,
          'createdAtMs': 123,
          'version': 'before-host',
        },
        <String, Object?>{
          'backupId': 'saf-backup',
          'kind': 'saf',
          'valid': true,
          'workspaceUri': 'content://com.example.documents/tree/fixture',
          'relativePath': 'README.md',
          'sizeBytes': 7,
          'createdAtMs': 456,
        },
        <String, Object?>{
          'backupId': 'broken-backup',
          'kind': 'invalid',
          'valid': false,
          'reason': 'malformed metadata',
        },
      ];
    });

    final backups = await LocalAndroidBackend().listBackups();

    expect(backups, hasLength(3));
    expect(backups[0].isValid, isTrue);
    expect(backups[0].workspace!.filesystemOwnerId, 'android-host');
    expect(backups[0].relativePath, 'README.md');
    expect(backups[1].workspace!.filesystemOwnerId, 'android-saf');
    expect(backups[1].workspace!.hostPath, startsWith('content://'));
    expect(backups[2].isValid, isFalse);
    expect(backups[2].reason, 'malformed metadata');
  });

  testWidgets('renders valid and unavailable backup records safely', (
    tester,
  ) async {
    messenger.setMockStreamHandler(
      eventChannel,
      MockStreamHandler.inline(onListen: (_, events) => events.endOfStream()),
    );
    messenger.setMockMethodCallHandler(methodChannel, (call) async {
      expect(call.method, 'listBackups');
      return <Object?>[
        <String, Object?>{
          'backupId': 'host-backup',
          'kind': 'host',
          'valid': true,
          'workspacePath': '/storage/emulated/0/Codex/Workspaces/demo-project',
          'relativePath': 'README.md',
          'sizeBytes': 12,
          'createdAtMs': 123,
        },
        <String, Object?>{
          'backupId': 'broken-backup',
          'kind': 'invalid',
          'valid': false,
          'reason': 'malformed metadata',
        },
      ];
    });

    final backend = LocalAndroidBackend(subscribeToHostEvents: false);
    await tester.pumpWidget(
      MaterialApp(home: BackupHistoryPage(backend: backend)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Backup history'), findsOneWidget);
    expect(find.text('README.md'), findsOneWidget);
    expect(find.text('Unavailable backup broken-backup'), findsOneWidget);
    expect(find.text('Restore'), findsOneWidget);

    await tester.tap(find.text('Restore'));
    await tester.pumpAndSettle();
    expect(find.text('Restore backup?'), findsOneWidget);
    expect(
      find.textContaining('The current file must still be readable'),
      findsOneWidget,
    );
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(find.text('Restore backup?'), findsNothing);
  });
}
