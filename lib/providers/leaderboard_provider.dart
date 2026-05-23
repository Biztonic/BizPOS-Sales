import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LeaderboardEntry {
  final String agentId;
  final String agentName;
  final String role;
  final double totalSales;
  
  LeaderboardEntry({
    required this.agentId,
    required this.agentName,
    required this.role,
    required this.totalSales,
  });
}

class LeaderboardProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<LeaderboardEntry> _entries = [];
  bool _isLoading = false;
  String? _error;

  List<LeaderboardEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> fetchLeaderboard({bool isAllTime = false, DateTime? selectedMonth}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      // 1. Fetch all users
      final usersSnapshot = await _db.collection('sales_users').get();
      final Map<String, Map<String, dynamic>> usersMap = {};
      for (var doc in usersSnapshot.docs) {
        usersMap[doc.id] = doc.data();
      }

      // 2. Fetch all completed sales
      var query = _db.collection('sales_transactions').where('status', isEqualTo: 'Completed');
      
      if (!isAllTime) {
        final targetDate = selectedMonth ?? DateTime.now();
        final currentMonth = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}';
        query = query.where('targetMonth', isEqualTo: currentMonth);
      }

      final salesSnapshot = await query.get();

      // 3. Aggregate sales by agentId
      final Map<String, double> salesByAgent = {};
      for (var doc in salesSnapshot.docs) {
        final data = doc.data();
        final agentId = data['agentId'] as String?;
        if (agentId != null) {
          final amount = (data['amountPaid'] ?? data['amount'] ?? 0.0).toDouble();
          salesByAgent[agentId] = (salesByAgent[agentId] ?? 0.0) + amount;
        }
      }

      // 4. Build entries list
      final List<LeaderboardEntry> newEntries = [];
      for (var agentId in usersMap.keys) {
        final userData = usersMap[agentId]!;
        // Exclude SuperAdmin as they usually don't have sales, but if they do we can include them. Let's exclude.
        // Include all roles in the leaderboard as per user request
        // if (userData['role'] == 'SuperAdmin') continue;
        
        final totalSales = salesByAgent[agentId] ?? 0.0;
        
        // Exclude users with zero business for the selected period
        // Only show users who actually have sales
        if (totalSales <= 0) continue;

        newEntries.add(LeaderboardEntry(
          agentId: agentId,
          agentName: userData['name'] ?? 'Unknown Agent',
          role: userData['role'] ?? 'Sales Executive',
          totalSales: totalSales,
        ));
      }

      // 5. Sort entries descending
      newEntries.sort((a, b) => b.totalSales.compareTo(a.totalSales));

      _entries = newEntries;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch leaderboard: $e';
      _isLoading = false;
      notifyListeners();
    }
  }
}
