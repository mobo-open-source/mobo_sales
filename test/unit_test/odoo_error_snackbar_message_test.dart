import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/services/odoo_error_handler.dart';

/// What a user reads in the error snackbar: the reason, in one sentence, with
/// none of the wrapping the app and Odoo put around it.
void main() {
  String say(Object error) => OdooErrorHandler.toSnackbarMessage(error);

  test('a "create a warehouse" warning is just its message', () {
    // Odoo's RedirectWarning also carries an action id, a button label and a
    // context, one per line; this is how it reached the old dialog.
    final error = Exception(
      'Failed to convert quotation to order: Exception: Odoo Server Error: '
      'Please create a warehouse for company My US Company.\n'
      '257\nGo to Warehouses\nNone',
    );
    expect(say(error), 'Please create a warehouse for company My US Company.');
  });

  test('an Odoo error map gives its data.message', () {
    for (final code in [200, 0]) {
      expect(
        say(
          'OdooException: {code: $code, message: Odoo Server Error, data: '
          '{name: odoo.exceptions.UserError, message: Some orders are not in '
          'a state requiring confirmation., arguments: [Some orders are not '
          'in a state requiring confirmation.], context: {}, debug: '
          'Traceback (most recent call last):\n  File "x.py"\nUserError: x\n}}',
        ),
        'Some orders are not in a state requiring confirmation.',
      );
    }
  });

  test('wrappers and prefixes are dropped, a plain message is kept', () {
    expect(
      say(Exception('Cannot confirm a cancelled quotation.')),
      'Cannot confirm a cancelled quotation.',
    );
    expect(
      say(
        Exception(
          'Failed to convert quotation to order: Exception: Order is in '
          'state "done" and cannot be confirmed.',
        ),
      ),
      'Order is in state "done" and cannot be confirmed.',
    );
  });

  test('a message of several lines becomes one', () {
    expect(
      say('Exception: Odoo Server Error: Check these lines:\n- Desk\n- Chair'),
      'Check these lines: - Desk - Chair',
    );
  });

  test('the connection, the session and the rights have their own wording', () {
    expect(
      say('SocketException: Failed host lookup'),
      'Could not reach the server. Please check your internet connection and '
      'try again.',
    );
    expect(
      say(TimeoutException('slow')),
      'The server took too long to respond. Please try again.',
    );
    expect(
      say('Exception: Session expired'),
      'Your session has expired. Please log in again.',
    );
    expect(
      say(
        "Exception: Odoo Server Error: You are not allowed to modify 'Sales "
        "Order' (sale.order) records.",
      ),
      "You don't have permission to do this. Please contact your "
      'administrator.',
    );
  });

  test(
    'a message this class phrased for a dialog gives its first paragraph',
    () {
      expect(
        say(
          '⚙️ Configuration Required\n\nThe system cannot create an invoice '
          'because a SALE journal is not configured for My Company.\n\n'
          '📋 To fix this issue:\n\n1. Log into Odoo web interface',
        ),
        'The system cannot create an invoice because a SALE journal is not '
        'configured for My Company.',
      );
      expect(
        say(
          '🌐 Connection Error\n\nThe server could not be reached. Please '
          'check:\n\n• Your internet connection',
        ),
        'Could not reach the server. Please check your internet connection and '
        'try again.',
      );
    },
  );

  test(
    'nothing readable falls back to the caller\'s sentence or a generic one',
    () {
      expect(say(Exception('')), 'Something went wrong. Please try again.');
      expect(
        OdooErrorHandler.toSnackbarMessage(
          Exception('Instance of \'Foo\''),
          fallback: 'Could not convert the quotation.',
        ),
        'Could not convert the quotation.',
      );
    },
  );
}
