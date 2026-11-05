import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/widgets/voice_search_dialog.dart';

/// A recognizer the test drives by hand.
class FakeSpeechEngine implements SpeechEngine {
  FakeSpeechEngine({this.available = true});

  final bool available;
  void Function(String status)? onStatus;
  void Function(String error)? onError;
  void Function(String words, bool isFinal)? onResult;
  int listens = 0;
  int cancels = 0;

  @override
  Future<bool> initialize({
    required void Function(String status) onStatus,
    required void Function(String error) onError,
  }) async {
    this.onStatus = onStatus;
    this.onError = onError;
    return available;
  }

  @override
  Future<void> listen({
    required void Function(String words, bool isFinal) onResult,
  }) async {
    listens++;
    this.onResult = onResult;
    onStatus?.call('listening');
  }

  @override
  Future<void> cancel() async => cancels++;

  void hear(String words, {bool isFinal = false}) =>
      onResult?.call(words, isFinal);
}

String? returned;
bool closed = false;

Future<void> open(WidgetTester tester, FakeSpeechEngine engine) async {
  returned = null;
  closed = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () async {
              returned = await showVoiceSearchDialog(context, engine: engine);
              closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Finder searchButton() => find.widgetWithText(ElevatedButton, 'Search');

void main() {
  testWidgets('tapping the mic opens a pop-up that listens', (tester) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);

    expect(find.text('Voice Search'), findsOneWidget);
    expect(find.text('Listening...'), findsOneWidget);
    expect(find.text('Recognized Text:'), findsOneWidget);
    expect(engine.listens, 1);
  });

  testWidgets('the words appear in the pop-up as they are spoken', (
    tester,
  ) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);

    engine.hear('apple');
    await tester.pump();
    expect(find.text('apple'), findsOneWidget);

    engine.hear('apple pie');
    await tester.pump();
    expect(find.text('apple pie'), findsOneWidget);
    // Nothing is returned, and the pop-up stays, until Search is tapped.
    expect(closed, isFalse);
    expect(find.text('Voice Search'), findsOneWidget);
  });

  testWidgets('Search is disabled until something has been heard', (
    tester,
  ) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);
    expect(tester.widget<ElevatedButton>(searchButton()).onPressed, isNull);

    engine.hear('shoes');
    await tester.pump();
    expect(tester.widget<ElevatedButton>(searchButton()).onPressed, isNotNull);
  });

  testWidgets('the search runs only when Search is tapped', (tester) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);

    engine.hear('apple pie', isFinal: true);
    // The recognizer finishing on its own does not search or close anything.
    engine.onStatus?.call('notListening');
    engine.onStatus?.call('done');
    await tester.pump();
    expect(closed, isFalse);
    expect(find.text('Finished listening'), findsOneWidget);
    expect(find.text('apple pie'), findsOneWidget);

    await tester.tap(searchButton());
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(returned, 'apple pie');
  });

  testWidgets('Search while still listening returns the words so far', (
    tester,
  ) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);
    engine.hear('laptop');
    await tester.pump();

    await tester.tap(searchButton());
    await tester.pumpAndSettle();
    expect(returned, 'laptop');
    expect(engine.cancels, greaterThan(0));
  });

  testWidgets('Cancel returns nothing', (tester) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);
    engine.hear('apple pie');
    await tester.pump();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(closed, isTrue);
    expect(returned, isNull);
  });

  testWidgets('nothing heard shows why and offers Try Again', (tester) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);

    engine.onError?.call('error_speech_timeout');
    engine.onStatus?.call('notListening');
    await tester.pump();
    expect(find.text('Nothing heard'), findsOneWidget);
    expect(find.textContaining('No speech heard'), findsOneWidget);
    expect(closed, isFalse);

    await tester.tap(find.widgetWithText(ElevatedButton, 'Try Again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(engine.listens, 2);
    expect(find.text('Listening...'), findsOneWidget);
  });

  testWidgets('Speak again clears the words and listens again', (tester) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);
    engine.hear('wrong words', isFinal: true);
    engine.onStatus?.call('done');
    await tester.pump();

    await tester.tap(find.text('Speak again'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('wrong words'), findsNothing);
    expect(engine.listens, 2);

    engine.hear('right words');
    await tester.pump();
    await tester.tap(searchButton());
    await tester.pumpAndSettle();
    expect(returned, 'right words');
  });

  testWidgets('an error after words were heard does not wipe them', (
    tester,
  ) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);
    engine.hear('apple pie', isFinal: true);
    engine.onError?.call('error_no_match');
    await tester.pump();
    expect(find.text('apple pie'), findsOneWidget);
    expect(find.textContaining('understand'), findsNothing);
  });

  testWidgets('a device without recognition says so', (tester) async {
    final engine = FakeSpeechEngine(available: false);
    await open(tester, engine);
    expect(find.textContaining('not available on this device'), findsOneWidget);
    expect(engine.listens, 0);
  });

  testWidgets('a second pop-up gets its own words, not the first one\'s', (
    tester,
  ) async {
    final engine = FakeSpeechEngine();
    await open(tester, engine);
    engine.hear('first');
    await tester.pump();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('first'), findsNothing);
    engine.hear('second');
    await tester.pump();
    await tester.tap(searchButton());
    await tester.pumpAndSettle();
    expect(returned, 'second');
  });
}
