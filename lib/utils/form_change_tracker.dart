/// Answers "has this form changed since it loaded?" for an edit form, so its
/// submit button can stay disabled until there is something to save.
///
/// Give it a function that reads *every* editable value on the form into a map.
/// Call [markClean] once the form holds the record it is editing, and
/// [isDirty] then compares the form's current values against that moment.
/// Comparing values rather than counting edits means typing something and
/// deleting it again leaves the form clean, as the user would expect.
///
/// ```dart
/// late final _changes = FormChangeTracker(() => {
///   'name': _nameController.text.trim(),
///   'category': _selectedCategory,
///   'lines': [
///     for (final l in _lines) {'product': l.productId, 'qty': l.quantity},
///   ],
/// });
/// ```
///
/// A value left out of the map is a change the user can make but never save,
/// because the form will never look edited. Everything the user can edit
/// belongs in it.
///
/// Values may be anything comparable with `==`, plus `List`s and `Map`s of such
/// values, compared deeply. Do not put large blobs (a picked image's bytes)
/// in: track a "changed" flag for those instead, since the map is rebuilt and
/// compared on every call.
class FormChangeTracker {
  FormChangeTracker(this._read);

  final Map<String, Object?> Function() _read;
  Map<String, Object?>? _baseline;

  /// Whether a baseline has been recorded yet.
  ///
  /// Until it has, nothing counts as a change, so a form that is still loading
  /// the record it edits never looks edited.
  bool get hasBaseline => _baseline != null;

  /// Records the form's current values as "unchanged".
  ///
  /// Call it when the form has finished loading the record it edits — after any
  /// asynchronous step that fills fields in — and again after a save that keeps
  /// the form open. A copy is stored, so later edits to a list the form owns
  /// cannot rewrite the baseline.
  void markClean() {
    _baseline = {
      for (final entry in _read().entries) entry.key: _copy(entry.value),
    };
  }

  /// Whether any value differs from the baseline.
  bool get isDirty {
    final baseline = _baseline;
    if (baseline == null) return false;
    return !_equal(baseline, _read());
  }

  static Object? _copy(Object? value) {
    if (value is Map) {
      return {for (final e in value.entries) e.key: _copy(e.value)};
    }
    if (value is List) return [for (final v in value) _copy(v)];
    return value;
  }

  static bool _equal(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in a.keys) {
        if (!b.containsKey(key) || !_equal(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_equal(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
