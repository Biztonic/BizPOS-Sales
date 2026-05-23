import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/commission.dart';
import '../repositories/commission_repository.dart';
import '../repositories/sales_repository.dart';
import '../repositories/expense_repository.dart';
import '../sync/sync_engine.dart';

class CommissionProvider with ChangeNotifier {
  final CommissionRepository _commissionRepository = CommissionRepository();
  final SalesRepository _salesRepository = SalesRepository();
  final ExpenseRepository _expenseRepository = ExpenseRepository();

  List<Commission> _commissions = [];
  Map<String, double> _commissionsByMonth = {};
  Map<String, double> _commissionsByYear = {};
  bool _isLoading = false;
  String? _error;

  double _currentMonthSales = 0.0;
  String _currentRole = 'Sales Executive';
  
  Map<String, dynamic> _globalConfig = {
    'targetAmount': 200000.0,
    'baseSalaryAtTarget': 25000.0,
    'baseCommissionRate': 10.0,
    'excessCommissionRate': 20.0,
    'teamLeaderOverrideRate': 5.0,
    'directorPoolRate': 12.0,
    'directorTargetRecruits': 10,
  };

  int _activeRecruitsCount = 0;
  double _totalCompanySalesThisMonth = 0.0;
  int _activeDirectorsCount = 1;
  bool _isPermanentDirector = false;
  double _approvedExpensesThisMonth = 0.0;
  double _teamMonthSales = 0.0;

  StreamSubscription? _syncEventsSubscription;
  String? _lastAgentId;

  // Getters
  List<Commission> get commissions => _commissions;
  Map<String, double> get commissionsByMonth => _commissionsByMonth;
  Map<String, double> get commissionsByYear => _commissionsByYear;
  bool get isLoading => _isLoading;
  String? get error => _error;
  double get currentMonthSales => _currentMonthSales;
  String get currentRole => _currentRole;
  double get targetAmount => (_globalConfig['targetAmount'] ?? 200000.0).toDouble();
  double get progressToTarget => targetAmount > 0 ? (_currentMonthSales / targetAmount).clamp(0.0, 1.0) : 0.0;
  int get activeRecruitsCount => _activeRecruitsCount;
  int get recruitsTarget => _globalConfig['directorTargetRecruits'] ?? 10;
  double get progressToDirector => recruitsTarget > 0 ? (_activeRecruitsCount / recruitsTarget).clamp(0.0, 1.0) : 0.0;
  double get teamMonthSales => _teamMonthSales;
  double get approvedExpensesThisMonth => _approvedExpensesThisMonth;

  double get monthlySalary => (_currentMonthSales >= targetAmount) ? (_globalConfig['baseSalaryAtTarget'] ?? 25000.0).toDouble() : 0.0;
  
  double get excessCommission {
    if (_currentMonthSales <= targetAmount) return 0.0;
    final excess = _currentMonthSales - targetAmount;
    final rate = (_globalConfig['excessCommissionRate'] ?? 20.0) / 100;
    return excess * rate;
  }

  double get teamOverride {
    if (_currentRole != 'Team Leader' && _currentRole != 'Director' && _currentRole != 'SuperAdmin') return 0.0;
    final rate = (_globalConfig['teamLeaderOverrideRate'] ?? 5.0) / 100;
    return _teamMonthSales * rate;
  }
  
  double get globalPoolShare {
    if (_currentRole != 'Director' && _currentRole != 'SuperAdmin') return 0.0;
    final totalPool = _totalCompanySalesThisMonth * ((_globalConfig['directorPoolRate'] ?? 12.0) / 100);
    return totalPool / (_activeDirectorsCount > 0 ? _activeDirectorsCount : 1);
  }

  double get baseEarnings {
    if (_currentMonthSales >= targetAmount) {
      return monthlySalary + excessCommission + teamOverride + globalPoolShare;
    } else {
      return _currentMonthSales * ((_globalConfig['baseCommissionRate'] ?? 10.0) / 100);
    }
  }

  double get totalMonthlyEstimate => baseEarnings + _approvedExpensesThisMonth;
  double get totalEarned => _commissions.fold(0.0, (sum, c) => sum + c.amount);
  double get totalPending => _commissions.where((c) => c.status == 'Pending').fold(0.0, (sum, c) => sum + c.amount);

  CommissionProvider() {
    fetchGlobalConfig();
    _listenToSyncEvents();
  }

  void _listenToSyncEvents() {
    _syncEventsSubscription?.cancel();
    _syncEventsSubscription = SyncEngine().syncEvents.listen((entityType) {
      if (entityType == 'commission' || entityType == 'transaction' || entityType == 'expense') {
        debugPrint("CommissionProvider: Sync event $entityType detected. Recalculating...");
        if (_lastAgentId != null) {
          _recalculateMonthlyProgress(_lastAgentId!);
          _reloadCommissions(_lastAgentId!);
        }
      }
    });
  }

