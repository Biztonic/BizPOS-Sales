import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sales_provider.dart';
import '../../models/product.dart';

class ProductManagementScreen extends StatefulWidget {
  const ProductManagementScreen({super.key});

  @override
  State<ProductManagementScreen> createState() => _ProductManagementScreenState();
}

class _ProductManagementScreenState extends State<ProductManagementScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _priceController = TextEditingController();
  final _warrantyController = TextEditingController(text: '0');
  String _type = 'HARDWARE';

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _priceController.dispose();
    _warrantyController.dispose();
    super.dispose();
  }

  void _submitProduct() async {
    if (!_formKey.currentState!.validate()) return;

    final sales = context.read<SalesProvider>();
    final product = Product(
      id: '',
      name: _nameController.text.trim(),
      description: _descController.text.trim(),
      price: double.parse(_priceController.text),
      type: _type,
      warrantyMonths: int.tryParse(_warrantyController.text) ?? 0,
    );

    final success = await sales.addProduct(product);
    if (success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Product added successfully')),
        );
        _nameController.clear();
        _descController.clear();
        _priceController.clear();
        _warrantyController.text = '0';
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(sales.error ?? 'Failed to add product')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final sales = context.watch<SalesProvider>();
    
    // Debug prints to troubleshoot product fetching
    debugPrint('ProductManagementScreen: total products: ${sales.products.length}');
    for (var p in sales.products) {
      debugPrint('Product: ID=${p.id}, Type=${p.type}, Name=${p.name}');
    }

    // Separate products into categories
    final softwarePlans = sales.products.where(
      (p) => p.type == 'SOFTWARE' && (p.id.startsWith('plan_') || p.name.toLowerCase().contains('plan'))
    ).toList();

    final addons = sales.products.where(
      (p) => p.type == 'SOFTWARE' && (p.id.startsWith('addon_') || p.name.toLowerCase().contains('addon'))
    ).toList();

    debugPrint('ProductManagementScreen: softwarePlans: ${softwarePlans.length}, addons: ${addons.length}');

    final otherProducts = sales.products.where(
      (p) => !softwarePlans.contains(p) && !addons.contains(p)
    ).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Product Management'),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync),
            tooltip: 'Sync from Settings',
            onPressed: () async {
              final success = await sales.syncProductsFromSettings();
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      sales.error == null 
                        ? 'Catalog synced with settings' 
                        : (sales.error ?? 'Sync completed')
                    ),
                  ),
                );
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // Summary Header
          Container(
            padding: const EdgeInsets.all(16),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Catalog Status', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    Text(
                      '${sales.products.length} Items • ${softwarePlans.length} Plans • ${addons.length} Addons • ${otherProducts.length} Other',
                      style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    ),
                  ],
                ),
                Icon(Icons.cloud_done, color: Theme.of(context).colorScheme.primary),
              ],
            ),
          ),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Software Subscription Plans
                _buildSectionHeader(
                  'Software Subscription Plans',
                  Icons.laptop_chromebook,
                  Colors.purple,
                  subtitle: 'Auto-synced from admin_config',
                ),
                if (softwarePlans.isEmpty)
                  _buildEmptyCard('No subscription plans found.\nThey sync automatically from settings/admin_config.')
                else
                  ...softwarePlans.map((p) => _buildProductTile(p, sales)),
                
                const SizedBox(height: 20),

                // Addon Modules
                _buildSectionHeader(
                  'Addon Modules',
                  Icons.extension,
                  Colors.teal,
                  subtitle: 'Auto-synced from platform_limits',
                ),
                if (addons.isEmpty)
                  _buildEmptyCard('No addons found.\nThey sync automatically from settings/platform_limits.')
                else
                  ...addons.map((p) => _buildProductTile(p, sales)),

                const SizedBox(height: 20),

                // Hardware & Other Products
                _buildSectionHeader(
                  'Hardware & Custom Products',
                  Icons.settings_input_component,
                  Colors.orange,
                  subtitle: 'Manually managed',
                ),
                if (otherProducts.isEmpty)
                  _buildEmptyCard('No custom products yet.\nUse the form below to add items.')
                else
                  ...otherProducts.map((p) => _buildProductTile(p, sales)),
                
                const SizedBox(height: 24),

                // Add Product Form
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('Add New Item', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _nameController,
                            decoration: const InputDecoration(labelText: 'Product Name', border: OutlineInputBorder()),
                            validator: (v) => v == null || v.isEmpty ? 'Required' : null,
                          ),
                          const SizedBox(height: 12),
                          TextFormField(
                            controller: _descController,
                            decoration: const InputDecoration(labelText: 'Description', border: OutlineInputBorder()),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _priceController,
                                  decoration: const InputDecoration(labelText: 'Price (₹)', border: OutlineInputBorder()),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => v == null || double.tryParse(v) == null ? 'Invalid price' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 2,
                                child: TextFormField(
                                  controller: _warrantyController,
                                  decoration: const InputDecoration(
                                    labelText: 'Warranty (Mo)',
                                    helperText: 'Hardware only',
                                    border: OutlineInputBorder(),
                                  ),
                                  keyboardType: TextInputType.number,
                                  validator: (v) => v == null || int.tryParse(v) == null ? 'Invalid' : null,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                flex: 3,
                                child: DropdownButtonFormField<String>(
                                  value: _type,
                                  decoration: const InputDecoration(labelText: 'Type', border: OutlineInputBorder()),
                                  items: const [
                                    DropdownMenuItem(value: 'HARDWARE', child: Text('Hardware')),
                                    DropdownMenuItem(value: 'SOFTWARE', child: Text('Software')),
                                  ],
                                  onChanged: (v) => setState(() => _type = v!),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: _submitProduct,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Theme.of(context).colorScheme.primary,
                                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: const Text('Add to Catalog'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon, Color color, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                if (subtitle != null)
                  Text(subtitle, style: TextStyle(fontSize: 11, color: Colors.grey[500])),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(String message) {
    return Card(
      color: Theme.of(context).brightness == Brightness.dark ? Colors.grey[900] : Colors.grey[50],
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 13),
          ),
        ),
      ),
    );
  }

  Widget _buildProductTile(Product product, SalesProvider sales) {
    final isSynced = product.id.startsWith('plan_') || product.id.startsWith('addon_');
    final iconData = product.type == 'SOFTWARE' ? Icons.laptop_chromebook : Icons.settings_input_component;
    final iconColor = product.type == 'SOFTWARE' ? Colors.blue : Colors.orange;

    return Card(
      margin: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        leading: Icon(iconData, color: product.isActive ? iconColor : Colors.grey),
        title: Text(
          product.name,
          style: TextStyle(
            color: product.isActive ? null : Colors.grey,
            decoration: product.isActive ? null : TextDecoration.lineThrough,
          ),
        ),
        subtitle: Text(
          '₹${product.price.toStringAsFixed(2)} • ${product.type}${isSynced ? ' • Auto-synced' : ''}',
          style: TextStyle(color: product.isActive ? Colors.grey[600] : Colors.grey[400]),
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: product.isActive,
              activeColor: Theme.of(context).colorScheme.primary,
              onChanged: (value) async {
                final success = await sales.toggleProductActive(product.id, value);
                if (!success && mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(sales.error ?? 'Failed to toggle')),
                  );
                }
              },
            ),
            if (!isSynced)
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 20),
                color: Colors.red[300],
                onPressed: () => _confirmDelete(product, sales),
              ),
          ],
        ),
      ),
    );
  }

  void _confirmDelete(Product product, SalesProvider sales) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Product'),
        content: Text('Are you sure you want to delete "${product.name}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              final success = await sales.deleteProduct(product.id);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Product deleted')),
                );
              }
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }
}
