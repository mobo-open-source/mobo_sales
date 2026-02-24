import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/empty_state_widget.dart';

void main() {
  group('EmptyStateWidget Tests', () {
    testWidgets('should display title and message', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: Icons.error,
              title: 'Test Title',
              message: 'Test Message',
            ),
          ),
        ),
      );

      expect(find.text('Test Title'), findsOneWidget);
      expect(find.text('Test Message'), findsOneWidget);
    });

    testWidgets('should call onAction when action button is pressed', (
      WidgetTester tester,
    ) async {
      bool actionCalled = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget(
              icon: Icons.error,
              title: 'Title',
              message: 'Message',
              actionLabel: 'Click Me',
              onAction: () => actionCalled = true,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Click Me'));
      await tester.pump();

      expect(actionCalled, true);
    });

    testWidgets('EmptyStateWidget.customers should show correct text', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: EmptyStateWidget.customers(
              hasFilters: true,
              onClearFilters: () {},
            ),
          ),
        ),
      );

      expect(find.text('No customers found'), findsOneWidget);
      expect(find.text('Clear Filters'), findsOneWidget);
    });
  });
}
