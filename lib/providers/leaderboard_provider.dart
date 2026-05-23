import 'package:flutter/material.dart';
import '../database/local_db_service.dart';
import '../sync/sync_engine.dart';
import 'dart:async';

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
  final LocalDatabaseService _localDb = LocalDatabaseService();

  List<LeaderboardEntry> _entries = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _syncEventsSubscription;

  bool _lastIsAllTime = false;
  DateTime? _lastSelectedMonth;

  List<LeaderboardEntry> get entries => _entries;
  bool get isLoading => _isLoading;
  String? get error => _error;

  LeaderboardProvider() {
    _listenToSyncEvents();
  }

  void _listenToSyncEvents() {
    _syncEventsSubscription?.cancel();
    _syncEventsSubscription = SyncEngine().syncEvents.listen((entityType) {
      if (entityType == 'transaction') {
        debugPrint("LeaderboardProvider: Sync event detected. Recalculating leaderboard...");
        fetchLeaderboard(isAllTime: _lastIsAllTime, selectedMonth: _lastSelectedMonth);
      }
    });
  }

  Future<void> fetchLeaderboard({bool isAllTime = false, DateTime? selectedMonth}) async {
    _lastIsAllTime = isAllTime;
    _lastSelectedMonth = selectedMonth;

    _isLoading = true;
    _error = null;
    Future.microtask(() => notifyListeners());

    try {
      // 1. Fetch all cached user profiles
      final List<Map<String, dynamic>> allUsers = _localDb.getAllItems('sync_metadata')
          .where((item) => item.containsKey('email'))
          .toList();

      final Map<String, Map<String, dynamic>> usersMap = {};
      for (var user in allUsers) {
        if (user['id'] != null) {
          usersMap[user['id']] = user;
        }
      }

      // 2. Fetch all completed sales locally
      final cachedTransactions = _localDb.getAllItems('sales_transactions');
      
      final targetDate = selectedMonth ?? DateTime.now();
      final currentMonth = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}';

      final salesList = cachedTransactions.where((t) {
        final isCompleted = t['status'] == 'Completed';
        if (!isCompleted) return false;
        
        if (!isAllTime) {
          return t['targetMonth'] == currentMonth;
        }
        return true;
      }).toList();

      // 3. Aggregate sales by agentId
      final Map<String, double> salesByAgent = {};
      for (var transaction in salesList) {
        final agentId = transaction['agentId'] as String?;
        if (agentId != null) {
          final amount = (transaction['amountPaid'] ?? transaction['amount'] ?? 0.0).toDouble();
          salesByAgent[agentId] = (salesByAgent[agentId] ?? 0.0) + amount;
        }
      }

      // 4. Build entries list
      final List<LeaderboardEntry> newEntries = [];
      for (var agentId in usersMap.keys) {
        final userData = usersMap[agentId]!;
        final totalSales = salesByAgent[agentId] ?? 0.0;
        
        // Exclude users with zero business for the selected period
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

  @override
  void dispose() {
    _syncEventsSubscription?.cancel();
    super.dispose();
  }
}
