import 'package:cloud_firestore/cloud_firestore.dart';
import 'sale_transaction.dart';

class Quotation {
  final String id;
  final String agentId;
  final String agentName;
  final String agentTitle;
  final String storeId;
  final String? customerId;
  final String? customerName;
  final String? customerPhone;
  final String? customerEmail;
  final double totalAmount;
  final String status; // DRAFT, SENT, CONVERTED, REJECTED
  final String? notes;
  final List<SaleItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime validUntil;

  Quotation({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.agentTitle,
    required this.storeId,
    this.customerId,
    this.customerName,
    this.customerPhone,
    this.customerEmail,
    required this.totalAmount,
    this.status = 'DRAFT',
    this.notes,
    this.items = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
    DateTime? validUntil,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now(),
        validUntil = validUntil ?? (createdAt ?? DateTime.now()).add(const Duration(days: 7));

  factory Quotation.fromMap(Map<String, dynamic> map, String id) {
    return Quotation(
      id: id,
      agentId: map['agentId'] ?? '',
      agentName: map['agentName'] ?? '',
      agentTitle: map['agentTitle'] ?? 'Sales Executive',
      storeId: map['storeId'] ?? '',
      customerId: map['customerId'],
      customerName: map['customerName'],
      customerPhone: map['customerPhone'],
      customerEmail: map['customerEmail'],
      totalAmount: (map['totalAmount'] ?? 0).toDouble(),
      status: map['status'] ?? 'DRAFT',
      notes: map['notes'],
      items: (map['items'] as List<dynamic>?)
              ?.map((i) => SaleItem.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
      validUntil: _parseDateTime(map['validUntil']),
    );
  }

  Map<String, dynamic> toMap({bool isUpdate = false}) {
    final Map<String, dynamic> data = {
      'agentId': agentId,
      'agentName': agentName,
      'agentTitle': agentTitle,
      'storeId': storeId,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'customerEmail': customerEmail,
      'totalAmount': totalAmount,
      'status': status,
      'notes': notes,
      'items': items.map((i) => i.toMap()).toList(),
      'validUntil': Timestamp.fromDate(validUntil),
      'updatedAt': FieldValue.serverTimestamp(),
    };

    if (!isUpdate) {
      data['createdAt'] = FieldValue.serverTimestamp();
    }
    
    return data;
  }

  Quotation copyWith({
    String? id,
    String? agentId,
    String? agentName,
    String? agentTitle,
    String? storeId,
    String? customerId,
    String? customerName,
    String? customerPhone,
    String? customerEmail,
    double? totalAmount,
    String? status,
    String? notes,
    List<SaleItem>? items,
  }) {
    return Quotation(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      agentTitle: agentTitle ?? this.agentTitle,
      storeId: storeId ?? this.storeId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      customerPhone: customerPhone ?? this.customerPhone,
      customerEmail: customerEmail ?? this.customerEmail,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
      validUntil: validUntil,
    );
  }

  static DateTime _parseDateTime(dynamic value) {
    if (value == null) return DateTime.now();
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value) ?? DateTime.now();
    if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
    return DateTime.now();
  }
}
