/// Major version of the connected Odoo server, or 0 when it cannot be read.
///
/// Handles the shapes Odoo reports: `17.0`, `17.0+e`, `saas~16.3`, `19.5a1`.
///
/// This is the number as written. To decide what the server *supports*, use
/// [odooGeneration]: an Odoo 20 pre-release writes itself as 19.
int odooMajorVersion(String? serverVersion) {
  final match = RegExp(r'\d+').firstMatch(serverVersion ?? '');
  return int.tryParse(match?.group(0) ?? '') ?? 0;
}

/// The Odoo *generation* behind [serverVersion], or 0 when it cannot be read.
///
/// Identical to [odooMajorVersion] except that `19.5` and later count as 20.
/// Odoo's development branch between 19.0 and the 20.0 release identifies
/// itself as `19.5a1` (and `saas~19.5`), yet it already carries every breaking
/// change of 20: `read_group` with a new signature, `check_access_rights`
/// removed, `res.partner.company_type` gone. A check written against the major
/// version alone would treat such a server as Odoo 19 and call APIs that no
/// longer exist, so every capability check below takes a generation.
///
/// `19.1` to `19.4` are feature releases of 19 and stay 19.
int odooGeneration(String? serverVersion) {
  final match = RegExp(r'(\d+)(?:\.(\d+))?').firstMatch(serverVersion ?? '');
  if (match == null) return 0;
  final major = int.tryParse(match.group(1)!) ?? 0;
  final minor = int.tryParse(match.group(2) ?? '') ?? 0;
  if (major == 19 && minor >= 5) return 20;
  return major;
}

// ---------------------------------------------------------------------------
// Capabilities. Each takes a generation from [odooGeneration]. An unknown
// generation (0) takes the path every release up to now has accepted, which is
// what the app did before it knew about versions; the field-pruning in
// `FieldValidationService` then recovers if the server disagrees.
// ---------------------------------------------------------------------------

/// Whether `res.partner.mobile` exists on this server.
///
/// Odoo 19 removed the field outright, merging it into `phone`. Reading or
/// writing it on 19 fails the *whole* call, so a profile save that includes
/// `mobile` silently loses phone, website and job title with it. An unknown
/// version (0) is treated as supporting it, matching every release the app
/// has actually seen.
bool odooHasPartnerMobile(int generation) => generation == 0 || generation < 19;

/// Whether `res.partner.title` (and the `res.partner.title` model) exist.
/// Removed in Odoo 19.
bool odooHasPartnerTitle(int generation) => generation == 0 || generation < 19;

/// Whether `res.partner.company_type` exists. Removed in Odoo 20, where
/// `is_company` is computed from the partner's VAT and its commercial entity
/// instead, so there is nothing to choose between "person" and "company".
bool odooHasPartnerCompanyType(int generation) =>
    generation == 0 || generation < 20;

/// Whether `res.partner.company_name` (the free-text company of a contact)
/// exists. Removed in Odoo 20 in favour of `parent_id`.
bool odooHasPartnerCompanyName(int generation) =>
    generation == 0 || generation < 20;

/// Whether `res.partner.is_company` can be set by writing it.
///
/// In Odoo 20 it is a stored computed field (a partner is a company when it is
/// its own commercial entity and has a VAT); a written value is overwritten the
/// next time the VAT changes. Before 20 it is a plain, editable boolean.
bool odooPartnerIsCompanyWritable(int generation) =>
    generation == 0 || generation < 20;

/// Whether grouped queries go through `formatted_read_group`.
///
/// Odoo 19 deprecated the old `read_group(domain, fields, groupby, …)` and
/// Odoo 20 replaced it with a different signature returning tuples.
/// `formatted_read_group(domain, groupby, aggregates, …)` — the same in 19 and
/// 20 — is the call that works on both; 17 and 18 only have the old one.
bool odooUsesFormattedReadGroup(int generation) => generation >= 19;

/// Whether the model-level access check is `has_access(operation)`.
///
/// `check_access_rights` was deprecated in 19 and removed in 20; `has_access`
/// arrived in 18. 17 and unknown servers keep `check_access_rights`.
bool odooUsesHasAccess(int generation) => generation >= 18;
