import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/codex_plugin_summary.dart';

void main() {
  test('preserves empty marketplaces and sanitizes display metadata', () {
    final marketplaces = CodexPluginMarketplaceSummary.parseResponse(
      <String, dynamic>{
        'marketplaces': <Object?>[
          <String, Object?>{
            'name': 'official\nmarket',
            'interface': <String, Object?>{'displayName': 'Official\tTools'},
            'plugins': const <Object?>[],
            'error': 'bad\rsource',
          },
          <String, Object?>{
            'name': 'local',
            'plugins': <Object?>[
              <String, Object?>{'id': 'one'},
              <String, Object?>{'id': 'two'},
            ],
          },
        ],
      },
    );

    expect(marketplaces, hasLength(2));
    expect(marketplaces.first.name, 'official market');
    expect(marketplaces.first.title, 'Official Tools');
    expect(marketplaces.first.pluginCount, 0);
    expect(marketplaces.first.loadError, 'bad source');
    expect(marketplaces.last.pluginCount, 2);
  });

  test('rejects a malformed marketplace identity', () {
    expect(
      () => CodexPluginMarketplaceSummary.parseResponse(<String, dynamic>{
        'marketplaces': <Object?>[
          <String, Object?>{'plugins': const <Object?>[]},
        ],
      }),
      throwsFormatException,
    );
  });
}
