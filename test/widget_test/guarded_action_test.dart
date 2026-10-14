import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/main.dart' show navigatorKey;
import 'package:mobo_sales/utils/guarded_action.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/widgets/loading_dialog.dart';

void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigatorKey,
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: Text('HOME'));
          },
        ),
      ),
    );
  }

  Future<void> finish(WidgetTester tester) async {
    CustomSnackbar.dismiss();
    await tester.pump();
  }

  testWidgets(
    'shows the loading card while it runs, then the success message',
    (tester) async {
      await pumpHost(tester);
      final done = Completer<String>();
      final future = runGuardedAction<String>(
        context: host,
        message: 'Archiving customer...',
        subtitle: 'Please wait while we archive the customer.',
        action: () => done.future,
        successMessage: 'Customer archived',
      );
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byType(LoadingDialog), findsOneWidget);
      expect(find.text('Archiving customer...'), findsOneWidget);
      expect(
        find.text('Please wait while we archive the customer.'),
        findsOneWidget,
      );

      done.complete('ok');
      expect(await future, 'ok');
      await tester.pumpAndSettle();

      expect(find.byType(LoadingDialog), findsNothing);
      expect(find.text('Customer archived'), findsOneWidget);
      expect(
        find.text('HOME'),
        findsOneWidget,
        reason: 'the page is untouched',
      );
      await finish(tester);
    },
  );

  testWidgets('a failure closes the card and says why, once', (tester) async {
    await pumpHost(tester);
    final future = runGuardedAction<Object?>(
      context: host,
      message: 'Deleting...',
      failurePrefix: 'Could not delete',
      action: () async {
        throw Exception('in use');
      },
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(await future, isNull);
    await tester.pumpAndSettle();
    expect(find.byType(LoadingDialog), findsNothing);
    expect(find.textContaining('Could not delete'), findsOneWidget);
    expect(find.text('HOME'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('a stalled action times out instead of hanging the screen', (
    tester,
  ) async {
    await pumpHost(tester);
    final future = runGuardedAction<Object?>(
      context: host,
      message: 'Saving...',
      timeout: const Duration(milliseconds: 200),
      action: () => Completer<Object?>().future,
    );
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(await future, isNull);
    await tester.pumpAndSettle();
    expect(find.byType(LoadingDialog), findsNothing);
    expect(find.textContaining('did not respond in time'), findsOneWidget);
    await finish(tester);
  });
}
