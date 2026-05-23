import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/sales_provider.dart';
import '../../models/product.dart';
import '../../models/sale_transaction.dart';
import '../../widgets/responsive_layout.dart';
import 'quotation_generator_screen.dart';
import '../../models/customer.dart';
import 'dart:ui';

class CatalogBrowserScreen extends StatefulWidget {
  final Customer? customer;
  const CatalogBrowserScreen({super.key, this.customer});

  @override
  State<CatalogBrowserScreen> createState() => _CatalogBrowserScreenState();
}

class _CatalogBrowserScreenState extends State<CatalogBrowserScreen> {
  final Map<String, SaleItem> _cart = {};
  String _searchQuery = '';
  String _selectedCategory = 'All'; // All, SOFTWARE, HARDWARE

  @override
  void initState() {
    super.initState();
    // fetchProducts() is now handled by SalesProvider's real-time listener
  }

  void _addToCart(Product product) {
    setState(() {
      if (_cart.containsKey(product.id)) {
        final existing = _cart[product.id]!;
        _cart[product.id] = SaleItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: existing.quantity + 1,
          warrantyMonths: product.warrantyMonths,
        );
      } else {
        _cart[product.id] = SaleItem(
          productId: product.id,
          productName: product.name,
          price: product.price,
          quantity: 1,
          warrantyMonths: product.warrantyMonths,
        );
      }
    });
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Added ${product.name} to cart',
          style: TextStyle(color: Theme.of(context).colorScheme.onPrimaryContainer),
        ),
        duration: const Duration(seconds: 1),
        backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.9),
      ),
    );
  }

  void _removeFromCart(Product product) {
    setState(() {
      if (_cart.containsKey(product.id)) {
        final existing = _cart[product.id]!;
        if (existing.quantity > 1) {
          _cart[product.id] = SaleItem(
            productId: product.id,
            productName: product.name,
            price: product.price,
            quantity: existing.quantity - 1,
            warrantyMonths: product.warrantyMonths,
          );
        } else {
          _cart.remove(product.id);
        }
      }
    });
  }

  int _getCartQuantity(String productId) {
    return _cart[productId]?.quantity ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SalesProvider>();
    final filteredProducts = provider.products.where((p) {
      final matchesSearch = p.name.toLowerCase().contains(_searchQuery.toLowerCase()) || 
                          p.description.toLowerCase().contains(_searchQuery.toLowerCase());
      final matchesCategory = _selectedCategory == 'All' || p.type == _selectedCategory;
      return matchesSearch && matchesCategory && p.isActive;
    }).toList();
    
    double cartTotal = _cart.values.fold(0, (sum, item) => sum + item.total);
    int cartCount = _cart.values.fold(0, (sum, item) => sum + item.quantity);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: const Text('Solution Catalog', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        flexibleSpace: ClipRRect(
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(color: const Color(0xFF00ACC1).withValues(alpha: 0.7)),
          ),
        ),
      ),
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF00ACC1), Color(0xFF00838F), Color(0xFFE0F7FA)],
                stops: [0.0, 0.4, 1.0],
              ),
            ),
          ),
          
          SafeArea(
            child: Column(
              children: [
                // Premium Search Bar
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: TextField(
                              onChanged: (v) => setState(() => _searchQuery = v),
                              style: const TextStyle(color: Colors.white),
                              decoration: InputDecoration(
                                hintText: 'Search software, hardware, services...',
                                hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
                                prefixIcon: const Icon(Icons.search, color: Colors.white70),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildCategoryChip('All', Icons.apps),
                            const SizedBox(width: 8),
                            _buildCategoryChip('SOFTWARE', Icons.cloud_done_outlined, label: 'Software'),
                            const SizedBox(width: 8),
                            _buildCategoryChip('HARDWARE', Icons.settings_input_hdmi, label: 'Hardware'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                
                // Product Grid
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surface,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(30),
                        topRight: Radius.circular(30),
                      ),
                    ),
                    child: provider.isLoading 
                        ? Center(child: CircularProgressIndicator(color: Theme.of(context).colorScheme.primary))
                        : filteredProducts.isEmpty
                            ? _buildEmptyState()
                            : GridView.builder(
                                padding: const EdgeInsets.all(20),
                                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: ResponsiveLayout.isDesktop(context) ? 3 : (ResponsiveLayout.isTablet(context) ? 2 : 1),
                                  childAspectRatio: ResponsiveLayout.isMobile(context) ? 3.0 : 1.2,
                                  crossAxisSpacing: 16,
                                  mainAxisSpacing: 16,
                                ),
                                itemCount: filteredProducts.length,
                                itemBuilder: (context, index) {
                                  final product = filteredProducts[index];
                                  final quantity = _getCartQuantity(product.id);
                                  return _buildProductCard(product, quantity);
                                },
                              ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: cartCount > 0 ? _buildCartBar(cartCount, cartTotal) : null,
    );
  }

  Widget _buildProductCard(Product product, int quantity) {
    final isSoftware = product.type == 'SOFTWARE';
    final isMobile = ResponsiveLayout.isMobile(context);
    
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: Theme.of(context).brightness == Brightness.dark ? 0.2 : 0.05),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _addToCart(product),
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: isMobile ? _buildMobileRow(product, quantity, isSoftware) : _buildGridColumn(product, quantity, isSoftware),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileRow(Product product, int quantity, bool isSoftware) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: (isSoftware ? Colors.purple : Colors.blue).withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(15),
          ),
          child: Icon(
            isSoftware ? Icons.auto_awesome_rounded : Icons.inventory_2_outlined,
            color: isSoftware ? Colors.purple : Colors.blue,
            size: 28,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                product.name,
                style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                product.description,
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 11),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                '₹${product.price.toStringAsFixed(0)}',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
        Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (quantity > 0) ...[
              _buildActionButton(Icons.remove, Colors.red, () => _removeFromCart(product)),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text('$quantity', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
            _buildActionButton(Icons.add, Colors.green, () => _addToCart(product)),
          ],
        ),
      ],
    );
  }

  Widget _buildGridColumn(Product product, int quantity, bool isSoftware) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (isSoftware ? Colors.purple : Colors.blue).withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(15),
              ),
              child: Icon(
                isSoftware ? Icons.auto_awesome_rounded : Icons.inventory_2_outlined,
                color: isSoftware ? Colors.purple : Colors.blue,
                size: 24,
              ),
            ),
            if (quantity > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: const Color(0xFF00ACC1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$quantity in cart',
                  style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
          ],
        ),
        const Spacer(),
        Text(
          product.name,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        Text(
          product.description,
          style: TextStyle(color: Colors.grey[600], fontSize: 12),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              '₹${product.price.toStringAsFixed(0)}',
              style: const TextStyle(
                color: Color(0xFF00ACC1),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            Row(
              children: [
                if (quantity > 0)
                  _buildActionButton(Icons.remove, Colors.red, () => _removeFromCart(product)),
                if (quantity > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text('$quantity', style: const TextStyle(fontWeight: FontWeight.bold)),
                  ),
                _buildActionButton(Icons.add, Colors.green, () => _addToCart(product)),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback onPressed) {
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconButton(
        icon: Icon(icon, size: 16, color: color),
        onPressed: onPressed,
        padding: EdgeInsets.zero,
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.search_off_rounded, size: 80, color: Colors.grey[300]),
          ),
          const SizedBox(height: 24),
          const Text(
            'No results found',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey),
          ),
          const SizedBox(height: 8),
          Text(
            'Try adjusting your search or filters',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildCartBar(int count, double total) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF263238),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$count Items Selected',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
              Text(
                '₹${total.toStringAsFixed(0)}',
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 20),
              ),
            ],
          ),
          ElevatedButton.icon(
            icon: const Icon(Icons.receipt_long_rounded),
            label: const Text('GENERATE QUOTE'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00ACC1),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              elevation: 0,
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => QuotationGeneratorScreen(
                    cartItems: _cart.values.toList(),
                    initialCustomer: widget.customer,
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryChip(String category, IconData icon, {String? label}) {
    final isSelected = _selectedCategory == category;
    return GestureDetector(
      onTap: () => setState(() => _selectedCategory = category),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withValues(alpha: 0.1),
          ),
          boxShadow: isSelected ? [BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10)] : null,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: isSelected ? const Color(0xFF00ACC1) : Colors.white70,
            ),
            const SizedBox(width: 8),
            Text(
              label ?? category,
              style: TextStyle(
                color: isSelected ? const Color(0xFF00ACC1) : Colors.white,
                fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
