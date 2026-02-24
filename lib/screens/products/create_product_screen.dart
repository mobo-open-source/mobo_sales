import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/product.dart';
import '../../services/product_service.dart';
import '../../widgets/confetti_dialogs.dart';
import '../../utils/data_loss_warning_mixin.dart';
import 'dart:io';
import 'dart:convert';
import 'package:image_picker/image_picker.dart';
import '../../widgets/barcode_scanner_screen.dart';
import 'package:provider/provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/custom_snackbar.dart';

class CreateProductScreen extends StatefulWidget {
  final Product? product;

  const CreateProductScreen({super.key, this.product});

  @override
  State<CreateProductScreen> createState() => _CreateProductScreenState();
}

class _CreateProductScreenState extends State<CreateProductScreen>
    with DataLossWarningMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _dropdownError;
  bool _isServerUnreachable = false;

  List<Map<String, String>> _categoryOptions = [];
  List<Map<String, String>> _taxOptions = [];
  List<Map<String, String>> _uomOptions = [];
  List<Map<String, String>> _currencyOptions = [];
  bool _dropdownsLoading = true;

  @override
  bool get hasUnsavedData {
    if (_dropdownsLoading) return false;

    return _nameController.text.trim().isNotEmpty ||
        _defaultCodeController.text.trim().isNotEmpty ||
        _barcodeController.text.trim().isNotEmpty ||
        _descriptionController.text.trim().isNotEmpty ||
        _listPriceController.text.trim().isNotEmpty ||
        _standardPriceController.text.trim().isNotEmpty ||
        _weightController.text.trim().isNotEmpty ||
        _volumeController.text.trim().isNotEmpty ||
        _dimensionsController.text.trim().isNotEmpty ||
        _leadTimeController.text.trim().isNotEmpty ||
        _selectedCategory != null ||
        _selectedTax != null ||
        _selectedUOM != null ||
        _selectedCurrency != null ||
        _pickedImageFile != null;
  }

  @override
  String get dataLossTitle =>
      _isEditMode ? 'Discard Changes?' : 'Discard Product?';

  @override
  String get dataLossMessage => _isEditMode
      ? 'You have unsaved changes that will be lost if you leave this page. Are you sure you want to discard these changes?'
      : 'You have unsaved product data that will be lost if you leave this page. Are you sure you want to discard this product?';

  @override
  void onConfirmLeave() {
    _nameController.clear();
    _defaultCodeController.clear();
    _barcodeController.clear();
    _descriptionController.clear();
    _listPriceController.clear();
    _standardPriceController.clear();
    _weightController.clear();
    _volumeController.clear();
    _dimensionsController.clear();
    _leadTimeController.clear();
    _selectedCategory = null;
    _selectedTax = null;
    _selectedUOM = null;
    _selectedCurrency = null;
    _pickedImageFile = null;
    _pickedImageBase64 = null;
  }

  late TextEditingController _nameController;
  late TextEditingController _defaultCodeController;
  late TextEditingController _barcodeController;
  late TextEditingController _descriptionController;
  late TextEditingController _listPriceController;
  late TextEditingController _standardPriceController;
  late TextEditingController _weightController;
  late TextEditingController _volumeController;
  late TextEditingController _dimensionsController;
  late TextEditingController _leadTimeController;

  String? _selectedCategory;
  String? _selectedTax;
  String? _selectedUOM;
  String? _selectedCurrency;
  bool _isActive = true;
  bool _canBeSold = true;
  bool _canBePurchased = true;

  bool _isEditMode = false;

  File? _pickedImageFile;
  String? _pickedImageBase64;
  final ImagePicker _picker = ImagePicker();

  bool get _isNameFilled => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.product != null;
    final p = widget.product;
    String clean(String? v) => (v == null || v == 'false') ? '' : v;

    if (p != null) {}

    _nameController = TextEditingController(text: clean(p?.name));
    _defaultCodeController = TextEditingController(text: clean(p?.defaultCode));
    _barcodeController = TextEditingController(text: clean(p?.barcode));
    _descriptionController = TextEditingController(text: clean(p?.description));
    _listPriceController = TextEditingController(
      text: p?.listPrice.toString() ?? '',
    );
    _standardPriceController = TextEditingController(
      text: p?.cost?.toString() ?? '',
    );
    _weightController = TextEditingController(
      text: p?.weight?.toString() ?? '',
    );
    _volumeController = TextEditingController(
      text: p?.volume?.toString() ?? '',
    );
    _dimensionsController = TextEditingController(text: clean(p?.dimensions));
    _leadTimeController = TextEditingController(
      text: p?.leadTime?.toString() ?? '',
    );

    _selectedCategory = null;
    _selectedTax = null;
    _selectedUOM = null;
    _selectedCurrency = null;
    _isActive = p?.active ?? true;
    _canBeSold = p?.saleOk ?? true;
    _canBePurchased = p?.purchaseOk ?? true;

    _fetchDropdowns();
    _nameController.addListener(() {
      setState(() {});
    });

    _pickedImageFile = null;
    _pickedImageBase64 = null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _defaultCodeController.dispose();
    _barcodeController.dispose();
    _descriptionController.dispose();
    _listPriceController.dispose();
    _standardPriceController.dispose();
    _weightController.dispose();
    _volumeController.dispose();
    _dimensionsController.dispose();
    _leadTimeController.dispose();
    super.dispose();
  }

  bool _isServerUnreachableError(dynamic error) {
    final s = error.toString().toLowerCase();
    return s.contains('socketexception') ||
        s.contains('connection refused') ||
        s.contains('connection timeout') ||
        s.contains('host unreachable') ||
        s.contains('no route to host') ||
        s.contains('network is unreachable') ||
        s.contains('failed to connect') ||
        s.contains('connection failed') ||
        s.contains('server returned html instead of json') ||
        s.contains('server may be down') ||
        s.contains('url incorrect');
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    final picked = await _picker.pickImage(
      source: source,
      imageQuality: 80,
      maxWidth: 600,
    );
    if (picked != null) {
      setState(() {
        _pickedImageFile = File(picked.path);
      });
      final bytes = await picked.readAsBytes();
      setState(() {
        _pickedImageBase64 = base64Encode(bytes);
      });
    }
  }

  void _showImageSourceActionSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[700] : Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.camera);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedCamera02,
                      size: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    const Text('Take Photo', style: TextStyle(fontSize: 16)),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickImageFromSource(ImageSource.gallery);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedImageAdd01,
                      size: 20,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                    const SizedBox(width: 16),
                    const Text(
                      'Choose from Gallery',
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: isDark ? Colors.grey[800] : Colors.grey[200],
            ),
          ],
        );
      },
    );
  }

  Future<void> _scanBarcode() async {
    final result = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (context) => BarcodeScannerScreen()),
    );
    if (!mounted) return;
    if (result != null && result.isNotEmpty) {
      setState(() {
        _barcodeController.text = result;
      });
    }
  }

  Future<void> save() async {
    final formState = _formKey.currentState;
    if (formState == null) return;

    if (_nameController.text.trim().isEmpty) {
      CustomSnackbar.showError(context, 'Product name is required');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      if (!_isEditMode) {
        final allowed = await ProductService.instance.canCreateProduct();
        if (!allowed) {
          if (mounted) {
            CustomSnackbar.showError(
              context,
              'You do not have permission to create products in Odoo. Please contact your administrator.',
            );
          }
          return;
        }
      }

      final data = <String, dynamic>{};

      data['name'] = _nameController.text.trim();
      data['default_code'] = _defaultCodeController.text.trim();
      data['barcode'] = _barcodeController.text.trim();
      data['description_sale'] = _descriptionController.text.trim();
      data['active'] = _isActive;
      data['sale_ok'] = _canBeSold;
      data['purchase_ok'] = _canBePurchased;

      data['list_price'] = _parseDouble(_listPriceController.text);
      data['standard_price'] = _parseDouble(_standardPriceController.text);
      data['weight'] = _parseDouble(_weightController.text);
      data['volume'] = _parseDouble(_volumeController.text);

      _handleRelationalFields(data);
      _handleImageData(data);

      if (_isEditMode) {
        final success = await ProductService.instance
            .updateProduct(widget.product!.id, data)
            .timeout(Duration(seconds: 30));

        if (!mounted) {
          return;
        }

        if (success) {
          if (mounted) {
            Navigator.pop(context, true);
          } else {}
        } else {
          if (mounted) {
            CustomSnackbar.showError(
              context,
              _getUserFriendlyErrorMessage(Exception('Update failed')),
            );
          }
        }
      } else {
        final resultProduct = await ProductService.instance
            .createProduct(data)
            .timeout(Duration(seconds: 30));

        if (!mounted) {
          return;
        }

        if (resultProduct != null) {
          final productName = resultProduct.name ?? _nameController.text.trim();

          if (mounted) {
            try {
              await showProductCreatedConfettiDialog(context, productName);
            } catch (e) {}

            if (mounted) {
              Navigator.pop(context, true);
            } else {}
          }
        } else {
          if (mounted) {
            CustomSnackbar.showError(
              context,
              _getUserFriendlyErrorMessage(Exception('Creation failed')),
            );
          }
        }
      }
    } catch (e) {
      String userFriendlyMessage = _getUserFriendlyErrorMessage(e);
      if (mounted) {
        try {
          CustomSnackbar.showError(context, userFriendlyMessage);
        } catch (e) {}
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('you do not have permission')) {
      final fullError = error.toString();
      if (fullError.contains('You do not have permission to create products')) {
        return 'Permission Denied: You do not have permission to create products (product.template create). Please contact your administrator.';
      } else if (fullError.contains(
        'You do not have permission to update products',
      )) {
        return 'Permission Denied: You do not have permission to update products (product.template write). Please contact your administrator.';
      } else {
        return fullError.replaceAll('Exception: ', '');
      }
    }

    if (errorString.contains('accesserror')) {
      if (errorString.contains('list_price') ||
          errorString.contains('standard_price')) {
        return 'You don\'t have permission to set product prices. The product will be created without pricing information.';
      } else if (errorString.contains('categ_id') ||
          errorString.contains('category')) {
        return 'You don\'t have permission to set product categories. The product will be created with default category.';
      } else if (errorString.contains('taxes_id') ||
          errorString.contains('tax')) {
        return 'You don\'t have permission to set tax information. The product will be created without tax settings.';
      } else if (errorString.contains('uom_id') ||
          errorString.contains('unit')) {
        return 'You don\'t have permission to set unit of measure. The product will be created with default unit.';
      } else if (errorString.contains('property_')) {
        return 'You don\'t have permission to set some advanced properties. The product will be created with basic information.';
      } else {
        return 'You don\'t have sufficient permissions to access some fields. Please contact your system administrator.';
      }
    }

    if (errorString.contains('validationerror')) {
      if (errorString.contains('name')) {
        return 'Product name is required and must be unique.';
      } else if (errorString.contains('barcode')) {
        return 'Please enter a valid barcode or leave it empty.';
      } else if (errorString.contains('price')) {
        return 'Please enter valid price values (numbers only).';
      } else {
        return 'Please check your input data for errors.';
      }
    }

    if (errorString.contains('duplicate') ||
        errorString.contains('already exists')) {
      if (errorString.contains('name')) {
        return 'A product with this name already exists.';
      } else if (errorString.contains('barcode')) {
        return 'A product with this barcode already exists.';
      } else if (errorString.contains('default_code')) {
        return 'A product with this internal reference already exists.';
      } else {
        return 'A product with similar information already exists.';
      }
    }

    if (_isServerUnreachableError(error)) {
      return 'Unable to connect to the server. Please check your internet connection and try again.';
    }

    if (errorString.contains('session') ||
        errorString.contains('authentication') ||
        errorString.contains('login')) {
      return 'Your session has expired. Please log in again.';
    }

    if (errorString.contains('database') ||
        errorString.contains('constraint')) {
      return 'Database error occurred. Please try again or contact support.';
    }

    if (errorString.contains('timeout')) {
      return 'Operation timed out. Please check your connection and try again.';
    }

    if (errorString.contains('formatexception') ||
        errorString.contains('invalid field')) {
      return 'Invalid data format. Please check your inputs and try again.';
    }

    if (_isEditMode) {
      return 'Failed to update product. Please try again.';
    } else {
      return 'Failed to create product. Please try again.';
    }
  }

  double? _parseDouble(String value) {
    if (value.trim().isEmpty) return null;
    return double.tryParse(value.trim());
  }

  void _handleRelationalFields(Map<String, dynamic> data) {
    if (_selectedCategory != null) {
      data['categ_id'] = int.tryParse(_selectedCategory!);
    } else if (_isEditMode && widget.product?.categId != null) {
      if (widget.product!.categId is int) {
        data['categ_id'] = widget.product!.categId;
      } else if (widget.product!.categId is List) {
        data['categ_id'] = widget.product!.categId[0];
      }
    }

    if (_selectedTax != null) {
      data['taxes_id'] = [
        [
          6,
          0,
          [int.tryParse(_selectedTax!)],
        ],
      ];
    } else if (_isEditMode && widget.product?.taxesIds != null) {
      data['taxes_id'] = [
        [6, 0, widget.product!.taxesIds],
      ];
    }

    if (_selectedUOM != null) {
      data['uom_id'] = int.tryParse(_selectedUOM!);
    } else if (_isEditMode && widget.product?.uomId != null) {
      if (widget.product!.uomId is int) {
        data['uom_id'] = widget.product!.uomId;
      } else if (widget.product!.uomId is List) {
        data['uom_id'] = widget.product!.uomId[0];
      }
    }

    if (_selectedCurrency != null) {
      data['currency_id'] = int.tryParse(_selectedCurrency!);
    } else if (_isEditMode && widget.product?.currencyId != null) {
      if (widget.product!.currencyId is int) {
        data['currency_id'] = widget.product!.currencyId;
      } else if (widget.product!.currencyId is List) {
        data['currency_id'] = widget.product!.currencyId?[0];
      }
    }
  }

  void _handleImageData(Map<String, dynamic> data) {
    if (_pickedImageBase64 != null) {
      data['image_1920'] = _pickedImageBase64;
    } else if (_isEditMode && widget.product?.imageUrl != null) {
      final existingImage = widget.product!.imageUrl!;
      if (existingImage.startsWith('data:image')) {
        data['image_1920'] = existingImage.split(',').last;
      } else {
        data['image_1920'] = existingImage;
      }
    }
  }

  Future<void> _fetchDropdowns({
    bool forceRefresh = false,
    bool silentRevalidate = false,
  }) async {
    if (!silentRevalidate) {
      setState(() {
        _dropdownsLoading = true;
        _dropdownError = null;
        _isServerUnreachable = false;
      });
    }
    try {
      List<String> failedDropdowns = [];
      int serverErrorCount = 0;

      final futures = <Future<List<Map<String, String>>?>>[
        (() async {
          try {
            final data = await ProductService.instance.fetchCategoryOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Categories');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await ProductService.instance.fetchTaxOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Taxes');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await ProductService.instance.fetchUOMOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Units of Measure');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await ProductService.instance.fetchCurrencyOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Currencies');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
      ];

      final results = await Future.wait<List<Map<String, String>>?>(
        futures,
        eagerError: false,
      );

      final int totalCalls = futures.length;
      final bool allFailedWithServerError = serverErrorCount >= totalCalls;
      if (allFailedWithServerError) {
        if (mounted) {
          setState(() {
            _categoryOptions = [];
            _taxOptions = [];
            _uomOptions = [];
            _currencyOptions = [];
            _dropdownsLoading = false;
            _isServerUnreachable = true;
            _dropdownError =
                'The Odoo server or database could not be reached. Please check your server settings or try again later.';
          });
        }
        return;
      }

      setState(() {
        _categoryOptions = results[0] ?? [];
        _taxOptions = results[1] ?? [];
        _uomOptions = results[2] ?? [];
        _currencyOptions = results[3] ?? [];

        final p = widget.product;
        if (p != null) {
          if (p.categId != null) {
            if (p.categId is List && p.categId.length > 0) {
              _selectedCategory = p.categId[0].toString();
            } else if (p.categId is int) {
              _selectedCategory = p.categId.toString();
            }
          }

          if (p.taxesIds != null && p.taxesIds!.isNotEmpty) {
            if (p.taxesIds![0] is int) {
              _selectedTax = p.taxesIds![0].toString();
            }
          }

          if (p.uomId != null) {
            _selectedUOM = p.uomId.toString();
          }

          if (p.currencyId != null) {
            if (p.currencyId is List && p.currencyId!.isNotEmpty) {
              _selectedCurrency = p.currencyId![0].toString();
            } else if (p.currencyId is int) {
              _selectedCurrency = p.currencyId.toString();
            }
          }
        }

        if (!silentRevalidate) {
          _dropdownsLoading = false;
        }

        _isServerUnreachable = false;

        if (!silentRevalidate && failedDropdowns.isNotEmpty && mounted) {
          CustomSnackbar.show(
            context: context,
            title: 'Warning',
            message:
                'Some options failed to load: ${failedDropdowns.join(', ')}. You can enter values manually.',
            type: SnackbarType.warning,
            duration: Duration(seconds: 4),
          );
        }
      });
    } catch (e) {
      String userFriendlyError;
      if (e.toString().contains('Invalid field') &&
          e.toString().contains('category_id')) {
        userFriendlyError =
            'Server compatibility issue detected. Some dropdown options may be limited, but the form will still work.';
      } else if (e.toString().contains('No active Odoo session')) {
        userFriendlyError =
            'Session expired. Please login again to load dropdown options.';
      } else if (_isServerUnreachableError(e)) {
        userFriendlyError =
            'The Odoo server or database could not be reached. Please check your server settings or try again later.';
        _isServerUnreachable = true;
      } else if (e.toString().contains('TimeoutException')) {
        userFriendlyError =
            'Request timed out. Please check your connection and try again.';
      } else if (e.toString().contains('FormatException')) {
        userFriendlyError =
            'Server returned invalid data. Please try again or contact support.';
      } else {
        userFriendlyError =
            'Unable to load dropdown options. You can still create products manually.';
      }

      if (!silentRevalidate) {
        setState(() {
          _dropdownError = userFriendlyError;
          _dropdownsLoading = false;
        });
      } else {}
    }
  }

  Future<void> _onReloadOptionsPressed() async {
    if (!mounted) return;
    try {
      CustomSnackbar.showInfo(context, 'Refreshing options...');
    } catch (_) {}
    try {
      ProductService.instance.clearDropdownCaches();
      await _fetchDropdowns(forceRefresh: true);
      if (!mounted) return;
      CustomSnackbar.showSuccess(context, 'Options updated');
    } catch (e) {}
  }

  InputDecoration themedInputDecoration(
    BuildContext context, {
    required String label,
    String? hint,
    Widget? prefixIcon,
    Widget? suffixIcon,
    String? errorText,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return InputDecoration(
      labelText: label,
      hintText: hint,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      errorText: null,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Theme.of(context).primaryColor, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red[700]!, width: 2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.red[700]!, width: 2),
      ),
      filled: true,
      fillColor: isDark ? Colors.grey[850] : Colors.grey[50],
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
    );
  }

  Widget themedErrorText(String error, BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 2, bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, color: Colors.red[700], size: 18),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red[700],
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _shimmerField(bool isDark, {double height = 44}) {
    return Container(
      height: height,
      width: double.infinity,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _shimmerDropdown(bool isDark) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[750] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[200],
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _shimmerTextFieldWithSuffix(bool isDark) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[850] : Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[750] : Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[700] : Colors.grey[200],
              borderRadius: BorderRadius.circular(6),
            ),
          ),
          const SizedBox(width: 12),
        ],
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
                _isEditMode ? 'Edit Product' : 'Create Product',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              foregroundColor: isDark ? Colors.white : primaryColor,
              elevation: 0,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  HugeIcons.strokeRoundedArrowLeft01,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Reload options',
                  onPressed: _dropdownsLoading ? null : _onReloadOptionsPressed,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: ConnectionStatusWidget(
              onRetry: () async {
                final ok = await connectivityService.checkConnectivityOnce();
                if (ok && mounted) setState(() {});
              },
            ),
          );
        }

        if (_isServerUnreachable) {
          return Scaffold(
            appBar: AppBar(
              title: Text(
                _isEditMode ? 'Edit Product' : 'Create Product',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              backgroundColor: isDark ? Colors.grey[900] : Colors.white,
              foregroundColor: isDark ? Colors.white : primaryColor,
              elevation: 0,
              leading: IconButton(
                onPressed: () => Navigator.pop(context),
                icon: Icon(
                  HugeIcons.strokeRoundedArrowLeft01,
                  color: isDark ? Colors.white : Colors.black,
                ),
              ),
              actions: [
                IconButton(
                  tooltip: 'Reload options',
                  onPressed: _dropdownsLoading ? null : _onReloadOptionsPressed,
                  icon: const Icon(Icons.refresh),
                ),
              ],
            ),
            body: ConnectionStatusWidget(
              onRetry: _dropdownsLoading
                  ? null
                  : () async {
                      await _onReloadOptionsPressed();
                    },
              serverUnreachable: true,
              serverErrorMessage: _dropdownError,
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
          child: _buildContent(context, isDark, primaryColor),
        );
        return (Platform.isAndroid && hasUnsavedData)
            ? WillPopScope(onWillPop: () => handleWillPop(), child: popChild)
            : popChild;
      },
    );
  }

  Widget _buildContent(BuildContext context, bool isDark, Color primaryColor) {
    if (_dropdownError != null && !_isServerUnreachable) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditMode ? 'Edit Product' : 'Create Product',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          foregroundColor: isDark ? Colors.white : primaryColor,
          elevation: 0,
          leading: IconButton(
            onPressed: () => handleNavigation(() => Navigator.pop(context)),
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Reload options',
              onPressed: _dropdownsLoading ? null : _onReloadOptionsPressed,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.orange.withOpacity(0.1),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(20),
                    child: Icon(
                      HugeIcons.strokeRoundedAlert02,
                      color: Colors.orange,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    'Loading Issue',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.black87,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),

                  Container(
                    padding: EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
                      ),
                    ),
                    child: Text(
                      _dropdownError!,
                      style: TextStyle(
                        color: isDark ? Colors.grey[300] : Colors.grey[700],
                        fontSize: 14,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      ElevatedButton.icon(
                        onPressed: _fetchDropdowns,
                        icon: Icon(HugeIcons.strokeRoundedRefresh, size: 18),
                        label: Text(
                          'Retry',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: primaryColor,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),

                      TextButton.icon(
                        onPressed: () {
                          setState(() {
                            _dropdownError = null;
                            _dropdownsLoading = false;

                            _categoryOptions = [];
                            _taxOptions = [];
                            _uomOptions = [];
                            _currencyOptions = [];
                          });
                        },
                        icon: Icon(
                          HugeIcons.strokeRoundedArrowRight01,
                          size: 18,
                        ),
                        label: Text(
                          'Continue Anyway',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        style: TextButton.styleFrom(
                          foregroundColor: isDark
                              ? Colors.grey[300]
                              : Colors.grey[700],
                          padding: const EdgeInsets.symmetric(
                            vertical: 12,
                            horizontal: 20,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                            side: BorderSide(
                              color: isDark
                                  ? Colors.grey[600]!
                                  : Colors.grey[300]!,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'You can continue without dropdown options and enter values manually.',
                    style: TextStyle(
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      fontSize: 12,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    if (_dropdownsLoading) {
      final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
      final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditMode ? 'Edit Product' : 'Create Product',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          foregroundColor: isDark ? Colors.white : primaryColor,
          elevation: 0,
          leading: IconButton(
            onPressed: () => handleNavigation(() => Navigator.pop(context)),
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            IconButton(
              tooltip: 'Reload options',
              onPressed: _dropdownsLoading ? null : _onReloadOptionsPressed,
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        body: Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Shimmer.fromColors(
            baseColor: shimmerBase,
            highlightColor: shimmerHighlight,
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Stack(
                      alignment: Alignment.bottomRight,
                      children: [
                        Container(
                          width: 96,
                          height: 96,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[850] : Colors.grey[50],
                            shape: BoxShape.circle,
                          ),
                        ),
                        Positioned(
                          right: 4,
                          bottom: 4,
                          child: Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: isDark
                                  ? Colors.grey[850]
                                  : Colors.grey[50],
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  _shimmerField(isDark, height: 44),
                  const SizedBox(height: 12),

                  _shimmerField(isDark, height: 44),
                  const SizedBox(height: 12),

                  _shimmerTextFieldWithSuffix(isDark),
                  const SizedBox(height: 12),

                  _shimmerDropdown(isDark),
                  const SizedBox(height: 12),

                  _shimmerField(isDark, height: 44),
                  const SizedBox(height: 12),

                  _shimmerField(isDark, height: 44),
                  const SizedBox(height: 12),

                  _shimmerDropdown(isDark),
                  const SizedBox(height: 12),

                  _shimmerDropdown(isDark),
                  const SizedBox(height: 12),

                  _shimmerDropdown(isDark),
                  const SizedBox(height: 12),

                  _shimmerField(isDark, height: 44),
                  const SizedBox(height: 12),

                  _shimmerField(isDark, height: 44),
                  const SizedBox(height: 12),

                  _shimmerField(isDark, height: 80),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[50],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        height: 16,
                        width: 80,
                        color: isDark ? Colors.grey[850] : Colors.grey[50],
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  Container(
                    height: 48,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.grey[850] : Colors.grey[50],
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget photoWidget;
    if (_pickedImageFile != null) {
      photoWidget = CircleAvatar(
        radius: 48,
        backgroundColor: isDark
            ? Colors.grey.shade200
            : Theme.of(context).primaryColor.withOpacity(.1),
        backgroundImage: FileImage(_pickedImageFile!),
      );
    } else if (widget.product?.imageUrl != null &&
        widget.product!.imageUrl!.isNotEmpty) {
      final imageUrl = widget.product!.imageUrl!;
      if (imageUrl.startsWith('http')) {
        photoWidget = CircleAvatar(
          radius: 48,
          backgroundColor: isDark
              ? Colors.grey.shade200
              : Theme.of(context).primaryColor.withOpacity(.1),
          backgroundImage: NetworkImage(imageUrl),
        );
      } else {
        try {
          final base64String = imageUrl.contains(',')
              ? imageUrl.split(',').last
              : imageUrl;
          final bytes = base64Decode(base64String);
          photoWidget = CircleAvatar(
            radius: 48,
            backgroundColor: isDark
                ? Colors.grey.shade200
                : Theme.of(context).primaryColor.withOpacity(.1),
            backgroundImage: MemoryImage(bytes),
          );
        } catch (e) {
          photoWidget = CircleAvatar(
            radius: 48,
            backgroundColor: isDark
                ? Colors.grey.shade200
                : Theme.of(context).primaryColor.withOpacity(.1),
            child: Icon(
              HugeIcons.strokeRoundedImage03,
              size: 48,
              color: isDark ? Colors.grey.shade800 : primaryColor,
            ),
          );
        }
      }
    } else {
      photoWidget = CircleAvatar(
        radius: 48,
        backgroundColor: isDark
            ? Colors.grey.shade200
            : Theme.of(context).primaryColor.withOpacity(.1),
        child: Icon(
          HugeIcons.strokeRoundedImage03,
          size: 48,
          color: isDark ? Colors.grey.shade800 : primaryColor,
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditMode ? 'Edit Product' : 'Create Product',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        foregroundColor: isDark ? Colors.white : primaryColor,
        elevation: 0,
        leading: IconButton(
          onPressed: () => handleNavigation(() => Navigator.pop(context)),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'Reload options',
            onPressed: _dropdownsLoading ? null : _onReloadOptionsPressed,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      body: Container(
        color: isDark ? Colors.grey[900] : Colors.white,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Center(
                child: Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    photoWidget,
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: InkWell(
                        onTap: _isLoading ? null : _showImageSourceActionSheet,
                        borderRadius: BorderRadius.circular(24),
                        child: CircleAvatar(
                          radius: 18,
                          backgroundColor: isDark
                              ? Colors.grey
                              : Theme.of(context).primaryColor,
                          child: Icon(
                            HugeIcons.strokeRoundedImageAdd01,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              CustomTextField(
                controller: _nameController,
                labelText: 'Product Name *',
                hintText: 'Enter product name',
                isDark: isDark,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Product name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _defaultCodeController,
                labelText: 'SKU/Default Code',
                hintText: 'Enter SKU',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _barcodeController,
                labelText: 'Barcode',
                hintText: 'Enter barcode or scan using camera',
                isDark: isDark,
                validator: (v) => null,
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  onPressed: _scanBarcode,
                  tooltip: 'Scan Barcode',
                ),
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value:
                    _categoryOptions.any((m) => m['value'] == _selectedCategory)
                    ? _selectedCategory
                    : null,
                labelText: 'Category',
                hintText: 'Select a product category',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _categoryOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedCategory = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _listPriceController,
                labelText: 'List Price',
                hintText: 'Enter selling price',
                isDark: isDark,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _standardPriceController,
                labelText: 'Cost Price',
                hintText: 'Enter cost price',
                isDark: isDark,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value: _taxOptions.any((m) => m['value'] == _selectedTax)
                    ? _selectedTax
                    : null,
                labelText: 'Tax',
                hintText: 'Select applicable tax',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _taxOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedTax = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value: _uomOptions.any((m) => m['value'] == _selectedUOM)
                    ? _selectedUOM
                    : null,
                labelText: 'Unit of Measure',
                hintText: 'Select unit',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _uomOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedUOM = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value:
                    _currencyOptions.any((m) => m['value'] == _selectedCurrency)
                    ? _selectedCurrency
                    : null,
                labelText: 'Currency',
                hintText: 'Select currency',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _currencyOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedCurrency = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _weightController,
                labelText: 'Weight',
                hintText: 'Enter weight in kg',
                isDark: isDark,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _volumeController,
                labelText: 'Volume',
                hintText: 'Enter volume in cubic meters',
                isDark: isDark,
                keyboardType: TextInputType.number,
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    if (double.tryParse(v.trim()) == null) {
                      return 'Enter a valid number';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _descriptionController,
                labelText: 'Description',
                hintText: 'Enter a product description',
                isDark: isDark,
                maxLines: 3,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    checkColor: Colors.white,
                    activeColor: isDark ? Colors.grey : primaryColor,
                    value: _isActive,
                    onChanged: (v) => setState(() => _isActive = v ?? true),
                  ),
                  const Text('Active'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    checkColor: Colors.white,
                    activeColor: isDark ? Colors.grey : primaryColor,
                    value: _canBeSold,
                    onChanged: (v) => setState(() => _canBeSold = v ?? true),
                  ),
                  const Text('Can be Sold'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Checkbox(
                    checkColor: Colors.white,
                    activeColor: isDark ? Colors.grey : primaryColor,
                    value: _canBePurchased,
                    onChanged: (v) =>
                        setState(() => _canBePurchased = v ?? true),
                  ),
                  const Text('Can be Purchased'),
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || !_isNameFilled) ? null : save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(
                      vertical: 14,
                      horizontal: 16,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    disabledBackgroundColor:
                        Theme.of(context).brightness == Brightness.dark
                        ? Colors.grey[700]!
                        : Colors.grey[400]!,
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2,
                          ),
                        )
                      : Text(
                          _isEditMode ? 'Save Changes' : 'Create Product',
                          style: TextStyle(fontSize: 16),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
