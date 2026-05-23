import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/sale_transaction.dart';
import '../../widgets/responsive_layout.dart';

class UserPerformanceScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userRole;

  const UserPerformanceScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userRole,
  });

  @override
  State<UserPerformanceScreen> createState() => _UserPerformanceScreenState();
}

class _UserPerformanceScreenState extends State<UserPerformanceScreen> {
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  bool _isLoading = true;
  List<SaleTransaction> _transactions = [];
  double _totalSales = 0.0;
  double _totalEarned = 0.0;
  double _targetAmount = 0.0;
  double _currentMonthSales = 0.0;
  int _activeQuotes = 0;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      // 1. Fetch transactions (Remove orderBy to avoid index requirement for new users/agents)
      final transSnapshot = await _db.collection('sales_transactions')
          .where('agentId', isEqualTo: widget.userId)
          .get();

      // Sort locally
      final allDocs = transSnapshot.docs;
      _transactions = allDocs
          .map((doc) => SaleTransaction.fromMap(doc.data(), doc.id))
          .toList();
      
      // Sort by createdAt descending
      _transactions.sort((a, b) => b.createdAt.compareTo(a.createdAt));

      _totalSales = _transactions
          .where((t) => t.status == 'Completed')
          .fold(0.0, (sum, t) => sum + (t.amountPaid > 0 ? t.amountPaid : t.amount));
    

      final now = DateTime.now();
      final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';

      _currentMonthSales = _transactions
          .where((t) => t.status == 'Completed' && t.targetMonth == monthKey)
          .fold(0.0, (sum, t) => sum + (t.amountPaid > 0 ? t.amountPaid : t.amount));
    

      // 2. Fetch commissions
      final commSnapshot = await _db.collection('commissions')
          .where('agentId', isEqualTo: widget.userId)
          .get();
      
      _totalEarned = commSnapshot.docs.fold(0.0, (sum, doc) => sum + (doc.data()['amount'] ?? 0.0));

      // 3. Fetch Active Quotes
      final quoteSnapshot = await _db.collection('quotations')
          .where('agentId', isEqualTo: widget.userId)
          .where('status', isEqualTo: 'PENDING')
          .get();
      _activeQuotes = quoteSnapshot.docs.length;

      // 4. Fetch targets/config
      try {
        final configDoc = await _db.collection('system_settings').doc('global_config').get();
        if (configDoc.exists) {
          final data = configDoc.data();
          _targetAmount = (data?['targetAmount'] ?? 200000.0).toDouble();
        } else {
          _targetAmount = 200000.0;
        }
      } catch (e) {
        debugPrint('Error fetching config: $e');
        _targetAmount = 200000.0;
      }

    } catch (e) {
      debugPrint('Error loading user data: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading performance data: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.userName}\'s Performance'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadUserData,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildHeaderCard(),
                  const SizedBox(height: 16),
                  _buildStatsGrid(),
                  const SizedBox(height: 24),
                  const Text(
                    'Recent Sales',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  if (_transactions.isEmpty)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(32.0),
                        child: Text('No sales records found for this user.'),
                      ),
                    )
                  else
                    ..._transactions.take(10).map((t) => _buildTransactionCard(t)),
                ],
              ),
            ),
    );
  }

  Widget _buildHeaderCard() {
    final theme = Theme.of(context);
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            CircleAvatar(
              radius: 40,
              backgroundColor: theme.colorScheme.onPrimary.withValues(alpha: 0.2),
              child: Text(
                widget.userName.isNotEmpty ? widget.userName[0].toUpperCase() : '?',
                style: TextStyle(fontSize: 32, color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.userName,
              style: TextStyle(
                color: theme.colorScheme.onPrimary,
                fontSize: 22,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              widget.userRole,
              style: TextStyle(
                color: theme.colorScheme.onPrimary.withValues(alpha: 0.7),
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 20),
            Divider(color: theme.colorScheme.onPrimary.withValues(alpha: 0.2)),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildHeaderStat('Month Sales', '₹${_currentMonthSales.toStringAsFixed(0)}', theme),
                _buildHeaderStat('Target', '₹${_targetAmount.toStringAsFixed(0)}', theme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderStat(String label, String value, ThemeData theme) {
    return Column(
      children: [
        Text(value, style: TextStyle(color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold, fontSize: 16)),
        Text(label, style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.7), fontSize: 11)),
      ],
    );
  }

  Widget _buildStatsGrid() {
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 1.2,
      children: [
        _buildStatItem('Lifetime Sales', '₹${_totalSales.toStringAsFixed(0)}', Icons.shopping_bag, Colors.green),
        _buildStatItem('Total Earned', '₹${_totalEarned.toStringAsFixed(0)}', Icons.payments, Colors.orange),
        _buildStatItem('Active Quotes', '$_activeQuotes', Icons.description, Colors.blue),
        _buildStatItem('Completion', '${_targetAmount > 0 ? ((_currentMonthSales / _targetAmount) * 100).toStringAsFixed(1) : "0"}%', Icons.pie_chart, Colors.purple),
      ],
    );
  }

  Widget _buildStatItem(String label, String value, IconData icon, Color color) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard(SaleTransaction t) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: t.status == 'Completed' ? Colors.green.shade100 : Colors.orange.shade100,
          child: Icon(
            t.status == 'Completed' ? Icons.check_circle : Icons.pending,
            color: t.status == 'Completed' ? Colors.green : Colors.orange,
            size: 20,
          ),
        ),
        title: Text('₹${t.amount.toStringAsFixed(2)}'),
        subtitle: Text('${t.customerName ?? "Walk-in"} • ${t.paymentMethod}'),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              t.status,
              style: TextStyle(
                color: t.status == 'Completed' ? Colors.green : Colors.orange,
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
            Text(
              '${t.createdAt.day}/${t.createdAt.month}/${t.createdAt.year}',
              style: const TextStyle(fontSize: 10, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}
