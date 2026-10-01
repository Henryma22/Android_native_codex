enum RootWriteRisk { low, medium, high, blocked }

/// The preferred handling path, not a blanket authorization decision.
/// `kernelSuPlugin` means that a reversible KernelSU module is preferred for a
/// high-risk change; it must not be treated as an unconditional denial when a
/// user has explicitly authorized the concrete operation.
enum RootWriteRoute { direct, userApproval, kernelSuPlugin, denied }

class RootWriteAssessment {
  const RootWriteAssessment({
    required this.risk,
    required this.route,
    required this.reason,
    this.readOnlyOperation = false,
  });

  final RootWriteRisk risk;
  final RootWriteRoute route;
  final String reason;

  /// True only when the request is an explicitly recognized read-only command.
  /// Path approvals and unknown operations default to false.
  final bool readOnlyOperation;

  bool get allowed => route != RootWriteRoute.denied;
}

/// Shared, transport-neutral policy for root sessions.
///
/// Read access intentionally has no application path allowlist. Android's
/// kernel/SELinux and the selected `su` helper remain authoritative, but the
/// Codex architecture does not silently hide readable files. Write access is
/// classified before a root operation is presented to the user. High-risk
/// paths use soft routing and visible authorization; they are not permanently
/// rejected by this app-side classifier.
class RootAccessPolicy {
  const RootAccessPolicy._();

  static bool readAllowed(String path) => path.trim().isNotEmpty;

  /// Keeps safe diagnostic reads available while denying every other Root
  /// approval when the session's permission level is read-only.
  static RootWriteAssessment enforceReadOnlySession(
    RootWriteAssessment assessment,
  ) {
    if (assessment.readOnlyOperation) return assessment;
    return const RootWriteAssessment(
      risk: RootWriteRisk.blocked,
      route: RootWriteRoute.denied,
      reason:
          'This Root session is read-only; Codex write requests are denied.',
    );
  }

