import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/root_access_policy.dart';

void main() {
  test('root reads are not restricted by an app path allowlist', () {
    expect(
      RootAccessPolicy.readAllowed('/data/user/0/other/files/a.txt'),
      isTrue,
    );
    expect(RootAccessPolicy.readAllowed('/system/etc/hosts'), isTrue);
  });

  test('workspace and runtime writes are direct low-risk writes', () {
    expect(
      RootAccessPolicy.assessWrite(
        '/storage/emulated/0/Codex/Workspaces/demo/a.txt',
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/data/local/tmp/io.henry.codex/a').risk,
      RootWriteRisk.low,
    );
  });

  test('ordinary Android data and system-file writes stay direct', () {
    expect(
      RootAccessPolicy.assessWrite('/data/user/0/example/files/a').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/data/data/example/shared_prefs/app.xml')
          .route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/data/misc/example/config.json').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/android/data/user/0/example/files/a')
          .route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/android').route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessWrite('/android/etc/hosts').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/system/fonts/Roboto-Regular.ttf').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/android/vendor/etc/config.json').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/android/vendor/etc/init/hw/init.rc').route,
      RootWriteRoute.kernelSuPlugin,
    );
    // Bare `/etc` belongs to the PRoot guest; host Android root paths are
    // explicitly mapped under `/android`.
    expect(
      RootAccessPolicy.assessWrite('/etc/hosts').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('<unknown>').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('relative/config.json').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessPaths(const <String>[]).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/data/adb/ksu/modules/example/module.prop')
          .route,
      RootWriteRoute.kernelSuPlugin,
    );
    expect(
      RootAccessPolicy.assessWrite('/data/adb/modules/example/module.prop')
          .route,
      RootWriteRoute.kernelSuPlugin,
    );
    for (final path in <String>[
      '/data/adb/ksu/allowlist',
      '/data/adb/ksu/profiles/io.henry.codex',
      '/data/adb/ksu/config/state.json',
    ]) {
      final assessment = RootAccessPolicy.assessWrite(path);
      expect(assessment.route, RootWriteRoute.userApproval, reason: path);
      expect(assessment.risk, RootWriteRisk.high, reason: path);
    }
  });

  test('raw block writes use explicit authorization and boot images prefer plugins', () {
    expect(
      RootAccessPolicy.assessWrite('/dev/block/by-name/boot').route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessWrite('/vendor_boot/boot.img').route,
      RootWriteRoute.kernelSuPlugin,
    );
    for (final path in <String>[
      '/dev/mtd0',
      '/dev/ubi0',
      '/dev/mapper/system',
      '/android/dev/block/by-name/boot',
    ]) {
      expect(
        RootAccessPolicy.assessWrite(path).route,
        RootWriteRoute.userApproval,
        reason: path,
      );
    }
  });

  test('dot segments cannot turn boot-critical writes into direct writes', () {
    expect(
      RootAccessPolicy.assessWrite('/workspace/../system/etc/hosts').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessWrite('/workspace/../../dev/block/by-name/boot')
          .route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessWrite(
        '/data/local/tmp/io.henry.codex/../../../adb/ksu/modules/example/module.prop',
      ).route,
      RootWriteRoute.kernelSuPlugin,
    );

    final escapedPermission = RootAccessPolicy.assessPermissionRequest(
      <String, Object?>{
        'fileSystem': <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'path': <String, Object?>{
                'type': 'path',
                'path': './../../../../../../../system/etc/hosts',
              },
              'access': 'write',
            },
          ],
        },
      },
      workspacePath: '/storage/emulated/0/Codex/Workspaces/demo',
    );
    expect(escapedPermission.route, RootWriteRoute.direct);
  });

  test('ordinary absolute paths are direct regardless of workspace casing', () {
    expect(
      RootAccessPolicy.assessWrite(
        '/STORAGE/EMULATED/0/CODEX/WORKSPACES/demo/file.txt',
      ).route,
      RootWriteRoute.direct,
    );
  });

  test('permission profile writes use the same root path policy', () {
    final workspaceWrite = RootAccessPolicy.assessPermissionRequest(
      <String, Object?>{
        'fileSystem': <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'path': <String, Object?>{
                'type': 'path',
                'path': '/storage/emulated/0/Codex/Workspaces/demo/a.txt',
              },
              'access': 'write',
            },
          ],
        },
      },
    );
    expect(workspaceWrite.route, RootWriteRoute.direct);

    final systemWrite = RootAccessPolicy.assessPermissionRequest(
      <String, Object?>{
        'fileSystem': <String, Object?>{
          'write': <String>['file:///vendor/etc/build.prop'],
        },
      },
    );
    expect(systemWrite.route, RootWriteRoute.direct);

    final initWrite = RootAccessPolicy.assessPermissionRequest(
      <String, Object?>{
        'fileSystem': <String, Object?>{
          'write': <String>['file:///vendor/etc/init/hw/init.rc'],
        },
      },
    );
    expect(initWrite.route, RootWriteRoute.kernelSuPlugin);

    final bootWrite = RootAccessPolicy.assessPermissionRequest(
      <String, Object?>{
        'fileSystem': <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'path': <String, Object?>{
                'type': 'special',
                'value': <String, Object?>{'kind': 'root'},
              },
              'access': 'write',
            },
          ],
        },
      },
    );
    expect(bootWrite.route, RootWriteRoute.userApproval);
  });

  test('ordinary system scopes stay direct while boot targets are routed', () {
    expect(
      RootAccessPolicy.assessPermissionRequest(<String, Object?>{
        'fileSystem': <String, Object?>{
          'entries': <Object?>[
            <String, Object?>{
              'path': <String, Object?>{
                'type': 'globPattern',
                'pattern': '/system/**',
              },
              'access': 'write',
            },
          ],
        },
      }).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessPermissionRequest(<String, Object?>{
        'fileSystem': <String, Object?>{
          'write': <String>['/system/etc/fstab.device'],
        },
      }).route,
      RootWriteRoute.kernelSuPlugin,
    );
    final unknown = RootAccessPolicy.assessPermissionRequest(
      <String, Object?>{},
    );
    expect(unknown.route, RootWriteRoute.direct);
    expect(unknown.risk, RootWriteRisk.medium);
  });

  test('command preflight leaves unknown Root commands direct but routes known critical targets', () {
    expect(
      RootAccessPolicy.assessCommand('/system/bin/id').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('cat /system/build.prop').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('grep -R product /system/etc').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('npm install debug@4.4.0').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('mount -o remount,rw /system').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('setprop debug.layout true').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('reboot').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('dd if=image of=/tmp/image-copy').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('fastboot flash boot boot.img').route,
      RootWriteRoute.kernelSuPlugin,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('relative.txt', 'w').write('x')\"",
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('custom-tool --ordinary-task').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('sed -i s/a/b/ /vendor/etc/config').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand("rg --pre='python -c' foo /system/etc")
          .route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('cat /system/build.prop > /tmp/copy')
          .route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand(
        'touch /storage/emulated/0/Codex/Workspaces/demo/new.txt',
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('/data/user/0/example/files/config.json', 'w').write('x')\"",
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand("python -c \"open('/', 'w').write('x')\"")
          .route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand('rm -rf /data/misc/example/cache').route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('rm -rf /').route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand(
        '/system/bin/dd if=x of=/dev/block/by-name/boot',
      ).route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand('/system/bin/dd if=x of=/dev/mtd0').route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand('/system/bin/ls /data/user/0/example')
          .route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('/android/data/user/0/example/files/config.json', 'w').write('x')\"",
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('/android/etc/hosts', 'w').write('x')\"",
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand('rm -rf /android').route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand('sed -i s/a/b/ /android/init.rc').route,
      RootWriteRoute.kernelSuPlugin,
    );
    expect(
      RootAccessPolicy.assessCommand(
        '/system/bin/dd if=x of=/android/dev/block/by-name/boot',
      ).route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "/system/bin/sh -c 'dd if=/data/local/tmp/payload of=/dev/block/by-name/boot'",
      ).route,
      RootWriteRoute.userApproval,
    );
    expect(
      RootAccessPolicy.assessCommand(
        '/system/bin/su -c "insmod /vendor/lib/modules/example.ko"',
      ).route,
      RootWriteRoute.kernelSuPlugin,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('/system/etc/build.prop', 'w').write('x')\"",
      ).route,
      RootWriteRoute.direct,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "sed -i s/a/b/ /android/system/etc/init/hw/init.rc",
      ).route,
      RootWriteRoute.kernelSuPlugin,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('/system/etc/fstab.device', 'w').write('x')\"",
      ).route,
      RootWriteRoute.kernelSuPlugin,
    );
    expect(
      RootAccessPolicy.assessCommand(
        "python -c \"open('/dev/block/by-name/boot', 'wb').write(b'x')\"",
      ).route,
      RootWriteRoute.userApproval,
    );
  });

  test(
    'command preflight surfaces explicit KernelSU control-state targets',
    () {
      final assessment = RootAccessPolicy.assessCommand(
        'python -c "open(\'/data/adb/ksu/allowlist\', \'w\').write(\'x\')"',
      );

      expect(assessment.route, RootWriteRoute.userApproval);
      expect(assessment.risk, RootWriteRisk.high);

      final read = RootAccessPolicy.assessCommand(
        'python -c "print(open(\'/data/adb/ksu/allowlist\').read())"',
      );
      expect(read.route, RootWriteRoute.direct);
      expect(read.route, isNot(RootWriteRoute.denied));

      for (final mode in <String>['wb', 'ab', 'x', 'a+', 'rb+', 'r+b']) {
        final write = RootAccessPolicy.assessCommand(
          "python -c \"open('/data/adb/ksu/allowlist', '$mode')\"",
        );
        expect(
          write.route,
          RootWriteRoute.userApproval,
          reason: 'write-capable Python open mode $mode',
        );
      }
      for (final operation in <String>[
        "os.chmod('/data/adb/ksu/allowlist', 0o600)",
        "shutil.copyfile('/tmp/source', '/data/adb/ksu/allowlist')",
        "os.open('/data/adb/ksu/allowlist', os.O_CREAT | os.O_RDONLY)",
      ]) {
        final write = RootAccessPolicy.assessCommand('python -c "$operation"');
        expect(
          write.route,
          RootWriteRoute.userApproval,
          reason: 'write-capable Python filesystem operation $operation',
        );
      }
    },
  );

  test('read-only Root sessions allow only recognized read-only commands', () {
    final read = RootAccessPolicy.assessCommand('cat /system/etc/hosts');
    expect(read.readOnlyOperation, isTrue);
    expect(
      RootAccessPolicy.enforceReadOnlySession(read).route,
      RootWriteRoute.direct,
    );

    for (final command in <String>[
      'touch /storage/emulated/0/Codex/Workspaces/demo/new.txt',
      'npm install debug@4.4.0',
      "python -c \"open('/data/user/0/example/file', 'w').write('x')\"",
      "sh -c 'cat /system/etc/hosts > /data/local/tmp/copy'",
    ]) {
      final assessment = RootAccessPolicy.enforceReadOnlySession(
        RootAccessPolicy.assessCommand(command),
      );
      expect(assessment.route, RootWriteRoute.denied, reason: command);
    }

    final fileChange = RootAccessPolicy.enforceReadOnlySession(
      RootAccessPolicy.assessPaths(const <String>['/workspace/notes.txt']),
    );
    expect(fileChange.route, RootWriteRoute.denied);
  });
}
