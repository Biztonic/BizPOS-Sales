import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../repositories/auth_repository.dart';
import '../sync/sync_engine.dart';
import 'dart:async';
import 'dart:typed_data';

class SalesAuthProvider with ChangeNotifier {
  final AuthRepository _repository = AuthRepository();
  final FirebaseAuth _auth = FirebaseAuth.instance;

  User? _user;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = false;
  String? _error;
  StreamSubscription? _userProfileSubscription;

  // Getters
  User? get user => _user;
  Map<String, dynamic>? get userProfile => _userProfile;
  bool get isLoading => _isLoading;
  bool get isLoggedIn => _user != null;
  String? get error => _error;
  String get userId => _user?.uid ?? '';
  String get userEmail => _user?.email ?? '';
  String get userName => _userProfile?['name'] ?? _user?.displayName ?? '';
  String get userRole => _userProfile?['role'] ?? 'Sales Executive';
  String get storeId => _userProfile?['storeId'] ?? 'DEFAULT_STORE';
  bool get isSuperAdmin => userRole == 'SuperAdmin';
  bool get isDirector => userRole == 'Director' || isSuperAdmin;
  bool get isTeamLeader => userRole == 'Team Leader' || isDirector;
  bool get isSalesExecutive => userRole == 'Sales Executive' || isTeamLeader;
  bool get isPermanentDirector => _userProfile?['isPermanentDirector'] ?? false;
  String? get photoUrl => _userProfile?['photoUrl'];

  SalesAuthProvider() {
    _auth.authStateChanges().listen(_onAuthChanged);
  }

  void _onAuthChanged(User? user) async {
    _user = user;
    if (user != null) {
      _userProfileSubscription?.cancel();

      // 1. Try to load user profile instantly from local Hive cache
      _userProfile = await _repository.getUserProfile(user.uid);
      notifyListeners();

      // 2. Start realtime listener for updates and refresh cache
      _userProfileSubscription = _repository.db
          .collection('sales_users')
          .doc(user.uid)
          .snapshots()
          .listen((snapshot) async {
        if (snapshot.exists && snapshot.data() != null) {
          _userProfile = snapshot.data();
          await _repository.cacheUserProfile(user.uid, _userProfile!);
          notifyListeners();

          // Initialize sync listener for their store
          SyncEngine().startSyncListener(storeId, onSyncChange: () {
            // Callback when delta versions change
            notifyListeners();
          });
        }
      });

      // Start Sync Engine queue flushing
      SyncEngine().start();
      SyncEngine().flushQueue();
    } else {
      _userProfileSubscription?.cancel();
      _userProfile = null;
      SyncEngine().stopSyncListener();
    }
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _getErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> signUp({
    required String email,
    required String password,
    required String name,
    required String teamLeaderCode,
  }) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final isFirst = await _repository.isFirstUser();
      final isRoot = isFirst && teamLeaderCode.trim().toUpperCase() == 'INITIAL';

      String? teamLeaderId;
      String? teamLeaderName;

      if (isRoot) {
        teamLeaderId = 'SYSTEM';
        teamLeaderName = 'Root System';
      } else {
        final tlInfo = await _repository.verifyTeamLeaderCode(teamLeaderCode);
        if (tlInfo == null) {
          _error = 'Invalid Team Leader Code. Please check and try again.';
          _isLoading = false;
          notifyListeners();
          return false;
        }
        teamLeaderId = tlInfo['id'];
        teamLeaderName = tlInfo['name'];
      }

      final role = isRoot ? 'SuperAdmin' : 'Sales Executive';
      final generatedReferralCode = isRoot ? 'ROOT' : _uuidReferralFallback();

      final signedUser = await _repository.signUp(
        email: email,
        password: password,
        name: name,
        teamLeaderId: teamLeaderId,
        teamLeaderName: teamLeaderName,
        role: role,
        referralCode: generatedReferralCode,
      );

      if (signedUser == null) {
        _error = 'Failed to create user account.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      _isLoading = false;
      notifyListeners();
      return true;
    } on FirebaseAuthException catch (e) {
      _error = _getErrorMessage(e.code);
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'An unexpected error occurred: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  String _uuidReferralFallback() {
    // Generate a quick 4-character uppercase code
    final uid = _auth.currentUser?.uid ?? 'XXXX';
    return uid.substring(0, 4).toUpperCase();
  }

  Future<void> signOut() async {
    _userProfileSubscription?.cancel();
    await _auth.signOut();
    _userProfile = null;
    SyncEngine().stopSyncListener();
    notifyListeners();
  }

  Future<bool> updateReferralCode(String newCode) async {
    if (_user == null) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final success = await _repository.updateReferralCode(_user!.uid, newCode);
      _isLoading = false;
      notifyListeners();
      return success;
    } catch (e) {
      _error = 'Failed to update referral code: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  Future<bool> updateProfilePhoto(Uint8List imageBytes) async {
    if (_user == null) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final url = await _repository.uploadProfilePhoto(_user!.uid, imageBytes);
      _isLoading = false;
      if (url != null) {
        if (_userProfile != null) {
          _userProfile!['photoUrl'] = url;
        }
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      _error = 'Failed to upload photo: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  String _getErrorMessage(String code) {
    switch (code) {
      case 'user-not-found':
        return 'No user found with this email.';
      case 'wrong-password':
        return 'Invalid password.';
      case 'email-already-in-use':
        return 'This email is already registered.';
      case 'weak-password':
        return 'Password is too weak.';
      case 'invalid-email':
        return 'Invalid email address.';
      default:
        return 'Authentication error: $code';
    }
  }

  @override
  void dispose() {
    _userProfileSubscription?.cancel();
    super.dispose();
  }
}
