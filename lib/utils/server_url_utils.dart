/// Canonicalises an Odoo server URL so every path that stores or compares one
/// agrees on a single string for the same server.
///
/// Adds a scheme when missing, lowercases scheme and host (never the path —
/// some reverse proxies mount Odoo under a case-sensitive segment), and drops
/// trailing slashes. Without this, `srv.example.com/` saved from Add Account
/// and `https://srv.example.com` from the login screen are two different
/// accounts to every equality check.
String normalizeServerUrl(String? url, {String defaultScheme = 'https://'}) {
  var trimmed = (url ?? '').trim();
  if (trimmed.isEmpty) return trimmed;

  final lower = trimmed.toLowerCase();
  if (!lower.startsWith('http://') && !lower.startsWith('https://')) {
    trimmed = '$defaultScheme$trimmed';
  }

  try {
    final uri = Uri.parse(trimmed);
    var path = uri.path;
    while (path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    return uri
        .replace(
          scheme: uri.scheme.toLowerCase(),
          host: uri.host.toLowerCase(),
          path: path,
        )
        .toString();
  } catch (_) {
    var result = trimmed;
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
