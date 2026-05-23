import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/team_provider.dart';
import '../../providers/auth_provider.dart';

class TeamListScreen extends StatefulWidget {
  const TeamListScreen({super.key});

  @override
  State<TeamListScreen> createState() => _TeamListScreenState();
}

class _TeamListScreenState extends State<TeamListScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<SalesAuthProvider>();
      context.read<TeamProvider>().fetchTeamMembers(auth.userId, isSuperAdmin: auth.isDirector);
    });
  }

  @override
  Widget build(BuildContext context) {
    final teamProvider = context.watch<TeamProvider>();
    final auth = context.watch<SalesAuthProvider>();

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
          child: teamProvider.isLoading
              ? const Center(child: CircularProgressIndicator())
              : teamProvider.error != null
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(Icons.error_outline, size: 64, color: Colors.red),
                          const SizedBox(height: 16),
                          Text(
                            teamProvider.error!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.red),
                          ),
                          const SizedBox(height: 16),
                          ElevatedButton(
                            onPressed: () {
                              final auth = context.read<SalesAuthProvider>();
                              context.read<TeamProvider>().fetchTeamMembers(auth.userId, isSuperAdmin: auth.isDirector);
                            },
                            child: const Text('Retry'),
                          ),
                        ],
                      ),
                    )
                  : teamProvider.teamMembers.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.group_outlined, size: 64, color: Colors.grey[400]),
                              const SizedBox(height: 16),
                              Text('No team members yet', style: TextStyle(color: Colors.grey[600])),
                            ],
                          ),
                        )
                  : ListView.builder(
                      itemCount: teamProvider.teamMembers.length,
                      itemBuilder: (context, index) {
                        final member = teamProvider.teamMembers[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: const Color(0xFF00ACC1).withValues(alpha: 0.1),
                              child: Text(member['name']?[0] ?? '?', style: const TextStyle(color: Color(0xFF00ACC1))),
                            ),
                            title: Text(member['name'] ?? 'Unknown'),
                            subtitle: Text(member['role'] ?? 'Sales Executive'),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _showMemberOverview(context, member),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }



  void _showMemberOverview(BuildContext context, Map<String, dynamic> member) {
    // Show a bottom sheet or dialog with stats
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        height: MediaQuery.of(context).size.height * 0.7,
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 30,
                  backgroundColor: const Color(0xFF00ACC1),
                  child: Text(
                    member['name']?[0] ?? '?',
                    style: const TextStyle(color: Colors.white, fontSize: 24),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(member['name'] ?? 'Unknown', style: Theme.of(context).textTheme.headlineSmall),
                      Text(member['role'] ?? 'Sales Executive', style: TextStyle(color: Colors.grey[600])),
                    ],
                  ),
                ),
                IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close)),
              ],
            ),
            const Divider(height: 40),
            Text('Business Performance', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 16),
            _buildStatCard('Monthly Sales', '₹${(member['monthlySales'] ?? 0.0).toStringAsFixed(0)}', Icons.trending_up, Colors.green),
            const SizedBox(height: 12),
            _buildStatCard('Total Commission', '₹${(member['totalCommission'] ?? 0.0).toStringAsFixed(0)}', Icons.account_balance_wallet, Colors.blue),
            const SizedBox(height: 12),
            _buildStatCard('Active Quotes', '${member['activeQuotes'] ?? 0}', Icons.description, Colors.orange),
            const Spacer(),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00ACC1),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
          const Spacer(),
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        ],
      ),
    );
  }
}
