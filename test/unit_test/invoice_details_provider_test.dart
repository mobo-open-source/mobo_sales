import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/providers/invoice_details_provider_enterprise.dart';
import 'package:mobo_sales/services/invoice_details_service.dart';
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

    /// Stubs the reads that follow a post, which the provider always runs.
    void stubRefreshAfterPost({String state = 'posted'}) {
      when(
        () => mockService.fetchInvoiceDetails(1),
      ).thenAnswer((_) async => {'state': state});
      when(
        () => mockService.fetchPartnerDetails(any()),
      ).thenAnswer((_) async => {});
      when(
        () => mockService.fetchInvoiceLines(any()),
      ).thenAnswer((_) async => []);
    }

    /// Grants write access and, unless [inInvoicingGroup] says otherwise,
    /// Odoo's Invoicing group — both of which posting needs.
    void stubPostPermissions({bool inInvoicingGroup = true}) {
      when(
        () => mockPermissionService.canWrite('account.move'),
      ).thenAnswer((_) async => true);
      when(
        () => mockPermissionService.hasGroup(kInvoicingGroup),
      ).thenAnswer((_) async => inInvoicingGroup);
    }

    test('postInvoice success', () async {
      provider.setInvoiceData({'state': 'draft'});
      stubPostPermissions();
      when(() => mockService.postInvoice(1)).thenAnswer((_) async => null);
      stubRefreshAfterPost();

      final result = await provider.postInvoice(mockContext, '1');

      expect(result, true);
      expect(provider.errorMessage, isEmpty);
      verify(() => mockService.postInvoice(1)).called(1);
    });

    test('postInvoice is refused without the Invoicing group', () async {
      // Odoo's `_post` needs `account.group_account_invoice` as well as write
      // access to the model, and raises an AccessError without it. The app
      // used to call anyway and report a bare "Access Denied".
      provider.setInvoiceData({'state': 'draft'});
      stubPostPermissions(inInvoicingGroup: false);

      final result = await provider.postInvoice(mockContext, '1');

      expect(result, false);
      expect(provider.errorMessage, kInvoicingGroupMissingMessage);
      expect(provider.errorMessage, contains('Invoicing'));
      verifyNever(() => mockService.postInvoice(any()));
    });

    test('a wizard Odoo returns is not reported as a confirmation', () async {
      // `action_post` answers with a window action when it wants something
      // confirmed first, and the invoice stays a draft. The app used to
      // ignore the return value and announce success.
      provider.setInvoiceData({'state': 'draft'});
      stubPostPermissions();
      when(
        () => mockService.postInvoice(1),
      ).thenAnswer((_) async => 'Confirm Entries');
      stubRefreshAfterPost(state: 'draft');

      final result = await provider.postInvoice(mockContext, '1');

      expect(result, false);
      expect(provider.errorMessage, contains('Confirm Entries'));
      expect(provider.errorMessage, contains('in Odoo'));
      verify(() => mockService.postInvoice(1)).called(1);
      expect(
        provider.invoiceState,
        'draft',
        reason: 'the page still shows what the invoice actually is',
      );
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
