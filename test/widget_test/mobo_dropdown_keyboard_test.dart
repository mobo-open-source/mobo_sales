import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_select_field.dart';

/// A dropdown must fit the screen the keyboard leaves behind.
///
/// Reported by a tester as "the last item in the dropdown cannot be selected
/// when scrolling": the panel was sized against the full screen height, so its
/// lower rows were drawn underneath the keyboard — scrollable into view, but
/// never tappable, because the keyboard takes the touch.
void main() {
  const screen = Size(400, 800);
  const keyboard = 320.0;

  List<MoboOption<String>> options(int count) => [
    for (var i = 0; i < count; i++)
      MoboOption<String>(value: 'v$i', label: 'Option $i'),
  ];

  /// Puts a searchable select near the top of the page, so there is plenty of
  /// room below it until the keyboard appears.
  Future<void> pumpField(
    WidgetTester tester, {
    required double viewInsetsBottom,
    ValueChanged<String?>? onChanged,
  }) async {
    tester.view.physicalSize = screen;
    tester.view.devicePixelRatio = 1;
    // Set on the view, not through a MediaQuery widget: the Overlay the panel
    // is inserted into lives above the app's own widgets, so only the view's
    // insets reach it — which is also how a real keyboard arrives.
    tester.view.viewInsets = FakeViewPadding(bottom: viewInsetsBottom);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          // A column that hugs its children, so the field is its natural
          // height rather than stretching to fill the body.
          body: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 300),
              MoboSelectField<String>(
                label: 'Product',
                options: options(30),
                value: null,
                searchable: true,
                onChanged: onChanged ?? (_) {},
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Opens the panel by tapping into the field, as a user does.
  Future<void> openPanel(WidgetTester tester) async {
    await tester.tap(find.byType(TextField).last);
    await tester.pumpAndSettle();
    expect(
      find.text('Option 0'),
      findsOneWidget,
      reason: 'the panel did not open, so the rest proves nothing',
    );
  }

  /// The panel's own option list, not the search field's internal scroll.
  Finder panelList() => find.byType(ListView);

  testWidgets('the panel stays clear of the keyboard', (tester) async {
    await pumpField(tester, viewInsetsBottom: keyboard);
    await openPanel(tester);

    final rect = tester.getRect(panelList());
    expect(
      rect.bottom,
      lessThanOrEqualTo(screen.height - keyboard + 0.5),
      reason: 'the panel runs under the keyboard, so its last rows cannot be '
          'tapped',
    );
  });

  testWidgets('its last option can actually be tapped', (tester) async {
    String? picked;
    await pumpField(
      tester,
      viewInsetsBottom: keyboard,
      onChanged: (value) => picked = value,
    );
    await openPanel(tester);

    // Scroll to the end of the list, as the tester did.
    await tester.drag(panelList(), const Offset(0, -2000));
    await tester.pumpAndSettle();

    final last = find.text('Option 29');
    expect(last, findsOneWidget);

    // Inside the area the keyboard leaves, or the tap never lands.
    expect(
      tester.getRect(last).bottom,
      lessThanOrEqualTo(screen.height - keyboard + 0.5),
    );

    await tester.tap(last);
    await tester.pumpAndSettle();
    expect(picked, 'v29');
  });

  testWidgets('with no keyboard it still uses the room below', (tester) async {
    await pumpField(tester, viewInsetsBottom: 0);
    await openPanel(tester);

    final rect = tester.getRect(panelList());
    expect(rect.height, greaterThan(200), reason: 'not needlessly cramped');
    expect(rect.bottom, lessThanOrEqualTo(screen.height + 0.5));
  });
}
