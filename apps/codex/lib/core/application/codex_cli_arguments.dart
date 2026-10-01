import 'dart:convert';

/// Splits a user-entered Codex command into argv without invoking a shell.
///
/// Single and double quotes group whitespace; a backslash outside quotes can
/// escape whitespace, a quote, or another backslash. Variable expansion,
/// pipes, redirection, and command substitution are deliberately not applied.
List<String> tokenizeCodexCommand(String commandLine) {
  final characters = commandLine.runes
      .map(String.fromCharCode)
      .toList(growable: false);
  final arguments = <String>[];
  final current = StringBuffer();
  String? quote;
  var tokenStarted = false;

  void finishToken() {
    if (!tokenStarted) return;
    arguments.add(current.toString());
    current.clear();
    tokenStarted = false;
  }

  for (var index = 0; index < characters.length; index++) {
    final character = characters[index];
    if (quote == "'") {
      if (character == "'") {
        quote = null;
      } else {
        current.write(character);
      }
      tokenStarted = true;
      continue;
    }

    if (quote == '"') {
      if (character == '"') {
        quote = null;
        tokenStarted = true;
      } else if (character == r'\' &&
          index + 1 < characters.length &&
          (characters[index + 1] == '"' || characters[index + 1] == r'\')) {
        current.write(characters[++index]);
        tokenStarted = true;
      } else {
        current.write(character);
        tokenStarted = true;
      }
      continue;
    }

    if (character == "'" || character == '"') {
      quote = character;
      tokenStarted = true;
      continue;
    }
    if (RegExp(r'\s').hasMatch(character)) {
      finishToken();
      continue;
    }
    if (character == r'\' && index + 1 < characters.length) {
      final next = characters[index + 1];
      if (RegExp(r'\s').hasMatch(next) ||
          next == "'" ||
          next == '"' ||
          next == r'\') {
        current.write(next);
        index++;
      } else {
        current.write(character);
      }
      tokenStarted = true;
      continue;
    }
    current.write(character);
    tokenStarted = true;
  }

  if (quote != null) {
    throw const FormatException('Unclosed quote in Codex command.');
  }
  finishToken();
  return arguments;
}

enum CodexCliCommandRoute {
  execute,
  appServerOwned,
  accountSettings,
  updaterSettings,
  appSessionUi,
  appServerDaemon,
  mcpList,
  mcpGet,
  mcpStatus,
  mcpAdd,
  mcpRemove,
  mcpAuthentication,
  mcpConfiguration,
  threadList,
  pluginList,
  pluginMarketplaceList,
  pluginConfiguration,
}

/// Identifies CLI operations that cannot safely run in an isolated one-shot
/// CODEX_HOME. Help/version and read-only subcommands remain executable.
CodexCliCommandRoute codexCliCommandRoute(List<String> arguments) {
  if (arguments.isEmpty ||
      arguments.any(
        (argument) =>
            argument == '--help' || argument == '-h' || argument == '--version',
      )) {
    return CodexCliCommandRoute.execute;
  }

  final command = arguments.first.toLowerCase();
  final subcommand = arguments.length > 1 ? arguments[1].toLowerCase() : '';
  switch (command) {
    case 'app-server':
      return CodexCliCommandRoute.appServerOwned;
    case 'login':
    case 'logout':
      return CodexCliCommandRoute.accountSettings;
    case 'update':
      return CodexCliCommandRoute.updaterSettings;
    case 'resume':
    case 'r':
    case 'fork':
    case 'archive':
    case 'delete':
    case 'unarchive':
    case 'migrate-rollouts':
      return CodexCliCommandRoute.appSessionUi;
    case 'agents':
    case 'queue':
    case 'remote-control':
    case 'exec-server':
      return CodexCliCommandRoute.appServerDaemon;
    case 'mcp':
      if (subcommand == 'list') {
        return CodexCliCommandRoute.mcpList;
      }
      if (subcommand == 'get') {
        return CodexCliCommandRoute.mcpGet;
      }
      if (subcommand == 'status') {
        return CodexCliCommandRoute.mcpStatus;
      }
      if (subcommand == 'add') {
        return CodexCliCommandRoute.mcpAdd;
      }
      if (subcommand == 'remove') {
        return CodexCliCommandRoute.mcpRemove;
      }
      if (subcommand == 'login' || subcommand == 'logout') {
        return CodexCliCommandRoute.mcpAuthentication;
      }
    case 'thread':
      if (subcommand == 'list') {
        return CodexCliCommandRoute.threadList;
      }
    case 'plugin':
      if (subcommand == 'list') {
        return CodexCliCommandRoute.pluginList;
      }
      if (subcommand == 'add' ||
          subcommand == 'remove' ||
          subcommand == 'enable' ||
          subcommand == 'disable') {
        return CodexCliCommandRoute.pluginConfiguration;
      }
      if (subcommand == 'marketplace' && arguments.length > 2) {
        final operation = arguments[2].toLowerCase();
        if (operation == 'list') {
          return CodexCliCommandRoute.pluginMarketplaceList;
        }
        if (operation == 'add' ||
            operation == 'remove' ||
            operation == 'upgrade') {
          return CodexCliCommandRoute.pluginConfiguration;
        }
      }
  }
  return CodexCliCommandRoute.execute;
}

class CodexThreadListRequest {
  const CodexThreadListRequest({
    required this.archived,
    this.searchTerm,
    required this.jsonOutput,
  });

  final bool archived;
  final String? searchTerm;
  final bool jsonOutput;

  static CodexThreadListRequest parse(List<String> arguments) {
    if (arguments.length < 2 ||
        arguments[0].toLowerCase() != 'thread' ||
        arguments[1].toLowerCase() != 'list') {
      throw const FormatException(
        'Usage: thread list [--archived] [--search <term>] [--json].',
      );
    }
    var archived = false;
    var jsonOutput = false;
    String? searchTerm;
    for (var index = 2; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--archived') {
        if (archived) {
          throw const FormatException('--archived may only be used once.');
        }
        archived = true;
      } else if (value == '--json') {
        jsonOutput = true;
      } else if (value == '--search') {
        if (searchTerm != null || ++index >= arguments.length) {
          throw const FormatException('--search requires one value.');
        }
        searchTerm = _validCliValue(arguments[index], 'Search term');
      } else {
        throw FormatException('Unsupported thread list option: $value.');
      }
    }
    return CodexThreadListRequest(
      archived: archived,
      searchTerm: searchTerm,
      jsonOutput: jsonOutput,
    );
  }
}

