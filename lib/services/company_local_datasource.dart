import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CompanyLocalDataSource {
  static const String _companiesKey = 'cached_companies';

  const CompanyLocalDataSource();

  String _getCacheKey(int? userId, String? database) {
    if (userId == null || database == null) return _companiesKey;

    final cleanDb = database.replaceAll(RegExp(r'[^a-zA-Z0-9]'), '_');
    return '${_companiesKey}_${cleanDb}_$userId';
  }

  Future<void> putAllCompanies(
    List<Map<String, dynamic>> companies, {
    int? userId,
    String? database,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getCacheKey(userId, database);
    final jsonList = companies.map((c) => jsonEncode(c)).toList();
    await prefs.setStringList(key, jsonList);
  }

  Future<List<Map<String, dynamic>>> getAllCompanies({
    int? userId,
    String? database,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getCacheKey(userId, database);
    final jsonList = prefs.getStringList(key);

    if (jsonList == null) return [];

    return jsonList.map((s) => jsonDecode(s) as Map<String, dynamic>).toList();
  }

  Future<void> clear({int? userId, String? database}) async {
    final prefs = await SharedPreferences.getInstance();
    final key = _getCacheKey(userId, database);
    await prefs.remove(key);
  }
}
