/// Returns a readable path for presentation without changing workspace IDs.
/// SAF document IDs commonly arrive percent-encoded (for example,
/// `primary%3ACodex%2FWorkspaces%2Fdemo`) and must not be shown verbatim.
String humanReadableWorkspacePath(String rawPath) {
  var value = rawPath.trim();
  if (value.toLowerCase().startsWith('saf:')) {
    value = value.substring(4).trim();
  }

  final uri = Uri.tryParse(value);
  if (uri?.scheme.toLowerCase() == 'content') {
    final segments = uri!.pathSegments;
    final marker = segments.lastIndexWhere(
      (segment) => segment == 'tree' || segment == 'document',
    );
    if (marker >= 0 && marker + 1 < segments.length) {
      value = segments[marker + 1];
    } else if (segments.isNotEmpty) {
      value = segments.last;
    }
  }

  if (RegExp(r'%(?:3a|2f)', caseSensitive: false).hasMatch(value)) {
    try {
      value = Uri.decodeComponent(value);
    } on FormatException {
      // Keep an invalid legacy encoding visible instead of failing the home.
    }
  }
  return value.trim().replaceAll('\\', '/');
}

String workspaceNameFromPath(
  String rawPath, {
  String fallback = 'Local workspace',
}) {
  final normalized = humanReadableWorkspacePath(rawPath)
      .replaceFirst(RegExp(r'/+$'), '');
  final parts = normalized
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? fallback : parts.last;
}

class WorkspaceRef {
  const WorkspaceRef({
    required this.backendId,
    required this.filesystemOwnerId,
    required this.displayPath,
    required this.hostPath,
    required this.backendLocator,
  });

  final String backendId;
  final String filesystemOwnerId;
  final String displayPath;
  final String hostPath;
  final String backendLocator;

  @override
  bool operator ==(Object other) =>
      other is WorkspaceRef &&
      other.backendId == backendId &&
      other.filesystemOwnerId == filesystemOwnerId &&
      other.backendLocator == backendLocator;

  @override
  int get hashCode => Object.hash(backendId, filesystemOwnerId, backendLocator);
}

class WorkspaceHandle {
  const WorkspaceHandle(this.ref);

  final WorkspaceRef ref;
}

class WorkspaceEntry {
  const WorkspaceEntry({
    required this.name,
    required this.relativePath,
    required this.isDirectory,
    required this.sizeBytes,
  });

  final String name;
  final String relativePath;
  final bool isDirectory;
  final int sizeBytes;
}
