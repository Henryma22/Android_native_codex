import 'package:flutter/material.dart';

/// API-compatible presentation fallback for CC Pocket's optional editor
/// highlighter. The markdown layer still uses its original `highlight`
/// fallback, so this package adds no native clipboard/runtime dependency.
class Highlighter {
  Highlighter({required this.language, required this.theme});

  final String language;
  final HighlighterTheme theme;

  static Future<void> initialize(Iterable<String> languages) async {}

  TextSpan highlight(String source) => TextSpan(text: source);
}

class HighlighterTheme {
  const HighlighterTheme._();

  static Future<HighlighterTheme> loadLightTheme() async =>
      const HighlighterTheme._();

  static Future<HighlighterTheme> loadDarkTheme() async =>
      const HighlighterTheme._();
}