class CodexPluginInstallRequest {
  const CodexPluginInstallRequest({
    required this.pluginName,
    required this.marketplaceName,
    required this.jsonOutput,
  });

  final String pluginName;
  final String marketplaceName;
  final bool jsonOutput;

  static CodexPluginInstallRequest parse(List<String> arguments) {
    return _parsePluginMutation(
      arguments,
      operation: 'add',
      errorUsage: 'Usage: plugin add <plugin[@marketplace]> [--marketplace <name>] [--json].',
      builder: (plugin, marketplace, jsonOutput) => CodexPluginInstallRequest(
        pluginName: plugin,
        marketplaceName: marketplace,
        jsonOutput: jsonOutput,
      ),
    );
  }
}

class CodexPluginListRequest {
  const CodexPluginListRequest({
    this.marketplaceName,
    required this.jsonOutput,
    required this.available,
  });

  final String? marketplaceName;
  final bool jsonOutput;
  final bool available;

  static CodexPluginListRequest parse(List<String> arguments) {
    if (arguments.length < 2 ||
        arguments[0].toLowerCase() != 'plugin' ||
        arguments[1].toLowerCase() != 'list') {
      throw const FormatException(
        'Usage: plugin list [--marketplace <name>] [--available] [--json].',
      );
    }
    String? marketplaceName;
    var jsonOutput = false;
    var available = false;
    for (var index = 2; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--json') {
        jsonOutput = true;
      } else if (value == '--available') {
        if (available) {
          throw const FormatException('--available may only be used once.');
        }
        available = true;
      } else if (value == '--marketplace' || value == '-m') {
        if (marketplaceName != null || ++index >= arguments.length) {
          throw const FormatException('--marketplace requires one value.');
        }
        marketplaceName = _validCliValue(arguments[index], 'Marketplace name');
      } else {
        throw FormatException('Unsupported plugin list option: $value.');
      }
    }
    if (available && !jsonOutput) {
      throw const FormatException('--available requires --json.');
    }
    return CodexPluginListRequest(
      marketplaceName: marketplaceName,
      jsonOutput: jsonOutput,
      available: available,
    );
  }
}

