import 'odoo_session_manager.dart';

class PermissionService {
  static PermissionService _instance = PermissionService._internal();
  static PermissionService get instance => _instance;
  static set instance(PermissionService instance) => _instance = instance;

  PermissionService._internal();

  final Map<String, _CachedPerm> _cache = {};
  final Duration _ttl = const Duration(minutes: 5);

  Future<bool> can(String model, String op) async {
    try {
      final key = '$model:$op';
      final now = DateTime.now();
      final cached = _cache[key];
      if (cached != null && now.difference(cached.at) < _ttl) {
        return cached.value;
      }

      final client = await OdooSessionManager.getClient();
      if (client == null) return false;

      final result = await client.callKw({
        'model': model,
        'method': 'check_access_rights',
        'args': [op],
        'kwargs': {'raise_exception': false},
      });

      final value = result is bool ? result : false;
      _cache[key] = _CachedPerm(value, now);
      return value;
    } catch (e) {
      return false;
    }
  }

  Future<bool> canRead(String model) => can(model, 'read');
  Future<bool> canCreate(String model) => can(model, 'create');
  Future<bool> canWrite(String model) => can(model, 'write');
  Future<bool> canUnlink(String model) => can(model, 'unlink');

  Future<void> ensureCan(
    String model,
    String op, {
    String? onDeniedMessage,
  }) async {
    final ok = await can(model, op);
    if (!ok) {
      throw Exception(
        onDeniedMessage ?? 'You do not have permission to $op on $model.',
      );
    }
  }
}

class _CachedPerm {
  final bool value;
  final DateTime at;
  _CachedPerm(this.value, this.at);
}
