import 'package:flutter/material.dart';

const defaultCodeFontSize = 12.0;
const minCodeFontSize = 8.0;
const maxCodeFontSize = 24.0;
const codeLineHeight = 1.45;

class CodeTextSettings {
  const CodeTextSettings({this.fontSize = defaultCodeFontSize});

  final double fontSize;
  String get family => 'monospace';

  TextStyle style({
    Color? color,
    double? fontSize,
    double height = codeLineHeight,
    FontWeight? fontWeight,
    Color? backgroundColor,
  }) {
    return TextStyle(
      fontFamily: 'monospace',
      fontSize: fontSize ?? this.fontSize,
      height: height,
      fontWeight: fontWeight,
      color: color,
      backgroundColor: backgroundColor,
    );
  }
}

CodeTextSettings codeTextSettingsOf(BuildContext context) =>
    const CodeTextSettings();