import 'package:flutter_test/flutter_test.dart';

import 'package:codex/core/application/auth_status_summary.dart';

void main() {
  test('recognizes not logged in from stderr with a non-zero exit', () {
    expect(
      summarizeAuthStatus(output: 'Not logged in\n', exitCode: 1),
      'Not logged in',
    );
  });

  test('recognizes logged in without exposing command output', () {
    expect(
      summarizeAuthStatus(
        output: 'Logged in\naccount@example.com\nsecret-token',
        exitCode: 0,
      ),
      'Logged in',
    );
  });

  test('redacts unknown output and reports an unexpected failure', () {
    expect(
      summarizeAuthStatus(output: 'token=secret', exitCode: 1),
      'Failed to check login status.',
    );
  });

  test('recognizes the API-key credential family without exposing the key', () {
    expect(
      summarizeAuthMode(output: 'Logged in using an API key - sk-secret\n'),
      'api-key',
    );
  });

  test('recognizes the ChatGPT credential family', () {
    expect(summarizeAuthMode(output: 'Logged in using ChatGPT\n'), 'chatgpt');
  });

  test('summarizes logout by exit code without exposing CLI output', () {
    expect(summarizeAuthLogout(exitCode: 0), 'Logged out');
    expect(summarizeAuthLogout(exitCode: 1), 'Failed to log out.');
    expect(summarizeAuthLogout(exitCode: null), 'Failed to log out.');
  });
}
