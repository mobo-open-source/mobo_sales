import 'package:flutter/material.dart';

import 'mobo_select_field.dart';

export 'mobo_select_field.dart';

/// [MoboSelectField] as a [FormField], for screens that validate through a
/// surrounding [Form].
///
/// [MoboSelectField] only takes an `errorText`; it has no validator and does
/// not take part in `Form.validate()`. This adapter feeds that `errorText` from
/// the form, so a screen swapping a `DropdownButtonFormField` for a Mobo field
/// keeps its `validator` and its "validate on submit" behaviour unchanged.
///
/// The parent still owns the value: [value] is what the field displays, and a
/// change to it from outside is carried into the form field's own value so a
/// validator never sees a stale one.
class MoboSelectFormField<T> extends FormField<T> {
  MoboSelectFormField({
    super.key,
    required List<MoboOption<T>> options,
    required T? value,
    required ValueChanged<T?> onChanged,
    super.validator,
    super.autovalidateMode,
    String? label,
    String hintText = 'Select',
    bool isRequired = false,
    super.enabled,
    bool searchable = false,
    bool allowClear = true,
    IconData? prefixIcon,
    IconData? prefixHugeIcon,
    ValueChanged<String>? onSearchChanged,
    String searchHintText = 'Search...',
    bool isLoading = false,
    String emptyText = 'No matches',
    VoidCallback? onOpened,
  }) : super(
         initialValue: value,
         builder: (field) => MoboSelectField<T>(
           options: options,
           value: value,
           onChanged: (next) {
             field.didChange(next);
             onChanged(next);
           },
           label: label,
           hintText: hintText,
           isRequired: isRequired,
           errorText: field.errorText,
           enabled: field.widget.enabled,
           searchable: searchable,
           allowClear: allowClear,
           prefixIcon: prefixIcon,
           prefixHugeIcon: prefixHugeIcon,
           onSearchChanged: onSearchChanged,
           searchHintText: searchHintText,
           isLoading: isLoading,
           emptyText: emptyText,
           onOpened: onOpened,
         ),
       );

  @override
  FormFieldState<T> createState() => _MoboSelectFormFieldState<T>();
}

class _MoboSelectFormFieldState<T> extends FormFieldState<T> {
  @override
  void didUpdateWidget(covariant MoboSelectFormField<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Same sync DropdownButtonFormField does: the parent changed the value, so
    // the form field's copy — which the validator reads — must follow.
    if (oldWidget.initialValue != widget.initialValue) {
      setValue(widget.initialValue);
    }
  }
}
