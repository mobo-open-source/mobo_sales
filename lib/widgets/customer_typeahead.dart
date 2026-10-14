import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hugeicons/hugeicons.dart';

import '../models/contact.dart';
import '../services/customer_service.dart';
import '../shared/widgets/mobo/mobo_select_form_field.dart';
import '../utils/app_theme.dart';

/// Server-searched customer picker, built on [MoboSelectFormField].
///
/// Keeps the original widget's job — search Odoo as the user types, hand back
/// the chosen [Contact] — but the field itself is the shared Mobo select, so it
/// looks and behaves like every other dropdown in the app.
class CustomerTypeAhead extends StatefulWidget {
  final String labelText;

  /// Draws a red ` *` after [labelText].
  final bool isRequired;
  final String? hintText;
  final ValueChanged<Contact> onCustomerSelected;
  final VoidCallback? onClear;
  final String? Function(Contact?)? validator;

  /// The customer the screen already holds, shown in the field with the
  /// avatar and name, as an Employee is in an expense form. Pass it for an
  /// edit form or a customer chosen elsewhere; the field follows it whenever it
  /// changes. Left null, the field keeps its own choice, as before.
  final Contact? selectedCustomer;

  /// Shows the ✕ that empties the field once a customer is chosen. A required
  /// field has no use for it — the user picks another customer instead — and
  /// shows only the chevron.
  final bool allowClear;

  /// False locks the field on [selectedCustomer].
  final bool enabled;

  /// Where the customers come from: the customer list's own query by default.
  /// A test hands in its own.
  final Future<List<Contact>> Function(String? query, int limit)? search;

  const CustomerTypeAhead({
    required this.labelText,
    this.isRequired = false,
    required this.onCustomerSelected,
    this.onClear,
    this.hintText,
    this.validator,
    this.selectedCustomer,
    this.allowClear = true,
    this.enabled = true,
    this.search,
    super.key,
  });

  @override
  State<CustomerTypeAhead> createState() => _CustomerTypeAheadState();
}

class _CustomerTypeAheadState extends State<CustomerTypeAhead> {
  static const _debounce = Duration(milliseconds: 300);

  List<Contact> _results = const [];
  Contact? _selected;
  bool _isLoading = false;
  bool _loadFailed = false;
  Timer? _debounceTimer;

  /// What the list on screen was searched for ('' for the first page).
  String _lastQuery = '';

  /// Responses can arrive out of order; only the latest request may write.
  int _requestSeq = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedCustomer;
  }

  @override
  void didUpdateWidget(covariant CustomerTypeAhead oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The screen picked or dropped the customer itself (an edit form loading
    // its quotation, a customer fetched later): the field shows what it holds.
    if (widget.selectedCustomer?.id != oldWidget.selectedCustomer?.id &&
        widget.selectedCustomer?.id != _selected?.id) {
      _selected = widget.selectedCustomer;
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    // The unfiltered first page needs no debounce — nothing was typed.
    if (query.trim().isEmpty) {
      _fetch(query);
      return;
    }
    _debounceTimer = Timer(_debounce, () => _fetch(query));
  }

  /// Opening the list shows the customers, whatever came before: a field
  /// holding a chosen customer has one option already, so it would never ask
  /// for the rest, and one that was searched earlier would reopen showing only
  /// that search's results. The chosen customer is moved to the top by the
  /// field itself.
  void _ensureFirstPageLoaded() {
    if (_lastQuery.isEmpty && (_results.isNotEmpty || _isLoading)) return;
    _fetch('');
  }

  Future<void> _fetch(String pattern) async {
    _lastQuery = pattern.trim();
    final seq = ++_requestSeq;
    setState(() {
      _isLoading = true;
      _loadFailed = false;
    });

    try {
      // Reuse the exact query the (working) customer list page uses
      // instead of a bespoke one. Earlier the typeahead's own query
      // (customer_rank filter / image_128 / mobile fields) failed with a
      // generic "Odoo server error" while this proven path kept working.
      final query = pattern.trim();
      final q = query.isEmpty ? null : query;
      final limit = query.isEmpty ? 20 : 100;
      final results =
          await (widget.search?.call(q, limit) ??
              CustomerService.instance.fetchAllCustomers(
                searchQuery: q,
                limit: limit,
              ));
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = results;
        _isLoading = false;
      });
    } catch (_) {
      if (!mounted || seq != _requestSeq) return;
      setState(() {
        _results = const [];
        _isLoading = false;
        _loadFailed = true;
      });
    }
  }

  void _onChanged(int? id) {
    if (id == null) {
      setState(() => _selected = null);
      widget.onClear?.call();
      return;
    }
    Contact? customer;
    for (final candidate in [..._results, if (_selected != null) _selected!]) {
      if (candidate.id == id) {
        customer = candidate;
        break;
      }
    }
    if (customer == null) return;
    setState(() => _selected = customer);
    widget.onCustomerSelected(customer);
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selected;
    final options = [
      for (final customer in _results) _optionFor(customer),
      // A picked customer must stay in the list even after a later search
      // replaces the results, or the field would lose what it is showing.
      if (selected != null && !_results.any((c) => c.id == selected.id))
        _optionFor(selected),
    ];

    return MoboSelectFormField<int>(
      label: widget.labelText,
      isRequired: widget.isRequired,
      hintText: widget.hintText ?? 'Search customers...',
      // The avatar stands in for the icon once someone is chosen.
      prefixHugeIcon: selected == null ? HugeIcons.strokeRoundedUser : null,
      allowClear: widget.allowClear,
      enabled: widget.enabled,
      options: options,
      value: selected?.id,
      isLoading: _isLoading,
      emptyText: _loadFailed
          ? 'Could not load customers. Please check your connection and try again.'
          : 'No customers found',
      onSearchChanged: _onSearchChanged,
      onOpened: _ensureFirstPageLoaded,
      onChanged: _onChanged,
      validator: widget.validator == null
          ? null
          : (_) => widget.validator!(_selected),
    );
  }

  MoboOption<int> _optionFor(Contact customer) {
    final email = customer.email;
    final hasEmail =
        email != null && email.isNotEmpty && email.toLowerCase() != 'false';

    return MoboOption<int>(
      value: customer.id,
      label: customer.name,
      subtitle: hasEmail ? email : null,
      leading: _buildAvatar(customer),
    );
  }

  Widget _buildAvatar(Contact customer) {
    if (customer.imageUrl != null &&
        customer.imageUrl!.isNotEmpty &&
        customer.imageUrl != 'false') {
      try {
        final base64String = customer.imageUrl!.contains(',')
            ? customer.imageUrl!.split(',')[1]
            : customer.imageUrl!;
        final bytes = base64Decode(base64String);
        return CircleAvatar(radius: 16, backgroundImage: MemoryImage(bytes));
      } catch (e) {
        // Fall through to the initial below.
      }
    }

    return CircleAvatar(
      radius: 16,
      backgroundColor: AppTheme.primaryColor.withValues(alpha: 0.1),
      child: Text(
        customer.name.isNotEmpty ? customer.name[0].toUpperCase() : '?',
        style: GoogleFonts.manrope(
          color: AppTheme.primaryColor,
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}
