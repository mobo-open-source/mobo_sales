import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/contact.dart';
import '../../services/customer_service.dart';
import '../../services/odoo_session_manager.dart';
import '../../widgets/confetti_dialogs.dart';
import '../../utils/data_loss_warning_mixin.dart';
import 'dart:io';
import 'dart:convert';
import 'package:mobo_sales/widgets/circular_image_widget.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_text_field.dart';
import '../../widgets/custom_dropdown.dart';
import '../../widgets/custom_generic_dropdown.dart';
import '../../widgets/custom_snackbar.dart';
import '../../providers/last_opened_provider.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class EditCustomerScreen extends StatefulWidget {
  final Contact? contact;

  const EditCustomerScreen({super.key, this.contact});

  @override
  State<EditCustomerScreen> createState() => _EditCustomerScreenState();
}

class _EditCustomerScreenState extends State<EditCustomerScreen>
    with DataLossWarningMixin {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;
  String? _dropdownError;
  bool _isServerUnreachable = false;

  List<Map<String, String>> _titleOptions = [];
  List<Map<String, String>> _companyTypeOptions = [];
  List<Map<String, String>> _customerRankOptions = [];
  List<Map<String, String>> _currencyOptions = [];
  List<Map<String, String>> _languageOptions = [];
  List<Map<String, String>> _timezoneOptions = [];
  List<Map<String, dynamic>> _stateOptions = [];
  bool _dropdownsLoading = true;

  @override
  bool get hasUnsavedData {
    if (_dropdownsLoading || _hasBeenSaved) return false;

    final c = widget.contact;
    return _nameController.text.trim() != (c?.name ?? '') ||
        _emailController.text.trim() != (c?.email ?? '') ||
        _phoneController.text.trim() != (c?.phone ?? '') ||
        _mobileController.text.trim() != (c?.mobile ?? '') ||
        _websiteController.text.trim() != (c?.website ?? '') ||
        _functionController.text.trim() != (c?.function ?? '') ||
        _streetController.text.trim() != (c?.street ?? '') ||
        _street2Controller.text.trim() != (c?.street2 ?? '') ||
        _cityController.text.trim() != (c?.city ?? '') ||
        _zipController.text.trim() != (c?.zip ?? '') ||
        _companyNameController.text.trim() != (c?.companyName ?? '') ||
        _vatController.text.trim() != (c?.vat ?? '') ||
        _industryController.text.trim() != (c?.industry ?? '') ||
        _creditLimitController.text.trim() != (c?.creditLimit ?? '') ||
        _commentController.text.trim() != (c?.comment ?? '') ||
        _isCompany != (c?.isCompany ?? false) ||
        _selectedTitle != c?.title ||
        _selectedCompanyType != c?.companyType ||
        _selectedCustomerRank != c?.customerRank ||
        _selectedCurrency != c?.currency ||
        _selectedLanguage != c?.lang ||
        _selectedTimezone != c?.timezone ||
        _selectedCountryId != _originalCountryIdFromContact() ||
        _selectedStateId != c?.stateId ||
        _pickedImageFile != null;
  }

  int? _originalCountryIdFromContact() {
    final originalCountryName = widget.contact?.country;
    if (originalCountryName == null || originalCountryName.isEmpty) {
      return null;
    }
    try {
      final match = _countryOptions.firstWhere(
        (m) =>
            (m['name']?.toString().toLowerCase() ?? '') ==
            originalCountryName.toLowerCase(),
        orElse: () => {},
      );
      if (match.isNotEmpty) {
        return match['id'] as int?;
      }
    } catch (_) {}
    return null;
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
        s.contains('url incorrect') ||
        s.contains('bad gateway') ||
        s.contains('service unavailable') ||
        s.contains('gateway timeout') ||
        s.contains('http') &&
            (s.contains('502') || s.contains('503') || s.contains('504')) ||
        s.contains('handshake error') ||
        s.contains('tls') ||
        s.contains('certificate');
  }

  String _getUserFriendlyErrorMessage(dynamic error) {
    final errorString = error.toString().toLowerCase();

    if (errorString.contains('you do not have permission')) {
      final fullError = error.toString();
      if (fullError.contains(
        'You do not have permission to create customers',
      )) {
        return 'Permission Denied: You do not have permission to create customers (res.partner create). Please contact your administrator.';
      } else if (fullError.contains(
        'You do not have permission to update customers',
      )) {
        return 'Permission Denied: You do not have permission to update customers (res.partner write). Please contact your administrator.';
      } else {
        return fullError.replaceAll('Exception: ', '');
      }
    }

    if (errorString.contains('accesserror')) {
      if (errorString.contains('credit_limit')) {
        return 'You don\'t have permission to set credit limits. The customer will be created without this field.';
      } else if (errorString.contains('payment_term')) {
        return 'You don\'t have permission to set payment terms. The customer will be created without this field.';
      } else if (errorString.contains('property_')) {
        return 'You don\'t have permission to set some advanced properties. The customer will be created with basic information.';
      } else {
        return 'You don\'t have sufficient permissions to access some fields. Please contact your system administrator.';
      }
    }

    if (errorString.contains('validationerror')) {
      if (errorString.contains('email')) {
        return 'Please enter a valid email address.';
      } else if (errorString.contains('phone')) {
        return 'Please enter a valid phone number.';
      } else if (errorString.contains('vat')) {
        return 'Please enter a valid VAT number.';
      } else {
        return 'Please check your input data for errors.';
      }
    }

    if (errorString.contains('duplicate') ||
        errorString.contains('already exists')) {
      if (errorString.contains('email')) {
        return 'A customer with this email address already exists.';
      } else if (errorString.contains('vat')) {
        return 'A customer with this VAT number already exists.';
      } else {
        return 'A customer with similar information already exists.';
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

    if (_isEditMode) {
      return 'Failed to update customer. Please try again.';
    } else {
      return 'Failed to create customer. Please try again.';
    }
  }

  @override
  String get dataLossTitle =>
      _isEditMode ? 'Discard Changes?' : 'Discard Customer?';

  @override
  String get dataLossMessage => _isEditMode
      ? 'You have unsaved changes that will be lost if you leave this page. Are you sure you want to discard these changes?'
      : 'You have unsaved customer data that will be lost if you leave this page. Are you sure you want to discard this customer?';

  @override
  void onConfirmLeave() {
    if (_isEditMode) {
      final c = widget.contact;
      _nameController.text = c?.name ?? '';
      _emailController.text = c?.email ?? '';
      _phoneController.text = c?.phone ?? '';
      _mobileController.text = c?.mobile ?? '';
      _websiteController.text = c?.website ?? '';
      _functionController.text = c?.function ?? '';
      _streetController.text = c?.street ?? '';
      _street2Controller.text = c?.street2 ?? '';
      _cityController.text = c?.city ?? '';
      _zipController.text = c?.zip ?? '';
      _companyNameController.text = c?.companyName ?? '';
      _vatController.text = c?.vat ?? '';
      _industryController.text = c?.industry ?? '';
      _creditLimitController.text = c?.creditLimit ?? '';
      _commentController.text = c?.comment ?? '';
      _isCompany = c?.isCompany ?? false;
    } else {
      _nameController.clear();
      _emailController.clear();
      _phoneController.clear();
      _mobileController.clear();
      _websiteController.clear();
      _functionController.clear();
      _streetController.clear();
      _street2Controller.clear();
      _cityController.clear();
      _zipController.clear();
      _companyNameController.clear();
      _vatController.clear();
      _industryController.clear();
      _creditLimitController.clear();
      _commentController.clear();
      _isCompany = false;
    }

    _selectedTitle = null;
    _selectedCompanyType = null;
    _selectedCustomerRank = null;
    _selectedCurrency = null;
    _selectedLanguage = null;
    _selectedTimezone = null;
    _selectedCountryId = null;
    _selectedStateId = null;
    _pickedImageFile = null;
    _pickedImageBase64 = null;
  }

  late TextEditingController _nameController;
  late TextEditingController _emailController;
  late TextEditingController _phoneController;
  late TextEditingController _mobileController;
  late TextEditingController _websiteController;
  late TextEditingController _functionController;
  late TextEditingController _streetController;
  late TextEditingController _street2Controller;
  late TextEditingController _cityController;
  late TextEditingController _stateController;
  late TextEditingController _zipController;
  late TextEditingController _companyNameController;
  late TextEditingController _vatController;
  late TextEditingController _industryController;
  late TextEditingController _creditLimitController;
  late TextEditingController _commentController;

  String? _selectedTitle;
  String? _selectedCompanyType;
  String? _selectedCustomerRank;
  String? _selectedCurrency;
  String? _selectedLanguage;
  String? _selectedTimezone;
  int? _selectedStateId;
  bool _isCompany = false;

  int? _selectedCountryId;
  List<Map<String, dynamic>> _countryOptions = [];
  bool _isLoadingCountries = false;
  bool _isLoadingStates = false;
  bool _isEditMode = false;
  bool _hasBeenSaved = false;

  File? _pickedImageFile;
  String? _pickedImageBase64;
  final ImagePicker _picker = ImagePicker();

  bool _isOcrLoading = false;
  File? _businessCardImageFile;
  String? _otherDetails;

  bool get _isNameFilled => _nameController.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    _isEditMode = widget.contact != null;
    if (_isEditMode && widget.contact != null) {
      _trackCustomerAccess();
    }
    final c = widget.contact;
    String clean(String? v) => (v == null || v == 'false') ? '' : v;
    _nameController = TextEditingController(text: clean(c?.name));
    _emailController = TextEditingController(text: clean(c?.email));
    _phoneController = TextEditingController(text: clean(c?.phone));
    _mobileController = TextEditingController(text: clean(c?.mobile));
    _websiteController = TextEditingController(text: clean(c?.website));
    _functionController = TextEditingController(text: clean(c?.function));
    _streetController = TextEditingController(text: clean(c?.street));
    _street2Controller = TextEditingController(text: clean(c?.street2));
    _cityController = TextEditingController(text: clean(c?.city));
    _stateController = TextEditingController(text: clean(c?.state));
    _zipController = TextEditingController(text: clean(c?.zip));
    _companyNameController = TextEditingController(text: clean(c?.companyName));
    _vatController = TextEditingController(text: clean(c?.vat));
    _industryController = TextEditingController(text: clean(c?.industry));
    _creditLimitController = TextEditingController(text: clean(c?.creditLimit));
    _commentController = TextEditingController(text: clean(c?.comment));
    _selectedTitle = _titleOptions.any((m) => m['value'] == c?.title)
        ? c?.title
        : null;
    _selectedCompanyType =
        _companyTypeOptions.any((m) => m['value'] == c?.companyType)
        ? c?.companyType
        : null;
    _selectedCustomerRank =
        _customerRankOptions.any((m) => m['value'] == c?.customerRank)
        ? c?.customerRank
        : null;
    _selectedCurrency = _currencyOptions.any((m) => m['value'] == c?.currency)
        ? c?.currency
        : null;
    _selectedLanguage = _languageOptions.any((m) => m['value'] == c?.lang)
        ? c?.lang
        : null;
    _selectedTimezone = _timezoneOptions.any((m) => m['value'] == c?.timezone)
        ? c?.timezone
        : null;
    _selectedStateId = _stateOptions.any((m) => m['label'] == c?.state)
        ? _stateOptions.firstWhere((m) => m['label'] == c?.state)['value']
        : null;
    _isCompany = c?.isCompany ?? false;
    _selectedCountryId = null;
    _selectedStateId = null;
    _fetchDropdowns();
    _fetchCountries();
    _nameController.addListener(() {
      setState(() {});
    });

    _pickedImageFile = null;
    _pickedImageBase64 = null;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _websiteController.dispose();
    _functionController.dispose();
    _streetController.dispose();
    _street2Controller.dispose();
    _cityController.dispose();
    _stateController.dispose();
    _zipController.dispose();
    _companyNameController.dispose();
    _vatController.dispose();
    _industryController.dispose();
    _creditLimitController.dispose();
    _commentController.dispose();
    super.dispose();
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
                      HugeIcons.strokeRoundedImageCrop,
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

  Future<void> _save() async {
    final formState = _formKey.currentState;
    if (formState == null) {
      return;
    }
    if (!formState.validate()) {
      _scrollToFirstError();
      return;
    }
    setState(() {
      _isLoading = true;
    });
    try {
      final data = <String, dynamic>{};

      void addField(String key, String? value) {
        if (value != null &&
            value.trim().isNotEmpty &&
            value.trim().toLowerCase() != 'false') {
          data[key] = value.trim();
        }
      }

      void addFieldSafe(String key, String? value) async {
        if (value != null &&
            value.trim().isNotEmpty &&
            value.trim().toLowerCase() != 'false') {
          data[key] = value.trim();
        }
      }

      addField('name', _nameController.text);
      addField('email', _emailController.text);
      addField('phone', _phoneController.text);
      addField('mobile', _mobileController.text);
      addField('website', _websiteController.text);
      addField('function', _functionController.text);
      addField('street', _streetController.text);
      addField('street2', _street2Controller.text);
      addField('city', _cityController.text);
      if (_selectedStateId != null) {
        data['state_id'] = _selectedStateId;
      }
      addField('zip', _zipController.text);
      if (_selectedCountryId != null) data['country_id'] = _selectedCountryId;
      addField('company_name', _companyNameController.text);
      addField('vat', _vatController.text);

      if (_industryController.text.trim().isNotEmpty) {
        data['industry'] = _industryController.text.trim();
      }

      if (_creditLimitController.text.trim().isNotEmpty) {
        try {
          addField('credit_limit', _creditLimitController.text);
        } catch (e) {}
      }
      addField('comment', _commentController.text);
      data['is_company'] = _isCompany;
      if (_selectedTitle != null && _selectedTitle!.isNotEmpty) {
        data['title'] = _selectedTitle;
      }
      if (_selectedCompanyType != null && _selectedCompanyType!.isNotEmpty) {
        data['company_type'] = _selectedCompanyType;
      }

      if (_selectedCustomerRank != null && _selectedCustomerRank!.isNotEmpty) {
        data['customer_rank'] = _selectedCustomerRank;
      } else if (!_isEditMode) {
        data['customer_rank'] = 1;
      }

      if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
        data['currency_id'] = _selectedCurrency;
      }
      if (_selectedLanguage != null && _selectedLanguage!.isNotEmpty) {
        data['lang'] = _selectedLanguage;
      }
      if (_selectedTimezone != null && _selectedTimezone!.isNotEmpty) {
        data['tz'] = _selectedTimezone;
      }

      if (_pickedImageBase64 != null) {
        data['image_1920'] = _pickedImageBase64;
      }

      data['active'] = widget.contact?.isActive ?? true;

      if (widget.contact?.paymentTermId != null) {
        data['property_payment_term_id'] = widget.contact!.paymentTermId;
      }

      if (widget.contact?.salesperson != null &&
          widget.contact!.salesperson!.isNotEmpty) {
        data['user_id'] = widget.contact!.salesperson;
      }
      bool success = false;
      Contact? resultContact;
      if (_isEditMode) {
        success = await CustomerService.instance.updateCustomer(
          widget.contact!.id,
          data,
        );
        if (success) {
          try {
            resultContact = await CustomerService.instance.fetchCustomerDetails(
              widget.contact!.id,
            );
          } catch (e) {
            resultContact = widget.contact;
          }
        }
      } else {
        resultContact = await CustomerService.instance.createCustomer(data);
        success = resultContact != null;
      }
      if (success && mounted) {
        if (!_isEditMode) {
          final customerName =
              resultContact?.name ?? _nameController.text.trim();
          await showCustomerCreatedConfettiDialog(context, customerName);

          if (mounted) {
            Navigator.pop(context, resultContact);
          }
        } else {
          setState(() {
            _hasBeenSaved = true;
          });
          if (mounted && Navigator.canPop(context)) {
            Navigator.pop(context, resultContact);
          } else {}
        }
      } else if (!success) {
        setState(() {});
      }
    } catch (e) {
      final errorString = e.toString().toLowerCase();
      if (errorString.contains('invalid field') ||
          errorString.contains('keyerror')) {
        String? invalidField;
        if (errorString.contains("'industry'")) {
          invalidField = 'industry';
        }

        if (invalidField != null) {
          try {
            setState(() {
              _isLoading = true;
            });

            final data = <String, dynamic>{};
            void addField(String key, String? value) {
              if (value != null &&
                  value.trim().isNotEmpty &&
                  value.trim().toLowerCase() != 'false') {
                data[key] = value.trim();
              }
            }

            addField('name', _nameController.text);
            addField('email', _emailController.text);
            addField('phone', _phoneController.text);
            addField('mobile', _mobileController.text);
            addField('website', _websiteController.text);
            addField('function', _functionController.text);
            addField('street', _streetController.text);
            addField('street2', _street2Controller.text);
            addField('city', _cityController.text);
            if (_selectedStateId != null) data['state_id'] = _selectedStateId;
            addField('zip', _zipController.text);
            if (_selectedCountryId != null) {
              data['country_id'] = _selectedCountryId;
            }
            addField('company_name', _companyNameController.text);
            addField('vat', _vatController.text);

            if (_creditLimitController.text.trim().isNotEmpty) {
              try {
                addField('credit_limit', _creditLimitController.text);
              } catch (e) {}
            }
            addField('comment', _commentController.text);
            data['is_company'] = _isCompany;
            if (_selectedTitle != null && _selectedTitle!.isNotEmpty) {
              data['title'] = _selectedTitle;
            }
            if (_selectedCompanyType != null &&
                _selectedCompanyType!.isNotEmpty) {
              data['company_type'] = _selectedCompanyType;
            }

            if (_selectedCustomerRank != null &&
                _selectedCustomerRank!.isNotEmpty) {
              data['customer_rank'] = _selectedCustomerRank;
            } else if (!_isEditMode) {
              data['customer_rank'] = 1;
            }

            if (_selectedCurrency != null && _selectedCurrency!.isNotEmpty) {
              data['currency_id'] = _selectedCurrency;
            }
            if (_selectedLanguage != null && _selectedLanguage!.isNotEmpty) {
              data['lang'] = _selectedLanguage;
            }
            if (_selectedTimezone != null && _selectedTimezone!.isNotEmpty) {
              data['tz'] = _selectedTimezone;
            }

            if (_pickedImageBase64 != null) {
              data['image_1920'] = _pickedImageBase64;
            }
            data['active'] = widget.contact?.isActive ?? true;
            if (widget.contact?.paymentTermId != null) {
              data['property_payment_term_id'] = widget.contact!.paymentTermId;
            }
            if (widget.contact?.salesperson != null &&
                widget.contact!.salesperson!.isNotEmpty) {
              data['user_id'] = widget.contact!.salesperson;
            }

            bool success = false;
            Contact? resultContact;
            if (_isEditMode) {
              success = await CustomerService.instance.updateCustomer(
                widget.contact!.id,
                data,
              );
              if (success) {
                try {
                  resultContact = await CustomerService.instance
                      .fetchCustomerDetails(widget.contact!.id);
                } catch (e) {
                  resultContact = widget.contact;
                }
              }
            } else {
              resultContact = await CustomerService.instance.createCustomer(
                data,
              );
              success = resultContact != null;
            }

            if (success && mounted) {
              if (!_isEditMode) {
                final customerName =
                    resultContact?.name ?? _nameController.text.trim();
                await showCustomerCreatedConfettiDialog(context, customerName);
                if (mounted) {
                  Navigator.pop(context, resultContact);
                }
              } else {
                setState(() {
                  _hasBeenSaved = true;
                });
                if (mounted && Navigator.canPop(context)) {
                  Navigator.pop(context, resultContact);
                }
              }
              return;
            }
          } finally {
            if (mounted) {
              setState(() {
                _isLoading = false;
              });
            }
          }
        }
      }

      String userFriendlyMessage = _getUserFriendlyErrorMessage(e);

      bool isPostCreationPermissionError =
          !_isEditMode &&
          e.toString().toLowerCase().contains('accesserror') &&
          (e.toString().contains('credit_limit') ||
              e.toString().contains('property_') ||
              e.toString().contains('payment_term'));

      if (mounted) {
        if (isPostCreationPermissionError) {
          try {
            CustomSnackbar.showSuccess(
              context,
              'Customer created successfully! Some advanced fields may not be accessible due to permissions.',
            );
          } catch (e) {}

          Future.delayed(Duration(milliseconds: 1500), () {
            if (mounted && Navigator.canPop(context)) {
              Navigator.pop(context, true);
            }
          });
        } else {
          try {
            CustomSnackbar.showError(context, userFriendlyMessage);
          } catch (e) {}
          setState(() {});
        }
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
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
            final data = await CustomerService.instance.fetchTitleOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Titles');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await CustomerService.instance.fetchCompanyTypeOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Company Types');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await CustomerService.instance
                .fetchCustomerRankOptions(forceRefresh: forceRefresh);

            return data;
          } catch (e) {
            failedDropdowns.add('Customer Ranks');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await CustomerService.instance.fetchCurrencyOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Currencies');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await CustomerService.instance.fetchLanguageOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Languages');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await CustomerService.instance.fetchTimezoneOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('Timezones');
            if (_isServerUnreachableError(e)) serverErrorCount++;
            return null;
          }
        })(),
        (() async {
          try {
            final data = await CustomerService.instance.fetchStateOptions(
              forceRefresh: forceRefresh,
            );

            return data;
          } catch (e) {
            failedDropdowns.add('States');
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
            _titleOptions = [];
            _companyTypeOptions = [];
            _customerRankOptions = [];
            _currencyOptions = [];
            _languageOptions = [];
            _timezoneOptions = [];
            _dropdownsLoading = false;
            _isServerUnreachable = true;
            _dropdownError =
                'The Odoo server or database could not be reached. Please check your server settings or try again later.';
          });
        }
        return;
      }

      setState(() {
        _titleOptions = results[0] ?? [];
        _companyTypeOptions = results[1] ?? [];
        _customerRankOptions = results[2] ?? [];
        _currencyOptions = results[3] ?? [];
        _languageOptions = results[4] ?? [];
        _timezoneOptions = results[5] ?? [];

        final c = widget.contact;
        _selectedTitle =
            _titleOptions.any((m) => m['value'] == (c?.title ?? ''))
            ? c?.title
            : null;
        _selectedCompanyType =
            _companyTypeOptions.any((m) => m['value'] == (c?.companyType ?? ''))
            ? c?.companyType
            : null;
        _selectedCustomerRank =
            _customerRankOptions.any(
              (m) => m['value'] == (c?.customerRank ?? ''),
            )
            ? c?.customerRank
            : null;
        _selectedCurrency =
            _currencyOptions.any((m) => m['value'] == (c?.currency ?? ''))
            ? c?.currency
            : null;
        _selectedLanguage =
            _languageOptions.any((m) => m['value'] == (c?.lang ?? ''))
            ? c?.lang
            : null;
        _selectedTimezone =
            _timezoneOptions.any((m) => m['value'] == (c?.timezone ?? ''))
            ? c?.timezone
            : null;

        final allStates = results[6] ?? [];
        _selectedStateId = allStates.any((m) => m['label'] == (c?.state ?? ''))
            ? int.tryParse(
                allStates.firstWhere((m) => m['label'] == c?.state)['value']!,
              )
            : null;

        if (!silentRevalidate) {
          _dropdownsLoading = false;
        }

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
      if (!silentRevalidate) {
        setState(() {
          if (_isServerUnreachableError(e)) {
            _dropdownError =
                'The Odoo server or database could not be reached. Please check your server settings or try again later.';
            _isServerUnreachable = true;
          } else {
            _dropdownError = 'Failed to load dropdown options: ${e.toString()}';
          }
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
      CustomerService.instance.clearDropdownCaches();
      await _fetchDropdowns(forceRefresh: true);
      await _fetchCountries();
      if (!mounted) return;
      CustomSnackbar.showSuccess(context, 'Options updated');
    } catch (e) {}
  }

  Future<void> _fetchCountries() async {
    setState(() {
      _isLoadingCountries = true;
    });
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');
      final result = await client.callKw({
        'model': 'res.country',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name', 'code'],
          'order': 'name ASC',
        },
      });
      if (result is List) {
        setState(() {
          _countryOptions = List<Map<String, dynamic>>.from(result);

          if (widget.contact?.country != null &&
              widget.contact!.country!.isNotEmpty) {
            final match = _countryOptions.firstWhere(
              (c) =>
                  c['name'].toString().trim().toLowerCase() ==
                  widget.contact!.country!.trim().toLowerCase(),
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              _selectedCountryId = match['id'];
            } else {
              _selectedCountryId = null;
            }
          } else {
            _selectedCountryId = null;
          }

          _isServerUnreachable = false;
        });

        if (_selectedCountryId != null) {
          await _fetchStates(_selectedCountryId!);
        }
      }
    } catch (e) {
      if (_isServerUnreachableError(e)) {
        setState(() {
          _isServerUnreachable = true;
          _dropdownError =
              'The Odoo server or database could not be reached. Please check your server settings or try again later.';
        });
      }
    } finally {
      setState(() {
        _isLoadingCountries = false;
      });
    }
  }

  Future<void> _fetchStates(int countryId) async {
    if (!mounted) return;
    setState(() {
      _isLoadingStates = true;
      _stateOptions = [];
      _selectedStateId = null;
    });
    try {
      final client = await OdooSessionManager.getClient();
      if (client == null) throw Exception('No active Odoo session');
      final result = await client.callKw({
        'model': 'res.country.state',
        'method': 'search_read',
        'args': [
          [
            ['country_id', '=', countryId],
          ],
        ],
        'kwargs': {
          'fields': ['id', 'name', 'code'],
          'order': 'name ASC',
        },
      });
      if (result is List) {
        if (!mounted) return;
        setState(() {
          _stateOptions = List<Map<String, dynamic>>.from(
            result,
          ).where((s) => s['id'] != null).toList();

          if (widget.contact?.stateId != null) {
            final match = _stateOptions.firstWhere(
              (s) => s['id'] == widget.contact!.stateId,
              orElse: () => {},
            );
            if (match.isNotEmpty) {
              _selectedStateId = match['id'];
            } else {
              _selectedStateId = null;
            }
          } else {
            _selectedStateId = null;
          }
        });
      }
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoadingStates = false;
      });
    }
  }

  void _scrollToFirstError() {
    setState(() {});
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
        color: isDark ? Colors.grey[800] : Colors.white,
        borderRadius: BorderRadius.circular(12),
      ),
    );
  }

  Widget _shimmerDropdown(bool isDark) {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.white,
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
        color: isDark ? Colors.grey[800] : Colors.white,
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

  void _trackCustomerAccess() {
    try {
      final lastOpenedProvider = Provider.of<LastOpenedProvider>(
        context,
        listen: false,
      );
      final contact = widget.contact!;
      final customerId = contact.id.toString();
      final customerName = contact.displayName;
      final customerType = contact.isCompany == true ? 'Company' : 'Contact';

      lastOpenedProvider.trackCustomerAccess(
        customerId: customerId,
        customerName: customerName,
        customerType: customerType,
        customerData: contact.toJson(),
      );
    } catch (e) {}
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
                _isEditMode ? 'Edit Customer' : 'Create Customer',
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
                _isEditMode ? 'Edit Customer' : 'Create Customer',
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

        return popChild;
      },
    );
  }

  Widget _buildContent(BuildContext context, bool isDark, Color primaryColor) {
    if (_dropdownError != null && !_isServerUnreachable) {
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditMode ? 'Edit Customer' : 'Create Customer',
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
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, color: Colors.red, size: 48),
                const SizedBox(height: 16),
                Text(
                  'Failed to load dropdown options.',
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32.0),
                  child: Text(
                    _dropdownError!,
                    style: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: _fetchDropdowns,
                  icon: Icon(Icons.refresh, size: 20),
                  label: Text('Retry', style: TextStyle(fontSize: 16)),
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
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final validCountryIds = _countryOptions.map((c) => c['id']).toSet();
    final safeSelectedCountryId = (validCountryIds.contains(_selectedCountryId))
        ? _selectedCountryId
        : null;
    final validStateIds = _stateOptions
        .where((s) => s['id'] != null)
        .map((s) => s['id'] as int)
        .toSet();
    final safeSelectedStateId = (validStateIds.contains(_selectedStateId))
        ? _selectedStateId
        : -1;

    if (_isLoadingCountries || _countryOptions.isEmpty) {
      final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
      final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
      return Scaffold(
        appBar: AppBar(
          title: Text(
            _isEditMode ? 'Edit Customer' : 'Create Customer',
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
        body: Container(
          color: isDark ? Colors.grey[900] : Colors.white,
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Shimmer.fromColors(
              baseColor: shimmerBase,
              highlightColor: shimmerHighlight,
              child: SingleChildScrollView(
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
                              color: isDark ? Colors.grey[800] : Colors.white,
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
                                color: isDark ? Colors.grey[800] : Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),

                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),
                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),
                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),

                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),
                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),
                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),

                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),

                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),

                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),
                    _shimmerDropdown(isDark),
                    const SizedBox(height: 12),

                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),
                    _shimmerField(isDark),
                    const SizedBox(height: 12),

                    _shimmerField(isDark, height: 80),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: isDark ? Colors.grey[800] : Colors.white,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          height: 16,
                          width: 120,
                          color: isDark ? Colors.grey[800] : Colors.white,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Container(
                      height: 48,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.grey[800] : Colors.white,
                        borderRadius: BorderRadius.circular(12),
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

    Widget photoWidget;
    if (_pickedImageFile != null) {
      photoWidget = CircleAvatar(
        radius: 48,
        backgroundColor: isDark
            ? Colors.grey.shade200
            : Theme.of(context).primaryColor.withOpacity(.1),
        backgroundImage: FileImage(_pickedImageFile!),
      );
    } else if (widget.contact?.imageUrl != null &&
        widget.contact!.imageUrl!.isNotEmpty) {
      final imageUrl = widget.contact!.imageUrl!;
      if (imageUrl.startsWith('http')) {
        photoWidget = CircleAvatar(
          radius: 48,
          backgroundColor: isDark
              ? Colors.grey.shade200
              : Theme.of(context).primaryColor.withOpacity(.1),
          backgroundImage: NetworkImage(imageUrl),
        );
      } else {
        photoWidget = CircularImageWidget(
          base64Image: imageUrl,
          radius: 48,
          fallbackText: widget.contact?.name ?? '?',
          backgroundColor: isDark
              ? Colors.grey.shade200
              : Theme.of(context).primaryColor.withOpacity(.1),
          textColor: isDark ? Colors.grey.shade800 : primaryColor,
        );
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
          _isEditMode ? 'Edit Customer' : 'Create Customer',
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
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      body: Container(
        color: isDark ? Colors.grey[900] : Colors.white,
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 16),
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
                labelText: 'Name *',
                hintText: 'Enter full name',
                isDark: isDark,
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'Name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _emailController,
                labelText: 'Email',
                hintText: 'Enter email address',
                isDark: isDark,
                keyboardType: TextInputType.emailAddress,
                validator: (v) {
                  if (v != null && v.trim().isNotEmpty) {
                    final emailRegex = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+');
                    if (!emailRegex.hasMatch(v.trim())) {
                      return 'Enter a valid email address';
                    }
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _phoneController,
                labelText: 'Phone',
                hintText: 'Enter phone number',
                isDark: isDark,
                keyboardType: TextInputType.phone,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _mobileController,
                labelText: 'Mobile',
                hintText: 'Enter mobile number',
                isDark: isDark,
                keyboardType: TextInputType.phone,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _websiteController,
                labelText: 'Website',
                hintText: 'Enter website URL',
                isDark: isDark,
                keyboardType: TextInputType.url,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _functionController,
                labelText: 'Job Position',
                hintText: 'Enter job title',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Checkbox(
                    value: _isCompany,
                    onChanged: (v) => setState(() => _isCompany = v ?? false),
                  ),
                  const Text('Is Company'),
                ],
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _companyNameController,
                labelText: 'Company Name',
                hintText: 'Enter company name',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _vatController,
                labelText: 'VAT Number',
                hintText: 'Enter VAT/Tax ID',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _industryController,
                labelText: 'Industry',
                hintText: 'Enter industry type',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _creditLimitController,
                labelText: 'Credit Limit',
                hintText: 'Enter credit limit amount',
                isDark: isDark,
                keyboardType: TextInputType.number,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _streetController,
                labelText: 'Street',
                hintText: 'Enter street address',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _street2Controller,
                labelText: 'Street 2',
                hintText: 'Enter additional address info',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _cityController,
                labelText: 'City',
                hintText: 'Enter city name',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),

              CustomGenericDropdownField<int>(
                value: safeSelectedCountryId,
                labelText: 'Country',
                hintText: 'Choose your country',
                isDark: isDark,
                items: _isLoadingCountries
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : [
                        DropdownMenuItem<int>(
                          value: null,
                          child: Text(
                            'Select Country',
                            style: TextStyle(fontStyle: FontStyle.italic),
                          ),
                        ),
                        ..._countryOptions
                            .where(
                              (country) =>
                                  country['id'] != null &&
                                  country['name'] != null,
                            )
                            .map(
                              (country) => DropdownMenuItem<int>(
                                value: country['id'],
                                child: Text(country['name']),
                              ),
                            ),
                      ],
                onChanged: _isLoadingCountries
                    ? null
                    : (v) {
                        setState(() {
                          _selectedCountryId = v;
                          _selectedStateId = null;
                          _stateOptions = [];
                        });
                        if (v != null) _fetchStates(v);
                      },
                validator: (v) => null,
              ),
              const SizedBox(height: 12),

              if (_isLoadingStates && _selectedCountryId != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Shimmer.fromColors(
                    baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
                    highlightColor: isDark
                        ? Colors.grey[700]!
                        : Colors.grey[100]!,
                    child: Container(
                      height: 44,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                )
              else
                CustomGenericDropdownField<int>(
                  value: safeSelectedStateId == -1 ? null : safeSelectedStateId,
                  labelText: 'State',
                  hintText: _selectedCountryId == null
                      ? 'Select a country first'
                      : 'Choose your state/province',
                  isDark: isDark,
                  items: _isLoadingStates
                      ? [DropdownMenuItem(value: -1, child: Text('Loading...'))]
                      : [
                          DropdownMenuItem<int>(
                            value: -1,
                            child: Text(
                              'Select State',
                              style: TextStyle(fontStyle: FontStyle.italic),
                            ),
                          ),
                          ..._stateOptions
                              .where(
                                (state) =>
                                    state['id'] != null &&
                                    state['name'] != null,
                              )
                              .map(
                                (state) => DropdownMenuItem<int>(
                                  value: state['id'] as int,
                                  child: Text(state['name']),
                                ),
                              ),
                        ],
                  onChanged: (_selectedCountryId == null || _isLoadingStates)
                      ? null
                      : (v) => setState(
                          () => _selectedStateId = v == -1 ? null : v,
                        ),
                  validator: (v) => null,
                ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _zipController,
                labelText: 'ZIP Code',
                hintText: 'Enter postal code',
                isDark: isDark,
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value: _titleOptions.any((m) => m['value'] == _selectedTitle)
                    ? _selectedTitle
                    : null,
                labelText: 'Title',
                hintText: 'Select title',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _titleOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedTitle = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value:
                    _companyTypeOptions.any(
                      (m) => m['value'] == _selectedCompanyType,
                    )
                    ? _selectedCompanyType
                    : null,
                labelText: 'Company Type',
                hintText: 'Select company type',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _companyTypeOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedCompanyType = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value:
                    _currencyOptions.any((m) => m['value'] == _selectedCurrency)
                    ? _selectedCurrency
                    : null,
                labelText: 'Currency',
                hintText: 'Select preferred currency',
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
              CustomDropdownField(
                value:
                    _languageOptions.any((m) => m['value'] == _selectedLanguage)
                    ? _selectedLanguage
                    : null,
                labelText: 'Language',
                hintText: 'Select preferred language',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _languageOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedLanguage = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomDropdownField(
                value:
                    _timezoneOptions.any((m) => m['value'] == _selectedTimezone)
                    ? _selectedTimezone
                    : null,
                labelText: 'Timezone',
                hintText: 'Select timezone',
                isDark: isDark,
                items: _dropdownsLoading
                    ? [DropdownMenuItem(value: null, child: Text('Loading...'))]
                    : _timezoneOptions
                          .map(
                            (m) => DropdownMenuItem(
                              value: m['value'],
                              child: Text(m['label']!),
                            ),
                          )
                          .toList(),
                onChanged: _dropdownsLoading
                    ? null
                    : (v) => setState(() => _selectedTimezone = v),
                validator: (v) => null,
              ),
              const SizedBox(height: 12),
              CustomTextField(
                controller: _commentController,
                labelText: 'Notes',
                isDark: isDark,
                maxLines: 2,
                validator: (v) => null,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: (_isLoading || !_isNameFilled)
                      ? null
                      : () {
                          _save();
                        },
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
                      ? Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isEditMode
                                  ? 'Saving Changes'
                                  : 'Creating Customer',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey.shade100,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            LoadingAnimationWidget.staggeredDotsWave(
                              color: Colors.white,
                              size: 24,
                            ),
                          ],
                        )
                      : Text(
                          _isEditMode ? 'Save Changes' : 'Create Customer',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey.shade100,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: !_isEditMode
          ? Padding(
              padding: EdgeInsets.only(bottom: 42),
              child: FloatingActionButton.extended(
                onPressed: _isLoading || _isOcrLoading
                    ? null
                    : _showBusinessCardScanner,
                backgroundColor: _isOcrLoading
                    ? Colors.grey
                    : Theme.of(context).primaryColor,
                foregroundColor: Colors.white,
                icon: _isOcrLoading
                    ? SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white,
                          ),
                        ),
                      )
                    : Icon(HugeIcons.strokeRoundedScanImage),
                label: Text(_isOcrLoading ? 'Scanning...' : 'Scan Card'),
              ),
            )
          : null,
    );
  }

  void _showBusinessCardScanner() {
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
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Scan Business Card',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ),
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickBusinessCardImage(ImageSource.camera);
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
                    const Text(
                      'Take Photo of Business Card',
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
            InkWell(
              onTap: () {
                Navigator.pop(context);
                _pickBusinessCardImage(ImageSource.gallery);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    Icon(
                      HugeIcons.strokeRoundedImageCrop,
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
            const SizedBox(height: 16),
          ],
        );
      },
    );
  }

  Future<void> _pickBusinessCardImage(ImageSource source) async {
    try {
      if (mounted) {
        setState(() {
          _isOcrLoading = true;
        });
      }

      final pickedFile = await _picker.pickImage(
        source: source,
        imageQuality: 90,
        maxWidth: 1920,
        maxHeight: 1080,
      );

      if (pickedFile == null) {
        if (mounted) {
          setState(() {
            _isOcrLoading = false;
          });
        }
        return;
      }

      try {
        final directory = await getApplicationDocumentsDirectory();
        final fileName =
            'business_card_${DateTime.now().millisecondsSinceEpoch}.jpg';
        final filePath = path.join(directory.path, fileName);
        final savedFile = await File(pickedFile.path).copy(filePath);

        if (mounted) {
          setState(() {
            _businessCardImageFile = savedFile;
          });
        }

        await _extractTextFromBusinessCard(savedFile);
      } catch (e) {
        if (mounted) {
          setState(() {
            _isOcrLoading = false;
          });
        }
        if (mounted) {
          CustomSnackbar.showError(
            context,
            'Failed to save image. Please try again.',
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOcrLoading = false;
        });
      }
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to access camera/gallery. Please check permissions.',
        );
      }
    }
  }

  Future<void> _extractTextFromBusinessCard(File imageFile) async {
    TextRecognizer? textRecognizer;
    try {
      if (!await imageFile.exists()) {
        throw Exception('Image file does not exist');
      }

      final fileSize = await imageFile.length();

      if (fileSize == 0) {
        throw Exception('Image file is empty');
      }

      final inputImage = InputImage.fromFile(imageFile);
      textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);

      final recognizedText = await textRecognizer.processImage(inputImage);
      final fullText = recognizedText.text.trim();

      if (fullText.isEmpty) {
        if (mounted) {
          setState(() {
            _isOcrLoading = false;
          });
          CustomSnackbar.showWarning(
            context,
            'No text detected in the image. Please try with a clearer photo.',
          );
        }
        await textRecognizer.close();
        return;
      }

      final textBlocks = recognizedText.blocks;
      final lines = fullText.split('\n').map((e) => e.trim()).toList();

      final nameRegex = RegExp(
        r'^[A-Za-z\s\-\.]{2,}(\s[A-Za-z\s\-\.]+){1,}$',
        multiLine: true,
      );
      final phoneRegex = RegExp(
        r'(\+?\d{1,4}[\s-]?)?(\(?\d{2,5}\)?[\s-]?)?[\d\s\-\.]{6,15}\b',
        multiLine: true,
      );
      final emailRegex = RegExp(
        r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
        caseSensitive: false,
      );
      final websiteRegex = RegExp(
        r'\b(?:https?://|www\.)[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b',
        caseSensitive: false,
      );
      final positionRegex = RegExp(
        r'\b(CEO|CTO|COO|CFO|Founder|Co-Founder|CoFounder|President|Vice President|VP|Managing Director|Director|Head|Team Lead|Manager|Supervisor|Engineer|Developer|Software Engineer|Consultant|Executive|Designer|UI/UX Designer|Product Manager|Project Manager|Marketing Manager|Sales Executive|Business Analyst|HR|Human Resources|Accountant|Intern|Trainee|Associate|Administrator|Creative Director|Data Scientist|Machine Learning Engineer|Support Engineer|Tech Lead|QA Engineer|Tester|Operations Manager|Architect|Analyst|Scrum Master|Agent|Representative|Specialist|Coordinator|Assistant|Officer)\b',
        caseSensitive: false,
      );
      final companyRegex = RegExp(
        r'\b[A-Za-z0-9\s\-\.]{5,}\s*(?:Technologies|Technology|Solutions|Systems|Software|Corporation|Corp\.?|Inc\.?|LLC|LLP|Limited|Ltd\.?|Pvt\.? Ltd\.?|Private Limited|Group|Associates|Consultancy|Studio|Agency|Labs|Networks|Partners|Holdings|Enterprise|Company|SAS|PLC|GmbH|BV|Co\.?|Real Estate|Realty|Properties|Services)?\b',
        caseSensitive: false,
      );
      final addressRegex = RegExp(
        r'\b\d+\s+[A-Za-z0-9\s,.-]+(?:Street|St\.?|Avenue|Ave\.?|Road|Rd\.?|Boulevard|Blvd\.?|Lane|Ln\.?|Drive|Dr\.?|Court|Ct\.?|Place|Pl\.?|Way|Circle|Cir\.?)[,\s]*[A-Za-z\s]*[,\s]*[A-Z]{2}\s*\d{5}(?:-\d{4})?',
        caseSensitive: false,
      );
      final cityStateZipRegex = RegExp(
        r'\b[A-Za-z\s]+,\s*[A-Z]{2}\s*\d{5}(?:-\d{4})?\b',
        caseSensitive: false,
      );

      String? name;
      String? phone;
      String? email;
      String? company;
      String? position;
      String? website;
      String? address;
      String? city;
      String? zipCode;

      name = nameRegex.firstMatch(fullText)?.group(0);
      phone = phoneRegex
          .firstMatch(fullText)
          ?.group(0)
          ?.replaceAll(RegExp(r'\s+'), '');
      email = emailRegex.firstMatch(fullText)?.group(0);
      website = websiteRegex.firstMatch(fullText)?.group(0);
      position = lines.firstWhere(
        (line) => positionRegex.hasMatch(line),
        orElse: () => '',
      );
      company = companyRegex.firstMatch(fullText)?.group(0);

      final addressMatch = addressRegex.firstMatch(fullText);
      if (addressMatch != null) {
        address = addressMatch.group(0);

        final cityStateZipMatch = cityStateZipRegex.firstMatch(address!);
        if (cityStateZipMatch != null) {
          final cityStateZip = cityStateZipMatch.group(0)!;
          final parts = cityStateZip.split(',');
          if (parts.length >= 2) {
            city = parts[0].trim();
            final stateZip = parts[1].trim().split(RegExp(r'\s+'));
            if (stateZip.length >= 2) {
              zipCode = stateZip.last;
            }
          }
        }
      } else {
        final cityStateZipMatch = cityStateZipRegex.firstMatch(fullText);
        if (cityStateZipMatch != null) {
          final cityStateZip = cityStateZipMatch.group(0)!;
          final parts = cityStateZip.split(',');
          if (parts.length >= 2) {
            city = parts[0].trim();
            final stateZip = parts[1].trim().split(RegExp(r'\s+'));
            if (stateZip.length >= 2) {
              zipCode = stateZip.last;
            }
          }
        }
      }

      for (var block in textBlocks) {
        final blockText = block.text.trim();
        if (name == null &&
            blockText.split(' ').length >= 2 &&
            !phoneRegex.hasMatch(blockText) &&
            !emailRegex.hasMatch(blockText) &&
            !websiteRegex.hasMatch(blockText) &&
            !positionRegex.hasMatch(blockText)) {
          name = blockText;
        }
        if (phone == null && phoneRegex.hasMatch(blockText)) {
          phone = phoneRegex
              .firstMatch(blockText)
              ?.group(0)
              ?.replaceAll(RegExp(r'\s+'), '');
        }
        if (email == null && emailRegex.hasMatch(blockText)) {
          email = blockText;
        }
        if (website == null && websiteRegex.hasMatch(blockText)) {
          website = blockText;
        }
        if (company == null &&
            companyRegex.hasMatch(blockText) &&
            !phoneRegex.hasMatch(blockText) &&
            !emailRegex.hasMatch(blockText) &&
            !websiteRegex.hasMatch(blockText) &&
            !positionRegex.hasMatch(blockText) &&
            blockText.split(' ').length >= 2) {
          company = blockText;
        }
      }

      if (company != null) {
        if (name != null) {
          company = company.replaceAll(
            RegExp(RegExp.escape(name), caseSensitive: false),
            '',
          );
        }
        if (phone != null) {
          company = company.replaceAll(
            RegExp(RegExp.escape(phone), caseSensitive: false),
            '',
          );
        }
        if (email != null) {
          company = company.replaceAll(
            RegExp(RegExp.escape(email), caseSensitive: false),
            '',
          );
        }
        if (website != null) {
          company = company.replaceAll(
            RegExp(RegExp.escape(website), caseSensitive: false),
            '',
          );
        }

        company = company.replaceAll(
          RegExp(RegExp.escape(position ?? ''), caseSensitive: false),
          '',
        );
        company = company
            .replaceAll(phoneRegex, '')
            .replaceAll(emailRegex, '')
            .replaceAll(websiteRegex, '')
            .replaceAll(positionRegex, '');
        company = company.replaceAll(RegExp(r'\s+'), ' ').trim();

        if (company.isEmpty ||
            (name != null && company.toLowerCase() == name.toLowerCase()) ||
            (company.toLowerCase() == position.toLowerCase())) {
          company = null;
        }
      }

      name = name?.replaceAll(RegExp(r'\s+'), ' ').trim();
      position = position.trim();

      setState(() {
        if (name != null && name.isNotEmpty) _nameController.text = name;
        if (phone != null && phone.isNotEmpty) {
          _phoneController.text = phone;
          _mobileController.text = phone;
        }
        if (email != null && email.isNotEmpty) _emailController.text = email;
        if (position != null && position.isNotEmpty) {
          _functionController.text = position;
        }
        if (website != null && website.isNotEmpty) {
          _websiteController.text = website;
        }
        if (company != null && company.isNotEmpty) {
          _companyNameController.text = company;
        }

        if (address != null && address.isNotEmpty) {
          String streetAddress = address;
          if (city != null) {
            streetAddress = streetAddress
                .replaceAll(',$city', '')
                .replaceAll(city, '');
          }
          if (zipCode != null) {
            streetAddress = streetAddress.replaceAll(zipCode, '');
          }
          streetAddress = streetAddress
              .replaceAll(RegExp(r',\s*[A-Z]{2}\s*'), '')
              .trim();
          if (streetAddress.endsWith(',')) {
            streetAddress = streetAddress.substring(
              0,
              streetAddress.length - 1,
            );
          }

          _streetController.text = streetAddress.trim();
        }
        if (city != null && city.isNotEmpty) _cityController.text = city;
        if (zipCode != null && zipCode.isNotEmpty) {
          _zipController.text = zipCode;
        }

        _otherDetails = fullText;
        _isOcrLoading = false;
      });

      final extractedFieldsCount = [
        name,
        phone,
        email,
        company,
        position,
        website,
        address,
        city,
        zipCode,
      ].where((field) => field != null && field.isNotEmpty).length;

      if (mounted) {
        if (extractedFieldsCount == 0) {
          CustomSnackbar.showWarning(
            context,
            'No contact information found. Please try with a clearer image.',
          );
        } else if (name == null || (phone == null && email == null)) {
          CustomSnackbar.showWarning(
            context,
            'Partial data extracted ($extractedFieldsCount fields). Please complete the missing information.',
          );
        } else {
          CustomSnackbar.showSuccess(
            context,
            'Business card scanned successfully! ($extractedFieldsCount fields filled)',
          );
        }
      }

      await textRecognizer.close();
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOcrLoading = false;
        });
      }

      if (mounted) {
        String userFriendlyMessage;
        if (e.toString().contains('MlKitException')) {
          userFriendlyMessage =
              'ML Kit service unavailable. Please try again later.';
        } else if (e.toString().contains('Permission')) {
          userFriendlyMessage =
              'Camera permission required. Please enable in settings.';
        } else if (e.toString().contains('file') ||
            e.toString().contains('path')) {
          userFriendlyMessage =
              'Image file error. Please try taking another photo.';
        } else {
          userFriendlyMessage =
              'Text recognition failed. Please try with a clearer image.';
        }

        CustomSnackbar.showError(context, userFriendlyMessage);
      }

      try {
        await textRecognizer?.close();
      } catch (closeError) {}
    }
  }
}
