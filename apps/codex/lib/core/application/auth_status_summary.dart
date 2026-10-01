String summarizeAuthStatus({required String output, required int? exitCode}) {
  final normalized = output.toLowerCase();
  if (normalized.contains('not logged in')) return 'Not logged in';
  if (normalized.contains('logged in')) return 'Logged in';
  if (exitCode != 0) return 'Failed to check login status.';
  return 'Login status checked (details redacted)';
}

/// Returns the credential family reported by `codex login status` without
/// forwarding the command's potentially sensitive output to the UI.
String? summarizeAuthMode({required String output}) {
  final normalized = output.toLowerCase();
  if (normalized.contains('logged in using an api key') ||
      normalized.contains('logged in using api key')) {
    return 'api-key';
  }
  if (normalized.contains('logged in using chatgpt')) return 'chatgpt';
  return null;
}

String summarizeAuthLogout({required int? exitCode}) {
  return exitCode == 0 ? 'Logged out' : 'Failed to log out.';
}
