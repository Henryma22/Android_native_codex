import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/domain/transcript.dart';
import 'package:codex/main.dart';

void main() {
  const quotaFailure =
      "You've hit your usage limit. Upgrade to Pro (https://chatgpt.com/explore/pro), "
      'visit https://chatgpt.com/codex/settings/usage to purchase more credits.';

  test('localizes provider usage limits without leaking raw service copy', () {
    final localized = localizeCodexRuntimeFailure(
      quotaFailure,
      languageCode: 'zh',
    );

    expect(localized, '已达到 Codex 使用额度上限。请等待额度恢复，或升级 Pro/购买额外额度后重试。');
    expect(localized, isNot(contains("You've hit your usage limit")));
    expect(localized, isNot(contains('chatgpt.com')));
  });

  test(
    'keeps a localized usage-limit message available for supported locales',
    () {
      expect(
        localizeCodexRuntimeFailure(quotaFailure, languageCode: 'ja'),
        contains('利用上限'),
      );
      expect(
        localizeCodexRuntimeFailure(quotaFailure, languageCode: 'ko'),
        contains('사용 한도'),
      );
      expect(
        localizeCodexRuntimeFailure(quotaFailure, languageCode: 'en'),
        contains('usage limit reached'),
      );
    },
  );

  test('preserves existing localized runtime diagnostics', () {
    expect(
      localizeCodexRuntimeFailure(
        'Linux compatibility runtime is not verified.',
        languageCode: 'zh',
      ),
      'Linux 兼容运行环境尚未验证。',
    );
  });

  test('localizes JSON transcript errors without rewriting stored history', () {
    const rawMessage =
        'You\u2019ve hit your usage limit. Upgrade to Pro '
        '(https://chatgpt.com/explore/pro), visit '
        'https://chatgpt.com/codex/settings/usage to purchase more credits.';
    final stored = CodexTranscriptEntry(
      id: 'quota-1',
      kind: CodexTranscriptKind.error,
      text: rawMessage,
      timestamp: DateTime(2026, 9, 30),
    ).toStored();

    final display = localizeCodexTranscriptEntry(stored, languageCode: 'zh');

    expect(display, isNot(stored));
    expect(display, contains('已达到 Codex 使用额度上限'));
    expect(display, isNot(contains('chatgpt.com')));
    expect(stored, contains('chatgpt.com'));
  });
}
