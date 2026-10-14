import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/loading_skeletons.dart';
import 'package:shimmer/shimmer.dart';

void main() {
  Widget host(Widget child, {ThemeData? theme, Size? size}) => MaterialApp(
    theme: theme ?? ThemeData.light(),
    home: Scaffold(
      body: SizedBox(width: size?.width, height: size?.height, child: child),
    ),
  );

  final themes = [ThemeData.light(), ThemeData.dark()];
  final sizes = [
    const Size(320, 480),
    const Size(411, 900),
    const Size(800, 600),
  ];

  Future<void> noOverflow(WidgetTester tester, Widget Function() build) async {
    for (final theme in themes) {
      for (final size in sizes) {
        await tester.pumpWidget(host(build(), theme: theme, size: size));
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull, reason: '$size');
      }
    }
  }

  group('InfoSectionsSkeleton', () {
    testWidgets('is one shimmer: a heading and a bordered card per section', (
      tester,
    ) async {
      await tester.pumpWidget(
        host(const InfoSectionsSkeleton(rowsPerSection: [3, 2])),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Shimmer), findsOneWidget);
      // A heading per section, then a label and a value per row.
      final blocks = find.byType(SkeletonBlock);
      expect(blocks, findsNWidgets(2 + (3 + 2) * 2));
    });

    testWidgets('does not overflow on any screen, light or dark', (
      tester,
    ) async {
      await noOverflow(tester, () => const InfoSectionsSkeleton());
    });
  });

  group('RowsSkeleton', () {
    testWidgets('draws the rows asked for under one shimmer', (tester) async {
      await tester.pumpWidget(host(const RowsSkeleton(count: 4)));
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(Shimmer), findsOneWidget);
      // A leading square and two lines per row.
      expect(find.byType(SkeletonBlock), findsNWidgets(4 * 3));
    });

    testWidgets('round leading for people, square for files', (tester) async {
      await tester.pumpWidget(
        host(const RowsSkeleton(count: 1, circleLeading: true)),
      );
      final leading = tester.widget<SkeletonBlock>(
        find.byType(SkeletonBlock).first,
      );
      expect(leading.shape, BoxShape.circle);
    });

    testWidgets('does not overflow in a narrow card', (tester) async {
      await noOverflow(tester, () => const RowsSkeleton(count: 3));
    });
  });

  group('SalesHistorySkeleton', () {
    testWidgets('has the heading, four tiles, the chart and the rows, under '
        'one shimmer', (tester) async {
      await tester.pumpWidget(host(const SalesHistorySkeleton()));
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(Shimmer), findsOneWidget, reason: 'a single sweep');
      final tiles = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 120 && w.width != null,
      );
      expect(tiles, findsNWidgets(4));
      final chart = find.byWidgetPredicate(
        (w) => w is SizedBox && w.height == 200,
      );
      expect(chart, findsOneWidget);
    });

    testWidgets('does not overflow on a phone, a tablet, light or dark', (
      tester,
    ) async {
      await noOverflow(tester, () => const SalesHistorySkeleton());
    });
  });
}
