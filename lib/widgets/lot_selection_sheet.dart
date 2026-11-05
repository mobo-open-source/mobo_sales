import 'package:flutter/material.dart';

import '../services/delivery_lot_service.dart';
import '../utils/quantity_format.dart';

/// What the user chose in [showLotSelectionSheet]: lots that already exist
/// (lot id to quantity) and new lot or serial numbers to make
/// (number to quantity).
class LotSelection {
  const LotSelection({this.existing = const {}, this.created = const {}});

  final Map<int, double> existing;
  final Map<String, double> created;

  double get total =>
      existing.values.fold(0.0, (a, b) => a + b) +
      created.values.fold(0.0, (a, b) => a + b);
}

/// Lets the user pick the lot or serial numbers a delivery line ships.
///
/// A serial number is one unit each, so it is ticked, up to the demand. A lot
/// takes a quantity, taken from what that lot has free. When the delivery's
/// operation type may create lots ([canCreate]), new numbers can also be typed
/// in or, for a serial product, generated from a first number — the Generate
/// button of Odoo's own delivery.
///
/// Returns the selection, or null when dismissed.
Future<LotSelection?> showLotSelectionSheet(
  BuildContext context, {
  required String productName,
  required double demand,
  required bool isSerial,
  required List<LotStock> lots,
  required Map<int, double> selected,
  bool canCreate = false,
  bool canUseExisting = true,
  String? suggestedFirst,
  Future<List<String>> Function(String first, int count)? generate,
}) {
  return showModalBottomSheet<LotSelection>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).brightness == Brightness.dark
        ? Colors.grey[900]
        : Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _LotSelectionSheet(
      productName: productName,
      demand: demand,
      isSerial: isSerial,
      lots: lots,
      selected: selected,
      canCreate: canCreate,
      canUseExisting: canUseExisting,
      suggestedFirst: suggestedFirst,
      generate: generate,
    ),
  );
}

class _LotSelectionSheet extends StatefulWidget {
  const _LotSelectionSheet({
    required this.productName,
    required this.demand,
    required this.isSerial,
    required this.lots,
    required this.selected,
    required this.canCreate,
    required this.canUseExisting,
    required this.suggestedFirst,
    required this.generate,
  });

  final String productName;
  final double demand;
  final bool isSerial;
  final List<LotStock> lots;
  final Map<int, double> selected;
  final bool canCreate;
  final bool canUseExisting;
  final String? suggestedFirst;
  final Future<List<String>> Function(String first, int count)? generate;

  @override
  State<_LotSelectionSheet> createState() => _LotSelectionSheetState();
}

class _LotSelectionSheetState extends State<_LotSelectionSheet> {
  late final Map<int, double> _picked = Map.of(widget.selected);

  /// New numbers to make, in the order they were added.
  final Map<String, double> _created = {};
  final Map<int, TextEditingController> _controllers = {};
  late final TextEditingController _first = TextEditingController(
    text: widget.suggestedFirst ?? '',
  );
  late final TextEditingController _count = TextEditingController(
    text: formatQuantity(_remaining < 1 ? 1 : _remaining),
  );
  final TextEditingController _newName = TextEditingController();
  final TextEditingController _newQty = TextEditingController(text: '1');
  String _query = '';
  bool _generating = false;
  String? _createError;

  @override
  void initState() {
    super.initState();
    for (final lot in widget.lots) {
      _controllers[lot.lotId] = TextEditingController(
        text: formatQuantity(_picked[lot.lotId] ?? 0),
      );
    }
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _first.dispose();
    _count.dispose();
    _newName.dispose();
    _newQty.dispose();
    super.dispose();
  }

  double get _total =>
      _picked.values.fold(0.0, (a, b) => a + b) +
      _created.values.fold(0.0, (a, b) => a + b);

  double get _remaining => widget.demand - _total;

  LotStock _lot(int id) => widget.lots.firstWhere((l) => l.lotId == id);

