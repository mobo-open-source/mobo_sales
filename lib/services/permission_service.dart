import 'package:flutter/foundation.dart' show visibleForTesting;

import 'odoo_compat.dart';
import 'odoo_session_manager.dart';

class PermissionService {
  static PermissionService _instance = PermissionService._internal();
  static PermissionService get instance => _instance;
  static set instance(PermissionService instance) => _instance = instance;

  PermissionService._internal()
    : _callKwProvider = _liveCallKw,
      _userIdProvider = _liveUserId,
      _generation = null,
      _clock = DateTime.now;

  /// A service that sends its access checks through [callKw] instead of the
  /// live session, for tests. [generation] is the Odoo generation to ask as
  /// (see `odooGeneration`), or null to read it from the session; [clock]
  /// replaces `DateTime.now` so the cache lifetime can be exercised.
  @visibleForTesting
  PermissionService.forTesting({
    required OdooCallKw callKw,
    int? generation,
    DateTime Function()? clock,
    int? userId,
  }) : _callKwProvider = (() async => callKw),
       _userIdProvider = (() async => userId ?? 2),
       _generation = generation,
       _clock = clock ?? DateTime.now;

  final Future<OdooCallKw?> Function() _callKwProvider;
  final Future<int?> Function() _userIdProvider;
  final int? _generation;
  final DateTime Function() _clock;

  final Map<String, _CachedPerm> _cache = {};
  final Duration _ttl = const Duration(minutes: 5);

  /// The call_kw of the signed-in session, or null when there is none.
  static Future<OdooCallKw?> _liveCallKw() async {
    final client = await OdooSessionManager.getClient();
    return client?.callKw;
  }

  /// The signed-in user's id, or null when there is no session.
  static Future<int?> _liveUserId() async {
    final session = await OdooSessionManager.getCurrentSession();
    return session?.userId;
  }

  /// Whether the current user may do [op] (`read`, `create`, `write`,
  /// `unlink`) on [model].
  ///
  /// The question is asked through [OdooCompat.hasAccess], which picks the call
  /// the server has: `check_access_rights` was removed in Odoo 20, and its
  /// absence there used to be indistinguishable from "no" here. An answer is
  /// remembered for five minutes. A failure to ask — no session, no network, a
  /// server error — answers false but is not remembered, so the next call asks
  /// again.
  Future<bool> can(String model, String op) async {
    try {
      final key = '$model:$op';
      final now = _clock();
      final cached = _cache[key];
      if (cached != null && now.difference(cached.at) < _ttl) {
        return cached.value;
      }

      final callKw = await _callKwProvider();
      if (callKw == null) return false;

      final value = await OdooCompat.hasAccess(
        model: model,
        operation: op,
        callKw: callKw,
        generation: _generation,
      );
      _cache[key] = _CachedPerm(value, now);
      return value;
    } catch (e) {
      return false;
    }
  }

  /// Whether the current user belongs to the Odoo group [groupXmlId].
  ///
  /// Separate from [can] because Odoo gates some actions on a group rather
  /// than on the model's ACL — posting an invoice needs
  /// `account.group_account_invoice` on top of write access to
  /// `account.move`, so asking [can] alone offers the user a button the
  /// server will refuse.
  ///
  /// Remembered for five minutes, like [can]. A failure to ask answers false
  /// and is not remembered.
  Future<bool> hasGroup(String groupXmlId) async {
    try {
      final key = 'group:$groupXmlId';
      final now = _clock();
      final cached = _cache[key];
      if (cached != null && now.difference(cached.at) < _ttl) {
        return cached.value;
      }

      final callKw = await _callKwProvider();
      if (callKw == null) return false;

      final userId = await _userIdProvider();
      if (userId == null) return false;

      final value = await OdooCompat.hasGroup(
        groupXmlId: groupXmlId,
        userId: userId,
        callKw: callKw,
        generation: _generation,
      );
      _cache[key] = _CachedPerm(value, now);
      return value;
    } catch (e) {
      return false;
    }
  }

  /// Forgets every remembered answer, e.g. when the account or company changes.
  void clearCache() => _cache.clear();

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
