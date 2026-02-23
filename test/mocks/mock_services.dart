import 'package:mocktail/mocktail.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/services/quotation_service.dart';
import 'package:mobo_sales/services/permission_service.dart';
import 'package:mobo_sales/services/field_validation_service.dart';
import 'package:mobo_sales/services/auth_service.dart';
import 'package:mobo_sales/services/product_service.dart';
import 'package:mobo_sales/services/customer_service.dart';
import 'package:mobo_sales/services/stock_service.dart';
import 'package:mobo_sales/services/invoice_service.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:mobo_sales/services/currency_service.dart';
import 'package:mobo_sales/services/settings_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:mobo_sales/services/invoice_details_service.dart';

class MockAuthService extends Mock implements AuthService {}

class MockOdooSessionManager extends Mock implements OdooSessionManager {}

class MockSessionService extends Mock implements SessionService {}

class MockQuotationService extends Mock implements QuotationService {}

class MockPermissionService extends Mock implements PermissionService {}

class MockFieldValidationService extends Mock
    implements FieldValidationService {}

class MockOdooClient extends Mock implements OdooClient {}

class MockConnectivityService extends Mock implements ConnectivityService {}

class MockProductService extends Mock implements ProductService {}

class MockCustomerService extends Mock implements CustomerService {}

class MockStockService extends Mock implements StockService {}

class MockInvoiceService extends Mock implements InvoiceService {}

class MockConnectivity extends Mock implements Connectivity {}

class MockCurrencyService extends Mock implements CurrencyService {}

class MockSettingsService extends Mock implements SettingsService {}

class MockInvoiceDetailsService extends Mock implements InvoiceDetailsService {}
