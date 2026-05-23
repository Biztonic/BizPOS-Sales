import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

class TeamProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<Map<String, dynamic>> _teamMembers = [];
  bool _isLoading = false;
  String? _error;

  List<Map<String, dynamic>> get teamMembers => _teamMembers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Fetch users based on hierarchy
  Future<void> fetchTeamMembers(String leaderId, {bool isSuperAdmin = false}) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final now = DateTime.now();
      final currentMonth = DateFormat('yyyy-MM').format(now);
      
      // Calculate start of month for date-based queries
      final startOfMonth = DateTime(now.year, now.month, 1);
      
      Query userQuery = _db.collection('sales_users');
      if (!isSuperAdmin) {
        userQuery = userQuery.where('teamLeaderId', isEqualTo: leaderId);
      } else {
        userQuery = userQuery.where(FieldPath.documentId, isNotEqualTo: leaderId);
      }

      final userSnapshot = await userQuery.get();
      final members = userSnapshot.docs.map((doc) => {'id': doc.id, ...(doc.data() as Map<String, dynamic>)}).toList();
      
      if (members.isEmpty) {
        _teamMembers = [];
        _isLoading = false;
        notifyListeners();
        return;
      }

      final memberIds = members.map((m) => m['id'] as String).toList();

      // Bulk fetch transactions for the month
      // Note: Firestore 'whereIn' is limited to 30 items. 
      // For larger teams, we might need to fetch all transactions for the month and filter by agentId.
      // Given the small scale, let's fetch all transactions for the month.
      final txSnapshot = await _db.collection('sales_transactions')
          .where('targetMonth', isEqualTo: currentMonth)
          .where('status', isEqualTo: 'Completed')
          .get();

      // Bulk fetch commissions (using date since 'month' field is missing)
      final commSnapshot = await _db.collection('commissions')
          .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfMonth))
          .get();

      // Bulk fetch pending quotations
      final qSnapshot = await _db.collection('quotations')
          .where('status', isEqualTo: 'PENDING')
          .get();

      // Aggregate data in memory
      for (var member in members) {
        final memberId = member['id'];
        
        double monthlySales = 0;
        for (var doc in txSnapshot.docs) {
          final data = doc.data();
          if (data['agentId'] == memberId) {
            monthlySales += (data['amountPaid'] ?? data['amount'] ?? 0).toDouble();
          }
        }

        double monthlyComm = 0;
        for (var doc in commSnapshot.docs) {
          final data = doc.data();
          if (data['agentId'] == memberId) {
            monthlyComm += (data['amount'] ?? 0).toDouble();
          }
        }

        int activeQuotes = 0;
        for (var doc in qSnapshot.docs) {
          final data = doc.data();
          if (data['agentId'] == memberId) {
            activeQuotes++;
          }
        }

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
      // NOTE: Creating auth users requires FirebaseAuth or a Cloud Function.
      // For now, we simulate this by just creating the user doc in Firestore 
      // (assuming they sign up with the same email later, or a Cloud Function creates auth).
      // A complete implementation would either use Firebase Admin SDK via Cloud Function
      // or the leader shares a join code.
      
      // Let's create a placeholder user document.
      final docRef = await _db.collection('sales_users').add({
        'name': name,
        'email': email.trim(),
        'role': 'Sales Executive',
        'teamLeaderId': leaderId,
        'createdAt': FieldValue.serverTimestamp(),
        'appSource': 'bizpos_sales',
      });

      _teamMembers.add({
        'id': docRef.id,
        'name': name,
        'email': email.trim(),
        'role': 'Sales Executive',
        'teamLeaderId': leaderId,
      });

      _isLoading = false;
      notifyListeners();
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
}
