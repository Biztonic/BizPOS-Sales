import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';
import '../database/local_db_service.dart';
import '../sync/sync_engine.dart';
import '../models/sync_queue_item.dart';
import 'dart:async';

class TeamProvider with ChangeNotifier {
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _teamMembers = [];
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _syncEventsSubscription;
  String? _lastLeaderId;
  bool _lastIsSuperAdmin = false;

  List<Map<String, dynamic>> get teamMembers => _teamMembers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  TeamProvider() {
    _listenToSyncEvents();
  }

  void _listenToSyncEvents() {
    _syncEventsSubscription?.cancel();
    _syncEventsSubscription = SyncEngine().syncEvents.listen((entityType) {
      if (entityType == 'transaction' || entityType == 'commission' || entityType == 'quotation') {
        debugPrint("TeamProvider: Sync event $entityType detected. Recalculating team members stats...");
        if (_lastLeaderId != null) {
          fetchTeamMembers(_lastLeaderId!, isSuperAdmin: _lastIsSuperAdmin);
        }
      }
    });
  }

  /// Fetch users based on hierarchy from local Hive database
  Future<void> fetchTeamMembers(String leaderId, {bool isSuperAdmin = false}) async {
    _lastLeaderId = leaderId;
    _lastIsSuperAdmin = isSuperAdmin;
    _isLoading = true;
    _error = null;
    Future.microtask(() => notifyListeners());

    try {
      final now = DateTime.now();
      final currentMonth = DateFormat('yyyy-MM').format(now);
      
      // Load all cached user profiles from local store
      final List<Map<String, dynamic>> allUsers = _localDb.getAllItems('sync_metadata')
          .where((item) => item.containsKey('email')) // filters users
          .toList();

      List<Map<String, dynamic>> members = [];
      if (!isSuperAdmin) {
        members = allUsers.where((u) => u['teamLeaderId'] == leaderId).toList();
      } else {
        members = allUsers.where((u) => u['id'] != leaderId).toList();
      }

      if (members.isEmpty) {
        _teamMembers = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      // Load cached collections locally
      final cachedTransactions = _localDb.getAllItems('sales_transactions');
      final cachedCommissions = _localDb.getAllItems('commissions');
      final cachedQuotations = _localDb.getAllItems('quotations');

      // Aggregate data in memory
      for (var member in members) {
        final memberId = member['id'];
        
        // 1. Calculate Monthly Sales
        double monthlySales = cachedTransactions
            .where((t) => t['agentId'] == memberId && t['targetMonth'] == currentMonth && t['status'] == 'Completed')
            .fold(0.0, (sum, t) => sum + (t['amountPaid'] ?? t['amount'] ?? 0.0));

        // 2. Calculate Commissions
        double monthlyComm = cachedCommissions
            .where((c) => c['agentId'] == memberId)
            .fold(0.0, (sum, c) => sum + (c['amount'] ?? 0.0));

        // 3. Count Pending Quotes
        int activeQuotes = cachedQuotations
            .where((q) => q['agentId'] == memberId && q['status'] == 'PENDING')
            .length;

        member['monthlySales'] = monthlySales;
        member['totalCommission'] = monthlyComm;
        member['activeQuotes'] = activeQuotes;
      }

      _teamMembers = members;
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch team members: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Create a new Sales Executive under this Team Leader
  Future<bool> recruitSalesExecutive({
    required String leaderId,
    required String name,
    required String email,
  }) async {
    _isLoading = true;
    notifyListeners();

    try {
      final id = UniqueKey().toString();
      final Map<String, dynamic> userMap = {
        'id': id,
        'name': name,
        'email': email.trim(),
        'role': 'Sales Executive',
        'teamLeaderId': leaderId,
        'createdAt': DateTime.now().toIso8601String(),
        'appSource': 'bizpos_sales',
      };

      // Save locally
      await _localDb.saveItem('sync_metadata', id, userMap);

      // Enqueue
      await _localDb.enqueueSyncItem(SyncQueueItem(
        id: UniqueKey().toString(),
        entityId: id,
        entityType: 'sales_user',
        operation: 'CREATE',
        payload: userMap,
        createdAt: DateTime.now(),
      ));

      _teamMembers.add(userMap);
      _isLoading = false;
      notifyListeners();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to recruit SE: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncEventsSubscription?.cancel();
    super.dispose();
  }
}
