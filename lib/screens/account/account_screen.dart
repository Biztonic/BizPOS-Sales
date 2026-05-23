import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/expense.dart';
import 'add_expense_screen.dart';
import 'expense_approvals_screen.dart';

class AccountScreen extends StatefulWidget {
  const AccountScreen({super.key});
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _fmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _loadData() {
    final auth = context.read<SalesAuthProvider>();
    final account = context.read<AccountProvider>();
    account.fetchTotalIncome(auth.userId);
    account.startListeningToMyExpenses(auth.userId);
    account.startListeningToPendingApprovals(
      userId: auth.userId, 
      role: auth.userRole,
      isPermanentDirector: auth.isPermanentDirector,
    );
  }

  @override
  void dispose() { _tabController.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<SalesAuthProvider>();
    final account = context.watch<AccountProvider>();
    final showApprovals = auth.userRole == 'Team Leader' || auth.userRole == 'Director' || auth.isSuperAdmin;

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('My Account'),
        backgroundColor: theme.appBarTheme.backgroundColor,
        foregroundColor: theme.appBarTheme.foregroundColor,
        actions: [
          if (showApprovals)
            Stack(
              children: [
                IconButton(
                  icon: const Icon(Icons.approval),
                  tooltip: 'Pending Approvals',
                  onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const ExpenseApprovalsScreen())),
                ),
                if (account.pendingApprovals.isNotEmpty)
                  Positioned(right: 6, top: 6, child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: const BoxDecoration(color: Colors.red, shape: BoxShape.circle),
                    child: Text('${account.pendingApprovals.length}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold)),
                  )),
              ],
            ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: isDark ? theme.colorScheme.primary : Colors.white,
          labelColor: isDark ? theme.colorScheme.primary : Colors.white,
          unselectedLabelColor: isDark ? Colors.white60 : Colors.white70,
          tabs: const [Tab(text: 'Overview'), Tab(text: 'My Expenses')],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const AddExpenseScreen())),
        icon: const Icon(Icons.add),
        label: const Text('Add Expense'),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(account, theme),
          _buildExpensesTab(account, theme),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(AccountProvider account, ThemeData theme) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Summary Cards
        Card(
          elevation: 4,
          clipBehavior: Clip.antiAlias,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.primary.withValues(alpha: 0.8)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(children: [
              Text('Net Balance', style: TextStyle(color: theme.colorScheme.onPrimary.withValues(alpha: 0.7), fontSize: 14)),
              const SizedBox(height: 8),
              Text(_fmt.format(account.netBalance), style: TextStyle(color: theme.colorScheme.onPrimary, fontSize: 32, fontWeight: FontWeight.bold)),
            ]),
          ),
        ),
        const SizedBox(height: 16),
        Row(children: [
          Expanded(child: _summaryCard('Total Income', account.totalIncome, Colors.green, Icons.trending_up, theme)),
          const SizedBox(width: 12),
          Expanded(child: _summaryCard('Total Expenses', account.totalExpenses, Colors.red, Icons.trending_down, theme)),
        ]),
        const SizedBox(height: 24),
        Text('Recent Expenses', style: theme.textTheme.titleLarge),
        const SizedBox(height: 12),
        if (account.myExpenses.isEmpty)
          Card(child: Padding(padding: const EdgeInsets.all(32), child: Center(child: Text('No expenses recorded yet.', style: theme.textTheme.bodyMedium))))
        else
          ...account.myExpenses.take(5).map((e) => _expenseTile(e, theme)),
      ],
    );
  }

  Widget _summaryCard(String label, double value, Color color, IconData icon, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 12),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6))),
          const SizedBox(height: 4),
          Text(_fmt.format(value), style: theme.textTheme.titleLarge?.copyWith(color: color, fontSize: 18)),
        ]),
      ),
    );
  }

  Widget _buildExpensesTab(AccountProvider account, ThemeData theme) {
    if (account.myExpenses.isEmpty) {
      return Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.receipt_long, size: 64, color: theme.disabledColor),
        const SizedBox(height: 16),
        Text('No expenses yet', style: theme.textTheme.titleMedium?.copyWith(color: theme.disabledColor)),
      ]));
    }
    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: account.myExpenses.length,
      itemBuilder: (context, index) => _expenseTile(account.myExpenses[index], theme),
    );
  }

  Widget _expenseTile(Expense expense, ThemeData theme) {
    Color statusColor;
    IconData statusIcon;
    switch (expense.status) {
      case 'Approved': statusColor = Colors.green; statusIcon = Icons.check_circle; break;
      case 'Rejected': statusColor = Colors.red; statusIcon = Icons.cancel; break;
      case 'PartiallyApproved': statusColor = Colors.orange; statusIcon = Icons.hourglass_bottom; break;
      default: statusColor = theme.colorScheme.primary; statusIcon = Icons.pending; break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: CircleAvatar(
          backgroundColor: statusColor.withValues(alpha: 0.1),
          child: Icon(statusIcon, color: statusColor, size: 20),
        ),
        title: Text(expense.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 4),
          Text(expense.description, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
          const SizedBox(height: 8),
          Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(expense.status, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ),
            const SizedBox(width: 8),
            Text('${expense.approvals.where((a) => a.decision == 'Approved').length}/${expense.requiredApprovals} approvals', style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
          ]),
        ]),
        trailing: Text(_fmt.format(expense.amount), style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: Colors.red)),
        onTap: () => _showExpenseDetail(expense, theme),
      ),
    );
  }

  void _showExpenseDetail(Expense expense, ThemeData theme) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => DraggableScrollableSheet(
        initialChildSize: 0.6, minChildSize: 0.4, maxChildSize: 0.9, expand: false,
        builder: (_, controller) => ListView(controller: controller, padding: const EdgeInsets.all(24), children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: theme.dividerColor, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 24),
          Text(expense.title, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Text(expense.description, style: theme.textTheme.bodyLarge),
          const SizedBox(height: 24),
          _detailRow('Amount', _fmt.format(expense.amount), theme, valueColor: Colors.red),
          _detailRow('Status', expense.status, theme, valueColor: expense.status == 'Approved' ? Colors.green : expense.status == 'Rejected' ? Colors.red : Colors.orange),
          _detailRow('Date', DateFormat('dd MMM yyyy, hh:mm a').format(expense.createdAt), theme),
          const Divider(height: 48),
          Text('Approval Trail', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 16),
          if (expense.approvals.isEmpty)
            Text('No approvals yet.', style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor))
          else
            ...expense.approvals.map((a) => Container(
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: ListTile(
                leading: Icon(a.decision == 'Approved' ? Icons.check_circle : Icons.cancel, color: a.decision == 'Approved' ? Colors.green : Colors.red),
                title: Text(a.approverName, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Text('${a.approverRole} • ${DateFormat('dd MMM yyyy').format(a.approvedAt)}', style: theme.textTheme.bodySmall),
                trailing: Text(a.decision, style: TextStyle(color: a.decision == 'Approved' ? Colors.green : Colors.red, fontWeight: FontWeight.bold, fontSize: 12)),
              ),
            )),
        ]),
      ),
    );
  }

  Widget _detailRow(String label, String value, ThemeData theme, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(color: theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.6))),
        Text(value, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.bold, color: valueColor)),
      ]),
    );
  }
}