  static RootWriteAssessment assessWrite(String path) {
    final normalized = _normalizeAndroidHostPath(path);
    if (normalized.isEmpty) {
      return _unknownWriteAssessment;
    }
    if (normalized == '/') {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.userApproval,
        reason: 'The target is the whole filesystem; verify the exact operation and authorize it explicitly.',
      );
    }
    if (_isKernelSuModulePath(normalized)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.kernelSuPlugin,
        reason: 'Prefer a reviewed KernelSU module archive for this deployment; an explicitly authorized direct operation remains available when required.',
      );
    }
    if (_isKernelSuControlPath(normalized)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.userApproval,
        reason: 'KernelSU profile/control state is user-managed; review the exact target and authorize the operation explicitly.',
      );
    }
    if (_isRawBlockPath(normalized)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.userApproval,
        reason: 'Raw block or boot targets require target/slot verification and explicit user authorization; direct execution remains available after that review.',
      );
    }
    if (_isBootImagePath(normalized)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.kernelSuPlugin,
        reason: 'Prefer a verified reversible KernelSU module for this boot image, but allow an explicitly authorized direct operation after target and recovery checks.',
      );
    }
    if (_isBootCriticalSystemPath(normalized)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.kernelSuPlugin,
        reason: 'This path participates in Android startup; verify the target and recovery path, prefer a reversible KernelSU module when appropriate, and keep direct execution available after explicit authorization.',
      );
    }
    if (_isAppWorkspacePath(normalized) || _isTemporaryPath(normalized)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.low,
        route: RootWriteRoute.direct,
        reason:
            'App workspace or temporary runtime data may be written directly.',
      );
    }
    if (!normalized.startsWith('/')) {
      return _unknownWriteAssessment;
    }
    return const RootWriteAssessment(
      risk: RootWriteRisk.low,
      route: RootWriteRoute.direct,
      reason: 'Ordinary absolute paths may be written directly in Root mode; identified Android startup targets use the soft route.',
    );
  }

  /// Combines exact path assessments, keeping the most restrictive result.
  ///
  /// A file-change approval can contain more than one target. Approving the
  /// request uses the most critical concrete target. Missing target metadata
  /// does not create a generic approval gate in normal Root mode.
  static RootWriteAssessment assessPaths(Iterable<String> paths) {
    final assessments = paths.map(assessWrite).toList(growable: false);
    if (assessments.isEmpty) {
      return _unknownWriteAssessment;
    }
    assessments.sort((a, b) => _severity(b).compareTo(_severity(a)));
    return assessments.first;
  }

  /// Classifies the write scopes in an app-server permission request.
  ///
  /// Newer app-server versions send both legacy `fileSystem.write` roots and
  /// typed `fileSystem.entries`. Concrete broad roots still receive their
  /// normal critical-path classification; malformed scopes remain unknown and
  /// do not add a generic Root approval.
  static RootWriteAssessment assessPermissionRequest(
    Object? value, {
    String? workspacePath,
  }) {
    if (value is! Map) return _unknownWriteAssessment;
    final fileSystem = value['fileSystem'] ?? value['file_system'];
    if (fileSystem is! Map) return _unknownWriteAssessment;

    final writePaths = <String>[];
    final legacyWrite = fileSystem['write'];
    if (legacyWrite is List) {
      for (final path in legacyWrite) {
        writePaths.add(_permissionPath(path, workspacePath));
      }
    }

    final entries = fileSystem['entries'];
    if (entries is List) {
      for (final entry in entries) {
        if (entry is! Map) {
          writePaths.add('<unknown>');
          continue;
        }
        if (entry['access']?.toString().toLowerCase() != 'write') continue;
        writePaths.add(_entryWritePath(entry['path'], workspacePath));
      }
    }

    if (writePaths.isEmpty) return _unknownWriteAssessment;
    return assessPaths(writePaths);
  }

  static String _permissionPath(Object? value, String? workspacePath) {
    if (value is! String || value.trim().isEmpty) return '<unknown>';
    final path = value.trim();
    if (path.startsWith('/')) return path;
    if (path.startsWith('file://')) {
      final decoded = Uri.tryParse(path)?.path;
      return decoded != null && decoded.startsWith('/') ? decoded : '<unknown>';
    }
    if (path == '.' || path == './') return workspacePath ?? '<unknown>';
    if (path.startsWith('./') && workspacePath != null) {
      return '$workspacePath/${path.substring(2)}';
    }
    return '<unknown>';
  }

  static String _entryWritePath(Object? value, String? workspacePath) {
    if (value is! Map) return '<unknown>';
    switch (value['type']?.toString()) {
      case 'path':
        return _permissionPath(value['path'], workspacePath);
      case 'globPattern':
        final pattern = value['pattern'];
        if (pattern is! String || pattern.trim().isEmpty) return '<unknown>';
        final normalized = _normalize(pattern);
        if (normalized.startsWith('/workspace/') ||
            normalized.startsWith('/storage/emulated/0/codex/workspaces/')) {
          return normalized;
        }
        if (!normalized.startsWith('/')) return '/';
        final prefix = normalized.split(RegExp(r'[?*{]')).first;
        return prefix.isEmpty ? '/' : prefix.replaceFirst(RegExp(r'/+$'), '');
      case 'special':
        final special = value['value'];
        if (special is! Map) return '<unknown>';
        return switch (special['kind']?.toString()) {
          'project_roots' ||
          'current_working_directory' => workspacePath ?? '<unknown>',
          'root' => '/',
          'tmpdir' || 'slash_tmp' => '/tmp',
          _ => '<unknown>',
        };
      default:
        return '<unknown>';
    }
  }

  static const _unknownWriteAssessment = RootWriteAssessment(
    risk: RootWriteRisk.medium,
    route: RootWriteRoute.direct,
    reason: 'No concrete boot-critical target was identified; normal Root execution remains direct.',
  );

  /// Performs a conservative preflight for a command-execution approval.
  ///
  /// The command is still subject to Codex's normal approval protocol. This
  /// helper identifies ordinary, high-risk, and unknown operations so the UI
  /// can show the right context. High-risk operations use soft routing and are
  /// not permanently rejected by the app-side classifier.
  static RootWriteAssessment assessCommand(String command) {
    // A command line is not a filesystem path: canonicalizing it with
    // `_normalize` strips a trailing `/` from arguments such as `rm -rf /`,
    // which could hide a whole-filesystem target from the guard below.
    final normalized = command.trim();
    if (normalized.isEmpty || normalized.contains('\u0000')) {
      return _unknownWriteAssessment;
    }
    final tokens = normalized.split(RegExp(r'\s+'));
    final executable = tokens.first.split('/').last;
    final arguments = tokens.skip(1).join(' ');
    const readOnlyCommands = <String>{
      'cat',
      'df',
      'du',
      'dumpsys',
      'file',
      'free',
      'getprop',
      'grep',
      'head',
      'id',
      'ls',
      'md5sum',
      'ps',
      'pwd',
      'readlink',
      'realpath',
      'rg',
      'sha256sum',
      'stat',
      'tail',
      'uname',
      'wc',
      'whoami',
      'which',
    };
    final invokesRgPreprocessor =
        executable == 'rg' &&
        RegExp(r'(^|\s)--pre(?:=|\s)').hasMatch(arguments);
    final safeReadOnlyCommand =
        readOnlyCommands.contains(executable) &&
        !invokesRgPreprocessor &&
        !RegExp(r'[;&|><`$]').hasMatch(command);
    if (safeReadOnlyCommand) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.low,
        route: RootWriteRoute.direct,
        reason: 'The command is a read-only diagnostic operation.',
        readOnlyOperation: true,
      );
    }
    const writeCommands = <String>{
      'chmod',
      'chown',
      'cp',
      'dd',
      'flash',
      'fastboot',
      'insmod',
      'install',
      'ln',
      'mkfs',
      'mount',
      'mv',
      'reboot',
      'rm',
      'rmmod',
      'sed',
      'setprop',
      'tee',
      'touch',
      'truncate',
    };
    final nestedWriteCommand = RegExp(
      r'''(?:^|[\s;|&"'`])(?:chmod|chown|cp|dd|flash|fastboot|insmod|install|ln|mkfs|mount|mv|reboot|rm|rmmod|sed|setprop|tee|touch|truncate)(?=\s|$)''',
    ).hasMatch(arguments);
    final shellWrapper = const <String>{
      'bash',
      'busybox',
      'sh',
      'su',
      'toybox',
    }.contains(executable);
    final likelyWrites =
        writeCommands.contains(executable) ||
        (shellWrapper && nestedWriteCommand) ||
        RegExp(r'(^|\s)(>>?|\|\s*tee)(\s|$)').hasMatch(arguments);
    final redirectedTargets = RegExp(r'(?:>>?\s*|\btee\s+)(/[^\s;&|]+)')
        .allMatches(arguments)
        .map((match) => match.group(1)!)
        .toList();
    if (redirectedTargets.isNotEmpty) return assessPaths(redirectedTargets);
    final pathMatches = RegExp(
      r'/(?:android|workspace|storage|data|mnt|sdcard|dev/(?:block|mtd|ubi|mapper)|system(?:_ext|_root|_dlkm)?|vendor(?:_dlkm)?|product|odm(?:_dlkm)?|apex|init(?:\.[^\s;&|/]*)?|boot|vendor_boot|init_boot)(?:/[^\s;&|]*)?',
    ).allMatches(arguments).map((match) => match.group(0)!).toList();
    final explicitWriteIntent = _hasExplicitWriteIntent(command, likelyWrites);
    final rootDirectoryWrite = RegExp(r'''(?:^|[\s"'`(=,])/(?:[\s"'`,)]|$)''')
        .hasMatch(arguments);
    if (explicitWriteIntent && rootDirectoryWrite) return assessWrite('/');
    final kernelSuControlPaths = pathMatches
        .where(
          (path) => _isKernelSuControlPath(_normalizeAndroidHostPath(path)),
        )
        .toList(growable: false);
    if (kernelSuControlPaths.isNotEmpty && explicitWriteIntent) {
      return assessPaths(kernelSuControlPaths);
    }
    if (explicitWriteIntent && pathMatches.isNotEmpty) {
      return assessPaths(pathMatches);
    }
    final protectedPathMatches = pathMatches
        .where(
          (path) =>
              _isRawBlockPath(_normalizeAndroidHostPath(path)) ||
              _isBootImagePath(_normalizeAndroidHostPath(path)) ||
              _isBootCriticalSystemPath(_normalizeAndroidHostPath(path)) ||
              _isKernelSuModulePath(_normalizeAndroidHostPath(path)),
        )
        .toList(growable: false);
    // An arbitrary interpreter or helper can write through APIs that cannot
    // be inferred from argv. If it names a protected target, prefer the
    // privileged plugin path and keep the exact operation visible for
    // authorization rather than creating a permanent app-side denial.
    if (protectedPathMatches.isNotEmpty && !safeReadOnlyCommand) {
      return assessPaths(protectedPathMatches);
    }
    if (likelyWrites &&
        const <String>{'fastboot', 'flash'}.contains(executable)) {
      return const RootWriteAssessment(
        risk: RootWriteRisk.high,
        route: RootWriteRoute.kernelSuPlugin,
        reason: 'This command can flash a boot or system partition; identify the exact partition and recovery path, obtain concrete authorization, and keep direct execution available after review.',
      );
    }
    // Root is the normal execution mode. Unknown syntax is not a reason to
    // interrupt routine work with a generic approval gate; concrete boot,
    // raw-block, whole-root, boot-critical, and KernelSU-control targets were
    // routed above. Read-only sessions still reject writes via
    // enforceReadOnlySession.
    return _unknownWriteAssessment;
  }

  static int _severity(RootWriteAssessment assessment) {
    return switch (assessment.route) {
      RootWriteRoute.denied => 4,
      RootWriteRoute.kernelSuPlugin => 3,
      RootWriteRoute.userApproval => 2,
      RootWriteRoute.direct => 1,
    };
  }

  static bool _hasExplicitWriteIntent(String command, bool likelyWrites) {
    if (likelyWrites) return true;
    return RegExp(
      r'''(?:\.write(?:Text|Bytes|FileSync)?\s*\(|\b(?:writeFile|write_text|write_bytes|unlink|remove|rename|replace|truncate|chmod|fchmod|chown|fchown|mkdir|makedirs|rmdir|symlink|link|copy|copy2|copyfile|copyfileobj|move)\s*\(|\bopen\s*\([^,]+,\s*(?:mode\s*=\s*)?['"](?:[wax][bt]*\+?[bt]*|r[bt]*\+[bt]*)['"]|\.open\s*\(\s*['"](?:[wax][bt]*\+?[bt]*|r[bt]*\+[bt]*)['"]|\bO_(?:WRONLY|RDWR|TRUNC|APPEND|CREAT)\b)''',
      caseSensitive: false,
    ).hasMatch(command);
  }

  static String _normalize(String value) {
    final path = value.trim().replaceAll('\\', '/');
    if (path.isEmpty || path.contains('\u0000')) return '';

    final absolute = path.startsWith('/');
    final segments = <String>[];
    for (final segment in path.split('/')) {
      if (segment.isEmpty || segment == '.') continue;
      if (segment == '..') {
        if (segments.isNotEmpty && segments.last != '..') {
          segments.removeLast();
        } else if (!absolute) {
          // Keep unresolved relative traversal non-canonical. It will not
          // match any low-risk absolute root and therefore requires review.
          segments.add(segment);
        }
        continue;
      }
      segments.add(segment);
    }

    final normalized = '${absolute ? '/' : ''}${segments.join('/')}';
    if (normalized.isEmpty) return absolute ? '/' : '';
    return normalized;
  }

  /// Root PRoot may expose the Android host tree below `/android` in Debian.
  /// Apply the same critical-path rules to either namespace.
  static String _normalizeAndroidHostPath(String value) {
    final normalized = _normalize(value);
    if (normalized == '/android') return '/';
    if (normalized.startsWith('/android/')) {
      return _normalize(normalized.substring('/android'.length));
    }
    return normalized;
  }

  static bool _isAppWorkspacePath(String path) =>
      path == '/storage/emulated/0/Codex/Workspaces' ||
      path.startsWith('/storage/emulated/0/Codex/Workspaces/') ||
      path == '/workspace' ||
      path.startsWith('/workspace/');

  static bool _isTemporaryPath(String path) =>
      path == '/data/local/tmp/io.henry.codex' ||
      path.startsWith('/data/local/tmp/io.henry.codex/');

  static bool _isKernelSuModulePath(String path) {
    final normalized = path.toLowerCase();
    return normalized == '/data/adb/modules' ||
        normalized.startsWith('/data/adb/modules/') ||
        normalized == '/data/adb/modules_update' ||
        normalized.startsWith('/data/adb/modules_update/') ||
        normalized == '/data/adb/ksu/modules' ||
        normalized.startsWith('/data/adb/ksu/modules/') ||
        normalized == '/data/adb/ksu/bin' ||
        normalized.startsWith('/data/adb/ksu/bin/');
  }

  /// KernelSU's profile/allowlist/control state is not a module payload.
  /// Editing those files directly bypasses the Manager's profile workflow,
  /// so the request is surfaced for explicit review rather than treated as an
  /// ordinary filesystem write.
  static bool _isKernelSuControlPath(String path) {
    final normalized = path.toLowerCase();
    return (normalized == '/data/adb/ksu' ||
            normalized.startsWith('/data/adb/ksu/')) &&
        !_isKernelSuModulePath(normalized);
  }

  static bool _isRawBlockPath(String path) {
    final normalized = path.toLowerCase();
    return normalized == '/dev/block' ||
        normalized.startsWith('/dev/block/') ||
        normalized == '/dev/mapper' ||
        normalized.startsWith('/dev/mapper/') ||
        normalized == '/dev/mtd' ||
        normalized.startsWith('/dev/mtd/') ||
        RegExp(r'^/dev/mtd\d+$').hasMatch(normalized) ||
        normalized == '/dev/ubi' ||
        normalized.startsWith('/dev/ubi/') ||
        RegExp(r'^/dev/ubi\d+$').hasMatch(normalized);
  }

  static bool _isBootImagePath(String path) {
    final normalized = path.toLowerCase();
    return normalized == '/boot' ||
        normalized.startsWith('/boot/') ||
        normalized == '/vendor_boot' ||
        normalized.startsWith('/vendor_boot/') ||
        normalized == '/init_boot' ||
        normalized.startsWith('/init_boot/') ||
        normalized.contains('/boot.img') ||
        normalized.endsWith('/init_boot.img');
  }

  /// Classifies Android files that participate in early startup. Ordinary
  /// `/system`, `/vendor`, `/product`, and app-configuration writes remain
  /// direct Root operations; the partition name alone is not a boot-risk
  /// signal.
  static bool _isBootCriticalSystemPath(String path) {
    final normalized = path.toLowerCase();
    if (normalized == '/init' ||
        normalized.startsWith('/init.') ||
        normalized.startsWith('/init/')) {
      return true;
    }
    const startupDirectories = <String>[
      '/system/etc/init',
      '/system_ext/etc/init',
      '/product/etc/init',
      '/vendor/etc/init',
      '/odm/etc/init',
      '/system_root/etc/init',
      '/system/etc/selinux',
      '/system_ext/etc/selinux',
      '/product/etc/selinux',
      '/vendor/etc/selinux',
      '/odm/etc/selinux',
      '/system/lib/modules',
      '/system_dlkm/lib/modules',
      '/vendor/lib/modules',
      '/vendor_dlkm/lib/modules',
      '/odm/lib/modules',
      '/odm_dlkm/lib/modules',
    ];
    if (startupDirectories.any(
      (root) => normalized == root || normalized.startsWith('$root/'),
    )) {
      return true;
    }
    final fstabPath = RegExp(
      r'^/(?:system(?:_ext|_root)?|vendor|product|odm)/etc/fstab(?:[._-].*)?$',
    );
    return fstabPath.hasMatch(normalized) ||
        normalized == '/fstab' ||
        normalized.startsWith('/fstab.');
  }
}
