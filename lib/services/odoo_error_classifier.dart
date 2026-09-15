/// Classifies raw Odoo and transport errors so every screen reports them alike.
class OdooErrorClassifier {
  const OdooErrorClassifier._();

  static final RegExp _httpStatus = RegExp(r'(?<![0-9])(404|500|502|503|504)(?![0-9])');

  static const List<String> _transportMarkers = [
    'socketexception',
    'clientexception',
    'connection refused',
    'connection timeout',
    'connection failed',
    'failed to connect',
    'failed host lookup',
    'host unreachable',
    'no route to host',
    'network is unreachable',
    'server returned html instead of json',
    'server may be down',
    'unexpected response',
    'url incorrect',
    'database not found',
  ];

  static const List<String> _httpContextMarkers = [
    'http',
    'statuscode',
    'status code',
    'bad gateway',
    'gateway timeout',
    'service unavailable',
    'internal server error',
  ];

  /// Returns `true` when [error] means the server or network could not be reached.
  ///
  /// A bare `Odoo Server Error` is deliberately excluded. Odoo uses it for
  /// application-level failures such as access, validation and domain errors,
  /// so treating it as an unreachable server hides the real cause and sends
  /// users to check infrastructure that is working correctly.
  ///
  /// A bare HTTP status number is also not enough on its own: amounts and
  /// record ids routinely contain `500`, so the message must additionally read
  /// like a transport failure.
  static bool isServerUnreachable(Object? error) {
    final message = error?.toString().toLowerCase() ?? '';
    if (message.isEmpty) return false;

    for (final marker in _transportMarkers) {
      if (message.contains(marker)) return true;
    }

    if (!_httpStatus.hasMatch(message)) return false;
    return _httpContextMarkers.any(message.contains);
  }
}
