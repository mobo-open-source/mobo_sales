import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lottie/lottie.dart';
import 'package:mobo_sales/services/odoo_error_classifier.dart';
import 'package:mobo_sales/widgets/connection_status_widget.dart';
import 'package:mobo_sales/widgets/empty_state_widget.dart';

/// The list screens have two illustrations and they mean different things:
/// the robot for "this failed", the ghost for "there is nothing here".
///
/// A tester had Customers, Quotations and Products on the robot and Invoices
/// alone on the ghost, from the same unreachable server. The invoice screen's
/// guard read `_isServerUnreachable && !isErrorWithNoData`, where
/// isErrorWithNoData was itself `_isServerUnreachable && the list is empty`,
/// so with the server down and nothing loaded the connection branch could
/// never fire and the failure fell through to the empty state.
String _assetOf(WidgetTester tester) {
  final builder = tester.widget<LottieBuilder>(find.byType(LottieBuilder));
  return (builder.lottie as AssetLottie).assetName;
}

void main() {
  group('a failure is drawn as a failure', () {
    testWidgets('an unreachable server gets the error animation', (
      tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ConnectionStatusWidget(
              serverUnreachable: true,
              serverErrorMessage:
                  'Unable to load invoices from server/database. '
                  'Please check your server or try again.',
            ),
          ),
        ),
      );

      expect(_assetOf(tester), 'assets/lotti/error_404.json');
    });

    testWidgets('an empty list gets the ghost', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmptyStateWidget.invoices())),
      );

      expect(_assetOf(tester), 'assets/lotti/empty_ghost.json');
    });

    testWidgets('the two never share one animation', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ConnectionStatusWidget(serverUnreachable: true)),
        ),
      );
      final failure = _assetOf(tester);

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: EmptyStateWidget.invoices())),
      );

      expect(failure, isNot(_assetOf(tester)));
    });
  });

  group('one dead server, one set of words', () {
    // A tester had four tabs of the same app describing the same unreachable
    // server four different ways, under two different titles, because each
    // screen passed its own sentence instead of the condition.
    const generic = ConnectionStatusWidget.cantReachServer;

    test('the sentence the providers set', () {
      expect(
        ConnectionStatusWidget.errorInfoFor(
          'Server/Database unreachable. Please check your server or try again.',
        ),
        generic,
      );
    });

    test('an unexpected response', () {
      expect(
        ConnectionStatusWidget.errorInfoFor(
          'The server sent an unexpected response. Please check the server '
          'address in Settings, or log in again.',
        ),
        generic,
      );
    });

    test('nothing to go on', () {
      expect(ConnectionStatusWidget.errorInfoFor(null), generic);
      expect(ConnectionStatusWidget.errorInfoFor(''), generic);
    });

    test('a raw exception never reaches the user', () {
      final info = ConnectionStatusWidget.errorInfoFor(
        'ClientException with SocketException: Connection refused '
        '(OS Error: Connection refused, errno = 111), address = 10.0.2.2',
      );

      expect(info['title'], generic['title']);
      expect(info['message'], isNot(contains('errno')));
    });

    test('an HTML error page reads the same as a refused socket', () {
      // One branch, one title. Split in two, the same dead server says
      // "Server Error" on Quotations and "Can't Reach Server" on Customers.
      expect(
        ConnectionStatusWidget.errorInfoFor(
          'FormatException: Unexpected character (at character 1) <html>',
        )['title'],
        ConnectionStatusWidget.errorInfoFor(
          'SocketException: Connection refused',
        )['title'],
      );
    });

    test('the server address is kept when the error carries one', () {
      final info = ConnectionStatusWidget.errorInfoFor(
        'SocketException: Connection refused, address = 10.0.2.2, port = 8069',
      );

      expect(info['message'], contains('10.0.2.2'));
      expect(info['message'], startsWith(generic['message']!));
    });

    test('a failure with its own name keeps it', () {
      expect(
        ConnectionStatusWidget.errorInfoFor(
          'Odoo returned 503 Service Unavailable',
        )['title'],
        'Server Unavailable (503)',
        reason: 'generic is for the unnamed case, not a flattening of all of them',
      );
      expect(
        ConnectionStatusWidget.errorInfoFor('Odoo Session Expired')['title'],
        'Session Expired',
      );
    });

    test('a business error is left exactly as it is', () {
      const userError = 'You cannot delete an entry which has been posted.';

      expect(ConnectionStatusWidget.errorInfoFor(userError), {
        'title': 'Error',
        'message': userError,
      });
    });
  });

  group('the message the invoice list fell through on', () {
    // _loadErrorMessage holds OdooErrorHandler.toSnackbarMessage(e), so the
    // guard's fallback has to recognise the formatted wording, not just the
    // raw exception.
    test('reads as a transport failure', () {
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'The server sent an unexpected response. Please check the server '
          'address in Settings, or log in again.',
        ),
        isTrue,
      );
    });

    test('a session failure still is not one', () {
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'Your session has expired. Please log in again to continue.',
        ),
        isFalse,
        reason: 'checking the network will not fix it',
      );
    });

    test('a business error still is not one', () {
      expect(
        OdooErrorClassifier.isServerUnreachable(
          'UserError: You cannot delete a posted entry.',
        ),
        isFalse,
      );
    });
  });
}
