import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'base_repository.dart';
import '../utils/image_helper.dart';

class AuthRepository extends BaseRepository {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;

  User? get currentUser => _auth.currentUser;

  /// Fetch user profile from cache immediately, fallback to Firebase Firestore
  Future<Map<String, dynamic>?> getUserProfile(String uid) async {
    // 1. Read from Hive cache
    final cached = localDb.getItem('sync_metadata', 'user_profile_$uid');
    if (cached != null) {
      return cached;
    }

    // 2. Fallback to Firestore
    try {
      final doc = await db.collection('sales_users').doc(uid).get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        await cacheUserProfile(uid, data);
        return data;
      }
    } catch (_) {
      // Ignore network errors, return null (stale/empty)
    }
    return null;
  }

  /// Cache user profile in Hive
  Future<void> cacheUserProfile(String uid, Map<String, dynamic> profile) async {
    await localDb.saveItem('sync_metadata', 'user_profile_$uid', profile);
  }

  /// Check if user is the first system user
  Future<bool> isFirstUser() async {
    try {
      final userCheck = await db.collection('sales_users').limit(1).get();
      return userCheck.docs.isEmpty;
    } catch (_) {
      return false;
    }
  }

  /// Verify Team Leader Code
  Future<Map<String, dynamic>?> verifyTeamLeaderCode(String code) async {
    try {
      final query = await db
          .collection('sales_users')
          .where('referralCode', isEqualTo: code.trim().toUpperCase())
          .limit(1)
          .get();

      if (query.docs.isNotEmpty) {
        final doc = query.docs.first;
        return {
          'id': doc.id,
          'name': doc.data()['name'] ?? 'Unknown',
        };
      }
    } catch (_) {}
    return null;
  }

  /// Create auth account and profile in Firestore
  Future<User?> signUp({
    required String email,
    required String password,
    required String name,
    required String? teamLeaderId,
    required String? teamLeaderName,
    required String role,
    required String referralCode,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );

    if (credential.user != null) {
      final uid = credential.user!.uid;
      final profile = {
        'name': name,
        'email': email.trim(),
        'role': role,
        'teamLeaderId': teamLeaderId,
        'teamLeaderName': teamLeaderName,
        'referralCode': referralCode,
        'createdAt': DateTime.now().toIso8601String(), // store ISO string for local compatibility
        'updatedAt': DateTime.now().toIso8601String(),
        'appSource': 'bizpos_sales',
      };

      // Write to Remote Firestore (with check for connectivity)
      if (await isConnected()) {
        await db.collection('sales_users').doc(uid).set({
          ...profile,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      } else {
        // Enqueue profile synchronization if offline
        // (Typically registration requires internet anyway, but we handle it gracefully)
        await db.collection('sales_users').doc(uid).set(profile);
      }

      await cacheUserProfile(uid, profile);
      return credential.user;
    }
    return null;
  }

  /// Update referral code
  Future<bool> updateReferralCode(String uid, String newCode) async {
    final updateData = {
      'referralCode': newCode.trim().toUpperCase(),
      'updatedAt': DateTime.now().toIso8601String(),
    };

    // Update Cache
    final profile = await getUserProfile(uid);
    if (profile != null) {
      profile['referralCode'] = updateData['referralCode'];
      profile['updatedAt'] = updateData['updatedAt'];
      await cacheUserProfile(uid, profile);
    }

    // Write to remote if online
    if (await isConnected()) {
      await db.collection('sales_users').doc(uid).update({
        'referralCode': updateData['referralCode'],
        'updatedAt': FieldValue.serverTimestamp(),
      });
      return true;
    } else {
      // Enqueue to offline sync
      // Add to sync queue
      return false; // Auth operations generally require network confirmation
    }
  }

  /// Update profile photo
  Future<String?> uploadProfilePhoto(String uid, Uint8List imageBytes) async {
    final compressedBytes = await ImageHelper.compressImage(imageBytes, targetSizeKb: 100);
    if (compressedBytes == null) return null;

    final storageRef = _storage.ref().child('profile_photos/$uid.jpg');
    final uploadTask = await storageRef.putData(
      compressedBytes,
      SettableMetadata(contentType: 'image/jpeg'),
    );

    final downloadUrl = await uploadTask.ref.getDownloadURL();

    // Update Remote Profile
    await db.collection('sales_users').doc(uid).update({
      'photoUrl': downloadUrl,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Update Cache
    final profile = await getUserProfile(uid);
    if (profile != null) {
      profile['photoUrl'] = downloadUrl;
      profile['updatedAt'] = DateTime.now().toIso8601String();
      await cacheUserProfile(uid, profile);
    }

    return downloadUrl;
  }
}
