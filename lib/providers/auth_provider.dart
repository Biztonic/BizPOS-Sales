import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import '../utils/image_helper.dart';
import 'dart:async';
import 'dart:typed_data';

class SalesAuthProvider with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  User? _user;
  Map<String, dynamic>? _userProfile;
  bool _isLoading = false;
  String? _error;

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
  bool get isSuperAdmin => userRole == 'SuperAdmin';
  bool get isDirector => userRole == 'Director' || isSuperAdmin;
  bool get isTeamLeader => userRole == 'Team Leader' || isDirector;
  bool get isSalesExecutive => userRole == 'Sales Executive' || isTeamLeader;
  bool get isPermanentDirector => _userProfile?['isPermanentDirector'] ?? false;
  String? get photoUrl => _userProfile?['photoUrl'];

  SalesAuthProvider() {
    _auth.authStateChanges().listen(_onAuthChanged);
  }

  StreamSubscription? _userProfileSubscription;

  void _onAuthChanged(User? user) async {
    _user = user;
    if (user != null) {
      _userProfileSubscription?.cancel();
      _userProfileSubscription = _db.collection('sales_users').doc(user.uid).snapshots().listen((snapshot) {
        if (snapshot.exists) {
          _userProfile = snapshot.data();
          notifyListeners();
        }
      });
    } else {
      _userProfileSubscription?.cancel();
      _userProfile = null;
    }
    notifyListeners();
  }

  // Remove the old _fetchUserProfile method

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
      // 1. Check if this is the very first user
      final userCheck = await _db.collection('sales_users').limit(1).get();
      final bool isFirstUser = userCheck.docs.isEmpty && teamLeaderCode.trim().toUpperCase() == 'INITIAL';

      String? teamLeaderId;
      String? teamLeaderName;

      if (isFirstUser) {
        teamLeaderId = 'SYSTEM';
        teamLeaderName = 'Root System';
      } else {
        // Verify Team Leader Code
        final tlQuery = await _db
            .collection('sales_users')
            .where('referralCode', isEqualTo: teamLeaderCode.trim().toUpperCase())
            .get();

        if (tlQuery.docs.isEmpty) {
          _error = 'Invalid Team Leader Code. Please check and try again.';
          _isLoading = false;
          notifyListeners();
          return false;
        }

        final teamLeaderDoc = tlQuery.docs.first;
        teamLeaderId = teamLeaderDoc.id;
        teamLeaderName = teamLeaderDoc.data()['name'] ?? 'Unknown';
      }

      // 2. Create Auth User
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );

      // 3. Create user profile in Firestore
      if (credential.user != null) {
        final uid = credential.user!.uid;
        // Generate a unique referral code for this new user
        // If first user, give them a nice default like 'ROOT' or 'BOSS'
        final newReferralCode = isFirstUser ? 'ROOT' : uid.substring(0, 4).toUpperCase();

        await _db.collection('sales_users').doc(uid).set({
          'name': name,
          'email': email.trim(),
          'role': isFirstUser ? 'SuperAdmin' : 'Sales Executive',
          'teamLeaderId': teamLeaderId,
          'teamLeaderName': teamLeaderName,
          'referralCode': isFirstUser ? newReferralCode : null, // Sales Executive starts without code
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
          'appSource': 'bizpos_sales',
        }, SetOptions(merge: true));
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

  Future<void> signOut() async {
    await _auth.signOut();
    _userProfile = null;
    notifyListeners();
  }

  Future<bool> updateReferralCode(String newCode) async {
    if (_user == null) return false;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final sanitizedCode = newCode.trim().toUpperCase();
      if (sanitizedCode.length != 4) {
        _error = 'Referral code must be exactly 4 letters.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // Check for uniqueness
      final duplicateQuery = await _db
          .collection('sales_users')
          .where('referralCode', isEqualTo: sanitizedCode)
          .get();

      if (duplicateQuery.docs.isNotEmpty) {
        // Check if the duplicate is the current user
        final isMine = duplicateQuery.docs.any((doc) => doc.id == _user!.uid);
        if (!isMine) {
          _error = 'Referral code already taken. Please try another one.';
          _isLoading = false;
          notifyListeners();
          return false;
        }
      }

      // Update Firestore
      await _db.collection('sales_users').doc(_user!.uid).update({
        'referralCode': sanitizedCode,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _isLoading = false;
      notifyListeners();
      return true;
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
      // 1. Compress image to under 100kb
      final compressedBytes = await ImageHelper.compressImage(imageBytes, targetSizeKb: 100);
      if (compressedBytes == null) {
        _error = 'Failed to process image.';
        _isLoading = false;
        notifyListeners();
        return false;
      }

      // 2. Upload to Firebase Storage
      final storageRef = _storage.ref().child('profile_photos/${_user!.uid}.jpg');
      final uploadTask = await storageRef.putData(
        compressedBytes,
        SettableMetadata(contentType: 'image/jpeg'),
      );

      // 3. Get Download URL
      final downloadUrl = await uploadTask.ref.getDownloadURL();

      // 4. Update Firestore
      await _db.collection('sales_users').doc(_user!.uid).update({
        'photoUrl': downloadUrl,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      _isLoading = false;
      notifyListeners();
      return true;
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
}
