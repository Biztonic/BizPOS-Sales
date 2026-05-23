import 'package:cloud_firestore/cloud_firestore.dart';

class SaleTransaction {
  final String id;
  final String agentId;
  final String agentName;
  final String agentTitle;
  final String storeId;
  final String? customerId;
  final String? customerName;
  final String? orderId;            // Link to BizPOS Clone order
  final String? quotationId;        // Link to original Quotation
  final double amount;
  final double amountPaid;          // Track partial payments
  final double commission;
  final double commissionRate;
  final String paymentMethod;       // Cash, Card, UPI, etc.
  final String paymentStatus;       // PENDING, PARTIAL, PAID
  final String status;              // Pending, Completed, Cancelled, Refunded
  final String saleType;            // SOFTWARE_SUBSCRIPTION, HARDWARE, MIXED
  final String targetMonth;         // For commission targets (e.g., "2026-04")
  final String? notes;
  final List<SaleItem> items;
  final DateTime createdAt;
  final DateTime updatedAt;

  SaleTransaction({
    required this.id,
    required this.agentId,
    required this.agentName,
    required this.agentTitle,
    required this.storeId,
    this.customerId,
    this.customerName,
    this.orderId,
    this.quotationId,
    required this.amount,
    this.amountPaid = 0.0,
    this.commission = 0.0,
    this.commissionRate = 0.0,
    this.paymentMethod = 'Cash',
    this.paymentStatus = 'PENDING',
    this.status = 'Pending',
    this.saleType = 'SOFTWARE_SUBSCRIPTION',
    required this.targetMonth,
    this.notes,
    this.items = const [],
    DateTime? createdAt,
    DateTime? updatedAt,
  })  : createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  factory SaleTransaction.fromMap(Map<String, dynamic> map, String id) {
    return SaleTransaction(
      id: id,
      agentId: map['agentId'] ?? '',
      agentName: map['agentName'] ?? '',
      agentTitle: map['agentTitle'] ?? 'Sales Executive',
      storeId: map['storeId'] ?? '',
      customerId: map['customerId'],
      customerName: map['customerName'],
      orderId: map['orderId'],
      quotationId: map['quotationId'],
      amount: (map['amount'] ?? 0).toDouble(),
      amountPaid: (map['amountPaid'] ?? 0).toDouble(),
      commission: (map['commission'] ?? 0).toDouble(),
      commissionRate: (map['commissionRate'] ?? 0).toDouble(),
      paymentMethod: map['paymentMethod'] ?? 'Cash',
      paymentStatus: map['paymentStatus'] ?? 'PENDING',
      status: map['status'] ?? 'Pending',
      saleType: map['saleType'] ?? 'SOFTWARE_SUBSCRIPTION',
      targetMonth: map['targetMonth'] ?? '',
      notes: map['notes'],
      items: (map['items'] as List<dynamic>?)
              ?.map((i) => SaleItem.fromMap(i as Map<String, dynamic>))
              .toList() ??
          [],
      createdAt: _parseDateTime(map['createdAt']),
      updatedAt: _parseDateTime(map['updatedAt']),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'agentId': agentId,
      'agentName': agentName,
      'agentTitle': agentTitle,
      'storeId': storeId,
      'customerId': customerId,
      'customerName': customerName,
      'orderId': orderId,
      'quotationId': quotationId,
      'amount': amount,
      'amountPaid': amountPaid,
      'commission': commission,
      'commissionRate': commissionRate,
      'paymentMethod': paymentMethod,
      'paymentStatus': paymentStatus,
      'status': status,
      'saleType': saleType,
      'targetMonth': targetMonth,
      'notes': notes,
      'items': items.map((i) => i.toMap()).toList(),
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }

  SaleTransaction copyWith({
    String? id,
    String? agentId,
    String? agentName,
    String? agentTitle,
    String? storeId,
    String? customerId,
    String? customerName,
    String? orderId,
    String? quotationId,
    double? amount,
    double? amountPaid,
    double? commission,
    double? commissionRate,
    String? paymentMethod,
    String? paymentStatus,
    String? status,
    String? saleType,
    String? targetMonth,
    String? notes,
    List<SaleItem>? items,
  }) {
    return SaleTransaction(
      id: id ?? this.id,
      agentId: agentId ?? this.agentId,
      agentName: agentName ?? this.agentName,
      agentTitle: agentTitle ?? this.agentTitle,
      storeId: storeId ?? this.storeId,
      customerId: customerId ?? this.customerId,
      customerName: customerName ?? this.customerName,
      orderId: orderId ?? this.orderId,
      quotationId: quotationId ?? this.quotationId,
      amount: amount ?? this.amount,
      amountPaid: amountPaid ?? this.amountPaid,
      commission: commission ?? this.commission,
      commissionRate: commissionRate ?? this.commissionRate,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      status: status ?? this.status,
      saleType: saleType ?? this.saleType,
      targetMonth: targetMonth ?? this.targetMonth,
      notes: notes ?? this.notes,
      items: items ?? this.items,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
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

class SaleItem {
  final String productId;
  final String productName;
  final double price;
  final int quantity;
  final double total;
  final int warrantyMonths;

  SaleItem({
    required this.productId,
    required this.productName,
    required this.price,
    required this.quantity,
    double? total,
    this.warrantyMonths = 0,
  }) : total = total ?? (price * quantity);

  factory SaleItem.fromMap(Map<String, dynamic> map) {
    return SaleItem(
      productId: map['productId'] ?? '',
      productName: map['productName'] ?? '',
      price: (map['price'] ?? 0).toDouble(),
      quantity: (map['quantity'] ?? 0).toInt(),
      total: (map['total'] ?? 0).toDouble(),
      warrantyMonths: (map['warrantyMonths'] ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productId': productId,
      'productName': productName,
      'price': price,
      'quantity': quantity,
      'total': total,
      'warrantyMonths': warrantyMonths,
    };
  }
}
