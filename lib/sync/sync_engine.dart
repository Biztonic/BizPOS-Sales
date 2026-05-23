import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import '../database/local_db_service.dart';
import '../models/sync_queue_item.dart';

class SyncEngine {
  static final SyncEngine _instance = SyncEngine._internal();
  factory SyncEngine() => _instance;
  SyncEngine._internal();

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final LocalDatabaseService _localDb = LocalDatabaseService();
  final Connectivity _connectivity = Connectivity();

  StreamSubscription? _connectivitySubscription;
  StreamSubscription? _versionListenerSubscription;
  bool _isSyncing = false;

  final _syncEventController = StreamController<String>.broadcast();
  Stream<String> get syncEvents => _syncEventController.stream;

  void start() {
    _connectivitySubscription?.cancel();
    _connectivitySubscription = _connectivity.onConnectivityChanged.listen((results) {
      if (results.isNotEmpty && !results.contains(ConnectivityResult.none)) {
        debugPrint("Connectivity restored. Starting sync queue flush...");
        flushQueue();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    _versionListenerSubscription?.cancel();
  }

  Future<void> flushQueue() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final queue = _localDb.getPendingSyncQueue();
      if (queue.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint("Sync Engine: Found ${queue.length} items in offline queue.");

      for (var item in queue) {
        if (item.status == 'FAILED') continue;

        bool success = await _syncItem(item);
        if (success) {
          await _localDb.dequeueSyncItem(item.id);
          debugPrint("Sync Engine: Successfully synced item ${item.entityId} (${item.entityType})");
          
          final storeId = item.payload['storeId'] ?? 'DEFAULT_STORE';
          await _incrementRemoteVersion(storeId, item.entityType);
        } else {
          final results = await _connectivity.checkConnectivity();
          final hasNetwork = results.isNotEmpty && !results.contains(ConnectivityResult.none);
          if (!hasNetwork) {
            debugPrint("Sync Engine: Network lost during sync. Pausing queue.");
            break;
          } else {
            final retry = item.retryCount + 1;
            if (retry >= 5) {
              await _localDb.updateSyncQueueStatus(
                item.id,
                'FAILED',
                errorMessage: 'Max retries exceeded.',
                retryCount: retry,
              );
            } else {
              await _localDb.updateSyncQueueStatus(
                item.id,
                'PENDING',
                retryCount: retry,
              );
            }
          }
        }
      }
    } catch (e) {
      debugPrint("Error flushing sync queue: $e");
    } finally {
      _isSyncing = false;
    }
  }

  Future<bool> _syncItem(SyncQueueItem item) async {
    try {
      final payload = Map<String, dynamic>.from(item.payload);
      final storeId = payload['storeId'] ?? 'DEFAULT_STORE';

      _convertDatesToTimestamps(payload);

      CollectionReference getRef() {
        switch (item.entityType) {
          case 'product':
            return _db.collection('products');
          case 'customer':
            return _db.collection('stores').doc(storeId).collection('customers');
          case 'transaction':
            return _db.collection('sales_transactions');
          case 'commission':
            return _db.collection('commissions');
          case 'expense':
            return _db.collection('expenses');
          case 'quotation':
            return _db.collection('quotations');
          case 'subscription_request':
            return _db.collection('subscription_requests');
          case 'app_user':
            return _db.collection('users');
          case 'sales_user':
            return _db.collection('sales_users');
          default:
            return _db.collection('misc_sync');
        }
      }

      final ref = getRef();

      if (item.operation == 'CREATE' || item.operation == 'CREATE_OR_UPDATE') {
        await ref.doc(item.entityId).set(payload, SetOptions(merge: true));
        
        // --- Precomputed Dashboard Summary Updates ---
        if (item.entityType == 'transaction') {
          final amount = (payload['amountPaid'] ?? payload['amount'] ?? 0.0).toDouble();
          final status = payload['status'] ?? 'Completed';
          if (status == 'Completed') {
            await _db.collection('metadata').doc('global_dashboard_stats').set({
              'totalSales': FieldValue.increment(amount),
              'updatedAt': FieldValue.serverTimestamp(),
            }, SetOptions(merge: true));
          }
        } else if (item.entityType == 'sales_user') {
          await _db.collection('metadata').doc('global_dashboard_stats').set({
            'totalAgents': FieldValue.increment(1),
            'updatedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
        }

      } else if (item.operation == 'UPDATE') {
        await ref.doc(item.entityId).update(payload);
      } else if (item.operation == 'DELETE') {
        await ref.doc(item.entityId).delete();
      }
      return true;
    } catch (e) {
      debugPrint("Failed to sync item ${item.entityId} to Firestore: $e");
      return false;
    }
  }

  void _convertDatesToTimestamps(Map<String, dynamic> data) {
    final dateKeys = [
      'createdAt',
      'updatedAt',
      'paidAt',
      'validUntil',
      'lastContactedAt',
      'nextFollowUpAt',
      'subscriptionExpiry',
      'purchaseDate',
      'expiryDate',
      'approvedAt'
    ];
    for (var key in dateKeys) {
      if (data.containsKey(key) && data[key] is String) {
        final date = DateTime.tryParse(data[key]);
        if (date != null) {
          data[key] = Timestamp.fromDate(date);
        }
      }
    }
  }

  Future<void> _incrementRemoteVersion(String storeId, String entityType) async {
    try {
      final docRef = _db.collection('stores').doc(storeId).collection('metadata').doc('sync_versions');
      await docRef.set({
        '${entityType}_version': FieldValue.increment(1),
        '${entityType}_updatedAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  void startSyncListener(String storeId, {VoidCallback? onSyncChange}) {
    _versionListenerSubscription?.cancel();
    
    final docRef = _db.collection('stores').doc(storeId).collection('metadata').doc('sync_versions');
    
    _versionListenerSubscription = docRef.snapshots().listen((snapshot) async {
      if (snapshot.exists && snapshot.data() != null) {
        final data = snapshot.data()!;
        bool hasChanges = false;

        final collections = ['product', 'customer', 'transaction', 'commission', 'expense', 'quotation'];
        for (var coll in collections) {
          final remoteVer = data['${coll}_version'] ?? 0;
          final localVer = _localDb.getLocalVersion(coll);

          if (remoteVer > localVer) {
            debugPrint("Sync Engine: Delta change detected for $coll. Pulling updates...");
            await _pullDeltaSync(storeId, coll, remoteVer);
            hasChanges = true;
          }
        }

        if (hasChanges && onSyncChange != null) {
          onSyncChange();
        }
      }
    }, onError: (e) {
      debugPrint("Error listening to sync versions: $e");
    });
  }

  Future<void> _pullDeltaSync(String storeId, String entityType, int remoteVer) async {
    try {
      final lastSync = _localDb.getLastSyncTime(entityType) ?? DateTime.now().subtract(const Duration(days: 30));
      Query query;

      switch (entityType) {
        case 'product':
          query = _db.collection('products');
          break;
        case 'customer':
          query = _db.collection('stores').doc(storeId).collection('customers');
          break;
        case 'transaction':
          query = _db.collection('sales_transactions').where('storeId', isEqualTo: storeId);
          break;
        case 'commission':
          query = _db.collection('commissions').where('storeId', isEqualTo: storeId);
          break;
        case 'expense':
          query = _db.collection('expenses');
          break;
        case 'quotation':
          query = _db.collection('quotations').where('storeId', isEqualTo: storeId);
          break;
        default:
          return;
      }

      final snapshot = await query.where('updatedAt', isGreaterThan: Timestamp.fromDate(lastSync)).get();
      
      final String hiveBoxName = entityType == 'transaction' ? 'sales_transactions' : '${entityType}s';
      
      for (var doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        data['id'] = doc.id;

        data.forEach((key, value) {
          if (value is Timestamp) {
            data[key] = value.toDate().toIso8601String();
          }
        });

        await _localDb.saveItem(hiveBoxName, doc.id, data);
      }

      await _localDb.setLocalVersion(entityType, remoteVer);
      await _localDb.setLastSyncTime(entityType, DateTime.now());
      debugPrint("Sync Engine: Synced ${snapshot.docs.length} delta docs for $entityType.");

      _syncEventController.add(entityType);
    } catch (e) {
      debugPrint("Error pulling delta sync for $entityType: $e");
    }
  }

  void stopSyncListener() {
    _versionListenerSubscription?.cancel();
    _versionListenerSubscription = null;
  }
}
