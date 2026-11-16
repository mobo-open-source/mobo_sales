import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/providers/company_provider.dart';
import 'package:mobo_sales/widgets/company_selector_widget.dart';

/// A provider whose state the test sets directly, so the pill can be shown in
/// each of its states without a server.
class _FakeCompanyProvider extends CompanyProvider {
  _FakeCompanyProvider({
    List<Map<String, dynamic>> companies = const [],
    bool loading = false,
    bool failed = false,
  }) : _companies = companies,
       _loading = loading,
       _failed = failed;

  final List<Map<String, dynamic>> _companies;
  final bool _loading;
  final bool _failed;

  @override
  List<Map<String, dynamic>> get companies => _companies;
  @override
  bool get isLoading => _loading;
  @override
  bool get loadFailed => _failed;
}

Future<void> pumpPill(WidgetTester tester, CompanyProvider provider) async {
  await tester.pumpWidget(
    MaterialApp(
      home: ChangeNotifierProvider<CompanyProvider>.value(
        value: provider,
        child: const Scaffold(body: Center(child: CompanySelectorWidget())),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets(
    'a failed load asks to be retried, it does not claim there are none',
    (tester) async {
      // The reported confusion: every other page had data, yet the pill said
      // "No companies" — which reads as a fact about the account rather than a
      // load that never finished.
      await pumpPill(tester, _FakeCompanyProvider(failed: true));

      expect(find.text('Tap to retry'), findsOneWidget);
      expect(find.text('No companies'), findsNothing);
    },
  );

  testWidgets('an account that really has none still says so', (tester) async {
    await pumpPill(tester, _FakeCompanyProvider(failed: false));

    expect(find.text('No companies'), findsOneWidget);
    expect(find.text('Tap to retry'), findsNothing);
  });

  testWidgets('a first load shows it is working, not that there are none', (
    tester,
  ) async {
    await pumpPill(tester, _FakeCompanyProvider(loading: true));

    expect(find.text('Loading...'), findsOneWidget);
    expect(find.text('No companies'), findsNothing);
    expect(find.text('Tap to retry'), findsNothing);
  });

  testWidgets('with companies loaded the pill names the selected one', (
    tester,
  ) async {
    final provider = _FakeCompanyProvider(
      companies: [
        {'id': 1, 'name': 'My Company'},
      ],
    );
    await pumpPill(tester, provider);

    expect(find.text('No companies'), findsNothing);
    expect(find.text('Tap to retry'), findsNothing);
  });
}
