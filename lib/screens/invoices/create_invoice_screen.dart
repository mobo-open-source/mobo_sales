import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:shimmer/shimmer.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../widgets/custom_snackbar.dart';
import '../../widgets/connection_status_widget.dart';
import '../../models/contact.dart';
import '../../providers/currency_provider.dart';
import '../../providers/invoice_creation_provider.dart';
import '../../widgets/confetti_dialogs.dart';
import '../../utils/data_loss_warning_mixin.dart';
import '../../providers/contact_provider.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/customer_typeahead.dart';
import '../../widgets/product_typeahead.dart';
import '../../widgets/custom_date_picker.dart';
import '../../utils/date_picker_utils.dart';
import '../../models/product.dart';
import '../../models/quote.dart';
import '../../services/odoo_session_manager.dart';

class CreateInvoiceScreen extends StatefulWidget {
  final Contact? customer;
  final Map<String, dynamic>? invoiceToEdit;
  final String? invoiceType;
  final double? downPaymentPercentage;
  final double? downPaymentAmount;

  const CreateInvoiceScreen({
    super.key,
    this.customer,
    this.invoiceToEdit,
    this.invoiceType,
    this.downPaymentPercentage,
    this.downPaymentAmount,
  });

  @override
  State<CreateInvoiceScreen> createState() => _CreateInvoiceScreenState();
}

