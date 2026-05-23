import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sale_transaction.dart';
import '../models/product.dart';
import '../models/quotation.dart';
import '../repositories/sales_repository.dart';
import '../repositories/product_repository.dart';
import '../sync/sync_engine.dart';

class SalesProvider with ChangeNotifier {
  final SalesRepository _salesRepository = SalesRepository();
  final ProductRepository _productRepository = ProductRepository();

  List<SaleTransaction> _transactions = [];
  List<Quotation> _quotations = [];
  List<Product> _products = [];
  bool _isLoading = false;
  String? _error;
  String? _activeStoreId;
  
  // Dashboard Aggregate stats
  int _totalAgents = 0;
  double _totalSales = 0.0;
  double _avgAchievement = 0.0;

  StreamSubscription? _syncEventsSubscription;
  StreamSubscription? _globalStatsSubscription;

  String? _lastAgentId;
  bool _lastIsSuperAdmin = false;

  SalesProvider() {
    _loadInitialCache();
    _listenToSyncEvents();
  }

  void _loadInitialCache() {
    _products = _productRepository.getLocalProducts();
    _transactions = _salesRepository.getLocalTransactions();
    _quotations = _salesRepository.getLocalQuotations();
  }

  /// Listen to Sync Engine events to auto-reload cached data in memory when sync completes
  void _listenToSyncEvents() {
    _syncEventsSubscription?.cancel();
    _syncEventsSubscription = SyncEngine().syncEvents.listen((entityType) {
      debugPrint("SalesProvider: Reloading local $entityType data after delta sync.");
      if (entityType == 'product') {
        _products = _productRepository.getLocalProducts();
      } else if (entityType == 'transaction') {
        _transactions = _salesRepository.getLocalTransactions(agentId: _lastAgentId, isSuperAdmin: _lastIsSuperAdmin);
      } else if (entityType == 'quotation') {
        _quotations = _salesRepository.getLocalQuotations(agentId: _lastAgentId, isSuperAdmin: _lastIsSuperAdmin);
      }
      notifyListeners();
    });
  }

  // Getters
  List<SaleTransaction> get transactions => _transactions;
  List<Quotation> get quotations => _quotations;
  List<Product> get products => _products;
  bool get isLoading => _isLoading;
  String? get error => _error;
  String? get activeStoreId => _activeStoreId;
  int get totalAgents => _totalAgents;
  double get totalSales => _totalSales;
  double get avgAchievement => _avgAchievement;

  double get transactionsTotalSales => _transactions
      .where((t) => t.status != 'Cancelled' && t.status != 'Refunded')
      .fold(0.0, (sum, t) => sum + t.amount);

  int get totalTransactionCount => _transactions
      .where((t) => t.status != 'Cancelled')
      .length;

  double get totalCommission => _transactions
      .where((t) => t.status == 'Completed')
      .fold(0.0, (sum, t) => sum + t.commission);

  void setActiveStore(String storeId) {
    _activeStoreId = storeId;
    notifyListeners();
  }

  void clearData() {
    _globalStatsSubscription?.cancel();
    _transactions = [];
    _quotations = [];
    _isLoading = false;
    _error = null;
    _activeStoreId = null;
    _totalAgents = 0;
    _totalSales = 0.0;
    _avgAchievement = 0.0;
    notifyListeners();
  }

  @override
  void dispose() {
    _syncEventsSubscription?.cancel();
    _globalStatsSubscription?.cancel();
    super.dispose();
  }

  // --- Transactions ---

