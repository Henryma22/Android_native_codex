import 'package:flutter/material.dart';

import '../models/messages.dart';

/// Visual tokens for the single local Codex provider.
class ProviderStyle {
  final Color foreground;
  final Color background;
  final Color border;
  final IconData icon;

  const ProviderStyle({
    required this.foreground,
    required this.background,
    required this.border,
    required this.icon,
  });
}

ProviderStyle providerStyleFor(BuildContext context, Provider provider) {
  final accent = Theme.of(context).colorScheme.secondary;
  return ProviderStyle(
    foreground: accent,
    background: accent.withValues(alpha: 0.12),
    border: accent.withValues(alpha: 0.34),
    icon: Icons.code,
  );
}

Provider providerFromRaw(String? provider) => Provider.codex;