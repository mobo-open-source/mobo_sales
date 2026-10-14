import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/profile_details_shimmer.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  Widget host({ThemeData? theme, Size? size}) => MaterialApp(
    theme: theme ?? ThemeData.light(),
    home: Scaffold(
      body: SizedBox(
        width: size?.width,
        height: size?.height,
        child: const ProfileDetailsShimmer(),
      ),
    ),
  );

  testWidgets('draws one skeleton shaped like the screen, under one shimmer', (
    tester,
  ) async {
    await tester.pumpWidget(host());
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.byType(Shimmer), findsOneWidget);
    expect(tester.takeException(), isNull);

    // The round photo is a circle the size of the real one.
    final circle = find.byWidgetPredicate(
      (w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle,
    );
    expect(circle, findsOneWidget);
    expect(tester.getSize(circle), const Size(126, 126));

    // An input box per field: full width, 56 tall.
    final boxes = find.byWidgetPredicate(
      (w) => w is Container && w.constraints?.maxHeight == 56,
    );
    expect(boxes, findsNWidgets(8));
  });

  testWidgets('does not overflow on a short or narrow screen, light or dark', (
    tester,
  ) async {
    for (final theme in [ThemeData.light(), ThemeData.dark()]) {
      for (final size in [const Size(320, 480), const Size(411, 900)]) {
        await tester.pumpWidget(host(theme: theme, size: size));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '$size');
      }
    }
  });
}
