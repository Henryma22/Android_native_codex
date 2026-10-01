import 'package:flutter/foundation.dart';

/// Small presentation-only logger replacing CC Pocket's app-wide Talker.
class LocalUiLogger {
  const LocalUiLogger();

  void info(Object? message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('$message');
  }

  void warning(Object? message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('$message');
  }

  void error(Object? message, [Object? error, StackTrace? stackTrace]) {
    debugPrint('$message');
  }
}

const logger = LocalUiLogger();