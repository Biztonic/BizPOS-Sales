import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_repository.dart';
import '../models/sale_transaction.dart';
import '../models/quotation.dart';
import '../models/product.dart';
import '../models/customer.dart';
import '../models/sync_queue_item.dart';
import '../services/promotion_service.dart';
import 'package:uuid/uuid.dart';

class SalesRepository extends BaseRepository {
  final Uuid _uuid = const Uuid();
  final PromotionService _promotionService = PromotionService();

  // --- Transactions ---

  Future<List<SaleTransaction>> getTransactions({
    String? agentId,
    bool isSuperAdmin = false,
    bool forceSync = false,
  }) async {
    final cached = localDb.getAllItems('sales_transactions');

    if (cached.isEmpty || forceSync) {
      if (await isConnected()) {
        await syncTransactionsFromFirestore(agentId, isSuperAdmin);
        return getLocalTransactions(agentId: agentId, isSuperAdmin: isSuperAdmin);
      }
    }

    return getLocalTransactions(agentId: agentId, isSuperAdmin: isSuperAdmin);
  }

  List<SaleTransaction> getLocalTransactions({String? agentId, bool isSuperAdmin = false}) {
    final cached = localDb.getAllItems('sales_transactions');
    var list = cached.map((map) => SaleTransaction.fromMap(map, map['id'] ?? '')).toList();
    
    if (!isSuperAdmin && agentId != null) {
      list = list.where((t) => t.agentId == agentId).toList();
    }
    
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> syncTransactionsFromFirestore(String? agentId, bool isSuperAdmin) async {
    try {
      Query query = db.collection('sales_transactions');
      if (!isSuperAdmin && agentId != null) {
        query = query.where('agentId', isEqualTo: agentId);
      }
      
      final snapshot = await query.limit(100).get(); // Paginate/limit to avoid large reads
      final Map<String, Map<String, dynamic>> itemsToCache = {};
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;
        
        if (data['createdAt'] is Timestamp) data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        if (data['updatedAt'] is Timestamp) data['updatedAt'] = (data['updatedAt'] as Timestamp).toDate().toIso8601String();
        
        itemsToCache[doc.id] = data;
      }
      
      if (itemsToCache.isNotEmpty) {
        await localDb.saveAllItems('sales_transactions', itemsToCache);
        await localDb.setLastSyncTime('sales_transactions', DateTime.now());
      }
    } catch (_) {}
  }

  Future<String> createTransaction(SaleTransaction transaction) async {
    final id = transaction.id.isEmpty ? _uuid.v4() : transaction.id;
    final map = transaction.toMap();
    map['id'] = id;
    map['createdAt'] = DateTime.now().toIso8601String();
    map['updatedAt'] = DateTime.now().toIso8601String();

    // 1. Save locally
    await localDb.saveItem('sales_transactions', id, map);

    // 2. Enqueue remote write
    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: id,
      entityType: 'transaction',
      operation: 'CREATE',
      payload: map,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);

    // 3. Trigger promotion check locally/asynchronously
    _promotionService.checkPromotions(transaction.agentId);

