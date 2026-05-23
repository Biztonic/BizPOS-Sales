import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_repository.dart';
import '../models/expense.dart';
import '../models/sync_queue_item.dart';
import 'package:uuid/uuid.dart';

class ExpenseRepository extends BaseRepository {
  final Uuid _uuid = const Uuid();

  Future<List<Expense>> getMyExpenses({
    required String userId,
    bool forceSync = false,
  }) async {
    final cached = localDb.getAllItems('expenses');

    if (cached.isEmpty || forceSync) {
      if (await isConnected()) {
        await syncExpensesFromFirestore(userId);
        return getLocalExpenses(userId);
      }
    }

    return getLocalExpenses(userId);
  }

  List<Expense> getLocalExpenses(String userId) {
    final cached = localDb.getAllItems('expenses');
    final list = cached
        .map((map) => Expense.fromMap(map, map['id'] ?? ''))
        .where((e) => e.userId == userId)
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Get pending approvals where this user can approve
  List<Expense> getLocalPendingApprovals(String userId, String role) {
    final cached = localDb.getAllItems('expenses');
    final list = cached
        .map((map) => Expense.fromMap(map, map['id'] ?? ''))
        .where((e) => e.status == 'Pending' || e.status == 'PartiallyApproved')
        .where((e) {
          // Check if user has already approved
          final alreadyApproved = e.approvals.any((a) => a.approverId == userId);
          if (alreadyApproved) return false;

          // Role-based approval authority validation
          if (role == 'Team Leader') {
            // Team Leader can approve their team members' expenses
            // (Subordinates logic)
            return e.userRole == 'Sales Executive';
          } else if (role == 'Director' || role == 'SuperAdmin') {
            // Directors and Admins can approve anything
            return true;
          }
          return false;
        })
        .toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> syncExpensesFromFirestore(String userId) async {
    try {
      // Sync my expenses
      final snapshot = await db
          .collection('expenses')
          .where('userId', isEqualTo: userId)
          .limit(100)
          .get();

      // Sync pending approvals
      final approvalsSnapshot = await db
          .collection('expenses')
          .where('status', whereIn: ['Pending', 'PartiallyApproved'])
          .limit(100)
          .get();

      final Map<String, Map<String, dynamic>> itemsToCache = {};
      
      void processDoc(QueryDocumentSnapshot doc) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;

        if (data['createdAt'] is Timestamp) data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        if (data['updatedAt'] is Timestamp) data['updatedAt'] = (data['updatedAt'] as Timestamp).toDate().toIso8601String();

        // Process nested approvals list
        final list = data['approvals'] as List?;
        if (list != null) {
          final mappedApprovals = [];
          for (var app in list) {
            final appMap = Map<String, dynamic>.from(app);
            if (appMap['approvedAt'] is Timestamp) {
              appMap['approvedAt'] = (appMap['approvedAt'] as Timestamp).toDate().toIso8601String();
            }
            mappedApprovals.add(appMap);
          }
          data['approvals'] = mappedApprovals;
        }

        itemsToCache[doc.id] = data;
      }

      for (var doc in snapshot.docs) {
        processDoc(doc);
      }
      for (var doc in approvalsSnapshot.docs) {
        processDoc(doc);
      }

      if (itemsToCache.isNotEmpty) {
        await localDb.saveAllItems('expenses', itemsToCache);
        await localDb.setLastSyncTime('expenses', DateTime.now());
      }
    } catch (_) {}
  }

  /// Add new expense claim offline first
  Future<void> addExpense(Expense expense) async {
    final id = expense.id.isEmpty ? _uuid.v4() : expense.id;
    final map = expense.toMap();
    map['id'] = id;
    map['createdAt'] = DateTime.now().toIso8601String();
    map['updatedAt'] = DateTime.now().toIso8601String();

    await localDb.saveItem('expenses', id, map);

    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: id,
      entityType: 'expense',
      operation: 'CREATE',
      payload: map,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);
  }

  /// Approve expense
  Future<void> approveExpense({
    required String expenseId,
    required ExpenseApproval approval,
    required String targetStatus,
  }) async {
    final cached = localDb.getItem('expenses', expenseId);
    if (cached != null) {
      final expense = Expense.fromMap(cached, expenseId);
      final updatedApprovals = List<ExpenseApproval>.from(expense.approvals)..add(approval);
      
      cached['status'] = targetStatus;
      cached['approvals'] = updatedApprovals.map((a) => a.toMap()).toList();
      cached['updatedAt'] = DateTime.now().toIso8601String();

      await localDb.saveItem('expenses', expenseId, cached);

      final queueItem = SyncQueueItem(
        id: _uuid.v4(),
        entityId: expenseId,
        entityType: 'expense',
        operation: 'UPDATE',
        payload: {
          'status': targetStatus,
          'approvals': updatedApprovals.map((a) => a.toMap()).toList(),
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: DateTime.now(),
      );
      await localDb.enqueueSyncItem(queueItem);
    }
  }

  /// Reject expense
  Future<void> rejectExpense(String expenseId) async {
    final cached = localDb.getItem('expenses', expenseId);
    if (cached != null) {
      cached['status'] = 'Rejected';
      cached['updatedAt'] = DateTime.now().toIso8601String();

      await localDb.saveItem('expenses', expenseId, cached);

      final queueItem = SyncQueueItem(
        id: _uuid.v4(),
        entityId: expenseId,
        entityType: 'expense',
        operation: 'UPDATE',
        payload: {
          'status': 'Rejected',
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: DateTime.now(),
      );
      await localDb.enqueueSyncItem(queueItem);
    }
  }
}
