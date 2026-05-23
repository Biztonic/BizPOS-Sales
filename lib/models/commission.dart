import 'package:cloud_firestore/cloud_firestore.dart';

class Commission {
  final String id;
  final String agentId;
  final String agentName;
  final String storeId;
  final String transactionId;     // Link to SaleTransaction
  final double saleAmount;
  final double rate;               // Percentage
  final double amount;             // Calculated commission amount
  final String status;             // Pending, Approved, Paid, Rejected
  final String type;               // Commission, Commission + Bonus, etc.
  final String? approvedBy;
  final DateTime? paidAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  Commission({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.storeId,
    required this.transactionId,
    required this.saleAmount,
    required this.rate,
    required this.amount,
    this.status = 'Pending',
    this.type = 'Commission',
    this.approvedBy,
    this.paidAt,
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory Commission.fromMap(Map<String, dynamic> map, String id) {
    return Commission(
      id: id,
      agentId: map['agentId'] ?? '',
      agentName: map['agentName'] ?? '',
      storeId: map['storeId'] ?? '',
      transactionId: map['transactionId'] ?? '',
      saleAmount: (map['saleAmount'] ?? 0).toDouble(),
      rate: (map['rate'] ?? 0).toDouble(),
      amount: (map['amount'] ?? 0).toDouble(),
      status: map['status'] ?? 'Pending',
      type: map['type'] ?? 'Commission',
      approvedBy: map['approvedBy'],
      paidAt: _parseDateTime(map['paidAt']),
      createdAt: _parseDateTime(map['createdAt']) ?? DateTime.now(),
      updatedAt: _parseDateTime(map['updatedAt']) ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'agentId': agentId,
      'agentName': agentName,
      'storeId': storeId,
      'transactionId': transactionId,
      'saleAmount': saleAmount,
      'rate': rate,
      'amount': amount,
      'status': status,
      'type': type,
      'approvedBy': approvedBy,
      'paidAt': paidAt != null ? Timestamp.fromDate(paidAt!) : null,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  Commission copyWith({
    String? id,
    String? agentId,
    String? agentName,
    String? storeId,
    String? transactionId,
    double? saleAmount,
    double? rate,
    double? amount,
    String? status,
    String? type,
    String? approvedBy,
    DateTime? paidAt,
  }) {
    return Commission(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      storeId: storeId ?? this.storeId,
      transactionId: transactionId ?? this.transactionId,
      saleAmount: saleAmount ?? this.saleAmount,
      rate: rate ?? this.rate,
      amount: amount ?? this.amount,
      status: status ?? this.status,
      type: type ?? this.type,
      approvedBy: approvedBy ?? this.approvedBy,
      paidAt: paidAt ?? this.paidAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }

  static DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return null;
  }
}