  void _toggleSerial(LotStock lot, bool on) {
    setState(() {
      if (on) {
        if (_total + 1 > widget.demand + 1e-9) return;
        _picked[lot.lotId] = 1;
      } else {
        _picked.remove(lot.lotId);
      }
    });
  }

  void _toggleLot(LotStock lot, bool on) {
    setState(() {
      if (on) {
        final left = _remaining;
        final qty = left <= 0
            ? 0.0
            : (left < lot.available ? left : lot.available);
        if (qty <= 0) return;
        _picked[lot.lotId] = qty;
        _controllers[lot.lotId]!.text = formatQuantity(qty);
      } else {
        _picked.remove(lot.lotId);
        _controllers[lot.lotId]!.text = '0';
      }
    });
  }

  void _setLotQty(LotStock lot, String text) {
    final qty = double.tryParse(text) ?? 0;
    setState(() {
      if (qty <= 0) {
        _picked.remove(lot.lotId);
      } else {
        _picked[lot.lotId] = qty;
      }
    });
  }

  /// Makes serial numbers from the first one, like Odoo's Generate button.
  Future<void> _generate() async {
    final first = _first.text.trim();
    final count = int.tryParse(_count.text.trim()) ?? 0;
    if (first.isEmpty) {
      setState(() => _createError = 'Enter the first serial number.');
      return;
    }
    if (count < 1) {
      setState(() => _createError = 'Enter how many to generate.');
      return;
    }
    if (_total + count > widget.demand + 1e-9) {
      setState(
        () => _createError =
            'That is more than the demand of ${formatQuantity(widget.demand)}.',
      );
      return;
    }
    setState(() {
      _generating = true;
      _createError = null;
    });
    final names = await widget.generate!(first, count);
    if (!mounted) return;
    setState(() {
      _generating = false;
      for (final name in names) {
        _created[name] = 1;
      }
      // The next batch starts after this one.
      if (names.isNotEmpty) _first.text = names.last;
      _count.text = formatQuantity(_remaining < 1 ? 1 : _remaining);
    });
  }

  /// Adds one typed number: a lot name with its quantity, or a single serial.
  void _addNew() {
    final name = _newName.text.trim();
    final qty = widget.isSerial ? 1.0 : (double.tryParse(_newQty.text) ?? 0);
    if (name.isEmpty) {
      setState(() => _createError = 'Enter a number.');
      return;
    }
    if (qty <= 0) {
      setState(() => _createError = 'Enter a quantity.');
      return;
    }
    if (_created.containsKey(name) || widget.lots.any((l) => l.name == name)) {
      setState(() => _createError = '$name is already in the list.');
      return;
    }
    if (_total + qty > widget.demand + 1e-9) {
      setState(
        () => _createError =
            'That is more than the demand of ${formatQuantity(widget.demand)}.',
      );
      return;
    }
    setState(() {
      _created[name] = qty;
      _newName.clear();
      _createError = null;
    });
  }

  /// A reason the selection cannot be saved, or null.
  String? get _problem {
    if (_picked.isEmpty && _created.isEmpty) return 'Select at least one.';
    for (final entry in _picked.entries) {
      final lot = _lot(entry.key);
      if (entry.value > lot.available + 1e-9) {
        return '${lot.name} has only ${formatQuantity(lot.available)} '
            'available.';
      }
    }
    if (_total > widget.demand + 1e-9) {
      return 'More than the demand of ${formatQuantity(widget.demand)}.';
    }
    return null;
  }

