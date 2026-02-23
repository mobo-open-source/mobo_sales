import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/last_opened_provider.dart';
import 'dart:convert';

void main() {
  late LastOpenedProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('LastOpenedProvider Tests', () {
    test('Initial state is empty', () async {
      provider = LastOpenedProvider();
      await Future.delayed(Duration.zero);

      expect(provider.items, isEmpty);
      expect(provider.lastOpened, isNull);
    });

    test('trackQuotationAccess adds item and saves', () async {
      provider = LastOpenedProvider();
      await Future.delayed(Duration.zero);

      await provider.trackQuotationAccess(
        quotationId: '1',
        quotationName: 'Q1',
        customerName: 'C1',
        quotationData: {'id': 1},
      );

      expect(provider.items.length, 1);
      expect(provider.items.first.id, 'quotation_1');
      expect(provider.items.first.title, 'Q1');
      expect(provider.items.first.type, 'quotation');

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('last_opened_items');
      expect(jsonString, isNotNull);
      final list = json.decode(jsonString!) as List;
      expect(list.length, 1);
      expect(list.first['id'], 'quotation_1');
    });

    test('Adding duplicate item moves it to top', () async {
      provider = LastOpenedProvider();
      await Future.delayed(Duration.zero);

      await provider.trackQuotationAccess(
        quotationId: '1',
        quotationName: 'Q1',
        customerName: 'C1',
      );

      await provider.trackInvoiceAccess(
        invoiceId: '2',
        invoiceName: 'INV2',
        customerName: 'C2',
      );

      expect(provider.items.first.id, 'invoice_2');
      expect(provider.items.length, 2);

      await provider.trackQuotationAccess(
        quotationId: '1',
        quotationName: 'Q1',
        customerName: 'C1',
      );

      expect(provider.items.first.id, 'quotation_1');
      expect(provider.items.length, 2);
    });

    test('Items list filters excluded types', () async {
      provider = LastOpenedProvider();
      await Future.delayed(Duration.zero);

      await provider.trackQuotationAccess(
        quotationId: '1',
        quotationName: 'Q1',
        customerName: 'C1',
      );

      await provider.trackPageAccess(
        pageId: 'settings',
        pageTitle: 'Settings',
        pageSubtitle: '',
        route: '/settings',
        icon: Icons.settings,
      );

      expect(provider.items.any((i) => i.id == 'page_settings'), false);
    });

    test('clearItems removes all items', () async {
      provider = LastOpenedProvider();
      await Future.delayed(Duration.zero);

      await provider.trackQuotationAccess(
        quotationId: '1',
        quotationName: 'Q1',
        customerName: 'C1',
      );
      expect(provider.items, isNotEmpty);

      await provider.clearItems();
      expect(provider.items, isEmpty);

      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString('last_opened_items');
      final list = json.decode(jsonString!) as List;
      expect(list, isEmpty);
    });
  });
}
