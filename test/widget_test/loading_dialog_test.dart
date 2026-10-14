import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/loading_dialog.dart';

void main() {
  late BuildContext host;

  Future<void> pumpHost(WidgetTester tester, {ThemeData? theme}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? ThemeData.light(),
        home: Builder(
          builder: (context) {
            host = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
  }

  final dots = find.byWidgetPredicate(
    (w) => w.runtimeType.toString() == 'FourRotatingDots',
  );

  testWidgets('is the card: dots in a pale circle, a title, a line under it', (
    tester,
  ) async {
    await pumpHost(tester);
    LoadingDialog.show(
      host,
      message: 'Creating quotation...',
      subtitle: 'Please wait while we create your quotation.',
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Creating quotation...'), findsOneWidget);
    expect(
      find.text('Please wait while we create your quotation.'),
      findsOneWidget,
    );
    expect(dots, findsOneWidget);

    // The dots sit in a circle, tinted with the brand colour.
    final circle = find.ancestor(
      of: dots,
      matching: find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).shape == BoxShape.circle,
      ),
    );
    expect(circle, findsOneWidget);
    final tint =
        (tester.widget<Container>(circle).decoration as BoxDecoration).color!;
    expect(tint.a, closeTo(0.08, 0.01));

    // The title is above the line, and bolder.
    final title = tester.widget<Text>(find.text('Creating quotation...'));
    expect(title.style!.fontSize, 18);
    expect(title.style!.fontWeight, FontWeight.w600);
    expect(
      tester.getTopLeft(find.text('Creating quotation...')).dy,
      lessThan(
        tester
            .getTopLeft(
              find.text('Please wait while we create your quotation.'),
            )
            .dy,
      ),
    );
  });

  testWidgets('framed like a dialog: white, rounded, at least 280 wide', (
    tester,
  ) async {
    await pumpHost(tester);
    LoadingDialog.show(host);
    await tester.pump(const Duration(milliseconds: 400));

    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    expect(dialog.backgroundColor, Colors.white);
    expect(
      dialog.shape,
      RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
    expect(
      tester.getSize(find.byType(Dialog)).width,
      greaterThanOrEqualTo(280),
    );
  });

  testWidgets('has a default title and line, and the line can be left out', (
    tester,
  ) async {
    await pumpHost(tester);
    LoadingDialog.show(host);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Processing...'), findsOneWidget);
    expect(find.text('Please wait a moment.'), findsOneWidget);

    Navigator.pop(host);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    LoadingDialog.show(host, message: 'Saving...', subtitle: null);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('Saving...'), findsOneWidget);
    expect(find.text('Please wait a moment.'), findsNothing);
  });

  testWidgets('blocks the screen and the back button; the caller closes it', (
    tester,
  ) async {
    await pumpHost(tester);
    var closed = false;
    LoadingDialog.show(host).then((_) => closed = true);
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tapAt(const Offset(4, 4));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoadingDialog), findsOneWidget, reason: 'barrier');

    await tester.binding.handlePopRoute();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoadingDialog), findsOneWidget, reason: 'back button');

    Navigator.pop(host);
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(LoadingDialog), findsNothing);
    expect(closed, isTrue);
  });

  testWidgets('dark theme gets the dark card; long text wraps on a small '
      'phone without overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    await pumpHost(tester, theme: ThemeData.dark());
    LoadingDialog.show(
      host,
      message: 'Switching to a very long account name that has to wrap...',
      subtitle:
          'Please wait while we switch to the other account and reload '
          'everything that depends on it.',
    );
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      Colors.grey[900],
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('LoadingCard alone brings its own white frame over a dimmed '
      'page', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              Container(
                color: Colors.black54,
                child: const Center(
                  child: LoadingCard(message: 'Processing...'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Processing...'), findsOneWidget);
    final frame = tester.widget<Material>(
      find
          .descendant(
            of: find.byType(LoadingCard),
            matching: find.byType(Material),
          )
          .first,
    );
    expect(frame.color, Colors.white);
    expect(
      tester.getSize(find.byType(LoadingCard)).width,
      greaterThanOrEqualTo(280),
    );
  });

  group('LoadingDialogHandle', () {
    testWidgets('closes its dialog, and closing again does nothing', (
      tester,
    ) async {
      await pumpHost(tester);
      final handle = LoadingDialog.open(host, message: 'Saving...');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saving...'), findsOneWidget);
      expect(handle.isOpen, isTrue);

      handle.close();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Saving...'), findsNothing);
      expect(handle.isOpen, isFalse);

      handle.close();
      handle.close();
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(
        find.byType(Scaffold),
        findsOneWidget,
        reason: 'the page is there',
      );
    });

    testWidgets('a second close after the screen was popped leaves the screen '
        'underneath alone (the edit-quotation bug)', (tester) async {
      bool? result;
      late LoadingDialogHandle handle;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (home) => Scaffold(
              body: ElevatedButton(
                onPressed: () async => Navigator.push(
                  home,
                  MaterialPageRoute(
                    builder: (details) => Scaffold(
                      body: Center(
                        child: ElevatedButton(
                          onPressed: () async {
                            result = await Navigator.push<bool>(
                              details,
                              MaterialPageRoute(
                                builder: (edit) => Scaffold(
                                  body: ElevatedButton(
                                    onPressed: () async {
                                      handle = LoadingDialog.open(edit);
                                      await WidgetsBinding.instance.endOfFrame;
                                      try {
                                        // The success path: close the card,
                                        // close the edit screen with a result.
                                        handle.close();
                                        Navigator.pop(edit, true);
                                      } finally {
                                        // The old `finally` popped again here.
                                        handle.close();
                                      }
                                    },
                                    child: const Text('SAVE'),
                                  ),
                                ),
                              ),
                            );
                          },
                          child: const Text('EDIT'),
                        ),
                      ),
                    ),
                  ),
                ),
                child: const Text('OPEN'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('OPEN'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('EDIT'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('SAVE'));
      await tester.pumpAndSettle();

      expect(result, isTrue, reason: 'the details got the edit\'s result');
      expect(
        find.text('EDIT'),
        findsOneWidget,
        reason: 'and is still on screen to refresh and say "updated"',
      );
    });

    testWidgets('closes only itself when something else was pushed above it', (
      tester,
    ) async {
      await pumpHost(tester);
      final handle = LoadingDialog.open(host, message: 'Working...');
      await tester.pump(const Duration(milliseconds: 400));
      showDialog<void>(
        context: host,
        builder: (_) => const AlertDialog(title: Text('ON TOP')),
      );
      await tester.pump(const Duration(milliseconds: 400));

      handle.close();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Working...'), findsNothing);
      expect(find.text('ON TOP'), findsOneWidget, reason: 'untouched');
    });
  });
}
