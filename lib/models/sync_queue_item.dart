import 'dart:convert';

class SyncQueueItem {
  final String id; // Unique ID (UUID)
  final String entityId; // ID of the entity (e.g. customerId, quotationId)
  final String entityType; // 'product', 'customer', 'transaction', 'expense', 'commission', 'quotation'
  final String operation; // 'CREATE', 'UPDATE', 'DELETE'
  final Map<String, dynamic> payload;
  final DateTime createdAt;
  final String status; // 'PENDING', 'SYNCING', 'FAILED'
  final int retryCount;
  final String? errorMessage;

  SyncQueueItem({
    required this.id,
    required this.entityId,
    required this.entityType,
    required this.operation,
    required this.payload,
    required this.createdAt,
    this.status = 'PENDING',
    this.retryCount = 0,
    this.errorMessage,
  });

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'entityId': entityId,
      'entityType': entityType,
      'operation': operation,
      'payload': payload,
      'createdAt': createdAt.toIso8601String(),
      'status': status,
      'retryCount': retryCount,
      'errorMessage': errorMessage,
    };
  }

  factory SyncQueueItem.fromMap(Map<String, dynamic> map) {
    return SyncQueueItem(
      id: map['id'] ?? '',
      entityId: map['entityId'] ?? '',
      entityType: map['entityType'] ?? '',
      operation: map['operation'] ?? '',
      payload: Map<String, dynamic>.from(map['payload'] ?? {}),
      createdAt: DateTime.parse(map['createdAt'] ?? DateTime.now().toIso8601String()),
      status: map['status'] ?? 'PENDING',
      retryCount: map['retryCount'] ?? 0,
      errorMessage: map['errorMessage'],
    );
  }

  SyncQueueItem copyWith({
    String? id,
    String? entityId,
    String? entityType,
    String? operation,
    Map<String, dynamic>? payload,
    DateTime? createdAt,
    String? status,
    int? retryCount,
    String? errorMessage,
  }) {
    return SyncQueueItem(
      id: id ?? this.id,
      entityId: entityId ?? this.entityId,
      entityType: entityType ?? this.entityType,
      operation: operation ?? this.operation,
      payload: payload ?? this.payload,
      createdAt: createdAt ?? this.createdAt,
      status: status ?? this.status,
      retryCount: retryCount ?? this.retryCount,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}
