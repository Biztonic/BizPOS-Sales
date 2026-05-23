import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../database/local_db_service.dart';

class SystemConfigProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final LocalDatabaseService _localDb = LocalDatabaseService();

  Map<String, dynamic> _config = {
    'targetAmount': 200000.0,
    'baseSalaryAtTarget': 25000.0,
    'baseCommissionRate': 10.0,
    'excessCommissionRate': 20.0,
    'teamLeaderOverrideRate': 5.0,
    'directorPoolRate': 12.0,
    'targetBonus': 5000.0,
    'directorPromotionQuota': 10,
    'allowNewRegistrations': true,
    'requireEmailVerification': false,
    'defaultUserRole': 'Sales Executive',
    'maintenanceMode': false,
  };

  bool _isLoading = false;
  String? _error;
  StreamSubscription? _configSubscription;

  Map<String, dynamic> get config => _config;
  bool get isLoading => _isLoading;
  String? get error => _error;

  double get targetAmount => (_config['targetAmount'] ?? 200000.0).toDouble();
  double get baseSalaryAtTarget => (_config['baseSalaryAtTarget'] ?? 25000.0).toDouble();
  double get baseCommissionRate => (_config['baseCommissionRate'] ?? 10.0).toDouble();
  double get excessCommissionRate => (_config['excessCommissionRate'] ?? 20.0).toDouble();
  double get teamLeaderOverrideRate => (_config['teamLeaderOverrideRate'] ?? 5.0).toDouble();
  double get directorPoolRate => (_config['directorPoolRate'] ?? 12.0).toDouble();
  double get targetBonus => (_config['targetBonus'] ?? 5000.0).toDouble();
  int get directorPromotionQuota => (_config['directorPromotionQuota'] ?? 10).toInt();
  bool get allowNewRegistrations => _config['allowNewRegistrations'] ?? true;
  bool get maintenanceMode => _config['maintenanceMode'] ?? false;

  SystemConfigProvider() {
    _loadInitialCache();
    _startListeningToConfig();
  }

  void _loadInitialCache() {
    final cached = _localDb.getItem('sync_metadata', 'system_config');
    if (cached != null) {
      _config = {..._config, ...cached};
    }
  }

  void _startListeningToConfig() {
    _isLoading = true;
    Future.microtask(() => notifyListeners());

    _configSubscription = _db.collection('system_settings')
        .doc('global_config')
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists && snapshot.data() != null) {
        _config = {..._config, ...snapshot.data()!};
        await _localDb.saveItem('sync_metadata', 'system_config', _config);
      } else {
        await _db.collection('system_settings').doc('global_config').set(_config);
      }
      _isLoading = false;
      notifyListeners();
    }, onError: (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    });
  }

  Future<void> fetchConfig() async {
    // Config loaded via listener and cache
  }

  Future<bool> updateConfig(Map<String, dynamic> newConfig) async {
    _isLoading = true;
    notifyListeners();

    try {
      // Direct local update
      _config = {..._config, ...newConfig};
      await _localDb.saveItem('sync_metadata', 'system_config', _config);
      notifyListeners();

      // remote update
      await _db.collection('system_settings').doc('global_config').update(newConfig);
      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  @override
  void dispose() {
    _configSubscription?.cancel();
    super.dispose();
  }
}
