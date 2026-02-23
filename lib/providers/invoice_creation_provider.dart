import 'dart:async';
import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'currency_provider.dart';
import '../models/contact.dart';
import '../models/payment_term.dart';
import '../models/product.dart';
import '../models/quote.dart';
import '../widgets/custom_snackbar.dart';
import 'package:mobo_sales/services/customer_service.dart';
import 'package:mobo_sales/services/product_service.dart';
import 'package:mobo_sales/services/invoice_service.dart';
import '../services/odoo_error_handler.dart';

class CreateInvoiceProvider with ChangeNotifier {
  bool _isLoading = false;
  bool _isLoadingCustomers = false;
  bool _isLoadingSaleOrders = false;
  bool _isLoadingSaleOrderDetails = false;
  bool _isAddingLine = false;
  String _errorMessage = '';
  String? _loadingError;
  String? _saleOrderLoadingError;
  List<Contact> _customers = [];
  List<Contact> _filteredCustomers = [];
  List<Quote> _saleOrders = [];
  List<Quote> _filteredSaleOrders = [];
  List<PaymentTerm> _paymentTerms = [];
  List<Product> _products = [];
  Contact? _selectedCustomer;
  Quote? _selectedSaleOrder;
  List<Map<String, dynamic>> _saleOrderLines = [];
  List<Map<String, dynamic>> _invoiceLines = [];
  DateTime? _invoiceDate = DateTime.now();
  DateTime? _dueDate = DateTime.now().add(const Duration(days: 30));
  PaymentTerm? _selectedPaymentTerm;
  String _currency = 'USD';
  late NumberFormat _currencyFormat;
  CurrencyProvider? _currencyProvider;
  final TextEditingController _customerSearchController =
      TextEditingController();
  final TextEditingController _saleOrderSearchController =
      TextEditingController();

  final CustomerService _customerService;
  final ProductService _productService;
  final InvoiceService _invoiceService;

  Map<String, dynamic> _taxTotals = {};
  bool _isCalculatingTax = false;

  final Map<String, int> _categoryTotalProducts = {};
  final Map<String, List<Product>> _categoryProducts = {};
  final Map<String, bool> _categoryHasMore = {};
  final Map<String, int> _categoryCurrentPage = {};
  final Map<String, bool> _categoryIsLoadingMore = {};
  final int _pageSize = 20;

  Map<String, dynamic> get taxTotals => _taxTotals;

  bool get isCalculatingTax => _isCalculatingTax;

  List<Quote> get saleOrders => _saleOrders;

  List<Quote> get filteredSaleOrders => _filteredSaleOrders;

  Quote? get selectedSaleOrder => _selectedSaleOrder;

  List<Map<String, dynamic>> get saleOrderLines => _saleOrderLines;

  bool get isLoadingSaleOrders => _isLoadingSaleOrders;

  bool get isLoadingSaleOrderDetails => _isLoadingSaleOrderDetails;

  String? get saleOrderLoadingError => _saleOrderLoadingError;

  bool _isCreatingInvoice = false;
  String? _lastCreatedInvoiceName;
  int? _lastCreatedInvoiceId;

  bool get isCreatingInvoice => _isCreatingInvoice;

  String? get lastCreatedInvoiceName => _lastCreatedInvoiceName;
  int? get lastCreatedInvoiceId => _lastCreatedInvoiceId;

  CreateInvoiceProvider({
    CurrencyProvider? currencyProvider,
    CustomerService? customerService,
    ProductService? productService,
    InvoiceService? invoiceService,
  }) : _customerService = customerService ?? CustomerService.instance,
       _productService = productService ?? ProductService.instance,
       _invoiceService = invoiceService ?? InvoiceService.instance {
    if (currencyProvider != null) {
      _currencyProvider = currencyProvider;
      _currencyFormat = _currencyProvider!.currencyFormat;
      _currency = _currencyProvider!.currency;
      _currencyProvider!.addListener(_onCurrencyChanged);
    } else {
      _currencyFormat = NumberFormat.currency(
        locale: 'en_US',
        decimalDigits: 2,
      );
    }
  }

  void _applyCurrency(String code) {
    final String locale = _currencyProvider?.currencyToLocale[code] ?? 'en_US';
    _currency = code;
    _currencyFormat = NumberFormat.currency(
      locale: locale,
      name: code,
      decimalDigits: 2,
    );
  }

