import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../repositories/product_repository.dart';
import '../sync/sync_engine.dart';
import '../models/product.dart';

// 1. Sync Engine Riverpod Provider
final syncEngineProvider = Provider<SyncEngine>((ref) {
  final engine = SyncEngine();
  ref.onDispose(() {
    engine.dispose();
  });
  return engine;
});

// 2. Product Repository Riverpod Provider
final productRepositoryProvider = Provider<ProductRepository>((ref) {
  return ProductRepository();
});

// 3. Cached Products Provider (Exposes cached products with automatic reload on Sync events)
final productsStateProvider = StateNotifierProvider<ProductsNotifier, List<Product>>((ref) {
  final repository = ref.watch(productRepositoryProvider);
  final syncEngine = ref.watch(syncEngineProvider);
  return ProductsNotifier(repository, syncEngine);
});

class ProductsNotifier extends StateNotifier<List<Product>> {
  final ProductRepository _repository;
  final SyncEngine _syncEngine;
  StreamSubscription? _subscription;

  ProductsNotifier(this._repository, this._syncEngine) : super([]) {
    loadCachedProducts();
    _listenToSyncEvents();
  }

  void loadCachedProducts() {
    state = _repository.getLocalProducts();
  }

  void _listenToSyncEvents() {
    _subscription?.cancel();
    _subscription = _syncEngine.syncEvents.listen((entityType) {
      if (entityType == 'product') {
        loadCachedProducts();
      }
    });
  }

  Future<void> syncProducts() async {
    await _repository.syncProductsFromFirestore();
    loadCachedProducts();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}

// 4. Cost-Optimized Dashboard Statistics Riverpod StreamProvider
// Pulls only 1 aggregate summary document rather than downloading all transaction logs!
final dashboardStatsStreamProvider = StreamProvider<Map<String, dynamic>>((ref) {
  return FirebaseFirestore.instance
      .collection('metadata')
      .doc('global_dashboard_stats')
      .snapshots()
      .map((snap) {
        if (snap.exists && snap.data() != null) {
          return snap.data()!;
        }
        return {
          'totalSales': 0.0,
          'totalAgents': 0,
          'avgAchievement': 0.0,
        };
      });
});