class CodexPluginRemoveRequest {
  const CodexPluginRemoveRequest({
    required this.pluginId,
    required this.jsonOutput,
  });

  final String pluginId;
  final bool jsonOutput;

  static CodexPluginRemoveRequest parse(List<String> arguments) {
    if (arguments.length < 3) {
      throw const FormatException(
        'Usage: plugin remove <plugin[@marketplace]> [--marketplace <name>] [--json].',
      );
    }
    String? plugin;
    String? marketplace;
    var jsonOutput = false;
    for (var index = 2; index < arguments.length; index++) {
      final argument = arguments[index];
      if (argument == '--json') {
        jsonOutput = true;
      } else if (argument == '--marketplace' || argument == '-m') {
        if (marketplace != null || ++index >= arguments.length) {
          throw const FormatException('--marketplace requires one value.');
        }
        marketplace = _validCliValue(arguments[index], 'Marketplace name');
      } else if (argument.startsWith('-') || plugin != null) {
        throw const FormatException(
          'Plugin remove accepts one plugin selector.',
        );
      } else {
        plugin = argument;
      }
    }
    final rawPlugin = plugin?.trim() ?? '';
    if (rawPlugin.isEmpty) {
      throw const FormatException(
        'Usage: plugin remove <plugin[@marketplace]> [--marketplace <name>] [--json].',
      );
    }
    final at = rawPlugin.lastIndexOf('@');
    final embeddedMarketplace = at > 0 && at < rawPlugin.length - 1
        ? rawPlugin.substring(at + 1)
        : null;
    final pluginName = embeddedMarketplace == null
        ? rawPlugin
        : rawPlugin.substring(0, at);
    final effectiveMarketplace = marketplace ?? embeddedMarketplace;
    if (effectiveMarketplace == null ||
        !_validPluginSegment(pluginName) ||
        !_validPluginSegment(effectiveMarketplace)) {
      throw const FormatException(
        'Plugin selector must use <plugin>@<marketplace> or --marketplace <name>.',
      );
    }
    if (marketplace != null &&
        embeddedMarketplace != null &&
        marketplace != embeddedMarketplace) {
      throw const FormatException(
        'Plugin selector marketplace conflicts with --marketplace.',
      );
    }
    return CodexPluginRemoveRequest(
      pluginId: '$pluginName@$effectiveMarketplace',
      jsonOutput: jsonOutput,
    );
  }
}

class CodexPluginToggleRequest {
  const CodexPluginToggleRequest({
    required this.pluginId,
    required this.enabled,
    required this.jsonOutput,
  });

  final String pluginId;
  final bool enabled;
  final bool jsonOutput;

  static CodexPluginToggleRequest parse(
    List<String> arguments, {
    required bool enabled,
  }) {
    final operation = enabled ? 'enable' : 'disable';
    return _parsePluginMutation(
      arguments,
      operation: operation,
      errorUsage:
          'Usage: plugin $operation <plugin[@marketplace]> [--marketplace <name>] [--json].',
      builder: (plugin, marketplace, jsonOutput) => CodexPluginToggleRequest(
        pluginId: '$plugin@$marketplace',
        enabled: enabled,
        jsonOutput: jsonOutput,
      ),
    );
  }
}

class CodexPluginMarketplaceAddRequest {
  const CodexPluginMarketplaceAddRequest({
    required this.source,
    this.refName,
    this.sparsePaths = const <String>[],
    required this.jsonOutput,
  });

  final String source;
  final String? refName;
  final List<String> sparsePaths;
  final bool jsonOutput;

