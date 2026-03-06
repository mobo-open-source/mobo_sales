import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/screens/others/settings_screen.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:shimmer/shimmer.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/widgets/custom_text_field.dart';
import 'package:mobo_sales/widgets/custom_dropdown.dart';
import 'package:mobo_sales/widgets/data_loss_warning_dialog.dart';
import 'package:mobo_sales/screens/others/profile_details_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import 'package:mobo_sales/services/connectivity_service.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/services/biometric_context_service.dart';
import 'package:mobo_sales/main.dart';
import 'package:mobo_sales/home_scaffold.dart';
import 'package:mobo_sales/screens/login/credentials_screen.dart';
import 'package:mobo_sales/screens/login/add_account_screen.dart';
import 'package:mobo_sales/widgets/circular_image_widget.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:mobo_sales/widgets/connection_status_widget.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;

  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  bool _isLoadingCountries = false;
  bool _isLoadingStates = false;
  File? _pickedImageFile;
  String? _pickedImageBase64;
  final ImagePicker _picker = ImagePicker();
  static const String _defaultCacheKeyUser = 'user_profile';
  static const String _defaultCacheKeyUserWriteDate = 'user_profile_write_date';

  Future<String> _getCacheKey() async {
    final session = await OdooSessionManager.getCurrentSession();
    if (session == null || session.userId == null) return _defaultCacheKeyUser;
    final cleanDb = session.database.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'user_profile_${cleanDb}_${session.userId}';
  }

  Future<String> _getWriteDateKey() async {
    final session = await OdooSessionManager.getCurrentSession();
    if (session == null || session.userId == null) {
      return _defaultCacheKeyUserWriteDate;
    }
    final cleanDb = session.database.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return 'user_profile_write_date_${cleanDb}_${session.userId}';
  }

  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  SessionService? _sessionService;
  bool _hasInternet = true;
  bool _isEditMode = false;
  bool _isSaving = false;
  bool _isShowingLoadingDialog = false;
  final int _cacheUpdateKey = 0;
  Uint8List? _avatarBytesCache;
  String? _avatarBase64Cache;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _mobileController = TextEditingController();
  final TextEditingController _websiteController = TextEditingController();
  final TextEditingController _functionController = TextEditingController();

  int? _partnerId;
  int? _relatedCompanyId;
  String? _relatedCompanyName;

  Future<void> _loadCachedUser() async {
    try {
      final cacheKey = await _getCacheKey();
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(cacheKey);

      String? dataToUse = cached;
      if (dataToUse == null || dataToUse.isEmpty) {
        dataToUse = prefs.getString(_defaultCacheKeyUser);
      }

      if (dataToUse != null && dataToUse.isNotEmpty && mounted) {
        final data = jsonDecode(dataToUse) as Map<String, dynamic>;
        setState(() {
          _userData = data;
          final img = data['image_1920'];

          _avatarBase64Cache = (img is String && img.isNotEmpty) ? img : null;
          _isLoading = false;
        });
        _updateControllers();
      }
    } catch (e) {}
  }

  void _startConnectivityListener() {
    _connectivitySub = Connectivity().onConnectivityChanged.listen((
      results,
    ) async {
      final hasNet = await _checkInternet();
      if (!mounted) return;
      setState(() => _hasInternet = hasNet);
    });

    _checkInternet().then((hasNet) {
      if (!mounted) return;
      setState(() => _hasInternet = hasNet);
    });
  }

  Future<bool> _checkInternet() async {
    try {
      final result = await InternetAddress.lookup('one.one.one.one');
      if (result.isNotEmpty && result.first.rawAddress.isNotEmpty) {
        return true;
      }
    } catch (_) {}
    return false;
  }

  String _normalizeForEdit(dynamic value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : '';
    final s = value.toString().trim();
    if (s.isEmpty) return '';
    if (s.toLowerCase() == 'false') return '';
    return s;
  }

  void _updateControllers() {
    if (_userData != null) {
      _nameController.text = _normalizeForEdit(_userData!['name']);
      _emailController.text = _normalizeForEdit(_userData!['email']);
      _phoneController.text = _normalizeForEdit(_userData!['phone']);
      _mobileController.text = _normalizeForEdit(_userData!['mobile']);
      _websiteController.text = _normalizeForEdit(_userData!['website']);
      _functionController.text = _normalizeForEdit(_userData!['function']);
    }
  }

  void _cancelEdit() {
    _updateControllers();
    setState(() => _isEditMode = false);
  }

  @override
  void initState() {
    super.initState();

    _sessionService = context.read<SessionService>();
    _sessionService?.addListener(_onSessionChanged);

    _loadCachedUser();
    _fetchUserProfile();
    _loadCountries();
    _startConnectivityListener();
  }

  void _onSessionChanged() {
    if (!mounted) return;

    if (_sessionService != null && _sessionService!.isRefreshing) {}
  }

  @override
  void dispose() {
    _sessionService?.removeListener(_onSessionChanged);
    _connectivitySub?.cancel();
    _nameController.dispose();
    _emailController.dispose();
    _phoneController.dispose();
    _mobileController.dispose();
    _websiteController.dispose();
    _functionController.dispose();
    super.dispose();
  }

  Future<void> _loadCountries() async {
    setState(() => _isLoadingCountries = true);
    try {
      final countries = await _fetchCountries();
      if (mounted) {
        setState(() {
          _countries = countries;
          _isLoadingCountries = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingCountries = false);
        _showErrorSnackBar('Failed to load countries: $e');
      }
    }
  }

  void _showLoadingDialog(BuildContext context, String message) {
    if (_isShowingLoadingDialog || !mounted) return;
    _isShowingLoadingDialog = true;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: isDark ? const Color(0xFF212121) : Colors.white,
        elevation: 8,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : const Color(0xFF1E88E5).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: LoadingAnimationWidget.fourRotatingDots(
                  color: isDark ? Colors.white : const Color(0xFF1E88E5),
                  size: 32,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                message,
                style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.grey[900],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait while we process your request',
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                  color: isDark ? Colors.grey[400] : Colors.grey[600],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;

    CustomSnackbar.show(
      context: context,
      title: 'Error',
      message: message,
      type: SnackbarType.error,
    );
  }

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;

    CustomSnackbar.show(
      context: context,
      title: 'Success',
      message: message,
      type: SnackbarType.success,
    );
  }

  void _showNonEditableFieldSnackBar(String fieldName) {
    if (!mounted) return;

    CustomSnackbar.show(
      context: context,
      title: 'Field Not Editable',
      message: '$fieldName cannot be modified from this screen',
      type: SnackbarType.info,
    );
  }

  Future<void> _pickImageFromSource(ImageSource source) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        imageQuality: 80,
        maxWidth: 600,
      );
      if (picked == null || !mounted) return;

      setState(() => _pickedImageFile = File(picked.path));
      final bytes = await picked.readAsBytes();
      if (!mounted) return;

      setState(() => _pickedImageBase64 = base64Encode(bytes));

      await _saveImage();
      if (mounted) {
        _showSuccessSnackBar('Image updated successfully');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to update image: $e');
      }
    }
  }

  void _showImageSourceActionSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      builder: (context) => Column(
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedCamera02,
                    size: 24,
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Row(
                children: [
                  Icon(
                    HugeIcons.strokeRoundedImageCrop,
                    size: 24,
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
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _fetchCountries() async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) return [];

    try {
      final result = await client.callKw({
        'model': 'res.country',
        'method': 'search_read',
        'args': [],
        'kwargs': {
          'fields': ['id', 'name', 'code'],
          'order': 'name ASC',
        },
      });
      return result is List ? result.cast<Map<String, dynamic>>() : [];
    } catch (e) {
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> _fetchStates(int countryId) async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final client = await sessionService.client;
    if (client == null) return [];

    try {
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
      return result is List ? result.cast<Map<String, dynamic>>() : [];
    } catch (e) {
      rethrow;
    }
  }

  void _showEditAddressDialog() {
    if (_userData == null) return;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final theme = Theme.of(context);

    final streetController = TextEditingController(
      text: _normalizeForEdit(_userData!['street']),
    );
    final street2Controller = TextEditingController(
      text: _normalizeForEdit(_userData!['street2']),
    );
    final cityController = TextEditingController(
      text: _normalizeForEdit(_userData!['city']),
    );
    final zipController = TextEditingController(
      text: _normalizeForEdit(_userData!['zip']),
    );

    int? selectedCountryId =
        _userData!['country_id'] is List &&
            _userData!['country_id'].isNotEmpty &&
            _userData!['country_id'][0] != null
        ? _userData!['country_id'][0] as int
        : null;
    int? selectedStateId =
        _userData!['state_id'] is List &&
            _userData!['state_id'].isNotEmpty &&
            _userData!['state_id'][0] != null
        ? _userData!['state_id'][0] as int
        : null;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          if (selectedCountryId != null &&
              _states.isEmpty &&
              !_isLoadingStates) {
            _isLoadingStates = true;
            _fetchStates(selectedCountryId!).then((states) {
              if (context.mounted) {
                setDialogState(() {
                  _states = states;
                  _isLoadingStates = false;
                });
              }
            });
          }

          return AlertDialog(
            backgroundColor: isDark ? Colors.grey[850] : Colors.white,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Text(
              'Edit Address',
              style: TextStyle(
                color: isDark ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w600,
              ),
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 400,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildAddressTextField(
                      controller: streetController,
                      label: 'Street Address',
                      hint: 'Enter street address',
                      isDark: isDark,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildAddressTextField(
                      controller: street2Controller,
                      label: 'Street Address 2',
                      hint: 'Apartment, suite, etc. (optional)',
                      isDark: isDark,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildAddressTextField(
                      controller: cityController,
                      label: 'City',
                      hint: 'Enter city',
                      isDark: isDark,
                      theme: theme,
                    ),
                    const SizedBox(height: 16),
                    _buildAddressTextField(
                      controller: zipController,
                      label: 'ZIP Code',
                      hint: 'Enter ZIP code',
                      isDark: isDark,
                      theme: theme,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: 16),
                    _buildCountryDropdown(
                      selectedCountryId: selectedCountryId,
                      countries: _countries,
                      isLoading: _isLoadingCountries,
                      isDark: isDark,
                      theme: theme,
                      onChanged: (countryId) {
                        setDialogState(() {
                          selectedCountryId = countryId;
                          selectedStateId = null;
                          _states = [];
                        });
                        if (countryId != null) {
                          _isLoadingStates = true;
                          _fetchStates(countryId).then((states) {
                            if (context.mounted) {
                              setDialogState(() {
                                _states = states;
                                _isLoadingStates = false;
                              });
                            }
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 16),
                    _buildStateDropdown(
                      selectedStateId: selectedStateId,
                      states: _states,
                      isLoading: _isLoadingStates,
                      isDark: isDark,
                      theme: theme,
                      enabled: selectedCountryId != null,
                      onChanged: (stateId) {
                        setDialogState(() => selectedStateId = stateId);
                      },
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  streetController.dispose();
                  street2Controller.dispose();
                  cityController.dispose();
                  zipController.dispose();
                },
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.grey[400] : Colors.grey[700],
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
              ElevatedButton(
                onPressed: () async {
                  if (streetController.text.trim().isEmpty) {
                    _showErrorSnackBar('Street address is required');
                    return;
                  }
                  final addressData = {
                    'street': streetController.text.trim(),
                    'street2': street2Controller.text.trim().isEmpty
                        ? false
                        : street2Controller.text.trim(),
                    'city': cityController.text.trim().isEmpty
                        ? false
                        : cityController.text.trim(),
                    'zip': zipController.text.trim().isEmpty
                        ? false
                        : zipController.text.trim(),
                    'country_id': selectedCountryId ?? false,
                    'state_id': selectedStateId ?? false,
                  };

                  final navigator = Navigator.of(context);
                  navigator.pop();

                  streetController.dispose();
                  street2Controller.dispose();
                  cityController.dispose();
                  zipController.dispose();

                  _showLoadingDialog(context, 'Updating Address');
                  try {
                    await _updateAddressFields(addressData);
                    if (mounted) {
                      _isShowingLoadingDialog = false;
                      navigator.pop();
                      _showSuccessSnackBar('Address updated successfully');
                    }
                  } catch (e) {
                    if (mounted) {
                      _isShowingLoadingDialog = false;
                      navigator.pop();
                      _showErrorSnackBar('Failed to update address: $e');
                    }
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: theme.primaryColor,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 24,
                    vertical: 12,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                child: const Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.w500),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildCountryDropdown({
    required int? selectedCountryId,
    required List<Map<String, dynamic>> countries,
    required bool isLoading,
    required bool isDark,
    required ThemeData theme,
    required Function(int?) onChanged,
  }) {
    final validCountryIds = countries.map((c) => c['id']).toSet();
    final safeSelectedCountryId =
        selectedCountryId != null && validCountryIds.contains(selectedCountryId)
        ? selectedCountryId
        : null;

    final stringItems = isLoading
        ? [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Loading...'),
            ),
          ]
        : [
            const DropdownMenuItem<String>(
              value: null,
              child: Text(
                'Select Country',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
            ...countries.map(
              (country) => DropdownMenuItem<String>(
                value: country['id'].toString(),
                child: Text(country['name']),
              ),
            ),
          ];

    return CustomDropdownField(
      value: safeSelectedCountryId?.toString(),
      labelText: 'Country',
      hintText: 'Select Country',
      isDark: isDark,
      items: stringItems,
      onChanged: isLoading
          ? null
          : (value) => onChanged(value != null ? int.tryParse(value) : null),
      validator: (value) => value == null ? 'Please select a country' : null,
    );
  }

  Widget _buildStateDropdown({
    required int? selectedStateId,
    required List<Map<String, dynamic>> states,
    required bool isLoading,
    required bool isDark,
    required ThemeData theme,
    required bool enabled,
    required Function(int?) onChanged,
  }) {
    final validStateIds = states.map((s) => s['id']).toSet();
    final safeSelectedStateId =
        selectedStateId != null && validStateIds.contains(selectedStateId)
        ? selectedStateId
        : null;

    final stringItems = !enabled
        ? [
            const DropdownMenuItem<String>(
              value: null,
              child: Text(
                'Select country first',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
          ]
        : isLoading
        ? [
            const DropdownMenuItem<String>(
              value: null,
              child: Text('Loading...'),
            ),
          ]
        : [
            const DropdownMenuItem<String>(
              value: null,
              child: Text(
                'Select State/Province',
                style: TextStyle(fontStyle: FontStyle.italic),
              ),
            ),
            ...states.map(
              (state) => DropdownMenuItem<String>(
                value: state['id'].toString(),
                child: Text(state['name']),
              ),
            ),
          ];

    return CustomDropdownField(
      value: safeSelectedStateId?.toString(),
      labelText: 'State/Province',
      hintText: enabled
          ? (isLoading ? 'Loading...' : 'Select State/Province')
          : 'Select country first',
      isDark: isDark,
      items: stringItems,
      onChanged: (!enabled || isLoading)
          ? null
          : (value) => onChanged(value != null ? int.tryParse(value) : null),
      validator: (value) => null,
    );
  }

  Widget _buildAddressTextField({
    required TextEditingController controller,
    required String label,
    required String hint,
    required bool isDark,
    required ThemeData theme,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return CustomTextField(
      controller: controller,
      labelText: label,
      hintText: hint,
      isDark: isDark,
      keyboardType: keyboardType,
      validator: label == 'Street Address'
          ? (value) => value == null || value.trim().isEmpty
                ? 'This field is required'
                : null
          : (value) => null,
    );
  }

  Future<void> _updateAddressFields(Map<String, dynamic> addressData) async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final session = sessionService.currentSession;
    if (session == null || _userData == null) {
      throw Exception('No active session or user data');
    }

    final client = await sessionService.client;
    if (client == null) {
      throw Exception('Client not initialized');
    }

    final uid = client.sessionId?.userId;
    if (uid == null) {
      throw Exception('User ID not found');
    }

    try {
      await client.callKw({
        'model': 'res.users',
        'method': 'write',
        'args': [
          [uid],
          addressData,
        ],
        'kwargs': {},
      });
      await _fetchUserProfile();
    } catch (e) {
      rethrow;
    }
  }

  Future<void> _loadRelatedCompany() async {
    if (_partnerId == null) {
      setState(() {
        _relatedCompanyId = null;
        _relatedCompanyName = null;
      });
      return;
    }
    try {
      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final client = await sessionService.client;
      if (client == null) return;
      final res = await client.callKw({
        'model': 'res.partner',
        'method': 'read',
        'args': [_partnerId],
        'kwargs': {
          'fields': ['parent_id'],
        },
      });
      if (!mounted) return;
      if (res is List && res.isNotEmpty) {
        final row = res.first as Map<String, dynamic>;
        if (row['parent_id'] is List &&
            (row['parent_id'] as List).length >= 2 &&
            row['parent_id'][0] != null) {
          setState(() {
            _relatedCompanyId = row['parent_id'][0] as int;
            _relatedCompanyName = row['parent_id'][1]?.toString();
          });
        } else {
          setState(() {
            _relatedCompanyId = null;
            _relatedCompanyName = null;
          });
        }
      }
    } catch (e) {}
  }

  Future<void> _fetchUserProfile({bool forceRefresh = false}) async {
    if (!mounted) return;
    setState(() => _isLoading = _userData == null);
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final session = sessionService.currentSession;

    if (session == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final client = await sessionService.client;
    if (client == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    final uid = client.sessionId?.userId;
    if (uid == null) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
      return;
    }

    try {
      String? serverWriteDate;
      try {
        final writeDateRes = await client.callKw({
          'model': 'res.users',
          'method': 'search_read',
          'args': [
            [
              ['id', '=', uid],
            ],
            ['write_date'],
          ],
          'kwargs': {'limit': 1},
        });
        if (writeDateRes is List && writeDateRes.isNotEmpty) {
          final row = writeDateRes.first as Map<String, dynamic>;
          serverWriteDate = row['write_date']?.toString();
        }
      } catch (_) {}

      String? cachedWriteDate;
      try {
        final prefs = await SharedPreferences.getInstance();
        final writeKey = await _getWriteDateKey();
        cachedWriteDate = prefs.getString(writeKey);
      } catch (_) {}

      if (!forceRefresh &&
          serverWriteDate != null &&
          cachedWriteDate != null &&
          serverWriteDate == cachedWriteDate &&
          _userData != null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final result = await client.callKw({
        'model': 'res.users',
        'method': 'read',
        'args': [uid],
        'kwargs': {
          'fields': [
            'name',
            'login',
            'email',
            'image_1920',
            'phone',
            'website',
            'function',
            'company_id',
            'partner_id',
            'street',
            'street2',
            'city',
            'state_id',
            'zip',
            'country_id',
            'active',
            'write_date',
          ],
        },
      });

      if (result is List && result.isNotEmpty && mounted) {
        final data = result[0] as Map<String, dynamic>;
        final imgField = data['image_1920'];
        final avatar = (imgField is String && imgField.isNotEmpty)
            ? imgField
            : null;
        setState(() {
          _userData = data;
          _avatarBase64Cache = avatar;
          if (data['partner_id'] is List &&
              (data['partner_id'] as List).isNotEmpty &&
              data['partner_id'][0] != null) {
            _partnerId = data['partner_id'][0] as int;
          } else {
            _partnerId = null;
          }
          _isLoading = false;
        });
        _updateControllers();

        await _loadRelatedCompany();

        try {
          final cacheKey = await _getCacheKey();
          final writeKey = await _getWriteDateKey();
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString(cacheKey, jsonEncode(data));
          final wd = (data['write_date'] ?? serverWriteDate)?.toString();
          if (wd != null) {
            await prefs.setString(writeKey, wd);
          }

          await prefs.setString(_defaultCacheKeyUser, jsonEncode(data));
        } catch (e) {}
      } else {
        if (mounted) {
          setState(() {
            _userData = _userData;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        _showErrorSnackBar('Failed to load profile: $e');
      }
    }
  }

  Future<void> _updateProfileField(String field, dynamic value) async {
    final sessionService = Provider.of<SessionService>(context, listen: false);
    final session = sessionService.currentSession;
    if (session == null || _userData == null) {
      throw Exception('No active session or user data');
    }

    final client = await sessionService.client;
    if (client == null) {
      throw Exception('Client not initialized');
    }

    final uid = client.sessionId?.userId;
    if (uid == null) {
      throw Exception('User ID not found');
    }

    NavigatorState? navigator;
    if (field != 'image_1920') {
      navigator = Navigator.of(context);
      _showLoadingDialog(context, 'Updating Profile');
    }

    try {
      await client.callKw({
        'model': 'res.users',
        'method': 'write',
        'args': [
          [uid],
          {field: value},
        ],
        'kwargs': {},
      });

      if (field == 'image_1920' && mounted) {
        setState(() {
          _pickedImageFile = null;
          _pickedImageBase64 = null;
        });
      }

      await _fetchUserProfile();

      if (field == 'image_1920' && mounted) {
        final settingsProvider = Provider.of<SettingsProvider>(
          context,
          listen: false,
        );
        await settingsProvider.fetchUserProfile();
      }

      if (field != 'image_1920') {
        _showSuccessSnackBar('Profile updated successfully');
      }
    } catch (e) {
      if (field != 'image_1920') {
        _showErrorSnackBar('Failed to update profile: $e');
      }
      rethrow;
    } finally {
      if (field != 'image_1920' && mounted && navigator != null) {
        _isShowingLoadingDialog = false;
        navigator.pop();
      }
    }
  }

  Future<void> _saveAllChanges() async {
    if (_isSaving || !mounted) return;

    if (_nameController.text.trim().isEmpty) {
      if (mounted) {
        _showErrorSnackBar('Full Name is required');
      }
      return;
    }

    if (_phoneController.text.trim().isNotEmpty) {
      final cleanPhone = _phoneController.text.replaceAll(
        RegExp(r'[\s\-\(\)\+]'),
        '',
      );
      if (!RegExp(r'^[0-9]+$').hasMatch(cleanPhone)) {
        if (mounted) {
          _showErrorSnackBar('Phone number can only contain numbers');
        }
        return;
      }
    }

    if (_mobileController.text.trim().isNotEmpty) {
      final cleanMobile = _mobileController.text.replaceAll(
        RegExp(r'[\s\-\(\)\+]'),
        '',
      );
      if (!RegExp(r'^[0-9]+$').hasMatch(cleanMobile)) {
        if (mounted) {
          _showErrorSnackBar('Mobile number can only contain numbers');
        }
        return;
      }
    }

    if (!mounted) return;
    setState(() => _isSaving = true);

    final navigator = Navigator.of(context);
    _showLoadingDialog(context, 'Saving Changes');

    try {
      if (!mounted) return;

      final sessionService = Provider.of<SessionService>(
        context,
        listen: false,
      );
      final session = sessionService.currentSession;
      if (session == null || _userData == null) {
        throw Exception('No active session or user data');
      }

      final client = await sessionService.client;
      if (client == null) {
        throw Exception('Client not initialized');
      }

      final uid = client.sessionId?.userId;
      if (uid == null) {
        throw Exception('User ID not found');
      }

      final updateData = <String, dynamic>{};

      if (_nameController.text.trim() !=
          _normalizeForEdit(_userData!['name'])) {
        updateData['name'] = _nameController.text.trim();
      }

      if (_phoneController.text.trim() !=
          _normalizeForEdit(_userData!['phone'])) {
        updateData['phone'] = _phoneController.text.trim().isEmpty
            ? false
            : _phoneController.text.trim();
      }

      if (_mobileController.text.trim() !=
          _normalizeForEdit(_userData!['mobile'])) {
        updateData['mobile'] = _mobileController.text.trim().isEmpty
            ? false
            : _mobileController.text.trim();
      }

      if (_websiteController.text.trim() !=
          _normalizeForEdit(_userData!['website'])) {
        updateData['website'] = _websiteController.text.trim().isEmpty
            ? false
            : _websiteController.text.trim();
      }

      if (_functionController.text.trim() !=
          _normalizeForEdit(_userData!['function'])) {
        updateData['function'] = _functionController.text.trim().isEmpty
            ? false
            : _functionController.text.trim();
      }

      if (updateData.isNotEmpty) {
        await client.callKw({
          'model': 'res.users',
          'method': 'write',
          'args': [
            [uid],
            updateData,
          ],
          'kwargs': {},
        });

        if (!mounted) return;
        await _fetchUserProfile();

        if (!mounted) return;
        _showSuccessSnackBar('Profile updated successfully');
      } else {
        if (!mounted) return;
        _showSuccessSnackBar('No changes to save');
      }

      if (!mounted) return;
      setState(() => _isEditMode = false);
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to save changes: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        _isShowingLoadingDialog = false;
        navigator.pop();
      }
    }
  }

  Future<void> _saveImage() async {
    if (_pickedImageBase64 == null || !mounted) return;

    final navigator = Navigator.of(context);
    _showLoadingDialog(context, 'Saving Image');
    try {
      await _updateProfileField('image_1920', _pickedImageBase64);
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar('Failed to update image: $e');
      }
    } finally {
      if (mounted) {
        _isShowingLoadingDialog = false;
        navigator.pop();
      }
    }
  }

  bool _hasUnsavedChanges() {
    if (_userData == null) return false;

    return _nameController.text.trim() !=
            _normalizeForEdit(_userData!['name']) ||
        _emailController.text.trim() !=
            _normalizeForEdit(_userData!['email']) ||
        _phoneController.text.trim() !=
            _normalizeForEdit(_userData!['phone']) ||
        _mobileController.text.trim() !=
            _normalizeForEdit(_userData!['mobile']) ||
        _websiteController.text.trim() !=
            _normalizeForEdit(_userData!['website']) ||
        _functionController.text.trim() !=
            _normalizeForEdit(_userData!['function']);
  }

  Future<bool> _showUnsavedChangesDialog() async {
    final result = await DataLossWarningDialog.show(
      context: context,
      title: 'Discard Changes?',
      message:
          'You have unsaved changes that will be lost if you leave this page. Are you sure you want to discard these changes?',
      confirmText: 'Discard',
      cancelText: 'Keep Editing',
    );
    return result ?? false;
  }

  Future<void> _performLogout(BuildContext context) async {
    BuildContext? dialogContext;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        dialogContext = ctx;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return WillPopScope(
          onWillPop: () async => false,
          child: Dialog(
            backgroundColor: isDark ? Colors.grey[900] : Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            elevation: 8,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.primary.withOpacity(0.08),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(16),
                    child: LoadingAnimationWidget.fourRotatingDots(
                      color: isDark
                          ? Colors.white
                          : Theme.of(context).colorScheme.primary,
                      size: 50,
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Logging out...',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Please wait while we process your request.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      color: isDark ? Colors.grey[300] : Colors.grey[700],
                    ),
                  ),
                  const SizedBox(height: 6),

                  Consumer2<ConnectivityService, SessionService>(
                    builder: (_, connectivity, session, __) {
                      final offline =
                          !connectivity.isConnected ||
                          session.isServerUnreachable;
                      final icon = offline
                          ? Icons.wifi_off_rounded
                          : Icons.wifi_rounded;
                      final color = offline
                          ? (isDark ? Colors.orange[300] : Colors.orange[700])
                          : (isDark ? Colors.grey[400] : Colors.grey[600]);
                      final label = offline
                          ? 'Offline: logging out locally'
                          : 'Online';
                      return Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 16, color: color),
                          const SizedBox(width: 6),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: color,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );

    await Future.delayed(const Duration(milliseconds: 900));
    await SessionService.instance.logout();

    if (dialogContext != null && dialogContext!.mounted) {
      Navigator.of(dialogContext!).pop();
    }

    if (context.mounted) {
      Navigator.pushAndRemoveUntil(
        context,

        MaterialPageRoute(builder: (context) => const AppEntryPoint()),
        (route) => false,
      );
      CustomSnackbar.showSuccess(context, 'Logged out successfully');
    }
  }

  Future<void> _showLogoutDialog(BuildContext context) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Confirm Logout',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to log out? Your session will be ended.',
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
                child: OutlinedButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    side: BorderSide(
                      color: isDark ? Colors.grey[700]! : AppTheme.primaryColor,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(
                      fontWeight: FontWeight.w500,
                      color: AppTheme.primaryColor,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).primaryColor,
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
                    'Log Out',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await _performLogout(context);
    }
  }

  Widget _tileDivider(bool isDark) =>
      Divider(height: 1, color: isDark ? Colors.grey[800] : Colors.grey[200]);

  Widget _quickActionTile(
    BuildContext context, {
    required IconData icon,
    required String title,
    String subtitle = '',
    VoidCallback? onTap,
    bool destructive = false,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final Color? subtitleColor = isDark ? Colors.grey[400] : Colors.grey[600];
    final Color titleColor = destructive
        ? const Color(0xFFD32F2F)
        : (isDark ? Colors.white : Colors.black87);
    final Color iconColor = destructive
        ? const Color(0xFFD32F2F)
        : (isDark ? Colors.grey[400]! : Colors.grey[600]!);

    return ListTile(
      leading: Icon(icon, color: iconColor),
      title: Text(
        title,
        style: TextStyle(
          color: titleColor,
          fontWeight: destructive ? FontWeight.w600 : FontWeight.w500,
        ),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(subtitle, style: TextStyle(color: subtitleColor))
          : null,
      trailing: trailing ?? const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildQuickActionsSection(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[900] : Colors.white;

    final List<Widget> tiles = [
      _quickActionTile(
        context,
        icon: Icons.settings_outlined,
        title: 'Settings',
        subtitle: 'App preferences and sync options',
        onTap: () async {
          try {
            final route = MaterialPageRoute(
              builder: (context) => const SettingsScreen(),
            );
            await Navigator.push(context, route);
          } catch (_) {}
        },
      ),
      Consumer<SessionService>(
        builder: (context, sessionService, child) {
          final otherAccounts = sessionService.storedAccounts
              .where((account) => !_isCurrentAccount(account, sessionService))
              .toList();

          final accountCount = otherAccounts.length;
          final isDark = Theme.of(context).brightness == Brightness.dark;

          return ExpansionTile(
            shape: const Border(),
            collapsedShape: const Border(),
            leading: Icon(
              HugeIcons.strokeRoundedUserSwitch,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
            title: const Text(
              'Switch Accounts',
              style: TextStyle(fontWeight: FontWeight.w500),
            ),
            subtitle: Text(
              accountCount > 0
                  ? '$accountCount other account${accountCount != 1 ? 's' : ''} available'
                  : 'Add multiple accounts to switch quickly',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            children: [
              if (accountCount == 0)
                _buildEmptyAccountState(context, sessionService)
              else
                ...otherAccounts.map(
                  (account) => _buildAccountTileInProfile(
                    context,
                    account,
                    sessionService,
                  ),
                ),
              _buildAddAccountButtonInProfile(context),
            ],
          );
        },
      ),
      _quickActionTile(
        context,
        icon: Icons.logout_outlined,
        title: 'Logout',
        subtitle: 'Sign out from this device',
        destructive: true,
        trailing: const SizedBox.shrink(),
        onTap: () => _showLogoutDialog(context),
      ),
    ];

    final children = <Widget>[];
    for (int i = 0; i < tiles.length; i++) {
      children.add(tiles[i]);
      if (i != tiles.length - 1) {
        children.add(_tileDivider(isDark));
      }
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isDark
              ? Colors.white.withOpacity(0.08)
              : Colors.black.withOpacity(0.06),
        ),
        boxShadow: [
          if (!isDark)
            BoxShadow(
              blurRadius: 16,
              spreadRadius: 2,
              offset: const Offset(0, 6),
              color: Colors.black.withOpacity(0.06),
            ),
        ],
      ),
      child: Column(children: children),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<SettingsProvider>(context);
    final bool isEditingDisabled = settings.offlineMode || !_hasInternet;
    final shimmerBase = isDark ? Colors.grey[800]! : Colors.grey[300]!;
    final shimmerHighlight = isDark ? Colors.grey[700]! : Colors.grey[100]!;
    final placeholderColor = isDark ? Colors.grey[900]! : Colors.white;
    final cardColor = isDark ? Colors.grey[900] : Colors.white;

    Widget photoWidget = CircularImageWidget(
      base64Image: _avatarBase64Cache,
      radius: 34,
      fallbackText: _userData != null && _userData!['name'] != null
          ? _userData!['name'].toString()
          : 'User',
      backgroundColor: AppTheme.primaryColor,
      textColor: Colors.white,
    );
    Future<void> showRelatedCompanyPicker() async {
      if (_partnerId == null) {
        _showErrorSnackBar('Partner record not found for this user');
        return;
      }
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      final TextEditingController searchCtrl = TextEditingController();
      List<Map<String, dynamic>> companies = [];
      bool loading = true;

      Future<void> loadCompanies([String q = '']) async {
        try {
          final sessionService = Provider.of<SessionService>(
            context,
            listen: false,
          );
          final client = await sessionService.client;
          if (client == null) return;
          final domain = [
            ['is_company', '=', true],
          ];
          if (q.trim().isNotEmpty) {
            domain.add(['name', 'ilike', q.trim()]);
          }
          final res = await client.callKw({
            'model': 'res.partner',
            'method': 'search_read',
            'args': [domain],
            'kwargs': {
              'fields': ['id', 'name'],
              'limit': 50,
              'order': 'name asc',
            },
          });
          companies = (res as List).cast<Map<String, dynamic>>();
        } catch (e) {
          companies = [];
        } finally {
          loading = false;
        }
      }

      await loadCompanies();
      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (ctx) {
          return StatefulBuilder(
            builder: (ctx, setDlg) {
              return AlertDialog(
                backgroundColor: isDark ? Colors.grey[850] : Colors.white,
                surfaceTintColor: Colors.transparent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                title: Text(
                  'Select Related Company',
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                content: SizedBox(
                  width: 420,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: searchCtrl,
                        decoration: InputDecoration(
                          prefixIcon: const Icon(Icons.search),
                          hintText: 'Search companies...',
                          isDense: true,
                        ),
                        onChanged: (val) async {
                          setDlg(() => loading = true);
                          await loadCompanies(val);
                          if (ctx.mounted) setDlg(() {});
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 320,
                        width: double.infinity,
                        child: loading
                            ? Center(
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    theme.primaryColor,
                                  ),
                                ),
                              )
                            : companies.isEmpty
                            ? Center(
                                child: Text(
                                  'No companies found',
                                  style: TextStyle(
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                ),
                              )
                            : ListView.separated(
                                itemCount: companies.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: .01,
                                  thickness: .01,
                                  color: isDark
                                      ? Colors.grey[800]
                                      : Colors.grey[200],
                                ),
                                itemBuilder: (ctx, i) {
                                  final c = companies[i];
                                  final selected = c['id'] == _relatedCompanyId;
                                  return ListTile(
                                    dense: true,
                                    title: Text(c['name'] ?? ''),
                                    trailing: selected
                                        ? Icon(
                                            Icons.check,
                                            color: theme.primaryColor,
                                            size: 18,
                                          )
                                        : null,
                                    onTap: () async {
                                      Navigator.of(ctx).pop(c);
                                    },
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    child: const Text('Cancel'),
                  ),
                ],
              );
            },
          );
        },
      ).then((selected) async {
        if (selected is Map<String, dynamic>) {
          try {
            final sessionService = Provider.of<SessionService>(
              context,
              listen: false,
            );
            final client = await sessionService.client;
            if (client == null) throw Exception('Client not initialized');
            _showLoadingDialog(context, 'Updating Related Company');
            await client.callKw({
              'model': 'res.partner',
              'method': 'write',
              'args': [
                [_partnerId],
                {'parent_id': selected['id'] ?? false},
              ],
              'kwargs': {},
            });
            if (!mounted) return;
            _isShowingLoadingDialog = false;
            Navigator.of(context).pop();
            setState(() {
              _relatedCompanyId = selected['id'] as int?;
              _relatedCompanyName = selected['name']?.toString();
            });
            _showSuccessSnackBar('Related Company updated');
          } catch (e) {
            if (mounted) {
              _isShowingLoadingDialog = false;
              Navigator.of(context).pop();
              _showErrorSnackBar('Failed to update related company: $e');
            }
          }
        }
      });
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Configuration',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () async {
            if (_isEditMode && _hasUnsavedChanges()) {
              final shouldPop = await _showUnsavedChangesDialog();
              if (shouldPop && mounted) {
                Navigator.of(context).pop();
              }
            } else {
              if (mounted) Navigator.of(context).pop();
            }
          },
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
      ),
      backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
      body: _isLoading
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Shimmer.fromColors(
                baseColor: shimmerBase,
                highlightColor: shimmerHighlight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.05),
                            blurRadius: 16,
                            spreadRadius: 2,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Container(
                            width: 90,
                            height: 90,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: placeholderColor,
                              border: Border.all(
                                color: isDark
                                    ? Colors.grey[800]!
                                    : Colors.grey[200]!,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(width: 18),

                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 18,
                                  width: 180,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: placeholderColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                Container(
                                  height: 14,
                                  width: 160,
                                  margin: const EdgeInsets.only(bottom: 6),
                                  decoration: BoxDecoration(
                                    color: placeholderColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                Container(
                                  height: 12,
                                  width: 120,
                                  decoration: BoxDecoration(
                                    color: placeholderColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    ...List.generate(8, (index) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: cardColor,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isDark
                                  ? Colors.white.withOpacity(0.08)
                                  : Colors.black.withOpacity(0.06),
                            ),
                            boxShadow: [
                              if (!isDark)
                                BoxShadow(
                                  blurRadius: 16,
                                  spreadRadius: 2,
                                  offset: const Offset(0, 6),
                                  color: Colors.black.withOpacity(0.06),
                                ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  color: placeholderColor,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                              const SizedBox(width: 12),

                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 12,
                                      width: 120,
                                      margin: const EdgeInsets.only(bottom: 8),
                                      decoration: BoxDecoration(
                                        color: placeholderColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                    Container(
                                      height: 16,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: placeholderColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),

                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  color: placeholderColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),

                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isDark
                              ? Colors.white.withOpacity(0.08)
                              : Colors.black.withOpacity(0.06),
                        ),
                        boxShadow: [
                          if (!isDark)
                            BoxShadow(
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: const Offset(0, 6),
                              color: Colors.black.withOpacity(0.06),
                            ),
                        ],
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: placeholderColor,
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  height: 12,
                                  width: 130,
                                  margin: const EdgeInsets.only(bottom: 8),
                                  decoration: BoxDecoration(
                                    color: placeholderColor,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ),
                                ...List.generate(
                                  3,
                                  (i) => Padding(
                                    padding: EdgeInsets.only(
                                      bottom: i == 2 ? 0 : 6,
                                    ),
                                    child: Container(
                                      height: 14,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: placeholderColor,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: placeholderColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            )
          : _userData == null
          ? ConnectionStatusWidget(
              serverUnreachable: true,
              onRetry: () => _fetchUserProfile(forceRefresh: true),
            )
          : RefreshIndicator(
              onRefresh: () => _fetchUserProfile(forceRefresh: true),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const SizedBox(height: 12),
                    GestureDetector(
                      onTap: () async {
                        final isIOS =
                            Theme.of(context).platform == TargetPlatform.iOS;
                        final route = MaterialPageRoute(
                          builder: (context) => const ProfileDetailsScreen(),
                        );
                        final result = await Navigator.push(context, route);
                        if (result == true && mounted) {
                          _fetchUserProfile(forceRefresh: true);
                        }
                      },
                      child: Container(
                        margin: const EdgeInsets.all(20),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 16,
                              spreadRadius: 2,
                              offset: const Offset(0, 6),
                            ),
                          ],
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            SizedBox(
                              width: 90,
                              height: 90,
                              child: Stack(
                                children: [
                                  Center(
                                    child: Container(
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.grey[200]!,
                                          width: 2,
                                        ),
                                      ),
                                      child: photoWidget,
                                    ),
                                  ),
                                  if (_isEditMode)
                                    Positioned(
                                      bottom: 8,
                                      right: 8,
                                      child: InkWell(
                                        onTap: (_isLoading || isEditingDisabled)
                                            ? null
                                            : _showImageSourceActionSheet,
                                        borderRadius: BorderRadius.circular(20),
                                        child: Container(
                                          width: 28,
                                          height: 28,
                                          decoration: BoxDecoration(
                                            color: const Color(0xFF4CAF50),
                                            shape: BoxShape.circle,
                                            border: Border.all(
                                              color: Colors.white,
                                              width: 2,
                                            ),
                                            boxShadow: [
                                              BoxShadow(
                                                color: Colors.black.withOpacity(
                                                  0.15,
                                                ),
                                                blurRadius: 8,
                                                offset: const Offset(0, 2),
                                              ),
                                            ],
                                          ),
                                          child: const Icon(
                                            HugeIcons.strokeRoundedCamera02,
                                            color: Colors.white,
                                            size: 16,
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 18),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    _userData!['name']?.toString() ??
                                        'Unknown User',
                                    style: GoogleFonts.manrope(
                                      color: Colors.white,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.5,
                                      height: 1.2,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  if (_normalizeForEdit(
                                    _userData!['email'],
                                  ).isNotEmpty)
                                    Text(
                                      _normalizeForEdit(_userData!['email']),
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.w400,
                                        letterSpacing: 0.7,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  if (_normalizeForEdit(
                                    _userData!['function'],
                                  ).isNotEmpty)
                                    Text(
                                      _normalizeForEdit(_userData!['function']),
                                      style: GoogleFonts.manrope(
                                        color: Colors.white,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        letterSpacing: 0.7,
                                        height: 1.2,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                ],
                              ),
                            ),

                            const Padding(
                              padding: EdgeInsets.only(left: 8),
                              child: Icon(
                                HugeIcons.strokeRoundedArrowRight01,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),
                    _buildQuickActionsSection(context),
                  ],
                ),
              ),
            ),
    );
  }

  bool _isCurrentAccount(
    Map<String, dynamic> account,
    SessionService sessionService,
  ) {
    final currentSession = sessionService.currentSession;
    if (currentSession == null) return false;

    return account['userId']?.toString() == currentSession.userId.toString() &&
        account['serverUrl'] == currentSession.serverUrl &&
        account['database'] == currentSession.database;
  }

  Widget _buildEmptyAccountState(
    BuildContext context,
    SessionService sessionService,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Text(
            'No Other Accounts',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Add multiple accounts to switch between them quickly',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccountTileInProfile(
    BuildContext context,
    Map<String, dynamic> account,
    SessionService sessionService,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: isDark ? Colors.grey[800] : Colors.grey[50],
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[200]!,
        ),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildUserAvatarInProfile(account, isDark),
        title: Text(
          account['userName'] ?? 'Unknown User',
          style: TextStyle(
            color: isDark ? Colors.white : Colors.black87,
            fontSize: 14,
            fontWeight: FontWeight.w500,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              account['database'] ?? 'Unknown Database',
              style: TextStyle(
                color: isDark ? Colors.grey[400] : Colors.grey[600],
                fontSize: 12,
              ),
            ),
          ],
        ),
        trailing: PopupMenuButton<String>(
          icon: Icon(
            Icons.more_vert,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 18,
          ),
          onSelected: (value) async {
            if (value == 'remove') {
              await _removeAccountInProfile(context, account, sessionService);
            }
          },
          itemBuilder: (context) => [
            PopupMenuItem<String>(
              value: 'remove',
              child: Row(
                children: [
                  Icon(Icons.delete_outline, size: 18, color: Colors.red[600]),
                  const SizedBox(width: 8),
                  Text(
                    'Remove',
                    style: TextStyle(color: Colors.red[600], fontSize: 14),
                  ),
                ],
              ),
            ),
          ],
        ),
        onTap: () async {
          await _switchAccountInProfile(context, account, sessionService);
        },
      ),
    );
  }

  Widget _buildAddAccountButtonInProfile(BuildContext context) {
    return Container(
      margin: const EdgeInsets.all(16),
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddAccountScreen()),
          );
        },
        icon: const Icon(HugeIcons.strokeRoundedUserAdd01, size: 18),
        label: const Text('Add Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildUserAvatarInProfile(Map<String, dynamic> account, bool isDark) {
    final serverUrl = account['serverUrl'] as String?;
    final userId = account['userId'];

    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
          width: 2,
        ),
      ),
      child: ClipOval(
        child: _buildAvatarImageInProfile(serverUrl, userId, isDark, account),
      ),
    );
  }

  Widget _buildAvatarImageInProfile(
    String? serverUrl,
    dynamic userId,
    bool isDark, [
    Map<String, dynamic>? account,
  ]) {
    final imageBase64 = account != null
        ? account['imageBase64'] as String?
        : null;
    if (imageBase64 != null && imageBase64.isNotEmpty) {
      try {
        return Image.memory(
          const Base64Decoder().convert(imageBase64),
          fit: BoxFit.cover,
        );
      } catch (e) {}
    }

    if (serverUrl == null || userId == null) {
      return _buildDefaultAvatarInProfile(isDark, account);
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final avatarUrl =
        '$serverUrl/web/image?model=res.users&id=$userId&field=image_128&unique=$timestamp';

    return CachedNetworkImage(
      imageUrl: avatarUrl,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (context, url) {
        return Container(
          color: isDark ? Colors.grey[700] : Colors.grey[100],
          child: Icon(
            HugeIcons.strokeRoundedUser,
            size: 20,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
          ),
        );
      },
      errorWidget: (context, url, error) {
        return _buildDefaultAvatarInProfile(isDark, account);
      },
    );
  }

  Widget _buildDefaultAvatarInProfile(
    bool isDark, [
    Map<String, dynamic>? account,
  ]) {
    final userName = account?['userName'] as String?;
    if (userName != null && userName.isNotEmpty) {
      final initials = _getUserInitialsInProfile(userName);
      return Container(
        color: isDark ? Colors.grey[700] : Colors.grey[100],
        child: Center(
          child: Text(
            initials,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.grey[300] : Colors.grey[700],
            ),
          ),
        ),
      );
    }

    return Container(
      color: isDark ? Colors.grey[700] : Colors.grey[100],
      child: Icon(
        HugeIcons.strokeRoundedUser,
        size: 20,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
      ),
    );
  }

  String _getUserInitialsInProfile(String userName) {
    final parts = userName.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    } else if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0].substring(0, 1).toUpperCase();
    }
    return 'U';
  }

  Future<void> _switchAccountInProfile(
    BuildContext context,
    Map<String, dynamic> account,
    SessionService sessionService,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final needsReauth = account['needsReauth']?.toString() == 'true';
    final hasEmptyPassword = account['password']?.toString().isEmpty == true;

    if (needsReauth || hasEmptyPassword) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => CredentialsScreen(
            url: account['serverUrl'] ?? '',
            database: account['database'] ?? '',
            prefilledUsername: account['username'] ?? account['userName'],
          ),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(color: AppTheme.primaryColor),
              const SizedBox(height: 16),
              Text(
                'Switching Account...',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white : Colors.black87,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    try {
      await _performDirectAccountSwitchInProfile(
        context,
        account,
        sessionService,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);

        if (e.toString().toLowerCase().contains('authentication') ||
            e.toString().toLowerCase().contains('password') ||
            e.toString().toLowerCase().contains('credentials')) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => CredentialsScreen(
                url: account['serverUrl'] ?? '',
                database: account['database'] ?? '',
                prefilledUsername: account['username'] ?? account['userName'],
              ),
            ),
          );
        } else {
          _showErrorSnackBar('Failed to switch account: ${e.toString()}');
        }
      }
    }
  }

  Future<void> _removeAccountInProfile(
    BuildContext context,
    Map<String, dynamic> account,
    SessionService sessionService,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Remove Account',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to remove ${account['userName']} from your saved accounts?',
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
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.red[700]
                        : Theme.of(context).colorScheme.error,
                    foregroundColor: isDark
                        ? Colors.white
                        : Theme.of(context).colorScheme.onError,
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
                    'Remove',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final accountIndex = sessionService.storedAccounts.indexWhere(
        (stored) => stored['userId'] == account['userId'],
      );

      if (accountIndex != -1) {
        await sessionService.removeStoredAccount(accountIndex);
        if (context.mounted) {
          _showSuccessSnackBar('Account ${account['userName']} removed');
        }
      }
    }
  }

  Future<void> _performDirectAccountSwitchInProfile(
    BuildContext context,
    Map<String, dynamic> account,
    SessionService sessionService,
  ) async {
    final biometricContext = BiometricContextService();
    biometricContext.startAccountOperation('account_switch');

    try {
      final prefs = await SharedPreferences.getInstance();
      String? password;

      final userId = account['userId']?.toString();
      final database = account['database']?.toString();
      final username =
          account['username']?.toString() ?? account['userName']?.toString();

      if (userId != null && database != null) {
        password = prefs.getString('password_${userId}_$database');
      }

      if (password == null && username != null && database != null) {
        password = prefs.getString('password_${username}_$database');
      }

      password ??= prefs.getString('password');

      if (password == null || password.isEmpty) {
        throw Exception('No password found for account');
      }

      final newSession = await OdooSessionManager.authenticate(
        serverUrl: account['serverUrl'],
        database: account['database'],
        username: username ?? '',
        password: password,
      );

      if (newSession != null) {
        await sessionService.updateSessionDirectly(newSession);

        if (context.mounted) {
          Navigator.pop(context);

          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => HomeScaffold()),
            (route) => false,
          );

          biometricContext.endAccountOperation('account_switch');
        }
      } else {
        throw Exception('Authentication failed');
      }
    } catch (e) {
      biometricContext.endAccountOperation('account_switch');

      rethrow;
    }
  }

  void _showAccountDrawer(BuildContext context, SessionService sessionService) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _AccountDrawer(sessionService: sessionService),
    );
  }
}

class _AccountDrawer extends StatelessWidget {
  final SessionService sessionService;

  const _AccountDrawer({required this.sessionService});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final storedAccounts = sessionService.storedAccounts;

    return Container(
      height: MediaQuery.of(context).size.height * 0.7,
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: isDark ? Colors.grey[600] : Colors.grey[300],
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Text(
                  'Switch Accounts',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: storedAccounts.isEmpty
                ? _buildEmptyState(context)
                : _buildAccountsList(context, storedAccounts),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: AppTheme.primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                HugeIcons.strokeRoundedUserAdd01,
                size: 40,
                color: AppTheme.primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              'No Additional Accounts',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Add multiple accounts to switch between them quickly',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
            const SizedBox(height: 32),
            _buildAddAccountButton(context),
          ],
        ),
      ),
    );
  }

  Widget _buildAccountsList(
    BuildContext context,
    List<Map<String, dynamic>> accounts,
  ) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Current Account',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: AppTheme.primaryColor,
          ),
        ),
        const SizedBox(height: 8),
        ...accounts
            .where((account) => _isCurrentAccount(account))
            .map((account) => _buildAccountTile(context, account, true)),

        if (accounts
            .where((account) => !_isCurrentAccount(account))
            .isNotEmpty) ...[
          const SizedBox(height: 24),
          Text(
            'Other Accounts',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Theme.of(context).brightness == Brightness.dark
                  ? Colors.grey[400]
                  : Colors.grey[600],
            ),
          ),
          const SizedBox(height: 8),
          ...accounts
              .where((account) => !_isCurrentAccount(account))
              .map((account) => _buildAccountTile(context, account, false)),
        ],

        const SizedBox(height: 24),
        _buildAddAccountButton(context),
      ],
    );
  }

  Widget _buildAccountTile(
    BuildContext context,
    Map<String, dynamic> account,
    bool isCurrent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () async {
            if (!isCurrent) {
              await _switchAccount(context, account);
            }
          },
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              color: isCurrent
                  ? AppTheme.primaryColor.withOpacity(0.08)
                  : (isDark ? Colors.grey[850] : Colors.grey[50]),
              border: Border.all(
                color: isCurrent
                    ? AppTheme.primaryColor.withOpacity(0.2)
                    : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                _buildUserAvatar(context, account, isCurrent),
                const SizedBox(width: 16),

                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              account['userName'] ?? 'Unknown User',
                              style: TextStyle(
                                color: isDark ? Colors.white : Colors.black87,
                                fontSize: 16,
                                fontWeight: isCurrent
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isCurrent)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: AppTheme.primaryColor,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                'Active',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        account['database'] ?? 'Unknown Database',
                        style: TextStyle(
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          fontSize: 13,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (account['url'] != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          _formatUrl(account['url']),
                          style: TextStyle(
                            color: isDark ? Colors.grey[500] : Colors.grey[500],
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (!isCurrent)
                  PopupMenuButton<String>(
                    icon: Icon(
                      Icons.more_horiz,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                      size: 20,
                    ),
                    onSelected: (value) async {
                      if (value == 'remove') {
                        await _removeAccount(context, account);
                      }
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem<String>(
                        value: 'remove',
                        child: Row(
                          children: [
                            Icon(
                              Icons.delete_outline,
                              size: 18,
                              color: Colors.red[600],
                            ),
                            const SizedBox(width: 12),
                            Text(
                              'Remove Account',
                              style: TextStyle(
                                color: Colors.red[600],
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  )
                else
                  Icon(
                    Icons.check_circle,
                    color: AppTheme.primaryColor,
                    size: 24,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUserAvatar(
    BuildContext context,
    Map<String, dynamic> account,
    bool isCurrent,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    String? avatarUrl;
    if (account['url'] != null && account['userId'] != null) {
      final baseUrl = account['url'].toString().replaceAll(RegExp(r'\/+$'), '');
      avatarUrl =
          '$baseUrl/web/image/res.users/${account['userId']}/image_1920';
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: isCurrent
              ? AppTheme.primaryColor
              : (isDark ? Colors.grey[600]! : Colors.grey[300]!),
          width: 2,
        ),
      ),
      child: ClipOval(
        child: avatarUrl != null
            ? CachedNetworkImage(
                imageUrl: avatarUrl,
                httpHeaders: sessionService.currentSession?.sessionId != null
                    ? {
                        "Cookie":
                            "session_id=${sessionService.currentSession!.sessionId}",
                      }
                    : {},
                width: 44,
                height: 44,
                fit: BoxFit.cover,
                placeholder: (context, url) => Container(
                  color: isCurrent
                      ? AppTheme.primaryColor.withOpacity(0.1)
                      : (isDark ? Colors.grey[700] : Colors.grey[200]),
                  child: Icon(
                    Icons.person,
                    size: 24,
                    color: isCurrent
                        ? AppTheme.primaryColor
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
                errorWidget: (context, url, error) => Container(
                  color: isCurrent
                      ? AppTheme.primaryColor.withOpacity(0.1)
                      : (isDark ? Colors.grey[700] : Colors.grey[200]),
                  child: Icon(
                    Icons.person,
                    size: 24,
                    color: isCurrent
                        ? AppTheme.primaryColor
                        : (isDark ? Colors.grey[400] : Colors.grey[600]),
                  ),
                ),
              )
            : Container(
                color: isCurrent
                    ? AppTheme.primaryColor.withOpacity(0.1)
                    : (isDark ? Colors.grey[700] : Colors.grey[200]),
                child: Icon(
                  Icons.person,
                  size: 24,
                  color: isCurrent
                      ? AppTheme.primaryColor
                      : (isDark ? Colors.grey[400] : Colors.grey[600]),
                ),
              ),
      ),
    );
  }

  String _formatUrl(String url) {
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return url;
    }
  }

  Widget _buildAddAccountButton(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () {
          Navigator.pop(context);
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => AddAccountScreen()),
          );
        },
        icon: const Icon(HugeIcons.strokeRoundedUserAdd01, size: 18),
        label: const Text('Add Account'),
        style: ElevatedButton.styleFrom(
          backgroundColor: AppTheme.primaryColor,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Future<void> _switchAccount(
    BuildContext context,
    Map<String, dynamic> account,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: Dialog(
          backgroundColor: isDark ? Colors.grey[900] : Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LoadingAnimationWidget.fourRotatingDots(
                  color: AppTheme.primaryColor,
                  size: 35,
                ),
                const SizedBox(height: 16),
                Text(
                  'Switching Account...',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Please wait while we switch to ${account['userName']}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[300] : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final accountIndex = sessionService.storedAccounts.indexWhere(
        (stored) => stored['userId'] == account['userId'],
      );

      if (accountIndex == -1) {
        throw Exception('Account not found in stored accounts');
      }

      final prefs = await SharedPreferences.getInstance();
      String? password;

      final userId = account['userId']?.toString();
      final database = account['database']?.toString();
      final username =
          account['username']?.toString() ?? account['userName']?.toString();

      if (userId != null && database != null) {
        password = prefs.getString('password_${userId}_$database');
      }

      if (password == null && username != null && database != null) {
        password = prefs.getString('password_${username}_$database');
      }

      password ??= prefs.getString('password');

      if (password == null || password.isEmpty) {
        throw Exception('No password found for account');
      }

      final newSession = await OdooSessionManager.authenticate(
        serverUrl: account['serverUrl'],
        database: account['database'],
        username: username ?? '',
        password: password,
      );

      if (newSession == null) {
        throw Exception('Authentication failed');
      }

      final success = await sessionService.updateSessionDirectly(newSession);

      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        Navigator.pop(context);

        if (success) {
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute(builder: (context) => const AppEntryPoint()),
            (route) => false,
          );

          Future.delayed(const Duration(milliseconds: 500), () {
            if (context.mounted) {
              CustomSnackbar.showSuccess(
                context,
                'Successfully switched to ${account['userName']}',
              );
            }
          });
        } else {
          CustomSnackbar.showError(
            context,
            'Failed to switch account. Please try again.',
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.pop(context);
        Navigator.pop(context);
        CustomSnackbar.showError(
          context,
          'Error switching account: ${e.toString()}',
        );
      }
    }
  }

  Future<void> _removeAccount(
    BuildContext context,
    Map<String, dynamic> account,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'Remove Account',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'Are you sure you want to remove ${account['userName']} from your saved accounts?',
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
                child: TextButton(
                  onPressed: () => Navigator.of(ctx).pop(false),
                  style: TextButton.styleFrom(
                    foregroundColor: isDark
                        ? Colors.grey[400]
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  child: const Text(
                    'Cancel',
                    style: TextStyle(fontWeight: FontWeight.w500),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: isDark
                        ? Colors.red[700]
                        : Theme.of(context).colorScheme.error,
                    foregroundColor: isDark
                        ? Colors.white
                        : Theme.of(context).colorScheme.onError,
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
                    'Remove',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
    if (confirmed == true) {
      final accountIndex = sessionService.storedAccounts.indexWhere(
        (stored) => stored['userId'] == account['userId'],
      );
      if (accountIndex != -1) {
        await sessionService.removeStoredAccount(accountIndex);
        if (context.mounted) {
          Navigator.of(context).pop();

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              CustomSnackbar.showSuccess(
                context,
                'Account ${account['userName']} removed',
              );
            }
          });
        }
      }
    }
  }

  bool _isCurrentAccount(Map<String, dynamic> account) {
    final currentSession = sessionService.currentSession;
    if (currentSession == null) return false;

    return account['userId']?.toString() == currentSession.userId.toString() &&
        account['serverUrl'] == currentSession.serverUrl &&
        account['database'] == currentSession.database;
  }
}

class FullImageScreen extends StatefulWidget {
  final Uint8List imageBytes;
  final String? title;

  const FullImageScreen({super.key, required this.imageBytes, this.title});

  @override
  State<FullImageScreen> createState() => _FullImageScreenState();
}

class _FullImageScreenState extends State<FullImageScreen> {
  final TransformationController _transformationController =
      TransformationController();
  TapDownDetails? _doubleTapDetails;
  static const double _zoomScale = 2.5;

  @override
  void dispose() {
    _transformationController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final matrix = _transformationController.value;
    if (matrix != Matrix4.identity()) {
      _transformationController.value = Matrix4.identity();
    } else if (_doubleTapDetails != null) {
      final position = _doubleTapDetails!.localPosition;
      _transformationController.value = Matrix4.identity()
        ..translate(
          -position.dx * (_zoomScale - 1),
          -position.dy * (_zoomScale - 1),
        )
        ..scale(_zoomScale);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Scaffold(
      backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
      appBar: AppBar(
        title: Text(
          widget.title ?? 'Profile Photo',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: Icon(HugeIcons.strokeRoundedArrowLeft01),
        ),
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        foregroundColor: isDark ? Colors.white : Theme.of(context).primaryColor,
        elevation: 0,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) => GestureDetector(
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          child: SizedBox.expand(
            child: InteractiveViewer(
              transformationController: _transformationController,
              minScale: 1.0,
              maxScale: 5.0,
              boundaryMargin: EdgeInsets.zero,
              constrained: true,
              child: Image.memory(
                widget.imageBytes,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Center(
                  child: Icon(
                    Icons.error,
                    color: isDark ? Colors.red[300] : Colors.red,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
