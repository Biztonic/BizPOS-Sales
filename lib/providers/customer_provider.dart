import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/customer.dart';

class CustomerProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  List<Customer> _customers = [];
  List<Map<String, dynamic>> _teamMembers = [];
  bool _isLoading = false;
  String? _error;

  StreamSubscription? _customersSubscription;

  List<Customer> get customers => _customers;
  List<Map<String, dynamic>> get teamMembers => _teamMembers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  String? _lastUserId;
  String? _lastRole;

  /// Start a real-time listener for customers.
  /// Replaces old one-shot fetch — now UI updates instantly on any Firestore change.
  Future<void> fetchCustomers({String? userId, String? role}) async {
    if (userId != null) _lastUserId = userId;
    if (role != null) _lastRole = role;
    
    final currentUserId = userId ?? _lastUserId;
    final currentRole = role ?? _lastRole;

    _customersSubscription?.cancel();
    _isLoading = true;
    _error = null;
    // Don't clear existing list — keep stale data visible until fresh data arrives
    Future.microtask(() => notifyListeners());
 
    try {
      Query query = _db.collection('customers');
 
      // Role-based filtering
      if (currentRole == 'Sales Executive' && currentUserId != null) {
        query = query.where('assignedTo', isEqualTo: currentUserId);
      } else if (currentRole == 'Team Leader' && currentUserId != null) {
        // First get team member IDs
        final teamSnapshot = await _db.collection('sales_users')
            .where('teamLeaderId', isEqualTo: currentUserId)
            .get();
        
        List<String> teamMemberIds = teamSnapshot.docs.map((doc) => doc.id).toList();
        teamMemberIds.add(currentUserId); // Include self
 
        if (teamMemberIds.isNotEmpty) {
          // Chunked query to bypass whereIn limit of 30 if necessary, 
          // but for now we increase the limit to 30 or handle it better.
          // Note: Firestore whereIn limit is strictly 30. 
          // If a team has >30 members, we need a different strategy (like a collection group or array contains).
          // For now, let's keep it at 30 as per Firestore constraints but ensure it doesn't break.
          query = query.where('assignedTo', whereIn: teamMemberIds.take(30).toList());
        }
      }
 
      _customersSubscription = query.snapshots().listen((snapshot) {
        _customers = snapshot.docs.map((doc) => Customer.fromFirestore(doc)).toList();
        _customers.sort((a, b) => (a.name).toLowerCase().compareTo((b.name).toLowerCase()));
        _isLoading = false;
        _error = null;
        notifyListeners();
      }, onError: (e) {
        _error = e.toString();
        _isLoading = false;
        debugPrint('Error listening to customers: $e');
        notifyListeners();
      });
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      debugPrint('Error fetching customers: $e');
      notifyListeners();
    }
  }

  Future<Customer?> getCustomerById(String id) async {
    try {
      final doc = await _db.collection('customers').doc(id).get();
      if (doc.exists) {
        return Customer.fromFirestore(doc);
      }
      return null;
    } catch (e) {
      debugPrint('Error getting customer by ID: $e');
      return null;
    }
  }

  Future<void> fetchTeamMembers(String currentUserId, String role) async {
    try {
      QuerySnapshot snapshot;
      
      if (role == 'Director' || role == 'SuperAdmin') {
        // Directors and SuperAdmins can assign leads to any user
        snapshot = await _db.collection('sales_users').get();
      } else if (role == 'Team Leader') {
        // Team Leaders can only assign to their own subordinates
        snapshot = await _db.collection('sales_users')
            .where('teamLeaderId', isEqualTo: currentUserId)
            .get();
      } else {
        // Sales Executives cannot transfer
        _teamMembers = [];
        notifyListeners();
        return;
      }
      
      _teamMembers = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data() as Map<String, dynamic>})
          .where((user) => user['id'] != currentUserId)
          .toList();
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching team members: $e');
    }
  }

  /// Transfer customer — real-time listener auto-refreshes the list.
  Future<bool> transferCustomer(String customerId, String targetUserId, String targetUserName) async {
    try {
      await _db.collection('customers').doc(customerId).update({
        'assignedTo': targetUserId,
        'assignedToName': targetUserName,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      // No need to call fetchCustomers() — real-time listener handles it
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Add customer — real-time listener auto-refreshes the list.
  Future<bool> addCustomer(Customer customer) async {
    try {
      await _db.collection('customers').add(customer.toFirestore());
      // No need to call fetchCustomers() — real-time listener handles it
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update customer — real-time listener auto-refreshes the list.
  Future<bool> updateCustomer(Customer customer) async {
    try {
      await _db.collection('customers').doc(customer.id).update(customer.toFirestore());
      // No need to call fetchCustomers() — real-time listener handles it
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  /// Update customer status — real-time listener auto-refreshes the list.
  Future<bool> updateCustomerStatus(String customerId, String newStatus) async {
    try {
      await _db.collection('customers').doc(customerId).update({'status': newStatus});
      // No need to call fetchCustomers() — real-time listener handles it
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _customersSubscription?.cancel();
    super.dispose();
  }
}
