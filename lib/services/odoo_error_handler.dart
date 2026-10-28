import 'dart:async';

import 'odoo_error_classifier.dart';

/// Converts raw Odoo server errors into readable user-facing messages.
class OdooErrorHandler {
  /// Returns `true` if [e] represents an access rights or permission error.
  ///
  /// Matches what Odoo 17 to 20 word their `AccessError`s: the model-level
  /// `You are not allowed to access 'X' (x.y) records.`, the record-rule
  /// `Uh-oh! Looks like you have stumbled upon some top-secret records.`
  /// and the field-level `You do not have enough rights to access the field
  /// "f" on X (x.y).` The exception class name (`odoo.exceptions.AccessError`)
  /// is there too when the error came through odoo_rpc.
  static bool isAccessError(dynamic e) {
    final s = e.toString().toLowerCase();
    return s.contains('accesserror') ||
        s.contains('access rights') ||
        s.contains('access denied') ||
        s.contains('not allowed to') ||
        s.contains('top-secret records') ||
        s.contains('enough rights') ||
        s.contains('permission');
  }

  /// The reason [e] gives, as one plain sentence for a snackbar.
  ///
  /// Only what the server (or the app) says went wrong, in the user's terms:
  /// no `Exception:` prefixes, no "Failed to do X:" wrappers, no `Odoo Server
  /// Error`, no traceback, none of the extra lines Odoo adds to a "go to the
  /// settings" warning (its action id, its button label, `None`). Failures that
  /// are about the connection, the session or the user's rights get their own
  /// short wording, because the server's text for those is not meant for
  /// users. [fallback] is used when nothing readable is left.
  static String toSnackbarMessage(dynamic e, {String? fallback}) {
    final generic = fallback ?? 'Something went wrong. Please try again.';
    final raw = e.toString();
    final lower = raw.toLowerCase();

    if (e is TimeoutException ||
        lower.contains('timeoutexception') ||
        lower.contains('timed out') ||
        lower.contains('request timeout')) {
      return 'The server took too long to respond. Please try again.';
    }
    if (lower.contains('session expired') ||
        lower.contains('session invalid') ||
        lower.contains('sessionexpired')) {
      return 'Your session has expired. Please log in again.';
    }
    if (isNotJsonResponse(e)) {
      return notJsonResponseMessage;
    }
    if (OdooErrorClassifier.isServerUnreachable(e) ||
        lower.contains('connection error')) {
      return 'Could not reach the server. Please check your internet '
          'connection and try again.';
    }
    if (isAccessError(e)) {
      return "You don't have permission to do this. Please contact your "
          'administrator.';
    }

    // The database's own words for a rule it enforces: a user cannot act on
    // "violates unique constraint res_partner_x_key".
    if (lower.contains('duplicate key value') ||
        lower.contains('violates unique constraint')) {
      return 'This already exists: a value that has to be unique is already '
          'used by another record.';
    }
    if (lower.contains('violates not-null constraint')) {
      return 'A required value is missing. Please fill in all required fields.';
    }
    if (lower.contains('violates foreign key constraint')) {
      return 'This is linked to other records, so it cannot be changed or '
          'removed.';
    }

    var text = _serverSentence(raw);
    text = _tidy(text);
    // The last gate before a person reads this. Anything still carrying a
    // stack frame, a parser's complaint or a Dart type name is the app's
    // internals leaking into the UI, and a generic sentence is better than
    // showing it.
    if (text.isEmpty || _looksTechnical(text)) {
      return generic;
    }
    return '${text[0].toUpperCase()}${text.substring(1)}';
  }

  /// What the user is told when the server answered with something other than
  /// the JSON the app asked for.
  static const String notJsonResponseMessage =
      'The server sent an unexpected response. Please check the server '
      'address in Settings, or log in again.';

  /// Whether [error] is the app failing to parse the server's reply.
  ///
  /// Odoo answers JSON-RPC with JSON. A web page instead — a proxy error page,
  /// a maintenance notice, or the login form after a session expired — fails
  /// in `jsonDecode` as "FormatException: Unexpected character (at character
  /// 1)" followed by `<html>`, which is meaningless to the person holding
  /// the phone.
  static bool isNotJsonResponse(dynamic error) {
    if (error is FormatException) return true;
    final s = error.toString().toLowerCase();
    return s.contains('unexpected character (at character') ||
        s.contains('server returned html instead of json') ||
        s.contains('<!doctype html') ||
        s.contains('<html');
  }

  /// Whether [text] still reads like machinery rather than a sentence.
  ///
  /// Deliberately specific: a blanket "contains exception" would also throw
  /// away Odoo's own messages, which routinely name `odoo.exceptions.UserError`
  /// before saying something the user needs to read. [_tidy] strips that
  /// prefix first; what this catches is what survives it.
  static bool _looksTechnical(String text) {
    final t = text.toLowerCase();
    return t.contains('instance of ') ||
        t.contains('traceback') ||
        t.contains('at character') ||
        t.contains('formatexception') ||
        t.contains('<!doctype') ||
        t.contains('<html') ||
        t.contains('is not a subtype of') ||
        t.contains('null check operator') ||
        t.contains('nosuchmethoderror') ||
        t.contains('stack trace') ||
        text.startsWith('{') ||
        text.startsWith('[') ||
        RegExp(r'^#\d+\s').hasMatch(text);
  }

