/// Produces a useful, credential-free explanation for a Codex transport
/// failure without exposing raw app-server diagnostics in the conversation.
class ProviderNetworkErrorSummary {
  static String message({
    required String? diagnostic,
    required String languageCode,
  }) {
    final cause = _localizedCause(diagnostic, languageCode);
    return switch (languageCode) {
      'zh' =>
        '网络连接失败${cause == null ? '' : '（$cause）'}。请检查 Android Wi-Fi、移动数据、VPN 或代理设置后重试。本地会话仍可继续。',
      'ja' =>
        'ネットワーク接続に失敗しました${cause == null ? '' : '（$cause）'}。Android の Wi-Fi、モバイルデータ、VPN、プロキシ設定を確認して再試行してください。ローカルセッションは引き続き利用できます。',
      'ko' =>
        '네트워크 연결에 실패했습니다${cause == null ? '' : '($cause)'}. Android Wi-Fi, 모바일 데이터, VPN 또는 프록시 설정을 확인하고 다시 시도하세요. 로컬 세션은 계속 사용할 수 있습니다.',
      _ =>
        'Provider network connection failed${cause == null ? '' : ' ($cause)'}. Check Android Wi-Fi, mobile data, VPN, or proxy settings and retry. The local session remains available.',
    };
  }

  static String? _localizedCause(String? diagnostic, String languageCode) {
    final normalized = (diagnostic ?? '').toLowerCase();
    if (normalized.isEmpty) return null;
    final cause = switch (true) {
      _
          when normalized.contains('tls handshake') ||
              normalized.contains('certificate verify') ||
              normalized.contains('invalid peer certificate') =>
        'tls',
      _
          when normalized.contains('failed to lookup') ||
              normalized.contains('name or service not known') ||
              normalized.contains('temporary failure in name resolution') ||
              normalized.contains('eai_again') =>
        'dns',
      _
          when normalized.contains('timed out') ||
              normalized.contains('timeout') =>
        'timeout',
      _ when normalized.contains('connection refused') => 'refused',
      _
          when normalized.contains('connection reset') ||
              normalized.contains('stream disconnected before completion') =>
        'reset',
      _ when normalized.contains('network is unreachable') => 'unreachable',
      _ when normalized.contains('failed to connect to websocket') =>
        'websocket',
      _ => null,
    };
    return switch ((languageCode, cause)) {
      ('zh', 'tls') => 'TLS/证书握手失败',
      ('zh', 'dns') => 'DNS 解析失败',
      ('zh', 'timeout') => '连接超时',
      ('zh', 'refused') => '目标服务拒绝连接',
      ('zh', 'reset') => '连接被对端重置',
      ('zh', 'unreachable') => '网络不可达',
      ('zh', 'websocket') => 'WebSocket 建连失败',
      ('ja', 'tls') => 'TLS/証明書ハンドシェイク失敗',
      ('ja', 'dns') => 'DNS 名前解決失敗',
      ('ja', 'timeout') => '接続タイムアウト',
      ('ja', 'refused') => '接続拒否',
      ('ja', 'reset') => '接続リセット',
      ('ja', 'unreachable') => 'ネットワーク到達不能',
      ('ja', 'websocket') => 'WebSocket 接続失敗',
      ('ko', 'tls') => 'TLS/인증서 핸드셰이크 실패',
      ('ko', 'dns') => 'DNS 조회 실패',
      ('ko', 'timeout') => '연결 시간 초과',
      ('ko', 'refused') => '연결 거부',
      ('ko', 'reset') => '연결 재설정',
      ('ko', 'unreachable') => '네트워크에 연결할 수 없음',
      ('ko', 'websocket') => 'WebSocket 연결 실패',
      (_, 'tls') => 'TLS/certificate handshake failed',
      (_, 'dns') => 'DNS lookup failed',
      (_, 'timeout') => 'connection timed out',
      (_, 'refused') => 'connection refused',
      (_, 'reset') => 'connection reset by peer',
      (_, 'unreachable') => 'network unreachable',
      (_, 'websocket') => 'WebSocket connection failed',
      _ => null,
    };
  }
}
