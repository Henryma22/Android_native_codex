import 'dart:async';

import 'package:flutter/services.dart';

import '../backends/compatibility/linux_compatibility_backend.dart';
import '../core/domain/backend.dart';
import '../core/domain/execution.dart';

/// Native probe and process boundary for the optional Android PRoot/rootfs
/// worker.
class AndroidCompatibilityRuntimeClient implements CompatibilityRuntimeClient {
  AndroidCompatibilityRuntimeClient({
    MethodChannel? channel,
    EventChannel? events,
  }) : _channel = channel ?? _defaultChannel,
       _events = events ?? _defaultEvents;

  static const _defaultChannel = MethodChannel(
    'io.henry.codex/linux_compatibility_runtime',
  );
  static const _defaultEvents = EventChannel(
    'io.henry.codex/linux_compatibility_events',
  );

  final MethodChannel _channel;
  final EventChannel _events;
  final Map<String, StreamController<ExecutionEvent>> _executions = {};
  StreamSubscription<Object?>? _eventSubscription;
  CompatibilityRuntimeDescriptor _descriptor =
      const CompatibilityRuntimeDescriptor.missing(
        reason: 'Linux compatibility runtime probe has not run.',
      );

  @override
  CompatibilityRuntimeDescriptor get descriptor => _descriptor;

  @override
  void acceptProbeResult(CompatibilityRuntimeDescriptor descriptor) {
    _descriptor = descriptor;
  }

  @override
  Future<CompatibilityRuntimeDescriptor> probe() async {
    try {
      final value = await _channel.invokeMethod<Object?>('probe');
      if (value is! Map) {
        return _setFailed('Native compatibility probe returned invalid data.');
      }
      final state = _parseState(value['state']);
      final version = _optionalString(value['version']);
      final digest = _optionalString(value['rootfsDigest']);
      final reason = _optionalString(value['reason']);
      final maintenanceCwd = _optionalString(value['maintenanceCwd']);
      _descriptor = CompatibilityRuntimeDescriptor(
        state: state,
        version: version,
        rootfsDigest: digest,
        reason: reason,
        maintenanceCwd: maintenanceCwd,
      );
      return _descriptor;
    } on MissingPluginException {
      return _setMissing('Native compatibility runtime is not available.');
    } on PlatformException catch (error) {
      return _setFailed(error.message ?? 'Native compatibility probe failed.');
    } catch (error) {
      return _setFailed('Native compatibility probe failed: $error');
    }
  }

  @override
  String mapHostPath(String hostPath) {
    // The native worker receives the canonical host path and binds only that
    // selected directory to the guest's /workspace. Keeping the host path in
    // the request lets native code repeat the same allowlist check.
    return hostPath;
  }

  @override
  Stream<ExecutionEvent> execute(ExecutionRequest request) =>
      startInteractive(request).events;

  @override
  InteractiveExecution startInteractive(ExecutionRequest request) {
    if (!_descriptor.usable) {
      throw BackendException(
        _descriptor.reason ?? 'Linux compatibility runtime is not verified; execution is disabled.',
      );
    }
    _ensureEventSubscription();
    final controller = StreamController<ExecutionEvent>();
    String? processId;
    var cancelled = false;
    final started = Completer<String>();
    Future<void>? stopInFlight;

    Future<void> stopOperation() async {
      cancelled = true;
      final id = processId;
      try {
        if (id != null) {
          _executions.remove(id);
          await _channel.invokeMethod<void>('stopProcess', <String, Object?>{
            'processId': id,
          });
        }
      } on PlatformException catch (error) {
        throw BackendException('${error.code}: ${error.message ?? error.code}');
      } finally {
        if (!controller.isClosed) await controller.close();
      }
    }

    Future<void> stop() {
      final existing = stopInFlight;
      if (existing != null) return existing;
      final operation = stopOperation();
      stopInFlight = operation;
      return operation;
    }

    // The stream subscription belongs to the current UI/protocol observer,
    // not to the process lifetime. A session can be hidden or reattached
    // without stopping its PRoot worker; explicit process owners call stop().
    _startExecution(
      request,
      controller,
      () => cancelled,
      (id) {
        processId = id;
        if (!started.isCompleted) started.complete(id);
      },
      started,
      stop,
    );
    return _CompatibilityInteractiveExecution(
      events: controller.stream,
      write: (value) async {
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        final id = processId ?? await started.future;
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        try {
          await _channel.invokeMethod<void>('writeProcess', <String, Object?>{
            'processId': id,
            'value': value,
          });
        } on PlatformException catch (error) {
          throw BackendException(
            '${error.code}: ${error.message ?? error.code}',
          );
        }
      },
      closeStdin: () async {
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        final id = processId ?? await started.future;
        if (cancelled) {
          throw const BackendException('execution has been cancelled.');
        }
        try {
          await _channel.invokeMethod<void>(
            'closeProcessStdin',
            <String, Object?>{'processId': id},
          );
        } on PlatformException catch (error) {
          throw BackendException(
            '${error.code}: ${error.message ?? error.code}',
          );
        }
      },
      stop: stop,
    );
  }

