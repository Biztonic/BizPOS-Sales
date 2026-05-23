import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/account_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/expense.dart';

class ExpenseApprovalsScreen extends StatefulWidget {
  const ExpenseApprovalsScreen({super.key});
  @override
  State<ExpenseApprovalsScreen> createState() => _ExpenseApprovalsScreenState();
}

class _ExpenseApprovalsScreenState extends State<ExpenseApprovalsScreen> {
  final _fmt = NumberFormat.currency(symbol: '₹', decimalDigits: 0);

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final auth = context.read<SalesAuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Expense Approvals'),
      ),
      body: account.pendingApprovals.isEmpty
          ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.check_circle_outline, size: 80, color: Colors.green.withValues(alpha: 0.5)),
              const SizedBox(height: 24),
              Text('No pending approvals', style: theme.textTheme.titleLarge?.copyWith(color: theme.disabledColor)),
              const SizedBox(height: 8),
              Text('You are all caught up!', style: theme.textTheme.bodyMedium?.copyWith(color: theme.disabledColor)),
            ]))
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: account.pendingApprovals.length,
              itemBuilder: (context, index) {
                final expense = account.pendingApprovals[index];
                return _buildApprovalCard(expense, auth, account, theme);
              },
            ),
    );
  }

  Widget _buildApprovalCard(Expense expense, SalesAuthProvider auth, AccountProvider account, ThemeData theme) {
    final approvedCount = expense.approvals.where((a) => a.decision == 'Approved').length;

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.1),
              child: Text(
                expense.userName.isNotEmpty ? expense.userName[0].toUpperCase() : '?',
                style: TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(expense.userName, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              Text(expense.userRole, style: theme.textTheme.bodySmall),
            ])),
            Text(_fmt.format(expense.amount), style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: Colors.red)),
          ]),
          const Divider(height: 32),
          Text(expense.title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(expense.description, style: theme.textTheme.bodyMedium),
          const SizedBox(height: 16),
          Row(children: [
            Icon(Icons.calendar_today, size: 14, color: theme.disabledColor),
            const SizedBox(width: 6),
            Text(DateFormat('dd MMM yyyy').format(expense.createdAt), style: theme.textTheme.bodySmall),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: theme.colorScheme.secondary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '$approvedCount/${expense.requiredApprovals} approvals',
                style: TextStyle(color: theme.colorScheme.secondary, fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
          ]),
          if (expense.approvals.isNotEmpty) ...[
            const SizedBox(height: 16),
            Wrap(spacing: 8, runSpacing: 8, children: expense.approvals.map((a) => Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.dividerColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(a.decision == 'Approved' ? Icons.check_circle : Icons.cancel, size: 14, color: a.decision == 'Approved' ? Colors.green : Colors.red),
                const SizedBox(width: 6),
                Text('${a.approverName} (${a.approverRole})', style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
              ]),
            )).toList()),
          ],
          const SizedBox(height: 24),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: account.isLoading ? null : () => _handleAction(expense, auth, account, 'Rejected'),
                icon: const Icon(Icons.close),
                label: const Text('Reject'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: ElevatedButton.icon(
                onPressed: account.isLoading ? null : () => _handleAction(expense, auth, account, 'Approved'),
                icon: const Icon(Icons.check),
                label: const Text('Approve'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  Future<void> _handleAction(Expense expense, SalesAuthProvider auth, AccountProvider account, String decision) async {
    final theme = Theme.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$decision Expense?'),
        content: Text('Are you sure you want to ${decision.toLowerCase()} "${expense.title}" for ${_fmt.format(expense.amount)}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: decision == 'Approved' ? Colors.green : Colors.red),
            child: Text(decision, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    final success = await account.actOnExpense(
      expenseId: expense.id,
      approverId: auth.userId,
      approverName: auth.userName,
      approverRole: auth.userRole,
      decision: decision,
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(success ? 'Expense $decision successfully!' : account.error ?? 'Failed'),
      backgroundColor: success ? Colors.green : Colors.red,
      behavior: SnackBarBehavior.floating,
    ));
  }
}
