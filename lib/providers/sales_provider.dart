import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/sale_transaction.dart';
import '../models/product.dart';
import '../models/quotation.dart';
import '../services/promotion_service.dart';

/// SalesProvider manages all sales transaction data.
/// Uses the same Firestore backend as BizPOS Clone (bizpos-clone project).
/// 
/// Firestore Collections Used:
/// - 'sales_transactions' — Sales records with agent, customer, amount, commission
/// - 'orders' — Reads from existing BizPOS orders for reporting
/// - 'customers' — Shared customer data with BizPOS Clone
/// - 'inventory' — Reads product catalog from BizPOS Clone
class SalesProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  List<SaleTransaction> _transactions = [];
  List<Quotation> _quotations = [];
  List<Product> _products = [];
  bool _isLoading = false;
  String? _error;
  String? _activeStoreId;
  int _totalAgents = 0;
  double _totalSales = 0.0;
  double _avgAchievement = 0.0;
  final PromotionService _promotionService = PromotionService();

  StreamSubscription? _productsSubscription;
  StreamSubscription? _adminConfigSubscription;
  StreamSubscription? _platformLimitsSubscription;
  StreamSubscription? _globalStatsSubscription;
  StreamSubscription? _globalAgentsSubscription;
  StreamSubscription? _globalAchievementsSubscription;
  StreamSubscription? _transactionsSubscription;
  StreamSubscription? _quotationsSubscription;

  SalesProvider() {
    _initRealtimeListeners();
  }

  void clearData() {
    _transactionsSubscription?.cancel();
    _quotationsSubscription?.cancel();
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
    _productsSubscription?.cancel();
    _adminConfigSubscription?.cancel();
    _platformLimitsSubscription?.cancel();
    _globalStatsSubscription?.cancel();
    _globalAgentsSubscription?.cancel();
    _globalAchievementsSubscription?.cancel();
    _transactionsSubscription?.cancel();
    _quotationsSubscription?.cancel();
    super.dispose();
  }

  void _initRealtimeListeners() {
    // 1. Listen to products collection
    _productsSubscription = _db.collection('products')
        .snapshots()
        .listen((snapshot) {
      final list = snapshot.docs
          .map((doc) => Product.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      _products = list;
      Future.microtask(() => notifyListeners());
    });

    // 2. Listen to BizPOS Clone Admin Config (Monthly/Yearly Prices)
    _adminConfigSubscription = _db.collection('settings').doc('admin_config')
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        _syncSoftwarePlans(doc.data()!);
      }
    });

    // 3. Listen to BizPOS Clone Platform Limits (Add-on Prices)
    _platformLimitsSubscription = _db.collection('settings').doc('platform_limits')
        .snapshots()
        .listen((doc) {
      if (doc.exists) {
        _syncAddonRates(doc.data()!);
      }
    });
  }

  Future<void> syncProductsFromSettings() async {
    _isLoading = true;
    notifyListeners();
    try {
      final configDoc = await _db.collection('settings').doc('admin_config').get();
      if (configDoc.exists) {
        await _syncSoftwarePlans(configDoc.data()!);
      }
      
      final limitsDoc = await _db.collection('settings').doc('platform_limits').get();
      if (limitsDoc.exists) {
        await _syncAddonRates(limitsDoc.data()!);
      }
      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = 'Failed to sync products: $e';
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _syncSoftwarePlans(Map<String, dynamic> data) async {
    final batch = _db.batch();
    
    // Monthly Plan
    if (data.containsKey('standardPlanMonthlyPrice')) {
      final monthlyPrice = (data['standardPlanMonthlyPrice'] ?? 0).toDouble();
      final id = 'plan_monthly';
      final existing = _products.any((p) => p.id == id);
      
      final Map<String, dynamic> planData = {
        'name': 'Standard Monthly Plan',
        'description': 'Standard Monthly Subscription for BizPOS',
        'price': monthlyPrice,
        'type': 'SOFTWARE',
      };
      
      if (!existing) {
        planData['isActive'] = true;
        planData['createdAt'] = FieldValue.serverTimestamp();
      }
      
      batch.set(_db.collection('products').doc(id), planData, SetOptions(merge: true));
    }

    // Yearly Plan
    if (data.containsKey('standardPlanYearlyPrice')) {
      final yearlyPrice = (data['standardPlanYearlyPrice'] ?? 0).toDouble();
      final id = 'plan_yearly';
      final existing = _products.any((p) => p.id == id);
      
      final Map<String, dynamic> planData = {
        'name': 'Standard Yearly Plan',
        'description': 'Standard Yearly Subscription for BizPOS (Save more!)',
        'price': yearlyPrice,
        'type': 'SOFTWARE',
      };
      
      if (!existing) {
        planData['isActive'] = true;
        planData['createdAt'] = FieldValue.serverTimestamp();
      }
      
      batch.set(_db.collection('products').doc(id), planData, SetOptions(merge: true));
    }

    await batch.commit();
  }

  Future<void> _syncAddonRates(Map<String, dynamic> data) async {
    final batch = _db.batch();
    
    // Mapping of platform_limits keys to Product Names
    final addonMapping = {
      'rate_central_catalog': 'Central Catalog Addon',
      'rate_customer_management': 'Customer Management Addon',
      'rate_data_center': 'Data Center Addon',
      'rate_employee_management': 'Employee Management Addon',
      'rate_franchise_management': 'Franchise Management Addon',
      'rate_integration_hub': 'Integration Hub Addon',
      'rate_kds_management': 'KDS Management Addon',
      'rate_supplier_management': 'Supplier Management Addon',
      'rate_table_reservation': 'Table Reservation Addon',
    };

    for (var entry in addonMapping.entries) {
      if (data.containsKey(entry.key)) {
        final price = (data[entry.key] ?? 0).toDouble();
        final id = 'addon_${entry.key.replaceFirst('rate_', '')}';
        final existing = _products.any((p) => p.id == id);
        
        final Map<String, dynamic> addonData = {
          'name': entry.value,
          'description': 'Add-on module for BizPOS',
          'price': price,
          'type': 'SOFTWARE',
        };
        
        if (!existing) {
          addonData['isActive'] = true;
          addonData['createdAt'] = FieldValue.serverTimestamp();
        }
        
        batch.set(_db.collection('products').doc(id), addonData, SetOptions(merge: true));
      }
    }

    await batch.commit();
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

  // --- Summary Stats (Local Transactions) ---
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

  /// Start real-time listener for sales transactions.
  /// Replaces old one-shot fetch — now UI updates instantly on any Firestore change.
  Future<void> fetchTransactions({String? agentId, bool isSuperAdmin = false}) async {
    _transactionsSubscription?.cancel();
    _isLoading = true;
    _error = null;
    // Don't clear existing list — keep stale data visible until fresh data arrives
    Future.microtask(() => notifyListeners());

    try {
      Query query = _db.collection('sales_transactions');
      
      // SECURITY: If not super admin, must filter by agentId
      if (!isSuperAdmin) {
        if (agentId == null || agentId.isEmpty) {
          _transactions = [];
          _isLoading = false;
          notifyListeners();
          return;
        }
        query = query.where('agentId', isEqualTo: agentId);
      } else if (agentId != null && agentId.isNotEmpty) {
        query = query.where('agentId', isEqualTo: agentId);
      }
      
      _transactionsSubscription = query.orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        _transactions = snapshot.docs
            .map((doc) => SaleTransaction.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
        _isLoading = false;
        _error = null;
        notifyListeners();
      }, onError: (e) {
        _error = 'Failed to fetch transactions: $e';
        _isLoading = false;
        notifyListeners();
      });
    } catch (e) {
      _error = 'Failed to fetch transactions: $e';
      _isLoading = false;
      Future.microtask(() => notifyListeners());
    }
  }

  /// Fetch transactions for a specific customer
  Future<List<SaleTransaction>> fetchTransactionsByCustomer(String customerId) async {
    try {
      final snapshot = await _db.collection('sales_transactions')
          .where('customerId', isEqualTo: customerId)
          .get();
      
      final list = snapshot.docs
          .map((doc) => SaleTransaction.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();
      
      // Sort in memory to avoid Firestore index requirement
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      debugPrint('Error fetching customer transactions: $e');
      return [];
    }
  }

  /// Create a new sales transaction
  Future<String?> createTransaction(SaleTransaction transaction) async {
    try {
      final docRef = await _db.collection('sales_transactions').add(transaction.toMap());
      final newTransaction = transaction.copyWith(id: docRef.id);
      _transactions.insert(0, newTransaction);
      
      // Trigger promotion check asynchronously
      _promotionService.checkPromotions(transaction.agentId);
      
      notifyListeners();
      return docRef.id;
    } catch (e) {
      _error = 'Failed to create transaction: $e';
      notifyListeners();
      return null;
    }
  }

  /// Update transaction status
  Future<bool> updateTransactionStatus(String transactionId, String newStatus) async {
    try {
      await _db.collection('sales_transactions').doc(transactionId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final index = _transactions.indexWhere((t) => t.id == transactionId);
      if (index != -1) {
        _transactions[index] = _transactions[index].copyWith(status: newStatus);
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = 'Failed to update transaction: $e';
      notifyListeners();
      return false;
    }
  }

  // --- Quotation & Product Management ---

  /// Products are now fetched in real-time via constructor listener.
  Future<void> fetchProducts() async {
    // Logic moved to _initRealtimeListeners
  }

  /// Start real-time listener for quotations.
  /// Replaces old one-shot fetch — now UI updates instantly on any Firestore change.
  Future<void> fetchQuotations({String? agentId, bool isSuperAdmin = false}) async {
    _quotationsSubscription?.cancel();
    _isLoading = true;
    _error = null;
    // Don't clear existing list — keep stale data visible until fresh data arrives
    Future.microtask(() => notifyListeners());

    try {
      Query query = _db.collection('quotations');
      
      // SECURITY: If not super admin, must filter by agentId
      if (!isSuperAdmin) {
        if (agentId == null || agentId.isEmpty) {
          _quotations = [];
          _isLoading = false;
          notifyListeners();
          return;
        }
        query = query.where('agentId', isEqualTo: agentId);
      } else if (agentId != null && agentId.isNotEmpty) {
        query = query.where('agentId', isEqualTo: agentId);
      }
      
      _quotationsSubscription = query.orderBy('createdAt', descending: true)
          .snapshots()
          .listen((snapshot) {
        _quotations = snapshot.docs
            .map((doc) => Quotation.fromMap(doc.data() as Map<String, dynamic>, doc.id))
            .toList();
        _isLoading = false;
        _error = null;
        notifyListeners();
      }, onError: (e) {
        _error = 'Error fetching quotations: $e';
        _isLoading = false;
        debugPrint('Error fetching quotations: $e');
        notifyListeners();
      });
    } catch (e) {
      _error = 'Error fetching quotations: $e';
      _isLoading = false;
      debugPrint('Error fetching quotations: $e');
      notifyListeners();
    }
  }

  /// Fetch quotations for a specific customer
  Future<List<Quotation>> fetchQuotationsByCustomer(String customerId) async {
    try {
      final snapshot = await _db.collection('quotations')
          .where('customerId', isEqualTo: customerId)
          .get();
      
      final list = snapshot.docs
          .map((doc) => Quotation.fromMap(doc.data() as Map<String, dynamic>, doc.id))
          .toList();

      // Sort in memory
      list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return list;
    } catch (e) {
      debugPrint('Error fetching customer quotations: $e');
      return [];
    }
  }

  Future<bool> createQuotation(Quotation quotation) async {
    try {
      final docRef = await _db.collection('quotations').add(quotation.toMap(isUpdate: false));
      final newQuotation = quotation.copyWith(id: docRef.id);
      _quotations.insert(0, newQuotation);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to create quotation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateQuotation(Quotation quotation) async {
    try {
      await _db.collection('quotations').doc(quotation.id).update(quotation.toMap(isUpdate: true));
      final index = _quotations.indexWhere((q) => q.id == quotation.id);
      if (index != -1) {
        _quotations[index] = quotation;
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = 'Failed to update quotation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Delete a quotation
  Future<bool> deleteQuotation(String quotationId) async {
    try {
      await _db.collection('quotations').doc(quotationId).delete();
      _quotations.removeWhere((q) => q.id == quotationId);
      notifyListeners();
      return true;
    } catch (e) {
      _error = 'Failed to delete quotation: $e';
      notifyListeners();
      return false;
    }
  }

  /// Update quotation status
  Future<bool> updateQuotationStatus(String quotationId, String newStatus) async {
    try {
      await _db.collection('quotations').doc(quotationId).update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      final index = _quotations.indexWhere((q) => q.id == quotationId);
      if (index != -1) {
        _quotations[index] = _quotations[index].copyWith(status: newStatus);
        notifyListeners();
      }
      return true;
    } catch (e) {
      _error = 'Failed to update quotation: $e';
      notifyListeners();
      return false;
    }
  }

  Future<Map<String, dynamic>?> convertQuotationToInvoice({
    required Quotation quotation,
    required List<SaleItem> finalItems,
    required double finalAmount,
    required double amountPaid,
    required String paymentMethod,
    required String targetMonth,
    required String saleType,
  }) async {
    try {
      // 1. Mark quotation as CONVERTED
      await updateQuotationStatus(quotation.id, 'CONVERTED');

      // 2. Determine payment status
      String paymentStatus = 'PENDING';
      if (amountPaid > 0 && amountPaid < finalAmount) {
        paymentStatus = 'PARTIAL';
      } else if (amountPaid >= finalAmount) {
        paymentStatus = 'PAID';
      }

      // 3. Update customer status to ACTIVE if they were a LEAD, and add Hardware Warranties
      bool hasSoftwareSubscription = false;
      bool isNewCustomerOnboarded = false;
      DateTime? subscriptionExpiry;
      String? planName;

      if (quotation.customerId != null) {
        final customerRef = _db.collection('customers').doc(quotation.customerId);
        Map<String, dynamic> updateData = {'status': 'ACTIVE'};
        
        // Handle Hardware Warranty & Subscription Logic
        List<String> purchasedAddons = [];
        try {
          List<Map<String, dynamic>> newWarranties = [];
          for (var item in finalItems) {
            final productDoc = await _db.collection('products').doc(item.productId).get();
            if (productDoc.exists) {
              final data = productDoc.data() as Map<String, dynamic>;
              final type = data['type'] ?? 'HARDWARE';
              final itemNameLower = item.productName.toLowerCase();
              
              if (type == 'SOFTWARE' || itemNameLower.contains('plan') || itemNameLower.contains('subscription') || itemNameLower.contains('addon')) {
                hasSoftwareSubscription = true;
                if (itemNameLower.contains('addon')) {
                  purchasedAddons.add(item.productName);
                } else {
                  planName = item.productName;
                  // Determine expiry based on plan name
                  final duration = itemNameLower.contains('yearly') ? 365 : 30;
                  subscriptionExpiry = DateTime.now().add(Duration(days: duration));
                }
              }

              final int warrantyMonths = (data['warrantyMonths'] ?? 0).toInt();
              if (warrantyMonths > 0) {
                final purchaseDate = DateTime.now();
                final int expiryMonth = purchaseDate.month + warrantyMonths;
                final expiryDate = DateTime(purchaseDate.year, expiryMonth, purchaseDate.day);
                
                newWarranties.add({
                  'productName': item.productName,
                  'productId': item.productId,
                  'purchaseDate': Timestamp.fromDate(purchaseDate),
                  'expiryDate': Timestamp.fromDate(expiryDate),
                  'durationMonths': warrantyMonths,
                });
              }
            }
          }
          
          if (newWarranties.isNotEmpty) {
            updateData['warranties'] = FieldValue.arrayUnion(newWarranties);
          }
        } catch (e) {
          debugPrint('Error processing items: $e');
        }

        await customerRef.update(updateData);

        // 3.1. Automatically activate main BizPOS User if software purchased
        if (hasSoftwareSubscription && quotation.customerEmail != null && quotation.customerEmail!.isNotEmpty) {
          try {
            final emailLower = quotation.customerEmail!.toLowerCase().trim();
            // Write to subscription_requests for StoreProvider to consume!
            await _db.collection('subscription_requests').add({
              'email': emailLower,
              'customerEmail': emailLower,
              'planName': planName ?? 'Standard Monthly Plan',
              'addons': purchasedAddons,
              'status': 'PENDING',
              'durationInDays': subscriptionExpiry != null ? subscriptionExpiry!.difference(DateTime.now()).inDays : 365,
              'createdAt': FieldValue.serverTimestamp(),
            });

            final userRef = _db.collection('users').doc(emailLower); // Using email as ID for main app users as requested
            final userSnap = await userRef.get();
            
            final userData = {
              'email': emailLower,
              'name': quotation.customerName,
              'role': 'Owner',
              'status': 'Active',
              'subscriptionStatus': 'Active',
              'subscriptionPlan': planName,
              'subscriptionExpiry': subscriptionExpiry != null ? Timestamp.fromDate(subscriptionExpiry!) : null,
              'addons': purchasedAddons, // Also save addons here
              'updatedAt': FieldValue.serverTimestamp(),
            };

            if (!userSnap.exists) {
              // New user workflow
              userData['createdAt'] = FieldValue.serverTimestamp();
              userData['needsInitialPassword'] = true;
              userData['isNewCustomer'] = true;
              await userRef.set(userData);
              isNewCustomerOnboarded = true;
            } else {
              // Existing user update
              await userRef.update(userData);
              // Check if they still need initial password (e.g. they were added but never logged in)
              if (userSnap.data()?['needsInitialPassword'] == true) {
                isNewCustomerOnboarded = true;
              }
            }
          } catch (e) {
            debugPrint('Error activating main BizPOS user: $e');
          }
        }
      }

      // 4. Implement 'Forever Linkage': Check if customer is assigned to someone else
      String actualAgentId = quotation.agentId;
      String actualAgentName = quotation.agentName;
      String actualAgentTitle = quotation.agentTitle;

      if (quotation.customerId != null && quotation.customerId!.isNotEmpty) {
        final customerDoc = await _db.collection('customers').doc(quotation.customerId).get();
        if (customerDoc.exists && customerDoc.data()?['assignedTo'] != null) {
          actualAgentId = customerDoc.data()!['assignedTo'];
          // Also fetch the actual agent's name and title to ensure accuracy
          final agentDoc = await _db.collection('sales_users').doc(actualAgentId).get();
          if (agentDoc.exists) {
            actualAgentName = agentDoc.data()?['name'] ?? actualAgentName;
            actualAgentTitle = agentDoc.data()?['role'] ?? actualAgentTitle;
          }
        }
      }

      // 5. Create SaleTransaction
      final transaction = SaleTransaction(
        id: '', // Will be assigned by Firestore
        agentId: actualAgentId,
        agentName: actualAgentName,
        agentTitle: actualAgentTitle,
        storeId: quotation.storeId,
        customerId: quotation.customerId,
        customerName: quotation.customerName,
        quotationId: quotation.id,
        amount: finalAmount,
        amountPaid: amountPaid,
        paymentMethod: paymentMethod,
        paymentStatus: paymentStatus,
        status: 'Completed', // The invoice is completed
        saleType: saleType,
        targetMonth: targetMonth,
        items: finalItems,
        notes: 'Converted from quotation ${quotation.id}',
      );

      final transactionId = await createTransaction(transaction);
      return {
        'transactionId': transactionId,
        'isNewCustomerOnboarded': isNewCustomerOnboarded,
      };
    } catch (e) {
      _error = 'Failed to convert quotation: $e';
      notifyListeners();
      return null;
    }
  }


  /// Add a payment to an existing transaction
  Future<bool> addPayment(String transactionId, double paymentAmount) async {
    try {
      final docRef = _db.collection('sales_transactions').doc(transactionId);
      final doc = await docRef.get();
      if (!doc.exists) return false;

      final data = doc.data() as Map<String, dynamic>;
      final currentPaid = (data['amountPaid'] ?? 0.0).toDouble();
      final totalAmount = (data['amount'] ?? 0.0).toDouble();
      final newPaid = (currentPaid + paymentAmount).clamp(0.0, totalAmount);

      String paymentStatus = 'PENDING';
      if (newPaid > 0 && newPaid < totalAmount) {
        paymentStatus = 'PARTIAL';
      } else if (newPaid >= totalAmount) {
        paymentStatus = 'PAID';
      }

      await docRef.update({
        'amountPaid': newPaid,
        'paymentStatus': paymentStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return true;
    } catch (e) {
      _error = 'Failed to add payment: $e';
      notifyListeners();
      return false;
    }
  }

  /// Fetch orders from BizPOS Clone for cross-referencing
  Future<List<Map<String, dynamic>>> fetchLinkedOrders(String storeId) async {
    try {
      final snapshot = await _db.collection('orders')
          .where('storeId', isEqualTo: storeId)
          .orderBy('date', descending: true)
          .limit(50)
          .get();
      return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error fetching linked orders: $e');
      return [];
    }
  }

  /// Fetch product catalog from BizPOS Clone inventory
  Future<List<Map<String, dynamic>>> fetchProductCatalog(String storeId) async {
    try {
      final snapshot = await _db.collection('inventory')
          .where('storeId', isEqualTo: storeId)
          .where('deletedAt', isNull: true)
          .get();
      return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error fetching product catalog: $e');
      return [];
    }
  }

  /// Add a new product to the catalog
  Future<bool> addProduct(Product product) async {
    try {
      await _db.collection('products').add(product.toMap());
      // Real-time listener will update _products
      return true;
    } catch (e) {
      _error = 'Failed to add product: $e';
      notifyListeners();
      return false;
    }
  }

  /// Toggle product active/inactive state
  Future<bool> toggleProductActive(String productId, bool isActive) async {
    try {
      // Optimistic update
      final index = _products.indexWhere((p) => p.id == productId);
      if (index != -1) {
        final oldProduct = _products[index];
        _products[index] = Product(
          id: oldProduct.id,
          name: oldProduct.name,
          description: oldProduct.description,
          price: oldProduct.price,
          type: oldProduct.type,
          isActive: isActive,
          createdAt: oldProduct.createdAt,
        );
        notifyListeners();
      }

      await _db.collection('products').doc(productId).update({
        'isActive': isActive,
      });
      return true;
    } catch (e) {
      _error = 'Failed to update product: $e';
      // Revert optimistic update if needed (listener will eventually fix it anyway)
      notifyListeners();
      return false;
    }
  }


  /// Delete a product from the catalog
  Future<bool> deleteProduct(String productId) async {
    try {
      await _db.collection('products').doc(productId).delete();
      return true;
    } catch (e) {
      _error = 'Failed to delete product: $e';
      notifyListeners();
      return false;
    }
  }

  /// Legacy sync method - now handled automatically via realtime listeners.
  Future<int> syncPlansFromClone() async {
    return 0;
  }

  void startGlobalStatsListener() {
    _globalStatsSubscription?.cancel();
    _globalAgentsSubscription?.cancel();
    _globalAchievementsSubscription?.cancel();

    // 1. Total Sales (Global)
    _globalStatsSubscription = _db.collection('sales_transactions')
        .where('status', isEqualTo: 'Completed')
        .snapshots()
        .listen((snapshot) {
      double total = 0;
      for (var doc in snapshot.docs) {
        total += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
      }
      _totalSales = total;
      notifyListeners();
    });

    // 2. Total Agents
    _globalAgentsSubscription = _db.collection('sales_users')
        .snapshots()
        .listen((snapshot) {
      _totalAgents = snapshot.docs.length;
      notifyListeners();
    });

    // 3. Avg Achievement
    final currentMonth = '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}';
    _globalAchievementsSubscription = _db.collection('monthly_achievements')
        .where('month', isEqualTo: currentMonth)
        .snapshots()
        .listen((snapshot) {
      if (snapshot.docs.isEmpty) {
        _avgAchievement = 0;
      } else {
        double totalProg = 0;
        for (var doc in snapshot.docs) {
          totalProg += (doc.data()['progress'] ?? 0.0).toDouble();
        }
        _avgAchievement = totalProg / (_totalAgents > 0 ? _totalAgents : snapshot.docs.length);
      }
      notifyListeners();
    });
  }


  void clearError() {
    _error = null;
    notifyListeners();
  }
}
