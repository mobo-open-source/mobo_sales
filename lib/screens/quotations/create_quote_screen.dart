import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:odoo_rpc/odoo_rpc.dart';
import 'package:provider/provider.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import 'package:mobo_sales/widgets/circular_image_widget.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/loading_dialog.dart';
import '../../models/contact.dart';
import '../../models/sale_order_compat.dart';
import '../../providers/contact_provider.dart';
import '../../providers/currency_provider.dart';
import '../../services/odoo_session_manager.dart';
import '../../services/odoo_error_handler.dart';
import '../../utils/odoo_version.dart';
import '../../widgets/confetti_dialogs.dart';
import '../../utils/data_loss_warning_mixin.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_date_picker.dart';
import '../../utils/date_picker_utils.dart';
import '../../utils/form_change_tracker.dart';
import '../../widgets/customer_typeahead.dart';
import '../../utils/html_text.dart';
import '../../widgets/product_typeahead.dart';
import '../../shared/widgets/mobo/mobo_bottom_action_bar.dart';
import '../../shared/widgets/mobo/mobo_dialog_buttons.dart';
import '../../shared/widgets/mobo/mobo_select_field.dart';
import '../../services/review_service.dart';
import '../../services/data_change_bus.dart';

/// What the edit screen hands back to the screen that opened it when the
/// quotation was saved. [note] is something the user must still be told about
/// the save — what the server would not let it change on a confirmed order.
class QuoteSaved {
  const QuoteSaved({this.note, this.noteIsWarning = false});

  final String? note;
  final bool noteIsWarning;
}

class CreateQuoteScreen extends StatefulWidget {
  final Contact? customer;
  final Map<String, dynamic>? quotationToEdit;

  const CreateQuoteScreen({super.key, this.customer, this.quotationToEdit});

  @override
  State<CreateQuoteScreen> createState() => _CreateQuoteScreenState();
}

