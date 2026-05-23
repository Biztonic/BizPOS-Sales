import 'package:flutter/material.dart';
import '../database/local_db_service.dart';
import '../models/sync_queue_item.dart';
import 'package:uuid/uuid.dart';

/// PromotionService handles the automated hierarchy transitions:
/// - Sales Executive -> Team Leader (When monthly sales hit 2L)
/// - Team Leader -> Director (When 10 team members hit 2L)
class PromotionService {
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final Uuid _uuid = const Uuid();

  /// Checks if the agent qualifies for a promotion based on current month performance.
  /// Called after every completed transaction.
  Future<void> checkPromotions(String userId) async {
    try {
      final userData = _localDb.getItem('sync_metadata', 'user_profile_$userId');
      if (userData == null) return;

      final currentRole = userData['role'] ?? 'Sales Executive';

      if (currentRole == 'Sales Executive' || currentRole == 'Sales Agent') {
        await _checkExecutiveToTL(userId, userData);
      } else if (currentRole == 'Team Leader') {
        await _checkTLToDirector(userId, userData);
      }
    } catch (e) {
      debugPrint('Error in PromotionService: $e');
    }
  }

  /// SE -> TL Promotion Logic
  Future<void> _checkExecutiveToTL(String userId, Map<String, dynamic> userData) async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final config = _localDb.getItem('sync_metadata', 'system_config') ?? {};
    final targetAmount = (config['targetAmount'] ?? 200000.0).toDouble();

    final localTransactions = _localDb.getAllItems('sales_transactions');
    final myCompletedSales = localTransactions
        .where((t) => t['agentId'] == userId && t['targetMonth'] == currentMonth && t['status'] == 'Completed')
        .toList();

    double totalSales = 0.0;
    for (var sale in myCompletedSales) {
      totalSales += (sale['amountPaid'] ?? sale['amount'] ?? 0.0).toDouble();
    }

    if (totalSales >= targetAmount) {
      final referralCode = 'TL${userId.substring(0, 5).toUpperCase()}';
      final updateData = {
        'role': 'Team Leader',
        'referralCode': referralCode,
        'promotedAt': DateTime.now().toIso8601String(),
        'previousRole': 'Sales Executive',
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // 1. Update Cache
      final newProfile = {...userData, ...updateData};
      await _localDb.saveItem('sync_metadata', 'user_profile_$userId', newProfile);

      // 2. Queue write
      await _localDb.enqueueSyncItem(SyncQueueItem(
        id: _uuid.v4(),
        entityId: userId,
        entityType: 'sales_user',
        operation: 'UPDATE',
        payload: updateData,
        createdAt: DateTime.now(),
      ));

      debugPrint('User $userId promoted to Team Leader locally!');
    }
  }

  /// TL -> Director Promotion Logic
  Future<void> _checkTLToDirector(String userId, Map<String, dynamic> userData) async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final config = _localDb.getItem('sync_metadata', 'system_config') ?? {};
    final targetAmount = (config['targetAmount'] ?? 200000.0).toDouble();
    final quota = (config['directorPromotionQuota'] ?? 10).toInt();

    // 1. Get all team members from local db user list cache
    final List<Map<String, dynamic>> allUsers = _localDb.getAllItems('sync_metadata')
        .where((item) => item.containsKey('email') && item['teamLeaderId'] == userId)
        .toList();

    if (allUsers.isEmpty) return;

    int qualifiedMembers = 0;
    final localTransactions = _localDb.getAllItems('sales_transactions');

    // 2. For each member, check if they hit the target this month
    for (var member in allUsers) {
      final memberId = member['id'];
      final memberSales = localTransactions
          .where((t) => t['agentId'] == memberId && t['targetMonth'] == currentMonth && t['status'] == 'Completed')
          .toList();

      double memberTotalSales = 0.0;
      for (var sale in memberSales) {
        memberTotalSales += (sale['amountPaid'] ?? sale['amount'] ?? 0.0).toDouble();
      }

      if (memberTotalSales >= targetAmount) {
        qualifiedMembers++;
      }
    }

    // 3. Promote if quota reached
    if (qualifiedMembers >= quota) {
      final updateData = {
        'role': 'Director',
        'promotedAt': DateTime.now().toIso8601String(),
        'previousRole': 'Team Leader',
        'updatedAt': DateTime.now().toIso8601String(),
      };

      // Update Cache
      final newProfile = {...userData, ...updateData};
      await _localDb.saveItem('sync_metadata', 'user_profile_$userId', newProfile);

      // Queue write
      await _localDb.enqueueSyncItem(SyncQueueItem(
        id: _uuid.v4(),
        entityId: userId,
        entityType: 'sales_user',
        operation: 'UPDATE',
        payload: updateData,
        createdAt: DateTime.now(),
      ));

      debugPrint('User $userId promoted to Director locally!');
    }
  }

  /// Calculate total company turnover for the current month.
  /// Used for Director Global Pool.
  Future<double> getGlobalCompanyTurnover() async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final localTransactions = _localDb.getAllItems('sales_transactions');
    final completedSales = localTransactions
        .where((t) => t['targetMonth'] == currentMonth && t['status'] == 'Completed')
        .toList();

    double total = 0.0;
    for (var sale in completedSales) {
      total += (sale['amountPaid'] ?? sale['amount'] ?? 0.0).toDouble();
    }
    return total;
  }
}