  Future<void> _startExecution(
    ExecutionRequest request,
    StreamController<ExecutionEvent> controller,
    bool Function() isCancelled,
    void Function(String id) setProcessId,
    Completer<String> started,
    Future<void> Function() stop,
  ) async {
    String? processId;
    try {
      final id = await _channel.invokeMethod<String>(
        'startProcess',
        <String, Object?>{
          'argv': request.argv,
          'cwd': request.cwd,
          'identity': request.identity.name,
          'timeoutMs': request.timeout.inMilliseconds,
          'environment': request.environment,
        },
      );
      if (id == null) {
        throw const BackendException(
          'Native compatibility worker returned no process id.',
        );
      }
      processId = id;
      setProcessId(id);
      if (isCancelled()) {
        await stop();
        if (!controller.isClosed) await controller.close();
        return;
      }
      _executions[id] = controller;
      await _channel.invokeMethod<void>('attachProcess', <String, Object?>{
        'processId': id,
      });
    } catch (error, stackTrace) {
      if (processId != null) {
        _executions.remove(processId);
        await stop();
      }
      if (!started.isCompleted) {
        started.completeError(_backendError(error), stackTrace);
      }
      if (!controller.isClosed) {
        controller.addError(_backendError(error), stackTrace);
        await controller.close();
      }
    }
  }

  void _ensureEventSubscription() {
    _eventSubscription ??= _events.receiveBroadcastStream().listen(
      _handleEvent,
      onError: (Object error, StackTrace stackTrace) {
        for (final controller in _executions.values.toList()) {
          if (!controller.isClosed) controller.addError(error, stackTrace);
        }
      },
    );
  }

  void _handleEvent(Object? raw) {
    if (raw is! Map<Object?, Object?>) return;
    final processId = raw['processId'] as String?;
    final type = raw['type'] as String?;
    final controller = processId == null ? null : _executions[processId];
    if (controller == null || type == null || controller.isClosed) return;
    switch (type) {
      case 'stdout':
        controller.add(ExecutionEvent.stdout(raw['value'] as String? ?? ''));
      case 'stderr':
        controller.add(ExecutionEvent.stderr(raw['value'] as String? ?? ''));
      case 'error':
        controller.add(ExecutionEvent.error(raw['value'] as String? ?? ''));
      case 'exit':
        controller.add(
          ExecutionEvent.exit((raw['exitCode'] as num?)?.toInt() ?? -1),
        );
        _executions.remove(processId);
        unawaited(controller.close());
    }
  }

  BackendException _backendError(Object error) {
    if (error is PlatformException) {
      return BackendException('${error.code}: ${error.message ?? error.code}');
    }
    if (error is BackendException) return error;
    return BackendException('$error');
  }

  CompatibilityRuntimeDescriptor _setMissing(String reason) {
    _descriptor = CompatibilityRuntimeDescriptor.missing(reason: reason);
    return _descriptor;
  }

  CompatibilityRuntimeDescriptor _setFailed(String reason) {
    _descriptor = CompatibilityRuntimeDescriptor(
      state: CompatibilityRuntimeState.failed,
      version: null,
      reason: reason,
    );
    return _descriptor;
  }

  static CompatibilityRuntimeState _parseState(Object? raw) {
    switch (raw) {
      case 'available':
        return CompatibilityRuntimeState.available;
      case 'verified':
        return CompatibilityRuntimeState.verified;
      case 'failed':
        return CompatibilityRuntimeState.failed;
      case 'missing':
      default:
        return CompatibilityRuntimeState.missing;
    }
  }

  static String? _optionalString(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}

class _CompatibilityInteractiveExecution
    implements InteractiveExecution, StdinClosableExecution {
  const _CompatibilityInteractiveExecution({
    required this.events,
    required Future<void> Function(String value) write,
    required Future<void> Function() closeStdin,
    required Future<void> Function() stop,
  }) : _write = write,
       _closeStdin = closeStdin,
       _stop = stop;

  @override
  final Stream<ExecutionEvent> events;

  final Future<void> Function(String value) _write;
  final Future<void> Function() _closeStdin;
  final Future<void> Function() _stop;

  @override
  Future<void> write(String value) => _write(value);

  @override
  Future<void> closeStdin() => _closeStdin();

  @override
  Future<void> stop() => _stop();
}