  Future<void> fetchGlobalConfig() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('system_settings').doc('global_config').get();
      if (doc.exists && doc.data() != null) {
        _globalConfig = doc.data()!;
        notifyListeners();
      }
    } catch (_) {}
  }

  void startListeningToProgress({
    required String agentId,
    required String role,
    bool isPermanentDirector = false,
    DateTime? selectedMonth,
  }) {
    _lastAgentId = agentId;
    _currentRole = role;
    _isPermanentDirector = isPermanentDirector;

    _recalculateMonthlyProgress(agentId, selectedMonth: selectedMonth);
    _reloadCommissions(agentId);
  }

  void _recalculateMonthlyProgress(String agentId, {DateTime? selectedMonth}) {
    final targetDate = selectedMonth ?? DateTime.now();
    final currentMonth = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}';

    // 1. Calculate user's monthly direct sales locally from Hive box (No Firestore reads!)
    final localTransactions = _salesRepository.getLocalTransactions();
    final myCompletedSales = localTransactions
        .where((t) => t.agentId == agentId && t.targetMonth == currentMonth && t.status == 'Completed')
        .toList();
    
    _currentMonthSales = myCompletedSales.fold(0.0, (sum, t) => sum + t.amountPaid);

    // 2. Calculate Team Sales locally (Offline-friendly join - N+1 Firestore queries avoided!)
    final teamMembers = _commissionRepository.localDb.getAllItems('customers'); // using generic lookups
    final teamMemberIds = _commissionRepository.localDb
        .getAllItems('sync_metadata')
        .where((item) => item['teamLeaderId'] == agentId)
        .map((item) => item['id'] as String)
        .toList();
    
    _teamMonthSales = localTransactions
        .where((t) => teamMemberIds.contains(t.agentId) && t.targetMonth == currentMonth && t.status == 'Completed')
        .fold(0.0, (sum, t) => sum + t.amountPaid);

    // 3. Compute Approved Expenses locally
    final localExpenses = _expenseRepository.getLocalExpenses(agentId);
    _approvedExpensesThisMonth = localExpenses
        .where((e) => e.status == 'Approved')
        .fold(0.0, (sum, e) => sum + e.amount);

    // 4. Calculate total company sales for pool allocation locally
    _totalCompanySalesThisMonth = localTransactions
        .where((t) => t.targetMonth == currentMonth && t.status == 'Completed')
        .fold(0.0, (sum, t) => sum + t.amountPaid);

    // 5. Count active directors locally
    final allProfiles = _commissionRepository.localDb.getAllItems('sync_metadata');
    final directors = allProfiles.where((p) => p['role'] == 'Director').toList();
    _activeDirectorsCount = directors.isNotEmpty ? directors.length : 1;

    // 6. Recruits achievement tracking
    final allAchievements = _commissionRepository.localDb.getAllItems('sync_metadata');
    _activeRecruitsCount = allAchievements
        .where((a) => a['teamLeaderId'] == agentId && a['month'] == currentMonth)
        .length;

    notifyListeners();
  }

  void _reloadCommissions(String agentId) {
    _commissions = _commissionRepository.getLocalCommissions(agentId);
    _calculateStats();
    notifyListeners();
  }

  void startListeningToCommissions({required String agentId}) {
    _lastAgentId = agentId;
    _reloadCommissions(agentId);
  }

  Future<void> fetchCommissions(String userId) async {
    _lastAgentId = userId;
    _isLoading = true;
    notifyListeners();
    try {
      _commissions = await _commissionRepository.getCommissions(agentId: userId);
      _calculateStats();
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  void _calculateStats() {
    _commissionsByMonth = {};
    _commissionsByYear = {};

    for (var commission in _commissions) {
      final date = commission.createdAt;
      final monthKey = '${date.year}-${date.month.toString().padLeft(2, '0')}';
      final yearKey = '${date.year}';

      _commissionsByMonth[monthKey] = (_commissionsByMonth[monthKey] ?? 0.0) + commission.amount;
      _commissionsByYear[yearKey] = (_commissionsByYear[yearKey] ?? 0.0) + commission.amount;
    }
  }

  Future<bool> markAsPaid(String commissionId) async {
    try {
      // Mark as Paid locally first, then enqueue
      final index = _commissions.indexWhere((c) => c.id == commissionId);
      if (index != -1) {
        _commissions[index] = _commissions[index].copyWith(status: 'Paid');
        
        final Map<String, dynamic> updatePayload = {
          'status': 'Paid',
          'paidAt': DateTime.now().toIso8601String(),
          'updatedAt': DateTime.now().toIso8601String(),
        };
        await _commissionRepository.localDb.saveItem('commissions', commissionId, {
          ..._commissions[index].toMap(),
          ...updatePayload,
        });

        // Enqueue remote write
        await _commissionRepository.localDb.enqueueSyncItem(SyncQueueItem(
          id: UniqueKey().toString(),
          entityId: commissionId,
          entityType: 'commission',
          operation: 'UPDATE',
          payload: updatePayload,
          createdAt: DateTime.now(),
        ));

        _calculateStats();
        notifyListeners();
        SyncEngine().flushQueue();
      }
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _syncEventsSubscription?.cancel();
    super.dispose();
  }
}
