import 'dart:async';
import 'package:flutter/material.dart';
import '../models/customer.dart';
import '../repositories/customer_repository.dart';
import '../sync/sync_engine.dart';

class CustomerProvider with ChangeNotifier {
  final CustomerRepository _repository = CustomerRepository();

  List<Customer> _customers = [];
  List<Map<String, dynamic>> _teamMembers = [];
  bool _isLoading = false;
  String? _error;

  String? _lastUserId;
  String? _lastRole;
  String? _lastStoreId;
  List<String>? _lastTeamMemberIds;

  StreamSubscription? _syncEventsSubscription;

  List<Customer> get customers => _customers;
  List<Map<String, dynamic>> get teamMembers => _teamMembers;
  bool get isLoading => _isLoading;
  String? get error => _error;

  CustomerProvider() {
    _listenToSyncEvents();
  }

  void _listenToSyncEvents() {
    _syncEventsSubscription?.cancel();
    _syncEventsSubscription = SyncEngine().syncEvents.listen((entityType) {
      if (entityType == 'customer') {
        debugPrint("CustomerProvider: Reloading customers after delta sync.");
        _reloadLocalCustomers();
      }
    });
  }

  void _reloadLocalCustomers() {
    if (_lastUserId != null && _lastRole != null) {
      _customers = _repository.getLocalCustomers(
        userId: _lastUserId!,
        role: _lastRole!,
        teamMemberIds: _lastTeamMemberIds,
      );
      notifyListeners();
    }
  }

  Future<void> fetchCustomers({
    required String userId,
    required String role,
    required String storeId,
    List<String>? teamMemberIds,
    bool forceSync = false,
  }) async {
    _lastUserId = userId;
    _lastRole = role;
    _lastStoreId = storeId;
    _lastTeamMemberIds = teamMemberIds;

    _isLoading = true;
    _error = null;
    Future.microtask(() => notifyListeners());

    try {
      _customers = await _repository.getCustomers(
        userId: userId,
        role: role,
        storeId: storeId,
        teamMemberIds: teamMemberIds,
        forceSync: forceSync,
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<Customer?> getCustomerById(String id) async {
    // Lookup cache first
    final list = _repository.getLocalCustomers(userId: _lastUserId ?? '', role: _lastRole ?? '');
    final match = list.where((c) => c.id == id);
    if (match.isNotEmpty) return match.first;
    
    // Fallback to database lookup
    return _repository.getCustomerById(id);
  }

  Future<void> fetchTeamMembers(String currentUserId, String role) async {
    try {
      _isLoading = true;
      notifyListeners();
      
      // Keep online checks but cache locally or use safe lookups
      final snapshot = await _repository.db.collection('sales_users').get();
      
      _teamMembers = snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .where((user) => user['id'] != currentUserId)
          .toList();
          
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      debugPrint('Error fetching team members: $e');
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> transferCustomer(String customerId, String targetUserId, String targetUserName) async {
    try {
      if (_lastStoreId == null) return false;
      await _repository.transferCustomer(
        customerId: customerId,
        targetUserId: targetUserId,
        targetUserName: targetUserName,
        storeId: _lastStoreId!,
      );
      
      _reloadLocalCustomers();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> addCustomer(Customer customer) async {
    try {
      if (_lastStoreId == null) return false;
      await _repository.addCustomer(customer, _lastStoreId!);
      
      // Direct local update for instant UI response
      _reloadLocalCustomers();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCustomer(Customer customer) async {
    try {
      if (_lastStoreId == null) return false;
      await _repository.updateCustomer(customer, _lastStoreId!);
      
      _reloadLocalCustomers();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateCustomerStatus(String customerId, String newStatus) async {
    try {
      if (_lastStoreId == null) return false;
      final match = _customers.where((c) => c.id == customerId);
      if (match.isNotEmpty) {
        final updatedCustomer = match.first.copyWith(status: newStatus);
        await _repository.updateCustomer(updatedCustomer, _lastStoreId!);
        _reloadLocalCustomers();
        SyncEngine().flushQueue();
        return true;
      }
      return false;
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