class _CreateInvoiceScreenState extends State<CreateInvoiceScreen>
    with DataLossWarningMixin {
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _customerSearchController =
      TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  late CreateInvoiceProvider _invoiceProvider;
  bool _isInitialized = false;
  final bool _isLoadingSaleOrder = false;
  String? _invoiceName;
  int? _invoiceId;
  Timer? _debounce;

  final TextEditingController _productSearchController =
      TextEditingController();
  Timer? _productDebounce;
  final bool _isSearchingProducts = false;
  final bool _showProductDropdown = false;
  final List<Product> _filteredProducts = [];

  @override
  bool get hasUnsavedData {
    if (!_isInitialized) return false;

    final provider = context.read<CreateInvoiceProvider>();
    return provider.selectedCustomer != null ||
        provider.invoiceLines.isNotEmpty ||
        _notesController.text.trim().isNotEmpty ||
        provider.selectedSaleOrder != null;
  }

  @override
  String get dataLossTitle => 'Discard Invoice?';

  @override
  String get dataLossMessage =>
      'You have unsaved invoice data that will be lost if you leave this page. Are you sure you want to discard this invoice?';

  @override
  void onConfirmLeave() {
    try {
      final provider = context.read<CreateInvoiceProvider>();
      provider.resetForm();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final invoiceProvider = context.read<CreateInvoiceProvider>();

      if (widget.invoiceType != null) {}

      if (widget.invoiceToEdit != null) {
        await _loadInvoiceForEditing(widget.invoiceToEdit!);
      } else if (widget.customer != null) {
        invoiceProvider.setSelectedCustomer(widget.customer!);
        _customerSearchController.text = widget.customer!.name;
      }

      invoiceProvider.fetchCustomers();
      if (widget.invoiceToEdit == null) {
        invoiceProvider.fetchSaleOrders();
      }
      invoiceProvider.fetchPaymentTerms();
      invoiceProvider.fetchProducts();

      _isInitialized = true;
    });
  }

  Future<void> _loadInvoiceForEditing(Map<String, dynamic> invoice) async {
    try {
      final invoiceProvider = context.read<CreateInvoiceProvider>();

      _invoiceId = invoice['id'] as int?;

      final nameValue = invoice['name'];
      if (nameValue != null &&
          nameValue != false &&
          nameValue.toString().isNotEmpty) {
        _invoiceName = nameValue.toString();
      } else {
        _invoiceName = null;
      }

      if (invoice['partner_id'] != null && invoice['partner_id'] is List) {
        final customerId = invoice['partner_id'][0] as int;
        final customerName = invoice['partner_id'][1] as String;

        try {
          final client = await OdooSessionManager.getClient();
          if (client != null) {
            final customerData = await client.callKw({
              'model': 'res.partner',
              'method': 'read',
              'args': [
                [customerId],
              ],
              'kwargs': {
                'fields': [
                  'id',
                  'name',
                  'email',
                  'phone',
                  'mobile',
                  'street',
                  'street2',
                  'city',
                  'state_id',
                  'zip',
                  'country_id',
                  'image_1920',
                  'company_name',
                  'vat',
                ],
              },
            });

            if (customerData != null &&
                customerData is List &&
                customerData.isNotEmpty) {
              final data = customerData[0];

              String? imageData;
              if (data['image_1920'] != null && data['image_1920'] != false) {
                imageData = data['image_1920'].toString();
              }

              final customer = Contact(
                id: customerId,
                name: data['name'] ?? customerName,
                email: data['email']?.toString() ?? '',
                phone: data['phone']?.toString() ?? '',
                mobile: data['mobile']?.toString() ?? '',
                street: data['street']?.toString(),
                street2: data['street2']?.toString(),
                city: data['city']?.toString(),
                zip: data['zip']?.toString(),
                companyName: data['company_name']?.toString(),
                vat: data['vat']?.toString(),
                imageUrl: imageData,
              );

              invoiceProvider.setSelectedCustomer(customer);
              _customerSearchController.text = customer.name;
            } else {
              final customer = Contact(
                id: customerId,
                name: customerName,
                email: '',
                phone: '',
                mobile: '',
              );
              invoiceProvider.setSelectedCustomer(customer);
              _customerSearchController.text = customerName;
            }
          }
        } catch (e) {
          final customer = Contact(
            id: customerId,
            name: customerName,
            email: '',
            phone: '',
            mobile: '',
          );
          invoiceProvider.setSelectedCustomer(customer);
          _customerSearchController.text = customerName;
        }
      }

      if (invoice['narration'] != null && invoice['narration'] != false) {
        _notesController.text = invoice['narration'].toString();
      }

      if (invoice['invoice_date'] != null && invoice['invoice_date'] != false) {
        try {
          invoiceProvider.setInvoiceDate(
            DateTime.parse(invoice['invoice_date'].toString()),
          );
        } catch (e) {}
      }

      if (invoice['invoice_line_ids'] != null &&
          invoice['invoice_line_ids'] is List) {
        final client = await OdooSessionManager.getClient();
        if (client != null) {
          final lineIds = (invoice['invoice_line_ids'] as List).cast<int>();

          dynamic linesData;
          List<String> fieldsToFetch = [
            'product_id',
            'name',
            'quantity',
            'price_unit',
            'price_subtotal',
          ];

          String? uomField;
          String? taxField;

          try {
            linesData = await client.callKw({
              'model': 'account.move.line',
              'method': 'read',
              'args': [lineIds],
              'kwargs': {
                'fields': [...fieldsToFetch, 'product_uom_id', 'tax_ids'],
              },
            });
            uomField = 'product_uom_id';
            taxField = 'tax_ids';
          } catch (e) {
            try {
              linesData = await client.callKw({
                'model': 'account.move.line',
                'method': 'read',
                'args': [lineIds],
                'kwargs': {
                  'fields': [...fieldsToFetch, 'uom_id', 'tax_ids'],
                },
              });
              uomField = 'uom_id';
              taxField = 'tax_ids';
            } catch (e2) {
              try {
                linesData = await client.callKw({
                  'model': 'account.move.line',
                  'method': 'read',
                  'args': [lineIds],
                  'kwargs': {
                    'fields': [...fieldsToFetch, 'uom_id', 'tax_id'],
                  },
                });
                uomField = 'uom_id';
                taxField = 'tax_id';
              } catch (e3) {
                linesData = await client.callKw({
                  'model': 'account.move.line',
                  'method': 'read',
                  'args': [lineIds],
                  'kwargs': {'fields': fieldsToFetch},
                });
              }
            }
          }

          if (linesData != null && linesData is List) {
            invoiceProvider.invoiceLines.clear();

            for (var line in linesData) {
              try {
                final bool hasProduct =
                    line['product_id'] != null && line['product_id'] != false;

                final int productId;
                final String productName;

                if (hasProduct) {
                  productId = line['product_id'] is List
                      ? line['product_id'][0]
                      : line['product_id'];
                  productName = line['product_id'] is List
                      ? line['product_id'][1]
                      : line['name'];
                } else {
                  productId = 0;
                  productName = line['name'] ?? 'Unnamed line';
                }

                final quantity = (line['quantity'] as num?)?.toDouble() ?? 1.0;
                final unitPrice =
                    (line['price_unit'] as num?)?.toDouble() ?? 0.0;

                final product = Product(
                  id: productId.toString(),
                  name: productName,
                  listPrice: unitPrice,
                  qtyAvailable: 0,
                  variantCount: 1,
                  defaultCode: '',
                );

                await invoiceProvider.addInvoiceLine(
                  product,
                  quantity,
                  unitPrice,
                );
              } catch (lineError) {}
            }
          } else {}
        } else {}
      } else {}

      if (mounted) {
        setState(() {});
      }
    } catch (e) {}
  }

  Future<void> _updateInvoice(CreateInvoiceProvider invoiceProvider) async {
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active session');

      final invoiceId = widget.invoiceToEdit!['id'];

      Map<String, dynamic> updateData = {
        'partner_id': invoiceProvider.selectedCustomer!.id,
      };

      if (invoiceProvider.invoiceDate != null) {
        updateData['invoice_date'] = DateFormat(
          'yyyy-MM-dd',
        ).format(invoiceProvider.invoiceDate!);
      }

      if (invoiceProvider.selectedPaymentTerm != null &&
          invoiceProvider.selectedPaymentTerm!.id != 0) {
        updateData['invoice_payment_term_id'] =
            invoiceProvider.selectedPaymentTerm!.id;
      }

      if (invoiceProvider.dueDate != null) {
        updateData['invoice_date_due'] = DateFormat(
          'yyyy-MM-dd',
        ).format(invoiceProvider.dueDate!);
      }

      if (invoiceProvider.selectedSaleOrder != null) {
        updateData['invoice_origin'] = invoiceProvider.selectedSaleOrder!.name;
      }

      if (_notesController.text.trim().isNotEmpty) {
        updateData['narration'] = _notesController.text.trim();
      } else {
        updateData['narration'] = false;
      }

      final invoiceLines = <List<dynamic>>[];

      if (widget.invoiceToEdit!['invoice_line_ids'] != null) {
        final existingLineIds =
            (widget.invoiceToEdit!['invoice_line_ids'] as List).cast<int>();
        for (final lineId in existingLineIds) {
          invoiceLines.add([2, lineId, false]);
        }
      }

      for (final line in invoiceProvider.invoiceLines) {
        final productId = line['product_id'];
        if (productId == null) continue;

        final lineData = {
          'product_id': productId,
          'name': line['product_name'],
          'quantity': line['quantity'],
          'price_unit': line['unit_price'],
        };

        invoiceLines.add([0, 0, lineData]);
      }

      updateData['invoice_line_ids'] = invoiceLines;

      await client.callKw({
        'model': 'account.move',
        'method': 'write',
        'args': [
          [invoiceId],
          updateData,
        ],
        'kwargs': {},
      });
    } catch (e) {
      rethrow;
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final provider = context.read<CreateInvoiceProvider>();
        provider.resetForm();
      } catch (_) {}
    });
    _customerSearchController.dispose();
    _notesController.dispose();
    _productSearchController.dispose();
    _debounce?.cancel();

    super.dispose();
  }

  String _buildAddressString(Contact contact) {
    return [
          contact.street,
          contact.street2,
          contact.city,
          contact.state,
          contact.zip,
          contact.country,
        ]
        .where((s) => s != null && s.isNotEmpty && s.toLowerCase() != 'false')
        .join(', ');
  }

  bool _isValidField(String? field) {
    return field != null &&
        field.isNotEmpty &&
        field.toLowerCase() != 'false' &&
        field.toLowerCase() != 'null';
  }

  Widget _buildAvatarFallback(Contact contact) {
    return CircleAvatar(
      backgroundColor: Theme.of(context).primaryColor,
      child: Text(
        contact.name.isNotEmpty ? contact.name[0].toUpperCase() : '?',
        style: const TextStyle(color: Colors.white),
      ),
    );
  }

  Widget _buildBase64Avatar(Contact contact) {
    try {
      if (contact.imageUrl == null || contact.imageUrl!.isEmpty) {
        return _buildAvatarFallback(contact);
      }
      final bytes = _safeBase64Decode(contact.imageUrl!);
      if (bytes == null) {
        return _buildAvatarFallback(contact);
      }
      return ClipOval(
        child: Image.memory(
          bytes,
          width: 48,
          height: 48,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) {
            return _buildAvatarFallback(contact);
          },
        ),
      );
    } catch (e) {
      return _buildAvatarFallback(contact);
    }
  }

  Uint8List? _safeBase64Decode(String raw) {
    try {
      var data = raw.contains(',') ? raw.split(',').last : raw;

      data = data.replaceAll(RegExp(r"\s+"), '');

      final rem = data.length % 4;
      if (rem != 0) {
        data = data.padRight(data.length + (4 - rem), '=');
      }
      return base64Decode(data);
    } catch (_) {
      return null;
    }
  }

  Widget _buildInfoChip(
    BuildContext context,
    IconData icon,
    String value,
    bool isDark,
  ) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width - 80,
      ),
      child: Container(
        margin: const EdgeInsets.only(right: 8, bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isDark ? Colors.grey[850] : Colors.grey[100],
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            const SizedBox(width: 4),
            Expanded(
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
                overflow: TextOverflow.ellipsis,
                maxLines: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomerSection(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = theme.primaryColor;

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
                Text(
                  'Customer',
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
          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : Colors.grey[200],
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (invoiceProvider.isLoadingCustomers)
                  Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(headerColor),
                      backgroundColor: isDark
                          ? Colors.grey[700]
                          : Colors.grey[200],
                    ),
                  )
                else if (invoiceProvider.loadingError != null)
                  Text(
                    invoiceProvider.loadingError!,
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  )
                else if (invoiceProvider.errorMessage.isNotEmpty)
                  Text(
                    invoiceProvider.errorMessage,
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                    ),
                  )
                else if (invoiceProvider.selectedCustomer != null)
                  _buildSelectedCustomerTile(context, invoiceProvider)
                else
                  _buildCustomerDropdown(invoiceProvider),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerDropdown(CreateInvoiceProvider invoiceProvider) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return CustomerTypeAhead(
      controller: _customerSearchController,
      labelText: 'Customer',
      isDark: isDark,
      onCustomerSelected: (customer) {
        invoiceProvider.setSelectedCustomer(customer);
        _customerSearchController.text = customer.name;
      },
      onClear: () {
        invoiceProvider.setSelectedCustomer(null);
        _customerSearchController.clear();
      },
      validator: (value) => invoiceProvider.selectedCustomer == null
          ? 'Please select a customer'
          : null,
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

  Widget _buildSelectedCustomerTile(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final customer = invoiceProvider.selectedCustomer!;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Card(
      margin: const EdgeInsets.only(top: 0),
      elevation: 1,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      color: isDark ? Colors.grey[800] : Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: isDark ? Colors.grey[100] : Colors.grey[200],
                  child:
                      customer.imageUrl != null && customer.imageUrl!.isNotEmpty
                      ? ClipOval(
                          child: customer.imageUrl!.startsWith('http')
                              ? Image.network(
                                  customer.imageUrl!,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) =>
                                      _buildAvatarFallback(customer),
                                )
                              : _buildBase64Avatar(customer),
                        )
                      : _buildAvatarFallback(customer),
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
                              customer.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 16,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                          ),
                          if (customer.isCompany == true)
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
                      if (_buildAddressString(customer).isNotEmpty)
                        Text(
                          _buildAddressString(customer),
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
                if (widget.customer == null &&
                    invoiceProvider.selectedSaleOrder == null)
                  IconButton(
                    icon: const Icon(HugeIcons.strokeRoundedCancel01),
                    onPressed: () {
                      invoiceProvider.setSelectedCustomer(null);
                      _customerSearchController.clear();
                    },
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              children: [
                if (_isValidField(customer.email))
                  _buildInfoChip(
                    context,
                    HugeIcons.strokeRoundedMail01,
                    customer.email!,
                    isDark,
                  ),
                if (_isValidField(customer.phone))
                  _buildInfoChip(
                    context,
                    HugeIcons.strokeRoundedCall,
                    customer.phone!,
                    isDark,
                  ),
                if (_isValidField(customer.mobile))
                  _buildInfoChip(
                    context,
                    HugeIcons.strokeRoundedSmartPhone01,
                    customer.mobile!,
                    isDark,
                  ),
                if (_isValidField(customer.vat))
                  _buildInfoChip(
                    context,
                    HugeIcons.strokeRoundedLegalDocument01,
                    customer.vat!,
                    isDark,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInvoiceDetailsSection(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                Text(
                  'Invoice Details',
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
          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : Colors.grey[200],
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildDatePicker(
                        context,
                        invoiceProvider,
                        label: 'Invoice Date',
                        selectedDate:
                            invoiceProvider.invoiceDate ?? DateTime.now(),
                        onConfirm: (date) =>
                            invoiceProvider.setInvoiceDate(date),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildDatePicker(
                        context,
                        invoiceProvider,
                        label: 'Due Date',
                        selectedDate:
                            invoiceProvider.dueDate ??
                            DateTime.now().add(const Duration(days: 30)),
                        onConfirm: (date) => invoiceProvider.setDueDate(date),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                CustomDropdownField(
                  value: invoiceProvider.selectedPaymentTerm?.id.toString(),
                  labelText: 'Payment Terms',
                  hintText: 'Select payment terms',
                  isDark: isDark,
                  items: [
                    const DropdownMenuItem<String>(
                      value: null,
                      child: Text('Select Payment Term'),
                    ),
                    ...invoiceProvider.paymentTerms.map(
                      (term) => DropdownMenuItem<String>(
                        value: term.id.toString(),
                        child: Text(term.name),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      invoiceProvider.setSelectedPaymentTerm(null);
                    } else {
                      final term = invoiceProvider.paymentTerms.firstWhere(
                        (t) => t.id.toString() == value,
                      );
                      invoiceProvider.setSelectedPaymentTerm(term);
                    }
                  },
                  validator: (value) => null,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDatePicker(
    BuildContext context,
    CreateInvoiceProvider provider, {
    required String label,
    required DateTime selectedDate,
    required Function(DateTime) onConfirm,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return CustomDateSelector(
      onTap: () async {
        final DateTime? pickedDate =
            await DatePickerUtils.showStandardDatePicker(
              context: context,
              initialDate: selectedDate,
              firstDate: DateTime(2000),
              lastDate: DateTime(2100),
              helpText: 'Select Date',
              cancelText: 'Cancel',
              confirmText: 'Select',
            );
        if (pickedDate != null) {
          onConfirm(pickedDate);
        }
      },
      selectedDate: selectedDate,
      labelText: label,
      isDark: isDark,
      showBorder: true,
    );
  }

  Widget _buildInvoiceLinesSection(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = theme.primaryColor;

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
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(
                        child: Text(
                          'Items',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.grey[900],
                            letterSpacing: -0.3,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (invoiceProvider.selectedSaleOrder != null &&
                        invoiceProvider.invoiceLines.isNotEmpty) ...[
                      _buildInfoBadge(
                        context,
                        icon: HugeIcons.strokeRoundedShoppingCart01,
                        label: 'From Sale Order',
                        color: isDark ? Colors.white : Colors.blue,
                      ),
                      const SizedBox(width: 8),
                    ],
                    _buildInfoBadge(
                      context,
                      label:
                          '${invoiceProvider.invoiceLines.length} ${invoiceProvider.invoiceLines.length == 1 ? 'item' : 'items'}',
                      color: isDark ? Colors.white : headerColor,
                    ),
                  ],
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : Colors.grey[200],
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProductTypeAhead(
                  controller: _productSearchController,
                  labelText: 'Search Product to Add',
                  isDark: isDark,
                  onProductSelected: (product) {
                    invoiceProvider.addInvoiceLine(
                      product,
                      1.0,
                      product.listPrice,
                    );
                    _productSearchController.clear();
                  },
                ),
                const SizedBox(height: 20),
                if (invoiceProvider.isLoadingSaleOrderDetails)
                  _buildPlaceholderState(
                    context,
                    icon: HugeIcons.strokeRoundedHourglass,
                    title: 'Loading sale order lines...',
                    subtitle: 'Please wait while we fetch the items',
                    showProgress: true,
                  )
                else if (invoiceProvider.invoiceLines.isEmpty)
                  _buildPlaceholderState(
                    context,
                    icon: HugeIcons.strokeRoundedPackageOutOfStock,
                    title: 'No products added yet',
                    subtitle: invoiceProvider.selectedSaleOrder != null
                        ? 'This sale order has no lines to invoice'
                        : 'Add products to create your invoice',
                  )
                else
                  Column(
                    children: [
                      const SizedBox(height: 4),
                      ...invoiceProvider.invoiceLines.asMap().entries.map((
                        entry,
                      ) {
                        final index = entry.key;
                        final line = entry.value;
                        return _InvoiceLineItem(
                          line: line,
                          index: index,
                          isLast:
                              index == invoiceProvider.invoiceLines.length - 1,
                          isDark: isDark,
                          primaryColor: headerColor,
                          currencyProvider: Provider.of<CurrencyProvider>(
                            context,
                            listen: false,
                          ),
                          onEdit: () {},
                          onDelete: () =>
                              invoiceProvider.removeInvoiceLine(index),
                          onUpdate: (qty, price) => invoiceProvider
                              .updateInvoiceLine(index, qty, price),
                        );
                      }),
                      if (invoiceProvider.isLoadingSaleOrderDetails) ...[
                        const SizedBox(height: 8),
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          color: isDark ? Colors.grey[850] : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
                                SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                                SizedBox(width: 10),
                                Text('Loading sale order lines...'),
                              ],
                            ),
                          ),
                        ),
                      ],
                      if (invoiceProvider.isAddingLine) ...[
                        const SizedBox(height: 8),
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          elevation: 0,
                          color: isDark ? Colors.grey[850] : Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: const [
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
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBadge(
    BuildContext context, {
    IconData? icon,
    required String label,
    required Color color,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(isDark ? 0.1 : 1.0),

        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFullWidthButton(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback? onPressed,
    required bool isPrimary,
    Color? color,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buttonColor = color ?? theme.primaryColor;

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        icon: Icon(icon, size: 20, color: isDark ? Colors.white : Colors.black),
        label: Text(
          label,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: isDark ? Colors.white : Colors.grey[800],
          ),
        ),
        style: ElevatedButton.styleFrom(
          backgroundColor: isDark ? Colors.grey[700] : Colors.grey[200],
          foregroundColor: isDark ? Colors.white : Colors.grey[800],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
          elevation: 0,
          shadowColor: Colors.transparent,
          side: isPrimary
              ? null
              : BorderSide(color: isDark ? Colors.white : buttonColor),
        ),
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildPlaceholderState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    bool showProgress = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerColor = Theme.of(context).primaryColor;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
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
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (showProgress)
            CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(headerColor),
              backgroundColor: isDark ? Colors.grey[700] : Colors.grey[200],
            ),
          if (!showProgress)
            Icon(
              icon,
              size: 48,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          const SizedBox(height: 16),
          Text(
            title,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.grey[900],
              letterSpacing: -0.3,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTotalsSection(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    if (invoiceProvider.invoiceLines.isEmpty) return const SizedBox.shrink();

    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = theme.primaryColor;

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
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (invoiceProvider.taxTotals.isNotEmpty) ...[
              _buildTotalRow(
                'Subtotal (Untaxed):',
                currencyProvider.formatAmount(
                  (invoiceProvider.taxTotals['amount_untaxed'] ?? 0.0)
                      .toDouble(),
                  currency:
                      currencyProvider.companyCurrencyIdList != null &&
                          currencyProvider.companyCurrencyIdList!.length > 1
                      ? currencyProvider.companyCurrencyIdList![1].toString()
                      : currencyProvider.currency,
                ),
                isDark,
              ),
              _buildTotalRow(
                'Tax:',
                currencyProvider.formatAmount(
                  (invoiceProvider.taxTotals['amount_tax'] ?? 0.0).toDouble(),
                  currency:
                      currencyProvider.companyCurrencyIdList != null &&
                          currencyProvider.companyCurrencyIdList!.length > 1
                      ? currencyProvider.companyCurrencyIdList![1].toString()
                      : currencyProvider.currency,
                ),
                isDark,
              ),
              Divider(
                height: 16,
                color: isDark ? Colors.grey[700] : Colors.grey[200],
              ),
              _buildTotalRow(
                'Total:',
                currencyProvider.formatAmount(
                  (invoiceProvider.taxTotals['amount_total'] ?? 0.0).toDouble(),
                  currency:
                      currencyProvider.companyCurrencyIdList != null &&
                          currencyProvider.companyCurrencyIdList!.length > 1
                      ? currencyProvider.companyCurrencyIdList![1].toString()
                      : currencyProvider.currency,
                ),
                isDark,
                isBold: true,
              ),
            ] else ...[
              _buildTotalRow(
                'Subtotal:',
                currencyProvider.formatAmount(
                  invoiceProvider.subtotal,
                  currency:
                      currencyProvider.companyCurrencyIdList != null &&
                          currencyProvider.companyCurrencyIdList!.length > 1
                      ? currencyProvider.companyCurrencyIdList![1].toString()
                      : currencyProvider.currency,
                ),
                isDark,
              ),
              if (invoiceProvider.isCalculatingTax)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Calculating tax...',
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                        ),
                      ),
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            headerColor,
                          ),
                          backgroundColor: isDark
                              ? Colors.grey[700]
                              : Colors.grey[200],
                        ),
                      ),
                    ],
                  ),
                )
              else
                _buildTotalRow('Tax:', 'Calculating...', isDark),
              Divider(
                height: 16,
                color: isDark ? Colors.grey[700] : Colors.grey[200],
              ),
              _buildTotalRow(
                'Total:',
                currencyProvider.formatAmount(
                  invoiceProvider.subtotal,
                  currency:
                      currencyProvider.companyCurrencyIdList != null &&
                          currencyProvider.companyCurrencyIdList!.length > 1
                      ? currencyProvider.companyCurrencyIdList![1].toString()
                      : currencyProvider.currency,
                ),
                isDark,
                isBold: true,
              ),
            ],
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.1)
                    : Colors.blue[50]!.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(.4)
                      : Colors.blue[200]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedInformationCircle,
                    size: 16,
                    color: isDark ? Colors.white : Colors.blue[700],
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      invoiceProvider.selectedSaleOrder != null
                          ? 'Tax amounts from sale order'
                          : 'Tax calculated based on product tax configuration',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white : Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalRow(
    String label,
    String value,
    bool isDark, {
    bool isBold = false,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: isBold ? 16 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: isBold ? 18 : 14,
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    bool isDark = false,
    bool isBold = false,
    bool isTotal = false,
    Color? color,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: isTotal ? 16 : 14,
            color: isDark ? Colors.grey[300] : Colors.grey[700],
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isTotal ? 18 : 14,
            fontWeight: isBold ? FontWeight.bold : FontWeight.w500,
            color: color ?? (isDark ? Colors.white : Colors.black87),
          ),
        ),
      ],
    );
  }

  Widget _buildNotesSection(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

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
                Text(
                  'Additional Notes',
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
          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : Colors.grey[200],
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: CustomTextField(
              controller: _notesController,
              labelText: 'Notes',
              isDark: isDark,
              maxLines: 3,
              validator: (value) => null,
            ),
          ),
        ],
      ),
    );
  }

  void showSaleOrderPicker(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final searchController = TextEditingController();
    bool isSearching = false;
    bool isLoadingSaleOrder = false;
    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final headerColor = theme.primaryColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: isDark ? Colors.grey[850] : Colors.white,

      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return StatefulBuilder(
              builder: (context, setState) {
                return Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(24),

                      decoration: BoxDecoration(
                        color: isDark
                            ? Colors.white.withOpacity(.05)
                            : headerColor.withOpacity(0.05),

                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Select Sale Order',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.grey[900],

                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              letterSpacing: -0.3,
                            ),
                          ),
                          Row(
                            children: [
                              if (invoiceProvider.selectedSaleOrder != null)
                                IconButton(
                                  icon: Icon(
                                    Icons.cancel,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                  onPressed: () {
                                    invoiceProvider.clearSelectedSaleOrder();
                                    Navigator.pop(context);
                                  },
                                  tooltip: 'Clear Sale Order',
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Divider(
                      height: 1,
                      color: isDark ? Colors.grey[700] : Colors.grey[200],
                    ),
                    Padding(
                      padding: const EdgeInsets.all(24.0),

                      child: TextField(
                        controller: searchController,
                        decoration: InputDecoration(
                          hintText: 'Search sale orders...',
                          prefixIcon: Icon(
                            Icons.search,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                          suffixIcon: searchController.text.isNotEmpty
                              ? IconButton(
                                  icon: Icon(
                                    Icons.clear,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                  onPressed: () {
                                    searchController.clear();
                                    invoiceProvider.filterSaleOrders('');
                                    setState(() {
                                      isSearching = false;
                                    });
                                  },
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[200]!,
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[200]!,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                              color: headerColor,
                              width: 2,
                            ),
                          ),
                          filled: true,
                          fillColor: isDark
                              ? Colors.grey[800]
                              : Colors.grey[50],

                          hintStyle: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 14,
                          ),
                          labelStyle: TextStyle(
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                            fontSize: 14,
                          ),
                        ),
                        style: TextStyle(
                          color: isDark ? Colors.white : Colors.grey[900],
                          fontSize: 14,
                        ),
                        onChanged: (value) {
                          invoiceProvider.filterSaleOrders(value);
                          setState(() {
                            isSearching = value.isNotEmpty;
                          });
                        },
                      ),
                    ),
                    Expanded(
                      child: invoiceProvider.isLoadingSaleOrders
                          ? Center(
                              child: CircularProgressIndicator(
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  headerColor,
                                ),
                                backgroundColor: isDark
                                    ? Colors.grey[700]
                                    : Colors.grey[200],
                              ),
                            )
                          : invoiceProvider.filteredSaleOrders.isEmpty
                          ? Center(
                              child: Text(
                                'No sale orders found',
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.grey[400]
                                      : Colors.grey[600],
                                  fontSize: 14,
                                ),
                              ),
                            )
                          : ListView.builder(
                              controller: scrollController,
                              padding: const EdgeInsets.symmetric(vertical: 0),
                              itemCount:
                                  invoiceProvider.filteredSaleOrders.length,
                              itemBuilder: (context, index) {
                                final order =
                                    invoiceProvider.filteredSaleOrders[index];
                                return Container(
                                  margin: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 8,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _getSaleOrderCardColor(
                                      order,
                                      isDark,
                                    ),
                                    borderRadius: BorderRadius.circular(16),
                                    border: _getSaleOrderCardBorder(
                                      order,
                                      isDark,
                                    ),
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
                                  child: InkWell(
                                    onTap: () async {
                                      if (isLoadingSaleOrder) return;

                                      final canInvoice =
                                          order.extraData?['can_invoice']
                                              as bool? ??
                                          false;
                                      final invoiceStatus =
                                          order.invoiceStatus ?? '';
                                      final statusReason =
                                          order
                                              .extraData?['invoice_status_reason']
                                              ?.toString() ??
                                          '';

                                      if (!canInvoice) {
                                        _showInvoiceStatusDialog(
                                          context,
                                          invoiceStatus,
                                          statusReason,
                                        );
                                        return;
                                      }

                                      setState(() {
                                        isLoadingSaleOrder = true;
                                      });
                                      showDialog(
                                        context: context,
                                        barrierDismissible: false,
                                        builder: (context) => Dialog(
                                          backgroundColor: Colors.transparent,
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 24.0,
                                              vertical: 20.0,
                                            ),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.grey[850]
                                                  : Colors.white,
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isDark
                                                      ? Colors.black
                                                            .withOpacity(0.18)
                                                      : Colors.black
                                                            .withOpacity(0.06),
                                                  blurRadius: 12,
                                                  offset: const Offset(0, 4),
                                                ),
                                              ],
                                            ),
                                            child: Column(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                CircularProgressIndicator(
                                                  strokeWidth: 3,
                                                  valueColor:
                                                      AlwaysStoppedAnimation<
                                                        Color
                                                      >(
                                                        isDark
                                                            ? Colors.white
                                                            : headerColor,
                                                      ),
                                                  backgroundColor: isDark
                                                      ? Colors.grey[700]
                                                      : Colors.grey[200],
                                                ),
                                                const SizedBox(height: 16),
                                                Text(
                                                  'Loading sale order details...',
                                                  style: TextStyle(
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w500,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.grey[900],
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      );
                                      try {
                                        await invoiceProvider
                                            .setSelectedSaleOrder(order);
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          Navigator.pop(context);
                                        }
                                      } catch (e) {
                                        if (context.mounted) {
                                          Navigator.pop(context);
                                          CustomSnackbar.showError(
                                            context,
                                            'Failed to load sale order details',
                                          );
                                        }
                                      } finally {
                                        setState(() {
                                          isLoadingSaleOrder = false;
                                        });
                                      }
                                    },
                                    child: Padding(
                                      padding: const EdgeInsets.all(24),
                                      child: Row(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.all(8),
                                            decoration: BoxDecoration(
                                              color: isDark
                                                  ? Colors.white.withOpacity(.1)
                                                  : headerColor.withOpacity(
                                                      0.1,
                                                    ),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                            ),
                                            child: Icon(
                                              HugeIcons.strokeRoundedAiMail,
                                              color: isDark
                                                  ? Colors.white
                                                  : headerColor,
                                              size: 20,
                                            ),
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            flex: 2,
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  order.name,
                                                  style: TextStyle(
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 14,
                                                    color: isDark
                                                        ? Colors.white
                                                        : Colors.grey[900],
                                                    letterSpacing: -0.3,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Customer: ${order.customerName ?? 'Unknown'}',
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[600],
                                                    fontSize: 12,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 8),
                                                Wrap(
                                                  spacing: 8,
                                                  runSpacing: 4,
                                                  children: [
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color: _getStatusColor(
                                                          order.status,
                                                          isDark,
                                                        ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: Text(
                                                        _getStatusText(
                                                          order.status,
                                                        ),
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontSize: 11,
                                                          fontWeight:
                                                              FontWeight.w500,
                                                        ),
                                                      ),
                                                    ),
                                                    Container(
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 8,
                                                            vertical: 4,
                                                          ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                            _getEnhancedInvoiceStatusColor(
                                                              order,
                                                              isDark,
                                                            ),
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              12,
                                                            ),
                                                      ),
                                                      child: Row(
                                                        mainAxisSize:
                                                            MainAxisSize.min,
                                                        children: [
                                                          Icon(
                                                            _getInvoiceStatusIcon(
                                                              order,
                                                            ),
                                                            color: Colors.white,
                                                            size: 12,
                                                          ),
                                                          const SizedBox(
                                                            width: 4,
                                                          ),
                                                          Text(
                                                            _getEnhancedInvoiceStatusText(
                                                              order,
                                                            ),
                                                            style:
                                                                const TextStyle(
                                                                  color: Colors
                                                                      .white,
                                                                  fontSize: 11,
                                                                  fontWeight:
                                                                      FontWeight
                                                                          .w500,
                                                                ),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.end,
                                            children: [
                                              Text(
                                                (() {
                                                  final String? currencyCode =
                                                      order.currencyName;
                                                  final String code =
                                                      currencyCode ??
                                                      currencyProvider.currency;
                                                  final String locale =
                                                      currencyProvider
                                                          .currencyToLocale[code] ??
                                                      'en_US';
                                                  return NumberFormat.currency(
                                                    locale: locale,
                                                    name: code,

                                                    decimalDigits: 2,
                                                  ).format(order.total ?? 0.0);
                                                })(),
                                                style: TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  color: isDark
                                                      ? Colors.white
                                                      : headerColor,
                                                  fontSize: 14,
                                                  letterSpacing: -0.3,
                                                ),
                                              ),
                                              if (order.dateOrder != null)
                                                Text(
                                                  DateFormat(
                                                    'MMM dd, yyyy',
                                                  ).format(order.dateOrder!),
                                                  style: TextStyle(
                                                    color: isDark
                                                        ? Colors.grey[400]
                                                        : Colors.grey[600],
                                                    fontSize: 11,
                                                  ),
                                                ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  Color _getStatusColor(String? status, bool isDark) {
    switch (status) {
      case 'sale':
        return isDark ? Colors.green[700]! : Colors.green;
      case 'draft':
        return isDark ? Colors.grey[600]! : Colors.grey;
      default:
        return isDark ? Colors.blue[700]! : Colors.blue;
    }
  }

  Color _getInvoiceStatusColor(String? status, bool isDark) {
    switch (status) {
      case 'invoiced':
        return isDark ? Colors.red[700]! : Colors.red;
      case 'to invoice':
        return isDark ? Colors.orange[700]! : Colors.orange;
      case 'upselling':
        return isDark ? Colors.blue[700]! : Colors.blue;
      case 'no':
        return isDark ? Colors.grey[600]! : Colors.grey;
      default:
        return isDark ? Colors.grey[600]! : Colors.grey;
    }
  }

  String _getStatusText(String? status) {
    switch (status) {
      case 'sale':
        return 'Confirmed';
      case 'draft':
        return 'Draft';
      default:
        return 'Unknown';
    }
  }

  String _getInvoiceStatusText(String? status) {
    switch (status) {
      case 'invoiced':
        return 'Invoiced';
      case 'to invoice':
        return 'To Invoice';
      default:
        return 'No Status';
    }
  }

  String _formatDate(dynamic date) {
    if (date is String) {
      try {
        final parsedDate = DateTime.parse(date);
        return DateFormat('MMM dd, yyyy').format(parsedDate);
      } catch (e) {
        return date;
      }
    }
    return 'Unknown Date';
  }

  void _showInvoiceStatusDialog(
    BuildContext context,
    String status,
    String reason,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final surfaceColor = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final onSurfaceColor = isDark ? Colors.white : Colors.black87;

    String title;
    IconData icon;
    Color iconColor;

    switch (status) {
      case 'invoiced':
        title = 'Fully Invoiced';
        icon = HugeIcons.strokeRoundedCheckmarkCircle02;
        iconColor = Colors.green;
        break;
      case 'no':
        title = 'Nothing to Invoice';
        icon = HugeIcons.strokeRoundedCancel01;
        iconColor = Colors.orange;
        break;
      default:
        title = 'Cannot Invoice';
        icon = HugeIcons.strokeRoundedAlert02;
        iconColor = Colors.red;
    }

    showDialog(
      context: context,
      builder: (context) => Dialog(
        elevation: 8,
        backgroundColor: surfaceColor,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          decoration: BoxDecoration(
            color: surfaceColor,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 24,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: iconColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: iconColor, size: 32),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: onSurfaceColor,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                reason,
                style: TextStyle(fontSize: 14, color: onSurfaceColor),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: iconColor,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  child: const Text(
                    'OK',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getSaleOrderCardColor(Quote order, bool isDark) {
    final canInvoice = order.extraData?['can_invoice'] as bool? ?? false;

    if (!canInvoice) {
      return isDark ? Colors.grey[850]! : Colors.grey[100]!;
    }

    return isDark ? Colors.grey[800]! : Colors.white;
  }

  Border? _getSaleOrderCardBorder(Quote order, bool isDark) {
    final canInvoice = order.extraData?['can_invoice'] as bool? ?? false;
    final invoiceStatus = order.invoiceStatus ?? '';

    if (canInvoice) {
      if (invoiceStatus == 'to invoice') {
        return Border.all(color: Colors.green.withOpacity(0.5), width: 2);
      } else if (invoiceStatus == 'upselling') {
        return Border.all(color: Colors.blue.withOpacity(0.5), width: 2);
      }
    } else {
      return Border.all(color: Colors.grey.withOpacity(0.3), width: 1);
    }

    return null;
  }

  Color _getEnhancedInvoiceStatusColor(Quote order, bool isDark) {
    final canInvoice = order.extraData?['can_invoice'] as bool? ?? false;
    final invoiceStatus = order.invoiceStatus ?? '';

    if (!canInvoice) {
      switch (invoiceStatus) {
        case 'invoiced':
          return isDark ? Colors.grey[600]! : Colors.grey[500]!;
        case 'no':
          return isDark ? Colors.orange[800]! : Colors.orange[600]!;
        default:
          return isDark ? Colors.red[800]! : Colors.red[600]!;
      }
    }

    switch (invoiceStatus) {
      case 'to invoice':
        return isDark ? Colors.green[700]! : Colors.green;
      case 'upselling':
        return isDark ? Colors.blue[700]! : Colors.blue;
      default:
        return isDark ? Colors.grey[600]! : Colors.grey;
    }
  }

  String _getEnhancedInvoiceStatusText(Quote order) {
    final canInvoice = order.extraData?['can_invoice'] as bool? ?? false;
    final invoiceStatus = order.invoiceStatus ?? '';
    final invoiceCount = order.extraData?['invoice_count'] as int? ?? 0;

    if (!canInvoice) {
      switch (invoiceStatus) {
        case 'invoiced':
          return 'Fully Invoiced';
        case 'no':
          return 'Nothing to Invoice';
        default:
          return 'Cannot Invoice';
      }
    }

    switch (invoiceStatus) {
      case 'to invoice':
        return invoiceCount > 0 ? 'Partially Invoiced' : 'Ready to Invoice';
      case 'upselling':
        return 'Upselling Available';
      default:
        return 'Unknown Status';
    }
  }

  IconData _getInvoiceStatusIcon(Quote order) {
    final canInvoice = order.extraData?['can_invoice'] as bool? ?? false;
    final invoiceStatus = order.invoiceStatus ?? '';

    if (!canInvoice) {
      switch (invoiceStatus) {
        case 'invoiced':
          return HugeIcons.strokeRoundedCheckmarkCircle02;
        case 'no':
          return HugeIcons.strokeRoundedCancel01;
        default:
          return HugeIcons.strokeRoundedAlert02;
      }
    }

    switch (invoiceStatus) {
      case 'to invoice':
        return HugeIcons.strokeRoundedInvoice;
      case 'upselling':
        return HugeIcons.strokeRoundedArrowUp01;
      default:
        return HugeIcons.strokeRoundedQuestion;
    }
  }

  Future<void> _saveInvoice(CreateInvoiceProvider invoiceProvider) async {
    if (!_formKey.currentState!.validate()) {
      CustomSnackbar.showError(context, 'Please fill in all required fields');
      return;
    }
    if (invoiceProvider.selectedCustomer == null) {
      CustomSnackbar.showError(context, 'Please select a customer');
      return;
    }

    final isDownPayment =
        widget.invoiceType == 'percentage' || widget.invoiceType == 'fixed';
    if (!isDownPayment && invoiceProvider.invoiceLines.isEmpty) {
      CustomSnackbar.showError(context, 'Please add at least one item');
      return;
    }

    final isEditing = widget.invoiceToEdit != null;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        return Dialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          elevation: 8,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  decoration: BoxDecoration(
                    color: primaryColor.withOpacity(0.08),
                    shape: BoxShape.circle,
                  ),
                  padding: const EdgeInsets.all(16),
                  child: LoadingAnimationWidget.fourRotatingDots(
                    color: Theme.of(context).colorScheme.primary,
                    size: 50,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  isEditing ? 'Updating invoice...' : 'Creating invoice...',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isEditing
                      ? 'Please wait while we update your invoice.'
                      : 'Please wait while we create your invoice.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    try {
      if (isEditing) {
        await _updateInvoice(invoiceProvider);

        if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
          Navigator.of(dialogContext!).pop();
        }

        if (mounted) {
          Navigator.pop(context, true);
        }
      } else {
        await invoiceProvider.createInvoice(
          context,
          invoiceType: widget.invoiceType ?? 'regular',
          downPaymentPercentage: widget.downPaymentPercentage,
          downPaymentAmount: widget.downPaymentAmount,
        );

        if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
          Navigator.of(dialogContext!).pop();
        }

        if (mounted) {
          final invoiceName = invoiceProvider.lastCreatedInvoiceName;
          final errorMsg = invoiceProvider.errorMessage;

          if (errorMsg.isNotEmpty) {
            final isDark = Theme.of(context).brightness == Brightness.dark;
            showDialog(
              context: context,
              barrierDismissible: true,
              builder: (ctx) => AlertDialog(
                backgroundColor: isDark ? Colors.grey[900] : Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                elevation: isDark ? 0 : 8,
                title: Text(
                  'Failed to Create Invoice',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: isDark
                        ? Colors.white
                        : Theme.of(context).colorScheme.onSurface,
                  ),
                ),
                content: Text(
                  errorMsg,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: isDark
                        ? Colors.grey[300]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                actionsPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                actions: [
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.of(ctx).pop(),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.grey[800]
                                : Theme.of(context).colorScheme.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 12,
                            ),
                            elevation: isDark ? 0 : 3,
                          ),
                          child: const Text(
                            'OK',
                            style: TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          } else if (invoiceName != null && invoiceName.isNotEmpty) {
            await showInvoiceCreatedConfettiDialog(context, invoiceName);
            Navigator.pop(context, true);
          }
        }
      }
    } catch (e) {
      if (dialogContext != null && Navigator.of(dialogContext!).canPop()) {
        Navigator.of(dialogContext!).pop();
      }

      if (mounted) {
        String errorMessage = e.toString();

        if (errorMessage.contains('message:')) {
          try {
            final messageStart = errorMessage.indexOf('message:');
            final messageContent = errorMessage.substring(
              messageStart + 'message:'.length,
            );

            var messageEnd = messageContent.indexOf(', arguments:');
            if (messageEnd == -1) {
              messageEnd = messageContent.indexOf(', context:');
            }
            if (messageEnd == -1) {
              messageEnd = messageContent.indexOf(', debug:');
            }

            if (messageEnd > 0) {
              errorMessage = messageContent.substring(0, messageEnd).trim();

              errorMessage = errorMessage
                  .replaceAll(RegExp(r'\s+'), ' ')
                  .trim();
            }
          } catch (parseError) {}
        }

        if (errorMessage.contains('Exception: ')) {
          errorMessage = errorMessage.split('Exception: ')[1];
        }

        if (errorMessage.length > 500 ||
            errorMessage.contains('OdooException')) {
          errorMessage =
              'An unexpected error occurred. Please try again or contact support if the problem persists.';
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        showDialog(
          context: context,
          barrierDismissible: true,
          builder: (ctx) => AlertDialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: isDark ? 0 : 8,
            title: Text(
              isEditing
                  ? 'Failed to Update Invoice'
                  : 'Failed to Create Invoice',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: isDark
                    ? Colors.white
                    : Theme.of(context).colorScheme.onSurface,
              ),
            ),
            content: Text(
              errorMessage,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? Colors.grey[300]
                    : Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            actionsPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: isDark
                            ? Colors.grey[800]
                            : Theme.of(context).colorScheme.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 12,
                        ),
                        elevation: isDark ? 0 : 3,
                      ),
                      child: const Text(
                        'OK',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }
    }
  }

  Widget _buildCreateInvoiceShimmer() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final highlightColor = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final cardBg = isDark ? Colors.grey[850]! : Colors.white;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: highlightColor,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSaleOrderShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildCustomerSectionShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildInvoiceDetailsShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildInvoiceLinesShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildTotalsShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildNotesShimmer(cardBg, baseColor),
            const SizedBox(height: 24),

            _buildButtonShimmer(baseColor),
          ],
        ),
      ),
    );
  }

  Widget _buildSaleOrderShimmer(Color cardBg, Color baseColor) {
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
            child: Container(
              width: double.infinity,
              height: 56,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCustomerSectionShimmer(Color cardBg, Color baseColor) {
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
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: baseColor,
                    shape: BoxShape.circle,
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
                        width: 200,
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

  Widget _buildInvoiceDetailsShimmer(Color cardBg, Color baseColor) {
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
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Container(
                        height: 56,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

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

  Widget _buildInvoiceLinesShimmer(Color cardBg, Color baseColor) {
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
                  width: 100,
                  height: 18,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 80,
                  height: 32,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[200]),

          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: List.generate(
                2,
                (index) => Padding(
                  padding: EdgeInsets.only(bottom: index == 1 ? 0 : 16),
                  child: Row(
                    children: [
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: baseColor,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      const SizedBox(width: 12),

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
                            const SizedBox(height: 6),
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
                      const SizedBox(width: 12),

                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            width: 60,
                            height: 16,
                            decoration: BoxDecoration(
                              color: baseColor,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            width: 80,
                            height: 14,
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
              ),
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
          children: List.generate(
            4,
            (index) => Padding(
              padding: EdgeInsets.only(bottom: index == 3 ? 0 : 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    width: 100,
                    height: index == 3 ? 18 : 16,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  Container(
                    width: 80,
                    height: index == 3 ? 18 : 16,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildNotesShimmer(Color cardBg, Color baseColor) {
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
                  width: 60,
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
            child: Container(
              width: double.infinity,
              height: 100,
              decoration: BoxDecoration(
                color: baseColor,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
        ],
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
    final backgroundColor = isDark ? Colors.grey[900] : Colors.grey[50];
    final primaryColor = Theme.of(context).primaryColor;

    return Consumer2<ConnectivityService, SessionService>(
      builder: (context, connectivityService, sessionService, child) {
        if (!connectivityService.isConnected ||
            !sessionService.hasValidSession) {
          final popChild = PopScope(
            canPop: !hasUnsavedData,
            onPopInvoked: (didPop) async {
              if (didPop) return;
              final shouldPop = await handleWillPop();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            },
            child: Scaffold(
              backgroundColor: backgroundColor,
              appBar: AppBar(
                backgroundColor: backgroundColor,
                foregroundColor: isDark ? Colors.white : Colors.black,
                elevation: 0,
                title: Text(
                  widget.invoiceToEdit != null
                      ? (_invoiceName != null
                            ? 'Edit $_invoiceName'
                            : 'Edit Invoice')
                      : 'Create Invoice',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
                leading: IconButton(
                  onPressed: () =>
                      handleNavigation(() => Navigator.pop(context)),
                  icon: Icon(
                    HugeIcons.strokeRoundedArrowLeft01,
                    color: isDark ? Colors.white : Colors.black,
                  ),
                ),
              ),
              body: ConnectionStatusWidget(
                onRetry: () async {
                  final ok = await connectivityService.checkConnectivityOnce();
                  if (ok && mounted) setState(() {});
                },
              ),
            ),
          );
          return (Platform.isAndroid && hasUnsavedData)
              ? WillPopScope(onWillPop: () => handleWillPop(), child: popChild)
              : popChild;
        }

        final contactProvider = context.watch<ContactProvider>();
        if (contactProvider.isServerUnreachable) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                widget.invoiceToEdit != null
                    ? (_invoiceName != null
                          ? 'Edit $_invoiceName'
                          : 'Edit Invoice')
                    : 'Create Invoice',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
              foregroundColor: isDark ? Colors.white : Colors.black,
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
                try {
                  await context.read<CreateInvoiceProvider>().fetchCustomers();
                } catch (_) {}
              },
              serverUnreachable: true,
              serverErrorMessage:
                  'Unable to load customers from server/database. Please check your server or try again.',
            ),
          );
        }

        return Consumer<CreateInvoiceProvider>(
          builder: (context, invoiceProvider, _) {
            if (widget.customer != null) {
              _customerSearchController.text = widget.customer!.name;
            }

            if (invoiceProvider.isLoadingCustomers ||
                invoiceProvider.isLoadingSaleOrders) {
              final popChildLoading = PopScope(
                canPop: !hasUnsavedData,
                onPopInvoked: (didPop) async {
                  if (didPop) return;
                  final shouldPop = await handleWillPop();
                  if (shouldPop && mounted) {
                    Navigator.of(context).pop();
                  }
                },
                child: Scaffold(
                  backgroundColor: backgroundColor,
                  appBar: AppBar(
                    backgroundColor: backgroundColor,
                    foregroundColor: isDark ? Colors.white : primaryColor,
                    elevation: 0,
                    title: Text(
                      widget.invoiceToEdit != null
                          ? (_invoiceName != null
                                ? 'Edit $_invoiceName'
                                : 'Edit Invoice')
                          : 'Create Invoice',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                    leading: IconButton(
                      onPressed: () =>
                          handleNavigation(() => Navigator.pop(context)),
                      icon: Icon(
                        HugeIcons.strokeRoundedArrowLeft01,
                        color: isDark ? Colors.white : Colors.black,
                      ),
                    ),
                  ),
                  body: _buildCreateInvoiceShimmer(),
                ),
              );
              return (Platform.isAndroid && hasUnsavedData)
                  ? WillPopScope(
                      onWillPop: () => handleWillPop(),
                      child: popChildLoading,
                    )
                  : popChildLoading;
            }

            final popChildMain = PopScope(
              canPop: !hasUnsavedData,
              onPopInvoked: (didPop) async {
                if (didPop) return;
                final shouldPop = await handleWillPop();
                if (shouldPop && mounted) {
                  Navigator.of(context).pop();
                }
              },
              child: Scaffold(
                backgroundColor: backgroundColor,
                appBar: AppBar(
                  backgroundColor: backgroundColor,
                  foregroundColor: isDark ? Colors.white : primaryColor,
                  elevation: 0,
                  title: Text(
                    widget.invoiceToEdit != null
                        ? (_invoiceName != null
                              ? 'Edit $_invoiceName'
                              : 'Edit Invoice')
                        : 'Create Invoice',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                  leading: IconButton(
                    onPressed: () =>
                        handleNavigation(() => Navigator.pop(context)),
                    icon: Icon(
                      HugeIcons.strokeRoundedArrowLeft01,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                  ),
                ),
                body: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.invoiceToEdit == null &&
                            widget.invoiceType != 'percentage' &&
                            widget.invoiceType != 'fixed')
                          _buildCustomerSection(context, invoiceProvider),

                        if (widget.invoiceType == 'percentage' ||
                            widget.invoiceType == 'fixed')
                          _buildDownPaymentInfoSection(
                            context,
                            invoiceProvider,
                          ),

                        _buildInvoiceDetailsSection(context, invoiceProvider),

                        if (widget.invoiceType != 'percentage' &&
                            widget.invoiceType != 'fixed')
                          _buildInvoiceLinesSection(context, invoiceProvider),

                        if (widget.invoiceType != 'percentage' &&
                            widget.invoiceType != 'fixed')
                          _buildTotalsSection(context, invoiceProvider),

                        _buildNotesSection(context),
                        const SizedBox(height: 24),
                        _buildCreateInvoiceButton(context, invoiceProvider),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
                ),
              ),
            );
            return (Platform.isAndroid && hasUnsavedData)
                ? WillPopScope(
                    onWillPop: () => handleWillPop(),
                    child: popChildMain,
                  )
                : popChildMain;
          },
        );
      },
    );
  }

  Widget _buildDownPaymentInfoSection(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final currencyProvider = Provider.of<CurrencyProvider>(
      context,
      listen: false,
    );

    final saleOrder = invoiceProvider.selectedSaleOrder;
    if (saleOrder == null) return const SizedBox.shrink();

    final orderTotal = saleOrder.total;
    final currencyIdField = saleOrder.extraData?['currency_id'];
    final String? currencyCode =
        (currencyIdField is List && currencyIdField.length > 1)
        ? currencyIdField[1].toString()
        : null;

    double dpAmount = 0.0;
    String dpDescription = '';

    if (widget.invoiceType == 'percentage' &&
        widget.downPaymentPercentage != null) {
      dpAmount = orderTotal * (widget.downPaymentPercentage! / 100);
      dpDescription =
          'Down payment of ${widget.downPaymentPercentage!.toStringAsFixed(2)}%';
    } else if (widget.invoiceType == 'fixed' &&
        widget.downPaymentAmount != null) {
      dpAmount = widget.downPaymentAmount!;
      dpDescription = 'Down payment (fixed amount)';
    }

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
            child: Row(
              children: [
                Icon(
                  HugeIcons.strokeRoundedInvoice,
                  color: theme.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 12),
                Text(
                  'Down Payment Invoice',
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
          Divider(
            height: 1,
            color: isDark ? Colors.grey[700] : Colors.grey[200],
          ),
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: theme.primaryColor.withOpacity(0.3),
                      width: 1,
                    ),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Sale Order:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            saleOrder.name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Order Total:',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                            ),
                          ),
                          Text(
                            currencyProvider.formatAmount(
                              orderTotal,
                              currency: currencyCode,
                            ),
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Divider(
                        height: 1,
                        color: isDark ? Colors.grey[600] : Colors.grey[300],
                      ),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              dpDescription,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.primaryColor,
                              ),
                            ),
                          ),
                          Text(
                            currencyProvider.formatAmount(
                              dpAmount,
                              currency: currencyCode,
                            ),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: theme.primaryColor,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.withOpacity(0.1)
                        : Colors.blue[50],
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isDark
                          ? Colors.blue.withOpacity(0.3)
                          : Colors.blue[200]!,
                      width: 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        HugeIcons.strokeRoundedInformationCircle,
                        size: 16,
                        color: isDark ? Colors.blue[300] : Colors.blue[700],
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'This invoice will be created as a down payment for the selected sale order.',
                          style: TextStyle(
                            fontSize: 12,
                            color: isDark ? Colors.blue[200] : Colors.blue[900],
                          ),
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

  Widget _buildCreateInvoiceButton(
    BuildContext context,
    CreateInvoiceProvider invoiceProvider,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final buttonColor = theme.primaryColor;

    final isDownPayment =
        widget.invoiceType == 'percentage' || widget.invoiceType == 'fixed';
    final canCreate =
        invoiceProvider.selectedCustomer != null &&
        (isDownPayment || invoiceProvider.invoiceLines.isNotEmpty) &&
        !invoiceProvider.isLoading &&
        !invoiceProvider.isCreatingInvoice;

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
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
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          icon: (invoiceProvider.isLoading || invoiceProvider.isCreatingInvoice)
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                  ),
                )
              : const Icon(
                  HugeIcons.strokeRoundedInvoice01,
                  color: Colors.white,
                  size: 20,
                ),
          label:
              (invoiceProvider.isLoading || invoiceProvider.isCreatingInvoice)
              ? const Text(
                  'Creating Invoice...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                )
              : Text(
                  widget.invoiceToEdit != null
                      ? 'Update Invoice'
                      : 'Create Invoice',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
          style: ElevatedButton.styleFrom(
            backgroundColor: buttonColor,
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            elevation: 0,
            shadowColor: Colors.transparent,
            disabledBackgroundColor: isDark
                ? Colors.grey[700]!
                : Colors.grey[400]!,
          ),
          onPressed: canCreate ? () => _saveInvoice(invoiceProvider) : null,
        ),
      ),
    );
  }
}

class _ProductSelectionSheet extends StatefulWidget {
  final Function(Product, double, double) onProductSelected;
  final String? initialSearchQuery;

  const _ProductSelectionSheet({
    required this.onProductSelected,
    this.initialSearchQuery,
  });

  @override
  _ProductSelectionSheetState createState() => _ProductSelectionSheetState();
}

class _ProductSelectionSheetState extends State<_ProductSelectionSheet> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  List<Product> _filteredProducts = [];
  bool _isLoading = false;
  bool _isPaginating = false;
  bool _allProductsLoaded = false;
  String? _clickedTileId;
  final Map<String, Uint8List> _base64ImageCache = {};
  Timer? _searchTimer;
  String _lastSearchValue = '';
  static List<Product> _cachedAllProducts = [];
  static bool _hasInitialDataLoaded = false;
  static String _lastSearchQuery = '';
  static bool _cacheAllProductsLoaded = false;
  String? _currentRequestId;

  static void resetCache() {
    _cachedAllProducts.clear();
    _hasInitialDataLoaded = false;
    _lastSearchQuery = '';
    _cacheAllProductsLoaded = false;
  }

  @override
  void initState() {
    super.initState();
    if (widget.initialSearchQuery != null) {
      _searchController.text = widget.initialSearchQuery!;
    }
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearchChanged);
    _cachedAllProducts.clear();
    _hasInitialDataLoaded = false;
    _lastSearchQuery = '';
    _cacheAllProductsLoaded = false;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadProducts();
      }
    });
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    _scrollController.dispose();
    _searchTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged() {
    if (!mounted) return;
    final currentValue = _searchController.text.trim();
    if (currentValue == _lastSearchValue) {
      return;
    }
    _lastSearchValue = currentValue;
    _searchTimer?.cancel();
    setState(() => _isLoading = true);
    _searchTimer = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      if (currentValue.isEmpty) {
        if (_hasInitialDataLoaded && _cachedAllProducts.isNotEmpty) {
          setState(() {
            _filteredProducts = List.from(_cachedAllProducts);
            _allProductsLoaded = _cacheAllProductsLoaded;
            _isLoading = false;
          });
        } else {
          _loadProducts();
        }
      } else {
        _loadProducts();
      }
    });
  }

  void _onScroll() {
    if (_scrollController.hasClients &&
        _scrollController.position.pixels >=
            _scrollController.position.maxScrollExtent - 100) {
      if (!_isPaginating && !_allProductsLoaded && !_isLoading) {
        _loadProducts(isLoadMore: true);
      }
    }
  }

  Future<void> _loadProducts({bool isLoadMore = false}) async {
    if (!mounted) return;
    final requestId = DateTime.now().millisecondsSinceEpoch.toString();
    _currentRequestId = requestId;

    if (!isLoadMore) {
      setState(() {
        _isLoading = true;
        _isPaginating = false;
        _allProductsLoaded = false;
      });
    } else {
      setState(() => _isPaginating = true);
    }

    try {
      final invoiceProvider = Provider.of<CreateInvoiceProvider>(
        context,
        listen: false,
      );
      final searchQuery = _searchController.text.trim();
      await invoiceProvider.fetchProducts(
        searchQuery: searchQuery,
        isLoadMore: isLoadMore,
        category: 'All Products',
      );

      if (!mounted || _currentRequestId != requestId) {
        return;
      }

      final products = invoiceProvider.getProductsForCategory('All Products');
      final hasMoreData = invoiceProvider.hasMoreDataForCategory(
        'All Products',
      );

      _processAndDisplayProducts(
        products,
        searchQuery: searchQuery,
        isLoadMore: isLoadMore,
      );

      if (mounted) {
        setState(() {
          _allProductsLoaded = !hasMoreData;
          _isPaginating = false;
        });
      }
    } catch (e) {
      if (mounted && _currentRequestId == requestId) {
        CustomSnackbar.showError(context, 'Failed to load products: $e');
      }
    } finally {
      if (mounted && _currentRequestId == requestId) {
        setState(() {
          _isLoading = false;
          _isPaginating = false;
        });
      }
    }
  }

  void _processAndDisplayProducts(
    List<Product> products, {
    String? searchQuery,
    bool isLoadMore = false,
  }) {
    if (mounted) {
      final isSearching = searchQuery?.isNotEmpty ?? false;
      setState(() {
        _filteredProducts = List.from(products);
        if (!isSearching && !isLoadMore) {
          _cachedAllProducts = List.from(products);
          _hasInitialDataLoaded = true;
          _cacheAllProductsLoaded = _allProductsLoaded;
        }
        _lastSearchQuery = searchQuery ?? '';
      });
    }
  }

  Widget _buildLoadingIndicator() {
    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            LoadingAnimationWidget.fourRotatingDots(
              color: Theme.of(context).primaryColor,
              size: 30,
            ),
            const SizedBox(height: 8),
            Text(
              'Loading more products...',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildProductPlaceholder() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: 50,
      height: 50,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[700] : Colors.grey[200],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        HugeIcons.strokeRoundedPackage,
        color: isDark ? Colors.grey[400] : Colors.grey[500],
        size: 24,
      ),
    );
  }

  Widget _buildFadeInNetworkImage(String imageUrl, String name) {
    return CachedNetworkImage(
      imageUrl: imageUrl,
      width: 60,
      height: 60,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) => Container(color: Colors.grey[200]),
      errorWidget: (context, url, error) {
        return const Icon(
          HugeIcons.strokeRoundedImage03,
          color: Colors.grey,
          size: 24,
        );
      },
    );
  }

  Widget _buildFadeInBase64Image(String imageUrl, String name) {
    if (_base64ImageCache.containsKey(imageUrl)) {
      return _FadeInMemoryImage(bytes: _base64ImageCache[imageUrl]!);
    }
    try {
      final base64String = imageUrl.contains(',')
          ? imageUrl.split(',')[1]
          : imageUrl;
      if (RegExp(r'^[a-zA-Z0-9+/]*={0,2}$').hasMatch(base64String)) {
        final bytes = base64Decode(base64String);
        _base64ImageCache[imageUrl] = bytes;
        return _FadeInMemoryImage(bytes: bytes);
      }
    } catch (e) {}
    return const Icon(
      HugeIcons.strokeRoundedImage03,
      color: Colors.grey,
      size: 24,
    );
  }

  void _selectProduct(Product product) {
    showDialog(
      context: context,
      builder: (context) => QuantityDialog(
        product: product,
        onConfirm: (quantity, unitPrice) {
          widget.onProductSelected(product, quantity, unitPrice);
          Navigator.pop(context);
        },
      ),
    );
  }

  Widget _buildTag({
    required String text,
    required Color color,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: textColor,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey.shade600 : Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(
                  HugeIcons.strokeRoundedPackage,
                  color: isDark ? Colors.white : Theme.of(context).primaryColor,
                  size: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'Select Product',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).primaryColor,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: Icon(
                    HugeIcons.strokeRoundedCancelCircleHalfDot,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.grey.shade800
                        : Colors.grey.shade100,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              decoration: BoxDecoration(
                color: isDark ? Colors.grey.shade800 : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isDark ? Colors.grey.shade700 : Colors.grey.shade200,
                ),
              ),
              child: TextField(
                controller: _searchController,
                style: TextStyle(
                  color: isDark ? Colors.white : Colors.black87,
                  fontSize: 14,
                ),
                onChanged: (value) {
                  setState(() {});
                },
                decoration: InputDecoration(
                  hintText: 'Search products by name or code...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
                    fontSize: 14,
                  ),
                  prefixIcon: Icon(
                    HugeIcons.strokeRoundedSearch01,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade400,
                    size: 20,
                  ),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: Icon(
                            HugeIcons.strokeRoundedCancel01,
                            color: isDark
                                ? Colors.grey.shade400
                                : Colors.grey.shade400,
                            size: 18,
                          ),
                          onPressed: () {
                            _searchController.clear();
                            _onSearchChanged();
                          },
                        )
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          if (!_isLoading && _filteredProducts.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    '${_filteredProducts.length} product${_filteredProducts.length == 1 ? '' : 's'} found',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 8),
          Expanded(
            child: _isLoading
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        LoadingAnimationWidget.fourRotatingDots(
                          color: isDark
                              ? Colors.white
                              : Theme.of(context).primaryColor,
                          size: 40,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.trim().isNotEmpty
                              ? 'Searching for "${_searchController.text.trim()}"...'
                              : 'Loading products...',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                : _filteredProducts.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _searchController.text.trim().isNotEmpty
                              ? HugeIcons.strokeRoundedSearchList02
                              : HugeIcons.strokeRoundedPackage,
                          size: 64,
                          color: Colors.grey.shade300,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchController.text.trim().isNotEmpty
                              ? 'No products found for "${_searchController.text.trim()}"'
                              : 'No products available',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: Colors.grey.shade600,
                                fontWeight: FontWeight.w500,
                              ),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _searchController.text.trim().isNotEmpty
                              ? 'Try different keywords or clear the search'
                              : 'Check your connection or try refreshing',
                          style: Theme.of(context).textTheme.bodyMedium
                              ?.copyWith(color: Colors.grey.shade500),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount:
                        _filteredProducts.length + (_allProductsLoaded ? 0 : 1),
                    itemBuilder: (context, index) {
                      if (index == _filteredProducts.length &&
                          !_allProductsLoaded) {
                        return _buildLoadingIndicator();
                      }
                      final product = _filteredProducts[index];
                      return _buildProductCard(product, isDark);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductCard(Product product, bool isDark) {
    final isClicked = _clickedTileId == product.id;
    final textColor = isDark ? Colors.white : Colors.black87;
    final borderColor = isDark ? Colors.grey[800]! : Colors.grey[300]!;

    final imageUrl = product.imageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: isDark ? Colors.grey[900] : Colors.white,
        elevation: isClicked ? 4 : 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isClicked ? Theme.of(context).primaryColor : borderColor,
            width: isClicked ? 2 : 1,
          ),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _clickedTileId = product.id;
            });
            _selectProduct(product);
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Hero(
                  tag: 'product_image_${product.id}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      width: 60,
                      height: 60,
                      color: isDark ? Colors.grey[800] : Colors.grey[100],
                      child: imageUrl != null
                          ? (imageUrl.startsWith('http')
                                ? _buildFadeInNetworkImage(
                                    imageUrl,
                                    product.name,
                                  )
                                : _buildFadeInBase64Image(
                                    imageUrl,
                                    product.name,
                                  ))
                          : _buildProductPlaceholder(),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        product.name,
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (product.defaultCode.isNotEmpty &&
                              product.defaultCode.toLowerCase() != 'false')
                            _buildTag(
                              text: "SKU: ${product.defaultCode}",
                              color: isDark
                                  ? Colors.grey[900]!
                                  : Colors.grey[100]!,
                              textColor: isDark
                                  ? Colors.white
                                  : Colors.grey[700]!,
                            ),
                          const SizedBox(width: 8),
                          Consumer<CurrencyProvider>(
                            builder: (context, currencyProvider, _) {
                              return Text(
                                currencyProvider.formatAmount(
                                  product.listPrice,
                                  currency:
                                      currencyProvider.companyCurrencyIdList !=
                                              null &&
                                          currencyProvider
                                                  .companyCurrencyIdList!
                                                  .length >
                                              1
                                      ? currencyProvider
                                            .companyCurrencyIdList![1]
                                            .toString()
                                      : currencyProvider.currency,
                                ),
                                style: TextStyle(
                                  color: isDark
                                      ? Colors.white
                                      : (isClicked
                                            ? Theme.of(
                                                context,
                                              ).primaryColor.withOpacity(0.7)
                                            : Theme.of(context).primaryColor),
                                  fontWeight: FontWeight.bold,
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          _buildTag(
                            text: "${product.qtyAvailable} in stock",
                            color: isDark
                                ? Colors.grey[900]!
                                : product.qtyAvailable > 0
                                ? Colors.green[50]!
                                : Colors.red[50]!,
                            textColor: isDark
                                ? Colors.white
                                : product.qtyAvailable > 0
                                ? Colors.green[700]!
                                : Colors.red[700]!,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _InvoiceLineItem extends StatefulWidget {
  final Map<String, dynamic> line;
  final int index;
  final bool isLast;
  final bool isDark;
  final Color primaryColor;
  final CurrencyProvider currencyProvider;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(double, double) onUpdate;

  const _InvoiceLineItem({
    required this.line,
    required this.index,
    required this.isLast,
    required this.isDark,
    required this.primaryColor,
    required this.currencyProvider,
    required this.onEdit,
    required this.onDelete,
    required this.onUpdate,
  });

  @override
  __InvoiceLineItemState createState() => __InvoiceLineItemState();
}

class __InvoiceLineItemState extends State<_InvoiceLineItem> {
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
    final isFromSaleOrder = widget.line['sale_line_id'] != null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850] : Colors.white;
    final borderColor = isDark ? Colors.grey[700]! : Colors.grey[200]!;
    final textColor = isDark ? Colors.white : Colors.black87;
    final secondaryTextColor = isDark ? Colors.grey[400] : Colors.grey[600];

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: cardColor,
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
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              widget.line['product_name']?.toString() ??
                                  'Unnamed Product',
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: textColor,
                              ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isFromSaleOrder)
                            Container(
                              margin: const EdgeInsets.only(left: 8),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'SALE ORDER',
                                style: TextStyle(
                                  color: Colors.blue[700],
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                        ],
                      ),
                      if (widget.line['product_data']?['default_code'] !=
                              null &&
                          widget.line['product_data']['default_code']
                              .toString()
                              .trim()
                              .isNotEmpty &&
                          widget.line['product_data']['default_code']
                                  .toString()
                                  .toLowerCase() !=
                              'false')
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
                      _QuantityInput(
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
                      _PriceInput(
                        initialValue: unitPrice,
                        onChanged: (value) {
                          setState(() => unitPrice = value);
                          widget.onUpdate(quantity, value);
                        },
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),

                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      'Total',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: secondaryTextColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.currencyProvider.formatAmount(
                        subtotal,
                        currency:
                            widget.currencyProvider.companyCurrencyIdList !=
                                    null &&
                                widget
                                        .currencyProvider
                                        .companyCurrencyIdList!
                                        .length >
                                    1
                            ? widget.currencyProvider.companyCurrencyIdList![1]
                                  .toString()
                            : widget.currencyProvider.currency,
                      ),
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white : theme.primaryColor,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _QuantityInput extends StatefulWidget {
  final double initialValue;
  final Function(double) onChanged;

  const _QuantityInput({required this.initialValue, required this.onChanged});

  @override
  __QuantityInputState createState() => __QuantityInputState();
}

class __QuantityInputState extends State<_QuantityInput> {
  late TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.initialValue.toStringAsFixed(0),
    );
    _controller.addListener(_onQuantityChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQuantityChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQuantityChanged() {
    final value = double.tryParse(_controller.text) ?? 0.0;
    widget.onChanged(value > 0 ? value : 1.0);
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
                if (currentValue > 1) {
                  _controller.text = (currentValue - 1).toInt().toString();
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
                style: theme.textTheme.bodyMedium,
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
                _controller.text = (currentValue + 1).toInt().toString();
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

class _PriceInput extends StatefulWidget {
  final double initialValue;
  final Function(double) onChanged;

  const _PriceInput({required this.initialValue, required this.onChanged});

  @override
  __PriceInputState createState() => __PriceInputState();
}

class __PriceInputState extends State<_PriceInput> {
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
          filled: isDark,
          fillColor: isDark ? Colors.grey[800] : null,
          prefixIcon: Padding(
            padding: const EdgeInsets.only(
              left: 12,
              right: 8,
              top: 12,
              bottom: 12,
            ),
            child: Text(
              (Provider.of<CurrencyProvider>(
                    context,
                    listen: false,
                  ).currencyFormat.currencySymbol).isNotEmpty
                  ? Provider.of<CurrencyProvider>(
                      context,
                      listen: false,
                    ).currencyFormat.currencySymbol
                  : Provider.of<CurrencyProvider>(
                      context,
                      listen: false,
                    ).currency,
              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey),
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
  final Product product;
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
    _priceController.text = widget.product.listPrice.toString();
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
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: isDark
                                ? colorScheme.onSurface
                                : colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _displayValue(widget.product.name),
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
                            currencyProvider.companyCurrencyIdList != null &&
                                currencyProvider.companyCurrencyIdList!.length >
                                    1
                            ? currencyProvider.companyCurrencyIdList![1]
                                  .toString()
                            : currencyProvider.currency;

                        return CustomTextField(
                          controller: _priceController,
                          labelText: 'Unit Price ($currencySymbol)',
                          isDark: isDark,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                            signed: false,
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
                    Text(
                      'Total:',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    ValueListenableBuilder(
                      valueListenable: _quantityController,
                      builder: (context, quantityValue, _) {
                        return ValueListenableBuilder(
                          valueListenable: _priceController,
                          builder: (context, priceValue, _) {
                            final quantity =
                                double.tryParse(quantityValue.text) ?? 0;
                            final price = double.tryParse(priceValue.text) ?? 0;
                            final total = quantity * price;

                            return Consumer<CurrencyProvider>(
                              builder: (context, currencyProvider, _) {
                                return Text(
                                  currencyProvider.formatAmount(
                                    total,
                                    currency:
                                        currencyProvider
                                                    .companyCurrencyIdList !=
                                                null &&
                                            currencyProvider
                                                    .companyCurrencyIdList!
                                                    .length >
                                                1
                                        ? currencyProvider
                                              .companyCurrencyIdList![1]
                                              .toString()
                                        : currencyProvider.currency,
                                  ),
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: isDark
                                        ? Colors.white
                                        : Theme.of(context).primaryColor,
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.pop(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: TextStyle(
                        color: isDark ? Colors.white : AppTheme.primaryColor,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: _isLoading ? null : _handleConfirm,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(
                            'Add to Invoice',
                            style: TextStyle(
                              color: isDark ? Colors.white : Colors.white,
                            ),
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

class _FadeInMemoryImage extends StatefulWidget {
  final Uint8List bytes;

  const _FadeInMemoryImage({required this.bytes});

  @override
  State<_FadeInMemoryImage> createState() => _FadeInMemoryImageState();
}

class _FadeInMemoryImageState extends State<_FadeInMemoryImage> {
  double _opacity = 0.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        setState(() {
          _opacity = 1.0;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _opacity,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeIn,
      child: Image.memory(
        widget.bytes,
        fit: BoxFit.cover,
        width: 60,
        height: 60,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(
            HugeIcons.strokeRoundedImage03,
            color: Colors.grey,
            size: 24,
          );
        },
      ),
    );
  }
}
