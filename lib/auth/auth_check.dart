import 'package:flutter/material.dart';
import 'package:loading_animation_widget/loading_animation_widget.dart';
import 'package:mobo_sales/services/biometric_context_service.dart';
import 'package:mobo_sales/screens/auth/app_lock_screen.dart';
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

  Future<Map<String, dynamic>> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final hasSeenGetStarted = prefs.getBool('hasSeenGetStarted') ?? false;
    final biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
    final hasCredentials = _hasStoredCredentials(prefs);

    return {
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
