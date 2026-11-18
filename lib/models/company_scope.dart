/// The domain Odoo's own form gives a `check_company` field: records of
/// [companyId], or of no company.
///
/// This is `_check_company_domain` in Odoo 17 to 20, which neither
/// `res.partner` nor `product.product` overrides. It is stricter than what the
/// user may read — record rules also show a parent company's records — and it
/// is exactly what Odoo accepts when the record is saved, so a picker that uses
/// it offers only what the record can be saved with.
///
/// Empty when the company is not known, which leaves a search as it was.
List<dynamic> companyCheckDomain(int? companyId) {
  if (companyId == null || companyId <= 0) return const [];
  return [
    '|',
    ['company_id', '=', false],
    ['company_id', '=', companyId],
  ];
}
