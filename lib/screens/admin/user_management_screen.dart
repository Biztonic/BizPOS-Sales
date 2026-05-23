import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<SalesAuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('User Management'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: _db.collection('sales_users').snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) return const Center(child: Text('Something went wrong'));
          if (snapshot.connectionState == ConnectionState.waiting) return const Center(child: CircularProgressIndicator());

          final users = snapshot.data!.docs;

          return ListView.builder(
            itemCount: users.length,
            itemBuilder: (context, index) {
              final userData = users[index].data() as Map<String, dynamic>;
              final userId = users[index].id;
              final currentRole = userData['role'] ?? 'Sales Executive';
              final name = userData['name'] ?? 'Unknown';
              final email = userData['email'] ?? 'No Email';

              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('$email\nRole: $currentRole'),
                  isThreeLine: true,
                  trailing: PopupMenuButton<String>(
                    onSelected: (newRole) => _updateUserRole(userId, newRole),
                    itemBuilder: (context) => [
                      const PopupMenuItem(value: 'Sales Executive', child: Text('Sales Executive')),
                      const PopupMenuItem(value: 'Team Leader', child: Text('Team Leader')),
                      const PopupMenuItem(value: 'Director', child: Text('Director')),
                      const PopupMenuItem(value: 'SuperAdmin', child: Text('SuperAdmin')),
                    ],
                    child: const Icon(Icons.more_vert),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _updateUserRole(String uid, String newRole) async {
    setState(() => _isLoading = true);
    try {
      final userDoc = await _db.collection('sales_users').doc(uid).get();
      final data = userDoc.data();
      
      final Map<String, dynamic> updates = {
        'role': newRole,
        'updatedAt': FieldValue.serverTimestamp(),
        // If superadmin sets role to Director, it's permanent/rigid
        'isPermanentDirector': newRole == 'Director',
      };

      // Ensure leadership roles have a referral code
      if ((newRole == 'Team Leader' || newRole == 'Director' || newRole == 'SuperAdmin') && 
          (data == null || data['referralCode'] == null || data['referralCode'].toString().isEmpty)) {
        final referralCode = 'TL${uid.substring(0, 5).toUpperCase()}';
        updates['referralCode'] = referralCode;
        updates['promotedAt'] = FieldValue.serverTimestamp();
      }

      await _db.collection('sales_users').doc(uid).update(updates);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('User role updated to $newRole')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error updating role: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }
}
