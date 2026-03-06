import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:provider/provider.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../main.dart';
import 'in_app_webview_screen.dart';
import 'dashboard_screen.dart';
import '../../utils/app_theme.dart';
import '../../services/session_service.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/last_opened_provider.dart';
import '../../widgets/custom_snackbar.dart';
import '../../services/biometric_service.dart';

enum SettingsSection { profile, appearance, preferences, support, account }

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, this.initialSection});

  final SettingsSection? initialSection;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _isLoading = false;
  int _cacheUpdateKey = 0;

  bool _isAppLockEnabled = false;
  bool _isBiometricAvailable = false;
  String _authStatusDescription = 'Checking authentication status...';

  final ScrollController _scrollController = ScrollController();
  final _appearanceKey = GlobalKey();
  final _preferencesKey = GlobalKey();
  final _supportKey = GlobalKey();
  final _accountKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _initializeSettings();
    _loadAuthSettings();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();

      try {
        context.read<SettingsProvider>().calculateCacheSize();
      } catch (_) {}
    });
  }

  Widget _ProfileChip({
    required IconData icon,
    required String label,
    required bool isDark,
  }) {
    final bg = isDark ? Colors.grey[850]! : Colors.grey[100]!;
    final fg = isDark ? Colors.white : Colors.black87;
    final ic = isDark ? Colors.white : Colors.black54;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark ? Colors.grey[700]! : Colors.grey[300]!,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: ic),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openInAppWebPage(Uri url, {String? title}) async {
    if (!mounted) return;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) =>
              InAppWebViewScreen(url: url.toString(), title: title),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      CustomSnackbar.showError(context, 'Could not open page. ${e.toString()}');
    }
  }

  Future<void> _launchUrlSmart(String url, {String? title}) async {
    final Uri uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      _openInAppWebPage(uri, title: title);
    }
  }

  Widget _buildShimmerBox({
    required double width,
    required double height,
    double borderRadius = 8,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final baseColor = isDark ? Colors.grey.shade800 : Colors.grey.shade300;

    return Shimmer.fromColors(
      baseColor: baseColor,
      highlightColor: isDark ? Colors.grey.shade600 : Colors.grey.shade100,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: isDark ? Colors.grey.shade700 : Colors.white,
          borderRadius: BorderRadius.circular(borderRadius),
        ),
      ),
    );
  }

  Future<void> _initializeSettings() async {
    final settingsProvider = context.read<SettingsProvider>();
    await settingsProvider.initialize();
  }

  Future<void> _loadAuthSettings() async {
    try {
      final isEnabled = await BiometricService.isBiometricEnabled();
      final isAvailable = await BiometricService.isBiometricAvailable();
      final description = isAvailable
          ? (isEnabled
                ? 'Biometric authentication is enabled'
                : 'Biometric authentication is available but disabled')
          : 'Biometric authentication is not available on this device';

      if (mounted) {
        setState(() {
          _isAppLockEnabled = isEnabled;
          _isBiometricAvailable = isAvailable;
          _authStatusDescription = description;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _authStatusDescription = 'Authentication status unavailable';
        });
      }
    }
  }

  Future<void> _toggleAppLock(bool enabled) async {
    try {
      if (enabled) {
        final canAuthenticate =
            await BiometricService.authenticateWithBiometrics(
              reason: 'Authenticate to enable biometric login',
            );
        if (!canAuthenticate) {
          if (mounted) {
            CustomSnackbar.showError(
              context,
              'Authentication failed. Biometric authentication not enabled.',
            );
          }
          return;
        }
      }

      await BiometricService.setBiometricEnabled(enabled);
      await _loadAuthSettings();

      if (mounted) {
        CustomSnackbar.showSuccess(
          context,
          enabled
              ? 'Biometric authentication enabled successfully'
              : 'Biometric authentication disabled',
        );
      }
    } catch (e) {
      if (mounted) {
        CustomSnackbar.showError(
          context,
          'Failed to ${enabled ? 'enable' : 'disable'} biometric authentication: $e',
        );
      }
    }
  }

  void _scrollToInitialSection() {
    if (widget.initialSection == null) return;
    final contextMap = <SettingsSection, BuildContext?>{
      SettingsSection.appearance: _appearanceKey.currentContext,
      SettingsSection.preferences: _preferencesKey.currentContext,
      SettingsSection.support: _supportKey.currentContext,
      SettingsSection.account: _accountKey.currentContext,
      SettingsSection.profile: null,
    };

    final targetContext = contextMap[widget.initialSection!];
    if (targetContext != null) {
      Scrollable.ensureVisible(
        targetContext,
        duration: Duration.zero,
        alignment: 0.0,
      );
    } else if (widget.initialSection == SettingsSection.profile) {
      _scrollController.jumpTo(0);
    }
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
                      color: isDark
                          ? Colors.grey[700]!
                          : Theme.of(
                              context,
                            ).colorScheme.outline.withOpacity(0.5),
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
                    style: TextStyle(fontWeight: FontWeight.w500),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final backgroundColor = isDark ? Colors.grey[900]! : Colors.grey[50]!;
    final cardColor = isDark ? Colors.grey[900] : Colors.grey[50];

    return Scaffold(
      backgroundColor: backgroundColor,
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
        backgroundColor: cardColor,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: Icon(
            HugeIcons.strokeRoundedArrowLeft01,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settingsProvider, child) {
          if (settingsProvider.error != null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              CustomSnackbar.showError(context, settingsProvider.error!);
            });
          }

          return ListView(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            children: [
              KeyedSubtree(
                key: _appearanceKey,
                child: _buildSectionCard(
                  context,
                  'Appearance',
                  HugeIcons.strokeRoundedPaintBoard,
                  [
                    _buildSwitchTile(
                      context,
                      'Dark Mode',
                      'Switch between light and dark themes',
                      HugeIcons.strokeRoundedMoon02,
                      Theme.of(context).brightness == Brightness.dark,
                      (value) async {
                        final themeProvider = context.read<ThemeProvider>();
                        themeProvider.toggleTheme();
                        await settingsProvider.updateDarkMode(value);

                        if (mounted) {
                          CustomSnackbar.showSuccess(
                            context,
                            'Theme changed to ${value ? 'dark' : 'light'} mode',
                          );
                        }
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _buildSectionCard(
                context,
                'Security',
                HugeIcons.strokeRoundedSecurity,
                [_buildBiometricTile(context)],
              ),

              const SizedBox(height: 16),

              KeyedSubtree(
                key: _preferencesKey,
                child: _buildSectionCard(
                  context,
                  'Language & Region',
                  HugeIcons.strokeRoundedSettings02,
                  [
                    _buildOdooDropdownTile(
                      context,
                      'Language',
                      'Select your preferred language',
                      HugeIcons.strokeRoundedTranslate,
                      settingsProvider.selectedLanguage,
                      settingsProvider.availableLanguages,
                      settingsProvider.isLoadingLanguages,
                      (value) async {
                        await settingsProvider.updateLanguage(value!);
                        if (!mounted) return;
                        if (settingsProvider.error != null) {
                          CustomSnackbar.showError(
                            context,
                            'Failed to update language: ${settingsProvider.error}',
                          );
                        } else {
                          CustomSnackbar.showSuccess(
                            context,
                            'Language updated to ${settingsProvider.getLanguageDisplayName(value)}',
                          );
                        }
                      },
                      displayKey: 'name',
                      valueKey: 'code',
                      lastUpdated: settingsProvider.languagesUpdatedAt,
                    ),
                    _buildOdooDropdownTile(
                      context,
                      'Currency',
                      'Default currency for transactions',
                      HugeIcons.strokeRoundedDollar01,
                      settingsProvider.selectedCurrency,
                      settingsProvider.availableCurrencies,
                      settingsProvider.isLoadingCurrencies,
                      (value) async {
                        await settingsProvider.updateCurrency(value!);
                        if (!mounted) return;
                        if (settingsProvider.error != null) {
                          CustomSnackbar.showError(
                            context,
                            'Failed to update currency: ${settingsProvider.error}',
                          );
                        } else {
                          CustomSnackbar.showSuccess(
                            context,
                            'Currency updated to ${settingsProvider.getCurrencyDisplayName(value)}',
                          );
                        }
                      },
                      displayKey: 'full_name',
                      valueKey: 'name',
                      lastUpdated: settingsProvider.currenciesUpdatedAt,
                    ),
                    _buildOdooDropdownTile(
                      context,
                      'Timezone',
                      'Your local timezone',
                      HugeIcons.strokeRoundedClock01,
                      settingsProvider.selectedTimezone,
                      settingsProvider.availableTimezones,
                      settingsProvider.isLoadingTimezones,
                      (value) async {
                        await settingsProvider.updateTimezone(value!);
                        if (!mounted) return;
                        if (settingsProvider.error != null) {
                          CustomSnackbar.showError(
                            context,
                            'Failed to update timezone: ${settingsProvider.error}',
                          );
                        } else {
                          CustomSnackbar.showSuccess(
                            context,
                            'Timezone updated to ${settingsProvider.getTimezoneDisplayName(value)}',
                          );
                        }
                      },
                      displayKey: 'name',
                      valueKey: 'code',
                      lastUpdated: settingsProvider.timezonesUpdatedAt,
                    ),
                  ],
                  headerTrailing: Builder(
                    builder: (ctx) {
                      final isDark =
                          Theme.of(ctx).brightness == Brightness.dark;
                      final sectionLoading =
                          settingsProvider.isLoadingLanguages ||
                          settingsProvider.isLoadingCurrencies ||
                          settingsProvider.isLoadingTimezones;

                      return IconButton(
                        tooltip: 'Refresh',
                        onPressed: () async {
                          await Future.wait([
                            settingsProvider.fetchAvailableLanguages(
                              markManual: true,
                            ),
                            settingsProvider.fetchAvailableCurrencies(
                              markManual: true,
                            ),
                            settingsProvider.fetchAvailableTimezones(
                              markManual: true,
                            ),
                          ]);
                          if (!mounted) return;

                          CustomSnackbar.showInfo(
                            ctx,
                            'Language & Region refreshed',
                          );
                        },
                        icon: Icon(
                          Icons.refresh,
                          size: 18,
                          color: isDark ? Colors.grey[300] : Colors.grey[600],
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        padding: const EdgeInsets.all(4),
                        splashRadius: 16,
                      );
                    },
                  ),
                ),
              ),

              const SizedBox(height: 16),

              KeyedSubtree(
                key: _supportKey,
                child: _buildSectionCard(
                  context,
                  'Help & Support',
                  HugeIcons.strokeRoundedCustomerSupport,
                  [
                    _buildActionTile(
                      context,
                      'Odoo Help Center',
                      'Documentation, guides and resources',
                      HugeIcons.strokeRoundedHelpCircle,
                      () => _openInAppWebPage(
                        Uri.parse('https://www.odoo.com/documentation'),
                        title: 'Odoo Help Center',
                      ),
                    ),
                    _buildActionTile(
                      context,
                      'Odoo Support',
                      'Create a ticket with Odoo Support',
                      HugeIcons.strokeRoundedCustomerSupport,
                      () => _openInAppWebPage(
                        Uri.parse('https://www.odoo.com/help'),
                        title: 'Odoo Support',
                      ),
                    ),
                    _buildActionTile(
                      context,
                      'Odoo Community Forum',
                      'Ask the community for help',
                      HugeIcons.strokeRoundedUserGroup,
                      () => _openInAppWebPage(
                        Uri.parse('https://www.odoo.com/forum/help-1'),
                        title: 'Odoo Forum',
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              _buildSectionCard(
                context,
                'About',
                HugeIcons.strokeRoundedBuilding06,
                [_buildAboutContent(context)],
              ),

              const SizedBox(height: 32),
            ],
          );
        },
      ),
    );
  }

  Widget _buildSectionCard(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children, {
    Widget? headerTrailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardColor = isDark ? Colors.grey[850]! : Colors.white;

    return Container(
      decoration: BoxDecoration(
        color: cardColor,
        borderRadius: BorderRadius.circular(12),

        boxShadow: [
          BoxShadow(
            color: isDark
                ? Colors.black.withOpacity(0.05)
                : Colors.black.withOpacity(0.05),
            blurRadius: 16,
            spreadRadius: 2,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isDark ? Colors.white : Colors.black,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ),
                if (headerTrailing != null) headerTrailing,
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    bool value,
    Function(bool) onChanged,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: SizedBox(
        width: 36,
        height: 36,

        child: Icon(
          icon,
          color: isDark ? Colors.grey[400] : Colors.black,
          size: 20,
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 16,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 14,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
          height: 1.3,
        ),
      ),
      trailing: _buildModernSwitch(value, onChanged, isDark),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    );
  }

  Widget _buildModernSwitch(bool value, Function(bool) onChanged, bool isDark) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 56,
        height: 32,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: value
              ? AppTheme.primaryColor
              : isDark
              ? Colors.transparent
              : AppTheme.primaryColor.withOpacity(0.06),
          border: Border.all(
            color: value
                ? AppTheme.primaryColor
                : (isDark
                      ? Colors.grey[400]!
                      : AppTheme.primaryColor.withOpacity(1)),
            width: 2,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: 24,
            height: 24,
            margin: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? Colors.white : AppTheme.primaryColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.15),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    String value,
    List<String> options,
    Function(String?) onChanged,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListTile(
      leading: Icon(
        icon,
        color: isDark ? Colors.grey[400] : Colors.grey[600],
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          color: isDark ? Colors.white : Colors.black87,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: isDark ? Colors.grey[400] : Colors.grey[600],
        ),
      ),
      trailing: DropdownButton<String>(
        value: value,
        onChanged: onChanged,
        underline: const SizedBox(),
        items: options.map((String option) {
          return DropdownMenuItem<String>(value: option, child: Text(option));
        }).toList(),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildActionTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback? onTap, {
    bool isDestructive = false,
    Widget? trailing,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDestructive
        ? Colors.red
        : (isDark ? Colors.white : Colors.black87);

    return ListTile(
      leading: Icon(
        icon,
        color: isDestructive
            ? Colors.red
            : (isDark ? Colors.grey[400] : Colors.black),
        size: 22,
      ),
      title: Text(
        title,
        style: TextStyle(fontWeight: FontWeight.w500, color: textColor),
      ),
      subtitle: subtitle.isNotEmpty
          ? Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            )
          : null,
      trailing:
          trailing ??
          Icon(
            HugeIcons.strokeRoundedArrowRight01,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 18,
          ),
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  String _formatLastUpdated(DateTime? dt) {
    if (dt == null) return '';
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes} min ago';
    if (diff.inHours < 24) return '${diff.inHours} hr ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }

  Widget _buildBiometricTile(BuildContext context) {
    final IconData icon = _isBiometricAvailable
        ? HugeIcons.strokeRoundedFingerprintScan
        : HugeIcons.strokeRoundedLockPassword;

    return _buildSwitchTile(
      context,
      'App Lock',
      _authStatusDescription,
      icon,
      _isAppLockEnabled,
      (bool value) {
        if (_isBiometricAvailable) {
          _toggleAppLock(value);
        } else {
          CustomSnackbar.showError(
            context,
            'Biometric authentication not available on this device',
          );
        }
      },
    );
  }

  Widget _buildOdooDropdownTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    String value,
    List<Map<String, dynamic>> options,
    bool isLoading,
    Function(String?) onChanged, {
    required String displayKey,
    required String valueKey,
    DateTime? lastUpdated,
    VoidCallback? onRefresh,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final bool hasCurrent = options.any((option) => option[valueKey] == value);
    final List<Map<String, dynamic>> effectiveOptions = hasCurrent
        ? options
        : [
            {valueKey: value, displayKey: value},
            ...options,
          ];

    return ListTile(
      leading: Icon(
        icon,
        color: isDark ? Colors.grey[400] : Colors.black,
        size: 22,
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.w500,
                color: isDark ? Colors.white : Colors.black87,
              ),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ),
          if (onRefresh != null)
            IconButton(
              tooltip: 'Refresh',
              onPressed: isLoading ? null : onRefresh,
              icon: Icon(
                Icons.refresh,
                size: 18,
                color: isLoading
                    ? (isDark ? Colors.grey[700] : Colors.grey[400])
                    : (isDark ? Colors.grey[300] : Colors.grey[600]),
              ),
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
              padding: const EdgeInsets.all(4),
              splashRadius: 16,
            ),
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          if (lastUpdated != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Last updated • ${_formatLastUpdated(lastUpdated)}',
                style: TextStyle(
                  fontSize: 11,
                  color: isDark ? Colors.grey[500] : Colors.grey[500],
                ),
              ),
            ),
        ],
      ),
      trailing: (isLoading && options.isEmpty)
          ? _buildShimmerBox(width: 140, height: 32, borderRadius: 8)
          : SizedBox(
              width: MediaQuery.of(context).size.width * .35,
              child: DropdownButton<String>(
                isExpanded: true,
                value:
                    effectiveOptions.any((option) => option[valueKey] == value)
                    ? value
                    : null,
                onChanged: onChanged,
                underline: const SizedBox(),
                selectedItemBuilder: (context) {
                  return effectiveOptions.map((option) {
                    final String displayText =
                        (option[displayKey] ?? option[valueKey] ?? '')
                            .toString();
                    return Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        displayText,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 14,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                      ),
                    );
                  }).toList();
                },
                items: effectiveOptions.map((Map<String, dynamic> option) {
                  final String displayText =
                      (option[displayKey] ?? option[valueKey] ?? '').toString();
                  final String optionValue = option[valueKey];

                  final bool isLanguageDropdown = title == 'Language';
                  final bool isEnglish = optionValue == 'en_US';
                  final bool isEnabled = !isLanguageDropdown || isEnglish;

                  return DropdownMenuItem<String>(
                    value: option[valueKey],
                    enabled: isEnabled,
                    child: Text(
                      displayText,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 14,
                        color: isEnabled
                            ? (isDark ? Colors.white : Colors.black87)
                            : (isDark ? Colors.grey[600] : Colors.grey[400]),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    );
  }

  Widget _buildSliderTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    double value,
    double min,
    double max,
    Function(double) onChanged,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        ListTile(
          leading: Icon(
            icon,
            color: isDark ? Colors.grey[400] : Colors.grey[600],
            size: 22,
          ),
          title: Text(
            title,
            style: TextStyle(
              fontWeight: FontWeight.w500,
              color: isDark ? Colors.white : Colors.black87,
            ),
          ),
          subtitle: Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: isDark ? Colors.grey[400] : Colors.grey[600],
            ),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 4,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Slider(
            value: value,
            min: min,
            max: max,
            divisions: ((max - min) / 5).round(),
            activeColor: Theme.of(context).primaryColor,
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }

  Widget _buildAboutContent(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textPrimary = isDark ? Colors.white : Colors.black87;
    final textSecondary = isDark ? Colors.grey[400] : Colors.grey[600];

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: Column(
        children: [
          _buildActionTile(
            context,
            'Visit Website',
            'www.cybrosys.com',
            HugeIcons.strokeRoundedGlobe02,
            () => _launchUrlSmart(
              'https://www.cybrosys.com/',
              title: 'Our Website',
            ),
          ),
          _buildActionTile(
            context,
            'Contact Us',
            'info@cybrosys.com',
            HugeIcons.strokeRoundedMail01,
            () => _launchUrlSmart('mailto:info@cybrosys.com'),
          ),

          if (Theme.of(context).platform == TargetPlatform.android)
            _buildActionTile(
              context,
              'More Apps',
              'View our other apps on Play Store',
              HugeIcons.strokeRoundedPlayStore,
              () => _launchUrlSmart(
                'https://play.google.com/store/apps/dev?id=7163004064816759344&pli=1',
                title: 'Play Store',
              ),
            ),
          if (Theme.of(context).platform == TargetPlatform.iOS)
            _buildActionTile(
              context,
              'More Apps',
              'View our other apps on App Store',
              HugeIcons.strokeRoundedAppStore,
              () => _launchUrlSmart(
                'https://apps.apple.com/in/developer/cybrosys-technologies/id1805306445',
                title: 'App Store',
              ),
            ),

          const SizedBox(height: 16),
          Divider(color: isDark ? Colors.grey[800] : Colors.grey[200]),
          const SizedBox(height: 16),

          Text(
            'Follow Us',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w500,
              color: textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _buildSocialButton(
                context,
                'assets/facebook.png',
                const Color(0xFF1877F2),
                'Facebook',
                () => _launchUrlSmart(
                  'https://www.facebook.com/cybrosystechnologies',
                  title: 'Facebook',
                ),
              ),
              _buildSocialButton(
                context,
                'assets/linkedin.png',
                const Color(0xFF0077B5),
                'LinkedIn',
                () => _launchUrlSmart(
                  'https://www.linkedin.com/company/cybrosys/',
                  title: 'LinkedIn',
                ),
              ),
              _buildSocialButton(
                context,
                'assets/instagram.png',
                const Color(0xFFE4405F),
                'Instagram',
                () => _launchUrlSmart(
                  'https://www.instagram.com/cybrosystech/',
                  title: 'Instagram',
                ),
              ),
              _buildSocialButton(
                context,
                'assets/youtube.png',
                const Color(0xFFFF0000),
                'YouTube',
                () => _launchUrlSmart(
                  'https://www.youtube.com/channel/UCKjWLm7iCyOYINVspCSanjg',
                  title: 'YouTube',
                ),
              ),
            ],
          ),

          const SizedBox(height: 24),
          Text(
            '© ${DateTime.now().year} Cybrosys Technologies',
            style: TextStyle(fontSize: 12, color: textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildSocialButton(
    BuildContext context,
    String imagePath,
    Color underlineColor,
    String label,
    VoidCallback onPressed,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onPressed,
          child: Container(
            width: 46,
            height: 46,
            padding: const EdgeInsets.all(12),
            child: Image.asset(
              imagePath,
              width: 24,
              height: 24,
              fit: BoxFit.contain,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Container(
          width: 48,
          height: 3,
          decoration: BoxDecoration(
            color: underlineColor,
            borderRadius: BorderRadius.circular(1.5),
          ),
        ),
      ],
    );
  }
}
