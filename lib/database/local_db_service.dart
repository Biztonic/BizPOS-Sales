import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../models/sync_queue_item.dart';

class LocalDatabaseService {
  static final LocalDatabaseService _instance = LocalDatabaseService._internal();
  factory LocalDatabaseService() => _instance;
  LocalDatabaseService._internal();

  // Box Names
  static const String productsBoxName = 'products';
  static const String customersBoxName = 'customers';
  static const String transactionsBoxName = 'sales_transactions';
  static const String commissionsBoxName = 'commissions';
  static const String expensesBoxName = 'expenses';
  static const String syncQueueBoxName = 'sync_queue';
  static const String syncMetadataBoxName = 'sync_metadata';

  // Initialize all boxes
  Future<void> init() async {
    try {
      await Hive.openBox(productsBoxName);
      await Hive.openBox(customersBoxName);
      await Hive.openBox(transactionsBoxName);
      await Hive.openBox(commissionsBoxName);
      await Hive.openBox(expensesBoxName);
      await Hive.openBox(syncQueueBoxName);
      await Hive.openBox(syncMetadataBoxName);
      debugPrint("All Hive boxes initialized successfully.");
    } catch (e) {
      debugPrint("Error initializing Hive boxes: $e");
    }
  }

  // --- Generic Cache Helpers ---

  Future<void> saveItem(String boxName, String id, Map<String, dynamic> data) async {
    final box = Hive.box(boxName);
    await box.put(id, data);
  }

  Future<void> saveAllItems(String boxName, Map<String, Map<String, dynamic>> items) async {
    final box = Hive.box(boxName);
    await box.putAll(items);
  }

  Map<String, dynamic>? getItem(String boxName, String id) {
    final box = Hive.box(boxName);
    final data = box.get(id);
    if (data == null) return null;
    return Map<String, dynamic>.from(data);
  }

  List<Map<String, dynamic>> getAllItems(String boxName) {
    final box = Hive.box(boxName);
    return box.values.map((item) => Map<String, dynamic>.from(item)).toList();
  }

  Future<void> deleteItem(String boxName, String id) async {
    final box = Hive.box(boxName);
    await box.delete(id);
  }

  Future<void> clearBox(String boxName) async {
    final box = Hive.box(boxName);
    await box.clear();
  }

  // --- Metadata & Version Helpers ---

  Future<void> setLastSyncTime(String collection, DateTime time) async {
    final box = Hive.box(syncMetadataBoxName);
    await box.put('${collection}_last_sync', time.toIso8601String());
  }

  DateTime? getLastSyncTime(String collection) {
    final box = Hive.box(syncMetadataBoxName);
    final timeStr = box.get('${collection}_last_sync');
    if (timeStr == null) return null;
    return DateTime.parse(timeStr);
  }

  Future<void> setLocalVersion(String collection, int version) async {
    final box = Hive.box(syncMetadataBoxName);
    await box.put('${collection}_version', version);
  }

  int getLocalVersion(String collection) {
    final box = Hive.box(syncMetadataBoxName);
    return box.get('${collection}_version') ?? 0;
  }

  // --- Sync Queue Helpers ---

  Future<void> enqueueSyncItem(SyncQueueItem item) async {
    final box = Hive.box(syncQueueBoxName);
    await box.put(item.id, item.toMap());
  }

  List<SyncQueueItem> getPendingSyncQueue() {
    final box = Hive.box(syncQueueBoxName);
    final list = box.values
        .map((item) => SyncQueueItem.fromMap(Map<String, dynamic>.from(item)))
        .toList();
    // Sort so older mutations are processed first to maintain chronological order
    list.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  Future<void> updateSyncQueueStatus(String id, String status, {String? errorMessage, int? retryCount}) async {
    final box = Hive.box(syncQueueBoxName);
    final data = box.get(id);
    if (data != null) {
      final item = SyncQueueItem.fromMap(Map<String, dynamic>.from(data));
      final updated = item.copyWith(
        status: status,
        errorMessage: errorMessage,
        retryCount: retryCount ?? item.retryCount,
      );
      await box.put(id, updated.toMap());
    }
  }

  Future<void> dequeueSyncItem(String id) async {
    final box = Hive.box(syncQueueBoxName);
    await box.delete(id);
  }
}