    return id;
  }

  Future<void> updateTransactionStatus(String transactionId, String newStatus) async {
    final cached = localDb.getItem('sales_transactions', transactionId);
    if (cached != null) {
      cached['status'] = newStatus;
      cached['updatedAt'] = DateTime.now().toIso8601String();
      await localDb.saveItem('sales_transactions', transactionId, cached);

      final queueItem = SyncQueueItem(
        id: _uuid.v4(),
        entityId: transactionId,
        entityType: 'transaction',
        operation: 'UPDATE',
        payload: {
          'status': newStatus,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: DateTime.now(),
      );
      await localDb.enqueueSyncItem(queueItem);
    }
  }

  // --- Quotations ---

  Future<List<Quotation>> getQuotations({
    String? agentId,
    bool isSuperAdmin = false,
    bool forceSync = false,
  }) async {
    final cached = localDb.getAllItems('quotations');

    if (cached.isEmpty || forceSync) {
      if (await isConnected()) {
        await syncQuotationsFromFirestore(agentId, isSuperAdmin);
        return getLocalQuotations(agentId: agentId, isSuperAdmin: isSuperAdmin);
      }
    }

    return getLocalQuotations(agentId: agentId, isSuperAdmin: isSuperAdmin);
  }

  List<Quotation> getLocalQuotations({String? agentId, bool isSuperAdmin = false}) {
    final cached = localDb.getAllItems('quotations');
    var list = cached.map((map) => Quotation.fromMap(map, map['id'] ?? '')).toList();

    if (!isSuperAdmin && agentId != null) {
      list = list.where((q) => q.agentId == agentId).toList();
    }

    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  Future<void> syncQuotationsFromFirestore(String? agentId, bool isSuperAdmin) async {
    try {
      Query query = db.collection('quotations');
      if (!isSuperAdmin && agentId != null) {
        query = query.where('agentId', isEqualTo: agentId);
      }

      final snapshot = await query.limit(100).get();
      final Map<String, Map<String, dynamic>> itemsToCache = {};

      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;

        if (data['createdAt'] is Timestamp) data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        if (data['updatedAt'] is Timestamp) data['updatedAt'] = (data['updatedAt'] as Timestamp).toDate().toIso8601String();
        if (data['validUntil'] is Timestamp) data['validUntil'] = (data['validUntil'] as Timestamp).toDate().toIso8601String();

        itemsToCache[doc.id] = data;
      }

      if (itemsToCache.isNotEmpty) {
        await localDb.saveAllItems('quotations', itemsToCache);
        await localDb.setLastSyncTime('quotations', DateTime.now());
      }
    } catch (_) {}
  }

  Future<String> addQuotation(Quotation quotation) async {
    final id = quotation.id.isEmpty ? _uuid.v4() : quotation.id;
    final map = quotation.toMap();
    map['id'] = id;
    map['createdAt'] = DateTime.now().toIso8601String();
    map['updatedAt'] = DateTime.now().toIso8601String();

    await localDb.saveItem('quotations', id, map);

    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: id,
      entityType: 'quotation',
      operation: 'CREATE',
      payload: map,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);

    return id;
  }

  Future<void> updateQuotationStatus(String quotationId, String status) async {
    final cached = localDb.getItem('quotations', quotationId);
    if (cached != null) {
      cached['status'] = status;
      cached['updatedAt'] = DateTime.now().toIso8601String();
      await localDb.saveItem('quotations', quotationId, cached);

      final queueItem = SyncQueueItem(
        id: _uuid.v4(),
        entityId: quotationId,
        entityType: 'quotation',
        operation: 'UPDATE',
        payload: {
          'status': status,
          'updatedAt': DateTime.now().toIso8601String(),
        },
        createdAt: DateTime.now(),
      );
      await localDb.enqueueSyncItem(queueItem);
    }
  }

  // --- Offline quotation conversion engine ---

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

      // 3. Update customer status locally, calculate hardware warranties offline
      bool hasSoftwareSubscription = false;
      bool isNewCustomerOnboarded = false;
      DateTime? subscriptionExpiry;
      String? planName;
      List<String> purchasedAddons = [];
      List<Map<String, dynamic>> newWarranties = [];

      // Loop through items and read from Hive cached products box (N+1 query avoided!)
      for (var item in finalItems) {
        final productMap = localDb.getItem('products', item.productId);
        if (productMap != null) {
          final type = productMap['type'] ?? 'HARDWARE';
          final itemNameLower = item.productName.toLowerCase();

          if (type == 'SOFTWARE' || itemNameLower.contains('plan') || itemNameLower.contains('subscription') || itemNameLower.contains('addon')) {
            hasSoftwareSubscription = true;
            if (itemNameLower.contains('addon')) {
              purchasedAddons.add(item.productName);
            } else {
              planName = item.productName;
              final duration = itemNameLower.contains('yearly') ? 365 : 30;
              subscriptionExpiry = DateTime.now().add(Duration(days: duration));
            }
          }

          final int warrantyMonths = (productMap['warrantyMonths'] ?? 0).toInt();
          if (warrantyMonths > 0) {
            final purchaseDate = DateTime.now();
            final expiryDate = DateTime(purchaseDate.year, purchaseDate.month + warrantyMonths, purchaseDate.day);

            newWarranties.add({
              'productName': item.productName,
              'productId': item.productId,
              'purchaseDate': purchaseDate.toIso8601String(),
              'expiryDate': expiryDate.toIso8601String(),
              'durationMonths': warrantyMonths,
            });
          }
        }
      }

      if (quotation.customerId != null) {
        final customerMap = localDb.getItem('customers', quotation.customerId!);
        if (customerMap != null) {
          customerMap['status'] = 'ACTIVE';
          
          final existingWarranties = List<Map<String, dynamic>>.from(customerMap['warranties'] ?? []);
          existingWarranties.addAll(newWarranties);
          customerMap['warranties'] = existingWarranties;

          // Update Customer locally & enqueue write
          await localDb.saveItem('customers', quotation.customerId!, customerMap);
          await localDb.enqueueSyncItem(SyncQueueItem(
            id: _uuid.v4(),
            entityId: quotation.customerId!,
            entityType: 'customer',
            operation: 'UPDATE',
            payload: {
              'status': 'ACTIVE',
              'warranties': existingWarranties,
            },
            createdAt: DateTime.now(),
          ));
        }

        // Handle Main App Onboarding & Subscriptions
        if (hasSoftwareSubscription && quotation.customerEmail != null && quotation.customerEmail!.isNotEmpty) {
          final emailLower = quotation.customerEmail!.toLowerCase().trim();
          
          // Enqueue subscription request write
          final subReqId = _uuid.v4();
          final subReqMap = {
            'email': emailLower,
            'customerEmail': emailLower,
            'planName': planName ?? 'Standard Monthly Plan',
            'addons': purchasedAddons,
            'status': 'PENDING',
            'durationInDays': subscriptionExpiry != null ? subscriptionExpiry.difference(DateTime.now()).inDays : 365,
            'createdAt': DateTime.now().toIso8601String(),
          };
          await localDb.enqueueSyncItem(SyncQueueItem(
            id: _uuid.v4(),
            entityId: subReqId,
            entityType: 'subscription_request',
            operation: 'CREATE',
            payload: subReqMap,
            createdAt: DateTime.now(),
          ));

          // Set/Update Main app User details
          final userMap = {
            'email': emailLower,
            'name': quotation.customerName,
            'role': 'Owner',
            'status': 'Active',
            'subscriptionStatus': 'Active',
            'subscriptionPlan': planName,
            'subscriptionExpiry': subscriptionExpiry?.toIso8601String(),
            'addons': purchasedAddons,
            'updatedAt': DateTime.now().toIso8601String(),
          };

          // Try checking cache first for users
          final userSnap = localDb.getItem('sync_metadata', 'user_app_$emailLower');
          if (userSnap == null) {
            userMap['createdAt'] = DateTime.now().toIso8601String();
            userMap['needsInitialPassword'] = true;
            userMap['isNewCustomer'] = true;
            isNewCustomerOnboarded = true;
          } else if (userSnap['needsInitialPassword'] == true) {
            isNewCustomerOnboarded = true;
          }

          await localDb.saveItem('sync_metadata', 'user_app_$emailLower', userMap);
          await localDb.enqueueSyncItem(SyncQueueItem(
            id: _uuid.v4(),
            entityId: emailLower,
            entityType: 'app_user',
            operation: 'CREATE_OR_UPDATE',
            payload: userMap,
            createdAt: DateTime.now(),
          ));
        }
      }

      // 4. Implement Forever Linkage: Retrieve assigned agent
      String actualAgentId = quotation.agentId;
      String actualAgentName = quotation.agentName;
      String actualAgentTitle = quotation.agentTitle;

      if (quotation.customerId != null) {
        final customerMap = localDb.getItem('customers', quotation.customerId!);
        if (customerMap != null && customerMap['assignedTo'] != null) {
          actualAgentId = customerMap['assignedTo'];
          // Find actual agent profile from user cache
          final cachedAgent = localDb.getItem('sync_metadata', 'user_profile_$actualAgentId');
          if (cachedAgent != null) {
            actualAgentName = cachedAgent['name'] ?? actualAgentName;
            actualAgentTitle = cachedAgent['role'] ?? actualAgentTitle;
          }
        }
      }

      // 5. Create SaleTransaction
      final transaction = SaleTransaction(
        id: '',
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
        status: 'Completed',
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
    } catch (_) {
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> fetchLinkedOrders(String storeId) async {
    try {
      final snapshot = await db.collection('orders')
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

  Future<List<Map<String, dynamic>>> fetchProductCatalog(String storeId) async {
    try {
      final snapshot = await db.collection('inventory')
          .where('storeId', isEqualTo: storeId)
          .where('deletedAt', isNull: true)
          .get();
      return snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList();
    } catch (e) {
      debugPrint('Error fetching product catalog: $e');
      return [];
    }
  }
}
