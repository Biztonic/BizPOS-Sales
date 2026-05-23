import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_repository.dart';
import '../models/customer.dart';
import '../models/sync_queue_item.dart';
import 'package:uuid/uuid.dart';

class CustomerRepository extends BaseRepository {
  final Uuid _uuid = const Uuid();

  /// Get customers filtered by role and user ID from the local cache.
  /// If cache is empty, triggers a sync from Firestore.
  Future<List<Customer>> getCustomers({
    required String userId,
    required String role,
    required String storeId,
    List<String>? teamMemberIds,
    bool forceSync = false,
  }) async {
    final cached = localDb.getAllItems('customers');

    if (cached.isEmpty || forceSync) {
      if (await isConnected()) {
        await syncCustomersFromFirestore(storeId);
        return getLocalCustomers(userId: userId, role: role, teamMemberIds: teamMemberIds);
      }
    }

    return getLocalCustomers(userId: userId, role: role, teamMemberIds: teamMemberIds);
  }

  /// Get cached customers and filter them in memory by role
  List<Customer> getLocalCustomers({
    required String userId,
    required String role,
    List<String>? teamMemberIds,
  }) {
    final cached = localDb.getAllItems('customers');
    var list = cached.map((map) {
      // Map helper (Customer model takes DocumentSnapshot, we mock/adapt it or map fields)
      // Since Customer uses fromFirestore(DocumentSnapshot doc), we can adapt it.
      // Wait, let's see how Customer.fromFirestore was implemented or write a mapper.
      return Customer(
        id: map['id'] ?? '',
        name: map['name'] ?? '',
        phone: map['phone'] ?? '',
        email: map['email'],
        address: map['address'],
        status: map['status'] ?? 'LEAD',
        assignedTo: map['assignedTo'],
        assignedToName: map['assignedToName'],
        lastContactedAt: map['lastContactedAt'] != null ? DateTime.parse(map['lastContactedAt']) : null,
        nextFollowUpAt: map['nextFollowUpAt'] != null ? DateTime.parse(map['nextFollowUpAt']) : null,
        createdAt: map['createdAt'] != null ? DateTime.parse(map['createdAt']) : DateTime.now(),
        warranties: [], // Parse warranties if needed
        source: map['source'] ?? 'MANUAL',
      );
    }).toList();

    // Perform role filtering in-memory
    if (role == 'Sales Executive') {
      list = list.where((c) => c.assignedTo == userId).toList();
    } else if (role == 'Team Leader') {
      final ids = teamMemberIds ?? [userId];
      list = list.where((c) => ids.contains(c.assignedTo)).toList();
    }

    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

  /// Sync store-specific customers from Firestore to Hive
  Future<void> syncCustomersFromFirestore(String storeId) async {
    try {
      // Use tenant isolation if configured, fallback to top-level collection
      final collectionRef = db.collection('stores').doc(storeId).collection('customers');
      var snapshot = await collectionRef.get();
      
      // Fallback to top-level 'customers' collection if store subcollection has no records
      if (snapshot.docs.isEmpty) {
        snapshot = await db.collection('customers').where('storeId', isEqualTo: storeId).get();
      }
      
      // Secondary fallback to entire top-level 'customers' if empty
      if (snapshot.docs.isEmpty) {
        snapshot = await db.collection('customers').get();
      }

      final Map<String, Map<String, dynamic>> itemsToCache = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        
        // Parse date values to strings
        if (data['lastContactedAt'] is Timestamp) {
          data['lastContactedAt'] = (data['lastContactedAt'] as Timestamp).toDate().toIso8601String();
        }
        if (data['nextFollowUpAt'] is Timestamp) {
          data['nextFollowUpAt'] = (data['nextFollowUpAt'] as Timestamp).toDate().toIso8601String();
        }
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        }
        
        itemsToCache[doc.id] = data;
      }

      if (itemsToCache.isNotEmpty) {
        await localDb.clearBox('customers');
        await localDb.saveAllItems('customers', itemsToCache);
        await localDb.setLastSyncTime('customers', DateTime.now());
      }
    } catch (_) {}
  }

  /// Add a new customer locally and enqueue remote write
  Future<void> addCustomer(Customer customer, String storeId) async {
    final id = customer.id.isEmpty ? _uuid.v4() : customer.id;
    final map = customer.toFirestore();
    map['id'] = id;
    
    // Ensure string dates for Hive
    if (map['lastContactedAt'] is Timestamp) {
      map['lastContactedAt'] = (map['lastContactedAt'] as Timestamp).toDate().toIso8601String();
    }
    if (map['nextFollowUpAt'] is Timestamp) {
      map['nextFollowUpAt'] = (map['nextFollowUpAt'] as Timestamp).toDate().toIso8601String();
    }
    if (map['createdAt'] is Timestamp) {
      map['createdAt'] = (map['createdAt'] as Timestamp).toDate().toIso8601String();
    } else {
      map['createdAt'] = DateTime.now().toIso8601String();
    }
    map['storeId'] = storeId;

    // Save locally
    await localDb.saveItem('customers', id, map);

    // Enqueue
    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: id,
      entityType: 'customer',
      operation: 'CREATE',
      payload: map,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);
  }

  /// Update customer status or data
  Future<void> updateCustomer(Customer customer, String storeId) async {
    final map = customer.toFirestore();
    map['id'] = customer.id;
    map['storeId'] = storeId;
    
    // Dates to ISO strings
    if (map['lastContactedAt'] is Timestamp) map['lastContactedAt'] = (map['lastContactedAt'] as Timestamp).toDate().toIso8601String();
    if (map['nextFollowUpAt'] is Timestamp) map['nextFollowUpAt'] = (map['nextFollowUpAt'] as Timestamp).toDate().toIso8601String();
    if (map['createdAt'] is Timestamp) map['createdAt'] = (map['createdAt'] as Timestamp).toDate().toIso8601String();

    await localDb.saveItem('customers', customer.id, map);

    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: customer.id,
      entityType: 'customer',
      operation: 'UPDATE',
      payload: map,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);
  }

  /// Transfer customer assignment
  Future<void> transferCustomer({
    required String customerId,
    required String targetUserId,
    required String targetUserName,
    required String storeId,
  }) async {
    final cached = localDb.getItem('customers', customerId);
    if (cached != null) {
      cached['assignedTo'] = targetUserId;
      cached['assignedToName'] = targetUserName;
      cached['updatedAt'] = DateTime.now().toIso8601String();
      await localDb.saveItem('customers', customerId, cached);

      final queueItem = SyncQueueItem(
        id: _uuid.v4(),
        entityId: customerId,
        entityType: 'customer',
        operation: 'UPDATE',
        payload: {
          'assignedTo': targetUserId,
          'assignedToName': targetUserName,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: DateTime.now(),
      );
      await localDb.enqueueSyncItem(queueItem);
    }
  }
}
