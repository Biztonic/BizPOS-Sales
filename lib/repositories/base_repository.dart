import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../database/local_db_service.dart';

abstract class BaseRepository {
  final FirebaseFirestore db = FirebaseFirestore.instance;
  final LocalDatabaseService localDb = LocalDatabaseService();
  final Connectivity _connectivity = Connectivity();

  /// Helper to check if internet connectivity is active
  Future<bool> isConnected() async {
    try {
      final results = await _connectivity.checkConnectivity();
      if (results.isEmpty) return false;
      return results.any((result) => result != ConnectivityResult.none);
    } catch (_) {
      return false; // Fallback to offline if connectivity checking fails
    }
  }

  /// Tenant isolation prefix or helper
  String getStorePath(String storeId) => 'stores/$storeId';
}
