/// What the app needs from the server before a user may in: the Sales module,
/// and the user's Sales access.
///
/// In Odoo's user form the second is the "Sales" line under Application
/// Access: "No" means the user belongs to none of the Sales groups.
/// `sales_team.group_sale_salesman` is the lowest of them and every higher
/// level (all documents, administrator) implies it, so membership of that one
/// group is the question. A user who is not in it — a portal user, or an
/// internal user with only Invoicing or Inventory — is not let in.
///
/// The module is the other half: a database without it has no quotations at
/// all, and the app has nothing to show for any user. (`sales_team` alone is not
/// enough — CRM installs it — so the probe is for `sale` itself.)
enum SalesAccessStatus {
  /// The module is installed and the user is in the group.
  granted,

  /// The module is installed and the user is not in the group.
  denied,

  /// The database has no Sales module.
  moduleMissing,

  /// The user is a portal (or public) user, not an internal one. Portal users
  /// cannot use the app at all, whatever else they are given.
  portalUser,

  /// The server could not be asked, or did not answer with a yes or no.
  unverified,
}

/// Sends one `call_kw` request and returns Odoo's whole JSON-RPC reply — the map
/// with a `result` or an `error` — so the caller can read the server's own error
/// name and message. Throws only when the server could not be reached.
typedef SalesRpc =
    Future<Map<String, dynamic>> Function(
      String model,
      String method,
      List<dynamic> args,
    );

class SalesAccess {
  const SalesAccess._();

  /// The group a user must belong to; the same external id on Odoo 17 to 20.
  static const groupXmlId = 'sales_team.group_sale_salesman';

  /// Every internal user is in it; portal and public users are not. Asked
  /// rather than looking for the portal group itself: Odoo 20 no longer puts a
  /// portal user in `base.group_portal`, but still keeps them out of this one.
  static const internalGroupXmlId = 'base.group_user';

  /// An external id only the `sale` module creates, and which exists, under the
  /// same name, on Odoo 17 to 20: the Sales app's root menu.
  static const moduleProbe = ['sale', 'sale_menu_root'];

  /// Looks the module and the group up together and says what they add up to.
  ///
  /// The two questions are asked at once: the answer is "granted" only when
  /// both hold, so there is nothing to save by asking them one after the other.
  static Future<SalesAccessStatus> check({
    required int majorVersion,
    required int userId,
    required SalesRpc rpc,
    String group = groupXmlId,
  }) async {
    final installed = _moduleInstalled(rpc);
    final internal = _inGroup(majorVersion, userId, internalGroupXmlId, rpc);
    final inGroup = _inGroup(majorVersion, userId, group, rpc);

    if (!await installed) return SalesAccessStatus.moduleMissing;
    if (await internal == false) return SalesAccessStatus.portalUser;
    final member = await inGroup;
    if (member == null) return SalesAccessStatus.unverified;
    return member ? SalesAccessStatus.granted : SalesAccessStatus.denied;
  }

  /// False only when the server says the module's external id does not exist.
  /// `ir.model.data.check_object_reference` answers for any signed-in user (it
  /// reads the id with sudo) and raises "External ID not found in the system"
  /// for an id no installed module created. Any other outcome — a reply, an
  /// error of another kind, no network — does not show the module missing, so
  /// the group question decides.
  static Future<bool> _moduleInstalled(SalesRpc rpc) async {
    try {
      final reply = await rpc(
        'ir.model.data',
        'check_object_reference',
        List<dynamic>.of(moduleProbe),
      );
      return !isMissingExternalId(reply);
    } catch (_) {
      return true;
    }
  }

  /// Whether [reply] is Odoo's "External ID not found in the system" error.
  static bool isMissingExternalId(Map<String, dynamic> reply) {
    final error = reply['error'];
    if (error is! Map) return false;
    final data = error['data'];
    final text = [
      if (data is Map) data['message'],
      error['message'],
    ].join(' ').toLowerCase();
    return text.contains('external id not found');
  }

  /// Whether [userId] belongs to [group]: true, false, or null when the server
  /// did not answer with a yes or no.
  ///
  /// `res.users.has_group` exists on every Odoo from 17 to 20 but not with one
  /// signature: it is a model method on 17 (`has_group(group)`), and on 18 and
  /// later it works on a record (`has_group([uid], group)`). Sending the wrong
  /// shape is a server error, not a wrong answer, so the shape for
  /// [majorVersion] goes first and the other is the fallback.
  static Future<bool?> _inGroup(
    int majorVersion,
    int userId,
    String group,
    SalesRpc rpc,
  ) async {
    final onRecord = <dynamic>[
      [userId],
      group,
    ];
    final onModel = <dynamic>[group];
    final attempts = majorVersion <= 17
        ? [onModel, onRecord]
        : [onRecord, onModel];

    for (final args in attempts) {
      try {
        final reply = await rpc('res.users', 'has_group', args);
        final answer = reply['result'];
        if (answer is bool) return answer;
      } catch (_) {
        // No answer for this shape: try the other.
      }
    }
    return null;
  }
}

/// Thrown by a sign-in that must not go on: the account authenticated but may
/// not use the app, or that could not be checked.
///
/// The text deliberately avoids the words "access denied": the account-switch
/// code reads those as a wrong password and asks for a new one, which is not
/// the problem here.
class SalesAccessException implements Exception {
  const SalesAccessException._(this.status, this.message);

  const SalesAccessException.denied()
    : this._(
        SalesAccessStatus.denied,
        "This account doesn't have Sales access.",
      );

  const SalesAccessException.portalUser()
    : this._(SalesAccessStatus.portalUser, "Portal users can't use this app.");

  const SalesAccessException.moduleMissing()
    : this._(
        SalesAccessStatus.moduleMissing,
        "The Sales module isn't installed on this database.",
      );

  const SalesAccessException.unverified()
    : this._(
        SalesAccessStatus.unverified,
        "Couldn't check this account's Sales access. Please try again.",
      );

  /// The exception for a status that is not [SalesAccessStatus.granted], or
  /// null for one that is.
  static SalesAccessException? from(SalesAccessStatus status) {
    switch (status) {
      case SalesAccessStatus.granted:
        return null;
      case SalesAccessStatus.denied:
        return const SalesAccessException.denied();
      case SalesAccessStatus.portalUser:
        return const SalesAccessException.portalUser();
      case SalesAccessStatus.moduleMissing:
        return const SalesAccessException.moduleMissing();
      case SalesAccessStatus.unverified:
        return const SalesAccessException.unverified();
    }
  }

  final SalesAccessStatus status;
  final String message;

  @override
  String toString() => 'SalesAccessException: $message';
}
