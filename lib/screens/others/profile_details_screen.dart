import 'dart:convert';
import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';
import 'package:mobo_sales/utils/app_theme.dart';
import 'package:mobo_sales/services/session_service.dart';
import 'package:mobo_sales/widgets/custom_text_field.dart';
import 'package:mobo_sales/widgets/custom_dropdown.dart';
import 'package:mobo_sales/widgets/data_loss_warning_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/settings_provider.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/widgets/full_image_screen.dart';
import 'package:mobo_sales/widgets/list_shimmer.dart';
import 'package:mobo_sales/widgets/circular_image_widget.dart';

class ProfileDetailsScreen extends StatefulWidget {
  const ProfileDetailsScreen({super.key});

  @override
  State<ProfileDetailsScreen> createState() => _ProfileDetailsScreenState();
}

class _ProfileDetailsScreenState extends State<ProfileDetailsScreen> {
  bool _isLoading = true;
  Map<String, dynamic>? _userData;
  String? _userAvatar;
  List<Map<String, dynamic>> _countries = [];
  List<Map<String, dynamic>> _states = [];
  bool _isLoadingCountries = false;
  bool _isLoadingStates = false;
  File? _pickedImageFile;
  String? _pickedImageBase64;
  final ImagePicker _picker = ImagePicker();
  static const String _cacheKeyUser = 'user_profile';
  static const String _cacheKeyUserWriteDate = 'user_profile_write_date';
  StreamSubscription<List<ConnectivityResult>>? _connectivitySub;
  bool _hasInternet = true;
  bool _isEditMode = false;
  bool _isSaving = false;
  bool _isShowingLoadingDialog = false;
  bool _saveSuccess = false;

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
      final prefs = await SharedPreferences.getInstance();
      final cached = prefs.getString(_cacheKeyUser);
      if (cached != null && cached.isNotEmpty && mounted) {
        final data = jsonDecode(cached) as Map<String, dynamic>;
        setState(() {
          _userData = data;
          final img = data['image_1920'];

          _userAvatar = (img is String && img.isNotEmpty) ? img : null;
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
    _loadCachedUser();
    _fetchUserProfile();
    _loadCountries();
    _startConnectivityListener();
  }

  @override
  void dispose() {
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
          _userAvatar = avatar;
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

  Future<void> _saveAllChanges() async {
    if (!_formKey.currentState!.validate()) {
      _showErrorSnackBar('Please fix the validation errors before saving');
      return;
    }

    setState(() => _isSaving = true);
    _showLoadingDialog(context, 'Saving Changes');

    try {
      final updates = <String, dynamic>{};

      if (_nameController.text.trim() !=
          _normalizeForEdit(_userData!['name'])) {
        updates['name'] = _nameController.text.trim();
      }
      if (_emailController.text.trim() !=
          _normalizeForEdit(_userData!['email'])) {
        updates['email'] = _emailController.text.trim();
      }
      if (_phoneController.text.trim() !=
          _normalizeForEdit(_userData!['phone'])) {
        updates['phone'] = _phoneController.text.trim();
      }
      if (_mobileController.text.trim() !=
          _normalizeForEdit(_userData!['mobile'])) {
        updates['mobile'] = _mobileController.text.trim();
      }
      if (_websiteController.text.trim() !=
          _normalizeForEdit(_userData!['website'])) {
        updates['website'] = _websiteController.text.trim();
      }
      if (_functionController.text.trim() !=
          _normalizeForEdit(_userData!['function'])) {
        updates['function'] = _functionController.text.trim();
      }

      if (updates.isNotEmpty) {
        final sessionService = Provider.of<SessionService>(
          context,
          listen: false,
        );
        final client = await sessionService.client;
        final uid = client?.sessionId?.userId;

        if (client != null && uid != null) {
          await client.callKw({
            'model': 'res.users',
            'method': 'write',
            'args': [
              [uid],
              updates,
            ],
            'kwargs': {},
          });
        }
      }

      await _fetchUserProfile();

      if (mounted) {
        final settingsProvider = Provider.of<SettingsProvider>(
          context,
          listen: false,
        );
        await settingsProvider.fetchUserProfile();
      }

      setState(() => _isEditMode = false);
      _showSuccessSnackBar('Profile updated successfully');
      _saveSuccess = true;
    } catch (e) {
      _showErrorSnackBar('Failed to save changes: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
        _isShowingLoadingDialog = false;

        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _handleBack() async {
    if (_isEditMode && _hasUnsavedChanges()) {
      final shouldPop = await _showUnsavedChangesDialog();
      if (shouldPop && mounted) {
        Navigator.of(context).pop(_saveSuccess);
      }
      return;
    }
    if (mounted) {
      Navigator.of(context).pop(_saveSuccess);
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
    } catch (e) {
      rethrow;
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

  Widget _buildCustomTextField(
    BuildContext context,
    String labelText,
    String? value,
    IconData icon, {
    VoidCallback? onEdit,
    bool disabled = false,
    TextEditingController? controller,
    TextInputType? keyboardType,
    bool showNonEditableMessage = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final displayValue =
        (value == null ||
            value.trim().isEmpty ||
            value.trim().toLowerCase() == 'false')
        ? 'Not set'
        : value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          labelText,
          style: TextStyle(
            fontFamily: GoogleFonts.manrope(
              fontWeight: FontWeight.w400,
            ).fontFamily,
            color: isDark ? Colors.white70 : const Color(0xff7F7F7F),
          ),
        ),
        const SizedBox(height: 8),
        _isEditMode && controller != null && !disabled
            ? _buildEditableField(
                context,
                controller,
                keyboardType,
                labelText,
                isDark,
              )
            : _buildDisplayField(
                context,
                displayValue,
                icon,
                isDark,
                onEdit: onEdit,
                labelText: labelText,
                showNonEditableMessage: showNonEditableMessage,
              ),
      ],
    );
  }

  Widget _buildDisplayField(
    BuildContext context,
    String displayValue,
    IconData icon,
    bool isDark, {
    VoidCallback? onEdit,
    String? labelText,
    bool showNonEditableMessage = false,
  }) {
    return GestureDetector(
      onTap:
          onEdit ??
          (showNonEditableMessage && labelText != null
              ? () {
                  if (mounted) {
                    _showNonEditableFieldSnackBar(labelText);
                  }
                }
              : null),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isDark ? const Color(0xFF2A2A2A) : const Color(0xffF8FAFB),
          border: Border.all(color: Colors.transparent, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Icon(
                icon,
                color: isDark ? Colors.white70 : Colors.black,
                size: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  displayValue,
                  style: TextStyle(
                    fontFamily: GoogleFonts.manrope(
                      fontWeight: FontWeight.w600,
                    ).fontFamily,
                    color: displayValue == 'Not set'
                        ? (isDark ? Colors.grey[500] : Colors.grey[500])
                        : (isDark ? Colors.white70 : const Color(0xff000000)),
                    fontStyle: displayValue == 'Not set'
                        ? FontStyle.italic
                        : FontStyle.normal,
                    fontSize: 14,
                    height: 1.2,
                    letterSpacing: 0.0,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEditableField(
    BuildContext context,
    TextEditingController controller,
    TextInputType? keyboardType,
    String labelText,
    bool isDark,
  ) {
    return Focus(
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: isDark
                      ? const Color(0xFF2A2A2A)
                      : const Color(0xffF8FAFB),
                  border: Border.all(
                    color: hasFocus
                        ? Theme.of(context).primaryColor
                        : Colors.transparent,
                    width: 1,
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _getIconForField(labelText),
                        color: isDark ? Colors.white70 : Colors.black,
                        size: 20,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextFormField(
                          controller: controller,
                          keyboardType: keyboardType,
                          validator: _getValidatorForField(labelText),
                          autovalidateMode: AutovalidateMode.onUserInteraction,
                          style: TextStyle(
                            fontFamily: GoogleFonts.manrope(
                              fontWeight: FontWeight.w600,
                            ).fontFamily,
                            color: isDark
                                ? Colors.white70
                                : const Color(0xff000000),
                            fontSize: 14,
                            height: 1.2,
                            letterSpacing: 0.0,
                          ),
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            errorBorder: InputBorder.none,
                            focusedErrorBorder: InputBorder.none,
                            hintText: controller.text.isEmpty
                                ? 'Enter $labelText'
                                : null,
                            hintStyle: TextStyle(
                              fontFamily: GoogleFonts.manrope(
                                fontWeight: FontWeight.w600,
                              ).fontFamily,
                              color: isDark
                                  ? Colors.grey[500]
                                  : Colors.grey[500],
                              fontStyle: FontStyle.italic,
                              fontSize: 14,
                              height: 1.2,
                              letterSpacing: 0.0,
                            ),
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                            errorStyle: const TextStyle(height: 0, fontSize: 0),
                          ),
                          cursorColor: isDark ? Colors.white70 : Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_getValidatorForField(labelText) != null)
                _buildErrorMessage(controller, labelText, isDark),
            ],
          );
        },
      ),
    );
  }

  IconData _getIconForField(String labelText) {
    switch (labelText.toLowerCase()) {
      case 'full name':
        return HugeIcons.strokeRoundedUserAccount;
      case 'email':
        return HugeIcons.strokeRoundedMail01;
      case 'phone':
        return HugeIcons.strokeRoundedCall02;
      case 'mobile':
        return HugeIcons.strokeRoundedSmartPhone01;
      case 'website':
        return HugeIcons.strokeRoundedWebDesign02;
      case 'job title':
        return HugeIcons.strokeRoundedWorkHistory;
      default:
        return HugeIcons.strokeRoundedUserAccount;
    }
  }

  String? Function(String?)? _getValidatorForField(String labelText) {
    switch (labelText.toLowerCase()) {
      case 'email':
        return (value) {
          if (value == null || value.trim().isEmpty) return null;
          final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
          if (!emailRegex.hasMatch(value.trim())) {
            return 'Please enter a valid email address';
          }
          return null;
        };
      case 'website':
        return (value) {
          if (value == null || value.trim().isEmpty) return null;
          final urlRegex = RegExp(
            r'^(https?:\/\/)?(www\.)?[a-zA-Z0-9-]+(\.[a-zA-Z]{2,})+(\/.*)?$',
          );
          if (!urlRegex.hasMatch(value.trim())) {
            return 'Please enter a valid website URL';
          }
          return null;
        };
      default:
        return null;
    }
  }

  Widget _buildErrorMessage(
    TextEditingController controller,
    String labelText,
    bool isDark,
  ) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, child) {
        final validator = _getValidatorForField(labelText);
        final errorMessage = validator?.call(value.text);
        if (errorMessage == null) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 4, left: 4),
          child: Text(
            errorMessage,
            style: TextStyle(
              color: Colors.red[400],
              fontSize: 12,
              fontWeight: FontWeight.w400,
            ),
          ),
        );
      },
    );
  }

  Widget _buildAddressCard() {
    final settings = Provider.of<SettingsProvider>(context);
    final disabled = settings.offlineMode || !_hasInternet;

    return _buildCustomTextField(
      context,
      'Address',
      _formatAddress(_userData!),
      HugeIcons.strokeRoundedLocation05,
      onEdit: _isEditMode && !disabled ? _showEditAddressDialog : null,
      disabled: disabled,
    );
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

  Future<void> _showRelatedCompanyPicker() async {
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
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
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

  String _formatAddress(Map<String, dynamic> data) {
    final parts = [
      if (data['street'] != null &&
          data['street'].toString().isNotEmpty &&
          data['street'].toString().toLowerCase() != 'false')
        data['street'],
      if (data['street2'] != null &&
          data['street2'].toString().isNotEmpty &&
          data['street2'].toString().toLowerCase() != 'false')
        data['street2'],
      if (data['city'] != null &&
          data['city'].toString().isNotEmpty &&
          data['city'].toString().toLowerCase() != 'false')
        data['city'],
      if (data['state_id'] is List &&
          data['state_id'].length > 1 &&
          data['state_id'][1] != null &&
          data['state_id'][1].toString().isNotEmpty &&
          data['state_id'][1].toString().toLowerCase() != 'false')
        data['state_id'][1],
      if (data['zip'] != null &&
          data['zip'].toString().isNotEmpty &&
          data['zip'].toString().toLowerCase() != 'false')
        data['zip'],
      if (data['country_id'] is List &&
          data['country_id'].length > 1 &&
          data['country_id'][1] != null &&
          data['country_id'][1].toString().isNotEmpty &&
          data['country_id'][1].toString().toLowerCase() != 'false')
        data['country_id'][1],
    ];
    return parts.isNotEmpty ? parts.join(', ') : 'No address set';
  }

  Widget _buildProfileImageSection(
    BuildContext context,
    bool isDark,
    bool isEditingDisabled,
  ) {
    Widget photoWidget;
    if (_pickedImageFile != null) {
      photoWidget = ClipOval(
        child: Image.file(
          _pickedImageFile!,
          width: 120,
          height: 120,
          fit: BoxFit.cover,
        ),
      );
    } else {
      photoWidget = CircularImageWidget(
        base64Image: _userAvatar,
        radius: 60,
        fallbackText: _userData != null && _userData!['name'] != null
            ? _userData!['name'].toString()
            : 'User',
        backgroundColor: AppTheme.primaryColor,
        textColor: Colors.white,
      );
    }

    return Center(
      child: Column(
        children: [
          GestureDetector(
            onTap:
                (!_isEditMode && _userAvatar != null && _userAvatar!.isNotEmpty)
                ? () {
                    try {
                      var raw = _userAvatar!.trim();
                      final dataUrlBase64 = RegExp(
                        r'^data:image\/[a-zA-Z0-9.+-]+;base64,',
                      );
                      raw = raw.replaceFirst(dataUrlBase64, '');
                      final cleanBase64 = raw.replaceAll(RegExp(r'\s+'), '');

                      if (cleanBase64.isEmpty) return;

                      final bytes = base64Decode(cleanBase64);

                      if (!_isValidImage(bytes)) {
                        _showErrorSnackBar(
                          'Profile image format not supported for full view',
                        );
                        return;
                      }

                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => FullImageScreen(
                            title: 'Profile Photo',
                            imageBytes: bytes,
                          ),
                        ),
                      );
                    } catch (e) {
                      _showErrorSnackBar('Could not open full image');
                    }
                  }
                : null,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: isDark ? Colors.grey[600]! : Colors.grey[300]!,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: photoWidget,
                ),
                if (_isEditMode && !isEditingDisabled)
                  Positioned(
                    bottom: 8,
                    right: 8,
                    child: InkWell(
                      onTap: _showImageSourceActionSheet,
                      borderRadius: BorderRadius.circular(20),
                      child: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: AppTheme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isDark ? Colors.grey[900]! : Colors.white,
                            width: 3,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: const Icon(
                          HugeIcons.strokeRoundedCamera02,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 6),

          if (_normalizeForEdit(_userData!['name']).isNotEmpty)
            Text(
              _normalizeForEdit(_userData!['name']),
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w400,
                color: isDark ? Colors.grey[400] : Colors.grey[800],
                letterSpacing: 0.1,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final settings = Provider.of<SettingsProvider>(context);
    final bool isEditingDisabled = settings.offlineMode || !_hasInternet;

    return WillPopScope(
      onWillPop: () async {
        await _handleBack();
        return false;
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            'Profile Details',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          leading: IconButton(
            onPressed: () async {
              await _handleBack();
            },
            icon: Icon(
              HugeIcons.strokeRoundedArrowLeft01,
              color: isDark ? Colors.white : Colors.black,
            ),
          ),
          actions: [
            if (_isEditMode)
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: TextButton(
                  onPressed: _isSaving ? null : _cancelEdit,
                  child: Text(
                    'Cancel',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(right: 0.0),
              child: TextButton(
                onPressed: isEditingDisabled || _isSaving
                    ? null
                    : () {
                        if (_isEditMode) {
                          _saveAllChanges();
                        } else {
                          setState(() {
                            _isEditMode = true;
                          });
                        }
                      },
                child: Text(
                  _isEditMode ? 'Save' : 'Edit',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
                    color: _isEditMode
                        ? (isDark ? Colors.white : Colors.black)
                        : isDark
                        ? Colors.white
                        : AppTheme.primaryColor,
                  ),
                ),
              ),
            ),
          ],
          backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
        ),
        backgroundColor: isDark ? Colors.grey[900]! : Colors.white,
        body: _isLoading
            ? ListShimmer.buildListShimmer(
                context,
                itemCount: 1,
                type: ShimmerType.profile,
              )
            : _userData == null
            ? const Center(child: Text('No user data found'))
            : RefreshIndicator(
                onRefresh: () => _fetchUserProfile(forceRefresh: true),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(20),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildProfileImageSection(
                                context,
                                isDark,
                                isEditingDisabled,
                              ),
                              const SizedBox(height: 32),

                              const Text(
                                'Personal Information',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 20),
                              _buildCustomTextField(
                                context,
                                'Full Name',
                                _userData!['name']?.toString(),
                                HugeIcons.strokeRoundedUserAccount,
                                disabled: isEditingDisabled,
                                controller: _nameController,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Email',
                                (_userData!['email'] ?? _userData!['email'])
                                    ?.toString(),
                                HugeIcons.strokeRoundedMail01,
                                disabled: isEditingDisabled,
                                controller: _emailController,
                                keyboardType: TextInputType.emailAddress,
                                showNonEditableMessage: false,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Phone',
                                _userData!['phone']?.toString(),
                                HugeIcons.strokeRoundedCall02,
                                disabled: isEditingDisabled,
                                controller: _phoneController,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Mobile',
                                _userData!['mobile']?.toString(),
                                HugeIcons.strokeRoundedSmartPhone01,
                                disabled: isEditingDisabled,
                                controller: _mobileController,
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Website',
                                _userData!['website']?.toString(),
                                HugeIcons.strokeRoundedWebDesign02,
                                disabled: isEditingDisabled,
                                controller: _websiteController,
                                keyboardType: TextInputType.url,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Job Title',
                                _userData!['function']?.toString(),
                                HugeIcons.strokeRoundedWorkHistory,
                                disabled: isEditingDisabled,
                                controller: _functionController,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Company',
                                _userData!['company_id'] is List &&
                                        _userData!['company_id'].length > 1
                                    ? (_userData!['company_id'][1]
                                              ?.toString() ??
                                          '')
                                    : '',
                                HugeIcons.strokeRoundedBuilding05,
                                disabled: isEditingDisabled,
                                showNonEditableMessage: true,
                              ),
                              const SizedBox(height: 16),
                              _buildCustomTextField(
                                context,
                                'Related Company',
                                (_relatedCompanyName ?? ''),
                                HugeIcons.strokeRoundedBuilding01,
                                disabled: isEditingDisabled,
                                onEdit: _isEditMode && !isEditingDisabled
                                    ? _showRelatedCompanyPicker
                                    : null,
                                showNonEditableMessage: false,
                              ),
                              const SizedBox(height: 20),
                              _buildAddressCard(),
                              const SizedBox(height: 32),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  bool _isValidImage(Uint8List bytes) {
    if (bytes.length < 4) return false;

    if (bytes[0] == 0x89 &&
        bytes[1] == 0x50 &&
        bytes[2] == 0x4E &&
        bytes[3] == 0x47) {
      return true;
    }

    if (bytes[0] == 0xFF && bytes[1] == 0xD8) return true;

    if (bytes[0] == 0x47 && bytes[1] == 0x49 && bytes[2] == 0x46) return true;

    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return true;
    }
    return false;
  }
}