  static CodexPluginMarketplaceAddRequest parse(List<String> arguments) {
    if (arguments.length < 4 ||
        arguments[0].toLowerCase() != 'plugin' ||
        arguments[1].toLowerCase() != 'marketplace' ||
        arguments[2].toLowerCase() != 'add') {
      throw const FormatException(
        'Usage: plugin marketplace add <source> [--ref <ref>] [--sparse <path>] [--json].',
      );
    }
    final source = arguments[3].trim();
    if (source.isEmpty || source.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('Marketplace source is invalid.');
    }
    String? refName;
    final sparsePaths = <String>[];
    var jsonOutput = false;
    for (var index = 4; index < arguments.length; index++) {
      switch (arguments[index]) {
        case '--json':
          jsonOutput = true;
          break;
        case '--ref':
          if (refName != null || ++index >= arguments.length) {
            throw const FormatException(
              'Marketplace --ref requires one value.',
            );
          }
          refName = _validCliValue(arguments[index], 'Marketplace ref');
          break;
        case '--sparse':
          if (++index >= arguments.length) {
            throw const FormatException(
              'Marketplace --sparse requires one value.',
            );
          }
          sparsePaths.add(_validCliValue(arguments[index], 'Sparse path'));
          break;
        default:
          throw FormatException(
            'Unsupported marketplace add option: ${arguments[index]}.',
          );
      }
    }
    return CodexPluginMarketplaceAddRequest(
      source: source,
      refName: refName,
      sparsePaths: List<String>.unmodifiable(sparsePaths),
      jsonOutput: jsonOutput,
    );
  }
}

class CodexPluginMarketplaceRemoveRequest {
  const CodexPluginMarketplaceRemoveRequest({
    required this.marketplaceName,
    required this.jsonOutput,
  });

  final String marketplaceName;
  final bool jsonOutput;

  static CodexPluginMarketplaceRemoveRequest parse(List<String> arguments) {
    final parsed = _parseMarketplaceName(arguments, operation: 'remove');
    return CodexPluginMarketplaceRemoveRequest(
      marketplaceName: parsed.name,
      jsonOutput: parsed.json,
    );
  }
}

class CodexPluginMarketplaceUpgradeRequest {
  const CodexPluginMarketplaceUpgradeRequest({
    this.marketplaceName,
    required this.jsonOutput,
  });

  final String? marketplaceName;
  final bool jsonOutput;

  static CodexPluginMarketplaceUpgradeRequest parse(List<String> arguments) {
    if (arguments.length < 3 ||
        arguments[0].toLowerCase() != 'plugin' ||
        arguments[1].toLowerCase() != 'marketplace' ||
        arguments[2].toLowerCase() != 'upgrade') {
      throw const FormatException(
        'Usage: plugin marketplace upgrade [name] [--json].',
      );
    }
    String? name;
    var jsonOutput = false;
    for (var index = 3; index < arguments.length; index++) {
      final value = arguments[index];
      if (value == '--json') {
        jsonOutput = true;
      } else if (value.startsWith('-') || name != null) {
        throw const FormatException(
          'Only one marketplace name and --json are accepted.',
        );
      } else {
        name = _validCliValue(value, 'Marketplace name');
      }
    }
    return CodexPluginMarketplaceUpgradeRequest(
      marketplaceName: name,
      jsonOutput: jsonOutput,
    );
  }
}

({String name, bool json}) _parseMarketplaceName(
  List<String> arguments, {
  required String operation,
}) {
  if (arguments.length < 4 ||
      arguments[0].toLowerCase() != 'plugin' ||
      arguments[1].toLowerCase() != 'marketplace' ||
      arguments[2].toLowerCase() != operation) {
    throw FormatException(
      'Usage: plugin marketplace $operation <name> [--json].',
    );
  }
  String? name;
  var jsonOutput = false;
  for (var index = 3; index < arguments.length; index++) {
    final value = arguments[index];
    if (value == '--json') {
      jsonOutput = true;
    } else if (value.startsWith('-') || name != null) {
      throw const FormatException(
        'Only one marketplace name and --json are accepted.',
      );
    } else {
      name = _validCliValue(value, 'Marketplace name');
    }
  }
  if (name == null)
    throw const FormatException('Marketplace name is required.');
  return (name: name, json: jsonOutput);
}

