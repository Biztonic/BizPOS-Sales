import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../models/quotation.dart';
import '../../models/sale_transaction.dart';
import '../../providers/sales_provider.dart';
import '../../providers/commission_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/system_config_provider.dart';
import '../../services/pdf_service.dart';
import 'package:flutter/services.dart';


class InvoiceConversionScreen extends StatefulWidget {
  final Quotation quotation;

  const InvoiceConversionScreen({super.key, required this.quotation});

  @override
  State<InvoiceConversionScreen> createState() => _InvoiceConversionScreenState();
}

class _InvoiceConversionScreenState extends State<InvoiceConversionScreen> {
  late List<SaleItem> _items;
  final _amountPaidController = TextEditingController();
  final _discountController = TextEditingController(text: '0');
  String _paymentMethod = 'UPI'; // Default to UPI for modern feel
  bool _isConverting = false;

  @override
  void initState() {
    super.initState();
    // Copy items so they can be modified if needed
    _items = List.from(widget.quotation.items);
    _amountPaidController.text = widget.quotation.totalAmount.toString();
  }

  double get _itemsTotal => _items.fold(0.0, (sum, item) => sum + item.total);
  double get _discount => double.tryParse(_discountController.text) ?? 0.0;
  double get _currentTotal => (_itemsTotal - _discount).clamp(0.0, double.infinity);

