/// Represents an Odoo payment term (e.g. '30 days', 'Immediate').
class PaymentTerm {
  final int id;
  final String name;

  PaymentTerm({required this.id, required this.name});

  /// Constructs a [PaymentTerm] from a raw Odoo map.
  factory PaymentTerm.fromMap(Map<String, dynamic> map) {
    return PaymentTerm(
      id: map['id'] as int,
      name: (map['name'] ?? 'Unnamed Term').toString(),
    );
  }

  /// Serialises this payment term to a map.
  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name};
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PaymentTerm &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'PaymentTerm{id: $id, name: $name}';
}