  /// The part of [raw] the server wrote: the `data.message` of an odoo_rpc
  /// error map, what follows `Odoo Server Error:` in the app's own wrapping,
  /// or [raw] itself. An error this class already phrased for a dialog (a
  /// title line with an emoji, then paragraphs) gives its first paragraph.
  static String _serverSentence(String raw) {
    final paragraphs = raw.trim().split(RegExp(r'\n\s*\n'));
    if (paragraphs.length > 1 && _startsWithSymbol(paragraphs.first)) {
      var body = paragraphs[1].trim();
      // "…could not be reached. Please check:" — the list that follows is gone.
      if (body.endsWith(':')) {
        final lastStop = body.lastIndexOf('. ');
        body = lastStop == -1
            ? body.substring(0, body.length - 1)
            : body.substring(0, lastStop + 1);
      }
      return body;
    }

    final map = RegExp(
      r'data:\s*\{.*?message:\s*(.*?),\s*arguments:',
      dotAll: true,
    ).firstMatch(raw);
    if (map != null) return map.group(1)!;

    const marker = 'Odoo Server Error:';
    final at = raw.lastIndexOf(marker);
    if (at != -1) return raw.substring(at + marker.length);
    return raw;
  }

  static bool _startsWithSymbol(String text) {
    final trimmed = text.trimLeft();
    return trimmed.isNotEmpty && trimmed.runes.first > 0x2000;
  }

