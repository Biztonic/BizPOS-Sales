import 'package:cloud_firestore/cloud_firestore.dart';

class Customer {
  final String id;
  final String name;
  final String phone;
  final String? email;
  final String? address;
  final String status; // 'LEAD', 'PROSPECT', 'ACTIVE', 'INACTIVE'
  final String? assignedTo;
  final String? assignedToName;
  final DateTime? lastContactedAt;
  final DateTime? nextFollowUpAt;
  final DateTime? createdAt;
  final List<WarrantyInfo> warranties;
  final String source; // 'MANUAL', 'CONTACT_IMPORT'

  Customer({
    required this.id,
    required this.name,
    required this.phone,
    this.email,
    this.address,
    this.status = 'LEAD',
    this.assignedTo,
    this.assignedToName,
    this.lastContactedAt,
    this.nextFollowUpAt,
    this.createdAt,
    this.warranties = const [],
    this.source = 'MANUAL',
  });

  factory Customer.fromFirestore(DocumentSnapshot doc) {
    Map data = doc.data() as Map<String, dynamic>;
    return Customer(
      id: doc.id,
      name: data['name'] ?? '',
      phone: data['phone'] ?? '',
      email: data['email'],
      address: data['address'],
      status: data['status'] ?? 'LEAD',
      assignedTo: data['assignedTo'],
      assignedToName: data['assignedToName'],
      lastContactedAt: (data['lastContactedAt'] as Timestamp?)?.toDate(),
      nextFollowUpAt: (data['nextFollowUpAt'] as Timestamp?)?.toDate(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      warranties: (data['warranties'] as List<dynamic>?)
              ?.map((w) => WarrantyInfo.fromMap(w as Map<String, dynamic>))
              .toList() ??
          [],
      source: data['source'] ?? 'MANUAL',
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'phone': phone,
      'email': email,
      'address': address,
      'status': status,
      'assignedTo': assignedTo,
      'assignedToName': assignedToName,
      'lastContactedAt': lastContactedAt != null ? Timestamp.fromDate(lastContactedAt!) : null,
      'nextFollowUpAt': nextFollowUpAt != null ? Timestamp.fromDate(nextFollowUpAt!) : null,
      'createdAt': createdAt ?? FieldValue.serverTimestamp(),
      'warranties': warranties.map((w) => w.toMap()).toList(),
      'source': source,
    };
  }

  Customer copyWith({
    String? id,
    String? name,
    String? phone,
    String? email,
    String? address,
    String? status,
    String? assignedTo,
    String? assignedToName,
    DateTime? lastContactedAt,
    DateTime? nextFollowUpAt,
    DateTime? createdAt,
    List<WarrantyInfo>? warranties,
    String? source,
  }) {
    return Customer(
      id: id ?? this.id,
      name: name ?? this.name,
      phone: phone ?? this.phone,
      email: email ?? this.email,
      address: address ?? this.address,
      status: status ?? this.status,
      assignedTo: assignedTo ?? this.assignedTo,
      assignedToName: assignedToName ?? this.assignedToName,
      lastContactedAt: lastContactedAt ?? this.lastContactedAt,
      nextFollowUpAt: nextFollowUpAt ?? this.nextFollowUpAt,
      createdAt: createdAt ?? this.createdAt,
      warranties: warranties ?? this.warranties,
      source: source ?? this.source,
    );
  }
}

class WarrantyInfo {
  final String productName;
  final String productId;
  final DateTime purchaseDate;
  final DateTime expiryDate;
  final int durationMonths;

  WarrantyInfo({
    required this.productName,
    required this.productId,
    required this.purchaseDate,
    required this.expiryDate,
    required this.durationMonths,
  });

  factory WarrantyInfo.fromMap(Map<String, dynamic> map) {
    return WarrantyInfo(
      productName: map['productName'] ?? '',
      productId: map['productId'] ?? '',
      purchaseDate: (map['purchaseDate'] as Timestamp).toDate(),
      expiryDate: (map['expiryDate'] as Timestamp).toDate(),
      durationMonths: (map['durationMonths'] ?? 0).toInt(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'productName': productName,
      'productId': productId,
      'purchaseDate': Timestamp.fromDate(purchaseDate),
      'expiryDate': Timestamp.fromDate(expiryDate),
      'durationMonths': durationMonths,
    };
  }

  int get remainingDays {
    final now = DateTime.now();
    if (now.isAfter(expiryDate)) return 0;
    return expiryDate.difference(now).inDays;
  }

  bool get isActive => DateTime.now().isBefore(expiryDate);
}
