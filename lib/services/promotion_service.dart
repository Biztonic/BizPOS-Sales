import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// PromotionService handles the automated hierarchy transitions:
/// - Sales Executive -> Team Leader (When monthly sales hit 2L)
/// - Team Leader -> Director (When 10 team members hit 2L)
class PromotionService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Checks if the agent qualifies for a promotion based on current month performance.
  /// Called after every completed transaction.
  Future<void> checkPromotions(String userId) async {
    try {
      final userDoc = await _db.collection('sales_users').doc(userId).get();
      if (!userDoc.exists) return;

      final userData = userDoc.data()!;
      final currentRole = userData['role'] ?? 'Sales Executive';

      if (currentRole == 'Sales Executive' || currentRole == 'Sales Agent') {
        await _checkExecutiveToTL(userId);
      } else if (currentRole == 'Team Leader') {
        await _checkTLToDirector(userId);
      }
    } catch (e) {
      debugPrint('Error in PromotionService: $e');
    }
  }

  /// SE -> TL Promotion Logic
  Future<void> _checkExecutiveToTL(String userId) async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final configDoc = await _db.collection('system_settings').doc('global_config').get();
    final targetAmount = (configDoc.data()?['targetAmount'] ?? 200000.0).toDouble();

    final snapshot = await _db.collection('sales_transactions')
        .where('agentId', isEqualTo: userId)
        .where('targetMonth', isEqualTo: currentMonth)
        .where('status', isEqualTo: 'Completed')
        .get();

    double totalSales = 0.0;
    for (var doc in snapshot.docs) {
      totalSales += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
    }

    if (totalSales >= targetAmount) {
      await _db.collection('sales_users').doc(userId).update({
        'role': 'Team Leader',
        'promotedAt': FieldValue.serverTimestamp(),
        'previousRole': 'Sales Executive',
      });
      debugPrint('User $userId promoted to Team Leader!');
    }
  }

  /// TL -> Director Promotion Logic
  Future<void> _checkTLToDirector(String userId) async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final configDoc = await _db.collection('system_settings').doc('global_config').get();
    final targetAmount = (configDoc.data()?['targetAmount'] ?? 200000.0).toDouble();
    final quota = (configDoc.data()?['directorPromotionQuota'] ?? 10).toInt();

    // 1. Get all team members
    final teamSnapshot = await _db.collection('sales_users')
        .where('teamLeaderId', isEqualTo: userId)
        .get();

    if (teamSnapshot.docs.isEmpty) return;

    int qualifiedMembers = 0;

    // 2. For each member, check if they hit the target this month
    for (var memberDoc in teamSnapshot.docs) {
      final memberId = memberDoc.id;
      
      final salesSnapshot = await _db.collection('sales_transactions')
          .where('agentId', isEqualTo: memberId)
          .where('targetMonth', isEqualTo: currentMonth)
          .where('status', isEqualTo: 'Completed')
          .get();

      double memberTotalSales = 0.0;
      for (var saleDoc in salesSnapshot.docs) {
        memberTotalSales += (saleDoc.data()['amountPaid'] ?? saleDoc.data()['amount'] ?? 0.0).toDouble();
      }

      if (memberTotalSales >= targetAmount) {
        qualifiedMembers++;
      }
    }

    // 3. Promote if quota reached
    if (qualifiedMembers >= quota) {
      await _db.collection('sales_users').doc(userId).update({
        'role': 'Director',
        'promotedAt': FieldValue.serverTimestamp(),
        'previousRole': 'Team Leader',
      });
      debugPrint('User $userId promoted to Director!');
    }
  }

  /// Calculate total company turnover for the current month.
  /// Used for Director Global Pool.
  Future<double> getGlobalCompanyTurnover() async {
    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';

    final snapshot = await _db.collection('sales_transactions')
        .where('targetMonth', isEqualTo: currentMonth)
        .where('status', isEqualTo: 'Completed')
        .get();

    double total = 0.0;
    for (var doc in snapshot.docs) {
      total += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
    }
    return total;
  }
}
