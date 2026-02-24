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
      future: _checkAuthStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return _buildLoadingScreen(context);
        } else if (snapshot.hasError || snapshot.data == null) {
          Future.microtask(() {
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/get_started');
            }
          });
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
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              Navigator.pushReplacement(
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
              );
            }
          });
          return _buildLoadingScreen(context);
        } else if (isLoggedIn) {
          return const HomeScaffold();
        } else if (!hasSeenGetStarted) {
          Future.microtask(() {
            if (context.mounted) {
              Navigator.pushReplacementNamed(context, '/get_started');
            }
          });
          return _buildLoadingScreen(context);
        } else {
          Future.microtask(() {
            if (context.mounted) {
              if (hasCredentials) {
                Navigator.pushReplacementNamed(context, '/login');
              } else {
                Navigator.pushReplacementNamed(context, '/server_setup');
              }
            }
          });
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
