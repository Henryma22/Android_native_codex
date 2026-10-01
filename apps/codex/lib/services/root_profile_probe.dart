import 'dart:async';

import 'package:flutter/services.dart';

/// Read-only KernelSU Root Profile evidence returned after a user tap.
/// Root availability is an identity result; the other fields are diagnostics.
class RootProfileProbeResult {
  const RootProfileProbeResult({
    required this.state,
    required this.uid,
    required this.gid,
    required this.context,
    required this.groups,
    required this.capEff,
    required this.capPrm,
    required this.capInh,
    required this.capBnd,
    required this.capAmb,
    required this.linuxNoNewPrivs,
    required this.selinux,
    required this.networkGroupPresent,
    required this.readProcGroupPresent,
    required this.requiredGroupsPresent,
    required this.systemDataReadable,
    required this.appDataRootReadable,
    required this.appInstallRootReadable,
    required this.globalReadSamplesPassed,
    required this.workspaceReadable,
    required this.workspaceWritable,
    required this.appFilesAccessible,
    required this.appNoBackupAccessible,
    this.blockAliasCount = 0,
    this.writableBlockAliasCount = 0,
    this.blockAliasEnumerationComplete = false,
    this.blockAliasesReadOnly = false,
    this.protectedWriteSamplesPassed = false,
    required this.bootBlockPresent,
    required this.bootBlockWritable,
    required this.protectedRootPresent,
    required this.protectedRootsWritable,
    required this.systemConfigPresent,
    required this.systemConfigReadable,
    required this.systemConfigWritable,
    required this.vendorConfigReadable,
    required this.vendorConfigWritable,
    required this.procStatusReadable,
    required this.selinuxStateReadable,
    required this.selinuxStateWritable,
    required this.reason,
  });

  factory RootProfileProbeResult.fromMap(Map<Object?, Object?> value) =>
      RootProfileProbeResult(
        state: value['state'] as String? ?? 'failed',
        uid: value['uid'] as String? ?? 'unknown',
        gid: value['gid'] as String? ?? 'unknown',
        context: value['context'] as String? ?? 'unknown',
        groups: value['groups'] as String? ?? 'unknown',
        capEff: value['capEff'] as String? ?? 'unknown',
        capPrm: value['capPrm'] as String? ?? 'unknown',
        capInh: value['capInh'] as String? ?? 'unknown',
        capBnd: value['capBnd'] as String? ?? 'unknown',
        capAmb: value['capAmb'] as String? ?? 'unknown',
        linuxNoNewPrivs: value['linuxNoNewPrivs'] as String? ?? 'unknown',
        selinux: value['selinux'] as String? ?? 'unknown',
        networkGroupPresent: value['networkGroupPresent'] == true,
        readProcGroupPresent: value['readProcGroupPresent'] == true,
        requiredGroupsPresent: value['requiredGroupsPresent'] == true,
        systemDataReadable: value['systemDataReadable'] == true,
        appDataRootReadable: value['appDataRootReadable'] == true,
        appInstallRootReadable: value['appInstallRootReadable'] == true,
        globalReadSamplesPassed: value['globalReadSamplesPassed'] == true,
        workspaceReadable: value['workspaceReadable'] == true,
        workspaceWritable: value['workspaceWritable'] == true,
        appFilesAccessible: value['appFilesAccessible'] == true,
        appNoBackupAccessible: value['appNoBackupAccessible'] == true,
        blockAliasCount: value['blockAliasCount'] as int? ?? 0,
        writableBlockAliasCount: value['writableBlockAliasCount'] as int? ?? 0,
        blockAliasEnumerationComplete:
            value['blockAliasEnumerationComplete'] == true,
        blockAliasesReadOnly: value['blockAliasesReadOnly'] == true,
        protectedWriteSamplesPassed:
            value['protectedWriteSamplesPassed'] == true,
        bootBlockPresent: value['bootBlockPresent'] == true,
        bootBlockWritable: value['bootBlockWritable'] == true,
        protectedRootPresent: value['protectedRootPresent'] == true,
        protectedRootsWritable: value['protectedRootsWritable'] == true,
        systemConfigPresent: value['systemConfigPresent'] == true,
        systemConfigReadable: value['systemConfigReadable'] == true,
        systemConfigWritable: value['systemConfigWritable'] == true,
        vendorConfigReadable: value['vendorConfigReadable'] == true,
        vendorConfigWritable: value['vendorConfigWritable'] == true,
        procStatusReadable: value['procStatusReadable'] == true,
        selinuxStateReadable: value['selinuxStateReadable'] == true,
        selinuxStateWritable: value['selinuxStateWritable'] == true,
        reason: value['reason'] as String? ?? '',
      );

