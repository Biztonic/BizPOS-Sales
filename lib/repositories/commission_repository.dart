import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_repository.dart';
import '../models/commission.dart';
import '../models/sync_queue_item.dart';
import 'package:uuid/uuid.dart';

class CommissionRepository extends BaseRepository {
  final Uuid _uuid = const Uuid();

  Future<List<Commission>> getCommissions({
    required String agentId,
    bool forceSync = false,
  }) async {
    final cached = localDb.getAllItems('commissions');

    if (cached.isEmpty || forceSync) {
      if (await isConnected()) {
        await syncCommissionsFromFirestore(agentId);
        return getLocalCommissions(agentId);
      }
    }

    return getLocalCommissions(agentId);
  }

  List<Commission> getLocalCommissions(String agentId) {
    final cached = localDb.getAllItems('commissions');
    final list = cached
        .map((map) => Commission.fromMap(map, map['id'] ?? ''))
        .where((c) => c.agentId == agentId)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> syncCommissionsFromFirestore(String agentId) async {
    try {
      final snapshot = await db
          .collection('commissions')
          .where('agentId', isEqualTo: agentId)
          .limit(100)
          .get();

      final Map<String, Map<String, dynamic>> itemsToCache = {};
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;

        if (data['createdAt'] is Timestamp) data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        if (data['updatedAt'] is Timestamp) data['updatedAt'] = (data['updatedAt'] as Timestamp).toDate().toIso8601String();
        if (data['paidAt'] is Timestamp) data['paidAt'] = (data['paidAt'] as Timestamp).toDate().toIso8601String();

        itemsToCache[doc.id] = data;
      }

      if (itemsToCache.isNotEmpty) {
        // Since we are writing agent-specific data, put it in without clearing all
        // to avoid wiping other cached agents in multi-user/testing scenarios.
        final box = localDb.getAllItems('commissions');
        final Map<String, Map<String, dynamic>> finalCache = {};
        for (var item in box) {
          if (item['id'] != null) finalCache[item['id']] = item;
        }
        finalCache.addAll(itemsToCache);
        
        await localDb.clearBox('commissions');
        await localDb.saveAllItems('commissions', finalCache);
        await localDb.setLastSyncTime('commissions', DateTime.now());
      }
    } catch (_) {}
  }

  /// Create a new commission locally first, then enqueue
  Future<void> createCommission(Commission commission) async {
    final id = commission.id.isEmpty ? _uuid.v4() : commission.id;
    final map = commission.toMap();
    map['id'] = id;
    
    // Convert field values to ISO strings for local cache
    map['createdAt'] = DateTime.now().toIso8601String();
    map['updatedAt'] = DateTime.now().toIso8601String();

    await localDb.saveItem('commissions', id, map);

    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: id,
      entityType: 'commission',
      operation: 'CREATE',
      payload: map,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);
  }

  /// Get total income for a user from local cached commissions
  double getCachedTotalIncome(String agentId) {
    final commissions = getLocalCommissions(agentId);
    return commissions
        .where((c) => c.status == 'Approved' || c.status == 'Paid')
        .fold(0.0, (sum, c) => sum + c.amount);
  }
}
