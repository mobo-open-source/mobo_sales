import '../services/odoo_error_handler.dart';

/// What to tell the user when saving a customer fails.
///
/// Odoo's own sentence is used whenever it gave one — a validation message
/// ("The VAT number [x] does not seem to be valid", "Invalid Email!") is
/// written for people and says exactly what to fix. What is added here is
/// what only the customer form knows: that a permission is about customers,
/// and which unique value (email, VAT, reference) is already taken.
String customerErrorMessage(Object error, {required bool isEdit}) {
  final text = error.toString();
  final lower = text.toLowerCase();
  final verb = isEdit ? 'edit' : 'create';

  if (lower.contains('you do not have permission to create customers')) {
    return "You don't have permission to create customers. Please contact "
        'your administrator.';
  }
  if (lower.contains('you do not have permission to modify customers') ||
      lower.contains('you do not have permission to update customers')) {
    return "You don't have permission to edit customers. Please contact your "
        'administrator.';
  }
  if (lower.contains('you do not have permission to archive customers')) {
    return "You don't have permission to archive customers. Please contact "
        'your administrator.';
  }

  if (lower.contains('accesserror') ||
      lower.contains('not allowed to') ||
      lower.contains('enough rights')) {
    if (lower.contains('credit_limit')) {
      return "You don't have permission to change the credit limit.";
    }
    if (lower.contains('payment_term')) {
      return "You don't have permission to change the payment terms.";
    }
    if (lower.contains('property_')) {
      return "You don't have permission to change some of the advanced "
          'settings. Please contact your administrator.';
    }
    return "You don't have permission to $verb this customer. Please contact "
        'your administrator.';
  }

  if (lower.contains('duplicate key value') ||
      lower.contains('violates unique constraint') ||
      lower.contains('already exists')) {
    if (lower.contains('email')) {
      return 'A customer with this email address already exists.';
    }
    if (lower.contains('vat')) {
      return 'A customer with this VAT number already exists.';
    }
    if (lower.contains('(ref)') || lower.contains('_ref_')) {
      return 'A customer with this reference already exists.';
    }
    return 'A customer with the same details already exists.';
  }

  return OdooErrorHandler.toSnackbarMessage(
    error,
    fallback: isEdit
        ? 'Could not update the customer. Please try again.'
        : 'Could not create the customer. Please try again.',
  );
}
