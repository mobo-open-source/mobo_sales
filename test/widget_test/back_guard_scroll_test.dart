import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mobo_sales/utils/data_loss_warning_mixin.dart';

/// A form must not jump back to the top, or lose what is under it, when the
/// user makes the first change. On Android the form is wrapped in a back guard;
/// the wrapper used to appear only once the form had unsaved changes, which
/// built everything under it again from scratch.
class _Form extends StatefulWidget {
  const _Form();

  @override
  State<_Form> createState() => _FormState();
}

class _FormState extends State<_Form> with DataLossWarningMixin<_Form> {
  final scroll = ScrollController();
  bool dirty = false;

  @override
  bool get hasUnsavedData => dirty;

  /// Poses as Android, where the guard is used.
  @override
  bool get needsWillPopScope => true;

  @override
  void dispose() {
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final popChild = PopScope(
      canPop: !hasUnsavedData,
      child: Scaffold(
        body: SingleChildScrollView(
          controller: scroll,
          child: Column(
            children: [
              for (var i = 0; i < 40; i++)
                SizedBox(height: 80, child: Text('row $i')),
              _Counter(key: const ValueKey('counter')),
            ],
          ),
        ),
      ),
    );
    return withBackGuard(popChild);
  }
}

/// Something with state of its own, which a rebuild from scratch would lose.
class _Counter extends StatefulWidget {
  const _Counter({super.key});

  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => TextButton(
    onPressed: () => setState(() => taps++),
    child: Text('taps $taps'),
  );
}

void main() {
  testWidgets('the first change to a form leaves its scroll position and its '
      'fields alone', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Form()));
    final state = tester.state<_FormState>(find.byType(_Form));

    state.scroll.jumpTo(1500);
    await tester.pump();
    await tester.ensureVisible(find.text('taps 0'));
    await tester.tap(find.text('taps 0'));
    await tester.pump();
    final offsetBefore = state.scroll.offset;
    expect(offsetBefore, greaterThan(1000));
    expect(find.text('taps 1'), findsOneWidget);

    // The user changes something: the form now has unsaved data.
    state.setState(() => state.dirty = true);
    await tester.pump();

    expect(state.hasUnsavedData, isTrue);
    expect(
      state.scroll.offset,
      offsetBefore,
      reason: 'did not jump to the top',
    );
    expect(
      find.text('taps 1'),
      findsOneWidget,
      reason: 'what is under the guard was not built again',
    );

    // And back to nothing to save: still no rebuild.
    state.setState(() => state.dirty = false);
    await tester.pump();
    expect(state.scroll.offset, offsetBefore);
    expect(find.text('taps 1'), findsOneWidget);
  });

  testWidgets('the guard still lets a clean form go back, and asks a changed '
      'one', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: _Form()));
    final state = tester.state<_FormState>(find.byType(_Form));

    expect(await state.handleWillPop(), isTrue, reason: 'nothing to lose');
  });
}
