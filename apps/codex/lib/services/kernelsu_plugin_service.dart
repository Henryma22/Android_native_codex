import 'package:flutter/services.dart';

class KernelSuPluginService {
  const KernelSuPluginService();

  static const _channel = MethodChannel('io.henry.codex/kernelsu_plugin');

  Future<KernelSuCapability> probe() async {
    final raw = await _channel.invokeMethod<Object?>('probe');
    return KernelSuCapability.fromMap(_map(raw));
  }

  Future<KernelSuPluginArchive?> pickArchive() async {
    final raw = await _channel.invokeMethod<Object?>('pickArchive');
    if (raw == null) return null;
    return KernelSuPluginArchive.fromMap(_map(raw));
  }

  Future<KernelSuPluginStage> stage({
    required String requestId,
    required KernelSuPluginArchive archive,
  }) async {
    final raw = await _channel.invokeMethod<Object?>('stage', {
      'requestId': requestId,
      'archiveBytes': archive.bytes,
      'sha256': archive.sha256,
    });
    return KernelSuPluginStage.fromMap(_map(raw));
  }

  Future<KernelSuPluginOperation> install(
    KernelSuPluginStage stage, {
    String confirmation = 'none',
  }) => _operation('install', stage, confirmation: confirmation);

  Future<KernelSuPluginOperation> enable(
    KernelSuPluginStage stage, {
    String confirmation = 'none',
  }) => _operation('enable', stage, confirmation: confirmation);

  Future<KernelSuPluginOperation> disable(KernelSuPluginStage stage) =>
      _operation('disable', stage);

  Future<KernelSuPluginOperation> uninstall(KernelSuPluginStage stage) =>
      _operation('uninstall', stage);

  Future<KernelSuPluginOperation> rollback(
    KernelSuPluginStage stage, {
    String confirmation = 'none',
  }) => _operation('rollback', stage, confirmation: confirmation);

  Future<KernelSuPluginOperation> runAction(
    KernelSuPluginStage stage,
    String actionId, {
    String confirmation = 'none',
  }) => _operation(
    'runAction',
    stage,
    confirmation: confirmation,
    extra: <String, Object?>{'actionId': actionId},
  );

  Future<KernelSuPluginOperation> list([String? moduleId]) async {
    final raw = await _channel.invokeMethod<Object?>('list', {
      if (moduleId != null && moduleId.trim().isNotEmpty) 'moduleId': moduleId,
    });
    return KernelSuPluginOperation.fromMap(_map(raw));
  }

  Future<KernelSuPluginStage?> restoreStage() async {
    final raw = await _channel.invokeMethod<Object?>('restoreStage');
    if (raw == null) return null;
    return KernelSuPluginStage.fromMap(_map(raw));
  }

  Future<KernelSuPluginOperation> _operation(
    String method,
    KernelSuPluginStage stage, {
    String confirmation = 'none',
    Map<String, Object?> extra = const <String, Object?>{},
  }) async {
    final arguments = <String, Object?>{
      'requestId': stage.requestId,
      'moduleId': stage.moduleId,
      'sha256': stage.sha256,
      'confirmation': confirmation,
      ...extra,
    };
    final raw = await _channel.invokeMethod<Object?>(method, arguments);
    return KernelSuPluginOperation.fromMap(_map(raw));
  }

  static Map<Object?, Object?> _map(Object? raw) {
    if (raw is Map<Object?, Object?>) return raw;
    if (raw is Map) return raw.cast<Object?, Object?>();
    throw const FormatException('KernelSU plugin returned an invalid result.');
  }
}

class KernelSuCapability {
  const KernelSuCapability({required this.available, required this.state});

  factory KernelSuCapability.fromMap(Map<Object?, Object?> value) {
    return KernelSuCapability(
      available: value['available'] == true,
      state: value['state'] as String? ?? 'unavailable',
    );
  }

  final bool available;
  final String state;
}

class KernelSuPluginArchive {
  const KernelSuPluginArchive({
    required this.bytes,
    required this.sha256,
    this.displayName,
  });

  factory KernelSuPluginArchive.fromMap(Map<Object?, Object?> value) {
    final rawBytes = value['bytes'];
    final bytes = rawBytes is Uint8List
        ? rawBytes
        : rawBytes is List
        ? Uint8List.fromList(rawBytes.cast<int>())
        : throw const FormatException('Plugin archive bytes are missing.');
    final sha256 = value['sha256'] as String?;
    if (sha256 == null || sha256.length != 64) {
      throw const FormatException('Plugin archive digest is missing.');
    }
    return KernelSuPluginArchive(
      bytes: bytes,
      sha256: sha256,
      displayName: value['displayName'] as String?,
    );
  }

  final Uint8List bytes;
  final String sha256;
  final String? displayName;
}

class KernelSuPluginStage {
  const KernelSuPluginStage({
    required this.requestId,
    required this.moduleId,
    required this.sha256,
    required this.effectiveRisk,
    required this.archiveSizeBytes,
    required this.uncompressedSizeBytes,
    required this.entryCount,
    required this.containsScripts,
    required this.requiresReboot,
    required this.review,
    required this.archiveEntries,
    required this.archiveEntriesTruncated,
  });

