import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/screens/login/login_layout.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  Future<void> pumpField(WidgetTester tester, List<String> items) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: LoginDropdownField(
              hint: 'Select database',
              value: null,
              items: items,
              onChanged: (_) {},
              validator: (_) => null,
            ),
          ),
        ),
      ),
    );
  }

  Future<Material> openMenu(WidgetTester tester) async {
    await tester.tap(find.byType(LoginDropdownField));
    // The field waits for the keyboard to go before it opens the menu.
    await tester.pump(const Duration(milliseconds: 300));
    // Mid-animation: the panel is still growing.
    await tester.pump(const Duration(milliseconds: 40));
    return tester.widget<Material>(
      find
          .ancestor(
            of: find.byType(PopupMenuItem<String>).first,
            matching: find.byType(Material),
          )
          .first,
    );
  }

  testWidgets('the database menu clips its rows to the panel while it opens', (
    tester,
  ) async {
    await pumpField(tester, [
      'Demo',
      'No_db',
      'barcode',
      'barcode_enterprice_19',
      'help_desk_19',
    ]);
    final panel = await openMenu(tester);
    expect(
      panel.clipBehavior,
      Clip.antiAlias,
      reason: 'unclipped rows hang out of the shrinking panel',
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the protocol menu clips its rows to the panel too', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(24),
            child: LoginUrlTextField(
              controller: TextEditingController(),
              hint: 'Server address',
              prefixIcon: Icons.dns,
              selectedProtocol: 'http://',
              onProtocolChanged: (_) {},
              validator: (_) => null,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('http://'));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump(const Duration(milliseconds: 40));
    final panel = tester.widget<Material>(
      find
          .ancestor(
            of: find.byType(PopupMenuItem<String>).first,
            matching: find.byType(Material),
          )
          .first,
    );
    expect(panel.clipBehavior, Clip.antiAlias);
  });
}
