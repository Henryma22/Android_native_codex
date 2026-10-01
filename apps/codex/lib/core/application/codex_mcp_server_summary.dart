/// Safe, user-facing summary of one MCP server in Codex's effective config.
///
/// Secret-bearing values such as env values, headers, OAuth data, URL paths,
/// query parameters, fragments, and command arguments are intentionally not
/// retained in this object.
class CodexMcpServerSummary {
  const CodexMcpServerSummary({
    required this.name,
    required this.enabled,
    required this.transport,
    this.endpointOrigin,
    this.commandName,
    this.argumentCount = 0,
  });

  final String name;
  final bool enabled;
  final String transport;
  final String? endpointOrigin;
  final String? commandName;
  final int argumentCount;

  Map<String, Object?> toSafeJsonMap() => <String, Object?>{
    'name': name,
    'enabled': enabled,
    'transport': transport,
    if (endpointOrigin != null) 'endpointOrigin': endpointOrigin,
    if (commandName != null) 'commandName': commandName,
    if (transport == 'stdio') 'argumentCount': argumentCount,
  };

  static List<CodexMcpServerSummary> parse(Object? value) {
    if (value == null) return const <CodexMcpServerSummary>[];
    if (value is! Map) {
      throw const FormatException('Codex MCP server config is not an object.');
    }

    final entries =
        value.entries
            .where((entry) => entry.key is String)
            .map((entry) => MapEntry(entry.key as String, entry.value))
            .where((entry) => entry.key.trim().isNotEmpty)
            .toList(growable: false)
          ..sort((left, right) => left.key.compareTo(right.key));

    return entries
        .map((entry) => _fromEntry(entry.key, entry.value))
        .toList(growable: false);
  }

  String displayLine({required bool chinese}) {
    final state = enabled
        ? (chinese ? '已启用' : 'enabled')
        : (chinese ? '已停用' : 'disabled');
    final details = switch (transport) {
      'http' => 'HTTP${endpointOrigin == null ? '' : ' · $endpointOrigin'}',
      'stdio' => <String>[
        'stdio',
        ?commandName,
        if (argumentCount > 0)
          chinese ? '$argumentCount 个参数' : '$argumentCount args',
      ].join(' · '),
      _ => chinese ? '类型未知' : 'unknown transport',
    };
    return '$name · $state · $details';
  }

  static CodexMcpServerSummary _fromEntry(String name, Object? value) {
    final config = _stringKeyedMap(value);
    final rawEnabled = config['enabled'];
    final enabled = rawEnabled is bool ? rawEnabled : true;
    final url = config['url'];
    if (url is String && url.trim().isNotEmpty) {
      return CodexMcpServerSummary(
        name: _safeName(name),
        enabled: enabled,
        transport: 'http',
        endpointOrigin: _originOnly(url),
      );
    }

    final command = config['command'];
    if (command is String && command.trim().isNotEmpty) {
      final basename = command.trim().replaceAll('\\', '/').split('/').last;
      final args = config['args'];
      return CodexMcpServerSummary(
        name: _safeName(name),
        enabled: enabled,
        transport: 'stdio',
        commandName: _safeName(basename),
        argumentCount: args is List ? args.length : 0,
      );
    }

    return CodexMcpServerSummary(
      name: _safeName(name),
      enabled: enabled,
      transport: 'unknown',
    );
  }

  static Map<String, Object?> _stringKeyedMap(Object? value) {
    if (value is! Map) return const <String, Object?>{};
    return <String, Object?>{
      for (final entry in value.entries)
        if (entry.key is String) entry.key as String: entry.value,
    };
  }

  static String? _originOnly(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null || !uri.hasScheme || uri.host.isEmpty) return null;
    final host = uri.host.contains(':') ? '[${uri.host}]' : uri.host;
    final port = uri.hasPort ? ':${uri.port}' : '';
    return '${uri.scheme.toLowerCase()}://$host$port';
  }

  static String _safeName(String value) => value
      .replaceAll(RegExp(r'[\r\n\t]+'), ' ')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();
}

