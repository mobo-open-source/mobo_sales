/// Major version of the connected Odoo server, or 0 when it cannot be read.
///
/// Handles the shapes Odoo reports: `17.0`, `17.0+e`, `saas~16.3`.
int odooMajorVersion(String? serverVersion) {
  final match = RegExp(r'\d+').firstMatch(serverVersion ?? '');
  return int.tryParse(match?.group(0) ?? '') ?? 0;
}

/// Whether `res.partner.mobile` exists on this server.
///
/// Odoo 19 removed the field outright, merging it into `phone`. Reading or
/// writing it on 19 fails the *whole* call, so a profile save that includes
/// `mobile` silently loses phone, website and job title with it. An unknown
/// version (0) is treated as supporting it, matching every release the app
/// has actually seen.
bool odooHasPartnerMobile(int major) => major == 0 || major < 19;
