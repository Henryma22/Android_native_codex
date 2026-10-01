import 'dart:async';

import 'package:flutter/services.dart';

import '../core/domain/runtime.dart';

class CodexRuntimeProbe {
  static const _channel = MethodChannel('io.henry.codex/native_probe');

  Future<CodexRuntimeDescriptor> run() async {
    try {
      final raw = await _channel
          .invokeMethod<Object?>('probeCodexRuntime')
          .timeout(const Duration(seconds: 8));
      if (raw is Map<Object?, Object?>) {
        return CodexRuntimeDescriptor.fromMap(raw);
      }
      return const CodexRuntimeDescriptor(
        state: CodexRuntimeState.failed,
        reason: 'Native Codex runtime probe returned an invalid result.',
      );
    } on MissingPluginException {
      return const CodexRuntimeDescriptor(
        state: CodexRuntimeState.missing,
        reason: 'Native Codex runtime probe is not available on this platform.',
      );
    } on TimeoutException {
      return const CodexRuntimeDescriptor(
        state: CodexRuntimeState.failed,
        reason: 'Native Codex runtime probe timed out.',
      );
    } on PlatformException catch (error) {
      return CodexRuntimeDescriptor(
        state: CodexRuntimeState.failed,
        reason: error.message ?? error.code,
      );
    }
  }
}