class _CreateQuoteScreenState extends State<CreateQuoteScreen>
    with DataLossWarningMixin {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  Contact? _selectedCustomer;
  final List<Map<String, dynamic>> _quoteLines = [];

  /// The state of the order being edited ('' when creating one): as the server
  /// has it now, falling back to what the screen that opened this one knew.
  String? _loadedState;
  String get _orderState =>
      _loadedState ?? widget.quotationToEdit?['state']?.toString() ?? '';

  /// Odoo's own form: once an order is confirmed (`sale`, or the older `done`)
  /// its customer and pricelist are read-only and its expiration date is no
  /// longer shown. A cancelled order is read-only in the same fields. The app's
  /// edit form follows suit, rather than offering a change the server refuses
  /// ("You cannot change the pricelist of a confirmed order").
  bool get _isConfirmedOrder => _orderState == 'sale' || _orderState == 'done';
  bool get _isCancelledOrder => _orderState == 'cancel';
  bool get _customerAndPricelistLocked =>
      _isConfirmedOrder || _isCancelledOrder;

  /// Monotonic id assigned to every quote line so each line widget gets a
  /// stable [ValueKey]. Without it, inserting a new line at the top makes
  /// Flutter reuse the previous line's widget state (e.g. its quantity input),
  /// which caused newly added products to inherit the prior line's quantity.
  int _quoteLineUidSeq = 0;

  DateTime? _validityDate;
  DateTime? _initialValidityDate;
  Timer? _debounce;

  /// Set once the quotation has been written to the server.
  ///
  /// Without it the discard prompt fired after a *successful* save: the
  /// customer and lines are naturally still populated at that point, and the
  /// check below reads any content at all as unsaved work.
  bool _savedSuccessfully = false;

  /// Every value the user can edit on the form, so an edit form can tell
  /// whether it differs from the quotation it loaded. The baseline is taken
  /// when the load that [initState] starts has filled in the quotation, its
  /// lines and the customer's defaults.
  late final FormChangeTracker _changes = FormChangeTracker(
    () => {
      'customer': _selectedCustomer?.id,
      'validityDate': _validityDate?.toIso8601String().split('T')[0],
      'notes': _notesController.text.trim(),
      'paymentTerm': _selectedPaymentTerm?['id'],
      'pricelist': _selectedPricelist?['id'],
      'lines': [
        for (final line in _quoteLines)
          {
            'product': line['product_id'],
            'quantity': line['quantity'],
            'unitPrice': line['unit_price'],
          },
      ],
    },
  );

  /// What the form refuses to submit without: a customer and a product line.
  bool get _requiredFieldsFilled =>
      _selectedCustomer != null && _quoteLines.isNotEmpty;

  /// Whether the submit button is live. Editing also needs a real change, so
  /// Update stays off until there is something to save.
  bool get _canSubmit {
    final idle = _quoteLines.isNotEmpty && !_isLoading;
    if (widget.quotationToEdit == null) return idle;
    return idle && _requiredFieldsFilled && _changes.isDirty;
  }

  void _onFormChanged() {
    if (mounted) setState(() {});
  }

  @override
  bool get hasUnsavedData {
    if (_isInitialLoad || _savedSuccessfully) return false;

    // An edit form has unsaved work only once it differs from the quotation it
    // loaded; the checks below would read that quotation's own customer and
    // lines as new work.
    if (widget.quotationToEdit != null) return _changes.isDirty;

    final customerChanged =
        _selectedCustomer != null &&
        _selectedCustomer?.id != widget.customer?.id;

    return customerChanged ||
        _quoteLines.isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        _selectedPaymentTerm != null ||
        _selectedPricelist != null ||
        (_validityDate != null && _validityDate != _initialValidityDate);
  }

  @override
  String get dataLossTitle => 'Discard Quotation?';

  @override
  String get dataLossMessage =>
      'You have unsaved quotation data that will be lost if you leave this page. Are you sure you want to discard this quotation?';

  @override
  void onConfirmLeave() {
    // Clearing the notes below would otherwise rebuild the form, showing it
    // emptied while the page is still sliding away.
    _notesController.removeListener(_onFormChanged);
    _selectedCustomer = null;
    _quoteLines.clear();
    _notesController.clear();
    _selectedPaymentTerm = null;
    _selectedPricelist = null;
    _validityDate = _initialValidityDate;

    _clearContactProviderSearchState();
  }

  void _clearContactProviderSearchState() {
    try {
      final contactProvider = Provider.of<ContactProvider>(
        context,
        listen: false,
      );
      contactProvider.clearSearchState();
    } catch (e) {}
  }

  bool _isAddingLine = false;
  bool _isLoading = false;

  bool _isInitialLoad = true;

  String? _currentRequestId;
  String? _quotationName;
  int? _quotationId;

  bool _isLoadingPaymentTermsShimmer = false;
  bool _isLoadingPricelistsShimmer = false;

  Map<String, dynamic>? _selectedPaymentTerm;
  Map<String, dynamic>? _selectedPricelist;
  List<Map<String, dynamic>> _paymentTerms = [];
  List<Map<String, dynamic>> _pricelists = [];
  final bool _isLoadingPaymentTerms = false;
  final bool _isLoadingPricelists = false;

  static List<Map<String, dynamic>>? _paymentTermsCache;
  static List<Map<String, dynamic>>? _pricelistsCache;

  /// Whose lists the two caches hold: database, user and company. A list read
  /// for one company must never be shown for another.
  static String? _listsCacheScope;
  static DateTime? _paymentTermsCacheTime;
  static DateTime? _pricelistsCacheTime;
  static const Duration _cacheDuration = Duration(minutes: 10);

  static String _displayValue(dynamic value) {
    if (value == null) return '-';
    String stringValue = value.toString();
    if (stringValue.isEmpty ||
        stringValue.toLowerCase() == 'false' ||
        stringValue.toLowerCase() == 'null') {
      return '-';
    }
    return stringValue;
  }

  int? _toIntId(dynamic v) {
    if (v == null) return null;
    if (v is int) return v;
    if (v is String) return int.tryParse(v);
    if (v is List && v.isNotEmpty) {
      final first = v.first;
      if (first is int) return first;
      if (first is String) return int.tryParse(first);
    }
    if (v is Map && v.containsKey('id')) {
      return _toIntId(v['id']);
    }
    return null;
  }

  Timer? _debouncedTaxRecalc;

  void _scheduleTaxRecalc() {
    _debouncedTaxRecalc?.cancel();
    _debouncedTaxRecalc = Timer(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _calculateTaxAmount();
        });
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _validityDate = DateTime.now().add(const Duration(days: 30));
    _initialValidityDate = _validityDate;

    // An edit form shows the skeleton from its first frame until the quotation
    // and its lines are in: never an empty form that fills in under the user.
    _isInitialLoad = widget.customer != null || widget.quotationToEdit != null;

    if (widget.customer != null && widget.quotationToEdit == null) {
      _selectedCustomer = widget.customer;
    }

    _notesController.addListener(_onFormChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final futures = <Future<void>>[];
        futures.add(_loadPaymentTerms());
        futures.add(_loadPricelists());

        if (widget.quotationToEdit != null) {
          await _loadQuotationForEditing(widget.quotationToEdit!);
        }

        // A quotation being edited keeps its own pricelist and payment term;
        // the customer's defaults are for a new one (and for a customer the
        // user picks later, which loads them itself).
        if (_selectedCustomer != null && widget.quotationToEdit == null) {
          futures.add(_loadCustomerDefaults(_selectedCustomer!));
        }

        await Future.wait(futures);

        // Everything an edit form fills in is in place by now: the quotation
        // and its lines, the customer's payment term and pricelist, and the
        // option lists. This is what "unchanged" means from here on. The tax
        // recalculation below only rewrites the derived tax total.
        if (mounted && widget.quotationToEdit != null) _changes.markClean();
      } catch (_) {
        // A failed load must not leave the skeleton up for good; the form
        // opens with whatever arrived.
      } finally {
        if (mounted) setState(() => _isInitialLoad = false);
      }

      if (_quoteLines.isNotEmpty) {
        _scheduleTaxRecalc();
      }
    });
  }

  Future<void> _loadQuotationForEditing(Map<String, dynamic> quotation) async {
    try {
      _quotationId = quotation['id'] as int?;
      _quotationName = quotation['name']?.toString();

      if (quotation['partner_id'] != null && quotation['partner_id'] is List) {
        final customerId = quotation['partner_id'][0] as int;

        final client = await OdooSessionManager.getClient();
        if (client != null) {
          try {
            // `company_name` is gone in Odoo 20; asking for it would fail the
            // whole read and leave the customer with no details.
            final generation = await OdooSessionManager.serverGeneration();
            final hasCompanyName = odooHasPartnerCompanyName(generation);
            final customerData = await client.callKw({
              'model': 'res.partner',
              'method': 'read',
              'args': [
                [customerId],
              ],
              'kwargs': {'fields': quoteCustomerFields(generation)},
            });

            if (customerData != null &&
                customerData is List &&
                customerData.isNotEmpty) {
              final data = customerData[0];

              Uint8List? imageBytes;
              if (data['image_1920'] != null && data['image_1920'] != false) {
                try {
                  imageBytes = base64Decode(data['image_1920']);
                } catch (e) {}
              }

              // The employer stands in for the free-text company where the
              // server no longer has `company_name`.
              final parent = data['parent_id'];
              final companyName = hasCompanyName
                  ? (data['company_name']?.toString() != 'false'
                        ? data['company_name']?.toString()
                        : null)
                  : (parent is List && parent.length > 1
                        ? parent[1]?.toString()
                        : null);

              _selectedCustomer = Contact(
                id: customerId,
                name: data['name'] ?? '',
                email: data['email']?.toString() != 'false'
                    ? data['email']?.toString()
                    : null,
                phone: data['phone']?.toString() != 'false'
                    ? data['phone']?.toString()
                    : null,
                street: data['street']?.toString() != 'false'
                    ? data['street']?.toString()
                    : null,
                street2: data['street2']?.toString() != 'false'
                    ? data['street2']?.toString()
                    : null,
                city: data['city']?.toString() != 'false'
                    ? data['city']?.toString()
                    : null,
                zip: data['zip']?.toString() != 'false'
                    ? data['zip']?.toString()
                    : null,
                vat: data['vat']?.toString() != 'false'
                    ? data['vat']?.toString()
                    : null,
                companyName: companyName,
                imageUrl: imageBytes != null
                    ? 'data:image/png;base64,${base64Encode(imageBytes)}'
                    : null,
              );
            } else {
              final customerName = quotation['partner_id'][1] as String;
              _selectedCustomer = Contact(
                id: customerId,
                name: customerName,
                email: '',
                phone: '',
                mobile: '',
              );
            }
          } catch (e) {
            final customerName = quotation['partner_id'][1] as String;
            _selectedCustomer = Contact(
              id: customerId,
              name: customerName,
              email: '',
              phone: '',
              mobile: '',
            );
          }
        }
      }

      // `sale.order.note` is an Odoo Html field, so a note typed as "Pay in
      // 30 days" comes back as `<p>Pay in 30 days</p>`. Put the readable text
      // in the box, the same way the invoice editor does with `narration`.
      _notesController.text = htmlToPlainText(quotation['note']);

      if (quotation['validity_date'] != null &&
          quotation['validity_date'] != false) {
        try {
          _validityDate = DateTime.parse(quotation['validity_date'].toString());
          _initialValidityDate = _validityDate;
        } catch (e) {}
      }

      // The order's own pricelist and payment term — not the customer's
      // defaults, which are what a new quotation starts from. Without this an
      // edit showed the customer's pricelist and saved it over the order's.
      final header = await _orderHeader();
      _loadedState = header?['state']?.toString();
      _selectedPricelist = _recordFrom(
        header != null ? header['pricelist_id'] : quotation['pricelist_id'],
      );
      _selectedPaymentTerm = _recordFrom(
        header != null
            ? header['payment_term_id']
            : quotation['payment_term_id'],
      );

      if (quotation['order_line'] != null && quotation['order_line'] is List) {
        final client = await OdooSessionManager.getClient();
        if (client != null) {
          final lineIds = (quotation['order_line'] as List).cast<int>();

          dynamic linesData;
          List<String> fieldsToFetch = [
            'product_id',
            'name',
            'product_uom_qty',
            'price_unit',
            'price_subtotal',
          ];

          String? uomField;
          String? taxField;

          // The unit and taxes fields were renamed together in Odoo 19
          // (`product_uom`/`tax_id` -> `product_uom_id`/`tax_ids`). Asking for
          // a mix, or the wrong pair, fails the read and the lines come back
          // without their unit or taxes, so each server gets its own pair.
          final generation = await OdooSessionManager.serverGeneration();
          for (final spelling in SaleLineFields.candidates(generation)) {
            try {
              linesData = await client.callKw({
                'model': 'sale.order.line',
                'method': 'read',
                'args': [lineIds],
                'kwargs': {
                  'fields': [...fieldsToFetch, spelling.uom, spelling.tax],
                },
              });
              uomField = spelling.uom;
              taxField = spelling.tax;
              break;
            } catch (e) {
              // This server spells them the other way; try the next pair.
            }
          }

          if (uomField == null) {
            linesData = await client.callKw({
              'model': 'sale.order.line',
              'method': 'read',
              'args': [lineIds],
              'kwargs': {'fields': fieldsToFetch},
            });
          }

          if (linesData != null && linesData is List) {
            _quoteLines.clear();

            for (var line in linesData) {
              final productId = line['product_id'];
              final productName = productId is List && productId.length > 1
                  ? productId[1]
                  : line['name'];
              final productIdInt = productId is List ? productId[0] : productId;

              dynamic uomId = 1;
              if (uomField != null && line[uomField] != null) {
                if (line[uomField] is List &&
                    (line[uomField] as List).isNotEmpty) {
                  uomId = line[uomField][0];
                } else if (line[uomField] is int) {
                  uomId = line[uomField];
                }
              }

              dynamic taxIds = [];
              if (taxField != null && line[taxField] != null) {
                taxIds = line[taxField];
              }

              final quoteLine = {
                'line_uid': _quoteLineUidSeq++,
                'product_id': productIdInt,
                'product_name': productName ?? '',
                'name': line['name'] ?? '',
                'quantity':
                    (line['product_uom_qty'] as num?)?.toDouble() ?? 1.0,
                'unit_price': (line['price_unit'] as num?)?.toDouble() ?? 0.0,
                'subtotal': (line['price_subtotal'] as num?)?.toDouble() ?? 0.0,
                'tax_id': taxIds,
                'uom_id': uomId,
              };

              _quoteLines.add(quoteLine);
            }
          } else {}
        } else {}
      } else {}

      if (mounted) {
        setState(() {});
      }
    } catch (e) {}
  }

  @override
  void dispose() {
    try {
      _clearContactProviderSearchState();

      _notesController.removeListener(_onFormChanged);
      _notesController.dispose();
      _debounce?.cancel();
      _selectedCustomer = null;
      _quoteLines.clear();
    } finally {
      super.dispose();
    }
  }

  Future<Map<String, dynamic>?>? _orderHeaderFuture;

  /// The order being edited as the server has it now: its company, pricelist,
  /// payment term and state. Null when creating one, or when it cannot be read.
  Future<Map<String, dynamic>?> _orderHeader() =>
      _orderHeaderFuture ??= _readOrderHeader();

  Future<Map<String, dynamic>?> _readOrderHeader() async {
    final orderId = widget.quotationToEdit?['id'];
    if (orderId is! int) return null;
    try {
      final client = await OdooSessionManager.getClient();
      final rows = await client?.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [orderId],
          ['company_id', 'pricelist_id', 'payment_term_id', 'state'],
        ],
        'kwargs': {},
      });
      if (rows is List && rows.isNotEmpty && rows.first is Map) {
        return Map<String, dynamic>.from(rows.first as Map);
      }
    } catch (_) {}
    return null;
  }

  /// A many2one value (`[id, name]`) as the id/name map the form's lists use.
  Map<String, dynamic>? _recordFrom(dynamic value) {
    if (value is List && value.length > 1 && value.first is int) {
      return {'id': value.first, 'name': value[1], 'display_name': value[1]};
    }
    return null;
  }

  Future<_QuoteCompany>? _companyFuture;

  /// The company this quotation belongs to, and the scope its lists are cached
  /// under: a quotation being edited keeps the company it was made in, a new
  /// one takes the company selected in the app, as Odoo's own form does.
  Future<_QuoteCompany> _quoteCompany() => _companyFuture ??= _resolveCompany();

  Future<_QuoteCompany> _resolveCompany() async {
    final session = await OdooSessionManager.getCurrentSession();
    int? companyId = session?.selectedCompanyId;

    final header = await _orderHeader();
    final value = header?['company_id'];
    if (value is List && value.isNotEmpty && value.first is int) {
      companyId = value.first as int;
    } else if (value is int) {
      companyId = value;
    }
    if (companyId == 0) companyId = null;

    return _QuoteCompany(
      id: companyId,
      scope: '${session?.database}|${session?.userId}|$companyId',
    );
  }

  Future<void> _loadPaymentTerms() async {
    final company = await _quoteCompany();
    if (_paymentTermsCache != null &&
        _paymentTermsCacheTime != null &&
        _listsCacheScope == company.scope &&
        DateTime.now().difference(_paymentTermsCacheTime!) < _cacheDuration) {
      if (mounted) {
        final uniqueList = <int, Map<String, dynamic>>{};
        for (var term in _paymentTermsCache!) {
          final id = term['id'] as int;
          uniqueList[id] = term;
        }
        setState(() {
          _paymentTerms = uniqueList.values.toList();
        });
      }
      return;
    }

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      // Odoo's form offers the terms with no company or the quotation's own.
      final paymentTerms = await client.callKw({
        'model': 'account.payment.term',
        'method': 'search_read',
        'args': [company.domain],
        'kwargs': {
          'fields': ['id', 'name'],
          'context': company.context,
        },
      });

      final list = List<Map<String, dynamic>>.from(paymentTerms);

      final uniqueList = <int, Map<String, dynamic>>{};
      for (var term in list) {
        final id = term['id'] as int;
        uniqueList[id] = term;
      }
      final deduplicatedList = uniqueList.values.toList();

      _paymentTermsCache = deduplicatedList;
      _paymentTermsCacheTime = DateTime.now();
      _listsCacheScope = company.scope;

      if (mounted) {
        setState(() {
          _paymentTerms = deduplicatedList;
        });
      }
    } catch (e) {}
  }

  Future<void> _loadPricelists() async {
    final company = await _quoteCompany();
    if (_pricelistsCache != null &&
        _pricelistsCacheTime != null &&
        _listsCacheScope == company.scope &&
        DateTime.now().difference(_pricelistsCacheTime!) < _cacheDuration) {
      if (mounted) {
        final uniqueList = <int, Map<String, dynamic>>{};
        for (var pricelist in _pricelistsCache!) {
          final id = pricelist['id'] as int;
          uniqueList[id] = pricelist;
        }
        setState(() {
          _pricelists = uniqueList.values.toList();
        });
      }
      return;
    }

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return;

      // Odoo's form offers the pricelists with no company or the quotation's
      // own. Asked with no company at all, the server answers for every company
      // the user may use, and a quotation could end up with another company's
      // pricelist.
      final pricelists = await client.callKw({
        'model': 'product.pricelist',
        'method': 'search_read',
        'args': [company.domain],
        'kwargs': {
          'fields': ['id', 'name', 'currency_id'],
          'context': company.context,
        },
      });

      final list = List<Map<String, dynamic>>.from(pricelists);

      final uniqueList = <int, Map<String, dynamic>>{};
      for (var pricelist in list) {
        final id = pricelist['id'] as int;
        uniqueList[id] = pricelist;
      }
      final deduplicatedList = uniqueList.values.toList();

      _pricelistsCache = deduplicatedList;
      _pricelistsCacheTime = DateTime.now();
      _listsCacheScope = company.scope;

      if (mounted) {
        setState(() {
          _pricelists = deduplicatedList;
        });
      }
    } catch (e) {}
  }

  Future<void> _loadCustomerDefaults(Contact customer) async {
    if (!mounted) return;

    setState(() {
      _isLoadingPaymentTermsShimmer = true;
      _isLoadingPricelistsShimmer = true;
    });

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      // Both are company-dependent properties: read for the quotation's
      // company, not the user's default one.
      final company = await _quoteCompany();
      final result = await client.callKw({
        'model': 'res.partner',
        'method': 'read',
        'args': [
          customer.id,
          ['property_payment_term_id', 'property_product_pricelist'],
        ],
        'kwargs': {'context': company.context},
      });

      if (mounted && result is List && result.isNotEmpty) {
        final data = result[0];

        if (data['property_payment_term_id'] is List) {
          final term = data['property_payment_term_id'];
          _selectedPaymentTerm = _paymentTerms.firstWhere(
            (t) => t['id'] == term[0],
            orElse: () => {'id': term[0], 'name': term[1] ?? 'Term ${term[0]}'},
          );
        }

        if (data['property_product_pricelist'] is List) {
          final pricelist = data['property_product_pricelist'];
          _selectedPricelist = _pricelists.firstWhere(
            (p) => p['id'] == pricelist[0],
            orElse: () => {
              'id': pricelist[0],
              'name': pricelist[1] ?? 'Pricelist ${pricelist[0]}',
              'display_name': pricelist[1] ?? 'Pricelist ${pricelist[0]}',
            },
          );
        }

        if (mounted) setState(() {});
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to load customer defaults: $e',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingPaymentTermsShimmer = false;
          _isLoadingPricelistsShimmer = false;
        });
      }
    }
  }

  /// Options for a Mobo select over Odoo id/name maps, keyed on the id's string
  /// form. The first entry for an id wins, as the lists are not guaranteed
  /// unique.
  List<MoboOption<String>> _mapOptions(
    List<Map<String, dynamic>> items,
    Object Function(Map<String, dynamic> item) labelOf,
  ) {
    final seen = <String>{};
    return [
      for (final item in items)
        if (item['id'] != null && seen.add(item['id'].toString()))
          MoboOption<String>(
            value: item['id'].toString(),
            label: labelOf(item).toString(),
          ),
    ];
  }

  Widget _buildShimmerDropdown(String label) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Shimmer.fromColors(
      baseColor: isDark ? Colors.grey[700]! : Colors.grey[300]!,
      highlightColor: isDark ? Colors.grey[600]! : Colors.grey[100]!,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.grey[200],
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            Icon(
              Icons.arrow_drop_down,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ],
        ),
      ),
    );
  }

  void _removeLine(int index) {
    final isConfirmedOrder =
        widget.quotationToEdit != null &&
        widget.quotationToEdit!['state'] == 'sale';

    if (isConfirmedOrder) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.red, size: 28),
              const SizedBox(width: 12),
              const Text('Invalid Operation'),
            ],
          ),
          content: const Text(
            'Once a sales order is confirmed, you can\'t remove one of its lines (we need to track if something gets invoiced or delivered).\n\nSet the quantity to 0 instead.',
            style: TextStyle(fontSize: 15),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    setState(() {
      _quoteLines.removeAt(index);
    });

    _scheduleTaxRecalc();
  }

  void _editLine(int index) {
    _showEditLineDialog(index);
  }

  void _updateLine(int index, double quantity, double unitPrice) {
    setState(() {
      _quoteLines[index]['quantity'] = quantity;
      _quoteLines[index]['unit_price'] = unitPrice;
      _quoteLines[index]['subtotal'] = quantity * unitPrice;
    });

    _scheduleTaxRecalc();
  }

  void _showEditLineDialog(int index) {
    final line = _quoteLines[index];
    final quantityController = TextEditingController(
      text: line['quantity'].toString(),
    );
    final priceController = TextEditingController(
      text: line['unit_price'].toString(),
    );

    // Update stays off until a value differs from what the dialog opened with.
    // Values compare as numbers, so retyping 1.0 as 1 is not a change.
    Object valueOf(TextEditingController c) =>
        double.tryParse(c.text) ?? c.text.trim();
    final changes = FormChangeTracker(
      () => {
        'quantity': valueOf(quantityController),
        'unitPrice': valueOf(priceController),
      },
    )..markClean();
    StateSetter? setButtonState;
    void onValuesChanged() => setButtonState?.call(() {});
    quantityController.addListener(onValuesChanged);
    priceController.addListener(onValuesChanged);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Edit ${line['product_name']}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: quantityController,
              decoration: const InputDecoration(
                labelText: 'Quantity',
                border: OutlineInputBorder(),
              ),
              keyboardType: TextInputType.number,
            ),
            const SizedBox(height: 16),
            TextField(
              controller: priceController,
              decoration: InputDecoration(
                labelText: 'Unit Price',
                border: const OutlineInputBorder(),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(
                    left: 12,
                    right: 8,
                    top: 12,
                    bottom: 12,
                  ),
                  child: Consumer<CurrencyProvider>(
                    builder: (context, currencyProvider, _) {
                      final code =
                          (currencyProvider.companyCurrencyIdList != null &&
                              currencyProvider.companyCurrencyIdList!.length >
                                  1)
                          ? currencyProvider.companyCurrencyIdList![1]
                                .toString()
                          : currencyProvider.currency;
                      return Text(
                        code,
                        style: const TextStyle(color: Colors.grey),
                      );
                    },
                  ),
                ),
                prefixIconConstraints: const BoxConstraints(
                  minWidth: 0,
                  minHeight: 0,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 8,
                  horizontal: 12,
                ),
              ),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
          ],
        ),
        actionsPadding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
        actions: [
          StatefulBuilder(
            builder: (context, setState) {
              setButtonState = setState;
              return MoboDialogButtons(
                secondaryLabel: 'Cancel',
                onSecondary: () => Navigator.pop(context),
                primaryLabel: 'Update',
                onPrimary: changes.isDirty
                    ? () {
                        final quantity =
                            double.tryParse(quantityController.text) ?? 1.0;
                        final price =
                            double.tryParse(priceController.text) ?? 0.0;
                        _updateLine(index, quantity, price);
                        Navigator.pop(context);
                      }
                    : null,
              );
            },
          ),
        ],
      ),
    );
  }

  double get _subtotal =>
      _quoteLines.fold(0.0, (sum, line) => sum + (line['subtotal'] as double));

  double _calculatedTaxAmount = 0.0;
  bool _isCalculatingTax = false;

  double get _taxAmount => _calculatedTaxAmount;

  bool get isCalculatingTax => _isCalculatingTax;

  Future<void> _calculateTaxAmount() async {
    if (_quoteLines.isEmpty || _selectedCustomer == null) {
      setState(() {
        _calculatedTaxAmount = 0.0;
        _isCalculatingTax = false;
      });
      return;
    }

    setState(() => _isCalculatingTax = true);

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) {
        setState(() {
          _calculatedTaxAmount = 0.0;
          _isCalculatingTax = false;
        });
        return;
      }

      bool hasAnyTaxes = false;
      for (final line in _quoteLines) {
        final productId = _toIntId(line['product_id']);
        if (productId == null) continue;

        final taxIds = await _fetchProductTaxInfo(productId);
        if (taxIds.isNotEmpty) {
          hasAnyTaxes = true;
          break;
        }
      }

      if (!hasAnyTaxes) {
        setState(() {
          _calculatedTaxAmount = 0.0;
          _isCalculatingTax = false;
        });

        return;
      }

      // The unit field is `product_uom` up to Odoo 18 and `product_uom_id` from
      // 19; an unknown server is tried with each in turn.
      final generation = await OdooSessionManager.serverGeneration();
      final uomSpellings = SaleLineFields.candidates(generation);

      final orderData = <String, dynamic>{
        'partner_id': _selectedCustomer!.id,
        'order_line': _buildOrderLineCommands(uomSpellings.first.uom),
        'payment_term_id': _selectedPaymentTerm?['id'],
        // Up to Odoo 18 the estimate pins the order to no fiscal position. From
        // 19 the server picks the customer's own, as it will for the saved
        // quotation, so the estimate carries that position's tax mapping.
        if (saleUsesFiscalPositionTaxModel(generation))
          'fiscal_position_id': false,
      };

      if (_selectedPricelist != null && _selectedPricelist!['id'] != null) {
        orderData['pricelist_id'] = _selectedPricelist!['id'];
      }

      int? orderId;
      try {
        orderId = await client.callKw({
          'model': 'sale.order',
          'method': 'create',
          'args': [orderData],
          'kwargs': {},
        });
      } catch (e) {
        if (uomSpellings.length > 1 &&
            (e.toString().contains('product_uom') ||
                e.toString().contains('Invalid field'))) {
          orderData['order_line'] = _buildOrderLineCommands(
            uomSpellings[1].uom,
          );

          orderId = await client.callKw({
            'model': 'sale.order',
            'method': 'create',
            'args': [orderData],
            'kwargs': {},
          });
        } else {
          rethrow;
        }
      }

      if (orderId == null) throw Exception('Failed to create temporary order');

      final order = await client.callKw({
        'model': 'sale.order',
        'method': 'read',
        'args': [
          [orderId],
        ],
        'kwargs': {
          'fields': ['amount_tax', 'amount_total', 'amount_untaxed'],
        },
      });

      if (order is List && order.isNotEmpty) {
        final taxAmount = (order[0]['amount_tax'] as num?)?.toDouble() ?? 0.0;
        setState(() => _calculatedTaxAmount = taxAmount);
      }

      try {
        await client.callKw({
          'model': 'sale.order',
          'method': 'unlink',
          'args': [
            [orderId],
          ],
          'kwargs': {},
        });
      } catch (e) {}
    } catch (createError) {
      if (createError.toString().contains('product_uom')) {
        try {
          await _calculateTaxesWithFallbackUom();
          return;
        } catch (fallbackError) {}
      }

      setState(() => _calculatedTaxAmount = 0.0);
    } finally {
      if (mounted) {
        setState(() => _isCalculatingTax = false);
      }
    }
  }

  /// The `order_line` create commands for the lines on the form, with the unit
  /// of measure under [uomField] (`product_uom` up to Odoo 18, `product_uom_id`
  /// from 19).
  List<List<dynamic>> _buildOrderLineCommands(String uomField) =>
      saleOrderLineCommands(_quoteLines, uomField, _toIntId);

  void _fallbackTaxCalculation() {
    setState(() => _calculatedTaxAmount = 0.0);
  }

  Future<void> _calculateTaxesWithFallbackUom() async {
    final client = await OdooSessionManager.getClient();
    if (client == null) return;

    final generation = await OdooSessionManager.serverGeneration();

    final orderData = <String, dynamic>{
      'partner_id': _selectedCustomer!.id,
      'order_line': _buildOrderLineCommands(
        SaleLineFields.candidates(generation).last.uom,
      ),
      'payment_term_id': _selectedPaymentTerm?['id'],
      if (saleUsesFiscalPositionTaxModel(generation))
        'fiscal_position_id': false,
    };

    if (_selectedPricelist != null && _selectedPricelist!['id'] != null) {
      orderData['pricelist_id'] = _selectedPricelist!['id'];
    }

    final orderId = await client.callKw({
      'model': 'sale.order',
      'method': 'create',
      'args': [orderData],
      'kwargs': {},
    });

    if (orderId == null) throw Exception('Failed to create temporary order');

    final order = await client.callKw({
      'model': 'sale.order',
      'method': 'read',
      'args': [
        [orderId],
      ],
      'kwargs': {
        'fields': ['amount_tax', 'amount_total', 'amount_untaxed'],
      },
    });

    if (order is List && order.isNotEmpty) {
      final taxAmount = (order[0]['amount_tax'] as num?)?.toDouble() ?? 0.0;
      setState(() => _calculatedTaxAmount = taxAmount);
    }

    try {
      await client.callKw({
        'model': 'sale.order',
        'method': 'unlink',
        'args': [
          [orderId],
        ],
        'kwargs': {},
      });
    } catch (e) {}
  }

  Future<List<int>> _fetchProductTaxInfo(int productId) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) return [];

      int? userCompanyId;
      try {
        final session = await OdooSessionManager.getCurrentSession();
        if (session != null) {
          final userResult = await client.callKw({
            'model': 'res.users',
            'method': 'search_read',
            'args': [
              [
                ['login', '=', session.userLogin],
              ],
              ['company_id'],
            ],
            'kwargs': {},
          });
          if (userResult != null && userResult.isNotEmpty) {
            final companyData = userResult[0]['company_id'];
            if (companyData is List && companyData.isNotEmpty) {
              userCompanyId = companyData[0] as int?;
            }
          }
        }
      } catch (e) {}

      final product = await client.callKw({
        'model': 'product.product',
        'method': 'read',
        'args': [
          [productId],
          ['taxes_id', 'supplier_taxes_id', 'company_id'],
        ],
        'kwargs': {},
      });

      if (product is! List || product.isEmpty) return [];
      final productData = product[0];

      List<int> taxIds = [];

      final generation = await OdooSessionManager.serverGeneration();
      if (!saleUsesFiscalPositionTaxModel(generation)) {
        // Odoo 19 dropped `account.fiscal.position.tax`, and no Odoo version
        // has a callable `get_fiscal_position`. The estimate's temporary order
        // takes the customer's fiscal position from the server, which maps the
        // taxes itself, so all this needs to know is whether the product is
        // taxed at all.
        taxIds = _extractTaxIds(productData['taxes_id']);
      } else {
        try {
          final fiscalPosition = await client.callKw({
            'model': 'account.fiscal.position',
            'method': 'get_fiscal_position',
            'args': [_selectedCustomer!.id],
            'kwargs': {},
          });

          final fiscalPositionId = _toIntId(fiscalPosition);
          taxIds = await _getTaxesWithFiscalPosition(
            productData,
            fiscalPositionId,
            client,
          );
        } catch (e) {
          taxIds = _extractTaxIds(productData['taxes_id']);
        }
      }

      if (userCompanyId != null && taxIds.isNotEmpty) {
        try {
          final taxResult = await client.callKw({
            'model': 'account.tax',
            'method': 'search_read',
            'args': [
              [
                ['id', 'in', taxIds],
                ['company_id', '=', userCompanyId],
              ],
            ],
            'kwargs': {
              'fields': ['id'],
            },
          });

          final filteredTaxIds = (taxResult as List)
              .map((t) => t['id'] as int)
              .toList();

          return filteredTaxIds;
        } catch (filterError) {}
      }

      return taxIds;
    } catch (e) {
      return [];
    }
  }

  List<int> _extractTaxIds(dynamic taxesField) {
    if (taxesField == null) return [];

    if (taxesField is List<int>) {
      return taxesField;
    }

    if (taxesField is List) {
      return taxesField.map((e) => _toIntId(e)).whereType<int>().toList();
    }

    final singleId = _toIntId(taxesField);
    return singleId != null ? [singleId] : [];
  }

  Future<List<int>> _getTaxesWithFiscalPosition(
    Map<String, dynamic> productData,
    int? fiscalPositionId,
    OdooClient client,
  ) async {
    List<int> taxIds = _extractTaxIds(productData['taxes_id']);

    if (fiscalPositionId == null) {
      return taxIds;
    }

    try {
      final mappedTaxes = await client.callKw({
        'model': 'account.fiscal.position.tax',
        'method': 'search_read',
        'args': [
          [
            ['position_id', '=', fiscalPositionId],
          ],
        ],
        'kwargs': {
          'fields': ['tax_src_id', 'tax_dest_id'],
        },
      });

      final taxMapping = <int, int>{};
      if (mappedTaxes is List) {
        for (final map in mappedTaxes) {
          final srcId = _toIntId(map['tax_src_id']);
          final destId = _toIntId(map['tax_dest_id']);
          if (srcId != null && destId != null) {
            taxMapping[srcId] = destId;
          }
        }
      }

      return taxIds.map((id) => taxMapping[id] ?? id).toList();
    } catch (e) {
      return taxIds;
    }
  }

  Future<String?> _getDefaultPickingPolicy({
    int? defaultWarehouseId,
    int? defaultPartnerId,
  }) async {
    final client = await OdooSessionManager.getClient();
    if (client == null) throw Exception('No active Odoo session');

    final ctx = <String, dynamic>{};
    if (defaultWarehouseId != null) {
      ctx['default_warehouse_id'] = defaultWarehouseId;
    }
    if (defaultPartnerId != null) ctx['default_partner_id'] = defaultPartnerId;

    final defaults = await client.callKw({
      'model': 'sale.order',
      'method': 'default_get',
      'args': ['picking_policy'],
      'kwargs': {'context': ctx},
    });

    if (defaults is Map && defaults['picking_policy'] is String) {
      return defaults['picking_policy'] as String;
    }
    return null;
  }

  Future<void> _saveQuote() async {
    if (!_formKey.currentState!.validate()) return;
    if (_selectedCustomer == null) {
      _showErrorSnackBar('Please select a customer');
      return;
    }
    if (_quoteLines.isEmpty) {
      _showErrorSnackBar('Please add at least one product');
      return;
    }

    setState(() => _isLoading = true);

    // The loading card, closed exactly once whichever path gets there first.
    // This used to be a `pop` in a `finally` that ran after the success path had
    // already closed the card AND this screen, and that second pop took the
    // screen underneath (the quotation's details) with it — so the details never
    // refreshed and never showed their "updated" message.
    final loading = LoadingDialog.open(
      context,
      message: widget.quotationToEdit != null
          ? 'Updating quotation...'
          : 'Creating quotation...',
      subtitle: widget.quotationToEdit != null
          ? 'Please wait while we update your quotation.'
          : 'Please wait while we create your quotation.',
    );
    void closeLoading() => loading.close();

    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');

      final isEditing = widget.quotationToEdit != null && _quotationId != null;

      if (isEditing) {
        // Written in the quotation's own company, so what the server computes
        // from it (pricelist, fiscal position, taxes) is that company's.
        final company = await _quoteCompany();
        String? savedNote;
        var savedNoteIsWarning = false;

        // Fields the order's state makes read-only are left out, as Odoo's own
        // form leaves them out.
        final locked = _customerAndPricelistLocked;
        final updateData = {
          if (!locked) 'partner_id': _selectedCustomer!.id,
          if (!locked)
            'validity_date': _validityDate?.toIso8601String().split('T')[0],
          // Back to HTML, or Odoo stores the typed text as markup: the
          // angle brackets and ampersands of an existing Terms & Conditions
          // block would be re-interpreted a little further on every save.
          'note': plainTextToHtml(_notesController.text) ?? false,
        };

        if (_selectedPaymentTerm != null) {
          updateData['payment_term_id'] = _selectedPaymentTerm!['id'];
        } else {
          updateData['payment_term_id'] = false;
        }

        if (!locked) {
          if (_selectedPricelist != null) {
            updateData['pricelist_id'] = _selectedPricelist!['id'];
          } else {
            updateData['pricelist_id'] = false;
          }
        }

        final defaultPickingPolicy = await _getDefaultPickingPolicy(
          defaultPartnerId: _selectedCustomer!.id,
        );
        if (defaultPickingPolicy != null) {
          updateData['picking_policy'] = defaultPickingPolicy;
        }

        // The unit field is `product_uom` up to Odoo 18 and `product_uom_id`
        // from 19; an unknown server is retried with the other spelling below.
        final generation = await OdooSessionManager.serverGeneration();
        final uomSpellings = SaleLineFields.candidates(generation);

        final orderLines = _buildOrderLineCommands(uomSpellings.first.uom);

        final existingQuotation = await client.callKw({
          'model': 'sale.order',
          'method': 'read',
          'args': [
            [_quotationId],
          ],
          'kwargs': {
            'fields': ['order_line'],
          },
        });

        if (existingQuotation != null &&
            existingQuotation is List &&
            existingQuotation.isNotEmpty) {
          final existingLines = existingQuotation[0]['order_line'];
          if (existingLines != null &&
              existingLines is List &&
              existingLines.isNotEmpty) {
            for (var lineId in existingLines) {
              orderLines.insert(0, [2, lineId, false]);
            }
          }
        }

        updateData['order_line'] = orderLines;

        try {
          await client.callKw({
            'model': 'sale.order',
            'method': 'write',
            'args': [
              [_quotationId],
              updateData,
            ],
            'kwargs': {'context': company.context},
          });
        } catch (writeError) {
          if (writeError.toString().contains(
            'You cannot change the pricelist of a confirmed order',
          )) {
            final updateDataWithoutPricelist = Map<String, dynamic>.from(
              updateData,
            );
            updateDataWithoutPricelist.remove('pricelist_id');

            try {
              await client.callKw({
                'model': 'sale.order',
                'method': 'write',
                'args': [
                  [_quotationId],
                  updateDataWithoutPricelist,
                ],
                'kwargs': {'context': company.context},
              });

              savedNote =
                  'Order updated successfully. Note: Pricelist cannot be changed on confirmed orders.';
              savedNoteIsWarning = true;
            } catch (retryError) {
              if (retryError.toString().contains(
                    'you can\'t remove one of its lines',
                  ) ||
                  retryError.toString().contains(
                    'Set the quantity to 0 instead',
                  )) {
                try {
                  await _updateConfirmedOrderLines(
                    client,
                    updateDataWithoutPricelist,
                  );

                  closeLoading();
                  final state =
                      widget.quotationToEdit?['state']?.toString() ?? '';
                  final documentType = (state == 'sale')
                      ? 'Sale Order'
                      : 'Quotation';
                  DataChangeBus.instance.quotationChanged(_quotationId);
                  if (mounted && context.mounted) {
                    _savedSuccessfully = true;
                    Navigator.pop(
                      context,
                      QuoteSaved(
                        note:
                            '$documentType updated successfully. Only existing line quantities were updated on this confirmed order.',
                      ),
                    );
                  }
                  return;
                } catch (updateError) {
                  if (mounted && context.mounted) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted && context.mounted) {
                        CustomSnackbar.showError(
                          context,
                          'Cannot modify this confirmed order. Please contact your administrator.',
                        );
                      }
                    });
                  }
                  return;
                }
              }

              rethrow;
            }
          } else if (uomSpellings.length > 1 &&
              writeError.toString().contains('product_uom')) {
            // The server did not know the first spelling of the unit field (it
            // is not known which Odoo this is): write again with the other.
            final fallbackOrderLines = <List<dynamic>>[];

            if (existingQuotation != null &&
                existingQuotation is List &&
                existingQuotation.isNotEmpty) {
              final existingLines = existingQuotation[0]['order_line'];
              if (existingLines != null &&
                  existingLines is List &&
                  existingLines.isNotEmpty) {
                for (var lineId in existingLines) {
                  fallbackOrderLines.add([2, lineId, false]);
                }
              }
            }

            fallbackOrderLines.addAll(
              _buildOrderLineCommands(uomSpellings[1].uom),
            );

            updateData['order_line'] = fallbackOrderLines;

            await client.callKw({
              'model': 'sale.order',
              'method': 'write',
              'args': [
                [_quotationId],
                updateData,
              ],
              'kwargs': {'context': company.context},
            });
          } else {
            String errorMessage = 'Failed to update quotation';

            if (writeError.toString().contains(
                  'you can\'t remove one of its lines',
                ) ||
                writeError.toString().contains(
                  'Set the quantity to 0 instead',
                )) {
              errorMessage =
                  'Cannot modify confirmed order lines. You can only update quantities, not add/remove products.';
            } else if (writeError.toString().contains('UserError')) {
              final regex = RegExp(r'message: ([^,}]+)');
              final match = regex.firstMatch(writeError.toString());
              if (match != null) {
                errorMessage = match.group(1)?.trim() ?? errorMessage;
              }
            }

            if (mounted && context.mounted) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && context.mounted) {
                  CustomSnackbar.showError(context, errorMessage);
                }
              });
            }

            return;
          }
        }

        closeLoading();
        // Announced before the pop: the details screen behind this one, the
        // list, the dashboard and a customer's page all refresh from it.
        DataChangeBus.instance.quotationChanged(_quotationId);
        if (mounted) {
          _savedSuccessfully = true;
          Navigator.pop(
            context,
            QuoteSaved(note: savedNote, noteIsWarning: savedNoteIsWarning),
          );
        }
      } else {
        // The unit field is `product_uom` up to Odoo 18 and `product_uom_id`
        // from 19; an unknown server is retried with the other spelling below.
        final generation = await OdooSessionManager.serverGeneration();
        final uomSpellings = SaleLineFields.candidates(generation);

        final orderLines = _buildOrderLineCommands(uomSpellings.first.uom);

        final defaultPickingPolicy = await _getDefaultPickingPolicy(
          defaultPartnerId: _selectedCustomer!.id,
        );

        final company = await _quoteCompany();
        final quoteData = {
          'partner_id': _selectedCustomer!.id,
          if (company.id != null) 'company_id': company.id,
          'validity_date': _validityDate?.toIso8601String().split('T')[0],
          'note': plainTextToHtml(_notesController.text) ?? false,
          'order_line': orderLines,
          'state': 'draft',
        };

        if (defaultPickingPolicy != null) {
          quoteData['picking_policy'] = defaultPickingPolicy;
        }

        if (_selectedPaymentTerm != null) {
          quoteData['payment_term_id'] = _selectedPaymentTerm!['id'];
        }

        if (_selectedPricelist != null) {
          quoteData['pricelist_id'] = _selectedPricelist!['id'];
        }

        int? quoteId;
        try {
          quoteId = await client
              .callKw({
                'model': 'sale.order',
                'method': 'create',
                'args': [quoteData],
                'kwargs': {'context': company.context},
              })
              .timeout(const Duration(seconds: 60));
        } catch (createError) {
          if (uomSpellings.length > 1 &&
              (createError.toString().contains('product_uom') ||
                  createError.toString().contains('Invalid field'))) {
            quoteData['order_line'] = _buildOrderLineCommands(
              uomSpellings[1].uom,
            );

            quoteId = await client
                .callKw({
                  'model': 'sale.order',
                  'method': 'create',
                  'args': [quoteData],
                  'kwargs': {'context': company.context},
                })
                .timeout(const Duration(seconds: 60));
          } else {
            rethrow;
          }
        }
        if (quoteId != null) {
          closeLoading();
          if (mounted) {
            String quotationName = 'Quotation';
            try {
              final quotationData = await client.callKw({
                'model': 'sale.order',
                'method': 'read',
                'args': [
                  [quoteId],
                ],
                'kwargs': {
                  'fields': ['name'],
                },
              });
              if (quotationData != null &&
                  quotationData is List &&
                  quotationData.isNotEmpty) {
                quotationName =
                    quotationData[0]['name']?.toString() ?? 'Quotation';
              }
            } catch (e) {}

            ReviewService().trackSignificantEvent();
            DataChangeBus.instance.quotationChanged(
              quoteId,
              kind: DataChangeKind.created,
            );

            await showQuotationCreatedConfettiDialog(context, quotationName);

            if (mounted) {
              _savedSuccessfully = true;
              ReviewService().checkAndShowRating(context);
              Navigator.pop(context, true);
            }
          }
        } else {
          throw Exception('Failed to create quotation');
        }
      }
    } catch (e) {
      final action = widget.quotationToEdit != null ? 'update' : 'create';
      if (e is TimeoutException) {
        _showErrorSnackBar(
          'The server took too long to $action the quotation (over 60 seconds). '
          'It may still have been saved — please check your quotations list before trying again.',
        );
      } else {
        _showErrorSnackBar(
          OdooErrorHandler.toUserMessage(
            e,
            defaultMessage:
                'Failed to $action the quotation. Please try again.',
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }

      closeLoading();
    }
  }

  void _showErrorSnackBar(String message) {
    if (mounted) {
      CustomSnackbar.showError(context, message);
    }
  }

  void _showSuccessSnackBar(String message) {
    if (mounted) {
      CustomSnackbar.showSuccess(context, message);
    }
  }

  double get _total => _subtotal + _taxAmount;

  Future<void> _selectValidityDate() async {
    final date = await DatePickerUtils.showStandardDatePicker(
      context: context,
      initialDate:
          _validityDate ?? DateTime.now().add(const Duration(days: 30)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Select Validity Date',
      cancelText: 'Cancel',
      confirmText: 'Select',
    );

    if (date != null && mounted) {
      setState(() {
        _validityDate = date;
      });
    }
  }

  Widget _buildSelectedCustomerTile() {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Card(
      margin: const EdgeInsets.only(top: 0),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey[850] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (_selectedCustomer!.imageUrl != null &&
                    _selectedCustomer!.imageUrl!.startsWith('http'))
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: isDark
                        ? Colors.grey[100]
                        : Colors.grey[200],
                    child: ClipOval(
                      child: Image.network(
                        _selectedCustomer!.imageUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            _buildAvatarFallback(_selectedCustomer!),
                      ),
                    ),
                  )
                else
                  CircularImageWidget(
                    base64Image: _selectedCustomer!.imageUrl,
                    radius: 20,
                    fallbackText: _selectedCustomer!.name,
                    backgroundColor: isDark
                        ? Colors.grey[100]!
                        : Colors.grey[200]!,
                    textColor: isDark ? Colors.black87 : Colors.black87,
                  ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _selectedCustomer!.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (_selectedCustomer!.isCompany == true)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.white.withOpacity(.1)
                                    : Theme.of(
                                        context,
                                      ).primaryColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Company',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : Theme.of(context).primaryColor,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (_isValidField(_selectedCustomer!.function))
                        Text(
                          _selectedCustomer!.function!,
                          style: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.customer == null)
                  IconButton(
                    icon: Icon(
                      HugeIcons.strokeRoundedCancelCircleHalfDot,

                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedCustomer = null;
                        _selectedPaymentTerm = null;
                        _selectedPricelist = null;
                        _isLoadingPaymentTermsShimmer = false;
                        _isLoadingPricelistsShimmer = false;
                      });

                      if (_quoteLines.isNotEmpty) {
                        _scheduleTaxRecalc();
                      }
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (_isValidField(_selectedCustomer!.email))
                  _buildInfoChip(
                    Icons.email_outlined,
                    _selectedCustomer!.email!,
                    isDark,
                  ),
                if (_isValidField(_selectedCustomer!.phone))
                  _buildInfoChip(
                    Icons.phone_outlined,
                    _selectedCustomer!.phone!,
                    isDark,
                  ),
                if (_isValidField(_selectedCustomer!.mobile))
                  _buildInfoChip(
                    Icons.smartphone_outlined,
                    _selectedCustomer!.mobile!,
                    isDark,
                  ),
                if (_buildAddressString(_selectedCustomer!).isNotEmpty)
                  _buildInfoChip(
                    Icons.location_on_outlined,
                    _buildAddressString(_selectedCustomer!),
                    isDark,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProfessionalCard({
    required String title,
    required List<Widget> children,
    IconData? icon,
    Color? headerColor,
    bool showDivider = true,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.18)
                : Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
              ),
            ),
            child: Row(
              children: [
                if (icon != null) ...[
                  Icon(
                    icon,
                    size: 20,
                    color:
                        headerColor ??
                        (isDark ? Colors.blue[400] : Colors.blue[600]),
                  ),
                  const SizedBox(width: 12),
                ],
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.grey[900],
                    letterSpacing: -0.3,
                  ),
                ),
              ],
            ),
          ),
          if (showDivider)
            Divider(
              height: 1,
              color: isDark ? Colors.grey[700] : Colors.grey[200],
            ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  bool _isValidField(String? field) {
    return field != null &&
        field.isNotEmpty &&
        field != 'false' &&
        field != 'False' &&
        field.trim().isNotEmpty;
  }

  Widget _buildContactInfo(IconData icon, String value) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[600],
                fontSize: 13,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String value, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[700],
                fontSize: 12,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDropdownContactInfo(IconData icon, String value, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: 12,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              value,
              style: TextStyle(
                color: isDark ? Colors.grey[300] : Colors.grey[600],
                fontSize: 11,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _buildAddressString(Contact contact) {
    final addressParts = <String>[];

    if (contact.street != null &&
        contact.street!.isNotEmpty &&
        contact.street != 'false') {
      addressParts.add(contact.street!);
    }
    if (contact.street2 != null &&
        contact.street2!.isNotEmpty &&
        contact.street2 != 'false') {
      addressParts.add(contact.street2!);
    }
    if (contact.city != null &&
        contact.city!.isNotEmpty &&
        contact.city != 'false') {
      addressParts.add(contact.city!);
    }
    if (contact.state != null &&
        contact.state!.isNotEmpty &&
        contact.state != 'false') {
      addressParts.add(contact.state!);
    }
    if (contact.zip != null &&
        contact.zip!.isNotEmpty &&
        contact.zip != 'false') {
      addressParts.add(contact.zip!);
    }
    if (contact.country != null &&
        contact.country!.isNotEmpty &&
        contact.country != 'false') {
      addressParts.add(contact.country!);
    }

    return addressParts.join(', ');
  }

  Widget _buildAvatarFallback(Contact contact) {
    final initial = contact.name.isNotEmpty
        ? contact.name[0].toUpperCase()
        : '?';

    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [
            Theme.of(context).primaryColor.withOpacity(0.8),
            Theme.of(context).primaryColor,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 16,
          ),
        ),
      ),
    );
  }

  Widget _buildBase64Avatar(Contact contact) {
    try {
      final bytes = base64Decode(contact.imageUrl!);
      return Image.memory(
        bytes,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            _buildAvatarFallback(contact),
      );
    } catch (e) {
      return _buildAvatarFallback(contact);
    }
  }

  Widget _buildCreateQuoteShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? Colors.grey[850]! : Colors.white;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[600]! : Colors.grey[100]!;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildCustomerShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildQuoteDetailsShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildProductsShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildTotalsShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildButtonShimmer(baseColor),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 160,
                  height: 18,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        width: double.infinity,
                        height: 16,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 120,
                        height: 14,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuoteDetailsShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 120,
                  height: 18,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  height: 80,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductsShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  width: 80,
                  height: 18,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Container(
                  width: double.infinity,
                  height: 56,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                const SizedBox(height: 20),

                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(32),
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(24),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        width: 180,
                        height: 16,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 200,
                        height: 14,
                        decoration: BoxDecoration(
                          color: cardBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsShimmer(Color cardBg, Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        color: cardBg,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 80,
                  height: 16,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 60,
                  height: 16,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 40,
                  height: 16,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 50,
                  height: 16,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Divider(color: Colors.grey[300]),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  width: 50,
                  height: 18,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                Container(
                  width: 80,
                  height: 18,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildButtonShimmer(Color baseColor) {
    return Container(
      width: double.infinity,
      height: 56,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    return Consumer2<ConnectivityService, SessionService>(
      builder: (context, connectivityService, sessionService, child) {
        if (!connectivityService.isConnected ||
            !sessionService.hasValidSession) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.quotationToEdit != null
                    ? (_quotationName != null
                          ? 'Edit $_quotationName'
                          : 'Edit Quotation')
                    : 'Create Quotation',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              foregroundColor: isDark ? Colors.white : primaryColor,
              elevation: 0,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  Icons.arrow_back,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),
            body: ConnectionStatusWidget(
              onRetry: () async {
                final ok = await connectivityService.checkConnectivityOnce();
                if (ok && mounted) {
                  setState(() {});
                }
              },
            ),
          );
        }

        final contactProvider = context.watch<ContactProvider>();
        if (contactProvider.isServerUnreachable) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.quotationToEdit != null
                    ? (_quotationName != null
                          ? 'Edit $_quotationName'
                          : 'Edit Quotation')
                    : 'Create Quotation',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              foregroundColor: isDark ? Colors.white : primaryColor,
              elevation: 0,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  HugeIcons.strokeRoundedArrowLeft01,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
            ),

            body: ConnectionStatusWidget(
              onRetry: () async {
                setState(() {});
              },
              serverUnreachable: true,
              serverErrorMessage:
                  'Unable to reach server. Please check your connection or try again.',
            ),
          );
        }

        final popChild = PopScope(
          canPop: !hasUnsavedData,
          onPopInvoked: (didPop) async {
            if (didPop) return;
            final shouldPop = await handleWillPop();
            if (shouldPop && mounted) {
              Navigator.of(context).pop();
            }
          },
          child: _buildContent(
            context,
            isDark,
            isDark ? Colors.grey[900]! : Colors.grey[50]!,
          ),
        );
        return withBackGuard(popChild);
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    bool isDark,
    Color backgroundColor,
  ) {
    if (_isInitialLoad) {
      return Scaffold(
        backgroundColor: backgroundColor,
        appBar: AppBar(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          foregroundColor: isDark
              ? Colors.white
              : Theme.of(context).primaryColor,
          elevation: 0,
          title: Text(
            widget.quotationToEdit != null
                ? (_quotationName != null
                      ? 'Edit $_quotationName'
                      : 'Edit Quotation')
                : 'Create Quotation',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          leading: IconButton(
            onPressed: () => handleNavigation(() => Navigator.pop(context)),
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
        ),
        body: _buildCreateQuoteShimmer(),
      );
    }

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
        foregroundColor: isDark ? Colors.white : Theme.of(context).primaryColor,
        elevation: 0,
        title: Text(
          widget.quotationToEdit != null
              ? (_quotationName != null
                    ? 'Edit $_quotationName'
                    : 'Edit Quotation')
              : 'Create Quotation',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => handleNavigation(() => Navigator.pop(context)),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: SafeArea(
        top: false,
        left: false,
        right: false,
        child: _isInitialLoad
            ? _buildCreateQuoteShimmer()
            : SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildProfessionalCard(
                        title: 'Customer Information',
                        children: [
                          // The chosen customer stays in the field, avatar and
                          // name, like an Employee in an expense form. A customer
                          // the screen was opened for is locked in place.
                          CustomerTypeAhead(
                            labelText: 'Customer',
                            isRequired: true,
                            selectedCustomer: _selectedCustomer,
                            allowClear: false,
                            enabled:
                                widget.customer == null &&
                                !_customerAndPricelistLocked,
                            onCustomerSelected: (customer) {
                              final changed =
                                  _selectedCustomer?.id != customer.id;
                              setState(() {
                                _selectedCustomer = customer;
                                // The previous customer's terms and pricelist
                                // are not the new one's: start clean, then take
                                // the new customer's own defaults.
                                if (changed) {
                                  _selectedPaymentTerm = null;
                                  _selectedPricelist = null;
                                }
                              });
                              _loadCustomerDefaults(customer);
                              if (_quoteLines.isNotEmpty) {
                                _scheduleTaxRecalc();
                              }
                            },
                            onClear: () {
                              setState(() {
                                _selectedCustomer = null;
                                _selectedPaymentTerm = null;
                                _selectedPricelist = null;
                                _isLoadingPaymentTermsShimmer = false;
                                _isLoadingPricelistsShimmer = false;
                              });
                              if (_quoteLines.isNotEmpty) {
                                _scheduleTaxRecalc();
                              }
                            },
                            validator: (value) => _selectedCustomer == null
                                ? 'Please select a customer'
                                : null,
                          ),
                        ],
                      ),
                      _buildProfessionalCard(
                        title: 'Quote Details',
                        children: [
                          if (!_isConfirmedOrder) ...[
                            Opacity(
                              opacity: _isCancelledOrder ? 0.6 : 1,
                              child: CustomDateSelector(
                                onTap: _isCancelledOrder
                                    ? () {}
                                    : _selectValidityDate,
                                selectedDate:
                                    _validityDate ??
                                    DateTime.now().add(
                                      const Duration(days: 30),
                                    ),
                                labelText: 'Validity Date',
                                isDark: isDark,
                                showBorder: true,
                              ),
                            ),
                            const SizedBox(height: 20),
                          ],
                          CustomTextField(
                            controller: _notesController,
                            labelText: 'Notes (Optional)',
                            isDark: isDark,
                            maxLines: 3,
                            validator: (value) => null,
                          ),
                          const SizedBox(height: 20),
                          _isLoadingPaymentTermsShimmer
                              ? _buildShimmerDropdown(
                                  'Loading payment terms...',
                                )
                              : MoboSelectField<String>(
                                  label: 'Payment Terms',
                                  hintText: 'Select payment terms (optional)',
                                  value: _selectedPaymentTerm?['id']
                                      ?.toString(),
                                  options: _mapOptions([
                                    ..._paymentTerms,
                                    if (_selectedPaymentTerm != null &&
                                        !_paymentTerms.any(
                                          (t) =>
                                              t['id'] ==
                                              _selectedPaymentTerm!['id'],
                                        ))
                                      _selectedPaymentTerm!,
                                  ], (term) => term['name'] ?? 'Unknown'),
                                  onChanged: (value) {
                                    if (value == null) {
                                      setState(() {
                                        _selectedPaymentTerm = null;
                                      });
                                    } else {
                                      final term = _paymentTerms.firstWhere(
                                        (t) => t['id']?.toString() == value,
                                        orElse: () => <String, dynamic>{},
                                      );
                                      setState(() {
                                        _selectedPaymentTerm = term.isNotEmpty
                                            ? term
                                            : null;
                                      });
                                    }
                                  },
                                ),
                          const SizedBox(height: 20),
                          _isLoadingPricelistsShimmer
                              ? _buildShimmerDropdown('Loading pricelists...')
                              : MoboSelectField<String>(
                                  label: 'Pricelist',
                                  hintText: 'Select pricelist (optional)',
                                  value: _selectedPricelist?['id']?.toString(),
                                  enabled: !_customerAndPricelistLocked,
                                  allowClear: !_customerAndPricelistLocked,
                                  options: _mapOptions(
                                    [
                                      ..._pricelists,
                                      // The order's own pricelist is shown even
                                      // when the list for its company no longer
                                      // holds it (an archived one, say).
                                      if (_selectedPricelist != null &&
                                          !_pricelists.any(
                                            (p) =>
                                                p['id'] ==
                                                _selectedPricelist!['id'],
                                          ))
                                        _selectedPricelist!,
                                    ],
                                    (pricelist) =>
                                        pricelist['display_name'] ??
                                        pricelist['name'] ??
                                        'Unknown',
                                  ),
                                  onChanged: (value) {
                                    if (value == null) {
                                      setState(() {
                                        _selectedPricelist = null;
                                      });
                                    } else {
                                      final pricelist = _pricelists.firstWhere(
                                        (p) => p['id']?.toString() == value,
                                        orElse: () => <String, dynamic>{},
                                      );
                                      setState(() {
                                        _selectedPricelist =
                                            pricelist.isNotEmpty
                                            ? pricelist
                                            : null;
                                      });
                                    }
                                  },
                                ),
                          const SizedBox(height: 20),
                        ],
                      ),
                      _buildProfessionalCard(
                        title: 'Products',
                        children: [
                          ProductTypeAhead(
                            labelText: 'Search Product to Add',
                            isRequired: true,
                            onProductSelected: (product) {
                              setState(() {
                                _isAddingLine = true;
                                final productId = int.tryParse(product.id) ?? 0;
                                final productName = product.name;
                                final unitPrice = product.listPrice;
                                final quantity = 1.0;
                                final subtotal = quantity * unitPrice;

                                final productMap = {
                                  'id': product.id,
                                  'name': product.name,
                                  'list_price': product.listPrice,
                                  'qty_available': product.qtyAvailable,
                                  'default_code': product.defaultCode,
                                  'barcode': product.barcode,
                                  'image_url': product.imageUrl,
                                  'uom_id': product.uomId,
                                  'tax_id': product.taxesIds,
                                };

                                _quoteLines.insert(0, {
                                  'line_uid': _quoteLineUidSeq++,
                                  'product_id': productId,
                                  'product_name': productName,
                                  'uom_id': product.uomId ?? 1,
                                  'quantity': quantity,
                                  'unit_price': unitPrice,
                                  'subtotal': subtotal,
                                  'product_data': productMap,
                                  'discount': 0.0,
                                  'tax_id': product.taxesIds,
                                });
                              });

                              _debouncedTaxRecalc?.cancel();
                              _calculateTaxAmount().whenComplete(() {
                                if (mounted) {
                                  setState(() {
                                    _isAddingLine = false;
                                  });
                                }
                              });
                            },
                          ),
                          const SizedBox(height: 20),
                          if (_quoteLines.isEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.all(32),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[100],
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[200]!,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Icon(
                                    HugeIcons.strokeRoundedShoppingBasket01,
                                    size: 48,
                                    color: isDark
                                        ? Colors.grey[600]
                                        : Colors.grey[400],
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No products added yet',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.w500,
                                      color: isDark
                                          ? Colors.grey[400]
                                          : Colors.grey[600],
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    'Tap "Add Product" to get started',
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: isDark
                                          ? Colors.grey[500]
                                          : Colors.grey[500],
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Column(
                              children: [
                                ...List.generate(_quoteLines.length, (index) {
                                  final line = _quoteLines[index];
                                  final isConfirmedOrder =
                                      widget.quotationToEdit != null &&
                                      widget.quotationToEdit!['state'] ==
                                          'sale';
                                  return _QuoteLineItem(
                                    key: ValueKey(line['line_uid']),
                                    line: line,
                                    index: index,
                                    isLast: index == _quoteLines.length - 1,
                                    isDark: isDark,
                                    isConfirmedOrder: isConfirmedOrder,
                                    onEdit: () => _editLine(index),
                                    onDelete: () => _removeLine(index),
                                    onUpdate: (quantity, unitPrice) =>
                                        _updateLine(index, quantity, unitPrice),
                                  );
                                }),
                                if (_isAddingLine) ...[
                                  const SizedBox(height: 8),
                                  Card(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    elevation: 0,
                                    color: isDark
                                        ? Colors.grey[850]
                                        : Colors.white,
                                    child: const Padding(
                                      padding: EdgeInsets.all(16),
                                      child: Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          ),
                                          SizedBox(width: 10),
                                          Text('Adding product...'),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                                if (_quoteLines.isNotEmpty) ...[
                                  const SizedBox(height: 16),
                                  Container(
                                    padding: const EdgeInsets.all(20),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? Colors.white.withOpacity(.1)
                                          : Colors.blue.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.white.withOpacity(.3)
                                            : Colors.blue.withOpacity(0.3),
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'Subtotal:',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? Colors.grey[300]
                                                      : Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Consumer<CurrencyProvider>(
                                                builder: (context, currencyProvider, _) {
                                                  final code =
                                                      (currencyProvider
                                                                  .companyCurrencyIdList !=
                                                              null &&
                                                          currencyProvider
                                                                  .companyCurrencyIdList!
                                                                  .length >
                                                              1)
                                                      ? currencyProvider
                                                            .companyCurrencyIdList![1]
                                                            .toString()
                                                      : currencyProvider
                                                            .currency;
                                                  final formatted =
                                                      currencyProvider
                                                          .formatAmount(
                                                            _subtotal,
                                                            currency: code,
                                                          );
                                                  return Text(
                                                    formatted,
                                                    style: TextStyle(
                                                      fontSize: 16,
                                                      fontWeight:
                                                          FontWeight.w500,
                                                      color: isDark
                                                          ? Colors.grey[300]
                                                          : Colors.grey[700],
                                                    ),
                                                    textAlign: TextAlign.end,
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),

                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'Tax:',
                                                style: TextStyle(
                                                  fontSize: 16,
                                                  fontWeight: FontWeight.w500,
                                                  color: isDark
                                                      ? Colors.grey[300]
                                                      : Colors.grey[700],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: _isCalculatingTax
                                                  ? Row(
                                                      mainAxisSize:
                                                          MainAxisSize.min,
                                                      children: [
                                                        SizedBox(
                                                          width: 16,
                                                          height: 16,
                                                          child: CircularProgressIndicator(
                                                            strokeWidth: 2,
                                                            valueColor:
                                                                AlwaysStoppedAnimation<
                                                                  Color
                                                                >(
                                                                  isDark
                                                                      ? Colors
                                                                            .blue[300]!
                                                                      : Colors
                                                                            .blue,
                                                                ),
                                                          ),
                                                        ),
                                                        const SizedBox(
                                                          width: 8,
                                                        ),
                                                        Text(
                                                          'Calculating...',
                                                          style: TextStyle(
                                                            fontSize: 14,
                                                            color: isDark
                                                                ? Colors
                                                                      .grey[400]
                                                                : Colors
                                                                      .grey[600],
                                                          ),
                                                        ),
                                                      ],
                                                    )
                                                  : Consumer<CurrencyProvider>(
                                                      builder:
                                                          (
                                                            context,
                                                            currencyProvider,
                                                            _,
                                                          ) {
                                                            final code =
                                                                (currencyProvider
                                                                            .companyCurrencyIdList !=
                                                                        null &&
                                                                    currencyProvider
                                                                            .companyCurrencyIdList!
                                                                            .length >
                                                                        1)
                                                                ? currencyProvider
                                                                      .companyCurrencyIdList![1]
                                                                      .toString()
                                                                : currencyProvider
                                                                      .currency;
                                                            final formatted =
                                                                currencyProvider
                                                                    .formatAmount(
                                                                      _taxAmount,
                                                                      currency:
                                                                          code,
                                                                    );
                                                            return Text(
                                                              formatted,
                                                              style: TextStyle(
                                                                fontSize: 16,
                                                                fontWeight:
                                                                    FontWeight
                                                                        .w500,
                                                                color: isDark
                                                                    ? Colors
                                                                          .grey[300]
                                                                    : Colors
                                                                          .grey[700],
                                                              ),
                                                              textAlign:
                                                                  TextAlign.end,
                                                            );
                                                          },
                                                    ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),

                                        Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.spaceBetween,
                                          children: [
                                            Flexible(
                                              child: Text(
                                                'Total Amount:',
                                                style: TextStyle(
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? Colors.white
                                                      : Colors.grey[900],
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Flexible(
                                              child: Consumer<CurrencyProvider>(
                                                builder: (context, currencyProvider, _) {
                                                  final code =
                                                      (currencyProvider
                                                                  .companyCurrencyIdList !=
                                                              null &&
                                                          currencyProvider
                                                                  .companyCurrencyIdList!
                                                                  .length >
                                                              1)
                                                      ? currencyProvider
                                                            .companyCurrencyIdList![1]
                                                            .toString()
                                                      : currencyProvider
                                                            .currency;
                                                  final formatted =
                                                      currencyProvider
                                                          .formatAmount(
                                                            _total,
                                                            currency: code,
                                                          );
                                                  return Text(
                                                    formatted,
                                                    style: TextStyle(
                                                      fontSize: 20,
                                                      fontWeight:
                                                          FontWeight.bold,
                                                      color: isDark
                                                          ? Colors.white
                                                          : Colors.blue,
                                                    ),
                                                    textAlign: TextAlign.end,
                                                  );
                                                },
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
      ),
      bottomNavigationBar: _isInitialLoad
          ? null
          : MoboBottomActionBar(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton.icon(
                  onPressed: _canSubmit ? _saveQuote : null,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Colors.white,
                            ),
                          ),
                        )
                      : const Icon(
                          HugeIcons.strokeRoundedFileAdd,
                          color: Colors.white,
                          size: 20,
                        ),
                  label: Text(
                    _isLoading
                        ? (widget.quotationToEdit != null
                              ? 'Updating Quote...'
                              : 'Creating Quote...')
                        : (widget.quotationToEdit != null
                              ? 'Update Quote'
                              : 'Create Quote'),
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    disabledBackgroundColor: isDark
                        ? Colors.grey[700]!
                        : Colors.grey[400]!,
                  ),
                ),
              ),
            ),
    );
  }

  Future<void> _updateConfirmedOrderLines(
    dynamic client,
    Map<String, dynamic> updateData,
  ) async {
    final existingQuotation = await client.callKw({
      'model': 'sale.order',
      'method': 'read',
      'args': [
        [_quotationId],
      ],
      'kwargs': {
        'fields': ['order_line'],
      },
    });

    if (existingQuotation == null ||
        existingQuotation is! List ||
        existingQuotation.isEmpty) {
      throw Exception('Could not fetch existing order lines');
    }

    final existingLineIds = List<int>.from(
      existingQuotation[0]['order_line'] ?? [],
    );

    if (existingLineIds.isEmpty) {
      throw Exception('No existing order lines found to update');
    }

    final existingLinesData = await client.callKw({
      'model': 'sale.order.line',
      'method': 'read',
      'args': [existingLineIds],
      'kwargs': {
        'fields': ['product_id', 'product_uom_qty', 'price_unit'],
      },
    });

    final updateCommands = <List<dynamic>>[];

    for (final currentLine in _quoteLines) {
      final currentProductId = _toIntId(currentLine['product_id']);
      if (currentProductId == null) continue;

      for (final existingLine in existingLinesData) {
        final existingProductId = existingLine['product_id'] is List
            ? existingLine['product_id'][0]
            : existingLine['product_id'];

        if (existingProductId == currentProductId) {
          updateCommands.add([
            1,
            existingLine['id'],
            {
              'product_uom_qty': currentLine['quantity'],
              'price_unit': currentLine['unit_price'],
            },
          ]);
          break;
        }
      }
    }

    if (updateCommands.isEmpty) {
      throw Exception('No matching product lines found to update');
    }

    final confirmedUpdateData = Map<String, dynamic>.from(updateData);
    confirmedUpdateData['order_line'] = updateCommands;

    await client.callKw({
      'model': 'sale.order',
      'method': 'write',
      'args': [
        [_quotationId],
        confirmedUpdateData,
      ],
      'kwargs': {},
    });
  }
}

class _QuoteLineItem extends StatefulWidget {
  final Map<String, dynamic> line;
  final int index;
  final bool isLast;
  final bool isDark;
  final bool isConfirmedOrder;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(double, double) onUpdate;

  const _QuoteLineItem({
    super.key,
    required this.line,
    required this.index,
    required this.isLast,
    required this.isDark,
    this.isConfirmedOrder = false,
    required this.onEdit,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  State<_QuoteLineItem> createState() => _QuoteLineItemState();
}

class _QuoteLineItemState extends State<_QuoteLineItem> {
  late double quantity;
  late double unitPrice;

  @override
  void initState() {
    super.initState();
    quantity = (widget.line['quantity'] as num?)?.toDouble() ?? 0.0;
    unitPrice = (widget.line['unit_price'] as num?)?.toDouble() ?? 0.0;
  }

  @override
  Widget build(BuildContext context) {
    final subtotal = widget.line['subtotal'] as double? ?? 0.0;
    final theme = Theme.of(context);
    final cardColor = widget.isDark ? Colors.grey[850] : Colors.white;
    final borderColor = widget.isDark ? Colors.grey[700]! : Colors.grey[200]!;
    final textColor = widget.isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = widget.isDark
        ? Colors.grey[400]
        : Colors.grey[600];

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: cardColor,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: borderColor, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.line['product_name']?.toString() ??
                              'Unnamed Product',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (widget.line['product_data']?['default_code'] !=
                            null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'SKU: ${widget.line['product_data']['default_code']}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: secondaryTextColor,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),

                  if (!widget.isConfirmedOrder)
                    IconButton(
                      icon: Icon(
                        HugeIcons.strokeRoundedDelete02,
                        color: Colors.red[400],
                        size: 20,
                      ),
                      tooltip: 'Delete',
                      onPressed: widget.onDelete,
                    ),
                ],
              ),

              const SizedBox(height: 12),
              // Quantity and price share the row; the total has its own line
              // underneath. All three sat in one row before, with the total
              // the only child not inside an `Expanded` — so it was measured
              // first at its natural width and a large amount ate the space
              // the two fields were meant to divide, leaving their contents
              // clipped (and overflowing the row once the total grew enough).
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Quantity',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _QuoteQuantityInput(
                          initialValue: quantity,
                          onChanged: (value) {
                            setState(() => quantity = value);
                            widget.onUpdate(value, unitPrice);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 16),

                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Unit Price',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: secondaryTextColor,
                          ),
                        ),
                        const SizedBox(height: 4),
                        _QuotePriceInput(
                          initialValue: unitPrice,
                          onChanged: (value) {
                            setState(() => unitPrice = value);
                            widget.onUpdate(quantity, value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Total',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: secondaryTextColor,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, _) {
                        final code =
                            (currencyProvider.companyCurrencyIdList != null &&
                                currencyProvider.companyCurrencyIdList!.length >
                                    1)
                            ? currencyProvider.companyCurrencyIdList![1]
                                  .toString()
                            : currencyProvider.currency;
                        final formatted = currencyProvider.formatAmount(
                          subtotal,
                          currency: code,
                        );
                        return Text(
                          formatted,
                          textAlign: TextAlign.right,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: widget.isDark
                                ? Colors.white
                                : theme.primaryColor,
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuoteQuantityInput extends StatefulWidget {
  final double initialValue;
  final Function(double) onChanged;

  const _QuoteQuantityInput({
    required this.initialValue,
    required this.onChanged,
  });

  @override
  _QuoteQuantityInputState createState() => _QuoteQuantityInputState();
}

class _QuoteQuantityInputState extends State<_QuoteQuantityInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: _formatQuantity(widget.initialValue),
    );
    _controller.addListener(_onQuantityChanged);
  }

  /// Renders whole numbers without decimals (e.g. `1`) while preserving
  /// fractional quantities (e.g. `2.5`) so unit-of-measure decimals aren't lost.
  String _formatQuantity(double value) {
    return value == value.roundToDouble()
        ? value.toStringAsFixed(0)
        : value.toString();
  }

  @override
  void dispose() {
    _controller.removeListener(_onQuantityChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQuantityChanged() {
    // An empty or half-typed field is not a quantity yet, so the line keeps
    // the one it has; 0 is a real value, though — it is how Odoo wants a line
    // of a confirmed order removed, which this screen tells the user to do.
    final value = double.tryParse(_controller.text);
    if (value == null || value < 0) return;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 40,
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[800] : Colors.white,
          border: Border.all(
            color: isDark ? Colors.grey[600]! : theme.dividerColor,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.remove, size: 18),
              onPressed: () {
                final currentValue = double.tryParse(_controller.text) ?? 1.0;
                if (currentValue > 0) {
                  // `_formatQuantity`, not `toInt()`: truncating here turned
                  // a 2.5 into a 3 and lost the unit-of-measure decimals.
                  _controller.text = _formatQuantity(
                    (currentValue - 1).clamp(0, double.infinity).toDouble(),
                  );
                }
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    left: Radius.circular(6),
                  ),
                ),
              ),
            ),
            Expanded(
              child: TextField(
                controller: _controller,
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: isDark ? Colors.white : null,
                ),
                decoration: const InputDecoration(
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.symmetric(
                    vertical: 8,
                    horizontal: 4,
                  ),
                  isDense: true,
                  counterText: '',
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.add, size: 18),
              onPressed: () {
                final currentValue = double.tryParse(_controller.text) ?? 0.0;
                _controller.text = _formatQuantity(currentValue + 1);
              },
              padding: const EdgeInsets.all(4),
              constraints: const BoxConstraints(),
              style: IconButton.styleFrom(
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: const RoundedRectangleBorder(
                  borderRadius: BorderRadius.horizontal(
                    right: Radius.circular(6),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _QuotePriceInput extends StatefulWidget {
  final double initialValue;
  final Function(double) onChanged;

  const _QuotePriceInput({required this.initialValue, required this.onChanged});

  @override
  _QuotePriceInputState createState() => _QuotePriceInputState();
}

class _QuotePriceInputState extends State<_QuotePriceInput> {
  late TextEditingController _controller;
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(2),
    );
    _controller.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onPriceChanged);
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onPriceChanged() {
    final cleanText = _controller.text.replaceAll(RegExp(r'[^\d.]'), '');
    final value = double.tryParse(cleanText) ?? 0.0;
    widget.onChanged(value);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: 40,
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        textAlign: TextAlign.right,
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        style: theme.textTheme.bodyMedium?.copyWith(
          color: isDark ? Colors.white : null,
        ),
        decoration: InputDecoration(
          labelStyle: TextStyle(
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
          prefixIcon: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              right: 8,
              top: 12,
              bottom: 12,
            ),
            child: Consumer<CurrencyProvider>(
              builder: (context, currencyProvider, _) {
                final code =
                    (currencyProvider.companyCurrencyIdList != null &&
                        currencyProvider.companyCurrencyIdList!.length > 1)
                    ? currencyProvider.companyCurrencyIdList![1].toString()
                    : currencyProvider.currency;
                return Text(
                  code,
                  style: TextStyle(
                    color: isDark ? Colors.grey[400] : Colors.grey,
                  ),
                );
              },
            ),
          ),
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          contentPadding: const EdgeInsets.symmetric(
            vertical: 8,
            horizontal: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[600]! : theme.dividerColor,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.grey[600]! : theme.dividerColor,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(
              color: isDark ? Colors.blue[300]! : theme.primaryColor,
              width: 1.5,
            ),
          ),
          isDense: true,
        ),
        onTap: () {
          _controller.selection = TextSelection(
            baseOffset: 0,
            extentOffset: _controller.text.length,
          );
        },
      ),
    );
  }
}

class QuantityDialog extends StatefulWidget {
  final Map<String, dynamic> product;
  final Function(double, double) onConfirm;

  const QuantityDialog({
    super.key,
    required this.product,
    required this.onConfirm,
  });

  @override
  State<QuantityDialog> createState() => _QuantityDialogState();
}

class _QuantityDialogState extends State<QuantityDialog> {
  final _quantityController = TextEditingController(text: '1');
  final _priceController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _priceController.text = widget.product['list_price']?.toString() ?? '0.00';
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    super.dispose();
  }

  String _displayValue(dynamic value) {
    return value?.toString() ?? 'Unknown';
  }

  void _handleConfirm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final quantity = double.parse(_quantityController.text);
      final unitPrice = double.parse(_priceController.text);

      widget.onConfirm(quantity, unitPrice);

      if (mounted) {
        Navigator.pop(context);
      }
    } catch (e) {
      CustomSnackbar.showError(context, 'Please enter valid numbers');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Dialog(
      elevation: 8,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: MediaQuery.of(context).size.width * 0.9,
        constraints: const BoxConstraints(maxWidth: 400),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[900] : Colors.white,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      HugeIcons.strokeRoundedPackageAdd,
                      color: colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Add Product',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayValue(widget.product['name']),
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: CustomTextField(
                      controller: _quantityController,
                      labelText: 'Quantity',
                      isRequired: true,
                      isDark: isDark,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                        signed: false,
                      ),
                      validator: (value) {
                        if (value?.isEmpty ?? true) {
                          return 'Required';
                        }
                        final quantity = double.tryParse(value!);
                        if (quantity == null || quantity <= 0) {
                          return 'Invalid quantity';
                        }
                        return null;
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 3,
                    child: Consumer<CurrencyProvider>(
                      builder: (context, currencyProvider, _) {
                        final currencySymbol =
                            (currencyProvider.companyCurrencyIdList != null &&
                                currencyProvider.companyCurrencyIdList!.length >
                                    1)
                            ? currencyProvider.companyCurrencyIdList![1]
                                  .toString()
                            : currencyProvider.currency;

                        return CustomTextField(
                          controller: _priceController,
                          labelText: 'Unit Price ($currencySymbol)',
                          isRequired: true,
                          isDark: isDark,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) {
                            if (value?.isEmpty ?? true) {
                              return 'Required';
                            }
                            final price = double.tryParse(value!);
                            if (price == null || price < 0) {
                              return 'Invalid price';
                            }
                            return null;
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: colorScheme.outline.withOpacity(0.2),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Flexible(
                      child: Text(
                        'Total:',
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: ValueListenableBuilder(
                        valueListenable: _quantityController,
                        builder: (context, quantityValue, _) {
                          return ValueListenableBuilder(
                            valueListenable: _priceController,
                            builder: (context, priceValue, _) {
                              final quantity =
                                  double.tryParse(quantityValue.text) ?? 0;
                              final price =
                                  double.tryParse(priceValue.text) ?? 0;
                              final total = quantity * price;

                              return Consumer<CurrencyProvider>(
                                builder: (context, currencyProvider, _) {
                                  final code =
                                      (currencyProvider.companyCurrencyIdList !=
                                              null &&
                                          currencyProvider
                                                  .companyCurrencyIdList!
                                                  .length >
                                              1)
                                      ? currencyProvider
                                            .companyCurrencyIdList![1]
                                            .toString()
                                      : currencyProvider.currency;
                                  return Text(
                                    currencyProvider.formatAmount(
                                      total,
                                      currency: code,
                                    ),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          fontWeight: FontWeight.w600,
                                          color: isDark
                                              ? Colors.white
                                              : colorScheme.primary,
                                        ),
                                    textAlign: TextAlign.end,
                                  );
                                },
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              MoboDialogButtons(
                secondaryLabel: 'Cancel',
                onSecondary: () => Navigator.pop(context),
                primaryLabel: 'Add to Quote',
                onPrimary: _handleConfirm,
                isLoading: _isLoading,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The company a quotation is for: what its pricelist and payment-term lists
/// are limited to, and the context its server calls run in.
class _QuoteCompany {
  const _QuoteCompany({required this.id, required this.scope});

  final int? id;

  /// Database, user and company: what a cached list belongs to.
  final String scope;

  /// The domain of Odoo's own form field: records with no company, or this
  /// one's. With no company known, all of the user's companies are left
  /// alone, as before.
  List<dynamic> get domain => id == null
      ? const []
      : [
          '|',
          ['company_id', '=', false],
          ['company_id', '=', id],
        ];

  /// Makes the server answer as if this company were the one selected.
  Map<String, dynamic> get context => id == null
      ? const {}
      : {
          'allowed_company_ids': [id],
          'company_id': id,
        };
}
