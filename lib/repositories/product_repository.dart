import 'package:cloud_firestore/cloud_firestore.dart';
import 'base_repository.dart';
import '../models/product.dart';
import '../models/sync_queue_item.dart';
import 'package:uuid/uuid.dart';

class ProductRepository extends BaseRepository {
  final Uuid _uuid = const Uuid();

  /// Retrieve products from local Hive database first, fallback to Firestore if empty or forced
  Future<List<Product>> getProducts({bool forceSync = false}) async {
    final cachedData = localDb.getAllItems('products');
    
    if (cachedData.isEmpty || forceSync) {
      if (await isConnected()) {
        await syncProductsFromFirestore();
        return getLocalProducts();
      }
    }
    
    final list = cachedData.map((map) => Product.fromMap(map, map['id'] ?? '')).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Retrieve directly from local Hive box without network access
  List<Product> getLocalProducts() {
    final cached = localDb.getAllItems('products');
    final list = cached.map((map) => Product.fromMap(map, map['id'] ?? '')).toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Sync all products from remote Firestore to Hive
  Future<void> syncProductsFromFirestore() async {
    try {
      final snapshot = await db.collection('products').get();
      final Map<String, Map<String, dynamic>> itemsToCache = {};
      
      for (var doc in snapshot.docs) {
        final data = doc.data();
        data['id'] = doc.id;
        // Parse Timestamps to string to ensure safe Hive storage
        if (data['createdAt'] is Timestamp) {
          data['createdAt'] = (data['createdAt'] as Timestamp).toDate().toIso8601String();
        }
        itemsToCache[doc.id] = data;
      }
      
      if (itemsToCache.isNotEmpty) {
        await localDb.clearBox('products');
        await localDb.saveAllItems('products', itemsToCache);
        await localDb.setLastSyncTime('products', DateTime.now());
      }
    } catch (e) {
      // Offline or network error: fail silently or let caller handle
    }
  }

  /// Save new product
  Future<void> addProduct(Product product) async {
    final id = product.id.isEmpty ? _uuid.v4() : product.id;
    final Map<String, dynamic> productMap = {
      ...product.toMap(),
      'id': id,
      'createdAt': product.createdAt.toIso8601String(),
    };

    // 1. Write to local database
    await localDb.saveItem('products', id, productMap);

    // 2. Enqueue mutation
    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: id,
      entityType: 'product',
      operation: 'CREATE',
      payload: productMap,
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);
  }

  /// Toggle active state of product
  Future<void> toggleProductActive(String productId, bool isActive) async {
    final Map<String, dynamic>? cached = localDb.getItem('products', productId);
    if (cached != null) {
      cached['isActive'] = isActive;
      await localDb.saveItem('products', productId, cached);

      // Enqueue update
      final queueItem = SyncQueueItem(
        id: _uuid.v4(),
        entityId: productId,
        entityType: 'product',
        operation: 'UPDATE',
        payload: {'isActive': isActive},
        createdAt: DateTime.now(),
      );
      await localDb.enqueueSyncItem(queueItem);
    }
  }

  /// Delete product
  Future<void> deleteProduct(String productId) async {
    // 1. Delete locally
    await localDb.deleteItem('products', productId);

    // 2. Enqueue deletion
    final queueItem = SyncQueueItem(
      id: _uuid.v4(),
      entityId: productId,
      entityType: 'product',
      operation: 'DELETE',
      payload: {},
      createdAt: DateTime.now(),
    );
    await localDb.enqueueSyncItem(queueItem);
  }
}
