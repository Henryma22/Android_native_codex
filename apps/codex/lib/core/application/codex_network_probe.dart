import 'dart:convert';

import '../domain/custom_provider.dart';

/// Probes the selected Codex provider from the same Android/PRoot execution
/// identity used by a session. The requests are unauthenticated GETs: they do
/// not send an API key, OAuth token, prompt, or model request.
class CodexNetworkProbe {
  static const _pythonScript = r'''import json, os, ssl, sys
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

def proxy_hint():
    value = os.environ.get("https_proxy") or os.environ.get("HTTPS_PROXY") or os.environ.get("all_proxy") or os.environ.get("ALL_PROXY")
    if not value:
        return None
    try:
        parsed = urlsplit(value)
        return {"scheme": parsed.scheme, "host": parsed.hostname, "port": parsed.port}
    except ValueError:
        return {"scheme": "configured", "host": None, "port": None}

for url in sys.argv[1:]:
    parsed = urlsplit(url)
    host = parsed.hostname or "unknown"
    proxy = proxy_hint()
    try:
        response = urlopen(Request(url, headers={"Accept": "application/json"}), timeout=8)
        result = {"host": host, "scheme": parsed.scheme, "status": response.status, "proxy": proxy}
        response.close()
    except HTTPError as error:
        result = {"host": host, "scheme": parsed.scheme, "status": error.code, "proxy": proxy}
        error.close()
    except (URLError, OSError, ssl.SSLError) as error:
        reason = getattr(error, "reason", error)
        result = {
            "host": host,
            "scheme": parsed.scheme,
            "error": type(reason).__name__,
            "errno": getattr(reason, "errno", None),
            "proxy": proxy,
        }
    except Exception as error:
        result = {"host": host, "scheme": parsed.scheme, "error": type(error).__name__, "proxy": proxy}
    print(json.dumps(result, separators=(",", ":")), flush=True)
''';

  static List<Uri> endpointsFor(CustomProviderConfig? provider) {
    if (provider != null) {
      return <Uri>[Uri.parse(provider.responsesBaseUri.origin)];
    }
    return <Uri>[
      // ChatGPT OAuth sessions use the first-party Codex backend route. Keep
      // this endpoint first so the probe reflects the route used by the
      // current app-server provider rather than only testing the API-key
      // origin below.
      Uri.parse('https://chatgpt.com/backend-api/codex'),
      Uri.parse('https://api.openai.com/v1/models'),
      Uri.parse('https://auth.openai.com/'),
    ];
  }

  static List<String> argumentsFor(Iterable<Uri> endpoints) {
    final urls = endpoints
        .map((endpoint) {
          if (!const <String>{'http', 'https'}.contains(endpoint.scheme) ||
              endpoint.host.isEmpty ||
              endpoint.userInfo.isNotEmpty ||
              endpoint.hasQuery ||
              endpoint.hasFragment) {
            throw const FormatException('Network probe endpoint is invalid.');
          }
          return endpoint.toString();
        })
        .toList(growable: false);
    if (urls.isEmpty) {
      throw const FormatException(
        'At least one network probe endpoint is required.',
      );
    }
    return <String>['-c', _pythonScript, ...urls];
  }

  static List<CodexNetworkProbeResult> parseOutput(String output) {
    final results = <CodexNetworkProbeResult>[];
    for (final line in const LineSplitter().convert(output)) {
      try {
        final value = jsonDecode(line);
        if (value is! Map<String, dynamic>) continue;
        final host = value['host'];
        final scheme = value['scheme'];
        if (host is! String || scheme is! String) continue;
        final status = value['status'];
        final error = value['error'];
        final errno = value['errno'];
        final proxy = value['proxy'];
        final proxyMap = proxy is Map<String, dynamic> ? proxy : null;
        final proxyHost = proxyMap?['host'];
        final proxyPort = proxyMap?['port'];
        final proxyScheme = proxyMap?['scheme'];
        results.add(
          CodexNetworkProbeResult(
            host: host,
            secure: scheme == 'https',
            statusCode: status is int ? status : null,
            errorType: error is String ? error : null,
            errorNumber: errno is int ? errno : null,
            proxyHost: proxyHost is String ? proxyHost : null,
            proxyPort: proxyPort is int ? proxyPort : null,
            proxyScheme: proxyScheme is String ? proxyScheme : null,
          ),
        );
      } on FormatException {
        continue;
      }
    }
    return List<CodexNetworkProbeResult>.unmodifiable(results);
  }
}

class CodexNetworkProbeResult {
  const CodexNetworkProbeResult({
    required this.host,
    required this.secure,
    this.statusCode,
    this.errorType,
    this.errorNumber,
    this.proxyHost,
    this.proxyPort,
    this.proxyScheme,
  });

  final String host;
  final bool secure;
  final int? statusCode;
  final String? errorType;
  final int? errorNumber;
  final String? proxyHost;
  final int? proxyPort;
  final String? proxyScheme;

  bool get reachedServer => statusCode != null;
}