/// Whitelisted live MCP status data returned by app-server.
///
/// Tool names, server error text, capabilities, and raw config are deliberately
/// discarded because they can contain private workspace or credential data.
class CodexMcpServerStatusSummary {
  const CodexMcpServerStatusSummary({
    required this.name,
    required this.runtimeStatus,
    required this.authStatus,
    required this.toolCount,
    required this.hasToolsError,
  });

  final String name;
  final String? runtimeStatus;
  final String authStatus;
  final int toolCount;
  final bool hasToolsError;

  Map<String, Object?> toSafeJsonMap() => <String, Object?>{
    'name': name,
    'runtimeStatus': runtimeStatus,
    'authStatus': authStatus,
    'toolCount': toolCount,
    'hasToolsError': hasToolsError,
  };

  String displayLine({required bool chinese}) {
    final runtime = switch (runtimeStatus) {
      'notStarted' => chinese ? '未启动' : 'not started',
      'starting' => chinese ? '连接中' : 'starting',
      'connected' => chinese ? '已连接' : 'connected',
      'authenticationRequired' => chinese ? '需要认证' : 'authentication required',
      'failed' => chinese ? '连接失败' : 'failed',
      'cancelled' => chinese ? '已取消' : 'cancelled',
      'disabled' => chinese ? '已停用' : 'disabled',
      _ => chinese ? '状态未知' : 'unknown',
    };
    final auth = switch (authStatus) {
      'unsupported' => chinese ? '不支持认证' : 'unsupported',
      'notLoggedIn' => chinese ? '未登录' : 'not logged in',
      'bearerToken' => chinese ? 'Bearer token' : 'bearer token',
      'oauth' => 'OAuth',
      _ => chinese ? '认证未知' : 'auth unknown',
    };
    final tools = chinese ? '$toolCount 个工具' : '$toolCount tools';
    final error = hasToolsError
        ? (chinese ? ' · 工具列表异常' : ' · tool discovery error')
        : '';
    return '$name · $runtime · $auth · $tools$error';
  }

  static List<CodexMcpServerStatusSummary> parse(Object? value) {
    if (value is! List) {
      throw const FormatException('Codex MCP status data is not a list.');
    }
    return value
        .map((entry) {
          if (entry is! Map) {
            throw const FormatException(
              'Codex MCP status entry is not an object.',
            );
          }
          final name = entry['name'];
          if (name is! String || name.trim().isEmpty) {
            throw const FormatException('Codex MCP status entry has no name.');
          }
          final rawRuntimeStatus = entry['runtimeStatus'];
          final runtimeStatus =
              rawRuntimeStatus is String &&
                  _runtimeStatuses.contains(rawRuntimeStatus)
              ? rawRuntimeStatus
              : null;
          final rawAuthStatus = entry['authStatus'];
          final authStatus =
              rawAuthStatus is String && _authStatuses.contains(rawAuthStatus)
              ? rawAuthStatus
              : 'unknown';
          final tools = entry['tools'];
          final toolCount = tools is Map ? tools.length : 0;
          return CodexMcpServerStatusSummary(
            name: CodexMcpServerSummary._safeName(name),
            runtimeStatus: runtimeStatus,
            authStatus: authStatus,
            toolCount: toolCount,
            hasToolsError:
                entry['toolsError'] is String &&
                (entry['toolsError'] as String).isNotEmpty,
          );
        })
        .toList(growable: false);
  }

  static const _runtimeStatuses = <String>{
    'notStarted',
    'starting',
    'connected',
    'authenticationRequired',
    'failed',
    'cancelled',
    'disabled',
  };
  static const _authStatuses = <String>{
    'unknown',
    'unsupported',
    'notLoggedIn',
    'bearerToken',
    'oauth',
  };
}
