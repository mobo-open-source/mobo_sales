import 'package:shared_preferences/shared_preferences.dart';

class PreferencesService {
  static const String _firstLaunchKey = 'is_first_launch';
  static const String _permissionsAskedKey = 'permissions_asked';

  SharedPreferences? _prefs;

  Future<void> initialize() async {
    try {
      _prefs = await SharedPreferences.getInstance();
    } catch (e) {
      rethrow;
    }
  }

  bool get isFirstLaunch {
    if (_prefs == null) {
      return true;
    }
    return _prefs!.getBool(_firstLaunchKey) ?? true;
  }

  Future<void> markAppLaunched() async {
    if (_prefs == null) {
      return;
    }

    try {
      await _prefs!.setBool(_firstLaunchKey, false);
    } catch (e) {}
  }

  bool get permissionsAsked {
    if (_prefs == null) {
      return false;
    }
    return _prefs!.getBool(_permissionsAskedKey) ?? false;
  }

  Future<void> markPermissionsAsked() async {
    if (_prefs == null) {
      return;
    }

    try {
      await _prefs!.setBool(_permissionsAskedKey, true);
    } catch (e) {}
  }

  Future<void> reset() async {
    if (_prefs == null) {
      return;
    }

    try {
      await _prefs!.clear();
    } catch (e) {}
  }
}