  final String state;
  final String uid;
  final String gid;
  final String context;
  final String groups;
  final String capEff;
  final String capPrm;
  final String capInh;
  final String capBnd;
  final String capAmb;
  final String linuxNoNewPrivs;
  final String selinux;
  final bool networkGroupPresent;
  final bool readProcGroupPresent;
  final bool requiredGroupsPresent;
  final bool systemDataReadable;
  final bool appDataRootReadable;
  final bool appInstallRootReadable;
  final bool globalReadSamplesPassed;
  final bool workspaceReadable;
  final bool workspaceWritable;
  final bool appFilesAccessible;
  final bool appNoBackupAccessible;
  final int blockAliasCount;
  final int writableBlockAliasCount;
  final bool blockAliasEnumerationComplete;
  final bool blockAliasesReadOnly;
  final bool protectedWriteSamplesPassed;
  final bool bootBlockPresent;
  final bool bootBlockWritable;
  final bool protectedRootPresent;
  final bool protectedRootsWritable;
  final bool systemConfigPresent;
  final bool systemConfigReadable;
  final bool systemConfigWritable;
  final bool vendorConfigReadable;
  final bool vendorConfigWritable;
  final bool procStatusReadable;
  final bool selinuxStateReadable;
  final bool selinuxStateWritable;
  final String reason;

  bool get rootIdentityPassed => state == 'root' || state == 'smoke_passed';

  /// Kept as a source-compatible alias for older settings widgets.
  bool get smokePassed => rootIdentityPassed;
}

class RootProfileProbe {
  const RootProfileProbe();

  static const _channel = MethodChannel('io.henry.codex/native_probe');

  Future<RootProfileProbeResult> run() async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('probeRootProfile')
          .timeout(const Duration(seconds: 7));
      if (raw is Map<Object?, Object?>) {
        return RootProfileProbeResult.fromMap(raw);
      }
      return const RootProfileProbeResult(
        state: 'failed',
        uid: 'unknown',
        gid: 'unknown',
        context: 'unknown',
        groups: 'unknown',
        capEff: 'unknown',
        capPrm: 'unknown',
        capInh: 'unknown',
        capBnd: 'unknown',
        capAmb: 'unknown',
        linuxNoNewPrivs: 'unknown',
        selinux: 'unknown',
        networkGroupPresent: false,
        readProcGroupPresent: false,
        requiredGroupsPresent: false,
        systemDataReadable: false,
        appDataRootReadable: false,
        appInstallRootReadable: false,
        globalReadSamplesPassed: false,
        workspaceReadable: false,
        workspaceWritable: false,
        appFilesAccessible: false,
        appNoBackupAccessible: false,
        bootBlockPresent: false,
        bootBlockWritable: false,
        protectedRootPresent: false,
        protectedRootsWritable: false,
        systemConfigPresent: false,
        systemConfigReadable: false,
        systemConfigWritable: false,
        vendorConfigReadable: false,
        vendorConfigWritable: false,
        procStatusReadable: false,
        selinuxStateReadable: false,
        selinuxStateWritable: false,
        reason: 'Native Root Profile probe returned an invalid result.',
      );
    } on PlatformException catch (error) {
      return RootProfileProbeResult(
        state: 'failed',
        uid: 'unknown',
        gid: 'unknown',
        context: 'unknown',
        groups: 'unknown',
        capEff: 'unknown',
        capPrm: 'unknown',
        capInh: 'unknown',
        capBnd: 'unknown',
        capAmb: 'unknown',
        linuxNoNewPrivs: 'unknown',
        selinux: 'unknown',
        networkGroupPresent: false,
        readProcGroupPresent: false,
        requiredGroupsPresent: false,
        systemDataReadable: false,
        appDataRootReadable: false,
        appInstallRootReadable: false,
        globalReadSamplesPassed: false,
        workspaceReadable: false,
        workspaceWritable: false,
        appFilesAccessible: false,
        appNoBackupAccessible: false,
        bootBlockPresent: false,
        bootBlockWritable: false,
        protectedRootPresent: false,
        protectedRootsWritable: false,
        systemConfigPresent: false,
        systemConfigReadable: false,
        systemConfigWritable: false,
        vendorConfigReadable: false,
        vendorConfigWritable: false,
        procStatusReadable: false,
        selinuxStateReadable: false,
        selinuxStateWritable: false,
        reason: error.message ?? error.code,
      );
    } on TimeoutException {
      return const RootProfileProbeResult(
        state: 'failed',
        uid: 'unknown',
        gid: 'unknown',
        context: 'unknown',
        groups: 'unknown',
        capEff: 'unknown',
        capPrm: 'unknown',
        capInh: 'unknown',
        capBnd: 'unknown',
        capAmb: 'unknown',
        linuxNoNewPrivs: 'unknown',
        selinux: 'unknown',
        networkGroupPresent: false,
        readProcGroupPresent: false,
        requiredGroupsPresent: false,
        systemDataReadable: false,
        appDataRootReadable: false,
        appInstallRootReadable: false,
        globalReadSamplesPassed: false,
        workspaceReadable: false,
        workspaceWritable: false,
        appFilesAccessible: false,
        appNoBackupAccessible: false,
        bootBlockPresent: false,
        bootBlockWritable: false,
        protectedRootPresent: false,
        protectedRootsWritable: false,
        systemConfigPresent: false,
        systemConfigReadable: false,
        systemConfigWritable: false,
        vendorConfigReadable: false,
        vendorConfigWritable: false,
        procStatusReadable: false,
        selinuxStateReadable: false,
        selinuxStateWritable: false,
        reason: 'Root Profile probe timed out.',
      );
    }
  }
}
