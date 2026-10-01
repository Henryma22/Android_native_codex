import '../core/domain/backend.dart';
import '../core/domain/execution.dart';
import '../core/domain/workspace.dart';

class CodexCliUpdateResult {
  const CodexCliUpdateResult({
    required this.installedVersion,
    required this.availableVersion,
    required this.updated,
    this.rolledBack = false,
  });

  final String installedVersion;
  final String availableVersion;
  final bool updated;
  final bool rolledBack;
}

/// Updates only the official Linux ARM64 CLI inside the verified app-private
/// PRoot guest. Android host ABI tools are managed separately from Codex.
class CodexCliUpdater {
  CodexCliUpdater({required this._backend, required this._workspace});

  static final _versionPattern = RegExp(
    r'(?<!\d)(\d+\.\d+\.\d+(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?)',
  );
  static final _semanticVersionPattern = RegExp(
    r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  );
  static const _registry = 'https://registry.npmjs.org';
  static const _versionsRoot = '/home/codex/.codex-cli/versions';
  static const _currentLink = '/home/codex/.codex-cli/current';
  static const _currentCli = <String>['codex', '--version'];

  final Backend _backend;
  final WorkspaceRef _workspace;

  Future<CodexCliUpdateResult> update() async {
    if (_backend.descriptor.kind != BackendKind.linuxCompatibility ||
        !_backend.descriptor.capabilities.usable) {
      throw const BackendException(
        'Codex CLI update requires a verified Linux compatibility runtime.',
      );
    }
    final current = parseVersion(await _run(_currentCli));
    final latestOutput = await _run(<String>[
      'npm',
      'view',
      '@openai/codex',
      'version',
      '--json',
      '--registry=$_registry',
    ]);
    final latest = parseVersion(latestOutput);
    final comparison = compareVersions(latest, current);
    if (comparison == 0) {
      return CodexCliUpdateResult(
        installedVersion: current,
        availableVersion: latest,
        updated: false,
      );
    }
    if (comparison < 0) {
      throw BackendException(
        'The official registry returned older Codex CLI $latest than installed $current.',
      );
    }

    // Keep the verified rootfs immutable. Its runtime manifest and digest
    // describe the shipped Linux guest; upgrades live in the bound app-private
    // home and are selected by the fixed guest command resolver.
    final versionedPrefix = '$_versionsRoot/$latest';
    await _run(
      <String>[
        'npm',
        'install',
        '--global',
        '--prefix',
        versionedPrefix,
        '@openai/codex@$latest',
        '--ignore-scripts',
        '--no-audit',
        '--no-fund',
        '--registry=$_registry',
      ],
      identity: ExecutionIdentity.app,
      timeout: const Duration(minutes: 10),
    );

    final stagedExecutable = '$versionedPrefix/bin/codex';
    final stagedVersion = parseVersion(
      await _run(<String>[stagedExecutable, '--version']),
    );
    if (stagedVersion != latest) {
      throw BackendException(
        'Staged Codex CLI reported $stagedVersion; expected $latest. The active CLI was not changed.',
      );
    }

    final previousTarget = await _readCurrentTarget();
    await _activate(
      target: 'versions/$latest',
      expectedVersion: latest,
      previousTarget: previousTarget,
      failureLabel: 'Codex CLI update',
    );

    return CodexCliUpdateResult(
      installedVersion: latest,
      availableVersion: latest,
      updated: true,
    );
  }