  Widget _createSection(Color? muted) {
    final canGenerate = widget.isSerial && widget.generate != null;
    InputDecoration field(String label) =>
        InputDecoration(labelText: label, isDense: true);

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.isSerial ? 'New serial numbers' : 'New lot',
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 8),
          if (canGenerate)
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    key: const Key('lot-first'),
                    controller: _first,
                    decoration: field('First serial number'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('lot-count'),
                    controller: _count,
                    keyboardType: TextInputType.number,
                    decoration: field('How many'),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  key: const Key('lot-generate'),
                  onPressed: _generating ? null : _generate,
                  child: const Text('Generate'),
                ),
              ],
            ),
          if (canGenerate) const SizedBox(height: 8),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  key: const Key('lot-name'),
                  controller: _newName,
                  decoration: field(
                    widget.isSerial ? 'Serial number' : 'Lot number',
                  ),
                ),
              ),
              if (!widget.isSerial) ...[
                const SizedBox(width: 8),
                Expanded(
                  flex: 2,
                  child: TextField(
                    key: const Key('lot-new-qty'),
                    controller: _newQty,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    inputFormatters: [QuantityInputFormatter()],
                    decoration: field('Quantity'),
                  ),
                ),
              ],
              const SizedBox(width: 8),
              OutlinedButton(
                key: const Key('lot-add'),
                onPressed: _addNew,
                child: const Text('Add'),
              ),
            ],
          ),
          if (_createError != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                _createError!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ),
          if (_created.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final entry in _created.entries)
                  InputChip(
                    label: Text(
                      widget.isSerial
                          ? entry.key
                          : '${entry.key} × ${formatQuantity(entry.value)}',
                    ),
                    onDeleted: () => setState(() => _created.remove(entry.key)),
                  ),
              ],
            ),
          ],
          if (widget.canUseExisting && widget.lots.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              widget.isSerial ? 'In stock' : 'Lots in stock',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ],
      ),
    );
  }

  Widget _lotRow(LotStock lot, Color? muted) {
    final on = _picked.containsKey(lot.lotId);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Row(
        children: [
          Expanded(
            child: CheckboxListTile(
              value: on,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: Text(lot.name, overflow: TextOverflow.ellipsis),
              subtitle: widget.isSerial
                  ? null
                  : Text(
                      '${formatQuantity(lot.available)} available',
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
              onChanged: (v) => widget.isSerial
                  ? _toggleSerial(lot, v ?? false)
                  : _toggleLot(lot, v ?? false),
            ),
          ),
          if (!widget.isSerial && on)
            SizedBox(
              width: 84,
              child: TextField(
                controller: _controllers[lot.lotId],
                textAlign: TextAlign.center,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [QuantityInputFormatter()],
                decoration: const InputDecoration(isDense: true),
                onChanged: (v) => _setLotQty(lot, v),
              ),
            ),
          const SizedBox(width: 8),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final muted = isDark ? Colors.grey[400] : Colors.grey[700];
    final showExisting = widget.canUseExisting;
    final visible = showExisting
        ? widget.lots
              .where((l) => l.name.toLowerCase().contains(_query.toLowerCase()))
              .toList()
        : const <LotStock>[];
    final problem = _problem;
    final complete = (_total - widget.demand).abs() < 1e-9;

    final header = <Widget>[
      if (widget.canCreate) _createSection(muted),
      if (showExisting && widget.lots.length > 6)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: TextField(
            decoration: const InputDecoration(
              hintText: 'Search',
              prefixIcon: Icon(Icons.search, size: 20),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
      if (showExisting && widget.lots.isEmpty && !widget.canCreate)
        Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No ${widget.isSerial ? 'serial numbers' : 'lots'} '
            'have stock at the source location.',
            style: TextStyle(color: muted),
          ),
        ),
    ];

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.9,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.isSerial ? 'Select Serial Numbers' : 'Select Lots',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    widget.productName,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Selected ${formatQuantity(_total)} of '
                    '${formatQuantity(widget.demand)}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: complete ? Colors.green : theme.primaryColor,
                    ),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                padding: const EdgeInsets.symmetric(vertical: 8),
                itemCount: header.length + visible.length,
                itemBuilder: (_, i) => i < header.length
                    ? header[i]
                    : _lotRow(visible[i - header.length], muted),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (problem != null &&
                      (_picked.isNotEmpty || _created.isNotEmpty))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        problem,
                        style: const TextStyle(color: Colors.red, fontSize: 12),
                      ),
                    ),
                  ElevatedButton(
                    onPressed: problem == null
                        ? () => Navigator.of(context).pop(
                            LotSelection(
                              existing: Map.of(_picked),
                              created: Map.of(_created),
                            ),
                          )
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Save',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
