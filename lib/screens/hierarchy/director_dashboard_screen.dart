import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:provider/provider.dart';
import '../../providers/system_config_provider.dart';
import '../../widgets/responsive_layout.dart';

class DirectorDashboardScreen extends StatefulWidget {
  const DirectorDashboardScreen({super.key});

  @override
  State<DirectorDashboardScreen> createState() => _DirectorDashboardScreenState();
}

class _DirectorDashboardScreenState extends State<DirectorDashboardScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  
  bool _isLoading = true;
  double _globalTurnover = 0.0;
  int _totalDirectors = 0;
  
  @override
  void initState() {
    super.initState();
    _fetchGlobalStats();
  }

  Future<void> _fetchGlobalStats() async {
    setState(() => _isLoading = true);
    try {
      final now = DateTime.now();
      final currentMonth = '${now.year}-${now.month.toString().padLeft(2, '0')}';
      
      // Fetch global turnover for the month
      final salesSnapshot = await _db.collection('sales_transactions')
          .where('targetMonth', isEqualTo: currentMonth)
          .where('status', isEqualTo: 'Completed')
          .get();
          
      double turnover = 0.0;
      for (var doc in salesSnapshot.docs) {
        turnover += (doc.data()['amountPaid'] ?? doc.data()['amount'] ?? 0.0).toDouble();
      }

      // Fetch total directors (include SuperAdmins in the pool)
      final directorsSnapshot = await _db.collection('sales_users')
          .where('role', whereIn: ['Director', 'SuperAdmin'])
          .get();

      setState(() {
        _globalTurnover = turnover;
        _totalDirectors = directorsSnapshot.docs.length > 0 ? directorsSnapshot.docs.length : 1; // Avoid division by zero
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Error fetching global stats: $e');
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final configProvider = context.watch<SystemConfigProvider>();
    final poolRateValue = configProvider.directorPoolRate;
    final poolRate = poolRateValue / 100;
    final totalPool = _globalTurnover * poolRate;
    final myShare = totalPool / _totalDirectors;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Director Dashboard'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ResponsiveLayout(
              mobile: _buildDashboardContent(totalPool, myShare, configProvider),
              tablet: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 800),
                  child: _buildDashboardContent(totalPool, myShare, configProvider),
                ),
              ),
              desktop: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: _buildDashboardContent(totalPool, myShare, configProvider),
                ),
              ),
            ),
    );
  }

  Widget _buildDashboardContent(double totalPool, double myShare, SystemConfigProvider configProvider) {
    return RefreshIndicator(
      onRefresh: _fetchGlobalStats,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'Global Turnover Pool',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                gradient: LinearGradient(
                  colors: [Theme.of(context).colorScheme.primary, Theme.of(context).colorScheme.secondary],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Company Turnover (This Month)',
                    style: TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '₹${_globalTurnover.toStringAsFixed(0)}',
                    style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Global Pool (${configProvider.directorPoolRate.toStringAsFixed(0)}%)', style: const TextStyle(color: Colors.white70)),
                          Text('₹${totalPool.toStringAsFixed(0)}', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Active Directors', style: TextStyle(color: Colors.white70)),
                          Text('$_totalDirectors', style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Icon(Icons.account_balance_wallet, size: 48, color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green),
                  const SizedBox(height: 12),
                  Text('Your Projected Share', style: TextStyle(fontSize: 16, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                  const SizedBox(height: 4),
                  Text('₹${myShare.toStringAsFixed(0)}', style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
