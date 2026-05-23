import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/commission.dart';

/// CommissionProvider manages sales commission calculations, tracking, and agent promotions.
class CommissionProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Commission> _commissions = [];
  Map<String, double> _commissionsByMonth = {};
  Map<String, double> _commissionsByYear = {};
  bool _isLoading = false;
  String? _error;

  // Target Tracking
  double _currentMonthSales = 0.0;
  String _currentRole = 'Sales Executive';
  
  // Global Config from Firestore
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
  StreamSubscription? _expensesSubscription;
  StreamSubscription? _directorsSubscription;

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

  // New Getters for Dashboard
  double _teamMonthSales = 0.0;
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
      // 10% base commission if target not reached
      return _currentMonthSales * ((_globalConfig['baseCommissionRate'] ?? 10.0) / 100);
    }
  }

  double get totalMonthlyEstimate {
    // Add approved expenses as reimbursements to the base earnings
    return baseEarnings + _approvedExpensesThisMonth;
  }

  double get totalEarned => _commissions.fold(0.0, (sum, c) => sum + c.amount);
  double get totalPending => _commissions.where((c) => c.status == 'Pending').fold(0.0, (sum, c) => sum + c.amount);

  StreamSubscription? _progressSubscription;
  StreamSubscription? _commissionsSubscription;
  StreamSubscription? _recruitsSubscription;
  StreamSubscription? _companySalesSubscription;

  CommissionProvider() {
    fetchGlobalConfig();
  }

  Future<void> fetchGlobalConfig() async {
    try {
      final doc = await _db.collection('system_settings').doc('global_config').get();
      if (doc.exists) {
        _globalConfig = doc.data()!;
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Error fetching global config: $e');
    }
  }

  /// Listens to real-time sales progress for the specified month (defaults to current).
  void startListeningToProgress({required String agentId, required String role, bool isPermanentDirector = false, DateTime? selectedMonth}) {
    _progressSubscription?.cancel();
    _recruitsSubscription?.cancel();
    _companySalesSubscription?.cancel();
    _currentRole = role;
    _isPermanentDirector = isPermanentDirector;
    
    final targetDate = selectedMonth ?? DateTime.now();
    final currentMonth = '${targetDate.year}-${targetDate.month.toString().padLeft(2, '0')}';

    // 1. Listen to user's own sales progress
    _startListeningToMonthlyExpenses(agentId, selectedMonth ?? DateTime.now());

    _progressSubscription = _db.collection('sales_transactions')
        .where('agentId', isEqualTo: agentId)
        .where('targetMonth', isEqualTo: currentMonth)
        .where('status', isEqualTo: 'Completed')
        .snapshots()
        .listen((snapshot) {
          double total = 0;
          for (var doc in snapshot.docs) {
            total += (doc.data()['amountPaid'] ?? 0.0).toDouble();
          }
          
          Future.microtask(() async {
            _currentMonthSales = total;
            
            // Promotion check
            if (_currentMonthSales >= targetAmount) {
              // Record achievement for this month
              await _recordAchievement(agentId, currentMonth);
              
              if (_currentRole == 'Sales Executive') {
                _promoteToTeamLeader(agentId);
              }
            }
            notifyListeners();
          });
        });

    // 2. Fetch Team Sales
    if (_currentRole == 'Team Leader' || _currentRole == 'Director') {
      _fetchTeamSales(agentId, currentMonth);
    }

    // 2. If Team Leader or Director, listen to successful recruits for Director promotion
    if (_currentRole == 'Team Leader' || _currentRole == 'Director' || _currentRole == 'SuperAdmin') {
      _recruitsSubscription = _db.collection('monthly_achievements')
          .where('teamLeaderId', isEqualTo: agentId)
          .where('month', isEqualTo: currentMonth)
          .snapshots()
          .listen((snapshot) {
            _activeRecruitsCount = snapshot.docs.length;
            
            // Promotion Logic: Team Leader -> Director
            if (_currentRole == 'Team Leader' && _activeRecruitsCount >= recruitsTarget) {
              _promoteToDirector(agentId);
            } 
            // Maintenance Logic: Director -> Team Leader (if criteria not met for current month)
            // SuperAdmin and Manually assigned Directors are exempt from role reversal.
            else if (_currentRole == 'Director' && !_isPermanentDirector && _activeRecruitsCount < recruitsTarget) {
              _downgradeToTeamLeader(agentId);
            }
            
            notifyListeners();
          });
    }

    // 3. If Director, listen to total company sales for pool calculation
    if (_currentRole == 'Director' || _currentRole == 'SuperAdmin') {
      _companySalesSubscription = _db.collection('sales_transactions')
          .where('targetMonth', isEqualTo: currentMonth)
          .where('status', isEqualTo: 'Completed')
          .snapshots()
          .listen((snapshot) {
            double companyTotal = 0;
            for (var doc in snapshot.docs) {
              companyTotal += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
            }
            _totalCompanySalesThisMonth = companyTotal;
            notifyListeners();
          });
          
      // Also listen to total number of directors for pool division
      _directorsSubscription = _db.collection('sales_users')
          .where('role', isEqualTo: 'Director')
          .snapshots()
          .listen((snapshot) {
            _activeDirectorsCount = snapshot.docs.length > 0 ? snapshot.docs.length : 1;
            notifyListeners();
          });
    }
  }

  Future<void> _fetchTeamSales(String leaderId, String currentMonth) async {
    try {
      final teamSnapshot = await _db.collection('sales_users')
          .where('teamLeaderId', isEqualTo: leaderId)
          .get();
      
      final memberIds = teamSnapshot.docs.map((d) => d.id).toList();
      if (memberIds.isEmpty) {
        _teamMonthSales = 0.0;
        notifyListeners();
        return;
      }

      double totalTeamSales = 0.0;
      // We can query each member's sales for the month (could be optimized with a Cloud Function or aggregation)
      for (final memberId in memberIds) {
        final salesSnapshot = await _db.collection('sales_transactions')
            .where('agentId', isEqualTo: memberId)
            .where('targetMonth', isEqualTo: currentMonth)
            .where('status', isEqualTo: 'Completed')
            .get();
        for (var doc in salesSnapshot.docs) {
          totalTeamSales += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
        }
      }

      _teamMonthSales = totalTeamSales;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching team sales: $e');
    }
  }

  /// Records that a user has hit their target for the current month.
  Future<void> _recordAchievement(String userId, String month) async {
    try {
      final docId = '${userId}_$month';
      final docRef = _db.collection('monthly_achievements').doc(docId);
      final doc = await docRef.get();
      
      if (!doc.exists) {
        // Get user's team leader ID to properly credit them
        final userDoc = await _db.collection('sales_users').doc(userId).get();
        final teamLeaderId = userDoc.data()?['teamLeaderId'];
        
        await docRef.set({
          'userId': userId,
          'month': month,
          'targetAmount': targetAmount,
          'achievedAt': FieldValue.serverTimestamp(),
          'teamLeaderId': teamLeaderId,
        });
      }
    } catch (e) {
      debugPrint('Error recording achievement: $e');
    }
  }

  void startListeningToCommissions({required String agentId}) {
    _commissionsSubscription?.cancel();
    _commissionsSubscription = _db.collection('commissions')
        .where('agentId', isEqualTo: agentId)
        .snapshots()
        .listen((snapshot) {
          final fetched = snapshot.docs.map((doc) => Commission.fromMap(doc.data(), doc.id)).toList();
          fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
          _commissions = fetched;
          _calculateStats();
          notifyListeners();
        });
  }

  /// Promotes a Sales Executive to Team Leader and generates their referral code.
  Future<void> _promoteToTeamLeader(String userId) async {
    try {
      final referralCode = 'TL${userId.substring(0, 5).toUpperCase()}';
      await _db.collection('sales_users').doc(userId).update({
        'role': 'Team Leader',
        'referralCode': referralCode,
        'promotedAt': FieldValue.serverTimestamp(),
      });
      _currentRole = 'Team Leader';
      notifyListeners();
    } catch (e) {
      debugPrint('Error promoting to Team Leader: $e');
    }
  }

  /// Promotes a Team Leader to Director.
  Future<void> _promoteToDirector(String userId) async {
    try {
      await _db.collection('sales_users').doc(userId).update({
        'role': 'Director',
        'promotedToDirectorAt': FieldValue.serverTimestamp(),
      });
      _currentRole = 'Director';
      notifyListeners();
    } catch (e) {
      debugPrint('Error promoting to Director: $e');
    }
  }

  /// Reverts a Director to Team Leader if they fail to maintain monthly criteria.
  Future<void> _downgradeToTeamLeader(String userId) async {
    try {
      // We don't remove referral code or other TL attributes, just change the role.
      await _db.collection('sales_users').doc(userId).update({
        'role': 'Team Leader',
        'demotedAt': FieldValue.serverTimestamp(),
      });
      _currentRole = 'Team Leader';
      notifyListeners();
    } catch (e) {
      debugPrint('Error demoting to Team Leader: $e');
    }
  }

  /// Calculates and records commission for a single sale based on the tiered structure.
  /// 
  /// Logic:
  /// - 10% on turnover up to 199,999.
  /// - 20,000 (10% of 200k) + 5,000 bonus at exactly 200,000.
  /// - 20% on all amounts above 200,000.
  Future<void> recordSaleCommission({
    required String transactionId,
    required String agentId,
    required String agentName,
    required String storeId,
    required double saleAmount,
    String? customerId,
  }) async {
    
    // 1. FOREVER LINKAGE: Check if customer is assigned to someone else
    String actualAgentId = agentId;
    String actualAgentName = agentName;
    String actualAgentRole = 'Sales Executive';
    String? customerStoreId = storeId;
    
    if (customerId != null && customerId.isNotEmpty) {
      final customerDoc = await _db.collection('customers').doc(customerId).get();
      if (customerDoc.exists && customerDoc.data()?['assignedTo'] != null) {
        actualAgentId = customerDoc.data()!['assignedTo'];
        actualAgentName = customerDoc.data()!['name'] ?? actualAgentName;
        // Also fetch the actual agent's current data
        final agentDoc = await _db.collection('sales_users').doc(actualAgentId).get();
        if (agentDoc.exists) {
          actualAgentName = agentDoc.data()?['name'] ?? actualAgentName;
          actualAgentRole = agentDoc.data()?['role'] ?? 'Sales Executive';
        }
      } else {
        // Just fetch the role for the provided agent
        final agentDoc = await _db.collection('sales_users').doc(actualAgentId).get();
        if (agentDoc.exists) {
          actualAgentRole = agentDoc.data()?['role'] ?? 'Sales Executive';
        }
      }
    } else {
      // Fetch role for the provided agent
      final agentDoc = await _db.collection('sales_users').doc(actualAgentId).get();
      if (agentDoc.exists) {
        actualAgentRole = agentDoc.data()?['role'] ?? 'Sales Executive';
      }
    }

    final now = DateTime.now();
    final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    
    // Get current monthly sales excluding this sale for the actual agent
    final snapshot = await _db.collection('sales_transactions')
        .where('agentId', isEqualTo: actualAgentId)
        .where('targetMonth', isEqualTo: currentMonth)
        .where('status', isEqualTo: 'Completed')
        .get();
        
    double previousTotal = 0;
    for (var doc in snapshot.docs) {
      if (doc.id != transactionId) {
        previousTotal += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
      }
    }
    
    double newTotal = previousTotal + saleAmount;
    double commissionAmount = 0;
    
    // Standardized Tiered Commission Logic (for all roles doing direct sales)
    final baseRate = ((_globalConfig['baseCommissionRate'] ?? 10.0) as num).toDouble() / 100;
    final excessRate = ((_globalConfig['excessCommissionRate'] ?? 20.0) as num).toDouble() / 100;
    final target = targetAmount; 
    
    double rate = baseRate * 100;
    String description = 'Direct Sale Commission (${(baseRate * 100).toStringAsFixed(0)}%)';

    if (newTotal < target) {
      commissionAmount = saleAmount * baseRate;
      rate = baseRate * 100;
    } else if (previousTotal < target && newTotal >= target) {
      // Part 1: Amount below target
      double amountBelow = target - previousTotal;
      commissionAmount += amountBelow * baseRate;
      
      // Bonus for hitting the target
      final targetBonus = ((_globalConfig['targetBonus'] ?? 5000.0) as num).toDouble();
      commissionAmount += targetBonus;
      description = 'Direct Sale Commission (Reached Target) + ₹${targetBonus.toInt()} Bonus';
      
      // Part 2: Amount above target
      double amountAbove = newTotal - target;
      if (amountAbove > 0) {
        commissionAmount += amountAbove * excessRate;
      }
      rate = (commissionAmount / saleAmount) * 100; 
    } else {
      // Already above target
      commissionAmount = saleAmount * excessRate;
      rate = excessRate * 100;
      description = 'Direct Sale Commission (${(excessRate * 100).toStringAsFixed(0)}% Excess Tier)';
    }

    final commission = Commission(
      id: '',
      agentId: actualAgentId,
      agentName: actualAgentName,
      storeId: storeId,
      transactionId: transactionId,
      saleAmount: saleAmount,
      rate: rate,
      amount: commissionAmount,
      type: 'Commission',
      status: 'Pending',
    );

    await _db.collection('commissions').add({
      ...commission.toMap(),
      'description': description, // For UI display
    });

    // Process overrides for Team Leader and Director (Indirect income)
    await _processOverrides(actualAgentId, saleAmount, transactionId, storeId);
    
    // Process Pool income for all Directors (Indirect income)
    await _processDirectorPool(saleAmount, transactionId, storeId);
  }

  Future<void> _processDirectorPool(double saleAmount, String transactionId, String storeId) async {
    try {
      final poolRatePercent = (_globalConfig['directorPoolRate'] ?? 12.0) as num;
      final poolRate = poolRatePercent.toDouble() / 100;
      final totalPoolAmount = saleAmount * poolRate;
      
      // Get all directors and superadmins for the pool
      final directorSnapshot = await _db.collection('sales_users')
          .where('role', whereIn: ['Director', 'SuperAdmin'])
          .get();
          
      if (directorSnapshot.docs.isNotEmpty) {
        final sharePerDirector = totalPoolAmount / directorSnapshot.docs.length;
        
        for (var directorDoc in directorSnapshot.docs) {
          final directorData = directorDoc.data();
          
          final commission = Commission(
            id: '',
            agentId: directorDoc.id,
            agentName: directorData['name'] ?? 'Director',
            storeId: storeId,
            transactionId: transactionId,
            saleAmount: saleAmount,
            rate: (sharePerDirector / saleAmount) * 100,
            amount: sharePerDirector,
            type: 'Pool',
            status: 'Pending',
          );

          await _db.collection('commissions').add({
            ...commission.toMap(),
            'description': 'Director Pool Share (${poolRatePercent.toStringAsFixed(0)}% Pool)',
          });
        }
      }
    } catch (e) {
      debugPrint('Error processing director pool: $e');
    }
  }

  Future<void> _processOverrides(String agentId, double saleAmount, String transactionId, String storeId) async {
    // 1. Get the agent's upline hierarchy
    final agentDoc = await _db.collection('sales_users').doc(agentId).get();
    final teamLeaderId = agentDoc.data()?['teamLeaderId'];
    
    if (teamLeaderId != null && teamLeaderId != 'SYSTEM') {
      final leaderDoc = await _db.collection('sales_users').doc(teamLeaderId).get();
          
      if (leaderDoc.exists) {
        final leaderData = leaderDoc.data()!;
        final leaderRole = leaderData['role'];
        
        // Indirect income for management roles
        if (leaderRole == 'Team Leader' || leaderRole == 'Director' || leaderRole == 'SuperAdmin') {
          final overrideRatePercent = (_globalConfig['teamLeaderOverrideRate'] ?? 5.0) as num;
          final overrideRate = overrideRatePercent.toDouble() / 100;
          final overrideAmount = saleAmount * overrideRate;

          final commission = Commission(
            id: '',
            agentId: teamLeaderId,
            agentName: leaderData['name'] ?? 'Leader',
            storeId: storeId,
            transactionId: transactionId,
            saleAmount: saleAmount,
            rate: overrideRatePercent.toDouble(),
            amount: overrideAmount,
            type: 'Override',
            status: 'Pending',
          );

          await _db.collection('commissions').add({
            ...commission.toMap(),
            'description': 'Team Override (Agent: ${agentDoc.data()?['name'] ?? agentId})',
          });
        }
      }
    }
  }

  Future<void> fetchCommissions(String userId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final snapshot = await _db.collection('commissions')
          .where('agentId', isEqualTo: userId)
          .get();

      final fetched = snapshot.docs.map((doc) => Commission.fromMap(doc.data(), doc.id)).toList();
      fetched.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _commissions = fetched;
      _calculateStats();
    } catch (e) {
      _error = 'Failed to fetch commissions: $e';
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
      await _db.collection('commissions').doc(commissionId).update({
        'status': 'Paid',
        'paidAt': FieldValue.serverTimestamp(),
      });
      
      final index = _commissions.indexWhere((c) => c.id == commissionId);
      if (index != -1) {
        _commissions[index] = _commissions[index].copyWith(status: 'Paid');
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = 'Error marking as paid: $e';
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _progressSubscription?.cancel();
    _commissionsSubscription?.cancel();
    _recruitsSubscription?.cancel();
    _companySalesSubscription?.cancel();
    _expensesSubscription?.cancel();
    _directorsSubscription?.cancel();
    super.dispose();
  }

  void _startListeningToMonthlyExpenses(String agentId, DateTime month) {
    _expensesSubscription?.cancel();
    
    final startOfMonth = DateTime(month.year, month.month, 1);
    final endOfMonth = DateTime(month.year, month.month + 1, 0, 23, 59, 59);

    _expensesSubscription = _db.collection('expenses')
        .where('userId', isEqualTo: agentId)
        .where('status', isEqualTo: 'Approved')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
        .where('createdAt', isLessThanOrEqualTo: Timestamp.fromDate(endOfMonth))
        .snapshots()
        .listen((snapshot) {
          _approvedExpensesThisMonth = snapshot.docs.fold(0.0, (sum, doc) => sum + (doc.data()['amount'] ?? 0.0));
          notifyListeners();
        });
  }
}