  /// Strips the wrappers, the traceback and Odoo's warning residue from
  /// [text] and folds it onto one line.
  static String _tidy(String text) {
    var out = text.trim();
    final traceback = out.indexOf('Traceback (most recent call last)');
    if (traceback != -1) out = out.substring(0, traceback);

    final wrappers = [
      RegExp(r'^(?:[A-Za-z]*Exception|Error|StateError)\s*:\s*'),
      // A Python exception named by its full path, which Odoo puts in front
      // of the sentence it actually wants read:
      // `odoo.exceptions.UserError: ...`, `psycopg2.errors.X: ...`.
      RegExp(r'^(?:[a-zA-Z_]\w*\.)+[A-Za-z_]\w*(?:Error|Exception|Warning)\s*:\s*'),
      RegExp(r'^Failed to [^:\n]{3,80}:\s+'),
      RegExp(r'^Odoo Server Error\s*:\s*'),
    ];
    var stripped = true;
    while (stripped) {
      stripped = false;
      for (final wrapper in wrappers) {
        final m = wrapper.firstMatch(out);
        if (m != null && m.end < out.length) {
          out = out.substring(m.end);
          stripped = true;
        }
      }
    }

    // An exception with no message prints as just its name.
    if (RegExp(r'^(?:[A-Za-z]*Exception|Error)\s*:?$').hasMatch(out)) return '';

    // A "go to <settings>" warning arrives as message, action id, button
    // label, context — one per line. Only the message is for the user.
    var lines = out
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();
    final actionId = lines.indexWhere((l) => RegExp(r'^\d+$').hasMatch(l));
    if (actionId > 0 &&
        lines.length - actionId <= 3 &&
        (lines.last == 'None' || lines.last.startsWith('{'))) {
      lines = lines.sublist(0, actionId);
    }

    out = lines.join(' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return out.length > 400 ? '${out.substring(0, 397)}...' : out;
  }

  /// Converts [e] to a user-readable error message, with an optional [defaultMessage] fallback.
  static String toUserMessage(dynamic e, {String? defaultMessage}) {
    final errorString = e.toString();
    final s = errorString.toLowerCase();

    // Checked before anything else: the reply never got as far as being an
    // Odoo error, so none of the patterns below can read it, and its raw text
    // is a parser's complaint about a web page.
    if (isNotJsonResponse(e)) {
      return '🌐 Unexpected Server Response\n\n$notJsonResponseMessage';
    }

    if (s.contains('no journal could be found') ||
        s.contains('no journal of type')) {
      String companyName = 'your company';
      String journalType = 'the required type';

      final companyMatch =
          RegExp(r'company\s+(.*?)\s+for\s+any').firstMatch(errorString) ??
          RegExp(r'company\s+(.*?)\s+[\(\)]').firstMatch(errorString);
      if (companyMatch != null && companyMatch.groupCount >= 1) {
        companyName = companyMatch.group(1)!.trim();
      }

      final typeMatch = RegExp(r'types?:\s*(\w+)').firstMatch(errorString);
      if (typeMatch != null && typeMatch.groupCount >= 1) {
        journalType = typeMatch.group(1)!.trim();
      }

      return '''⚙️ Configuration Required

The system cannot create an invoice because a ${journalType.toUpperCase()} journal is not configured for $companyName.

📋 To fix this issue:

1. Log into Odoo web interface
2. Go to Accounting → Configuration → Journals
3. Create a new journal with:
   • Type: ${journalType.toUpperCase()}
   • Name: Customer Invoices (or similar)
   • Short Code: INV (or your preference)
   • Company: $companyName

If this is a new database, you may need to install the Chart of Accounts first from Accounting → Configuration → Settings.

Please contact your system administrator if you need assistance.''';
    }

    if (s.contains('missing required account on accountable line')) {
      return '''⚙️ Accounting Configuration Required

The system cannot create an invoice because an income account is missing for one of the products.

📋 To fix this issue:

1. Log into Odoo web interface
2. Check the Product configuration:
   • Go to Inventory → Products
   • Open the product(s) in your invoice
   • Go to the 'Accounting' tab
   • Ensure 'Income Account' is set
3. OR check the Product Category:
   • Go to Inventory → Configuration → Product Categories
   • Ensure 'Income Account' is set for the category

If you have just installed Odoo, ensure you have a Chart of Accounts installed.

Please contact your system administrator for assistance.''';
    }

    if (s.contains('chart of accounts') ||
        s.contains('no account configured') ||
        s.contains('account.account')) {
      return '''⚙️ Accounting Setup Required

The accounting module is not fully configured for this company.

📋 To fix this issue:

1. Log into Odoo web interface
2. Go to Accounting → Configuration → Settings
3. Install the Chart of Accounts for your country
4. Complete the accounting setup wizard

This will automatically create all necessary journals and accounts.

Please contact your system administrator for assistance.''';
    }

    if (s.contains('fiscal position') && s.contains('not found')) {
      return '''⚙️ Fiscal Position Error

The fiscal position configured for this customer or company is invalid or missing.

📋 To fix this issue:

1. Check the customer's fiscal position settings
2. Verify fiscal positions in Accounting → Configuration → Fiscal Positions
3. Update or remove the invalid fiscal position

Please contact your system administrator for assistance.''';
    }

    if (s.contains('you are not allowed to create') ||
        s.contains('you are not allowed to modify') ||
        s.contains('you do not have permission')) {
      if (errorString.contains('message: ')) {
        final parts = errorString.split('message: ');
        if (parts.length > 1) {
          String permissionMsg = parts[1];

          if (permissionMsg.contains(', arguments:')) {
            permissionMsg = permissionMsg.split(', arguments:')[0];
          }
          if (permissionMsg.contains(', context:')) {
            permissionMsg = permissionMsg.split(', context:')[0];
          }
          return '🔒 Permission Denied\n\n$permissionMsg\n\nPlease contact your administrator to request the necessary permissions.';
        }
      }
    }

    if (isAccessError(e)) {
      return '🔒 Access Denied\n\nYou do not have sufficient permissions to perform this action.\n\nPlease contact your administrator to request the necessary permissions.';
    }

    if (s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('connection timeout') ||
        s.contains('host unreachable') ||
        s.contains('no route to host') ||
        s.contains('network is unreachable') ||
        s.contains('failed to connect') ||
        s.contains('connection failed') ||
        s.contains('server returned html instead of json')) {
      return '🌐 Connection Error\n\nThe server could not be reached. Please check:\n\n• Your internet connection\n• Server URL in settings\n• Server availability\n\nThen try again.';
    }

    if (s.contains('timeout')) {
      return '⏱️ Request Timeout\n\nThe request took too long to complete.\n\nThis might be due to:\n• Slow internet connection\n• Server overload\n• Large data processing\n\nPlease try again.';
    }

    if (s.contains('product') &&
        (s.contains('not found') || s.contains('does not exist'))) {
      return '📦 Product Error\n\nThe selected product is invalid or has been deleted.\n\nPlease select a different product and try again.';
    }

    if (s.contains('partner') &&
        (s.contains('not found') || s.contains('does not exist'))) {
      return '👤 Customer Error\n\nThe selected customer is invalid or has been deleted.\n\nPlease select a different customer and try again.';
    }

    if (s.contains('company inconsistencies') ||
        s.contains('company crossover')) {
      if (errorString.contains('message:')) {
        try {
          final messageStart = errorString.indexOf('message:');
          final messageContent = errorString.substring(
            messageStart + 'message:'.length,
          );

          var messageEnd = messageContent.indexOf(', arguments:');
          if (messageEnd == -1) {
            messageEnd = messageContent.indexOf(', context:');
          }
          if (messageEnd == -1) messageEnd = messageContent.indexOf(', debug:');

          if (messageEnd > 0) {
            String cleanMessage = messageContent
                .substring(0, messageEnd)
                .trim();

            cleanMessage = cleanMessage.replaceAll(RegExp(r'\s+'), ' ').trim();
            return '⚠️ Company Mismatch\n\n$cleanMessage';
          }
        } catch (parseError) {}
      }

      return '⚠️ Company Mismatch\n\nThe product and taxes belong to different companies. Please ensure all items in the invoice belong to the same company.\n\nContact your administrator if you need assistance.';
    }

    return defaultMessage ??
        '❌ Operation Failed\n\nAn unexpected error occurred. Please try again or contact support if the problem persists.';
  }
}