  Future<void> _convertQuotation() async {
    setState(() => _isConverting = true);
    final salesProvider = context.read<SalesProvider>();

    final amountPaid = double.tryParse(_amountPaidController.text) ?? 0.0;
    
    // Check if it has hardware items to define saleType
    // This is a simplified check
    String saleType = 'SOFTWARE_SUBSCRIPTION';
    if (_items.any((i) => i.productName.toLowerCase().contains('hardware') || i.productName.toLowerCase().contains('device'))) {
       saleType = _items.any((i) => i.productName.toLowerCase().contains('subscription')) ? 'MIXED' : 'HARDWARE';
    }

    final targetMonth = DateFormat('yyyy-MM').format(DateTime.now());

    final result = await salesProvider.convertQuotationToInvoice(
      quotation: widget.quotation,
      finalItems: _items,
      finalAmount: _currentTotal,
      amountPaid: amountPaid,
      paymentMethod: _paymentMethod,
      targetMonth: targetMonth,
      saleType: saleType,
    );

    final transactionId = result?['transactionId'];
    final isNewOnboarded = result?['isNewCustomerOnboarded'] ?? false;

    setState(() => _isConverting = false);

    if (transactionId != null && mounted) {
      // Record Commission
      final commissionProvider = context.read<CommissionProvider>();
      await commissionProvider.recordSaleCommission(
        transactionId: transactionId,
        agentId: widget.quotation.agentId,
        agentName: widget.quotation.agentName,
        storeId: widget.quotation.storeId,
        saleAmount: amountPaid,
        customerId: widget.quotation.customerId, // Pass customer ID for permanent linkage lookup
      );

      // Force refresh data
      final auth = context.read<SalesAuthProvider>();
      commissionProvider.startListeningToProgress(
        agentId: widget.quotation.agentId,
        role: auth.userRole,
        isPermanentDirector: auth.isPermanentDirector,
      );

      // Show success dialog with share option
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 32),
                const SizedBox(width: 12),
                Text(isNewOnboarded ? 'Success & Onboarded' : 'Invoice Created'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Quotation has been successfully converted to an invoice.'),
                if (isNewOnboarded)
                  Container(
                    margin: const EdgeInsets.only(top: 16),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.person_add, color: Colors.blue.shade700),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'New customer account pre-created in BizPOS! Invite them to set their password.',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
                Text('Transaction ID: $transactionId', style: const TextStyle(fontSize: 10, color: Colors.grey)),
                const SizedBox(height: 8),
                Text('Amount Paid: ₹${amountPaid.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            actions: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (isNewOnboarded)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blue.shade600,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: () {
                          final msg = "Welcome to BizPOS, ${widget.quotation.customerName}!\n\n"
                              "Your account is ready. Please log in with your email (${widget.quotation.customerEmail}) "
                              "and set your initial password to get started.\n\n"
                              "Download BizPOS from the Play Store/App Store today!";
                          Clipboard.setData(ClipboardData(text: msg));
                          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Welcome message copied to clipboard!')));
                        },
                        icon: const Icon(Icons.send),
                        label: const Text('SHARE WELCOME LINK'),
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.deepPurple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      onPressed: () async {
                        // Construct local transaction for PDF
                          final transObj = SaleTransaction(
                            id: transactionId,
                            agentId: widget.quotation.agentId,
                            agentName: widget.quotation.agentName,
                            agentTitle: widget.quotation.agentTitle,
                            storeId: widget.quotation.storeId,
                            customerId: widget.quotation.customerId,
                          customerName: widget.quotation.customerName,
                          amount: _currentTotal,
                          amountPaid: amountPaid,
                          paymentMethod: _paymentMethod,
                          targetMonth: targetMonth,
                          items: _items,
                          notes: 'Converted from quotation ${widget.quotation.id}',
                        );
                        await PdfService.generateAndShareInvoice(transObj);
                      },
                      icon: const Icon(Icons.share),
                      label: const Text('SHARE INVOICE'),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      Navigator.pop(context); // Pop dialog
                      Navigator.pop(context); // Pop screen
                    },
                    child: const Text('DONE'),
                  ),
                ],
              ),
            ],
          ),
        );
      }


    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(salesProvider.error ?? 'Failed to create invoice')));
      }
    }
  }

  void _updateItemQuantity(int index, int delta) {
    setState(() {
      final item = _items[index];
      final newQty = (item.quantity + delta).clamp(1, 999);
      _items[index] = SaleItem(
        productId: item.productId,
        productName: item.productName,
        price: item.price,
        quantity: newQty,
        warrantyMonths: item.warrantyMonths,
      );
      _amountPaidController.text = _currentTotal.toString();
    });
  }

  void _removeItem(int index) {
    if (_items.length <= 1) {
       ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('At least one item is required')));
       return;
    }
    setState(() {
      _items.removeAt(index);
      _amountPaidController.text = _currentTotal.toString();
    });
  }

  double _calculateEstimatedCommission(CommissionProvider commission) {
    final configProvider = context.read<SystemConfigProvider>();
    final double target = commission.targetAmount;
    final double current = commission.currentMonthSales;
    final double saleAmount = _currentTotal;
    final double nextTotal = current + saleAmount;
    final double baseRate = configProvider.baseCommissionRate / 100;
    final double excessRate = configProvider.excessCommissionRate / 100;
    final double baseSalary = configProvider.baseSalaryAtTarget;

    // Logic from CommissionProvider
    double currentEarnings = 0;
    if (current < target) {
      currentEarnings = current * baseRate;
    } else {
      currentEarnings = baseSalary + (current - target) * excessRate;
    }

    double nextEarnings = 0;
    if (nextTotal < target) {
      nextEarnings = nextTotal * baseRate;
    } else {
      nextEarnings = baseSalary + (nextTotal - target) * excessRate;
    }

    return nextEarnings - currentEarnings;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Convert to Invoice')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Customer: ${widget.quotation.customerName}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 8),
                  Text('Quotation Ref: ${widget.quotation.id.isEmpty ? "DRAFT" : widget.quotation.id}'),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('Finalize Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const Text('You can adjust quantities before finalizing.', style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            ..._items.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  title: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Text('₹${item.price} x ${item.quantity}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
                        onPressed: () => _updateItemQuantity(index, -1),
                      ),
                      Text('${item.quantity}', style: const TextStyle(fontWeight: FontWeight.bold)),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline, color: Colors.green),
                        onPressed: () => _updateItemQuantity(index, 1),
                      ),
                      const SizedBox(width: 8),
                      Text('₹${item.total.toStringAsFixed(0)}', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.deepPurple)),
                      IconButton(
                        icon: const Icon(Icons.delete_outline, color: Colors.grey),
                        onPressed: () => _removeItem(index),
                      ),
                    ],
                  ),
                ),
              );
            }),
            const Divider(height: 32, thickness: 2),
            
            // Commission Preview
            Consumer<CommissionProvider>(
              builder: (context, commission, _) {
                final estComm = _calculateEstimatedCommission(commission);
                final willHitTarget = commission.currentMonthSales < commission.targetAmount && 
                                    (commission.currentMonthSales + _currentTotal) >= commission.targetAmount;

                return Container(
                  padding: const EdgeInsets.all(16),
                  margin: const EdgeInsets.only(bottom: 24),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('Estimated Commission', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.green)),
                          Text('+ ₹${estComm.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.green)),
                        ],
                      ),
                      if (willHitTarget)
                        const Padding(
                          padding: EdgeInsets.only(top: 8),
                          child: Text('🚀 This sale will hit your 2L target! Bonus applied.', style: TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                );
              }
            ),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Items Total', style: TextStyle(color: Colors.grey)),
                Text('₹${_itemsTotal.toStringAsFixed(2)}', style: const TextStyle(color: Colors.grey)),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Discount / Adjustment', style: TextStyle(color: Colors.red)),
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: _discountController,
                    textAlign: TextAlign.end,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {
                      _amountPaidController.text = _currentTotal.toString();
                    }),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixText: '- ₹',
                      border: InputBorder.none,
                    ),
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Net Invoice Total', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                Text('₹${_currentTotal.toStringAsFixed(2)}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.deepPurple)),
              ],
            ),
            const SizedBox(height: 32),
            const Text('Payment Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            
            // Payment Method Selection
            const Text('Payment Method', style: TextStyle(fontSize: 14, color: Colors.grey)),
            const SizedBox(height: 8),
            Row(
              children: [
                _buildPaymentOption('UPI', Icons.qr_code),
                _buildPaymentOption('Cash', Icons.money),
                _buildPaymentOption('Card', Icons.credit_card),
                _buildPaymentOption('Bank', Icons.account_balance),
              ],
            ),
            const SizedBox(height: 16),
            
            TextField(
              controller: _amountPaidController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Amount Paid Now',
                border: OutlineInputBorder(),
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.receipt_long),
                label: _isConverting 
                  ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm Invoice & Record Payment', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _isConverting ? null : _convertQuotation,
              ),
            )
          ],
        ),
      ),
      ),
      ),
    );
  }

  Widget _buildPaymentOption(String method, IconData icon) {
    final isSelected = _paymentMethod == method;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _paymentMethod = method),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? Colors.deepPurple : Colors.white,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: isSelected ? Colors.deepPurple : Colors.grey.shade300),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? Colors.white : Colors.grey),
              const SizedBox(height: 4),
              Text(method, style: TextStyle(color: isSelected ? Colors.white : Colors.black, fontSize: 12, fontWeight: isSelected ? FontWeight.bold : FontWeight.normal)),
            ],
          ),
        ),
      ),
    );
  }
}
