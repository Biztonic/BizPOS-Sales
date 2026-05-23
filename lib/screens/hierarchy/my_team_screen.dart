import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/team_provider.dart';
import '../../widgets/responsive_layout.dart';
import './user_performance_screen.dart';

import 'package:url_launcher/url_launcher.dart';

class MyTeamScreen extends StatefulWidget {
  const MyTeamScreen({super.key});

  @override
  State<MyTeamScreen> createState() => _MyTeamScreenState();
}

class _MyTeamScreenState extends State<MyTeamScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<SalesAuthProvider>();
      if (auth.isLoggedIn) {
        context.read<TeamProvider>().fetchTeamMembers(auth.userId);
      }
    });
  }



  @override
  Widget build(BuildContext context) {
    final team = context.watch<TeamProvider>();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(
            'My Team',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
          ),
        ),
        Expanded(
          child: team.isLoading
              ? const Center(child: CircularProgressIndicator())
              : team.teamMembers.isEmpty
                  ? Center(
                      child: Text(
                        'No team members yet.',

                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                      ),
                    )
                  : ResponsiveLayout(
                      mobile: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: team.teamMembers.length,
                        itemBuilder: (context, index) {
                          final member = team.teamMembers[index];
                          return Card(
                            elevation: 2,
                            margin: const EdgeInsets.only(bottom: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(12),
                              onTap: () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => UserPerformanceScreen(
                                      userId: member['id'],
                                      userName: member['name'] ?? 'Unknown',
                                      userRole: member['role'] ?? 'Sales Executive',
                                    ),
                                  ),
                                );
                              },
                              child: Padding(
                                padding: const EdgeInsets.all(16.0),
                                child: Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 28,
                                      backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                                      child: Icon(Icons.person, color: Theme.of(context).colorScheme.onPrimaryContainer, size: 32),
                                    ),
                                    const SizedBox(width: 16),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Text(
                                            member['name'] ?? 'Unknown', 
                                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)
                                          ),
                                          const SizedBox(height: 4),
                                          Text(
                                            '${member['email']}', 
                                            style: TextStyle(color: Colors.grey[600], fontSize: 13)
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: Colors.deepPurple.withValues(alpha: 0.1),
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              member['role'] ?? 'Sales Executive', 
                                              style: const TextStyle(color: Colors.deepPurple, fontSize: 11, fontWeight: FontWeight.bold)
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        IconButton(
                                          icon: const Icon(Icons.phone, color: Colors.green),
                                          onPressed: () async {
                                            final phone = member['phone'] ?? '';
                                            if (phone.isNotEmpty) {
                                              final uri = Uri.parse('tel:$phone');
                                              if (await canLaunchUrl(uri)) {
                                                await launchUrl(uri);
                                              }
                                            } else {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number not available')));
                                              }
                                            }
                                          },
                                        ),
                                        IconButton(
                                          icon: const Icon(Icons.message, color: Colors.teal),
                                          onPressed: () async {
                                            final phone = member['phone'] ?? '';
                                            if (phone.isNotEmpty) {
                                              final cleanPhone = phone.replaceAll(RegExp(r'[^0-9]'), '');
                                              final uri = Uri.parse('https://wa.me/$cleanPhone');
                                              if (await canLaunchUrl(uri)) {
                                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                                              }
                                            } else {
                                              if (context.mounted) {
                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Phone number not available')));
                                              }
                                            }
                                          },
                                        ),
                                        const Icon(Icons.chevron_right, color: Colors.grey),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