  Future<void> fetchTransactions({String? agentId, bool isSuperAdmin = false}) async {
    _lastAgentId = agentId;
    _lastIsSuperAdmin = isSuperAdmin;
    _isLoading = true;
    _error = null;
    Future.microtask(() => notifyListeners());

    try {
      _transactions = await _salesRepository.getTransactions(
        agentId: agentId,
        isSuperAdmin: isSuperAdmin,
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch transactions: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<List<SaleTransaction>> fetchTransactionsByCustomer(String customerId) async {
    return _salesRepository.getLocalTransactions().where((t) => t.customerId == customerId).toList();
  }

  Future<String?> createTransaction(SaleTransaction transaction) async {
    try {
      final id = await _salesRepository.createTransaction(transaction);
      
      // Update local memory list for instant feedback
      final newTx = transaction.copyWith(id: id);
      _transactions.insert(0, newTx);
      notifyListeners();
      
      // Attempt background flush
      SyncEngine().flushQueue();
      return id;
    } catch (e) {
      _error = 'Failed to create transaction: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateTransactionStatus(String transactionId, String newStatus) async {
    try {
      await _salesRepository.updateTransactionStatus(transactionId, newStatus);
      final index = _transactions.indexWhere((t) => t.id == transactionId);
      if (index != -1) {
        _transactions[index] = _transactions[index].copyWith(status: newStatus);
        notifyListeners();
      }
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to update transaction: $e';
      notifyListeners();
      return false;
    }
  }

  // --- Products ---

  Future<void> fetchProducts({bool forceRefresh = false}) async {
    _isLoading = true;
    notifyListeners();
    try {
      _products = await _productRepository.getProducts(forceSync: forceRefresh);
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to load products: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> addProduct(Product product) async {
    try {
      await _productRepository.addProduct(product);
      // Insert locally
      _products.insert(0, product);
      notifyListeners();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to add product: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> toggleProductActive(String productId, bool isActive) async {
    try {
      await _productRepository.toggleProductActive(productId, isActive);
      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        _products[index] = _products[index].copyWith(isActive: isActive);
        notifyListeners();
      }
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to toggle product: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> deleteProduct(String productId) async {
    try {
      await _productRepository.deleteProduct(productId);
      _products.removeWhere((p) => p.id == productId);
      notifyListeners();
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to delete product: $e';
      notifyListeners();
      return false;
    }
  }

  // --- Quotations ---

  Future<void> fetchQuotations({String? agentId, bool isSuperAdmin = false}) async {
    _lastAgentId = agentId;
    _lastIsSuperAdmin = isSuperAdmin;
    _isLoading = true;
    _error = null;
    Future.microtask(() => notifyListeners());

    try {
      _quotations = await _salesRepository.getQuotations(
        agentId: agentId,
        isSuperAdmin: isSuperAdmin,
      );
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to fetch quotations: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<String?> addQuotation(Quotation quotation) async {
    try {
      final id = await _salesRepository.addQuotation(quotation);
      final newQ = quotation.copyWith(id: id);
      _quotations.insert(0, newQ);
      notifyListeners();
      SyncEngine().flushQueue();
      return id;
    } catch (e) {
      _error = 'Failed to add quotation: $e';
      notifyListeners();
      return null;
    }
  }

  Future<bool> updateQuotationStatus(String quotationId, String status) async {
    try {
      await _salesRepository.updateQuotationStatus(quotationId, status);
      final index = _quotations.indexWhere((q) => q.id == quotationId);
      if (index != -1) {
        _quotations[index] = _quotations[index].copyWith(status: status);
        notifyListeners();
      }
      SyncEngine().flushQueue();
      return true;
    } catch (e) {
      _error = 'Failed to update quotation: $e';
      notifyListeners();
      return false;
    }
  }

  // --- Invoice Conversion ---

  Future<Map<String, dynamic>?> convertQuotationToInvoice({
    required Quotation quotation,
    required List<SaleItem> finalItems,
    required double finalAmount,
    required double amountPaid,
    required String paymentMethod,
    required String targetMonth,
    required String saleType,
  }) async {
    _isLoading = true;
    notifyListeners();

    final result = await _salesRepository.convertQuotationToInvoice(
      quotation: quotation,
      finalItems: finalItems,
      finalAmount: finalAmount,
      amountPaid: amountPaid,
      paymentMethod: paymentMethod,
      targetMonth: targetMonth,
      saleType: saleType,
    );

    _isLoading = false;
    notifyListeners();
    
    if (result != null) {
      SyncEngine().flushQueue();
    }
    return result;
  }

  // --- External Integrations (BizPOS Clone) ---

  Future<List<Map<String, dynamic>>> fetchLinkedOrders(String storeId) async {
    // Delegates to SalesRepository using standard connection
    return _salesRepository.fetchLinkedOrders(storeId);
  }

  Future<List<Map<String, dynamic>>> fetchProductCatalog(String storeId) async {
    return _salesRepository.fetchProductCatalog(storeId);
  }

  // --- Cost-Optimized Dashboard Analytics ---

  /// Reads aggregate summary documents from Firestore to build dashboard statistics
  void startGlobalStatsListener() {
    _globalStatsSubscription?.cancel();

    // Scopes dashboard reads to 1 aggregate document read
    _globalStatsSubscription = FirebaseFirestore.instance
        .collection('metadata')
        .doc('global_dashboard_stats')
        .snapshots()
        .listen((snap) {
      if (snap.exists && snap.data() != null) {
        final data = snap.data()!;
        _totalSales = (data['totalSales'] ?? 0.0).toDouble();
        _totalAgents = (data['totalAgents'] ?? 0).toInt();
        _avgAchievement = (data['avgAchievement'] ?? 0.0).toDouble();
        notifyListeners();
      }
    });
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }
}