T _parsePluginMutation<T>(
  List<String> arguments, {
  required String operation,
  required String errorUsage,
  required T Function(String plugin, String marketplace, bool jsonOutput)
  builder,
}) {
  if (arguments.length < 3 ||
      arguments[0].toLowerCase() != 'plugin' ||
      arguments[1].toLowerCase() != operation) {
    throw FormatException(errorUsage);
  }
  String? selector;
  String? marketplace;
  var jsonOutput = false;
  for (var index = 2; index < arguments.length; index++) {
    final value = arguments[index];
    if (value == '--json') {
      jsonOutput = true;
    } else if (value == '--marketplace') {
      if (marketplace != null || ++index >= arguments.length) {
        throw const FormatException('--marketplace requires one value.');
      }
      marketplace = _validCliValue(arguments[index], 'Marketplace name');
    } else if (value.startsWith('-') || selector != null) {
      throw FormatException('Unsupported plugin $operation option: $value.');
    } else {
      selector = value;
    }
  }
  final rawSelector = selector?.trim() ?? '';
  if (rawSelector.isEmpty) throw FormatException(errorUsage);
  final at = rawSelector.lastIndexOf('@');
  final hasEmbeddedMarketplace = at > 0 && at < rawSelector.length - 1;
  final plugin = hasEmbeddedMarketplace
      ? rawSelector.substring(0, at)
      : rawSelector;
  final embeddedMarketplace = hasEmbeddedMarketplace
      ? rawSelector.substring(at + 1)
      : null;
  final effectiveMarketplace = marketplace ?? embeddedMarketplace;
  if (effectiveMarketplace == null ||
      !_validPluginSegment(plugin) ||
      !_validPluginSegment(effectiveMarketplace)) {
    throw const FormatException(
      'Plugin selector must use <plugin>@<marketplace> or --marketplace <name>.',
    );
  }
  if (marketplace != null &&
      embeddedMarketplace != null &&
      marketplace != embeddedMarketplace) {
    throw const FormatException(
      'Plugin selector marketplace conflicts with --marketplace.',
    );
  }
  return builder(plugin, effectiveMarketplace, jsonOutput);
}

String _validCliValue(String value, String label) {
  final normalized = value.trim();
  if (normalized.isEmpty || normalized.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
    throw FormatException('$label is invalid.');
  }
  return normalized;
}

bool _validPluginSegment(String value) =>
    value.isNotEmpty && !value.contains(RegExp(r'[\x00-\x1f\x7f/\\]'));

bool _validPluginId(String value) {
  final at = value.lastIndexOf('@');
  return at > 0 &&
      at < value.length - 1 &&
      _validPluginSegment(value.substring(0, at)) &&
      _validPluginSegment(value.substring(at + 1));
}

class CodexMcpLoginRequest {
  const CodexMcpLoginRequest({required this.name});

  final String name;

  factory CodexMcpLoginRequest.parse(List<String> arguments) {
    if (arguments.length != 3 ||
        arguments[0].toLowerCase() != 'mcp' ||
        arguments[1].toLowerCase() != 'login') {
      throw const FormatException('Usage: mcp login <server-name>.');
    }
    final name = arguments[2].trim();
    if (name.isEmpty || name.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('MCP server name is invalid.');
    }
    return CodexMcpLoginRequest(name: name);
  }
}

class CodexMcpLogoutRequest {
  const CodexMcpLogoutRequest({required this.name});

  final String name;

  factory CodexMcpLogoutRequest.parse(List<String> arguments) {
    if (arguments.length != 3 ||
        arguments[0].toLowerCase() != 'mcp' ||
        arguments[1].toLowerCase() != 'logout') {
      throw const FormatException('Usage: mcp logout <server-name>.');
    }
    final name = arguments[2].trim();
    if (name.isEmpty || name.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('MCP server name is invalid.');
    }
    return CodexMcpLogoutRequest(name: name);
  }
}

class CodexMcpAddRequest {
  const CodexMcpAddRequest({required this.name, required this.config});

  final String name;
  final Map<String, Object?> config;

