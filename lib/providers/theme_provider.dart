import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/app_theme.dart';

/// Manages the app's light/dark theme and persists the user's preference.
class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  bool _isInitialized = false;

  ThemeProvider() {
    _initializeTheme();
  }

  ThemeMode get themeMode => _themeMode;
  bool get isInitialized => _isInitialized;

  void _initializeTheme() {
    _isInitialized = true;

    _loadThemeMode();
  }

  /// Toggles the theme between light and dark mode and saves the choice.
  Future<void> toggleTheme() async {
    _themeMode = _themeMode == ThemeMode.light
        ? ThemeMode.dark
        : ThemeMode.light;
    notifyListeners();
    await _saveThemeMode();
  }

  Future<void> _saveThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      'theme_mode',
      _themeMode == ThemeMode.dark ? 'dark' : 'light',
    );
  }

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final mode = prefs.getString('theme_mode');
    if (mode == 'dark') {
      _themeMode = ThemeMode.dark;
    } else {
      _themeMode = ThemeMode.light;
    }
    notifyListeners();
  }

  ThemeData get lightTheme => AppTheme.lightTheme;
  ThemeData get darkTheme => AppTheme.darkTheme;
}
