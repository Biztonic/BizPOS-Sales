import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';
import '../../models/sale_transaction.dart';
import '../../models/quotation.dart';
import '../../providers/sales_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customer_provider.dart';
import '../../services/pdf_service.dart';
import '../customers/customer_list_screen.dart';
import '../../models/customer.dart';
import 'invoice_conversion_screen.dart';

class QuotationGeneratorScreen extends StatefulWidget {
  final List<SaleItem> cartItems;
  final Quotation? quotation;
  final Customer? initialCustomer;

  const QuotationGeneratorScreen({
    super.key, 
    required this.cartItems, 
    this.quotation,
    this.initialCustomer,
  });

  @override
  State<QuotationGeneratorScreen> createState() => _QuotationGeneratorScreenState();
}

class _QuotationGeneratorScreenState extends State<QuotationGeneratorScreen> {
  final _customerNameController = TextEditingController();
  final _customerPhoneController = TextEditingController();
  final _notesController = TextEditingController();
  bool _isGenerating = false;
  Customer? _selectedCustomer;

  @override
  void initState() {
    super.initState();
    if (widget.quotation != null) {
      _customerNameController.text = widget.quotation!.customerName ?? '';
      _customerPhoneController.text = widget.quotation!.customerPhone ?? '';
      _notesController.text = widget.quotation!.notes ?? '';
    }
    
    if (widget.initialCustomer != null) {
      _selectedCustomer = widget.initialCustomer;
      _customerNameController.text = widget.initialCustomer!.name;
      _customerPhoneController.text = widget.initialCustomer!.phone;
    }
  }

  void _pickCustomer() async {
    final customer = await Navigator.push<Customer>(
      context,
      MaterialPageRoute(builder: (context) => const CustomerListScreen(pickMode: true)),
    );

    if (customer != null) {
      setState(() {
        _selectedCustomer = customer;
        _customerNameController.text = customer.name;
        _customerPhoneController.text = customer.phone;
      });
    }
  }

  Future<void> _generateQuotation() async {
    if (_customerNameController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enter a customer name')));
      return;
    }

    setState(() => _isGenerating = true);

    final salesProvider = context.read<SalesProvider>();
    final authProvider = context.read<SalesAuthProvider>();
    final user = authProvider.user;

    if (user == null) {
      setState(() => _isGenerating = false);
      return;
    }

    final totalAmount = widget.cartItems.fold(0.0, (sum, item) => sum + item.total);

    final quotation = Quotation(
      id: widget.quotation?.id ?? '',
      agentId: user.uid,
      agentName: authProvider.userName,
      agentTitle: authProvider.userRole,
      storeId: authProvider.userProfile?['storeId'] ?? 'DEFAULT_STORE',
      customerId: _selectedCustomer?.id,
      customerName: _customerNameController.text.trim(),
      customerPhone: _customerPhoneController.text.trim(),
      totalAmount: totalAmount,
      items: widget.cartItems,
      status: widget.quotation?.status ?? 'SENT', 
      notes: _notesController.text.trim(),
      createdAt: widget.quotation?.createdAt,
    );

    bool success;
    if (quotation.id.isEmpty) {
      success = await salesProvider.createQuotation(quotation);
    } else {
      success = await salesProvider.updateQuotation(quotation);
    }

    setState(() => _isGenerating = false);

    if (success && mounted) {
      final updatedQuotation = quotation.id.isEmpty 
          ? salesProvider.quotations.first 
          : salesProvider.quotations.firstWhere((q) => q.id == quotation.id);
      
      // Share Professional PDF
      await PdfService.generateAndShareQuotation(updatedQuotation);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(quotation.id.isEmpty ? 'Quotation generated & Shared!' : 'Quotation updated & Shared!')));
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => InvoiceConversionScreen(quotation: updatedQuotation),
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(salesProvider.error ?? 'Failed to process quotation')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalAmount = widget.cartItems.fold(0.0, (sum, item) => sum + item.total);

    return Scaffold(
      appBar: AppBar(title: Text(widget.quotation == null ? 'Review Quotation' : 'Edit Quotation')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 600),
          child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Customer Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _customerNameController,
                    decoration: const InputDecoration(
                      labelText: 'Customer/Business Name',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.business),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                IconButton.filledTonal(
                  onPressed: _pickCustomer,
                  icon: const Icon(Icons.person_search),
                  tooltip: 'Select from Customers',
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customerPhoneController,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone Number',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.phone),
              ),
            ),
            const SizedBox(height: 24),
            const Text('Items', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...widget.cartItems.map((item) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(item.productName),
              subtitle: Text('${item.quantity} x ₹${item.price}'),
              trailing: Text('₹${item.total.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            )),
            const Divider(),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Total', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              trailing: Text('₹${totalAmount.toStringAsFixed(2)}', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Theme.of(context).colorScheme.primary)),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _notesController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Notes / Terms',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 32),
            SizedBox(
              width: double.infinity,
              height: 54,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.primary,
                  foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: _isGenerating ? null : _generateQuotation,
                child: _isGenerating 
                  ? const CircularProgressIndicator(color: Colors.white)
                  : Text(widget.quotation == null ? 'Generate & Share Quotation' : 'Update & Share Quotation', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            )
          ],
        ),
      ),
      ),
      ),
    );
  }
}
