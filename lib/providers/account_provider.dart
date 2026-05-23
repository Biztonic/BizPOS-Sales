import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';
import '../repositories/expense_repository.dart';
import '../repositories/commission_repository.dart';
import '../sync/sync_engine.dart';

class AccountProvider with ChangeNotifier {
  final ExpenseRepository _expenseRepository = ExpenseRepository();
  final CommissionRepository _commissionRepository = CommissionRepository();

  List<Expense> _myExpenses = [];
  List<Expense> _pendingApprovals = [];
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  bool _isLoading = false;
  String? _error;

  String? _lastUserId;
  String? _lastRole;

  StreamSubscription? _syncEventsSubscription;

  // Getters
  List<Expense> get myExpenses => _myExpenses;
  List<Expense> get pendingApprovals => _pendingApprovals;
  double get totalIncome => _totalIncome;
  double get totalExpenses => _totalExpenses;
  double get netBalance => _totalIncome - _totalExpenses;
  bool get isLoading => _isLoading;
  String? get error => _error;

  AccountProvider() {
    _listenToSyncEvents();
  }

  void _listenToSyncEvents() {
    _syncEventsSubscription?.cancel();
    _syncEventsSubscription = SyncEngine().syncEvents.listen((entityType) {
      if (entityType == 'expense' || entityType == 'commission') {
        debugPrint("AccountProvider: Sync event $entityType detected. Reloading data...");
        if (_lastUserId != null) {
          _reloadLocalData(_lastUserId!, _lastRole ?? 'Sales Executive');
        }
      }
    });
  }

  void _reloadLocalData(String userId, String role) {
    _myExpenses = _expenseRepository.getLocalExpenses(userId);
    _pendingApprovals = _expenseRepository.getLocalPendingApprovals(userId, role);
    _totalExpenses = _myExpenses
        .where((e) => e.status == 'Approved')
        .fold(0.0, (s, e) => s + e.amount);
    _totalIncome = _commissionRepository.getCachedTotalIncome(userId);
    notifyListeners();
  }

  Future<void> fetchTotalIncome(String userId) async {
    _totalIncome = _commissionRepository.getCachedTotalIncome(userId);
    notifyListeners();
  }

  void startListeningToMyExpenses(String userId) {
    _lastUserId = userId;
    _myExpenses = _expenseRepository.getLocalExpenses(userId);
    _totalExpenses = _myExpenses
        .where((e) => e.status == 'Approved')
        .fold(0.0, (s, e) => s + e.amount);
    notifyListeners();
  }

  void startListeningToPendingApprovals({
    required String userId,
    required String role,
    bool isPermanentDirector = false,
  }) {
    _lastUserId = userId;
    _lastRole = role;
    _pendingApprovals = _expenseRepository.getLocalPendingApprovals(userId, role);
    notifyListeners();
  }

  Future<bool> addExpense({
    required String userId,
    required String userName,
    required String userRole,
    bool isPermanentDirector = false,
    String? teamLeaderId,
    required String title,
    required String description,
    required double amount,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      int requiredApprovals = 2;
      
      final bool effectivelyDirector = (userRole == 'Director' && isPermanentDirector) || userRole == 'SuperAdmin';
      final bool effectivelyTeamLeader = userRole == 'Team Leader' || (userRole == 'Director' && !isPermanentDirector);

      if (userRole == 'Sales Executive') {
        requiredApprovals = 2; 
      } else if (effectivelyTeamLeader) {
        requiredApprovals = 2; 
      } else if (effectivelyDirector) {
        // Safe count for offline-first: default to 2 or check cache count
        final directorProfiles = _expenseRepository.localDb.getAllItems('sync_metadata')
            .where((p) => p['role'] == 'Director').toList();
        final otherPermanentDirectors = directorProfiles.where((d) => d['id'] != userId).length;
        requiredApprovals = otherPermanentDirectors > 0 ? otherPermanentDirectors : 1;
      }

      final expense = Expense(
        id: '',
        userId: userId,
        userName: userName,
        userRole: userRole,
        teamLeaderId: teamLeaderId,
        title: title,
        description: description,
        amount: amount,
        requiredApprovals: requiredApprovals,
      );

      await _expenseRepository.addExpense(expense);
      _reloadLocalData(userId, userRole);
      
      _isLoading = false;
      notifyListeners();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to add expense: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> actOnExpense({
    required String expenseId,
    required String approverId,
    required String approverName,
    required String approverRole,
    required String decision,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final cached = _expenseRepository.localDb.getItem('expenses', expenseId);
      if (cached == null) {
        _error = 'Expense not found.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final expense = Expense.fromMap(cached, expenseId);

      if (expense.approvals.any((a) => a.approverId == approverId)) {
        _error = 'You have already acted on this expense.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (decision == 'Rejected') {
        await _expenseRepository.rejectExpense(expenseId);
      } else {
        final newApproval = ExpenseApproval(
          approverId: approverId,
          approverName: approverName,
          approverRole: approverRole,
          decision: 'Approved',
          approvedAt: DateTime.now(),
        );

        final totalApprovals = expense.approvals.where((a) => a.decision == 'Approved').length + 1;
        String newStatus = totalApprovals >= expense.requiredApprovals ? 'Approved' : 'PartiallyApproved';

        await _expenseRepository.approveExpense(
          expenseId: expenseId,
          approval: newApproval,
          targetStatus: newStatus,
        );
      }

      if (_lastUserId != null) {
        _reloadLocalData(_lastUserId!, _lastRole ?? 'Sales Executive');
      }

      _isLoading = false;
      notifyListeners();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to process approval: $e';
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
