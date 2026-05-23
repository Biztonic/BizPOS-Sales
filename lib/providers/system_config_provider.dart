import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SystemConfigProvider with ChangeNotifier {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  Map<String, dynamic> _config = {
    // Commission Defaults
    'targetAmount': 200000.0,
    'baseSalaryAtTarget': 25000.0,
    'baseCommissionRate': 10.0, // %
    'excessCommissionRate': 20.0, // %
    'teamLeaderOverrideRate': 5.0, // %
    'directorPoolRate': 12.0, // %
    'targetBonus': 5000.0,
    'directorPromotionQuota': 10,
    // Login & Auth Config
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

  // Easy access getters
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
    _startListeningToConfig();
  }

  /// Real-time listener for system config — changes propagate instantly.
  void _startListeningToConfig() {
    _isLoading = true;
    Future.microtask(() => notifyListeners());

    _configSubscription = _db.collection('system_settings')
        .doc('global_config')
        .snapshots()
        .listen((snapshot) async {
      if (snapshot.exists) {
        _config = {..._config, ...snapshot.data()!};
      } else {
        // Initialize with defaults if not exists
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

  /// Legacy method kept for backward compatibility — now a no-op since listener handles it.
  Future<void> fetchConfig() async {
    // Config is now fetched via real-time listener in constructor
  }

  Future<bool> updateConfig(Map<String, dynamic> newConfig) async {
    _isLoading = true;
    notifyListeners();

    try {
      await _db.collection('system_settings').doc('global_config').update(newConfig);
      // Real-time listener will automatically pick up the change
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
