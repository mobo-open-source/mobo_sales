import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/home_scaffold.dart';
import 'package:mobo_sales/services/review_service.dart';
import 'package:mobo_sales/widgets/rating_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('the rating pop-up never shows outside the signed-in app', (
    tester,
  ) async {
    // Every threshold is met, so only the screen decides.
    SharedPreferences.setMockInitialValues({
      'review_open_count': 50,
      'review_event_count': 50,
    });
    late BuildContext context;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (c) {
            context = c;
            return const Scaffold(body: Text('Sign In'));
          },
        ),
      ),
    );

    expect(HomeScaffoldState.isShowing, isFalse);
    await ReviewService().checkAndShowRating(context);
    await tester.pumpAndSettle();
    expect(find.byType(CustomRatingDialog), findsNothing);
    expect(find.text("How’s your experience ?"), findsNothing);
  });
}
