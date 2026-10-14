import 'dart:async';

/// What kind of record changed. [profile] is the signed-in user's own record
/// (their `res.users` row and its partner): name, photo, contact details,
/// address, related company.
enum DataEntity { quotation, invoice, payment, customer, product, profile }

/// How it changed.
enum DataChangeKind { created, updated, deleted }

/// One change to one record (or, with no [id], to the records of that kind in
/// general), announced after the server has accepted it.
class DataChange {
  DataChange(this.entity, this.kind, {this.id, this.origin, DateTime? at})
    : at = at ?? DateTime.now();

  final DataEntity entity;
  final DataChangeKind kind;

  /// The server id of the record, when the change is to a single one.
  final int? id;

  /// When it was announced.
  final DateTime at;

  /// Whether a refresh that began at [refreshStartedAt] has already seen this
  /// change: the server had it by then, so reading again would show the same.
  bool isCoveredByRefreshStartedAt(DateTime? refreshStartedAt) =>
      refreshStartedAt != null && at.isBefore(refreshStartedAt);

  /// Who announced it. A screen that announces its own change and has already
  /// refreshed itself skips events whose origin is itself.
  final Object? origin;

  bool get isQuotation => entity == DataEntity.quotation;
  bool get isInvoice => entity == DataEntity.invoice;
  bool get isProduct => entity == DataEntity.product;
  bool get isProfile => entity == DataEntity.profile;

  /// Whether this can alter the figures the dashboard shows (counts, revenue,
  /// receivables, the number of products and the names of the best sellers):
  /// a change to any of the kinds of record except the user's own profile,
  /// which moves no figure (the dashboard's header listens for it apart).
  bool get affectsDashboard => entity != DataEntity.profile;

  @override
  String toString() => 'DataChange($entity, $kind, id: $id)';
}

/// The one place the app says "this record changed", so that every screen that
/// shows it — the lists, the details open behind them, the dashboard, a
/// customer's page — can bring itself up to date, whichever screen made the
/// change.
///
/// A screen or provider that changes a record on the server [publish]es the
/// change once the server has accepted it; anything that shows records of that
/// kind [changes]-listens and refreshes what it shows. Nothing here knows who
/// listens, and a listener never needs to know who published.
///
/// Delivery is asynchronous and in order, so a publisher can announce a change
/// in the middle of a `setState` or a navigation without the listeners
/// rebuilding inside it.
class DataChangeBus {
  DataChangeBus._();

  static final DataChangeBus instance = DataChangeBus._();

  /// A bus of its own, for tests.
  DataChangeBus.forTesting();

  final StreamController<DataChange> _controller =
      StreamController<DataChange>.broadcast();

  Stream<DataChange> get changes => _controller.stream;

  void publish(
    DataEntity entity,
    DataChangeKind kind, {
    int? id,
    Object? origin,
  }) {
    if (_controller.isClosed) return;
    _controller.add(DataChange(entity, kind, id: id, origin: origin));
  }

  void quotationChanged(
    int? id, {
    DataChangeKind kind = DataChangeKind.updated,
    Object? origin,
  }) => publish(DataEntity.quotation, kind, id: id, origin: origin);

  void invoiceChanged(
    int? id, {
    DataChangeKind kind = DataChangeKind.updated,
    Object? origin,
  }) => publish(DataEntity.invoice, kind, id: id, origin: origin);

  /// A product (the template, which is what the lists and the forms work on)
  /// was created, edited, archived or deleted.
  void productChanged(
    int? id, {
    DataChangeKind kind = DataChangeKind.updated,
    Object? origin,
  }) => publish(DataEntity.product, kind, id: id, origin: origin);

  /// The signed-in user's own profile was edited — their name, photo, phone,
  /// address, related company — and the server has it. Everything that shows
  /// who is signed in (the app bar avatar, the dashboard header, the profile
  /// screen, the account list) re-reads it.
  void profileChanged({Object? origin}) =>
      publish(DataEntity.profile, DataChangeKind.updated, origin: origin);

  void paymentChanged(
    int? id, {
    DataChangeKind kind = DataChangeKind.created,
    Object? origin,
  }) => publish(DataEntity.payment, kind, id: id, origin: origin);

  /// Calls [onChange] for the changes [where] accepts (all, when it is null),
  /// collapsing a burst into one call: a confirm followed by an invoice and a
  /// payment is three events and one refresh. [onChange] gets every change of
  /// the burst. [debounce] is how long the bus stays quiet before it calls.
  ///
  /// [DataChangeSubscription.cancel] when the listener goes away; a screen does
  /// it in `dispose`.
  DataChangeSubscription listen({
    bool Function(DataChange change)? where,
    required void Function(List<DataChange> burst) onChange,
    Duration debounce = const Duration(milliseconds: 350),
  }) {
    final pending = <DataChange>[];
    Timer? timer;

    final source = _controller.stream.listen((change) {
      if (where != null && !where(change)) return;
      pending.add(change);
      timer?.cancel();
      timer = Timer(debounce, () {
        final burst = List<DataChange>.of(pending);
        pending.clear();
        onChange(burst);
      });
    });

    return DataChangeSubscription._(() {
      timer?.cancel();
      pending.clear();
      source.cancel();
    });
  }
}

/// The handle [DataChangeBus.listen] returns.
class DataChangeSubscription {
  DataChangeSubscription._(this._cancel);

  final void Function() _cancel;
  bool _cancelled = false;

  /// Stops the listener, and drops a call that was waiting for the burst to
  /// end. Safe to call twice.
  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    _cancel();
  }
}
