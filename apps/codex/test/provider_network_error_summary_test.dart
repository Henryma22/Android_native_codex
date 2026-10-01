import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/provider_network_error_summary.dart';

void main() {
  test('localizes TLS handshake failures without copying raw diagnostics', () {
    final summary = ProviderNetworkErrorSummary.message(
      diagnostic: 'failed to connect to websocket: IO error: tls handshake eof sk-secret-token',
      languageCode: 'zh',
    );

    expect(summary, contains('TLS/证书握手失败'));
    expect(summary, isNot(contains('sk-secret-token')));
  });

  test('distinguishes DNS, timeout, and refused connections', () {
    expect(
      ProviderNetworkErrorSummary.message(
        diagnostic: 'temporary failure in name resolution',
        languageCode: 'zh',
      ),
      contains('DNS 解析失败'),
    );
    expect(
      ProviderNetworkErrorSummary.message(
        diagnostic: 'request timed out connecting to host',
        languageCode: 'en',
      ),
      contains('connection timed out'),
    );
    expect(
      ProviderNetworkErrorSummary.message(
        diagnostic: 'connection refused',
        languageCode: 'ja',
      ),
      contains('接続拒否'),
    );
  });

  test('preserves the generic localized message when detail is absent', () {
    expect(
      ProviderNetworkErrorSummary.message(diagnostic: null, languageCode: 'zh'),
      '网络连接失败。请检查 Android Wi-Fi、移动数据、VPN 或代理设置后重试。本地会话仍可继续。',
    );
  });
}
