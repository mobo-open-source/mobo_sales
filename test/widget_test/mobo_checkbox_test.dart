import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/shared/widgets/mobo/mobo_checkbox.dart';
import 'package:mobo_sales/utils/app_theme.dart';

/// The checkbox is built to a design spec, so the first group of tests samples
/// real pixels at 2x and checks them against what the spec shows: a 24 dp box
/// is 48 px, its outline 3 px, and the hover tint `#FAE6E8`. The rest cover how
/// it behaves and where [MoboCheckboxField] puts things.
void main() {
  const primary = Color(0xFFC03355);
  const hoverTint = Color(0xFFFAE6E8);

  // A plain theme with the brand colour: AppTheme loads Manrope over the
  // network, which a test that runs real async work cannot do.
  final light = ThemeData(primaryColor: primary);
  final dark = ThemeData(brightness: Brightness.dark, primaryColor: primary);

  group('pixels, against the design spec', () {
    /// Renders [box] at 2x, optionally with a finger held on it, and returns a
    /// lookup of the pixel at (x, y), composited over [background].
    Future<Color Function(int x, int y)> render(
      WidgetTester tester,
      Widget box, {
      bool press = false,
      ThemeData? theme,
      Color background = Colors.white,
    }) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme ?? light,
          home: Scaffold(
            backgroundColor: background,
            body: Center(
              child: RepaintBoundary(key: key, child: box),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      TestGesture? finger;
      if (press) {
        finger = await tester.startGesture(
          tester.getCenter(find.byType(box.runtimeType)),
        );
        // One pump to start the fill animating, one to let it finish.
        await tester.pump(const Duration(milliseconds: 300));
        await tester.pump(const Duration(milliseconds: 300));
      }

      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      late Uint8List rgba;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        rgba = (await image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        ))!.buffer.asUint8List();
        expect(image.width, 48, reason: 'a 24 dp box at 2x');
        expect(image.height, 48);
      });
      await finger?.cancel();

      return (x, y) {
        final i = (y * 48 + x) * 4;
        final a = rgba[i + 3] / 255;
        int mix(int c, int bg) => (c * a + bg * (1 - a)).round();
        return Color.fromARGB(
          255,
          mix(rgba[i], (background.r * 255).round()),
          mix(rgba[i + 1], (background.g * 255).round()),
          mix(rgba[i + 2], (background.b * 255).round()),
        );
      };
    }

    Matcher near(Color c, {int tolerance = 2}) => predicate<Color>(
      (p) =>
          (p.r * 255 - c.r * 255).abs() <= tolerance &&
          (p.g * 255 - c.g * 255).abs() <= tolerance &&
          (p.b * 255 - c.b * 255).abs() <= tolerance,
      'is within $tolerance of $c',
    );

    Matcher whiteish() => predicate<Color>(
      (p) => p.r * 255 > 235 && p.g * 255 > 235 && p.b * 255 > 235,
      'is (nearly) white',
    );

    testWidgets(
      'default: white inside, a 3 px brand outline, rounded corners',
      (tester) async {
        final at = await render(
          tester,
          MoboCheckbox(value: false, onChanged: (_) {}),
        );

        expect(at(24, 24), near(Colors.white), reason: 'fill');
        // 3 px of outline on each side: 1.5 dp at 2x.
        for (final x in [0, 1, 2]) {
          expect(at(x, 24), near(primary), reason: 'left outline, x=$x');
          expect(at(47 - x, 24), near(primary), reason: 'right outline, x=$x');
          expect(at(24, x), near(primary), reason: 'top outline, y=$x');
          expect(at(24, 47 - x), near(primary), reason: 'bottom outline, y=$x');
        }
        expect(
          at(3, 24),
          near(Colors.white),
          reason: 'outline is 3 px, not more',
        );
        // An 8 dp radius leaves the very corner empty.
        expect(at(0, 0), near(Colors.white), reason: 'rounded corner');
        expect(at(47, 47), near(Colors.white), reason: 'rounded corner');
      },
    );

    testWidgets('hover / pressed: the #FAE6E8 tint inside the same outline', (
      tester,
    ) async {
      final at = await render(
        tester,
        MoboCheckbox(value: false, onChanged: (_) {}),
        press: true,
      );

      expect(at(24, 24), near(hoverTint), reason: 'fill');
      expect(at(1, 24), near(primary), reason: 'outline stays');
    });

    testWidgets('selected: brand fill with a white check, no visible outline', (
      tester,
    ) async {
      final at = await render(
        tester,
        MoboCheckbox(value: true, onChanged: (_) {}),
      );

      expect(at(24, 40), near(primary), reason: 'fill below the check');
      expect(at(24, 16), near(primary), reason: 'fill above the vertex');
      expect(at(1, 24), near(primary), reason: 'outline is the fill colour');
      // Points inside each stroke of the check, read off the spec: the short
      // left arm, the vertex, and the long right arm.
      expect(at(12, 26), whiteish(), reason: 'left arm');
      expect(at(18, 31), whiteish(), reason: 'vertex');
      expect(at(35, 16), whiteish(), reason: 'right arm tip');
      expect(at(27, 24), whiteish(), reason: 'right arm middle');
      // And just off it.
      expect(at(18, 20), near(primary), reason: 'between the arms');
    });

    testWidgets('indeterminate: brand fill with a white dash', (tester) async {
      final at = await render(
        tester,
        MoboCheckbox(value: null, tristate: true, onChanged: (_) {}),
      );

      expect(at(24, 24), whiteish(), reason: 'dash');
      expect(at(14, 23), whiteish(), reason: 'dash, left part');
      expect(at(24, 14), near(primary), reason: 'fill above the dash');
      expect(at(24, 34), near(primary), reason: 'fill below the dash');
    });

    testWidgets('scales with its size, keeping its proportions', (
      tester,
    ) async {
      final key = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          theme: light,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: Center(
              child: RepaintBoundary(
                key: key,
                child: MoboCheckbox(value: true, size: 48, onChanged: (_) {}),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.getSize(find.byType(MoboCheckbox)), const Size(48, 48));
    });

    testWidgets(
      'dark theme: surface fill, brand outline, brand tint on hover',
      (tester) async {
        final surface = Colors.grey[850]!;
        final background = const Color(0xFF181A20);

        var at = await render(
          tester,
          MoboCheckbox(value: false, onChanged: (_) {}),
          theme: dark,
          background: background,
        );
        expect(at(24, 24), near(surface), reason: 'fill');
        expect(at(1, 24), near(primary), reason: 'outline');

        at = await render(
          tester,
          MoboCheckbox(value: true, onChanged: (_) {}),
          theme: dark,
          background: background,
        );
        expect(at(24, 40), near(primary), reason: 'selected fill');
        expect(at(35, 16), whiteish(), reason: 'check');
      },
    );
  });

  group('behaviour', () {
    Widget host(Widget child) => MaterialApp(
      theme: light,
      home: Scaffold(body: Center(child: child)),
    );

    testWidgets('a tap reports the opposite value', (tester) async {
      final seen = <bool?>[];
      await tester.pumpWidget(
        host(MoboCheckbox(value: false, onChanged: seen.add)),
      );

      await tester.tap(find.byType(MoboCheckbox));
      expect(seen, [true]);

      await tester.pumpWidget(
        host(MoboCheckbox(value: true, onChanged: seen.add)),
      );
      await tester.tap(find.byType(MoboCheckbox));
      expect(seen, [true, false]);
    });

    testWidgets('tristate cycles unselected, selected, indeterminate', (
      tester,
    ) async {
      final seen = <bool?>[];
      Widget box(bool? v) =>
          host(MoboCheckbox(value: v, tristate: true, onChanged: seen.add));

      await tester.pumpWidget(box(false));
      await tester.tap(find.byType(MoboCheckbox));
      await tester.pumpWidget(box(true));
      await tester.tap(find.byType(MoboCheckbox));
      await tester.pumpWidget(box(null));
      await tester.tap(find.byType(MoboCheckbox));

      expect(seen, [true, null, false]);
    });

    testWidgets('without onChanged it only displays, at full strength', (
      tester,
    ) async {
      await tester.pumpWidget(host(const MoboCheckbox(value: true)));

      await tester.tap(find.byType(MoboCheckbox));
      await tester.pump();

      expect(
        find.descendant(
          of: find.byType(MoboCheckbox),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );
    });

    testWidgets('enabled: false dims it and ignores taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          MoboCheckbox(value: false, enabled: false, onChanged: (_) => taps++),
        ),
      );

      await tester.tap(find.byType(MoboCheckbox));
      expect(taps, 0);

      final dim = tester.widget<Opacity>(
        find.descendant(
          of: find.byType(MoboCheckbox),
          matching: find.byType(Opacity),
        ),
      );
      expect(dim.opacity, 0.6);
    });

    testWidgets('tapTargetSize widens the hit area, not the box', (
      tester,
    ) async {
      var taps = 0;
      await tester.pumpWidget(
        host(
          MoboCheckbox(
            value: false,
            tapTargetSize: 48,
            onChanged: (_) => taps++,
          ),
        ),
      );

      expect(tester.getSize(find.byType(MoboCheckbox)), const Size(48, 48));
      final box = tester.getRect(find.byType(AnimatedContainer));
      expect(box.size, const Size(24, 24));

      // 18 dp off the box's centre: outside the 24 dp box, inside the 48.
      await tester.tapAt(box.center + const Offset(18, 0));
      expect(taps, 1);
    });
  });

  group('MoboCheckboxField', () {
    Widget host(Widget child, {double width = 400}) => MaterialApp(
      theme: ThemeData(primaryColor: primary),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            child: Padding(padding: const EdgeInsets.all(20), child: child),
          ),
        ),
      ),
    );

    testWidgets('label at the start, box at the far end', (tester) async {
      await tester.pumpWidget(
        host(
          MoboCheckboxField(label: 'Active', value: true, onChanged: (_) {}),
        ),
      );

      final row = tester.getRect(find.byType(MoboCheckboxField));
      final label = tester.getRect(find.text('Active'));
      final box = tester.getRect(find.byType(AnimatedContainer));

      expect(label.left, row.left, reason: 'label flush left');
      expect(box.right, row.right, reason: 'box flush right');
      expect(box.left, greaterThan(label.right));
      expect(box.size, const Size(24, 24));
      expect(row.height, greaterThanOrEqualTo(48), reason: 'a comfortable tap');
    });

    testWidgets('the whole row toggles, label and empty space included', (
      tester,
    ) async {
      final seen = <bool>[];
      await tester.pumpWidget(
        host(
          MoboCheckboxField(label: 'Active', value: false, onChanged: seen.add),
        ),
      );

      await tester.tap(find.text('Active'));
      final row = tester.getRect(find.byType(MoboCheckboxField));
      await tester.tapAt(row.center + const Offset(40, 0)); // empty middle
      await tester.tap(find.byType(AnimatedContainer));

      expect(seen, [true, true, true]);
    });

    testWidgets('a null onChanged disables and dims the row', (tester) async {
      await tester.pumpWidget(
        host(
          const MoboCheckboxField(
            label: 'Active',
            value: true,
            onChanged: null,
          ),
        ),
      );

      final dim = tester.widget<Opacity>(
        find
            .descendant(
              of: find.byType(MoboCheckboxField),
              matching: find.byType(Opacity),
            )
            .first,
      );
      expect(dim.opacity, 0.6);
    });

    testWidgets('is announced as a checkbox with its label and state', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        host(
          MoboCheckboxField(
            label: 'Can be Sold',
            value: true,
            onChanged: (_) {},
          ),
        ),
      );

      expect(
        tester.getSemantics(find.byType(MoboCheckboxField)),
        matchesSemantics(
          label: 'Can be Sold',
          hasCheckedState: true,
          isChecked: true,
          hasEnabledState: true,
          isEnabled: true,
          hasTapAction: true,
        ),
      );
      handle.dispose();
    });

    testWidgets('renders in the real app theme, light and dark', (
      tester,
    ) async {
      for (final theme in [AppTheme.lightTheme, AppTheme.darkTheme]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: Scaffold(
              body: MoboCheckboxField(
                label: 'Is Company',
                value: false,
                onChanged: (_) {},
              ),
            ),
          ),
        );
        expect(find.text('Is Company'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });
}