  factory KernelSuPluginStage.fromMap(Map<Object?, Object?> value) {
    return KernelSuPluginStage(
      requestId: value['requestId'] as String? ?? '',
      moduleId: value['moduleId'] as String? ?? '',
      sha256: value['sha256'] as String? ?? '',
      effectiveRisk: value['effectiveRisk'] as String? ?? 'R4',
      archiveSizeBytes: (value['archiveSizeBytes'] as num?)?.toInt() ?? 0,
      uncompressedSizeBytes:
          (value['uncompressedSizeBytes'] as num?)?.toInt() ?? 0,
      entryCount: (value['entryCount'] as num?)?.toInt() ?? 0,
      containsScripts: value['containsScripts'] == true,
      requiresReboot: value['requiresReboot'] == true,
      review: KernelSuPluginReviewDetails.fromStage(value),
      archiveEntries: _readStrings(value['archiveEntries']),
      archiveEntriesTruncated: value['archiveEntriesTruncated'] == true,
    );
  }

  final String requestId;
  final String moduleId;
  final String sha256;
  final String effectiveRisk;
  final int archiveSizeBytes;
  final int uncompressedSizeBytes;
  final int entryCount;
  final bool containsScripts;
  final bool requiresReboot;
  final KernelSuPluginReviewDetails review;
  final List<String> archiveEntries;
  final bool archiveEntriesTruncated;

  bool get canAutoApply => effectiveRisk == 'R1';
  bool get requiresApproval =>
      effectiveRisk == 'R2' || effectiveRisk == 'R3' || effectiveRisk == 'R4';
  bool get requiresExplicitEnable =>
      effectiveRisk == 'R3' || effectiveRisk == 'R4';
}

class KernelSuPluginReviewDetails {
  const KernelSuPluginReviewDetails({
    required this.name,
    required this.version,
    required this.riskHint,
    required this.reversible,
    required this.capabilities,
    required this.overlayRoots,
    required this.actions,
    required this.backupTargets,
    required this.healthChecks,
    required this.author,
    required this.description,
    required this.files,
  });

  factory KernelSuPluginReviewDetails.fromStage(Map<Object?, Object?> stage) {
    final rawManifest = stage['reviewManifest'];
    final manifest = rawManifest is Map
        ? rawManifest.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final rawModuleProp = stage['moduleProp'];
    final moduleProp = rawModuleProp is Map
        ? rawModuleProp.cast<Object?, Object?>()
        : const <Object?, Object?>{};
    final rawFiles = stage['reviewFiles'];
    return KernelSuPluginReviewDetails(
      name: manifest['name'] as String? ?? '',
      version: manifest['version'] as String? ?? '',
      riskHint: manifest['riskHint'] as String? ?? 'R4',
      reversible: manifest['reversible'] == true,
      capabilities: _readStrings(manifest['capabilities']),
      overlayRoots: _readStrings(manifest['overlayRoots']),
      actions: _readStrings(manifest['actions']),
      backupTargets: _readStrings(manifest['backupTargets']),
      healthChecks: _readStrings(manifest['healthChecks']),
      author: moduleProp['author'] as String? ?? '',
      description: moduleProp['description'] as String? ?? '',
      files: rawFiles is List
          ? rawFiles
                .whereType<Map>()
                .map(
                  (item) => KernelSuPluginReviewFile.fromMap(
                    item.cast<Object?, Object?>(),
                  ),
                )
                .toList(growable: false)
          : const <KernelSuPluginReviewFile>[],
    );
  }

  final String name;
  final String version;
  final String riskHint;
  final bool reversible;
  final List<String> capabilities;
  final List<String> overlayRoots;
  final List<String> actions;
  final List<String> backupTargets;
  final List<String> healthChecks;
  final String author;
  final String description;
  final List<KernelSuPluginReviewFile> files;
}

class KernelSuPluginReviewFile {
  const KernelSuPluginReviewFile({
    required this.path,
    required this.sizeBytes,
    required this.content,
    required this.truncated,
  });

  factory KernelSuPluginReviewFile.fromMap(Map<Object?, Object?> value) =>
      KernelSuPluginReviewFile(
        path: value['path'] as String? ?? '',
        sizeBytes: (value['sizeBytes'] as num?)?.toInt() ?? 0,
        content: value['content'] as String?,
        truncated: value['truncated'] == true,
      );

  final String path;
  final int sizeBytes;
  final String? content;
  final bool truncated;
}

List<String> _readStrings(Object? value) => value is List
    ? value.whereType<String>().toList(growable: false)
    : const <String>[];

class KernelSuPluginOperation {
  const KernelSuPluginOperation({
    required this.moduleId,
    required this.effectiveRisk,
    required this.operations,
    this.modules = const <KernelSuPluginModule>[],
  });

  factory KernelSuPluginOperation.fromMap(Map<Object?, Object?> value) {
    return KernelSuPluginOperation(
      moduleId: value['moduleId'] as String? ?? '',
      effectiveRisk: value['effectiveRisk'] as String? ?? 'R4',
      operations:
          (value['operations'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[],
      modules:
          (value['modules'] as List?)
              ?.whereType<Map>()
              .map(
                (item) =>
                    KernelSuPluginModule.fromMap(item.cast<Object?, Object?>()),
              )
              .toList(growable: false) ??
          const <KernelSuPluginModule>[],
    );
  }

  final String moduleId;
  final String effectiveRisk;
  final List<String> operations;
  final List<KernelSuPluginModule> modules;
}

class KernelSuPluginModule {
  const KernelSuPluginModule({
    required this.id,
    required this.name,
    required this.version,
    required this.author,
    required this.enabled,
  });

  factory KernelSuPluginModule.fromMap(Map<Object?, Object?> value) =>
      KernelSuPluginModule(
        id: value['id'] as String? ?? '',
        name: value['name'] as String? ?? '',
        version: value['version'] as String? ?? '',
        author: value['author'] as String? ?? '',
        enabled: value['enabled'] == true,
      );

  final String id;
  final String name;
  final String version;
  final String author;
  final bool enabled;
}
