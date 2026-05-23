import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/expense.dart';

/// AccountProvider manages income (commissions) and expenses for a sales user.
/// Handles the multi-tier expense approval workflow:
///   - Sales Executive: Team Leader (stage 1) → Any Director (stage 2)
///   - Team Leader: Any 2 Directors
///   - Director: ALL remaining Directors
class AccountProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Expense> _myExpenses = [];
  List<Expense> _pendingApprovals = [];
  double _totalIncome = 0.0;
  double _totalExpenses = 0.0;
  bool _isLoading = false;
  String? _error;

  // Getters
  List<Expense> get myExpenses => _myExpenses;
  List<Expense> get pendingApprovals => _pendingApprovals;
  double get totalIncome => _totalIncome;
  double get totalExpenses => _totalExpenses;
  double get netBalance => _totalIncome - _totalExpenses;
  bool get isLoading => _isLoading;
  String? get error => _error;

  StreamSubscription? _expensesSubscription;
  StreamSubscription? _approvalsSubscription;

  /// Fetches the user's total commission income (all time).
  Future<void> fetchTotalIncome(String userId) async {
    try {
      final snapshot = await _db.collection('commissions')
          .where('agentId', isEqualTo: userId)
          .get();

      double total = 0.0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['amount'] ?? 0.0).toDouble();
      }
      _totalIncome = total;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching total income: $e');
    }
  }

  /// Listens to the user's own expenses in real-time.
  void startListeningToMyExpenses(String userId) {
    _expensesSubscription?.cancel();
    _expensesSubscription = _db.collection('expenses')
        .where('userId', isEqualTo: userId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          _myExpenses = snapshot.docs
              .map((doc) => Expense.fromMap(doc.data(), doc.id))
              .toList();
          _totalExpenses = _myExpenses
              .where((e) => e.status == 'Approved')
              .fold(0.0, (s, e) => s + e.amount);
          notifyListeners();
        }, onError: (e) {
          debugPrint('Error listening to expenses: $e');
        });
  }

  /// Listens to expenses that the current user can approve.
  /// 
  /// Approval rules:
  /// - Team Leader sees pending expenses from their team members (Sales Executives)
  /// - Director sees:
  ///   a) SE expenses that have been approved by TL but still need Director approval
  ///   b) TL expenses that need 2 Director approvals
  ///   c) Other Director expenses that need all-Director approval
  /// - SuperAdmin acts as Director for approval purposes.
  void startListeningToPendingApprovals({
    required String userId,
    required String role,
    bool isPermanentDirector = false,
  }) {
    _approvalsSubscription?.cancel();

    if (role == 'Sales Executive') {
      _pendingApprovals = [];
      notifyListeners();
      return;
    }

    // For Team Leaders: fetch pending SE expenses assigned to them
    // For Directors/SuperAdmin: fetch all expenses that need Director-level approval
    _approvalsSubscription = _db.collection('expenses')
        .where('status', whereIn: ['Pending', 'PartiallyApproved'])
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen((snapshot) {
          final allPending = snapshot.docs
              .map((doc) => Expense.fromMap(doc.data(), doc.id))
              .toList();

          // Filter to only show expenses this user can act on
          _pendingApprovals = allPending.where((expense) {
            // Don't show the user their own expenses
            if (expense.userId == userId) return false;

            // Check if this user has already approved/rejected
            final alreadyActed = expense.approvals.any((a) => a.approverId == userId);
            if (alreadyActed) return false;

            // Logic refinement: Temporary Directors act as Team Leaders
            final bool actsAsDirector = (role == 'Director' && isPermanentDirector) || role == 'SuperAdmin';
            final bool actsAsTeamLeader = role == 'Team Leader' || (role == 'Director' && !isPermanentDirector);

            if (actsAsTeamLeader) {
              // TL can approve SE expenses from their team (stage 1)
              // Stage 1: No approvals yet
              return expense.userRole == 'Sales Executive' &&
                     expense.teamLeaderId == userId &&
                     expense.approvals.isEmpty;
            }

            if (actsAsDirector) {
              // Director can approve:
              // 1. SE expenses:
              if (expense.userRole == 'Sales Executive') {
                // Stage 1: If I am the direct team leader/manager, I can approve first
                if (expense.teamLeaderId == userId && expense.approvals.isEmpty) return true;
                
                // Stage 2: If it already has one approval (from TL or another Director acting as manager), 
                // and it's partially approved, any Director can approve it.
                final hasFirstApproval = expense.approvals.isNotEmpty;
                return hasFirstApproval && expense.status == 'PartiallyApproved';
              }
              // 2. TL expenses (need 2 director approvals)
              if (expense.userRole == 'Team Leader') {
                return true;
              }
              // 3. Other Director expenses (need all remaining permanent directors)
              if (expense.userRole == 'Director' || expense.userRole == 'SuperAdmin') {
                return true;
              }
              return false;
            }

            return false;
          }).toList();

          notifyListeners();
        }, onError: (e) {
          debugPrint('Error listening to pending approvals: $e');
        });
  }

  /// Adds a new expense for the current user.
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
      // Calculate required approvals based on role
      int requiredApprovals;
      
      // Determine effective role for approval logic
      final bool effectivelyDirector = (userRole == 'Director' && isPermanentDirector) || userRole == 'SuperAdmin';
      final bool effectivelyTeamLeader = userRole == 'Team Leader' || (userRole == 'Director' && !isPermanentDirector);

      if (userRole == 'Sales Executive') {
        // Stage 1: Team Leader, Stage 2: 1 Permanent Director
        requiredApprovals = 2; 
      } else if (effectivelyTeamLeader) {
        // Any 2 Permanent Directors
        requiredApprovals = 2; 
      } else if (effectivelyDirector) {
        // Permanent Director: need all other permanent directors to approve
        final directorSnapshot = await _db.collection('sales_users')
            .where('role', whereIn: ['Director', 'SuperAdmin'])
            .where('isPermanentDirector', isEqualTo: true)
            .get();
        
        // Count permanent directors excluding the submitter
        final otherPermanentDirectors = directorSnapshot.docs.where((d) => d.id != userId).length;
        requiredApprovals = otherPermanentDirectors > 0 ? otherPermanentDirectors : 1;
      } else {
        requiredApprovals = 1;
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

      await _db.collection('expenses').add(expense.toMap());

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to add expense: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Approves or rejects an expense.
  Future<bool> actOnExpense({
    required String expenseId,
    required String approverId,
    required String approverName,
    required String approverRole,
    required String decision, // 'Approved' or 'Rejected'
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final docRef = _db.collection('expenses').doc(expenseId);
      final doc = await docRef.get();
      if (!doc.exists) {
        _error = 'Expense not found.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      final expense = Expense.fromMap(doc.data()!, doc.id);

      // Prevent double approval
      if (expense.approvals.any((a) => a.approverId == approverId)) {
        _error = 'You have already acted on this expense.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      if (decision == 'Rejected') {
        await docRef.update({
          'status': 'Rejected',
          'approvals': FieldValue.arrayUnion([
            ExpenseApproval(
              approverId: approverId,
              approverName: approverName,
              approverRole: approverRole,
              decision: 'Rejected',
            ).toMap(),
          ]),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        _isLoading = false;
        notifyListeners();
        return true;
      }

      // Approval logic
      final newApproval = ExpenseApproval(
        approverId: approverId,
        approverName: approverName,
        approverRole: approverRole,
        decision: 'Approved',
      );

      final updatedApprovals = [...expense.approvals, newApproval];
      final totalApprovals = updatedApprovals.where((a) => a.decision == 'Approved').length;

      String newStatus;
      if (totalApprovals >= expense.requiredApprovals) {
        newStatus = 'Approved';
      } else {
        newStatus = 'PartiallyApproved';
      }

      await docRef.update({
        'status': newStatus,
        'approvals': updatedApprovals.map((a) => a.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _isLoading = false;
      notifyListeners();
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
    _expensesSubscription?.cancel();
    _approvalsSubscription?.cancel();
    super.dispose();
  }
}