  factory CodexMcpAddRequest.parse(List<String> arguments) {
    if (arguments.length < 4 ||
        arguments[0].toLowerCase() != 'mcp' ||
        arguments[1].toLowerCase() != 'add') {
      throw const FormatException(
        'Usage: mcp add <name> (-- <command>... | --url <url>).',
      );
    }
    final name = arguments[2];
    if (name.trim().isEmpty || name.contains(RegExp(r'[\x00-\x1f\x7f]'))) {
      throw const FormatException('MCP server name is invalid.');
    }

    final separator = arguments.indexOf('--', 3);
    if (separator >= 0) {
      final environment = <String, String>{};
      var index = 3;
      while (index < separator) {
        if (arguments[index] != '--env' || index + 1 >= separator) {
          throw const FormatException(
            'Only repeated --env KEY=VALUE options may precede -- for a stdio server.',
          );
        }
        final pair = arguments[index + 1];
        final equals = pair.indexOf('=');
        if (equals <= 0) {
          throw const FormatException(
            'MCP environment entries must use KEY=VALUE.',
          );
        }
        final key = pair.substring(0, equals);
        if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(key)) {
          throw const FormatException(
            'MCP environment variable name is invalid.',
          );
        }
        if (environment.containsKey(key)) {
          throw const FormatException(
            'MCP environment variable names must be unique.',
          );
        }
        environment[key] = pair.substring(equals + 1);
        index += 2;
      }
      final command = arguments.skip(separator + 1).toList(growable: false);
      if (command.isEmpty || command.first.isEmpty) {
        throw const FormatException(
          'A stdio MCP launch command is required after --.',
        );
      }
      return CodexMcpAddRequest(
        name: name,
        config: <String, Object?>{
          'command': command.first,
          'args': command.skip(1).toList(growable: false),
          if (environment.isNotEmpty) 'env': environment,
        },
      );
    }

    String? url;
    String? bearerTokenEnvVar;
    var index = 3;
    while (index < arguments.length) {
      final option = arguments[index++];
      if (index >= arguments.length) {
        throw FormatException('Missing value for $option.');
      }
      final value = arguments[index++];
      switch (option) {
        case '--url':
          if (url != null) {
            throw const FormatException('Only one --url is allowed.');
          }
          url = value;
        case '--bearer-token-env-var':
          if (bearerTokenEnvVar != null) {
            throw const FormatException(
              'Only one bearer token environment variable is allowed.',
            );
          }
          if (!RegExp(r'^[A-Za-z_][A-Za-z0-9_]*$').hasMatch(value)) {
            throw const FormatException(
              'Bearer token environment variable name is invalid.',
            );
          }
          bearerTokenEnvVar = value;
        default:
          throw FormatException('Unsupported MCP add option: $option.');
      }
    }
    final parsedUrl = Uri.tryParse(url ?? '');
    if (parsedUrl == null ||
        !parsedUrl.hasAuthority ||
        !const <String>{
          'https',
          'http',
        }.contains(parsedUrl.scheme.toLowerCase()) ||
        parsedUrl.host.isEmpty ||
        parsedUrl.userInfo.isNotEmpty ||
        parsedUrl.hasFragment) {
      throw const FormatException(
        'A valid HTTP(S) MCP server URL is required.',
      );
    }
    final config = <String, Object?>{'url': url};
    if (bearerTokenEnvVar case final tokenVariable?) {
      config['bearer_token_env_var'] = tokenVariable;
    }
    return CodexMcpAddRequest(name: name, config: config);
  }
}

/// Adds per-session Codex state overrides to a CLI argv vector.
///
/// A copied config.toml can contain absolute sqlite_home/log_dir values. Those
/// values take precedence over CODEX_SQLITE_HOME/CODEX_HOME, so every scoped
/// Android invocation must override them at the CLI layer as well.
List<String> codexArgumentsWithSessionIsolation(
  List<String> argv,
  Map<String, String> environment,
) {
  final sqliteHome = environment['CODEX_SQLITE_HOME']?.trim();
  final codexHome = environment['CODEX_HOME']?.trim();
  if (sqliteHome == null ||
      sqliteHome.isEmpty ||
      codexHome == null ||
      codexHome.isEmpty ||
      argv.isEmpty) {
    return List<String>.from(argv);
  }

  final overrides = <String>[
    '-c',
    'sqlite_home=${jsonEncode(sqliteHome)}',
    '-c',
    'log_dir=${jsonEncode('$codexHome/log')}',
  ];
  final subcommandIndex = argv.indexOf('app-server');
  final insertAt = subcommandIndex > 0
      ? subcommandIndex
      : argv.length > 1
      ? 1
      : argv.length;
  return <String>[...argv]..insertAll(insertAt, overrides);
}
