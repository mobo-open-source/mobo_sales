import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobo_sales/providers/theme_provider.dart';

void main() {
  late ThemeProvider provider;

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
  });

  group('ThemeProvider Tests', () {
    test('Initial state uses local settings (default light)', () async {
      SharedPreferences.setMockInitialValues({});
      provider = ThemeProvider();

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.themeMode, ThemeMode.light);
      expect(provider.isInitialized, true);
    });

    test('Initial state loads dark mode from prefs', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'dark'});

      provider = ThemeProvider();

      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.themeMode, ThemeMode.dark);
    });

    test('toggleTheme switches modes and saves to prefs', () async {
      SharedPreferences.setMockInitialValues({'theme_mode': 'light'});

      provider = ThemeProvider();
      await Future.delayed(Duration.zero);
      await Future.delayed(Duration.zero);

      expect(provider.themeMode, ThemeMode.light);

      await provider.toggleTheme();

      expect(provider.themeMode, ThemeMode.dark);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString('theme_mode'), 'dark');

      await provider.toggleTheme();
      expect(provider.themeMode, ThemeMode.light);
      expect(prefs.getString('theme_mode'), 'light');
    });

    test('ThemeData getters return correct themes', () {
      provider = ThemeProvider();
      expect(provider.lightTheme, isA<ThemeData>());
      expect(provider.darkTheme, isA<ThemeData>());
      expect(provider.lightTheme.brightness, Brightness.light);
      expect(provider.darkTheme.brightness, Brightness.dark);
    });
  });
}