  /// Switches future launches to the newest retained version older than the
  /// active CLI. If no older overlay exists, the immutable rootfs CLI is also
  /// considered. Already-running Codex processes are not restarted.
  Future<CodexCliUpdateResult> rollbackToPrevious() async {
    if (_backend.descriptor.kind != BackendKind.linuxCompatibility ||
        !_backend.descriptor.capabilities.usable) {
      throw const BackendException(
        'Codex CLI rollback requires a verified Linux compatibility runtime.',
      );
    }

    final currentVersion = parseVersion(await _run(_currentCli));
    final previousTarget = await _readCurrentTarget();
    if (previousTarget == null) {
      throw const BackendException(
        'No app-installed Codex CLI override is active; there is nothing to roll back.',
      );
    }
    final activeTargetVersion = _versionFromTarget(previousTarget);
    if (activeTargetVersion != currentVersion) {
      throw BackendException(
        'The active Codex launcher points to $activeTargetVersion but reports $currentVersion; refusing to switch an inconsistent runtime.',
      );
    }

    final candidates = <_CliRollbackTarget>[];
    final rootfsResult = await _runResult(<String>[
      '/usr/local/bin/codex',
      '--version',
    ]);
    if (rootfsResult.exitCode == 0) {
      try {
        final rootfsVersion = parseVersion(rootfsResult.output);
        if (compareVersions(rootfsVersion, currentVersion) < 0) {
          candidates.add(_CliRollbackTarget(rootfsVersion, null));
        }
      } on FormatException {
        // A malformed fallback must not prevent using a verified retained
        // overlay version.
      }
    }

    final versionsOutput = await _run(<String>[
      'ls',
      '-1',
      '--',
      _versionsRoot,
    ]);
    for (final version in versionsOutput.split(RegExp(r'\s+'))) {
      if (!_semanticVersionPattern.hasMatch(version) ||
          compareVersions(version, currentVersion) >= 0) {
        continue;
      }
      final staged = await _runResult(<String>[
        '$_versionsRoot/$version/bin/codex',
        '--version',
      ]);
      if (staged.exitCode != 0) continue;
      try {
        if (parseVersion(staged.output) == version) {
          candidates.add(_CliRollbackTarget(version, 'versions/$version'));
        }
      } on FormatException {
        // Ignore incomplete or non-Codex directories; never switch to them.
      }
    }

    if (candidates.isEmpty) {
      throw BackendException(
        'No verified Codex CLI version older than $currentVersion is available.',
      );
    }
    candidates.sort(
      (left, right) => compareVersions(left.version, right.version),
    );
    final selected = candidates.last;
    await _activate(
      target: selected.launcherTarget,
      expectedVersion: selected.version,
      previousTarget: previousTarget,
      failureLabel: 'Codex CLI rollback',
    );
    return CodexCliUpdateResult(
      installedVersion: selected.version,
      availableVersion: selected.version,
      updated: true,
      rolledBack: true,
    );
  }

  Future<String?> _readCurrentTarget() async {
    final result = await _runResult(<String>['readlink', _currentLink]);
    if (result.exitCode == 1) return null;
    if (result.exitCode != 0) {
      throw BackendException(
        'Could not inspect the current Codex launcher: ${result.output.trim()}',
      );
    }
    final target = result.output.trim();
    if (target.isEmpty) {
      throw const BackendException(
        'The current Codex launcher has an empty target; the active CLI was not changed.',
      );
    }
    return target;
  }

  String _versionFromTarget(String target) {
    const prefix = 'versions/';
    if (!target.startsWith(prefix)) {
      throw const BackendException(
        'The current Codex launcher is not a versioned app CLI; refusing rollback.',
      );
    }
    final version = target.substring(prefix.length);
    if (!_semanticVersionPattern.hasMatch(version)) {
      throw const BackendException(
        'The current Codex launcher has an invalid version target; refusing rollback.',
      );
    }
    return version;
  }

  Future<void> _activate({
    required String? target,
    required String expectedVersion,
    required String? previousTarget,
    required String failureLabel,
  }) async {
    try {
      await _setCurrentTarget(target);
      final activeVersion = parseVersion(await _run(_currentCli));
      if (activeVersion != expectedVersion) {
        throw BackendException(
          'Codex launcher verification reported $activeVersion; expected $expectedVersion.',
        );
      }
    } on Object catch (error) {
      try {
        await _setCurrentTarget(previousTarget);
      } on Object catch (rollbackError) {
        throw BackendException(
          '$failureLabel failed ($error), and launcher rollback failed ($rollbackError).',
        );
      }
      rethrow;
    }
  }

  Future<void> _setCurrentTarget(String? target) async {
    if (target == null) {
      await _run(<String>[
        'rm',
        '-f',
        '--',
        _currentLink,
      ], identity: ExecutionIdentity.app);
    } else {
      // Publish the launcher as one filesystem rename. `ln -sfn` removes and
      // recreates the destination in separate steps; a session starting at
      // that exact moment can then observe a missing or partially replaced
      // `current` link. The rootfs CLI remains the fallback while the staged
      // link is prepared, and already-running processes keep their absolute
      // executable path unchanged.
      final stagedLink = '$_currentLink.next';
      await _run(<String>[
        'rm',
        '-f',
        '--',
        stagedLink,
      ], identity: ExecutionIdentity.app);
      try {
        await _run(<String>[
          'ln',
          '-s',
          '--',
          target,
          stagedLink,
        ], identity: ExecutionIdentity.app);
        await _run(<String>[
          'mv',
          '-Tf',
          '--',
          stagedLink,
          _currentLink,
        ], identity: ExecutionIdentity.app);
      } catch (_) {
        // Do not leave an unreferenced candidate that can confuse a later
        // update or a diagnostic listing.
        try {
          await _run(<String>[
            'rm',
            '-f',
            '--',
            stagedLink,
          ], identity: ExecutionIdentity.app);
        } catch (_) {
          // Preserve the original activation failure; cleanup is best effort.
        }
        rethrow;
      }
    }
  }

