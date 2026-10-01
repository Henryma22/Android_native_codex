import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:codex/kernelsu_plugin_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('io.henry.codex/kernelsu_plugin');
  const nativeProbeChannel = MethodChannel('io.henry.codex/native_probe');
  final calls = <MethodCall>[];
  final nativeProbeCalls = <MethodCall>[];
  var stagedRisk = 'R3';
  var restoreStaged = false;
  var rootProbeContextUnavailable = false;
  var rootProbeProfileIncompatible = false;

  setUp(() {
    calls.clear();
    nativeProbeCalls.clear();
    stagedRisk = 'R3';
    restoreStaged = false;
    rootProbeContextUnavailable = false;
    rootProbeProfileIncompatible = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          switch (call.method) {
            case 'probe':
              return <String, Object?>{'available': true, 'state': 'available'};
            case 'pickArchive':
              return <String, Object?>{
                'bytes': Uint8List.fromList(<int>[0x50, 0x4b]),
                'sha256': List<String>.filled(64, 'a').join(),
                'displayName': 'test.zip',
              };
            case 'stage':
              return <String, Object?>{
                'requestId': 'request-1',
                'moduleId': 'ccpocket.plugin.test',
                'sha256': List<String>.filled(64, 'a').join(),
                'effectiveRisk': stagedRisk,
                'archiveSizeBytes': 2,
                'uncompressedSizeBytes': 2,
                'entryCount': 2,
                'containsScripts': true,
                'requiresReboot': true,
                'reviewManifest': <String, Object?>{
                  'name': 'Reviewed module',
                  'version': '1.2',
                  'riskHint': 'R1',
                  'reversible': true,
                  'capabilities': <String>['filesystem'],
                  'overlayRoots': stagedRisk == 'R4'
                      ? <String>['/dev/block/by-name/boot_a']
                      : <String>['/system/etc'],
                  'actions': <String>['refresh'],
                  'backupTargets': <String>['/system/etc/example.conf'],
                  'healthChecks': <String>['service check'],
                },
                'moduleProp': <String, Object?>{
                  'author': 'Test author',
                  'description': 'Test description',
                },
                'archiveEntries': stagedRisk == 'R4'
                    ? <String>['module.prop', 'assets/boot.img']
                    : <String>['module.prop', 'sepolicy.rule', 'service.sh'],
                'archiveEntriesTruncated': false,
                'reviewFiles': <Map<String, Object?>>[
                  <String, Object?>{
                    'path': 'sepolicy.rule',
                    'sizeBytes': 21,
                    'content': 'allow app_data_file',
                    'truncated': false,
                  },
                  <String, Object?>{
                    'path': 'service.sh',
                    'sizeBytes': 13,
                    'content': '#!/system/bin/sh',
                    'truncated': false,
                  },
                ],
              };
            case 'restoreStage':
              if (!restoreStaged) return null;
              return <String, Object?>{
                'requestId': 'restored',
                'moduleId': 'ccpocket.plugin.test',
                'sha256': List<String>.filled(64, 'a').join(),
                'effectiveRisk': stagedRisk,
                'archiveSizeBytes': 2,
                'uncompressedSizeBytes': 2,
                'entryCount': 2,
                'containsScripts': true,
                'requiresReboot': true,
                'reviewManifest': <String, Object?>{
                  'name': 'Restored module',
                  'version': '1.2',
                  'riskHint': 'R1',
                  'reversible': true,
                  'capabilities': <String>['filesystem'],
                  'overlayRoots': <String>['/system/etc'],
                  'actions': <String>[],
                  'backupTargets': <String>[],
                  'healthChecks': <String>[],
                },
                'moduleProp': <String, Object?>{
                  'author': 'Test author',
                  'description': 'Restored description',
                },
              };
            case 'install':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.test',
                'effectiveRisk': stagedRisk,
                'operations': <String>['install', 'disable'],
              };
            case 'enable':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.test',
                'effectiveRisk': stagedRisk,
                'operations': <String>['enable'],
              };
            case 'disable':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.test',
                'effectiveRisk': stagedRisk,
                'operations': <String>['disable'],
              };
            case 'uninstall':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.test',
                'effectiveRisk': stagedRisk,
                'operations': <String>['uninstall'],
              };
            case 'rollback':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.test',
                'effectiveRisk': stagedRisk,
                'operations': <String>['install', 'disable'],
              };
            case 'runAction':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.test',
                'effectiveRisk': stagedRisk,
                'operations': <String>['action'],
              };
            case 'list':
              return <String, Object?>{
                'moduleId': 'ccpocket.plugin.capability_probe',
                'effectiveRisk': 'R0',
                'operations': <String>['list'],
                'modules': <Map<String, Object?>>[
                  <String, Object?>{
                    'id': 'ccpocket.plugin.test',
                    'name': 'Reviewed module',
                    'version': '1.2',
                    'author': 'Test author',
                    'enabled': true,
                  },
                ],
              };
            default:
              fail('Unexpected KernelSU plugin method: ${call.method}');
          }
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeProbeChannel, (call) async {
          nativeProbeCalls.add(call);
          expect(call.method, 'probeRootProfile');
          return <String, Object?>{
            'state': rootProbeContextUnavailable
                ? 'context_unavailable'
                : rootProbeProfileIncompatible
                ? 'profile_incompatible'
                : 'smoke_passed',
            'uid': '0',
            'gid': '0',
            'context': 'u:r:codex_agent:s0',
            'groups': '0 3003 3009 1007',
            'capEff': '000001ffffffffff',
            'capPrm': '000001ffffffffff',
            'capInh': '0000000000000002',
            'capBnd': '000001ffffffffff',
            'capAmb': '0000000000000002',
            'linuxNoNewPrivs': '0',
            'selinux': 'Enforcing',
            'systemDataReadable': true,
            'appDataRootReadable': true,
            'appInstallRootReadable': true,
            'globalReadSamplesPassed': true,
            'networkGroupPresent': true,
            'readProcGroupPresent': true,
            'requiredGroupsPresent': true,
            'workspaceReadable': true,
            'workspaceWritable': true,
            'appFilesAccessible': true,
            'appNoBackupAccessible': true,
            'blockAliasCount': 174,
            'writableBlockAliasCount': 0,
            'blockAliasEnumerationComplete': true,
            'blockAliasesReadOnly': true,
            'protectedWriteSamplesPassed': true,
            'bootBlockPresent': true,
            'bootBlockWritable': false,
            'protectedRootPresent': true,
            'protectedRootsWritable': false,
            'systemConfigPresent': true,
            'systemConfigReadable': true,
            'systemConfigWritable': false,
            'vendorConfigReadable': true,
            'vendorConfigWritable': false,
            'procStatusReadable': true,
            'selinuxStateReadable': true,
            'selinuxStateWritable': false,
            'reason': rootProbeContextUnavailable
                ? 'Error: setcontext u:r:codex_agent:s0 (os error 22)'
                : rootProbeProfileIncompatible
                ? 'root_worker_security_error=missing_cap_setpcap'
                : 'Sample checks passed; not full validation.',
          };
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(nativeProbeChannel, null);
  });

  testWidgets(
    'R3 install stays disabled and enable uses the native prompt path',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KernelSuPluginSettingsSection(zh: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), ['restoreStage']);
      final refreshButton = find.byTooltip('刷新');
      await tester.tap(refreshButton);
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), ['restoreStage', 'probe']);

      final importButton = find.text('导入并检查插件归档');
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('SHA-256'), findsOneWidget);
      expect(find.textContaining('需要重启'), findsOneWidget);

      final reviewTile = find.byKey(const ValueKey('kernelsu_plugin_review'));
      await tester.ensureVisible(reviewTile);
      await tester.tap(reviewTile);
      await tester.pumpAndSettle();
      expect(find.text('Test description'), findsOneWidget);
      expect(find.textContaining('sepolicy.rule'), findsWidgets);
      final policyFile = find.text('sepolicy.rule');
      await tester.ensureVisible(policyFile);
      await tester.tap(policyFile);
      await tester.pumpAndSettle();
      expect(find.textContaining('allow app_data_file'), findsOneWidget);
      expect(find.textContaining('service.sh'), findsWidgets);

      final installButton = find.text('审批安装为禁用状态');
      await tester.ensureVisible(installButton);
      await tester.tap(installButton);
      await tester.pumpAndSettle();

      final enableButton = find.text('通过设备凭据启用');
      expect(enableButton, findsOneWidget);
      await tester.ensureVisible(enableButton);
      await tester.tap(enableButton);
      await tester.pumpAndSettle();

      expect(
        calls.map((call) => call.method),
        containsAllInOrder(<String>[
          'probe',
          'pickArchive',
          'stage',
          'install',
          'enable',
        ]),
      );
      final enableCall = calls.lastWhere((call) => call.method == 'enable');
      expect(enableCall.arguments['confirmation'], 'none');
      expect(find.textContaining('重启后生效'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kernelsu_plugin_disable')));
      await tester.pumpAndSettle();
      expect(find.text('已禁用：ccpocket.plugin.test'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('kernelsu_plugin_rollback')));
      await tester.pumpAndSettle();
      expect(find.textContaining('已回滚 ccpocket.plugin.test'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('kernelsu_plugin_action_refresh')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('kernelsu_action_confirm_refresh')),
      );
      await tester.pumpAndSettle();
      expect(
        find.textContaining('已运行插件操作：ccpocket.plugin.test / refresh'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const ValueKey('kernelsu_plugin_uninstall')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('kernelsu_uninstall_confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('已卸载'), findsOneWidget);
      expect(
        calls.map((call) => call.method),
        containsAllInOrder(<String>[
          'enable',
          'disable',
          'rollback',
          'runAction',
          'uninstall',
        ]),
      );
    },
  );

  testWidgets(
    'R4 boot-sensitive plugin can be installed disabled and explicitly enabled',
    (tester) async {
      stagedRisk = 'R4';
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KernelSuPluginSettingsSection(zh: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final importButton = find.text('导入并检查插件归档');
      await tester.ensureVisible(importButton);
      await tester.tap(importButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('有效风险 R4'), findsOneWidget);

      final installButton = find.text('审阅启动链影响并安装为禁用状态');
      await tester.ensureVisible(installButton);
      await tester.tap(installButton);
      await tester.pumpAndSettle();
      expect(find.textContaining('安装不会自动启用'), findsOneWidget);
      expect(find.textContaining('assets/boot.img'), findsOneWidget);
      expect(calls.map((call) => call.method), isNot(contains('install')));

      final confirmInstall = find.byKey(
        const ValueKey('kernelsu_r4_install_confirm'),
      );
      await tester.tap(confirmInstall);
      await tester.pumpAndSettle();
      final installCall = calls.lastWhere((call) => call.method == 'install');
      expect(installCall.arguments['confirmation'], 'user');
      expect(find.text('审阅影响并确认启用'), findsOneWidget);

      final enableReview = find.text('审阅影响并确认启用');
      await tester.ensureVisible(enableReview);
      await tester.tap(enableReview);
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), isNot(contains('enable')));
      expect(find.textContaining('当前 slot'), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey('kernelsu_r4_enable_confirm')),
      );
      await tester.pumpAndSettle();
      final enableCall = calls.lastWhere((call) => call.method == 'enable');
      expect(enableCall.arguments['confirmation'], 'user');
      expect(find.textContaining('已在明确确认后启用'), findsOneWidget);
    },
  );

  testWidgets(
    'Root Profile inspection is explicit and displays identity and policy evidence',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KernelSuPluginSettingsSection(zh: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(calls.map((call) => call.method), ['restoreStage']);
      expect(nativeProbeCalls, isEmpty);

      final probeButton = find.text('检查 KernelSU Root Profile');
      await tester.ensureVisible(probeButton);
      await tester.tap(probeButton);
      await tester.pumpAndSettle();

      expect(nativeProbeCalls.map((call) => call.method), ['probeRootProfile']);
      expect(find.textContaining('样本检查通过'), findsOneWidget);
      expect(find.textContaining('u:r:codex_agent:s0'), findsOneWidget);
      expect(find.textContaining('UID/GID 0/0'), findsOneWidget);
      expect(find.textContaining('Android 组 0 3003 3009 1007'), findsOneWidget);
      expect(find.textContaining('CapPrm 000001ffffffffff'), findsOneWidget);
      expect(find.textContaining('CapInh 0000000000000002'), findsOneWidget);
      expect(find.textContaining('CapBnd 000001ffffffffff'), findsOneWidget);
      expect(find.textContaining('CapAmb 0000000000000002'), findsOneWidget);
      expect(find.textContaining('必需组 root/inet/readproc 是'), findsOneWidget);
      expect(find.textContaining('进程读取组(3009) 是'), findsOneWidget);
      expect(find.textContaining('Linux NoNewPrivs 0 (仅记录)'), findsOneWidget);
      expect(find.textContaining('全局读取样本 是'), findsOneWidget);
      expect(
        find.textContaining('块设备别名枚举完成/只读/总数/可写 是/是/174/0'),
        findsOneWidget,
      );
      expect(find.textContaining('高危写入样本 是'), findsOneWidget);
      expect(find.textContaining('Boot 节点存在/可写 是/否'), findsOneWidget);
      expect(find.textContaining('应用运行目录可读写 是/是'), findsOneWidget);
      expect(find.textContaining('应用数据/安装目录可读 是/是'), findsOneWidget);
      expect(find.textContaining('Vendor 配置可读/可写 是/否'), findsOneWidget);
      expect(find.textContaining('不代表所有系统路径均安全'), findsOneWidget);
    },
  );

  testWidgets(
    'rejected normal KernelSU invocation explains the profile issue',
    (tester) async {
      rootProbeContextUnavailable = true;
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: KernelSuPluginSettingsSection(zh: true),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final probeButton = find.text('检查 KernelSU Root Profile');
      await tester.ensureVisible(probeButton);
      await tester.tap(probeButton);
      await tester.pumpAndSettle();

      expect(find.textContaining('KernelSU Root 调用被拒绝'), findsOneWidget);
      expect(find.textContaining('KernelSU 拒绝了正常 Root 调用'), findsOneWidget);
      expect(find.textContaining('自定义 SELinux 域'), findsOneWidget);
      expect(find.textContaining('固定 -Z 参数'), findsNothing);
      expect(find.textContaining('setcontext'), findsNothing);
    },
  );

  testWidgets('incompatible root identity explains the launch requirement', (
    tester,
  ) async {
    rootProbeProfileIncompatible = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KernelSuPluginSettingsSection(zh: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final probeButton = find.text('检查 KernelSU Root Profile');
    await tester.ensureVisible(probeButton);
    await tester.tap(probeButton);
    await tester.pumpAndSettle();

    expect(find.textContaining('KernelSU 权限配置不兼容'), findsOneWidget);
    expect(find.textContaining('UID/GID 0/0'), findsOneWidget);
    expect(
      find.textContaining('required groups root/inet/readproc'),
      findsNothing,
    );
    expect(find.textContaining('root_worker_security_error'), findsNothing);
  });

  testWidgets('installed module refresh displays native module state', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KernelSuPluginSettingsSection(zh: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('刷新已安装模块'));
    await tester.pumpAndSettle();

    expect(calls.map((call) => call.method), contains('list'));
    final installedModules = find.byKey(
      const ValueKey('kernelsu_installed_modules'),
    );
    expect(installedModules, findsOneWidget);
    await tester.tap(installedModules);
    await tester.pumpAndSettle();
    expect(find.text('Reviewed module'), findsOneWidget);
    expect(find.text('已启用'), findsOneWidget);
  });

  testWidgets('restores the last verified archive without invoking Root', (
    tester,
  ) async {
    restoreStaged = true;
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: KernelSuPluginSettingsSection(zh: true),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 20));

    await tester.tap(find.byKey(const ValueKey('kernelsu_plugin_review')));
    await tester.pumpAndSettle();
    expect(find.text('Restored description'), findsOneWidget);
    expect(find.textContaining('已恢复上次校验的插件归档'), findsOneWidget);
    expect(calls.map((call) => call.method), ['restoreStage']);
  });
}
