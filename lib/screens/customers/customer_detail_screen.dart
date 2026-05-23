import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/customer.dart';
import '../../models/quotation.dart';
import '../../models/sale_transaction.dart';
import '../../providers/customer_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/auth_provider.dart';
import '../sales_flow/invoice_conversion_screen.dart';
import '../sales_flow/catalog_browser_screen.dart';

class CustomerDetailScreen extends StatefulWidget {
  final Customer customer;

  const CustomerDetailScreen({Key? key, required this.customer}) : super(key: key);

  @override
  _CustomerDetailScreenState createState() => _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends State<CustomerDetailScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Quotation> _quotations = [];
  List<SaleTransaction> _transactions = [];
  bool _isLoading = true;
  late Customer _currentCustomer;

  @override
  void initState() {
    super.initState();
    _currentCustomer = widget.customer;
    _tabController = TabController(length: 3, vsync: this);
    _fetchData();
  }

  Future<void> _fetchData() async {
    setState(() => _isLoading = true);
    final salesProvider = Provider.of<SalesProvider>(context, listen: false);
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    
    try {
      // Refresh customer data to get latest warranties
      final refreshedCustomer = await customerProvider.getCustomerById(_currentCustomer.id);
      
      final results = await Future.wait([
        salesProvider.fetchQuotationsByCustomer(_currentCustomer.id),
        salesProvider.fetchTransactionsByCustomer(_currentCustomer.id),
      ]);

      if (mounted) {
        setState(() {
          if (refreshedCustomer != null) {
            _currentCustomer = refreshedCustomer;
          }
          _quotations = results[0] as List<Quotation>;
          _transactions = results[1] as List<SaleTransaction>;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading customer data: $e')),
        );
      }
    }
  }

  double get _totalBilled => _transactions.fold(0.0, (sum, t) => sum + t.amount);
  double get _totalPaid => _transactions.fold(0.0, (sum, t) => sum + t.amountPaid);
  double get _balance => _totalBilled - _totalPaid;

  Future<void> _updateStatus(String newStatus) async {
    final updatedCustomer = _currentCustomer.copyWith(status: newStatus);
    
    final success = await Provider.of<CustomerProvider>(context, listen: false)
        .updateCustomer(updatedCustomer);
    
    if (success && mounted) {
      setState(() {
        _currentCustomer = updatedCustomer;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Customer status updated to $newStatus')),
      );
    }
  }

  Future<void> _createQuotation() async {
    // If they are a LEAD, move them to PROSPECT automatically when creating a quotation
    if (_currentCustomer.status == 'LEAD') {
      await _updateStatus('PROSPECT');
    }

    if (!mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => CatalogBrowserScreen(customer: _currentCustomer),
      ),
    ).then((_) => _fetchData());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createQuotation,
        label: const Text('Create Quotation'),
        icon: const Icon(Icons.add_shopping_cart),
        backgroundColor: colorScheme.primary,
        foregroundColor: colorScheme.onPrimary,
      ),
      body: CustomScrollView(
        slivers: [
          _buildAppBar(colorScheme),
          SliverToBoxAdapter(
            child: Column(
              children: [
                _buildCustomerInfo(colorScheme),
                _buildSummaryCards(colorScheme),
                _buildTabs(colorScheme),
              ],
            ),
          ),
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildQuotationsList(colorScheme),
                _buildTransactionsList(colorScheme),
                _buildWarrantiesList(colorScheme),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBar(ColorScheme colorScheme) {
    return SliverAppBar(
      expandedHeight: 120.0,
      floating: false,
      pinned: true,
      backgroundColor: colorScheme.primary,
      foregroundColor: colorScheme.onPrimary,
      flexibleSpace: FlexibleSpaceBar(
        title: Text(
          _currentCustomer.name,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        background: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [colorScheme.primary, colorScheme.primary.withValues(alpha: 0.8)],
            ),
          ),
        ),
      ),
      actions: [
        if (context.watch<SalesAuthProvider>().isTeamLeader)
          IconButton(
            icon: const Icon(Icons.swap_horiz),
            tooltip: 'Transfer Lead',
            onPressed: () => _showTransferDialog(),
          ),
        IconButton(
          icon: const Icon(Icons.edit),
          onPressed: () {
            // Edit customer logic
          },
        ),
      ],
    );
  }

  void _showTransferDialog() {
    final customerProvider = Provider.of<CustomerProvider>(context, listen: false);
    final auth = Provider.of<SalesAuthProvider>(context, listen: false);
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer / Assign Lead'),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Transferring lead: ${_currentCustomer.name}'),
              const SizedBox(height: 16),
              FutureBuilder<void>(
                future: customerProvider.fetchTeamMembers(auth.userId, auth.userRole),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  
                  final members = customerProvider.teamMembers;
                  if (members.isEmpty) {
                    return const Center(child: Text('No eligible team members found to transfer.'));
                  }

                  return Flexible(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: members.length,
                      itemBuilder: (context, index) {
                        final member = members[index];
                        return ListTile(
                          leading: const CircleAvatar(child: Icon(Icons.person)),
                          title: Text(member['name'] ?? 'Unknown'),
                          subtitle: Text(member['role'] ?? ''),
                          onTap: () async {
                            final success = await customerProvider.transferCustomer(
                              _currentCustomer.id,
                              member['id'],
                              member['name']
                            );
                            if (success && mounted) {
                              Navigator.pop(context);
                              setState(() {
                                _currentCustomer = _currentCustomer.copyWith(
                                  assignedTo: member['id'],
                                  assignedToName: member['name'],
                                );
                              });
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Lead transferred successfully')),
                              );
                            }
                          },
                        );
                      },
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ],
      ),
    );
  }

  Widget _buildCustomerInfo(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildPipelineIndicator(colorScheme),
              const SizedBox(height: 24),
              _infoRow(Icons.phone, _currentCustomer.phone, colorScheme),
              const SizedBox(height: 8),
              _infoRow(Icons.email, _currentCustomer.email ?? 'No email', colorScheme),
              const SizedBox(height: 8),
              _infoRow(Icons.location_on, _currentCustomer.address ?? 'No address', colorScheme),
              const Divider(height: 24),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Current Stage: ${_currentCustomer.status}',
                    style: TextStyle(
                      color: colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_currentCustomer.status != 'ACTIVE')
                    ElevatedButton(
                      onPressed: () {
                        if (_currentCustomer.status == 'LEAD') {
                          _updateStatus('PROSPECT');
                        } else if (_currentCustomer.status == 'PROSPECT') {
                          _updateStatus('ACTIVE');
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colorScheme.primaryContainer,
                        foregroundColor: colorScheme.onPrimaryContainer,
                      ),
                      child: Text(_currentCustomer.status == 'LEAD' ? 'Move to Prospect' : 'Mark as Active'),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPipelineIndicator(ColorScheme colorScheme) {
    final stages = ['LEAD', 'PROSPECT', 'ACTIVE'];
    final currentIdx = stages.indexOf(_currentCustomer.status);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pipeline Stage',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: List.generate(stages.length, (index) {
            final isActive = index <= currentIdx;
            final isCurrent = index == currentIdx;
            
            return Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      children: [
                        Container(
                          height: 8,
                          decoration: BoxDecoration(
                            color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stages[index],
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal,
                            color: isCurrent ? colorScheme.primary : colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (index < stages.length - 1)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Icon(
                        Icons.chevron_right,
                        size: 16,
                        color: isActive ? colorScheme.primary : colorScheme.outlineVariant,
                      ),
                    ),
                ],
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _infoRow(IconData icon, String text, ColorScheme colorScheme) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 12),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 14))),
      ],
    );
  }

  Widget _buildSummaryCards(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Row(
        children: [
          _summaryCard('Billed', _totalBilled, Colors.blue, colorScheme),
          const SizedBox(width: 12),
          _summaryCard('Paid', _totalPaid, Colors.green, colorScheme),
          const SizedBox(width: 12),
          _summaryCard('Balance', _balance, Colors.red, colorScheme),
        ],
      ),
    );
  }

  Widget _summaryCard(String title, double amount, Color accentColor, ColorScheme colorScheme) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(color: colorScheme.outline, fontSize: 12)),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                '₹${NumberFormat('#,##,###').format(amount)}',
                style: TextStyle(
                  color: accentColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabs(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(top: 16),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: TabBar(
        controller: _tabController,
        labelColor: colorScheme.primary,
        unselectedLabelColor: colorScheme.outline,
        indicatorColor: colorScheme.primary,
        tabs: const [
          Tab(text: 'Quotations'),
          Tab(text: 'Transactions'),
          Tab(text: 'Warranties'),
        ],
      ),
    );
  }

  Widget _buildWarrantiesList(ColorScheme colorScheme) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    final warranties = _currentCustomer.warranties;

    if (warranties.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.security_outlined, size: 64, color: colorScheme.outline.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text('No active warranties found', style: TextStyle(color: colorScheme.outline, fontSize: 16)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: warranties.length,
      itemBuilder: (context, index) {
        final warranty = warranties[index];
        final remainingDays = warranty.remainingDays;
        final isExpired = remainingDays <= 0;
        final theme = Theme.of(context);

        return Container(
          margin: const EdgeInsets.only(bottom: 16),
          decoration: BoxDecoration(
            color: theme.cardColor,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.05),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
            border: Border.all(
              color: (isExpired ? Colors.red : Colors.green).withValues(alpha: 0.1),
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            warranty.productName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Purchase Date: ${DateFormat('dd MMM yyyy').format(warranty.purchaseDate)}',
                            style: TextStyle(color: colorScheme.outline, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (isExpired ? Colors.red : Colors.green).withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        isExpired ? 'EXPIRED' : 'ACTIVE',
                        style: TextStyle(
                          color: isExpired ? Colors.red : Colors.green,
                          fontWeight: FontWeight.bold,
                          fontSize: 10,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    _buildWarrantyStat(
                      context,
                      'Expiry Date',
                      DateFormat('dd MMM yyyy').format(warranty.expiryDate),
                      Icons.event_available,
                    ),
                    const SizedBox(width: 24),
                    _buildWarrantyStat(
                      context,
                      'Validity',
                      isExpired ? 'Expired' : '$remainingDays Days left',
                      Icons.timer_outlined,
                      color: isExpired ? Colors.red : Colors.green,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWarrantyStat(BuildContext context, String label, String value, IconData icon, {Color? color}) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Row(
      children: [
        Icon(icon, size: 16, color: color ?? colorScheme.primary),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: TextStyle(color: colorScheme.outline, fontSize: 10)),
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: color,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuotationsList(ColorScheme colorScheme) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_quotations.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description_outlined, size: 48, color: colorScheme.outline),
            const SizedBox(height: 16),
            const Text('No quotations found'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _quotations.length,
      itemBuilder: (context, index) {
        final q = _quotations[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('Quotation #${q.id.substring(0, 8)}'),
            subtitle: Text(DateFormat('dd MMM yyyy').format(q.createdAt)),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${NumberFormat('#,##,###').format(q.totalAmount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  q.status,
                  style: TextStyle(
                    fontSize: 10,
                    color: q.status == 'CONVERTED' ? Colors.green : Colors.blue,
                  ),
                ),
              ],
            ),
            onTap: () {
              if (q.status != 'CONVERTED') {
                 Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InvoiceConversionScreen(quotation: q),
                  ),
                ).then((_) => _fetchData());
              }
            },
          ),
        );
      },
    );
  }

  void _showPaymentDialog(SaleTransaction transaction) {
    final remaining = transaction.amount - transaction.amountPaid;
    final controller = TextEditingController(text: remaining.toString());

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Record Payment'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Invoice: #${transaction.id.substring(0, 8)}'),
            Text('Total: ₹${transaction.amount.toStringAsFixed(2)}'),
            Text('Paid: ₹${transaction.amountPaid.toStringAsFixed(2)}'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Payment Amount',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              final amount = double.tryParse(controller.text) ?? 0.0;
              if (amount <= 0) return;
              
              final success = await Provider.of<SalesProvider>(context, listen: false)
                  .addPayment(transaction.id, amount);
              
              if (success && mounted) {
                Navigator.pop(context);
                _fetchData();
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Payment recorded successfully')),
                );
              }
            },
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  Widget _buildTransactionsList(ColorScheme colorScheme) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 48, color: colorScheme.outline),
            const SizedBox(height: 16),
            const Text('No transactions found'),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _transactions.length,
      itemBuilder: (context, index) {
        final t = _transactions[index];
        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: ListTile(
            title: Text('Invoice #${t.id.substring(0, 8)}'),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(DateFormat('dd MMM yyyy').format(t.createdAt)),
                if (t.paymentStatus != 'PAID')
                  Text(
                    'Balance: ₹${NumberFormat('#,##,###').format(t.amount - t.amountPaid)}',
                    style: const TextStyle(color: Colors.red, fontSize: 12),
                  ),
              ],
            ),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '₹${NumberFormat('#,##,###').format(t.amount)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _getPaymentStatusColor(t.paymentStatus).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    t.paymentStatus,
                    style: TextStyle(
                      fontSize: 10,
                      color: _getPaymentStatusColor(t.paymentStatus),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            onTap: () {
              if (t.paymentStatus != 'PAID') {
                _showPaymentDialog(t);
              }
            },
          ),
        );
      },
    );
  }

  Color _getPaymentStatusColor(String status) {
    switch (status) {
      case 'PAID': return Colors.green;
      case 'PARTIAL': return Colors.orange;
      case 'PENDING': return Colors.red;
      default: return Colors.grey;
    }
  }
}