  void _onCurrencyChanged() {
    if (_currencyProvider != null) {
      _currencyFormat = _currencyProvider!.currencyFormat;
      _currency = _currencyProvider!.currency;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _currencyProvider?.removeListener(_onCurrencyChanged);
    _customerSearchController.dispose();
    _saleOrderSearchController.dispose();
    super.dispose();
  }

  bool get isLoading => _isLoading;

  String get errorMessage => _errorMessage;

  List<Contact> get customers => _customers;

  List<Contact> get filteredCustomers => _filteredCustomers;

  List<PaymentTerm> get paymentTerms => _paymentTerms;

  List<Product> get products => _products;

  Contact? get selectedCustomer => _selectedCustomer;

  List<Map<String, dynamic>> get invoiceLines => _invoiceLines;

  DateTime? get invoiceDate => _invoiceDate;

  DateTime? get dueDate => _dueDate;

  PaymentTerm? get selectedPaymentTerm => _selectedPaymentTerm;

  String get currency => _currency;

  NumberFormat get currencyFormat => _currencyFormat;

  bool get isLoadingCustomers => _isLoadingCustomers;

  String? get loadingError => _loadingError;

  TextEditingController get customerSearchController =>
      _customerSearchController;

  TextEditingController get saleOrderSearchController =>
      _saleOrderSearchController;

  bool get isAddingLine => _isAddingLine;

  double get subtotal => _invoiceLines.fold(
    0.0,
    (sum, line) => sum + (line['subtotal'] as double? ?? 0.0),
  );

  double get taxAmount {
    if (_taxTotals.containsKey('amount_tax')) {
      return (_taxTotals['amount_tax'] as num?)?.toDouble() ?? 0.0;
    }
    return 0.0;
  }

  double get total {
    if (_taxTotals.containsKey('amount_total')) {
      return (_taxTotals['amount_total'] as num?)?.toDouble() ?? 0.0;
    }
    return subtotal + taxAmount;
  }

  void setSelectedCustomer(Contact? customer) {
    _selectedCustomer = customer;

    if (customer != null && customer.paymentTermId != null) {
      _setCustomerPaymentTerm(customer.paymentTermId!);
    } else if (customer != null) {}

    if (_selectedSaleOrder == null && _invoiceLines.isNotEmpty) {
      calculateTaxForInvoiceLines();
    }

    notifyListeners();
  }

  void _setCustomerPaymentTerm(int paymentTermId) {
    try {
      final term = _paymentTerms.firstWhere(
        (t) => t.id == paymentTermId,
        orElse: () => PaymentTerm(id: 0, name: ''),
      );
      if (term.id != 0) {
        setSelectedPaymentTerm(term);
      } else {
        _fetchAndSetPaymentTerm(paymentTermId);
      }
    } catch (e) {}
  }

  Future<void> _fetchAndSetPaymentTerm(int paymentTermId) async {
    try {
      final result = await _invoiceService.fetchPaymentTerms();
      final termData = result.firstWhere(
        (t) => t['id'] == paymentTermId,
        orElse: () => {},
      );

      if (termData.isNotEmpty) {
        final term = PaymentTerm(
          id: termData['id'] ?? 0,
          name: termData['name']?.toString() ?? '',
        );

        if (term.id != 0) {
          if (!_paymentTerms.any((t) => t.id == term.id)) {
            _paymentTerms.add(term);
          }
          setSelectedPaymentTerm(term);
        }
      }
    } catch (e) {}
  }

  void clearSelectedCustomer() {
    _selectedCustomer = null;
    _customerSearchController.clear();
    notifyListeners();
  }

  void filterCustomers(String query) {
    if (query.isEmpty) {
      _filteredCustomers = List.from(_customers);
    } else {
      _filteredCustomers = _customers.where((customer) {
        return customer.name.toLowerCase().contains(query.toLowerCase()) ||
            (customer.email?.toLowerCase().contains(query.toLowerCase()) ??
                false) ||
            (customer.phone?.toLowerCase().contains(query.toLowerCase()) ??
                false);
      }).toList();
    }
    notifyListeners();
  }

  void filterSaleOrders(String query) {
    if (query.isEmpty) {
      _filteredSaleOrders = List.from(_saleOrders);
    } else {
      _filteredSaleOrders = _saleOrders.where((order) {
        final orderName = order.name.toLowerCase();
        final partnerName = (order.customerName ?? '').toLowerCase();
        final queryLower = query.toLowerCase();
        return orderName.contains(queryLower) ||
            partnerName.contains(queryLower);
      }).toList();
    }
    notifyListeners();
  }

  Future<Contact?> fetchCustomerById(int partnerId) async {
    try {
      final contact = await _customerService.fetchCustomerDetails(partnerId);
      if (contact != null) {
        if (!_customers.any((c) => c.id == contact.id)) {
          _customers.add(contact);
          _filteredCustomers = List.from(_customers);
        }
        return contact;
      }
      return null;
    } catch (e, stackTrace) {
      log(
        'Error fetching customer by ID $partnerId: $e',
        stackTrace: stackTrace,
      );
      return null;
    }
  }

  Future<void> setSelectedSaleOrder(Quote? saleOrder) async {
    if (saleOrder == null) {
      _selectedSaleOrder = null;
      _saleOrderLines.clear();
      _invoiceLines.clear();
      _selectedCustomer = null;
      _customerSearchController.clear();
      _errorMessage = '';
      notifyListeners();
      return;
    }
    _isLoadingSaleOrderDetails = true;
    _selectedSaleOrder = saleOrder;
    _errorMessage = '';
    notifyListeners();
    try {
      if (saleOrder.id == null) throw Exception('Invalid sale order ID');

      final details = await fetchSaleOrderDetails(saleOrder.id!);
      _selectedSaleOrder = Quote.fromJson({...saleOrder.toJson(), ...details});

      final dynamic currField = _selectedSaleOrder!.extraData?['currency_id'];
      final String? currencyCode = (currField is List && currField.length > 1)
          ? currField[1].toString()
          : null;
      if (currencyCode != null && currencyCode.isNotEmpty) {
        _applyCurrency(currencyCode);
        notifyListeners();
      }

      final partnerId = _selectedSaleOrder!.customerId;
      if (partnerId != null) {
        if (_customers.isEmpty) {
          await fetchCustomers();
        }
        Contact? customer;
        try {
          customer = _customers.firstWhere(
            (c) => c.id == partnerId,
            orElse: () => Contact(id: 0, name: 'Unknown'),
          );
        } catch (e) {}
        if (customer == null || customer.id == 0) {
          _isLoadingCustomers = true;
          notifyListeners();
          customer = await fetchCustomerById(partnerId);
          _isLoadingCustomers = false;
          notifyListeners();
        }
        if (customer != null && customer.id != 0) {
          setSelectedCustomer(customer);
          _customerSearchController.text = customer.name;
        } else {
          _errorMessage = 'Customer not found for this sale order';
          _selectedCustomer = null;
          _customerSearchController.clear();
          notifyListeners();
        }
      } else {
        _errorMessage = 'No valid customer associated with this sale order';
        _selectedCustomer = null;
        _customerSearchController.clear();
        notifyListeners();
      }

      await fetchSaleOrderLines(saleOrder.id!);

      final invoiceCount = _selectedSaleOrder!.extraData?['invoice_count'] ?? 0;
      final invoiceStatus = _selectedSaleOrder!.invoiceStatus ?? '';

      if (_invoiceLines.isEmpty &&
          (invoiceCount > 0 || invoiceStatus == 'invoiced')) {
        _errorMessage =
            'This sale order is already fully invoiced. There are no remaining items to invoice.';
        notifyListeners();
        return;
      } else if (_invoiceLines.isEmpty) {
        _errorMessage = 'No invoiceable items found in this sale order.';
        notifyListeners();
        return;
      }

      if (_selectedSaleOrder!.dateOrder != null) {
        setInvoiceDate(_selectedSaleOrder!.dateOrder!);
      }
      final commitmentDate = _selectedSaleOrder!.extraData?['commitment_date'];
      if (commitmentDate != null && commitmentDate != false) {
        try {
          setDueDate(DateTime.parse(commitmentDate));
        } catch (e) {}
      }

      if (_selectedSaleOrder?.extraData?['payment_term_id'] is List &&
          (_selectedSaleOrder?.extraData?['payment_term_id'] as List)
              .isNotEmpty) {
        final termId = _selectedSaleOrder?.extraData?['payment_term_id'][0];
        final term = _paymentTerms.firstWhere(
          (t) => t.id == termId,
          orElse: () => PaymentTerm(id: 0, name: ''),
        );
        if (term.id != 0) {
          setSelectedPaymentTerm(term);
        } else {
          if (_selectedCustomer?.paymentTermId != null) {
            _setCustomerPaymentTerm(_selectedCustomer!.paymentTermId!);
          }
        }
      } else if (_selectedCustomer?.paymentTermId != null) {
        _setCustomerPaymentTerm(_selectedCustomer!.paymentTermId!);
      }
    } catch (e) {
      _errorMessage = 'Failed to load sale order details: $e';
      notifyListeners();
    } finally {
      _isLoadingSaleOrderDetails = false;
      notifyListeners();
    }
  }

  Future<Map<String, dynamic>> fetchSaleOrderDetails(int saleOrderId) async {
    try {
      final result = await _invoiceService.fetchSaleOrderDetails(saleOrderId);
      return result;
    } catch (e, stackTrace) {
      log(
        'Error fetching sale order details: $e',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> fetchSaleOrderLines(int saleOrderId) async {
    try {
      final orderData = await _invoiceService.fetchSaleOrderDetails(
        saleOrderId,
      );

      if (orderData.isEmpty || orderData['order_line'] == null) {
        _saleOrderLines.clear();
        _invoiceLines.clear();
        _taxTotals.clear();
        notifyListeners();
        return;
      }

      _taxTotals = {
        'amount_untaxed': orderData['amount_untaxed'] ?? 0.0,
        'amount_tax': orderData['amount_tax'] ?? 0.0,
        'amount_total': orderData['amount_total'] ?? 0.0,
      };

      final lineIds = List<int>.from(orderData['order_line']);

      final linesResult = await _invoiceService.fetchSaleOrderLines(lineIds);
      _saleOrderLines = linesResult;

      String? taxFieldUsed;
      String? uomFieldUsed;

      if (linesResult.isNotEmpty) {
        final firstLine = linesResult.first;
        if (firstLine.containsKey('tax_id')) {
          taxFieldUsed = 'tax_id';
        } else if (firstLine.containsKey('tax_ids')) {
          taxFieldUsed = 'tax_ids';
        }

        if (firstLine.containsKey('product_uom')) {
          uomFieldUsed = 'product_uom';
        } else if (firstLine.containsKey('product_uom_id')) {
          uomFieldUsed = 'product_uom_id';
        }
      }

      _invoiceLines.clear();

      for (final line in _saleOrderLines) {
        final qtyToInvoice =
            (line['qty_to_invoice'] as num?)?.toDouble() ?? 0.0;
        final productUomQty =
            (line['product_uom_qty'] as num?)?.toDouble() ?? 0.0;

        final quantityToUse = productUomQty > 0 ? productUomQty : qtyToInvoice;

        if (quantityToUse > 0) {
          final unitPrice = (line['price_unit'] as num?)?.toDouble() ?? 0.0;
          final subtotal = (line['price_subtotal'] as num?)?.toDouble() ?? 0.0;
          final total = (line['price_total'] as num?)?.toDouble() ?? 0.0;

          String productName;
          if (line['product_id'] is List &&
              (line['product_id'] as List).length > 1) {
            productName = (line['product_id'][1] ?? '').toString();
          } else {
            final raw = line['name']?.toString();
            if (raw != null && raw.isNotEmpty && raw != 'false') {
              var first = raw.split('\n').first;
              if (first.contains(' - ')) first = first.split(' - ').first;
              productName = first.isNotEmpty ? first : 'Custom Line';
            } else {
              productName = 'Custom Line';
            }
          }
          int? productId;
          int? productUomId;
          List<int> taxIds = [];

          if (taxFieldUsed != null) {
            if (taxFieldUsed == 'tax_id') {
              if (line['tax_id'] is List &&
                  (line['tax_id'] as List).isNotEmpty) {
                taxIds = [line['tax_id'][0] as int];
              } else if (line['tax_id'] is int) {
                taxIds = [line['tax_id'] as int];
              }
            } else if (taxFieldUsed == 'tax_ids') {
              if (line['tax_ids'] is List) {
                taxIds = List<int>.from(line['tax_ids']);
              }
            }
          }

          if (line['product_id'] is List) {
            final productList = line['product_id'] as List;
            if (productList.isNotEmpty) {
              productId = productList[0] as int?;
              if (productList.length > 1 && productList[1] != null) {
                productName = productList[1].toString();
              }
            }
          } else if (line['product_id'] is int) {
            productId = line['product_id'] as int?;
          }

          if (uomFieldUsed != null) {
            if (line[uomFieldUsed] is List) {
              final uomList = line[uomFieldUsed] as List;
              if (uomList.isNotEmpty) {
                productUomId = uomList[0] as int?;
              }
            } else if (line[uomFieldUsed] is int) {
              productUomId = line[uomFieldUsed] as int?;
            }
          }

          Map<String, dynamic> productData = {
            'id': productId,
            'name': productName,
            'list_price': unitPrice,
          };

          if (productId != null) {
            try {
              final product = await _productService.fetchProductData(
                productId,
                fields: ['name', 'default_code', 'list_price', 'uom_id'],
              );

              if (product.isNotEmpty) {
                productData['name'] =
                    product['name']?.toString() ?? productName;
                productData['default_code'] = product['default_code']
                    ?.toString();
                productData['list_price'] =
                    (product['list_price'] as num?)?.toDouble() ?? unitPrice;
                productName = productData['name'];

                if (product['uom_id'] is List) {
                  productData['uom_id'] = product['uom_id'];
                  productUomId ??= product['uom_id'][0];
                }
              }
            } catch (e) {}
          }

          if (productId != null && productId > 0) {
            final invoiceLine = {
              'product_id': productId,
              'product_name': productName,
              'quantity': quantityToUse,
              'unit_price': unitPrice,
              'subtotal': subtotal,
              'price_total': total,
              'tax_ids': taxIds,
              'sale_line_id': line['id'],
              'product_data': productData,
            };

            if (productUomId != null && productUomId > 0) {
              invoiceLine['product_uom_id'] = productUomId;
            }

            _invoiceLines.add(invoiceLine);
          } else {}
        }
      }

      notifyListeners();
    } catch (e, stackTrace) {
      log(
        'Error fetching sale order lines: $e',
        error: e,
        stackTrace: stackTrace,
      );
      rethrow;
    }
  }

  Future<void> calculateTaxForInvoiceLines() async {
    if (_invoiceLines.isEmpty || _selectedCustomer == null) {
      _taxTotals.clear();
      notifyListeners();
      return;
    }

    _isCalculatingTax = true;
    notifyListeners();

    try {
      final invoiceLines = _invoiceLines.map((line) {
        return [
          0,
          0,
          {
            'product_id': line['product_id'],
            'name': line['product_name'],
            'quantity': line['quantity'] ?? 1.0,
            'price_unit': line['unit_price'] ?? 0.0,
            'product_uom_id': line['product_uom_id'],
          },
        ];
      }).toList();

      final tempInvoiceData = {
        'partner_id': _selectedCustomer!.id,
        'invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate!),
        'move_type': _getMoveType(),
        'invoice_line_ids': invoiceLines,
      };

      final String currentCode = _currency;
      final int? tempCurrencyId = await _invoiceService.getCurrencyId(
        currentCode,
      );
      if (tempCurrencyId != null) {
        tempInvoiceData['currency_id'] = tempCurrencyId;
      }

      final invoiceData = await _invoiceService.calculateTax(tempInvoiceData);

      if (invoiceData.isNotEmpty) {
        _taxTotals = {
          'amount_untaxed': invoiceData['amount_untaxed'] ?? 0.0,
          'amount_tax': invoiceData['amount_tax'] ?? 0.0,
          'amount_total': invoiceData['amount_total'] ?? 0.0,
        };
      }
    } catch (e) {
      _taxTotals = {
        'amount_untaxed': subtotal,
        'amount_tax': 0.0,
        'amount_total': subtotal,
      };
    } finally {
      _isCalculatingTax = false;
    }
  }

  Future<Map<String, dynamic>> fetchSaleOrderLine(int id) async {
    try {
      final results = await _invoiceService.fetchSaleOrderLines([id]);
      if (results.isNotEmpty) {
        return results.first;
      }
      return {};
    } catch (e) {
      rethrow;
    }
  }

  void setSelectedPaymentTerm(PaymentTerm? term) {
    _selectedPaymentTerm = term;
    notifyListeners();
  }

  void setInvoiceDate(DateTime date) {
    _invoiceDate = date;
    notifyListeners();
  }

  void setDueDate(DateTime date) {
    _dueDate = date;
    notifyListeners();
  }

  Future<void> addInvoiceLine(
    Product product,
    double quantity,
    double unitPrice,
  ) async {
    _isAddingLine = true;
    notifyListeners();
    try {
      final subtotal = quantity * unitPrice;

      final pid = int.tryParse(product.id);
      final taxIds = await _fetchProductTaxInfo(
        pid,
        initialTaxIds: product.taxId != null ? [product.taxId!] : null,
      );

      _invoiceLines.insert(0, {
        'product_id': pid,
        'product_name': product.name,
        'quantity': quantity,
        'unit_price': unitPrice,
        'subtotal': subtotal,
        'tax_ids': taxIds,
        'product_data': product.toJson(),
        'product_uom_id': (product.uomId is List && product.uomId.isNotEmpty)
            ? product.uomId[0]
            : product.uomId,
      });

      if (_selectedSaleOrder == null) {
        await calculateTaxForInvoiceLines();
      }
    } finally {
      _isAddingLine = false;
      notifyListeners();
    }
  }

  Future<List<int>> _fetchProductTaxInfo(
    int? productId, {
    List<int>? initialTaxIds,
  }) async {
    if (productId == null || productId <= 0) {
      return [];
    }

    try {
      List<int> productTaxIds;
      if (initialTaxIds != null) {
        productTaxIds = initialTaxIds;
      } else {
        final result = await _productService.fetchProductData(
          productId,
          fields: ['taxes_id'],
        );
        if (result.isNotEmpty && result['taxes_id'] is List) {
          productTaxIds = List<int>.from(result['taxes_id']);
        } else {
          productTaxIds = [];
        }
      }

      if (productTaxIds.isEmpty) {
        return [];
      }

      return await _invoiceService.filterTaxesByCompany(productTaxIds);
    } catch (e) {}
    return [];
  }

  void updateInvoiceLine(int index, double quantity, double unitPrice) {
    if (index >= 0 && index < _invoiceLines.length) {
      final subtotal = quantity * unitPrice;
      _invoiceLines[index]['quantity'] = quantity;
      _invoiceLines[index]['unit_price'] = unitPrice;
      _invoiceLines[index]['subtotal'] = subtotal;

      if (_selectedSaleOrder == null) {
        calculateTaxForInvoiceLines();
      }
      notifyListeners();
    }
  }

  void removeInvoiceLine(int index) {
    if (index >= 0 && index < _invoiceLines.length) {
      _invoiceLines.removeAt(index);

      if (_selectedSaleOrder == null) {
        calculateTaxForInvoiceLines();
      }
      notifyListeners();
    }
  }

  Future<void> fetchCustomers() async {
    if (_isLoadingCustomers) return;
    _isLoadingCustomers = true;
    _loadingError = null;
    notifyListeners();

    try {
      final customers = await _customerService.fetchAllCustomers();
      _customers = List.from(customers);
      _filteredCustomers = List.from(_customers);
    } catch (e) {
      _loadingError = 'Failed to load customers. Please try again.';
    } finally {
      _isLoadingCustomers = false;
      notifyListeners();
    }
  }

  Future<void> fetchSaleOrders() async {
    if (_isLoadingSaleOrders) return;
    _isLoadingSaleOrders = true;
    _saleOrderLoadingError = null;
    notifyListeners();
    try {
      final result = await _invoiceService.fetchSaleOrders(
        domain: [
          ['state', '=', 'sale'],
        ],
      );

      _saleOrders = result.map((order) => Quote.fromJson(order)).toList();

      _saleOrders.sort((a, b) {
        final aCanInvoice = _canInvoiceSaleOrder(a);
        final bCanInvoice = _canInvoiceSaleOrder(b);
        final aStatus = a.invoiceStatus ?? '';
        final bStatus = b.invoiceStatus ?? '';

        if (aCanInvoice && !bCanInvoice) return -1;
        if (!aCanInvoice && bCanInvoice) return 1;

        if (aStatus == 'to invoice' && bStatus != 'to invoice') return -1;
        if (aStatus != 'to invoice' && bStatus == 'to invoice') return 1;
        if (aStatus == 'upselling' && bStatus == 'invoiced') return -1;
        if (aStatus == 'invoiced' && bStatus == 'upselling') return 1;

        return 0;
      });

      _filteredSaleOrders = List.from(_saleOrders);
    } catch (e) {
      _saleOrderLoadingError = 'Failed to load sale orders. Please try again.';
    } finally {
      _isLoadingSaleOrders = false;
      notifyListeners();
    }
  }

  bool _canInvoiceSaleOrder(Quote order) {
    final invoiceStatus = order.invoiceStatus ?? '';
    final amountToInvoice =
        (order.extraData?['amount_to_invoice'] as num?)?.toDouble() ?? 0.0;
    final amountTotal = order.total;
    final amountInvoiced =
        (order.extraData?['amount_invoiced'] as num?)?.toDouble() ?? 0.0;

    if (invoiceStatus == 'to invoice') {
      if (amountToInvoice > 0) return true;

      final remainingAmount = amountTotal - amountInvoiced;
      return remainingAmount > 0.01;
    }

    if (invoiceStatus == 'upselling') {
      return amountToInvoice > 0 || (amountTotal - amountInvoiced) > 0.01;
    }

    return false;
  }

  Future<void> fetchPaymentTerms() async {
    _isLoading = true;
    notifyListeners();

    try {
      final result = await _invoiceService.fetchPaymentTerms();

      final terms = <PaymentTerm>[];
      final seenIds = <int>{};

      for (final term in List<Map<String, dynamic>>.from(result)) {
        final id = term['id'] as int;
        if (!seenIds.contains(id)) {
          seenIds.add(id);
          terms.add(PaymentTerm.fromMap(term));
        }
      }

      _paymentTerms = terms;
    } catch (e) {
      _errorMessage = 'Failed to fetch payment terms: $e';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  List<String> _availableFields = [];
  bool _isFieldsFetched = false;

  Future<void> fetchProducts({
    String category = 'All Products',
    bool isLoadMore = false,
    String searchQuery = '',
  }) async {
    if (!isLoadMore) {
      _categoryCurrentPage[category] = 0;
      _categoryProducts[category] = [];
      _errorMessage = '';
      _isLoading = true;
      notifyListeners();
    } else if (_categoryIsLoadingMore[category] == true) {
      return;
    }

    try {
      if (!_isFieldsFetched) {
        _availableFields = await _fetchAvailableFields();
        _isFieldsFetched = true;
      }

      List<dynamic> productDomain = [
        ['active', '=', true],
        [
          'type',
          'in',
          ['product', 'consu'],
        ],
      ];

      if (category != 'All Products') {
        productDomain.add(['categ_id.name', '=', category]);
      }

      if (searchQuery.isNotEmpty) {
        productDomain.add('|');
        productDomain.add('|');
        productDomain.add(['name', 'ilike', searchQuery]);
        productDomain.add(['default_code', 'ilike', searchQuery]);
        productDomain.add(['barcode', 'ilike', searchQuery]);
      }

      List<String> fields = [
        'id',
        'name',
        'list_price',
        'default_code',
        'taxes_id',
        'categ_id',
        'product_tmpl_id',
        'product_template_attribute_value_ids',
        'product_variant_count',
        'type',
        'image_1920',
        'seller_ids',
      ];

      if (_availableFields.contains('qty_available')) {
        fields.add('qty_available');
      }

      final results = await Future.wait([
        _productService.getProductCount(productDomain),
        _productService.fetchProducts(
          domain: productDomain,
          fields: fields,
          limit: _pageSize,
          offset: (_categoryCurrentPage[category] ?? 0) * _pageSize,
          order: 'name asc',
        ),
      ]);

      final totalCount = results[0] as int;
      final productList = (results[1] as List<Map<String, dynamic>>)
          .map((json) => Product.fromJson(json))
          .toList();

      if (category == 'All Products') {
        if (isLoadMore) {
          _products.addAll(productList);
        } else {
          _products = productList;
        }
      }

      _categoryTotalProducts[category] = totalCount;
      if (isLoadMore) {
        _categoryProducts[category]!.addAll(productList);
      } else {
        _categoryProducts[category] = productList;
      }

      _categoryHasMore[category] =
          _categoryProducts[category]!.length < totalCount;
      _categoryCurrentPage[category] =
          (_categoryCurrentPage[category] ?? 0) + 1;
    } catch (e) {
      _errorMessage = 'Failed to load products: $e';
    } finally {
      if (!isLoadMore) {
        _isLoading = false;
      } else {
        _categoryIsLoadingMore[category] = false;
      }
      notifyListeners();
    }
  }

  Future<List<String>> _fetchAvailableFields() async {
    try {
      final fields = await _productService.fetchFields('product.product');
      return fields.keys.toList();
    } catch (e) {
      return [];
    }
  }

  Future<void> createInvoice(
    BuildContext context, {
    String invoiceType = 'regular',
    double? downPaymentPercentage,
    double? downPaymentAmount,
  }) async {
    if (_isCreatingInvoice) {
      CustomSnackbar.showWarning(
        context,
        'Please wait while the current invoice is being created',
      );
      return;
    }

    _isCreatingInvoice = true;
    _isLoading = true;
    _lastCreatedInvoiceName = null;
    _lastCreatedInvoiceId = null;
    notifyListeners();

    try {
      if (_selectedCustomer == null) {
        throw Exception('No customer selected');
      }

      if (invoiceType == 'percentage' || invoiceType == 'fixed') {
        if (_selectedSaleOrder == null) {
          throw Exception('Down payment invoices require a sale order');
        }
        await _createDownPaymentInvoice(
          context,
          invoiceType,
          downPaymentPercentage,
          downPaymentAmount,
        );
      } else {
        if (_invoiceLines.isEmpty) {
          throw Exception('No invoice lines provided');
        }

        for (int i = 0; i < _invoiceLines.length; i++) {
          final line = _invoiceLines[i];
          if (line['product_id'] == null || line['product_id'] <= 0) {
            throw Exception('Invalid product ID in invoice line ${i + 1}');
          }
          if (line['product_name'] == null ||
              line['product_name'].toString().isEmpty) {
            throw Exception('Invalid product name in invoice line ${i + 1}');
          }
        }

        if (_selectedSaleOrder != null) {
          await _createInvoiceFromSaleOrder(context);
        } else {
          await _createDirectInvoice(context);
        }
      }
    } catch (e) {
      _errorMessage = OdooErrorHandler.toUserMessage(e);
    } finally {
      _isCreatingInvoice = false;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _createInvoiceFromSaleOrder(BuildContext context) async {
    try {
      final saleOrderId = _selectedSaleOrder?.id;

      final wizardId = await _invoiceService.createAdvancePaymentWizard({
        'advance_payment_method': 'delivered',
        'sale_order_ids': [
          [
            6,
            0,
            [saleOrderId],
          ],
        ],
      });

      final result = await _invoiceService.executeAdvancePaymentWizard(
        wizardId,
      );

      int? invoiceId;
      if (result is List && result.isNotEmpty) {
        invoiceId = result[0] as int?;
      } else if (result is Map && result['res_id'] is int) {
        invoiceId = result['res_id'] as int;
      } else if (result is int) {
        invoiceId = result;
      }

      if (invoiceId == null) {
        throw Exception('Failed to get invoice ID from wizard result');
      }

      final writeVals = <String, dynamic>{};
      if (_selectedPaymentTerm != null && _selectedPaymentTerm!.id != 0) {
        writeVals['invoice_payment_term_id'] = _selectedPaymentTerm!.id;
      }
      if (_invoiceDate != null) {
        writeVals['invoice_date'] = DateFormat(
          'yyyy-MM-dd',
        ).format(_invoiceDate!);
      }

      await _invoiceService.linkInvoiceToSaleOrder(saleOrderId!, invoiceId);

      _lastCreatedInvoiceName =
          await _invoiceService.getInvoiceName(invoiceId) ?? 'Invoice';
      _lastCreatedInvoiceId = invoiceId;

      clearSelectedSaleOrder();
      await fetchSaleOrders();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _createDirectInvoice(BuildContext context) async {
    try {
      final invoiceLines = _invoiceLines.map((line) {
        return [
          0,
          0,
          {
            'product_id': line['product_id'],
            'name': line['product_name'],
            'quantity': line['quantity'] ?? 1.0,
            'price_unit': line['unit_price'] ?? 0.0,
            'product_uom_id': line['product_uom_id'],
            'tax_ids': [
              [6, 0, line['tax_ids'] ?? []],
            ],
            'discount': line['discount'] ?? 0.0,
          },
        ];
      }).toList();

      final invoiceData = {
        'partner_id': _selectedCustomer!.id,
        'move_type': 'out_invoice',
        'invoice_date': DateFormat('yyyy-MM-dd').format(_invoiceDate!),
        'invoice_line_ids': invoiceLines,
        if (_selectedPaymentTerm != null)
          'invoice_payment_term_id': _selectedPaymentTerm!.id,
      };

      final int? currencyId = await _invoiceService.getCurrencyId(_currency);
      if (currencyId != null) {
        invoiceData['currency_id'] = currencyId;
      }

      final invoiceId = await _invoiceService.createInvoice(invoiceData);

      if (_selectedSaleOrder != null) {
        await _invoiceService.linkInvoiceToSaleOrder(
          _selectedSaleOrder!.id!,
          invoiceId,
        );
      }

      _lastCreatedInvoiceName =
          await _invoiceService.getInvoiceName(invoiceId) ?? 'Invoice';
      _lastCreatedInvoiceId = invoiceId;

      clearSelectedSaleOrder();
      await fetchSaleOrders();
    } catch (e) {
      rethrow;
    }
  }

  String _getMoveType() {
    return 'out_invoice';
  }

  Future<void> _createDownPaymentInvoice(
    BuildContext context,
    String invoiceType,
    double? downPaymentPercentage,
    double? downPaymentAmount,
  ) async {
    try {
      final saleOrderId = _selectedSaleOrder?.id;

      final Map<String, dynamic> invoiceData = {
        'partner_id': _selectedCustomer!.id,
        'move_type': 'out_invoice',
        'invoice_origin': _selectedSaleOrder?.name,
      };

      if (invoiceType == 'percentage') {
        invoiceData['invoice_line_ids'] = [
          [
            0,
            0,
            {
              'name': 'Down payment of $downPaymentPercentage%',
              'quantity': 1,
              'price_unit':
                  (_selectedSaleOrder?.total ?? 0.0) *
                  (downPaymentPercentage! / 100.0),
            },
          ],
        ];
      } else {
        invoiceData['invoice_line_ids'] = [
          [
            0,
            0,
            {
              'name': 'Down payment',
              'quantity': 1,
              'price_unit': downPaymentAmount ?? 0.0,
            },
          ],
        ];
      }

      final int? currencyId = await _invoiceService.getCurrencyId(_currency);
      if (currencyId != null) {
        invoiceData['currency_id'] = currencyId;
      }

      final invoiceId = await _invoiceService.createInvoice(invoiceData);

      await _invoiceService.linkInvoiceToSaleOrder(saleOrderId!, invoiceId);
      _lastCreatedInvoiceName =
          await _invoiceService.getInvoiceName(invoiceId) ?? 'Invoice';
      _lastCreatedInvoiceId = invoiceId;

      clearSelectedSaleOrder();
      await fetchSaleOrders();
    } catch (e) {
      rethrow;
    }
  }

  void resetForm() {
    _selectedCustomer = null;
    _selectedSaleOrder = null;
    _saleOrderLines.clear();
    _invoiceLines.clear();
    _selectedPaymentTerm = null;
    _taxTotals.clear();
    _invoiceDate = DateTime.now();
    _dueDate = DateTime.now().add(const Duration(days: 30));
    _customerSearchController.clear();
    _saleOrderSearchController.clear();
    notifyListeners();
  }

  void clearSelectedSaleOrder() {
    setSelectedSaleOrder(null);
    _invoiceLines.clear();
    _selectedCustomer = null;
    _taxTotals.clear();
    _customerSearchController.clear();
    _errorMessage = '';
    notifyListeners();
  }

  Future<void> clearData() async {
    _isLoading = false;
    _isLoadingCustomers = false;
    _isLoadingSaleOrders = false;
    _isLoadingSaleOrderDetails = false;
    _errorMessage = '';
    _loadingError = null;
    _saleOrderLoadingError = null;
    _customers = [];
    _filteredCustomers = [];
    _saleOrders = [];
    _filteredSaleOrders = [];
    _paymentTerms = [];
    _products = [];
    _selectedCustomer = null;
    _selectedSaleOrder = null;
    _saleOrderLines = [];
    _invoiceLines = [];
    _invoiceDate = DateTime.now();
    _dueDate = DateTime.now().add(const Duration(days: 30));
    _selectedPaymentTerm = null;
    _currency = 'USD';
    _customerSearchController.clear();
    _saleOrderSearchController.clear();

    notifyListeners();
  }

  List<Product> getProductsForCategory(String category) {
    if (category == 'All Products') {
      if (_categoryProducts.containsKey('all')) {
        return _categoryProducts['all']!;
      }

      return _products;
    }
    return _categoryProducts[category] ?? [];
  }

  bool hasMoreDataForCategory(String category) {
    if (category == 'All Products') {
      return _categoryHasMore['all'] ?? false;
    }
    return _categoryHasMore[category] ?? false;
  }
}