  static String parseVersion(String output) {
    final match = _versionPattern.firstMatch(output);
    if (match == null) {
      throw const FormatException(
        'Codex CLI returned no valid semantic version.',
      );
    }
    final version = match.group(1)!;
    if (!_semanticVersionPattern.hasMatch(version)) {
      throw const FormatException(
        'Codex CLI returned no valid semantic version.',
      );
    }
    return version;
  }

  static int compareVersions(String left, String right) {
    final a = _semanticVersion(left);
    final b = _semanticVersion(right);
    for (var index = 0; index < 3; index++) {
      final difference = int.parse(a.core[index])
          .compareTo(int.parse(b.core[index]));
      if (difference != 0) return difference;
    }
    final aPrerelease = a.prerelease;
    final bPrerelease = b.prerelease;
    if (aPrerelease == null || bPrerelease == null) {
      if (aPrerelease == bPrerelease) return 0;
      return aPrerelease == null ? 1 : -1;
    }
    final sharedLength = aPrerelease.length < bPrerelease.length
        ? aPrerelease.length
        : bPrerelease.length;
    for (var index = 0; index < sharedLength; index++) {
      final leftIdentifier = aPrerelease[index];
      final rightIdentifier = bPrerelease[index];
      if (leftIdentifier == rightIdentifier) continue;
      final leftIsNumeric = RegExp(r'^\d+$').hasMatch(leftIdentifier);
      final rightIsNumeric = RegExp(r'^\d+$').hasMatch(rightIdentifier);
      if (leftIsNumeric && rightIsNumeric) {
        final leftNormalized = leftIdentifier.replaceFirst(
          RegExp(r'^0+(?=\d)'),
          '',
        );
        final rightNormalized = rightIdentifier.replaceFirst(
          RegExp(r'^0+(?=\d)'),
          '',
        );
        final lengthDifference = leftNormalized.length.compareTo(
          rightNormalized.length,
        );
        if (lengthDifference != 0) return lengthDifference;
        final numericDifference = leftNormalized.compareTo(rightNormalized);
        if (numericDifference != 0) return numericDifference;
      } else if (leftIsNumeric != rightIsNumeric) {
        return leftIsNumeric ? -1 : 1;
      } else {
        return leftIdentifier.compareTo(rightIdentifier);
      }
    }
    return aPrerelease.length.compareTo(bPrerelease.length);
  }

  static _SemanticVersion _semanticVersion(String value) {
    final match = _semanticVersionPattern.firstMatch(value);
    if (match == null) {
      throw FormatException('Invalid Codex CLI semantic version: $value');
    }
    return _SemanticVersion(
      core: <String>[match.group(1)!, match.group(2)!, match.group(3)!],
      prerelease: match.group(4)?.split('.'),
    );
  }

  Future<String> _run(
    List<String> argv, {
    ExecutionIdentity identity = ExecutionIdentity.app,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final result = await _runResult(argv, identity: identity, timeout: timeout);
    if (result.exitCode != 0) {
      final detail = result.output.trim();
      throw BackendException(
        'Codex CLI update command exited ${result.exitCode ?? 'without an exit code'}${detail.isEmpty ? '' : ': $detail'}',
      );
    }
    return result.output;
  }

  Future<_CommandResult> _runResult(
    List<String> argv, {
    ExecutionIdentity identity = ExecutionIdentity.app,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    final output = StringBuffer();
    int? exitCode;
    try {
      await for (final event in _backend.execute(
        ExecutionRequest(
          argv: argv,
          cwd: _workspace.hostPath,
          identity: identity,
          timeout: timeout,
        ),
      )) {
        if (event.stdout != null) output.write(event.stdout);
        if (event.stderr != null) output.write(event.stderr);
        if (event.error != null) output.write(event.error);
        if (event.exitCode != null) exitCode = event.exitCode;
      }
    } on Object catch (error) {
      throw BackendException('Codex CLI update command failed: $error');
    }
    return _CommandResult(output.toString(), exitCode);
  }
}

class _CommandResult {
  const _CommandResult(this.output, this.exitCode);

  final String output;
  final int? exitCode;
}

class _SemanticVersion {
  const _SemanticVersion({required this.core, required this.prerelease});

  final List<String> core;
  final List<String>? prerelease;
}

class _CliRollbackTarget {
  const _CliRollbackTarget(this.version, this.launcherTarget);

  final String version;
  final String? launcherTarget;
}
