/// Local-only image/header adapter.
///
/// The Android local app supplies local file/data URLs and deliberately sends
/// no remote bearer headers.
Map<String, String> localHttpHeadersForUrl(Object context, String url) => const {};