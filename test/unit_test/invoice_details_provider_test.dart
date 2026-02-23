import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/invoice_details_provider_enterprise.dart';
import '../mocks/mock_services.dart';

class FakeBuildContext extends Fake implements BuildContext {}

void main() {
  late InvoiceDetailsProvider provider;
  late MockInvoiceDetailsService mockService;
  late MockPermissionService mockPermissionService;
  late BuildContext mockContext;

  setUpAll(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  setUp(() {
    mockService = MockInvoiceDetailsService();
    mockPermissionService = MockPermissionService();
    mockContext = FakeBuildContext();
    provider = InvoiceDetailsProvider(
      invoiceDetailsService: mockService,
      permissionService: mockPermissionService,
    );
  });

  group('InvoiceDetailsProvider Tests', () {
    test('Initial state should be correct', () {
      expect(provider.invoiceData, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.isProcessing, false);
      expect(provider.errorMessage, isEmpty);
      expect(provider.invoiceState, 'draft');
      expect(provider.invoiceNumber, 'Draft');
    });

    test('resetState should clear all data', () {
      provider.setInvoiceData({'name': 'INV/001', 'state': 'posted'});
      expect(provider.invoiceData, isNotEmpty);

      provider.resetState();

      expect(provider.invoiceData, isEmpty);
      expect(provider.isLoading, false);
      expect(provider.errorMessage, isEmpty);
    });

    test('fetchInvoiceDetails success updates state', () async {
      final invoiceData = {
        'id': 1,
        'name': 'INV/2023/001',
        'state': 'posted',
        'amount_total': 100.0,
        'partner_id': [1, 'Customer A'],
        'invoice_line_ids': [10, 11],
      };

      when(
        () => mockService.fetchInvoiceDetails(1),
      ).thenAnswer((_) async => invoiceData);

      when(
        () => mockService.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockService.fetchInvoiceLines(any()),
      ).thenAnswer((_) async => []);

      await provider.fetchInvoiceDetails(mockContext, '1');

      expect(provider.isLoading, false);
      expect(provider.errorMessage, isEmpty);
      expect(provider.invoiceData['name'], 'INV/2023/001');
      expect(provider.invoiceState, 'posted');
      verify(() => mockService.fetchInvoiceDetails(1)).called(1);
    });

    test('fetchInvoiceDetails failure sets error', () async {
      when(
        () => mockService.fetchInvoiceDetails(1),
      ).thenThrow(const SocketException('No Internet'));

      await provider.fetchInvoiceDetails(mockContext, '1');

      expect(provider.isLoading, false);
      expect(provider.errorMessage, contains('Connection Error'));
    });

    test('postInvoice success', () async {
      provider.setInvoiceData({'state': 'draft'});
      when(
        () => mockPermissionService.canWrite('account.move'),
      ).thenAnswer((_) async => true);
      when(() => mockService.postInvoice(1)).thenAnswer((_) async {});

      when(
        () => mockService.fetchInvoiceDetails(1),
      ).thenAnswer((_) async => {'state': 'posted'});
      when(
        () => mockService.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockService.fetchInvoiceLines(any()),
      ).thenAnswer((_) async => []);

      final result = await provider.postInvoice(mockContext, '1');

      expect(result, true);
      verify(() => mockService.postInvoice(1)).called(1);
    });

    test('postInvoice fails if not draft', () async {
      provider.setInvoiceData({'state': 'posted'});

      final result = await provider.postInvoice(mockContext, '1');

      expect(result, false);
      expect(provider.errorMessage, contains("must be in 'draft' state"));
      verifyNever(() => mockService.postInvoice(any()));
    });

    test('resetToDraft success', () async {
      provider.setInvoiceData({'state': 'cancel'});
      when(
        () => mockPermissionService.canWrite('account.move'),
      ).thenAnswer((_) async => true);
      when(() => mockService.resetToDraft(1)).thenAnswer((_) async {});

      when(
        () => mockService.fetchInvoiceDetails(1),
      ).thenAnswer((_) async => {'state': 'draft'});
      when(
        () => mockService.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockService.fetchInvoiceLines(any()),
      ).thenAnswer((_) async => []);

      final result = await provider.resetToDraft(mockContext, '1');

      expect(result, true);
      verify(() => mockService.resetToDraft(1)).called(1);
    });

    test('cancelInvoice success', () async {
      provider.setInvoiceData({'state': 'posted'});
      when(
        () => mockPermissionService.canWrite('account.move'),
      ).thenAnswer((_) async => true);
      when(() => mockService.cancelInvoice(1)).thenAnswer((_) async {});

      when(
        () => mockService.fetchInvoiceDetails(1),
      ).thenAnswer((_) async => {'state': 'cancel'});
      when(
        () => mockService.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockService.fetchInvoiceLines(any()),
      ).thenAnswer((_) async => []);

      final result = await provider.cancelInvoice(mockContext, '1');

      expect(result, true);
      verify(() => mockService.cancelInvoice(1)).called(1);
    });

    test('deleteInvoice success', () async {
      when(
        () => mockPermissionService.canUnlink('account.move'),
      ).thenAnswer((_) async => true);
      when(() => mockService.deleteInvoice(1)).thenAnswer((_) async {});

      final result = await provider.deleteInvoice(mockContext, '1');

      expect(result, true);
      verify(() => mockService.deleteInvoice(1)).called(1);
    });
  });
}
