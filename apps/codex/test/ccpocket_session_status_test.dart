import 'package:ccpocket_ui/widgets/session_visual_status.dart';
import 'package:ccpocket_ui/models/messages.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('preserves reconnect and disconnected session states in Home cards', () {
    final reconnecting = sessionVisualStatusFor(rawStatus: 'reconnecting');
    final disconnected = sessionVisualStatusFor(rawStatus: 'disconnected');
    final failed = sessionVisualStatusFor(rawStatus: 'failed');

    expect(reconnecting.primary, SessionPrimaryStatus.working);
    expect(reconnecting.label, 'Reconnecting');
    expect(reconnecting.animate, isTrue);
    expect(disconnected.primary, SessionPrimaryStatus.disconnected);
    expect(disconnected.detail, 'Reconnect');
    expect(failed.primary, SessionPrimaryStatus.failed);
    expect(failed.detail, 'Retry');
  });

  test('keeps approval state ahead of the raw runtime state', () {
    final status = sessionVisualStatusFor(
      rawStatus: 'running',
      pendingPermission: const PermissionRequestMessage(
        toolUseId: 'tool-1',
        toolName: 'Bash',
        input: <String, dynamic>{},
      ),
    );

    expect(status.primary, SessionPrimaryStatus.needsYou);
    expect(status.label, 'Needs You');
    expect(status.detail, 'Approve Bash');
  });
}
