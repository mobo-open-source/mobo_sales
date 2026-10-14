import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/data_loss_warning_mixin.dart';

/// A screen that is "dirty" until its form has been reset, as an edit form is
/// when it measures unsaved work against what it loaded.
class _Probe extends StatefulWidget {
  const _Probe({super.key});

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> with DataLossWarningMixin {
  /// Stays true even after [onConfirmLeave]: the reset form still differs from
  /// the record it loaded, which is exactly the case the mixin must survive.
  @override
  bool get hasUnsavedData => true;

  int resets = 0;

  @override
  void onConfirmLeave() => resets++;

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  Widget host(GlobalKey<_ProbeState> key) => MaterialApp(
    home: Scaffold(body: _Probe(key: key)),
  );

  testWidgets('asks once, then lets the second back handler through', (
    tester,
  ) async {
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(host(key));

    // The first handler (WillPopScope on Android) asks.
    var first = Future<bool>.value(false);
    first = key.currentState!.handleWillPop();
    await tester.pumpAndSettle();
    expect(find.text('Leave'), findsOneWidget);
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    expect(await first, isTrue);
    expect(key.currentState!.resets, 1);

    // The second (PopScope, straight after) must not ask again.
    final second = await key.currentState!.handleWillPop();
    await tester.pumpAndSettle();
    expect(find.text('Leave'), findsNothing, reason: 'no second dialog');
    expect(second, isTrue);
    expect(key.currentState!.resets, 1, reason: 'reset only once');
  });

  testWidgets('choosing Stay keeps asking', (tester) async {
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(host(key));

    for (var i = 0; i < 2; i++) {
      final result = key.currentState!.handleWillPop();
      await tester.pumpAndSettle();
      expect(find.text('Stay'), findsOneWidget, reason: 'asked again, ask #$i');
      await tester.tap(find.text('Stay'));
      await tester.pumpAndSettle();
      expect(await result, isFalse);
    }
    expect(key.currentState!.resets, 0);
  });

  testWidgets('handleNavigation also asks only once', (tester) async {
    final key = GlobalKey<_ProbeState>();
    await tester.pumpWidget(host(key));

    var navigated = 0;
    final first = key.currentState!.handleNavigation(() => navigated++);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Leave'));
    await tester.pumpAndSettle();
    await first;
    expect(navigated, 1);

    await key.currentState!.handleNavigation(() => navigated++);
    await tester.pumpAndSettle();
    expect(find.text('Leave'), findsNothing);
    expect(navigated, 2);
  });
}
