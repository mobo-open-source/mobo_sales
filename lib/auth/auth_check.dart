import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mobo_sales/services/biometric_context_service.dart';
import 'package:mobo_sales/screens/auth/app_lock_screen.dart';
import 'package:mobo_sales/services/odoo_session_manager.dart';
import 'package:mobo_sales/main.dart' show navigatorKey;
import 'package:mobo_sales/services/sales_access.dart';
import 'package:mobo_sales/utils/database_expiry.dart';
import 'package:mobo_sales/widgets/access_denied_dialog.dart';
import 'package:mobo_sales/widgets/custom_snackbar.dart';
import 'package:mobo_sales/home_scaffold.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthCheck extends StatefulWidget {
  final bool skipBiometric;

  const AuthCheck({super.key, this.skipBiometric = false});

  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  late final Future<Map<String, dynamic>> _authFuture = _checkAuthStatus();
  bool _navigated = false;

  /// Clears the entire stack and lands on [routeName], at most once.
  void _redirectTo(String routeName) {
    if (_navigated) return;
    _navigated = true;
    Future.microtask(() {
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil(routeName, (route) => false);
      }
    });
  }

  /// Says why the saved session was ended, then lands on the sign-in screen.
  void _explainAndRedirect(SalesAccessException problem, bool hasCredentials) {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await AccessDeniedDialog.showFor(context, problem);
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        hasCredentials ? '/login' : '/server_setup',
        (route) => false,
      );
    });
  }

  /// Lands on the sign-in screen and says there, once, that the database has
  /// expired. The message waits for the first frame of that screen.
  void _explainExpiredAndRedirect(bool hasCredentials) {
    if (_navigated) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil(
        hasCredentials ? '/login' : '/server_setup',
        (route) => false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final target = navigatorKey.currentContext;
        if (target != null && target.mounted) {
          CustomSnackbar.showError(target, DatabaseExpiredException.message);
        }
      });
    });
  }

  Future<Map<String, dynamic>> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    var isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final hasSeenGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final hasCredentials = _hasStoredCredentials(prefs);

    // A saved session is not a licence to walk in: the account may have lost its
    // Sales access, or the database its Sales module, since the last sign-in. A
    // definite "no" ends the session before any screen of the app is reached;
    // an unreachable server or an expired session says nothing and changes
    // nothing.
    //
    // The subscription comes first: a database that has expired since the last
    // sign-in ends the session before anything else is asked of the server.
    bool databaseExpired = false;
    if (isLoggedIn) {
      databaseExpired =
          await OdooSessionManager.currentSessionDatabaseExpired();
      if (databaseExpired) {
        await OdooSessionManager.logout();
        isLoggedIn = false;
      }
    }

    SalesAccessException? accessProblem;
    if (isLoggedIn) {
      accessProblem = await OdooSessionManager.currentSessionAccessProblem();
      if (accessProblem != null) {
        await OdooSessionManager.logout();
        isLoggedIn = false;
      }
    }

    return {
      'databaseExpired': databaseExpired,
      'accessProblem': accessProblem,
      'isLoggedIn': isLoggedIn,
      'hasSeenGetStarted': hasSeenGetStarted,
      'biometricEnabled': biometricEnabled,
      'hasCredentials': hasCredentials,
    };
  }

  bool _hasStoredCredentials(SharedPreferences prefs) {
    final savedUrl = prefs.getString('lastUrl');
    final savedDatabase = prefs.getString('lastDatabase');
    final savedUsername = prefs.getString('lastUsername');

    return savedUrl != null &&
        savedUrl.isNotEmpty &&
        savedDatabase != null &&
        savedDatabase.isNotEmpty &&
        savedUsername != null &&
        savedUsername.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, dynamic>>(
      future: _authFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context);
        } else if (snapshot.hasError || snapshot.data == null) {
          _redirectTo('/get_started');
          return _buildLoadingScreen(context);
        }

        if (snapshot.data!['databaseExpired'] == true) {
          _explainExpiredAndRedirect(snapshot.data!['hasCredentials']!);
          return _buildLoadingScreen(context);
        }

        final accessProblem =
            snapshot.data!['accessProblem'] as SalesAccessException?;
        if (accessProblem != null) {
          _explainAndRedirect(accessProblem, snapshot.data!['hasCredentials']!);
          return _buildLoadingScreen(context);
        }

        final isLoggedIn = snapshot.data!['isLoggedIn']!;
        final hasSeenGetStarted = snapshot.data!['hasSeenGetStarted']!;
        final biometricEnabled = snapshot.data!['biometricEnabled']!;
        final hasCredentials = snapshot.data!['hasCredentials']!;

        final biometricContext = BiometricContextService();
        final shouldSkipBiometric =
            widget.skipBiometric || biometricContext.shouldSkipBiometric;

        if (biometricEnabled && isLoggedIn && !shouldSkipBiometric) {
          if (!_navigated) {
            _navigated = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                    builder: (context) => AppLockScreen(
                      onAuthenticationSuccess: () {
                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const HomeScaffold(),
                          ),
                        );
                      },
                    ),
                  ),
                  (route) => false,
                );
              }
            });
          }
          return _buildLoadingScreen(context);
        } else if (isLoggedIn) {
          return const HomeScaffold();
        } else if (!hasSeenGetStarted) {
          _redirectTo('/get_started');
          return _buildLoadingScreen(context);
        } else {
          _redirectTo(hasCredentials ? '/login' : '/server_setup');
          return _buildLoadingScreen(context);
        }
      },
    );
  }

  Widget _buildLoadingScreen(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: isDark ? Colors.black : Colors.white,
      body: Center(
        child: Semantics(
          label: 'Loading, please wait',
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              LoadingAnimationWidget.staggeredDotsWave(
                color: isDark ? Colors.white : theme.colorScheme.primary,
                size: 50,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
