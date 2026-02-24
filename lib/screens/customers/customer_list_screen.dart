import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:hugeicons/hugeicons.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../models/contact.dart';
import '../../services/connectivity_service.dart';
import '../../services/session_service.dart';
import '../../providers/contact_provider.dart';
import '../../utils/app_theme.dart';
import '../../widgets/connection_status_widget.dart';
import '../../widgets/custom_snackbar.dart';
import '../../utils/date_picker_utils.dart';
import '../../widgets/customer_list_tile.dart';
import '../../widgets/empty_state_widget.dart';
import '../../widgets/list_shimmer.dart';
import '../../utils/customer_location_helper.dart';
import 'customer_details_screen.dart';
import 'edit_customer_screen.dart';
import 'select_location_screen.dart';
import 'package:latlong2/latlong.dart';

class CustomerListScreen extends StatefulWidget {
  final bool showForcedAppBar;
  final String? forcedAppBarTitle;
  final bool creditBreachesOnly;

  const CustomerListScreen({
    super.key,
    this.showForcedAppBar = false,
    this.forcedAppBarTitle,
    this.creditBreachesOnly = false,
  });

  @override
  State<CustomerListScreen> createState() => CustomerListScreenState();
}

class CustomerListScreenState extends State<CustomerListScreen>
    with AutomaticKeepAliveClientMixin {
  final TextEditingController _searchController = TextEditingController();
  final double _standardPadding = 16.0;
  final double _smallPadding = 8.0;
  final double _tinyPadding = 4.0;
  final double _cardBorderRadius = 12.0;
  final ScrollController _scrollController = ScrollController();
  bool _showScrollToTop = false;

  final Map<String, Uint8List> _base64ImageCache = {};
  Timer? _debounce;

  String _currentSearchQuery = '';

  final Map<String, bool> _expandedGroups = {};
  bool _allGroupsExpanded = false;

  bool _showActiveOnly = true;
  bool _showCompaniesOnly = false;
  bool _showIndividualsOnly = false;
  bool _showCreditBreachesOnly = false;
  String? _selectedIndustry;
  String? _selectedCountry;
  DateTime? _startDate;
  DateTime? _endDate;

  bool _wasConnected = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = Provider.of<ContactProvider>(context, listen: false);
      final connectivityService = context.read<ConnectivityService>();

      _wasConnected = connectivityService.isConnected;

      setState(() {
        _showActiveOnly = provider.showActiveOnly;
        _showCompaniesOnly = provider.showCompaniesOnly;
        _showIndividualsOnly = provider.showIndividualsOnly;
        _showCreditBreachesOnly = provider.showCreditBreachesOnly;
        _selectedIndustry = provider.selectedIndustry;
        _selectedCountry = provider.selectedCountry;
        _startDate = provider.startDate;
        _endDate = provider.endDate;
      });

      if (provider.contacts.isEmpty || provider.error != null) {
        _checkConnectionAndFetch();
      } else {}
    });
    _searchController.addListener(_onSearchChanged);

    _scrollController.addListener(() {
      final shouldShow =
          _scrollController.hasClients && _scrollController.offset > 300;
      if (shouldShow != _showScrollToTop) {
        setState(() {
          _showScrollToTop = shouldShow;
        });
      }
    });
  }

  Future<void> _clearSearchAndReload({bool resetFilters = false}) async {
    if (_debounce?.isActive ?? false) _debounce!.cancel();

    if (mounted) FocusScope.of(context).unfocus();

    _searchController.removeListener(_onSearchChanged);
    _searchController.clear();
    _searchController.addListener(_onSearchChanged);

    _currentSearchQuery = '';

    if (resetFilters) {
      final provider = Provider.of<ContactProvider>(context, listen: false);
      setState(() {
        _showActiveOnly = true;
        _showCompaniesOnly = false;
        _showIndividualsOnly = false;
        _showCreditBreachesOnly = false;
        _selectedIndustry = null;
        _selectedCountry = null;
        _startDate = null;
        _endDate = null;
      });

      provider.clearFilters();
    } else {
      if (mounted) setState(() {});
    }

    if (_scrollController.hasClients) {
      try {
        _scrollController.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      } catch (_) {}
    }

    final provider = Provider.of<ContactProvider>(context, listen: false);
    await provider.clearData();

    Map<String, dynamic>? filters;
    if (!resetFilters) {
      final tmp = <String, dynamic>{};
      if (_showActiveOnly) tmp['showActiveOnly'] = true;
      if (_showCompaniesOnly) tmp['showCompaniesOnly'] = true;
      if (_showIndividualsOnly) tmp['showIndividualsOnly'] = true;
      if (_showCreditBreachesOnly) tmp['showCreditBreachesOnly'] = true;
      if (_startDate != null) tmp['startDate'] = _startDate;
      if (_endDate != null) tmp['endDate'] = _endDate;
      filters = tmp.isEmpty ? null : tmp;
    }

    await provider.fetchContacts(searchQuery: null, filters: filters);
  }

  void _onSearchChanged() {
    _debounce?.cancel();

    _currentSearchQuery = _searchController.text.trim();

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      if (!mounted) return;

      final provider = Provider.of<ContactProvider>(context, listen: false);

      if (_currentSearchQuery.isNotEmpty && _currentSearchQuery.length >= 2) {
        final filters = _buildCurrentFilters();
        await provider.fetchContacts(
          searchQuery: _currentSearchQuery,
          filters: filters?.isEmpty == true ? null : filters,
        );
        if (mounted) {}
      } else if (_currentSearchQuery.isEmpty) {
        final filters = _buildCurrentFilters();
        await provider.fetchContacts(
          searchQuery: null,
          filters: filters?.isEmpty == true ? null : filters,
        );
      }
    });
  }

  bool _hasActiveFilters(ContactProvider provider) {
    return !provider.showActiveOnly ||
        provider.showCompaniesOnly ||
        provider.showIndividualsOnly ||
        provider.showCreditBreachesOnly ||
        provider.selectedIndustry != null ||
        provider.selectedCountry != null ||
        provider.startDate != null ||
        provider.endDate != null ||
        _currentSearchQuery.isNotEmpty;
  }

  Widget _buildFilterIndicator(
    ContactProvider provider,
    bool isDark,
    bool hasGroupBy,
  ) {
    int count = 0;
    if (!provider.showActiveOnly) count++;
    if (provider.showCompaniesOnly) count++;
    if (provider.showIndividualsOnly) count++;
    if (provider.showCreditBreachesOnly) count++;
    if (provider.selectedIndustry != null) count++;
    if (provider.selectedCountry != null) count++;
    if (provider.startDate != null) count++;
    if (provider.endDate != null) count++;
    if (_currentSearchQuery.isNotEmpty) count++;

    if (count == 0) {
      if (hasGroupBy) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Text(
          'No filters applied',
          style: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.white70 : Colors.black54,
            fontWeight: FontWeight.w500,
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count active',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupByPill(bool isDark, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.white70 : Colors.black,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            HugeIcons.strokeRoundedLayer,
            size: 14,
            color: isDark ? Colors.black : Colors.white,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.black : Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  String _getGroupByDisplayName(String? groupBy) {
    if (groupBy == null) return '';

    const groupByOptions = {
      'user_id': 'Salesperson',
      'country_id': 'Country',
      'state_id': 'State',
      'parent_id': 'Parent Company',
      'company_id': 'Company',
      'category_id': 'Tags',
      'create_date': 'Creation Date',
      'write_date': 'Last Modified',
      'active': 'Status',
    };

    return groupByOptions[groupBy] ?? groupBy;
  }

  Widget _buildTopPaginationBar(ContactProvider provider, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[800] : Colors.grey[100],
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
          width: 1,
        ),
      ),
      child: Text(
        provider.getPaginationText(),
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: isDark ? Colors.grey[300] : Colors.grey[700],
        ),
      ),
    );
  }

  Map<String, dynamic>? _buildCurrentFilters() {
    Map<String, dynamic> filters = {};

    if (_showActiveOnly) filters['showActiveOnly'] = true;
    if (_showCompaniesOnly) filters['showCompaniesOnly'] = true;
    if (_showIndividualsOnly) filters['showIndividualsOnly'] = true;
    if (_showCreditBreachesOnly) filters['showCreditBreachesOnly'] = true;
    if (_selectedIndustry != null) filters['industry'] = _selectedIndustry;
    if (_selectedCountry != null) filters['country'] = _selectedCountry;
    if (_startDate != null) filters['startDate'] = _startDate;
    if (_endDate != null) filters['endDate'] = _endDate;

    return filters.isEmpty ? null : filters;
  }

  Future<void> _checkConnectionAndFetch() async {
    final connectivityService = context.read<ConnectivityService>();
    final sessionService = context.read<SessionService>();

    if (connectivityService.isConnected && sessionService.hasValidSession) {
      Map<String, dynamic> filters = {};
      if (_showActiveOnly) filters['showActiveOnly'] = true;
      if (_showCompaniesOnly) filters['showCompaniesOnly'] = true;
      if (_showIndividualsOnly) filters['showIndividualsOnly'] = true;
      if (_showCreditBreachesOnly) filters['showCreditBreachesOnly'] = true;
      if (_startDate != null) filters['startDate'] = _startDate;
      if (_endDate != null) filters['endDate'] = _endDate;

      Provider.of<ContactProvider>(context, listen: false).fetchContacts(
        searchQuery: _currentSearchQuery.isEmpty ? null : _currentSearchQuery,
        filters: filters.isEmpty ? null : filters,
      );
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _scrollController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _showSnack(String message, {SnackbarType type = SnackbarType.info}) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      switch (type) {
        case SnackbarType.success:
          CustomSnackbar.showSuccess(context, message);
          break;
        case SnackbarType.error:
          CustomSnackbar.showError(context, message);
          break;
        case SnackbarType.warning:
          CustomSnackbar.showWarning(context, message);
          break;
        case SnackbarType.info:
        default:
          CustomSnackbar.showInfo(context, message);
          break;
      }
    });
  }

  void _showSnackBarSafe(SnackBar snackBar) {
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) return;
      messenger.showSnackBar(snackBar);
    });
  }

  Widget _buildAvatarFallback(Contact contact) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [Colors.grey[300]!, Colors.grey[400]!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Text(
          contact.name.isNotEmpty
              ? contact.name.substring(0, 2).toUpperCase()
              : '?',
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  bool _hasValidPhoneNumber(String? phoneNumber) {
    if (phoneNumber == null ||
        phoneNumber.trim().isEmpty ||
        phoneNumber == 'false') {
      return false;
    }

    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (cleanedNumber.isEmpty) {
      cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    }

    return cleanedNumber.isNotEmpty && cleanedNumber.length >= 7;
  }

  void _showNoPhoneNumberMessage() {
    _showSnack(
      'No phone number available for this contact',
      type: SnackbarType.error,
    );
  }

  Future<void> _openWhatsApp(BuildContext context, Contact contact) async {
    bool hasValidPhoneNumber(String? phoneNumber) {
      if (phoneNumber == null ||
          phoneNumber.trim().isEmpty ||
          phoneNumber == 'false') {
        return false;
      }
      String cleanedNumber = phoneNumber
          .replaceAll(RegExp(r'[^\d+]'), '')
          .trim();
      if (cleanedNumber.isEmpty) {
        cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
      }
      return cleanedNumber.isNotEmpty && cleanedNumber.length >= 7;
    }

    void showNoPhoneNumberMessageLocal() {
      _showSnack(
        'No phone number available for this contact',
        type: SnackbarType.error,
      );
    }

    if (!hasValidPhoneNumber(contact.phone)) {
      showNoPhoneNumberMessageLocal();
      return;
    }

    try {
      final phoneNumber = contact.phone ?? contact.mobile;

      if (phoneNumber == null || phoneNumber.isEmpty) {
        throw Exception('No phone number available');
      }

      final cleanedNumber = phoneNumber
          .replaceAll(RegExp(r'[^\d+]'), '')
          .trim();

      if (cleanedNumber.isEmpty) {
        throw Exception('Invalid phone number format');
      }

      String whatsappNumber = cleanedNumber;

      if (whatsappNumber.startsWith('+')) {
        whatsappNumber = whatsappNumber.substring(1);
      }

      if (whatsappNumber.length == 10) {
        if (whatsappNumber.startsWith('9') ||
            whatsappNumber.startsWith('8') ||
            whatsappNumber.startsWith('7') ||
            whatsappNumber.startsWith('6')) {
          whatsappNumber = '91$whatsappNumber';
        } else if (whatsappNumber.startsWith('2') ||
            whatsappNumber.startsWith('3') ||
            whatsappNumber.startsWith('4') ||
            whatsappNumber.startsWith('5')) {
          whatsappNumber = '1$whatsappNumber';
        }
      }

      if (whatsappNumber.length < 7) {
        throw Exception('Phone number too short for WhatsApp');
      }

      if (whatsappNumber.length > 15) {
        throw Exception('Phone number too long for WhatsApp');
      }

      if (!RegExp(r'^\d+$').hasMatch(whatsappNumber)) {
        throw Exception('Phone number contains invalid characters');
      }

      final whatsappUrl = Uri.encodeFull('https://wa.me/$whatsappNumber');

      try {
        await launchUrl(
          Uri.parse(whatsappUrl),
          mode: LaunchMode.externalApplication,
        );
        return;
      } catch (e) {}

      if (await canLaunchUrl(Uri.parse(whatsappUrl))) {
        await launchUrl(
          Uri.parse(whatsappUrl),
          mode: LaunchMode.externalApplication,
        );
      } else {
        _showSnack(
          'WhatsApp is not available on this device',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      _showSnack(
        'Failed to open WhatsApp: ${e.toString()}',
        type: SnackbarType.error,
      );
    }
  }

  void _showChatOptionsBottomSheet(BuildContext context, Contact contact) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Send Message',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey[300]),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedMessage01,
              color: isDark ? Colors.white : primaryColor,
            ),
            title: Text(
              'System Messenger',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            subtitle: Text(
              'Send SMS using default messaging app',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            onTap: () {
              Navigator.pop(bottomSheetContext);
              final phoneNumber = contact.phone ?? contact.mobile;
              _sendSMS(phoneNumber);
            },
          ),
          ListTile(
            leading: Icon(HugeIcons.strokeRoundedWhatsapp, color: Colors.green),
            title: Text(
              'WhatsApp',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            subtitle: Text(
              'Send message via WhatsApp',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            onTap: () {
              Navigator.pop(bottomSheetContext);
              _openWhatsApp(context, contact);
            },
          ),
          Builder(
            builder: (context) =>
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ),
        ],
      ),
    );
  }

  Future<void> _sendSMS(String? phoneNumber) async {
    if (!_hasValidPhoneNumber(phoneNumber)) {
      _showNoPhoneNumberMessage();
      return;
    }

    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      _showSnack(
        'No phone number available for this contact',
        type: SnackbarType.error,
      );
      return;
    }

    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();

    if (cleanedNumber.isEmpty) {
      cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    }

    if (cleanedNumber.isEmpty) {
      _showSnack(
        'Phone number contains no valid digits',
        type: SnackbarType.error,
      );
      return;
    }

    final isInternational = cleanedNumber.startsWith('+');

    if (!isInternational && !cleanedNumber.startsWith('00')) {}

    final minLength = isInternational ? 8 : 7;
    if (cleanedNumber.length < minLength) {
      _showSnack(
        'Phone number is too short (minimum $minLength digits)',
        type: SnackbarType.error,
      );
      return;
    }

    if (cleanedNumber.length > 20) {
      _showSnack(
        'Phone number is too long. Please check the format.',
        type: SnackbarType.error,
      );
      return;
    }

    try {
      final smsUri = Uri(scheme: 'sms', path: cleanedNumber);

      try {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
        return;
      } catch (e) {}

      if (await canLaunchUrl(smsUri)) {
        await launchUrl(smsUri, mode: LaunchMode.externalApplication);
      } else {
        _showSnack(
          'No SMS app found to send message',
          type: SnackbarType.error,
        );
      }
    } catch (e) {
      _showSnack(
        'Failed to send SMS: ${e.toString()}',
        type: SnackbarType.error,
      );
    }
  }

  bool _hasValidEmail(String? email) {
    if (email == null || email.trim().isEmpty || email == 'false') {
      return false;
    }

    final emailRegex = RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$');
    return emailRegex.hasMatch(email);
  }

  Future<void> _handleSendEmail(Contact contact) async {
    final email = contact.email;

    if (email == null || email.isEmpty || email == 'false') {
      if (mounted) {
        _showSnack('No email address available for this contact');
      }
      return;
    }

    final List<Uri> emailUris = [
      Uri(scheme: 'mailto', path: email),
      Uri.parse('mailto:$email'),
    ];

    bool launched = false;

    for (final uri in emailUris) {
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);

          launched = true;
          break;
        }
      } catch (e) {
        continue;
      }
    }

    if (!launched) {
      try {
        await Clipboard.setData(ClipboardData(text: email));
        if (mounted) {
          _showSnack('Could not open email app. Email copied to clipboard.');
        }
      } catch (e) {
        if (mounted) {
          _showSnack('Could not open email app or copy to clipboard.');
        }
      }
    }
  }

  Future<void> _makePhoneCall(String? phoneNumber) async {
    if (!_hasValidPhoneNumber(phoneNumber)) {
      _showNoPhoneNumberMessage();
      return;
    }
    if (phoneNumber == null || phoneNumber.trim().isEmpty) {
      _showSnack(
        'No phone number available for this contact',
        type: SnackbarType.error,
      );
      return;
    }

    String cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '').trim();

    if (cleanedNumber.isEmpty) {
      cleanedNumber = phoneNumber.replaceAll(RegExp(r'[^0-9]'), '');
    }
    if (cleanedNumber.isEmpty) {
      _showSnack(
        'Phone number contains no valid digits',
        type: SnackbarType.error,
      );
      return;
    }

    final isInternational = cleanedNumber.startsWith('+');

    if (!isInternational && !cleanedNumber.startsWith('00')) {}

    final minLength = isInternational ? 8 : 7;
    if (cleanedNumber.length < minLength) {
      _showSnack(
        'Phone number is too short (minimum $minLength digits)',
        type: SnackbarType.error,
      );
      return;
    }

    if (cleanedNumber.length > 20) {
      _showSnack(
        'Phone number is too long. Please check the format.',
        type: SnackbarType.error,
      );
      return;
    }

    final phoneUrl = 'tel:$cleanedNumber';

    try {
      await launchUrl(Uri.parse(phoneUrl));
      return;
    } catch (e) {}

    if (await canLaunchUrl(Uri.parse(phoneUrl))) {
      await launchUrl(Uri.parse(phoneUrl));
    } else {
      _showSnack(
        'No phone app found to make the call',
        type: SnackbarType.error,
      );
    }
  }

  void _showOldCustomerFilterBottomSheet() {
    bool tempShowActiveOnly = _showActiveOnly;
    bool tempShowCompaniesOnly = _showCompaniesOnly;
    bool tempShowIndividualsOnly = _showIndividualsOnly;
    bool tempShowCreditBreachesOnly = _showCreditBreachesOnly;
    String? tempSelectedIndustry = _selectedIndustry;
    String? tempSelectedCountry = _selectedCountry;
    DateTime? tempStartDate = _startDate;
    DateTime? tempEndDate = _endDate;

    final Map<String, String> statusFilters = {
      'active_only': 'Active Only',
      'credit_breaches': 'Credit Breaches',
    };
    final Map<String, String> typeFilters = {
      'companies': 'Companies',
      'individuals': 'Individuals',
    };

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          final theme = Theme.of(context);
          final isDark = theme.brightness == Brightness.dark;

          return Container(
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF232323) : Colors.white,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 16,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          HugeIcons.strokeRoundedFilterHorizontal,
                          color: isDark ? Colors.white : Colors.black87,
                          size: 20,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'Filter Customers',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: isDark ? Colors.white : Colors.black87,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: Icon(
                            Icons.close,
                            color: isDark ? Colors.white : Colors.black54,
                          ),
                          splashRadius: 20,
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                  ),

                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 8,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (tempShowActiveOnly ||
                              tempShowCreditBreachesOnly ||
                              tempShowCompaniesOnly ||
                              tempShowIndividualsOnly ||
                              tempStartDate != null ||
                              tempEndDate != null) ...[
                            Text(
                              'Active Filters',
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: isDark
                                    ? Colors.white
                                    : theme.primaryColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              children: [
                                if (tempShowActiveOnly)
                                  Chip(
                                    label: Text(
                                      'Active Only',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    backgroundColor: isDark
                                        ? Colors.white.withOpacity(.08)
                                        : theme.primaryColor.withOpacity(0.08),
                                    deleteIcon: Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setDialogState(() {
                                        tempShowActiveOnly = false;
                                      });
                                    },
                                  ),
                                if (tempShowCreditBreachesOnly)
                                  Chip(
                                    label: Text(
                                      'Credit Breaches',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    backgroundColor: isDark
                                        ? Colors.white.withOpacity(.08)
                                        : theme.primaryColor.withOpacity(0.08),
                                    deleteIcon: Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setDialogState(() {
                                        tempShowCreditBreachesOnly = false;
                                      });
                                    },
                                  ),
                                if (tempShowCompaniesOnly)
                                  Chip(
                                    label: Text(
                                      'Companies',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    backgroundColor: isDark
                                        ? Colors.white.withOpacity(.08)
                                        : theme.primaryColor.withOpacity(0.08),
                                    deleteIcon: Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setDialogState(() {
                                        tempShowCompaniesOnly = false;
                                      });
                                    },
                                  ),
                                if (tempShowIndividualsOnly)
                                  Chip(
                                    label: Text(
                                      'Individuals',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    backgroundColor: isDark
                                        ? Colors.white.withOpacity(.08)
                                        : theme.primaryColor.withOpacity(0.08),
                                    deleteIcon: Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setDialogState(() {
                                        tempShowIndividualsOnly = false;
                                      });
                                    },
                                  ),
                                if (tempStartDate != null ||
                                    tempEndDate != null)
                                  Chip(
                                    label: Text(
                                      'Date: ${tempStartDate != null ? DateFormat('MMM dd').format(tempStartDate!) : '...'} - ${tempEndDate != null ? DateFormat('MMM dd, yyyy').format(tempEndDate!) : '...'}',
                                      style: TextStyle(fontSize: 13),
                                    ),
                                    backgroundColor: isDark
                                        ? Colors.white.withOpacity(.08)
                                        : theme.primaryColor.withOpacity(0.08),
                                    deleteIcon: Icon(Icons.close, size: 16),
                                    onDeleted: () {
                                      setDialogState(() {
                                        tempStartDate = null;
                                        tempEndDate = null;
                                      });
                                    },
                                  ),
                              ],
                            ),
                            const SizedBox(height: 16),
                          ],
                          Text(
                            'Available Filters',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),

                          Text(
                            'Status',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: statusFilters.entries.map((entry) {
                              final selected =
                                  (entry.key == 'active_only' &&
                                      tempShowActiveOnly) ||
                                  (entry.key == 'credit_breaches' &&
                                      tempShowCreditBreachesOnly);
                              return ChoiceChip(
                                label: Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: selected
                                        ? Colors.white
                                        : (isDark
                                              ? Colors.white
                                              : Colors.black87),
                                  ),
                                ),
                                selected: selected,
                                selectedColor: theme.primaryColor,
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(.08)
                                    : theme.primaryColor.withOpacity(0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                onSelected: (isSelected) {
                                  setDialogState(() {
                                    if (entry.key == 'active_only') {
                                      tempShowActiveOnly = isSelected;
                                    } else if (entry.key == 'credit_breaches') {
                                      tempShowCreditBreachesOnly = isSelected;
                                    }
                                  });
                                },
                              );
                            }).toList(),
                          ),
                          const SizedBox(height: 16),

                          Text(
                            'Type',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: typeFilters.entries.map((entry) {
                              final selected =
                                  (entry.key == 'companies' &&
                                      tempShowCompaniesOnly) ||
                                  (entry.key == 'individuals' &&
                                      tempShowIndividualsOnly);
                              final disabled =
                                  (entry.key == 'companies' &&
                                      tempShowIndividualsOnly) ||
                                  (entry.key == 'individuals' &&
                                      tempShowCompaniesOnly);
                              return ChoiceChip(
                                label: Text(
                                  entry.value,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: selected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: disabled
                                        ? (isDark
                                              ? Colors.grey[700]
                                              : Colors.grey[400])
                                        : (selected
                                              ? Colors.white
                                              : (isDark
                                                    ? Colors.white
                                                    : Colors.black87)),
                                  ),
                                ),
                                selected: selected,
                                selectedColor: theme.primaryColor,
                                disabledColor: isDark
                                    ? Colors.grey[800]
                                    : Colors.grey[200],
                                backgroundColor: isDark
                                    ? Colors.white.withOpacity(.08)
                                    : theme.primaryColor.withOpacity(0.08),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                ),
                                onSelected: disabled
                                    ? null
                                    : (isSelected) {
                                        setDialogState(() {
                                          if (entry.key == 'companies') {
                                            tempShowCompaniesOnly = isSelected;
                                            if (isSelected) {
                                              tempShowIndividualsOnly = false;
                                            }
                                          } else if (entry.key ==
                                              'individuals') {
                                            tempShowIndividualsOnly =
                                                isSelected;
                                            if (isSelected) {
                                              tempShowCompaniesOnly = false;
                                            }
                                          }
                                        });
                                      },
                              );
                            }).toList(),
                          ),

                          const SizedBox(height: 16),
                          Text(
                            'Date Range',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: isDark
                                  ? Colors.grey[400]
                                  : Colors.grey[600],
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),

                          InkWell(
                            onTap: () async {
                              final date =
                                  await DatePickerUtils.showStandardDatePicker(
                                    context: context,
                                    initialDate:
                                        tempStartDate ?? DateTime.now(),
                                    firstDate: DateTime(2020),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                              if (date != null) {
                                setDialogState(() {
                                  tempStartDate = date;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[850]
                                    : Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tempStartDate != null
                                          ? 'From: ${DateFormat('MMM dd, yyyy').format(tempStartDate!)}'
                                          : 'Select start date',
                                      style: TextStyle(
                                        color: tempStartDate != null
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.grey[800])
                                            : (isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[600]),
                                      ),
                                    ),
                                  ),
                                  if (tempStartDate != null)
                                    IconButton(
                                      onPressed: () {
                                        setDialogState(() {
                                          tempStartDate = null;
                                        });
                                      },
                                      icon: Icon(
                                        Icons.clear,
                                        size: 16,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),

                          InkWell(
                            onTap: () async {
                              final date =
                                  await DatePickerUtils.showStandardDatePicker(
                                    context: context,
                                    initialDate: tempEndDate ?? DateTime.now(),
                                    firstDate: tempStartDate ?? DateTime(2020),
                                    lastDate: DateTime.now().add(
                                      const Duration(days: 365),
                                    ),
                                  );
                              if (date != null) {
                                setDialogState(() {
                                  tempEndDate = date;
                                });
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? Colors.grey[850]
                                    : Colors.grey[50],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: isDark
                                      ? Colors.grey[700]!
                                      : Colors.grey[300]!,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.calendar_today,
                                    size: 16,
                                    color: isDark
                                        ? Colors.grey[400]
                                        : Colors.grey[600],
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      tempEndDate != null
                                          ? 'To: ${DateFormat('MMM dd, yyyy').format(tempEndDate!)}'
                                          : 'Select end date',
                                      style: TextStyle(
                                        color: tempEndDate != null
                                            ? (isDark
                                                  ? Colors.white
                                                  : Colors.grey[800])
                                            : (isDark
                                                  ? Colors.grey[400]
                                                  : Colors.grey[600]),
                                      ),
                                    ),
                                  ),
                                  if (tempEndDate != null)
                                    IconButton(
                                      onPressed: () {
                                        setDialogState(() {
                                          tempEndDate = null;
                                        });
                                      },
                                      icon: Icon(
                                        Icons.clear,
                                        size: 16,
                                        color: isDark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                      ),
                    ),
                  ),

                  Divider(
                    height: 1,
                    thickness: 1,
                    color: isDark ? Colors.grey[800] : Colors.grey[200],
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () {
                              setDialogState(() {
                                tempShowActiveOnly = true;
                                tempShowCompaniesOnly = false;
                                tempShowIndividualsOnly = false;
                                tempShowCreditBreachesOnly = false;
                                tempSelectedIndustry = null;
                                tempSelectedCountry = null;
                                tempStartDate = null;
                                tempEndDate = null;
                              });
                            },
                            style: OutlinedButton.styleFrom(
                              foregroundColor: isDark
                                  ? Colors.grey[300]
                                  : Colors.grey[700],
                              side: BorderSide(
                                color: isDark
                                    ? Colors.grey[700]!
                                    : Colors.grey[300]!,
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Clear',
                              style: TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () {
                              _applyCustomerFilters(
                                tempShowActiveOnly,
                                tempShowCompaniesOnly,
                                tempShowIndividualsOnly,
                                tempShowCreditBreachesOnly,
                                tempSelectedIndustry,
                                tempSelectedCountry,
                                tempStartDate,
                                tempEndDate,
                              );
                              Navigator.of(context).pop();
                              final appliedCount = [
                                if (tempShowActiveOnly) 'Active Only',
                                if (tempShowCreditBreachesOnly)
                                  'Credit Breaches',
                                if (tempShowCompaniesOnly) 'Companies',
                                if (tempShowIndividualsOnly) 'Individuals',
                                if (tempStartDate != null ||
                                    tempEndDate != null)
                                  'Date Range',
                              ].length;
                              final message = (appliedCount > 0)
                                  ? 'Applied $appliedCount filter${appliedCount > 1 ? 's' : ''}'
                                  : 'All filters cleared';
                              _showSnack(message);
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: isDark
                                  ? Colors.grey[800]
                                  : theme.primaryColor,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: Text(
                              'Apply',
                              style: TextStyle(fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  void _applyCustomerFilters(
    bool showActiveOnly,
    bool showCompaniesOnly,
    bool showIndividualsOnly,
    bool showCreditBreachesOnly,
    String? selectedIndustry,
    String? selectedCountry,
    DateTime? startDate,
    DateTime? endDate,
  ) {
    setState(() {
      _showActiveOnly = showActiveOnly;
      _showCompaniesOnly = showCompaniesOnly;
      _showIndividualsOnly = showIndividualsOnly;
      _showCreditBreachesOnly = showCreditBreachesOnly;
      _selectedIndustry = selectedIndustry;
      _selectedCountry = selectedCountry;
      _startDate = startDate;
      _endDate = endDate;
    });

    final provider = Provider.of<ContactProvider>(context, listen: false);

    Map<String, dynamic> filters = {};
    if (showActiveOnly) filters['showActiveOnly'] = true;
    if (showCompaniesOnly) filters['showCompaniesOnly'] = true;
    if (showIndividualsOnly) filters['showIndividualsOnly'] = true;
    if (showCreditBreachesOnly) filters['showCreditBreachesOnly'] = true;
    if (startDate != null) filters['startDate'] = startDate;
    if (endDate != null) filters['endDate'] = endDate;

    provider.refreshContacts(
      searchQuery: _currentSearchQuery.isEmpty ? null : _currentSearchQuery,
      filters: filters.isEmpty ? null : filters,
    );
  }

  Future<void> _openContactLocation(Contact contact) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;

    final shouldProceed = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        elevation: isDark ? 0 : 8,
        backgroundColor: isDark ? Colors.grey[900] : Colors.white,
        title: Text(
          'No Location Data',
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w700,
            color: isDark
                ? Colors.white
                : Theme.of(context).colorScheme.onSurface,
          ),
        ),
        content: Text(
          'This customer doesn\'t have location coordinates set. Would you like to add location data for ${contact.displayName ?? 'this customer'}?',
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
                    backgroundColor: isDark ? primaryColor : primaryColor,
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
                    'Add Location',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );

    if (shouldProceed != true) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? Colors.grey[900] : Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (bottomSheetContext) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              'Add Location for ${contact.displayName ?? 'Customer'}',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
          Divider(height: 1, color: isDark ? Colors.white24 : Colors.grey[300]),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedCoordinate01,
              color: isDark ? Colors.white : primaryColor,
            ),
            title: Text(
              'Geolocalize with Odoo',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            subtitle: Text(
              'Use Odoo\'s geolocation service',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            onTap: () async {
              Navigator.pop(bottomSheetContext);
              await handleCustomerLocation(
                context: context,
                parentContext: context,
                contact: contact,
                onContactUpdated: (updatedContact) {
                  final provider = Provider.of<ContactProvider>(
                    context,
                    listen: false,
                  );
                  provider.updateContactCoordinates(updatedContact);
                  setState(() {});
                },
                suppressMapRedirect: true,
                skipConfirmation: true,
              );
            },
          ),
          ListTile(
            leading: Icon(
              HugeIcons.strokeRoundedMaping,
              color: isDark ? Colors.white : primaryColor,
            ),
            title: Text(
              'Select location on map',
              style: TextStyle(color: isDark ? Colors.white : Colors.black87),
            ),
            subtitle: Text(
              'Manually choose a location on the map',
              style: TextStyle(
                color: isDark ? Colors.white60 : Colors.grey[600],
              ),
            ),
            onTap: () async {
              Navigator.pop(bottomSheetContext);
              final LatLng? selected = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => SelectLocationScreen(
                    onSaveLocation: (LatLng latLng) async {
                      final sessionService = Provider.of<SessionService>(
                        context,
                        listen: false,
                      );
                      final client = await sessionService.client;
                      if (client == null) {
                        return false;
                      }
                      try {
                        final result = await client.callKw({
                          'model': 'res.partner',
                          'method': 'write',
                          'args': [
                            [contact.id],
                            {
                              'partner_latitude': latLng.latitude,
                              'partner_longitude': latLng.longitude,
                            },
                          ],
                          'kwargs': {},
                        });
                        Future.microtask(() {
                          _showSnack(
                            'Location updated successfully!',
                            type: SnackbarType.success,
                          );
                        });
                        if (result == true) {
                          WidgetsBinding.instance.addPostFrameCallback((_) {
                            if (mounted) {
                              setState(() {
                                contact = contact.copyWith(
                                  latitude: latLng.latitude,
                                  longitude: latLng.longitude,
                                );
                              });
                            }
                          });
                          return true;
                        } else {
                          return false;
                        }
                      } catch (e) {
                        return false;
                      }
                    },
                  ),
                ),
              );
              if (selected != null) {
                final sessionService = Provider.of<SessionService>(
                  context,
                  listen: false,
                );
                final client = await sessionService.client;
                if (client != null) {
                  await client.callKw({
                    'model': 'res.partner',
                    'method': 'write',
                    'args': [
                      [contact.id],
                      {
                        'partner_latitude': selected.latitude,
                        'partner_longitude': selected.longitude,
                      },
                    ],
                    'kwargs': {},
                  });
                  final provider = Provider.of<ContactProvider>(
                    context,
                    listen: false,
                  );
                  provider.updateContactCoordinates(
                    contact.copyWith(
                      latitude: selected.latitude,
                      longitude: selected.longitude,
                    ),
                  );
                  setState(() {});
                }
              }
            },
          ),
          Builder(
            builder: (context) =>
                SizedBox(height: MediaQuery.of(context).viewInsets.bottom),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Consumer<ContactProvider>(
      builder: (context, provider, _) {
        final contacts = provider.contacts;
        final isLoading = provider.isLoading;
        final isSearching = provider.isSearching;
        final error = provider.error;

        List<Contact> filteredContacts = contacts;

        return Scaffold(
          backgroundColor: isDark ? Colors.grey[900] : Colors.grey[50],
          floatingActionButton: Consumer<ContactProvider>(
            builder: (context, provider, child) {
              return Padding(
                padding: EdgeInsets.only(bottom: 0.0),
                child: FloatingActionButton(
                  heroTag: 'fab_create_customer',
                  onPressed: () async {
                    final isIOS =
                        Theme.of(context).platform == TargetPlatform.iOS;
                    final result = await Navigator.push(
                      context,

                      MaterialPageRoute(
                        builder: (context) => const EditCustomerScreen(),
                      ),
                    );
                    if (result != null && mounted) {
                      final filters = _buildCurrentFilters();
                      Provider.of<ContactProvider>(
                        context,
                        listen: false,
                      ).refreshContacts(
                        searchQuery: _currentSearchQuery.isEmpty
                            ? null
                            : _currentSearchQuery,
                        filters: filters?.isEmpty == true ? null : filters,
                      );
                      if (mounted) setState(() {});
                    }
                  },
                  backgroundColor:
                      Theme.of(context).brightness == Brightness.dark
                      ? Colors.white
                      : Theme.of(context).primaryColor,
                  tooltip: 'Create Customer',
                  child: Icon(
                    HugeIcons.strokeRoundedUserAdd01,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black
                        : Colors.white,
                  ),
                ),
              );
            },
          ),
          body: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Container(
                  decoration: BoxDecoration(
                    boxShadow: [
                      BoxShadow(
                        color: Color(0xFF000000).withOpacity(0.05),
                        offset: Offset(0, 6),
                        blurRadius: 16,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: TextField(
                    controller: _searchController,
                    enabled: !isLoading && !isSearching,
                    style: TextStyle(
                      color: isDark ? Colors.white : Color(0xff1E1E1E),
                      fontWeight: FontWeight.w400,
                      fontStyle: FontStyle.normal,
                      fontSize: 15,
                      height: 1.0,
                      letterSpacing: 0.0,
                    ),
                    decoration: InputDecoration(
                      hintText: 'Search customers...',
                      hintStyle: TextStyle(
                        color: isDark ? Colors.white : Color(0xff1E1E1E),
                        fontWeight: FontWeight.w400,
                        fontStyle: FontStyle.normal,
                        fontSize: 15,
                        height: 1.0,
                        letterSpacing: 0.0,
                      ),
                      prefixIcon: IconButton(
                        icon: Icon(
                          HugeIcons.strokeRoundedFilterHorizontal,
                          color: isDark ? Colors.grey[400] : Colors.grey[600],
                          size: 18,
                        ),
                        tooltip: 'Filter & Group By',
                        onPressed: () {
                          showCustomerFilterBottomSheet();
                        },
                      ),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: Icon(
                                Icons.clear,
                                color: isDark ? Colors.grey[400] : Colors.grey,
                              ),
                              onPressed: (isLoading || isSearching)
                                  ? null
                                  : () {
                                      _clearSearchAndReload();
                                    },
                            )
                          : null,
                      filled: true,
                      fillColor: isDark ? Colors.grey[850] : Colors.white,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide(
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                      alignLabelWithHint: true,
                    ),
                  ),
                ),
              ),
              SizedBox(height: 16),

              Consumer<ContactProvider>(
                builder: (context, provider, _) {
                  if (!provider.hasInitiallyLoaded) {
                    return const SizedBox.shrink();
                  }

                  final paginationText = provider.getPaginationText();
                  if (paginationText == "0 items") {
                    return const SizedBox.shrink();
                  }

                  return Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16.0,
                      vertical: 8.0,
                    ),
                    child: Row(
                      children: [
                        _buildFilterIndicator(
                          provider,
                          isDark,
                          provider.isGrouped,
                        ),
                        if (provider.isGrouped) ...[
                          const SizedBox(width: 8),
                          _buildGroupByPill(
                            isDark,
                            _getGroupByDisplayName(provider.selectedGroupBy),
                          ),
                        ],
                        const Spacer(),
                        _buildTopPaginationBar(provider, isDark),
                        if (!provider.isGrouped) ...[
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    (provider.canGoToPreviousPage &&
                                        !provider.isLoadingMore)
                                    ? () => provider.goToPreviousPage()
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 4,
                                  ),
                                  child: Icon(
                                    HugeIcons.strokeRoundedArrowLeft01,
                                    size: 20,
                                    color:
                                        (provider.canGoToPreviousPage &&
                                            !provider.isLoadingMore)
                                        ? (isDark
                                              ? Colors.white
                                              : Colors.black87)
                                        : (isDark
                                              ? Colors.grey[600]
                                              : Colors.grey[400]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap:
                                    (provider.canGoToNextPage &&
                                        !provider.isLoadingMore)
                                    ? () => provider.goToNextPage()
                                    : null,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8.0,
                                    horizontal: 4,
                                  ),
                                  child: Icon(
                                    HugeIcons.strokeRoundedArrowRight01,
                                    size: 20,
                                    color:
                                        (provider.canGoToNextPage &&
                                            !provider.isLoadingMore)
                                        ? (isDark
                                              ? Colors.white
                                              : Colors.black87)
                                        : (isDark
                                              ? Colors.grey[600]
                                              : Colors.grey[400]),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
              Expanded(
                child: Consumer2<ConnectivityService, SessionService>(
                  builder: (context, connectivityService, sessionService, child) {
                    if (!_wasConnected && connectivityService.isConnected) {
                      _wasConnected = true;

                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (mounted && sessionService.hasValidSession) {
                          final filters = _buildCurrentFilters();
                          provider.refreshContacts(
                            searchQuery: _currentSearchQuery.isEmpty
                                ? null
                                : _currentSearchQuery,
                            filters: filters?.isEmpty == true ? null : filters,
                          );
                        }
                      });
                    } else if (_wasConnected &&
                        !connectivityService.isConnected) {
                      _wasConnected = false;
                    }

                    if (!connectivityService.isConnected) {
                      return ConnectionStatusWidget(
                        onRetry: () {
                          if (connectivityService.isConnected &&
                              sessionService.hasValidSession) {
                            final filters = _buildCurrentFilters();
                            provider.refreshContacts(
                              searchQuery: _currentSearchQuery.isEmpty
                                  ? null
                                  : _currentSearchQuery,
                              filters: filters?.isEmpty == true
                                  ? null
                                  : filters,
                            );
                          }
                        },
                        customMessage:
                            'No internet connection. Please check your connection and try again.',
                      );
                    }
                    if (provider.isServerUnreachable ||
                        (error != null && _isServerUnreachableError(error))) {
                      return ConnectionStatusWidget(
                        serverUnreachable: true,
                        serverErrorMessage: error ?? provider.error,
                        onRetry: () {
                          provider.clearServerUnreachableState();
                          final filters = _buildCurrentFilters();
                          provider.refreshContacts(
                            searchQuery: _currentSearchQuery.isEmpty
                                ? null
                                : _currentSearchQuery,
                            filters: filters?.isEmpty == true ? null : filters,
                          );
                        },
                      );
                    }

                    if (provider.accessErrorMessage != null) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32.0),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 24,
                                  vertical: 20,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.white.withOpacity(0.06)
                                      : Theme.of(
                                          context,
                                        ).colorScheme.error.withOpacity(0.08),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: isDark
                                        ? Colors.white.withOpacity(0.18)
                                        : Theme.of(
                                            context,
                                          ).colorScheme.error.withOpacity(0.18),
                                    width: 1.2,
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(
                                      Icons.info_outline,
                                      color: isDark
                                          ? Colors.white.withOpacity(0.85)
                                          : Theme.of(context).colorScheme.error
                                                .withOpacity(0.85),
                                      size: 48,
                                    ),
                                    const SizedBox(height: 16),
                                    Text(
                                      'Access Error',
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white
                                            : Theme.of(
                                                context,
                                              ).colorScheme.error,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      provider.accessErrorMessage!,
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.white.withOpacity(0.8)
                                            : Theme.of(context)
                                                  .colorScheme
                                                  .error
                                                  .withOpacity(0.8),
                                        fontSize: 16,
                                        fontWeight: FontWeight.w400,
                                      ),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 24),
                                    SizedBox(
                                      width: double.infinity,
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isDark
                                              ? Colors.white.withOpacity(0.1)
                                              : Theme.of(
                                                  context,
                                                ).colorScheme.primary,
                                          foregroundColor: isDark
                                              ? Colors.white
                                              : Colors.white,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 24,
                                            vertical: 12,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              12,
                                            ),
                                          ),
                                          elevation: 0,
                                        ),
                                        onPressed: () {
                                          final filters =
                                              _buildCurrentFilters();
                                          provider.fetchContacts(
                                            forceRefresh: true,
                                            searchQuery:
                                                _currentSearchQuery.isEmpty
                                                ? null
                                                : _currentSearchQuery,
                                            filters: filters?.isEmpty == true
                                                ? null
                                                : filters,
                                          );
                                        },
                                        icon: Icon(Icons.refresh, size: 20),
                                        label: Text(
                                          'Retry',
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w500,
                                          ),
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
                    if (isLoading || isSearching) {
                      return ListShimmer.buildListShimmer(
                        context,
                        itemCount: 8,
                        type: ShimmerType.standard,
                      );
                    }

                    if (error != null) {
                      return RefreshIndicator(
                        onRefresh: () async {
                          final filters = _buildCurrentFilters();
                          await provider.refreshContacts(
                            searchQuery: _currentSearchQuery.isEmpty
                                ? null
                                : _currentSearchQuery,
                            filters: filters?.isEmpty == true ? null : filters,
                          );
                        },
                        child: CustomScrollView(
                          slivers: [
                            SliverFillRemaining(
                              hasScrollBody: false,
                              child: EmptyStateWidget(
                                icon: HugeIcons.strokeRoundedUserMultiple,
                                title: 'Error Loading Customers',
                                message: error,
                                showRetry: true,
                                onRetry: () {
                                  final filters = _buildCurrentFilters();
                                  provider.refreshContacts(
                                    searchQuery: _currentSearchQuery.isEmpty
                                        ? null
                                        : _currentSearchQuery,
                                    filters: filters?.isEmpty == true
                                        ? null
                                        : filters,
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                      );
                    }

                    if (filteredContacts.isEmpty &&
                        !isLoading &&
                        !isSearching &&
                        provider.hasInitiallyLoaded) {
                      final hasFilters =
                          _showActiveOnly ||
                          _showCompaniesOnly ||
                          _showIndividualsOnly ||
                          _showCreditBreachesOnly ||
                          _selectedIndustry != null ||
                          _selectedCountry != null ||
                          _startDate != null ||
                          _endDate != null;

                      return EmptyStateWidget.customers(
                        hasSearchQuery: _currentSearchQuery.isNotEmpty,
                        hasFilters: hasFilters,
                        onClearFilters: hasFilters
                            ? () async {
                                await _clearSearchAndReload(resetFilters: true);
                              }
                            : null,
                        onRetry: () {
                          final filters = _buildCurrentFilters();
                          provider.refreshContacts(
                            searchQuery: _currentSearchQuery.isEmpty
                                ? null
                                : _currentSearchQuery,
                            filters: filters?.isEmpty == true ? null : filters,
                          );
                        },
                      );
                    }

                    return RefreshIndicator(
                      onRefresh: () async {
                        final filters = _buildCurrentFilters();
                        await provider.refreshContacts(
                          searchQuery: _currentSearchQuery.isEmpty
                              ? null
                              : _currentSearchQuery,
                          filters: filters?.isEmpty == true ? null : filters,
                        );
                      },
                      child: provider.isGrouped
                          ? _buildGroupedCustomerList(provider, isDark)
                          : _buildRegularCustomerList(
                              filteredContacts,
                              provider,
                              isDark,
                            ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  bool get wantKeepAlive => true;

  Widget _buildGroupedCustomerList(ContactProvider provider, bool isDark) {
    try {
      if (provider.groupSummary.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.group_work_outlined,
                  size: 64,
                  color: isDark ? Colors.grey[600] : Colors.grey[400],
                ),
                const SizedBox(height: 16),
                Text(
                  'No groups found',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Try adjusting your filters or group by settings',
                  style: TextStyle(
                    fontSize: 14,
                    color: isDark ? Colors.grey[500] : Colors.grey[500],
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      }

      for (final groupKey in provider.groupSummary.keys) {
        if (!_expandedGroups.containsKey(groupKey)) {
          _expandedGroups[groupKey] = false;
        }
      }

      _expandedGroups.removeWhere(
        (key, value) => !provider.groupSummary.containsKey(key),
      );

      return Expanded(
        child: ListView.builder(
          controller: _scrollController,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: provider.groupSummary.keys.length,
          itemBuilder: (context, index) {
            try {
              final groupKey = provider.groupSummary.keys.elementAt(index);
              final count = provider.groupSummary[groupKey]!;
              final isExpanded = _expandedGroups[groupKey] ?? false;
              final loadedContacts = provider.loadedGroups[groupKey] ?? [];

              return _buildOdooStyleGroupTile(
                groupKey,
                count,
                isExpanded,
                loadedContacts,
                provider,
                isDark,
              );
            } catch (e) {
              return const SizedBox.shrink();
            }
          },
        ),
      );
    } catch (e) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: isDark ? Colors.red[400] : Colors.red[600],
              ),
              const SizedBox(height: 16),
              Text(
                'Error loading groups',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.red[400] : Colors.red[600],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please try refreshing or contact support',
                style: TextStyle(
                  fontSize: 14,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }
  }

  Widget _buildRegularCustomerList(
    List<Contact> filteredContacts,
    ContactProvider provider,
    bool isDark,
  ) {
    return Column(
      children: [
        Expanded(
          child: provider.isLoadingMore
              ? ListShimmer.buildListShimmer(
                  context,
                  itemCount: 8,
                  type: ShimmerType.standard,
                )
              : ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(horizontal: _standardPadding),
                  itemCount: filteredContacts.length,
                  itemBuilder: (context, index) {
                    final contact = filteredContacts[index];
                    return CustomerListTile(
                      contact: contact,
                      isDark: isDark,
                      imageCache: _base64ImageCache,
                      onTap: () => _navigateToCustomerDetails(contact),
                      onCall: () => _makePhoneCall(contact.phone),
                      onMessage: () =>
                          _showChatOptionsBottomSheet(context, contact),
                      onEmail: () => _handleSendEmail(contact),
                      onLocation: () => _handleLocationAction(contact),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildOdooStyleGroupTile(
    String groupKey,
    int count,
    bool isExpanded,
    List<Contact> loadedContacts,
    ContactProvider provider,
    bool isDark,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? Colors.grey[900] : Colors.white,
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
              color: Colors.black.withOpacity(0.08),
            ),
        ],
      ),
      margin: const EdgeInsets.only(bottom: 8),
      child: Column(
        children: [
          InkWell(
            onTap: () async {
              try {
                setState(() {
                  _expandedGroups[groupKey] = !isExpanded;
                  _allGroupsExpanded = _expandedGroups.values.every(
                    (expanded) => expanded,
                  );
                });

                if (!isExpanded && loadedContacts.isEmpty) {
                  await provider.loadGroupContacts(groupKey);
                }
              } catch (e) {}
            },
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          groupKey.isNotEmpty ? groupKey : 'Unknown Group',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$count customer${count != 1 ? 's' : ''}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isDark ? Colors.grey[400] : Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ],
              ),
            ),
          ),
          if (isExpanded)
            loadedContacts.isEmpty
                ? Container(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            AppTheme.primaryColor,
                          ),
                        ),
                      ),
                    ),
                  )
                : Column(
                    children: loadedContacts.map((contact) {
                      try {
                        return Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          child: CustomerListTile(
                            contact: contact,
                            isDark: isDark,
                            onTap: () => _navigateToCustomerDetails(contact),
                            onLocation: () => _handleLocationAction(contact),
                          ),
                        );
                      } catch (e) {
                        return const SizedBox.shrink();
                      }
                    }).toList(),
                  ),
        ],
      ),
    );
  }

  Future<void> _navigateToCustomerDetails(Contact contact) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CustomerDetailsScreen(contact: contact),
      ),
    );
    if (result == true) {
      final filters = _buildCurrentFilters();
      Provider.of<ContactProvider>(context, listen: false).refreshContacts(
        searchQuery: _currentSearchQuery.isEmpty ? null : _currentSearchQuery,
        filters: filters?.isEmpty == true ? null : filters,
      );
      if (mounted) setState(() {});
    } else if (result != null && result is Contact) {
      Provider.of<ContactProvider>(
        context,
        listen: false,
      ).updateContact(result);
      if (mounted) setState(() {});
    }
  }

  Future<void> _handleLocationAction(Contact contact) async {
    if (contact.latitude != null &&
        contact.longitude != null &&
        contact.latitude != 0.0 &&
        contact.longitude != 0.0) {
      final lat = contact.latitude!;
      final lng = contact.longitude!;
      if (lat < -90 || lat > 90 || lng < -180 || lng > 180) {
        CustomSnackbar.showError(context, 'Invalid location coordinates');
        return;
      }
      final url = Uri.parse('geo:$lat,$lng?q=$lat,$lng');
      if (await canLaunchUrl(url)) {
        await launchUrl(url, mode: LaunchMode.externalApplication);
      } else {
        final webUrl = Uri.parse(
          'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
        );
        if (await canLaunchUrl(webUrl)) {
          await launchUrl(webUrl, mode: LaunchMode.externalApplication);
        } else {
          await Clipboard.setData(ClipboardData(text: '$lat,$lng'));
          CustomSnackbar.showError(
            context,
            'Could not open maps. Coordinates copied to clipboard.',
          );
        }
      }
    } else {
      await _openContactLocation(contact);
    }
  }

  Future<void> showCustomerFilterBottomSheet() async {
    return _showFilterAndGroupByBottomSheet();
  }

  Future<void> _showFilterAndGroupByBottomSheet() async {
    try {
      final provider = Provider.of<ContactProvider>(context, listen: false);

      final Map<String, dynamic> tempState = {
        'showActiveOnly': _showActiveOnly,
        'showCompaniesOnly': _showCompaniesOnly,
        'showIndividualsOnly': _showIndividualsOnly,
        'showCreditBreachesOnly': _showCreditBreachesOnly,
        'selectedIndustry': _selectedIndustry,
        'selectedCountry': _selectedCountry,
        'startDate': _startDate,
        'endDate': _endDate,
        'selectedGroupBy': provider.selectedGroupBy,
      };

      await provider.fetchGroupByOptions();

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        isDismissible: true,
        enableDrag: true,
        builder: (context) => DefaultTabController(
          length: 2,
          child: StatefulBuilder(
            builder: (context, setDialogState) {
              final theme = Theme.of(context);
              final isDark = theme.brightness == Brightness.dark;

              return Container(
                height: MediaQuery.of(context).size.height * 0.8,
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF232323) : Colors.white,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(16),
                  ),
                ),
                child: SafeArea(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 20,
                          vertical: 16,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Filter & Group By',
                                style: theme.textTheme.titleMedium?.copyWith(
                                  color: isDark ? Colors.white : Colors.black87,
                                  fontSize: 18,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.of(context).pop(),
                              icon: Icon(
                                Icons.close,
                                color: isDark ? Colors.white : Colors.black54,
                              ),
                              splashRadius: 20,
                            ),
                          ],
                        ),
                      ),

                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[800] : Colors.grey[100],
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: TabBar(
                          indicator: BoxDecoration(
                            color: theme.primaryColor,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: theme.primaryColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          indicatorPadding: const EdgeInsets.all(4),
                          indicatorSize: TabBarIndicatorSize.tab,
                          dividerColor: Colors.transparent,
                          labelColor: Colors.white,
                          unselectedLabelColor: isDark
                              ? Colors.grey[400]
                              : Colors.grey[600],
                          labelStyle: const TextStyle(
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                          unselectedLabelStyle: const TextStyle(
                            fontWeight: FontWeight.w500,
                            fontSize: 14,
                          ),
                          tabs: const [
                            Tab(height: 48, text: 'Filter'),
                            Tab(height: 48, text: 'Group By'),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      Expanded(
                        child: TabBarView(
                          children: [
                            _buildCustomerFilterTab(
                              context,
                              setDialogState,
                              isDark,
                              theme,
                              provider,
                              tempState,
                            ),
                            _buildCustomerGroupByTab(
                              context,
                              setDialogState,
                              isDark,
                              theme,
                              provider,
                              tempState,
                            ),
                          ],
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.grey[850] : Colors.grey[50],
                          border: Border(
                            top: BorderSide(
                              color: isDark
                                  ? Colors.grey[700]!
                                  : Colors.grey[200]!,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: OutlinedButton(
                                onPressed: () => _clearAllFilters(
                                  setDialogState,
                                  tempState,
                                  provider,
                                ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: isDark
                                      ? Colors.white
                                      : Colors.black87,
                                  side: BorderSide(
                                    color: isDark
                                        ? Colors.grey[600]!
                                        : Colors.grey[300]!,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Clear All'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              flex: 2,
                              child: ElevatedButton(
                                onPressed: () => _applyFiltersAndGroupBy(
                                  tempState,
                                  provider,
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: theme.primaryColor,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 12,
                                  ),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                ),
                                child: const Text('Apply'),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to open filter dialog: ${e.toString()}',
        );
      }
    }
  }

  Widget _buildCustomerFilterTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    ContactProvider provider,
    Map<String, dynamic> tempState,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tempState['showActiveOnly'] == true ||
              tempState['showCompaniesOnly'] == true ||
              tempState['showIndividualsOnly'] == true ||
              tempState['showCreditBreachesOnly'] == true ||
              tempState['startDate'] != null ||
              tempState['endDate'] != null) ...[
            Text(
              'Active Filters',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? Colors.white : theme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                if (tempState['showActiveOnly'] == true)
                  Chip(
                    label: const Text(
                      'Active Only',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showActiveOnly'] = false,
                    ),
                  ),
                if (tempState['showCompaniesOnly'] == true)
                  Chip(
                    label: const Text(
                      'Companies',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showCompaniesOnly'] = false,
                    ),
                  ),
                if (tempState['showIndividualsOnly'] == true)
                  Chip(
                    label: const Text(
                      'Individuals',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showIndividualsOnly'] = false,
                    ),
                  ),
                if (tempState['showCreditBreachesOnly'] == true)
                  Chip(
                    label: const Text(
                      'Credit Breaches',
                      style: TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(
                      () => tempState['showCreditBreachesOnly'] = false,
                    ),
                  ),
                if (tempState['startDate'] != null ||
                    tempState['endDate'] != null)
                  Chip(
                    label: Text(
                      'Date: ${tempState['startDate'] != null ? DateFormat('MMM dd').format(tempState['startDate']) : '...'} - ${tempState['endDate'] != null ? DateFormat('MMM dd, yyyy').format(tempState['endDate']) : '...'}',
                      style: const TextStyle(fontSize: 13),
                    ),
                    backgroundColor: isDark
                        ? Colors.white.withOpacity(.08)
                        : theme.primaryColor.withOpacity(0.08),
                    deleteIcon: const Icon(Icons.close, size: 16),
                    onDeleted: () => setDialogState(() {
                      tempState['startDate'] = null;
                      tempState['endDate'] = null;
                    }),
                  ),
              ],
            ),
            const SizedBox(height: 16),
          ],

          Text(
            'Status',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text(
                  'Active Only',
                  style: TextStyle(fontSize: 13),
                ),
                selected: tempState['showActiveOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                onSelected: (selected) => setDialogState(
                  () => tempState['showActiveOnly'] = selected,
                ),
              ),
              ChoiceChip(
                label: const Text(
                  'Credit Breaches',
                  style: TextStyle(fontSize: 13),
                ),
                selected: tempState['showCreditBreachesOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                onSelected: (selected) => setDialogState(
                  () => tempState['showCreditBreachesOnly'] = selected,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Type',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: const Text('Companies', style: TextStyle(fontSize: 13)),
                selected: tempState['showCompaniesOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                onSelected: (selected) => setDialogState(() {
                  tempState['showCompaniesOnly'] = selected;
                  if (selected) tempState['showIndividualsOnly'] = false;
                }),
              ),
              ChoiceChip(
                label: const Text(
                  'Individuals',
                  style: TextStyle(fontSize: 13),
                ),
                selected: tempState['showIndividualsOnly'] == true,
                selectedColor: theme.primaryColor,
                backgroundColor: isDark
                    ? Colors.white.withOpacity(.08)
                    : theme.primaryColor.withOpacity(0.08),
                onSelected: (selected) => setDialogState(() {
                  tempState['showIndividualsOnly'] = selected;
                  if (selected) tempState['showCompaniesOnly'] = false;
                }),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text(
            'Date Range',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          InkWell(
            onTap: () async {
              final date = await DatePickerUtils.showStandardDatePicker(
                context: context,
                initialDate: tempState['startDate'] ?? DateTime.now(),
                firstDate: DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setDialogState(() => tempState['startDate'] = date);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tempState['startDate'] != null
                          ? 'From: ${DateFormat('MMM dd, yyyy').format(tempState['startDate'])}'
                          : 'Select start date',
                      style: TextStyle(
                        color: tempState['startDate'] != null
                            ? (isDark ? Colors.white : Colors.grey[800])
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                  ),
                  if (tempState['startDate'] != null)
                    IconButton(
                      onPressed: () =>
                          setDialogState(() => tempState['startDate'] = null),
                      icon: Icon(
                        Icons.clear,
                        size: 16,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),

          InkWell(
            onTap: () async {
              final date = await DatePickerUtils.showStandardDatePicker(
                context: context,
                initialDate: tempState['endDate'] ?? DateTime.now(),
                firstDate: tempState['startDate'] ?? DateTime(2020),
                lastDate: DateTime.now().add(const Duration(days: 365)),
              );
              if (date != null) {
                setDialogState(() => tempState['endDate'] = date);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? Colors.grey[850] : Colors.grey[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.calendar_today,
                    size: 16,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tempState['endDate'] != null
                          ? 'To: ${DateFormat('MMM dd, yyyy').format(tempState['endDate'])}'
                          : 'Select end date',
                      style: TextStyle(
                        color: tempState['endDate'] != null
                            ? (isDark ? Colors.white : Colors.grey[800])
                            : (isDark ? Colors.grey[400] : Colors.grey[600]),
                      ),
                    ),
                  ),
                  if (tempState['endDate'] != null)
                    IconButton(
                      onPressed: () =>
                          setDialogState(() => tempState['endDate'] = null),
                      icon: Icon(
                        Icons.clear,
                        size: 16,
                        color: isDark ? Colors.grey[400] : Colors.grey[600],
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildCustomerGroupByTab(
    BuildContext context,
    StateSetter setDialogState,
    bool isDark,
    ThemeData theme,
    ContactProvider provider,
    Map<String, dynamic> tempState,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tempState['selectedGroupBy'] != null) ...[
            Text(
              'Active Group By',
              style: theme.textTheme.labelMedium?.copyWith(
                color: isDark ? Colors.white : theme.primaryColor,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Chip(
              label: Text(
                provider.groupByOptions[tempState['selectedGroupBy']] ??
                    tempState['selectedGroupBy'],
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: isDark
                  ? Colors.white.withOpacity(.08)
                  : theme.primaryColor.withOpacity(0.08),
              deleteIcon: const Icon(Icons.close, size: 16),
              onDeleted: () =>
                  setDialogState(() => tempState['selectedGroupBy'] = null),
            ),
            const SizedBox(height: 16),
          ],
          Text(
            'Group By Options',
            style: theme.textTheme.labelMedium?.copyWith(
              color: isDark ? Colors.grey[400] : Colors.grey[600],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          if (provider.groupByOptions.isEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withOpacity(0.06)
                    : Colors.blue[50],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withOpacity(0.12)
                      : Colors.blue.withOpacity(0.25),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Loading group by options...',
                      style: TextStyle(
                        color: isDark ? Colors.white70 : Colors.blueGrey[800],
                        fontSize: 14,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        isDark ? Colors.white70 : Colors.blueGrey[800]!,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            ...provider.groupByOptions.entries.map((entry) {
              final isSelected = tempState['selectedGroupBy'] == entry.key;
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                child: RadioListTile<String>(
                  value: entry.key,
                  groupValue: tempState['selectedGroupBy'],
                  onChanged: (value) => setDialogState(
                    () => tempState['selectedGroupBy'] = value,
                  ),
                  title: Text(
                    entry.value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isSelected
                          ? FontWeight.w600
                          : FontWeight.w400,
                      color: isDark ? Colors.white : Colors.black87,
                    ),
                  ),
                  subtitle: Text(
                    _getGroupByDescription(entry.key),
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.grey[400] : Colors.grey[600],
                    ),
                  ),
                  activeColor: theme.primaryColor,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                  dense: true,
                ),
              );
            }),
          ],
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  String _getGroupByDescription(String field) {
    switch (field) {
      case 'user_id':
        return 'Group customers by assigned salesperson';
      case 'country_id':
        return 'Group customers by their country';
      case 'state_id':
        return 'Group customers by their state/province';
      case 'company_id':
        return 'Group customers by their company';
      case 'parent_id':
        return 'Group customers by their parent company';
      default:
        return 'Group customers by $field';
    }
  }

  void _clearAllFilters(
    StateSetter setDialogState,
    Map<String, dynamic> tempState,
    ContactProvider provider,
  ) {
    setDialogState(() {
      tempState['showActiveOnly'] = true;
      tempState['showCompaniesOnly'] = false;
      tempState['showIndividualsOnly'] = false;
      tempState['showCreditBreachesOnly'] = false;
      tempState['selectedIndustry'] = null;
      tempState['selectedCountry'] = null;
      tempState['startDate'] = null;
      tempState['endDate'] = null;
      tempState['selectedGroupBy'] = null;
    });

    setState(() {
      _showActiveOnly = true;
      _showCompaniesOnly = false;
      _showIndividualsOnly = false;
      _showCreditBreachesOnly = false;
      _selectedIndustry = null;
      _selectedCountry = null;
      _startDate = null;
      _endDate = null;
      _searchController.clear();
      _currentSearchQuery = '';
    });

    provider.clearFilters();
    provider.setGroupBy(null);
    provider.fetchContacts(searchQuery: null, filters: null);

    Navigator.of(context).pop();
    CustomSnackbar.showInfo(context, 'All filters cleared');
  }

  void _applyFiltersAndGroupBy(
    Map<String, dynamic> tempState,
    ContactProvider provider,
  ) async {
    try {
      Navigator.of(context).pop();

      setState(() {
        _showActiveOnly = tempState['showActiveOnly'] ?? true;
        _showCompaniesOnly = tempState['showCompaniesOnly'] ?? false;
        _showIndividualsOnly = tempState['showIndividualsOnly'] ?? false;
        _showCreditBreachesOnly = tempState['showCreditBreachesOnly'] ?? false;
        _selectedIndustry = tempState['selectedIndustry'];
        _selectedCountry = tempState['selectedCountry'];
        _startDate = tempState['startDate'];
        _endDate = tempState['endDate'];
      });

      provider.setFilterState(
        showActiveOnly: _showActiveOnly,
        showCompaniesOnly: _showCompaniesOnly,
        showIndividualsOnly: _showIndividualsOnly,
        showCreditBreachesOnly: _showCreditBreachesOnly,
        selectedIndustry: _selectedIndustry,
        selectedCountry: _selectedCountry,
        startDate: _startDate,
        endDate: _endDate,
      );

      final selectedGroupBy = tempState['selectedGroupBy'] as String?;
      if (selectedGroupBy != null && selectedGroupBy.isNotEmpty) {
        provider.setGroupBy(selectedGroupBy);
      } else {
        provider.setGroupBy(null);
      }

      Map<String, dynamic> filters = {};
      if (_showActiveOnly == true) filters['showActiveOnly'] = true;
      if (_showCompaniesOnly == true) filters['showCompaniesOnly'] = true;
      if (_showIndividualsOnly == true) filters['showIndividualsOnly'] = true;
      if (_showCreditBreachesOnly == true) {
        filters['showCreditBreachesOnly'] = true;
      }
      if (_selectedIndustry != null) filters['industry'] = _selectedIndustry;
      if (_selectedCountry != null) filters['country'] = _selectedCountry;
      if (_startDate != null) filters['startDate'] = _startDate;
      if (_endDate != null) filters['endDate'] = _endDate;

      provider
          .fetchContacts(
            searchQuery: _currentSearchQuery.isEmpty
                ? null
                : _currentSearchQuery,
            filters: filters.isEmpty ? null : filters,
          )
          .catchError((error) {
            if (mounted) {
              CustomSnackbar.showError(
                context,
                'Failed to apply filters: ${error.toString()}',
              );
            }
          });

      final appliedFilters = <String>[];
      if (_showActiveOnly == true) appliedFilters.add('Active Only');
      if (_showCreditBreachesOnly == true) {
        appliedFilters.add('Credit Breaches');
      }
      if (_showCompaniesOnly == true) appliedFilters.add('Companies');
      if (_showIndividualsOnly == true) appliedFilters.add('Individuals');
      if (_startDate != null || _endDate != null) {
        appliedFilters.add('Date Range');
      }

      final hasGroupBy = selectedGroupBy != null && selectedGroupBy.isNotEmpty;

      String message;
      if (appliedFilters.isEmpty && !hasGroupBy) {
        message = 'All filters cleared';
      } else {
        final parts = <String>[];
        if (appliedFilters.isNotEmpty) {
          parts.add(
            '${appliedFilters.length} filter${appliedFilters.length > 1 ? 's' : ''}',
          );
        }
        if (hasGroupBy) {
          final groupByLabel =
              provider.groupByOptions[selectedGroupBy] ?? selectedGroupBy;
          parts.add('grouped by $groupByLabel');
        }
        message = 'Applied ${parts.join(' and ')}';
      }

      if (mounted) {
        CustomSnackbar.showInfo(context, message);
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to apply filters: ${e.toString()}',
        );
      }
    }
  }

  bool _isServerUnreachableError(String error) {
    final errorString = error.toLowerCase();
    return errorString.contains('socketexception') ||
        errorString.contains('connection refused') ||
        errorString.contains('connection timeout') ||
        errorString.contains('host unreachable') ||
        errorString.contains('no route to host') ||
        errorString.contains('network is unreachable') ||
        errorString.contains('failed to connect') ||
        errorString.contains('connection failed') ||
        errorString.contains('server returned html instead of json') ||
        errorString.contains('server may be down') ||
        errorString.contains('url incorrect') ||
        errorString.contains('odoo server error') ||
        errorString.contains('unexpected response') ||
        errorString.contains('404') ||
        errorString.contains('not found') ||
        errorString.contains('500') ||
        errorString.contains('502') ||
        errorString.contains('503') ||
        errorString.contains('504');
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
        width: 64,
        height: 64,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.person, color: Colors.grey, size: 32);
        },
      ),
    );
  }
}
