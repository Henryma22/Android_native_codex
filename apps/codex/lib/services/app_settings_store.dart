import 'package:flutter/services.dart';

/// Persistent app-wide presentation preferences.
///
/// These values belong to the Android shell, not to a Codex thread. Keeping
/// them outside the session history means a theme or locale change applies to
/// Home, Settings, and every resumed session consistently.
class AppSettingsStore {
  static const _channel = MethodChannel('io.henry.codex/app_preferences');

  Future<AppSettingsSnapshot> load() async {
    try {
      final value = await _channel.invokeMethod<Object?>('loadAppSettings');
      if (value is Map) {
        return AppSettingsSnapshot.fromMap(value);
      }
    } on MissingPluginException {
      // Widget tests and non-Android embeddings use the in-memory defaults.
    } on PlatformException {
      // A stale preference must never prevent the local shell from starting.
    }
    return const AppSettingsSnapshot.defaults();
  }

  Future<void> save(AppSettingsSnapshot settings) async {
    try {
      await _channel.invokeMethod<void>('saveAppSettings', settings.toMap());
    } on MissingPluginException {
      // Persistence is unavailable in widget tests.
    } on PlatformException {
      // Presentation preferences are best effort and never block a turn.
    }
  }
}

class AppSettingsSnapshot {
  const AppSettingsSnapshot({
    required this.themeMode,
    required this.locale,
    this.compatibilityCliVersion,
    this.codexModel = 'gpt-6-luna',
    this.codexEffort = 'low',
    this.codexApprovalPolicy = 'never',
    this.codexSandbox = 'danger-full-access',
  });

  const AppSettingsSnapshot.defaults()
    : themeMode = 'system',
      locale = 'zh',
      compatibilityCliVersion = null,
      codexModel = 'gpt-6-luna',
      codexEffort = 'low',
      codexApprovalPolicy = 'never',
      codexSandbox = 'danger-full-access';

  final String themeMode;
  final String locale;
  final String? compatibilityCliVersion;
  final String codexModel;
  final String codexEffort;
  final String codexApprovalPolicy;
  final String codexSandbox;

  factory AppSettingsSnapshot.fromMap(Map<Object?, Object?> value) {
    final theme = value['themeMode'];
    final locale = value['locale'];
    return AppSettingsSnapshot(
      themeMode: _validTheme(theme is String ? theme : null),
      locale: _validLocale(locale is String ? locale : null),
      compatibilityCliVersion: _validCliVersion(
        value['compatibilityCliVersion'] is String
            ? value['compatibilityCliVersion'] as String
            : null,
      ),
      codexModel: _validModel(
        value['codexModel'] is String ? value['codexModel'] as String : null,
      ),
      codexEffort: _validEffort(
        value['codexEffort'] is String ? value['codexEffort'] as String : null,
      ),
      codexApprovalPolicy: _validApprovalPolicy(
        value['codexApprovalPolicy'] is String
            ? value['codexApprovalPolicy'] as String
            : null,
      ),
      codexSandbox: _validSandbox(
        value['codexSandbox'] is String
            ? value['codexSandbox'] as String
            : null,
      ),
    );
  }

  Map<String, String?> toMap() => <String, String?>{
    'themeMode': themeMode,
    'locale': locale,
    'compatibilityCliVersion': compatibilityCliVersion,
    'codexModel': codexModel,
    'codexEffort': codexEffort,
    'codexApprovalPolicy': codexApprovalPolicy,
    'codexSandbox': codexSandbox,
  };

  static String _validTheme(String? value) {
    return switch (value) {
      'system' || 'light' || 'dark' => value!,
      _ => 'system',
    };
  }

  static String _validLocale(String? value) {
    return switch (value) {
      'system' || 'zh' || 'en' => value!,
      _ => 'system',
    };
  }

  static String? _validCliVersion(String? value) {
    final normalized = value?.trim();
    if (normalized == null || normalized.isEmpty) return null;
    return RegExp(r'^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$')
            .hasMatch(normalized)
        ? normalized
        : null;
  }

  static String _validModel(String? value) {
    final normalized = value?.trim();
    return normalized == null || normalized.isEmpty || normalized.length > 256
        ? 'gpt-6-luna'
        : normalized;
  }

  static String _validEffort(String? value) {
    return switch (value) {
      'none' ||
      'minimal' ||
      'low' ||
      'medium' ||
      'high' ||
      'xhigh' ||
      'max' ||
      'ultra' => value!,
      _ => 'low',
    };
  }

  static String _validApprovalPolicy(String? value) {
    return switch (value) {
      'on-request' || 'on-failure' || 'never' => value!,
      _ => 'never',
    };
  }

  static String _validSandbox(String? value) {
    return switch (value) {
      'workspace-write' || 'read-only' || 'danger-full-access' => value!,
      _ => 'danger-full-access',
    };
  }
}
