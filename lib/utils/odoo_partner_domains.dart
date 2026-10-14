import 'odoo_version.dart';

/// The search domain for the partners a person can be attached to as their
/// "Related Company" (`res.partner.parent_id`), narrowed by [query] on the
/// name.
///
/// Up to Odoo 19 that is every partner flagged `is_company`, a plain boolean.
/// In Odoo 20 `is_company` is computed: true only for a partner that is its
/// own commercial entity *and* has a VAT (odoo/addons/base/models/
/// res_partner.py, `_compute_is_company`). A company without a VAT number
/// would never be offered, so Odoo 20's own partner form picks from the
/// partners that have no parent instead (`domain="[('parent_id', '=', False)]"`
/// on `parent_id`, in res_partner_views.xml), and so does this.
///
/// [generation] is an Odoo generation as returned by `odooGeneration`.
List<List<dynamic>> relatedCompanyDomain(int generation, {String query = ''}) {
  final domain = <List<dynamic>>[
    if (odooPartnerIsCompanyWritable(generation))
      ['is_company', '=', true]
    else
      ['parent_id', '=', false],
  ];
  final name = query.trim();
  if (name.isNotEmpty) domain.add(['name', 'ilike', name]);
  return domain;
}
