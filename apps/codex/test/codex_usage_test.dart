import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_usage.dart';

void main() {
  test('maps Codex primary and secondary windows by duration', () {
    final snapshot = CodexUsageSnapshot.fromRpcResponse(<String, dynamic>{
      'rateLimits': <String, dynamic>{
        'limitId': 'codex',
        'primary': <String, dynamic>{
          'usedPercent': 37,
          'windowDurationMins': 10080,
          'resetsAt': 1_900_000_000,
        },
        'secondary': <String, dynamic>{
          'usedPercent': 12.5,
          'windowDurationMins': 300,
          'resetsAt': 1_800_000_000,
        },
      },
    });

    expect(snapshot.fiveHour?.usedPercent, 12.5);
    expect(snapshot.sevenDay?.usedPercent, 37);
    expect(snapshot.fiveHour?.remainingPercent, 87.5);
  });

  test('prefers the account-wide codex entry from rateLimitsByLimitId', () {
    final snapshot = CodexUsageSnapshot.fromRpcResponse(<String, dynamic>{
      'rateLimits': <String, dynamic>{
        'primary': <String, dynamic>{
          'usedPercent': 99,
          'windowDurationMins': 300,
        },
      },
      'rateLimitsByLimitId': <String, dynamic>{
        'codex': <String, dynamic>{
          'primary': <String, dynamic>{
            'usedPercent': 4,
            'windowDurationMins': 300,
          },
        },
      },
    });

    expect(snapshot.fiveHour?.usedPercent, 4);
  });

  test('rejects a response without supported windows', () {
    expect(
      () => CodexUsageSnapshot.fromRpcResponse(<String, dynamic>{
        'rateLimits': <String, dynamic>{
          'primary': <String, dynamic>{
            'usedPercent': 10,
            'windowDurationMins': 60,
          },
        },
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
