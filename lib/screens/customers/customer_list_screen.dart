import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../providers/customer_provider.dart';
import '../../providers/auth_provider.dart';
import '../../models/customer.dart';
import 'customer_detail_screen.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:permission_handler/permission_handler.dart';

class CustomerListScreen extends StatefulWidget {
  final bool pickMode;

  const CustomerListScreen({super.key, this.pickMode = false});

  @override
  State<CustomerListScreen> createState() => _CustomerListScreenState();
}

class _CustomerListScreenState extends State<CustomerListScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<SalesAuthProvider>();
      context.read<CustomerProvider>().fetchCustomers(
            userId: auth.userId,
            role: auth.userRole,
          );
      context.read<CustomerProvider>().fetchTeamMembers(auth.userId, auth.userRole);
    });
  }

  Future<void> _importFromContacts() async {
    try {
      if (await FlutterContacts.requestPermission(readonly: true)) {
        final contact = await FlutterContacts.openExternalPick();
        if (contact != null) {
          final fullContact = await FlutterContacts.getContact(contact.id);
          if (fullContact != null) {
            final name = fullContact.displayName;
            final phone = fullContact.phones.isNotEmpty 
                ? fullContact.phones.first.number.replaceAll(RegExp(r'[^\d+]'), '') 
                : '';
            final email = fullContact.emails.isNotEmpty ? fullContact.emails.first.address : '';
            final address = fullContact.addresses.isNotEmpty ? fullContact.addresses.first.address : '';

            if (name.isEmpty || phone.isEmpty) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Contact must have a name and phone number')),
                );
              }
              return;
            }

            final auth = context.read<SalesAuthProvider>();
            final newCustomer = Customer(
              id: '',
              name: name,
              phone: phone,
              email: email,
              address: address,
              status: 'LEAD',
              assignedTo: auth.userId,
              assignedToName: auth.userName,
              source: 'CONTACT_IMPORT',
            );

            if (mounted) {
              final success = await context.read<CustomerProvider>().addCustomer(newCustomer);
              if (success && mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Imported $name successfully')),
                );
              }
            }
          }
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Contacts permission denied')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error importing contact: $e')),
        );
      }
    }
  }

  void _showTransferDialog(Customer customer) {
    final provider = context.read<CustomerProvider>();
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Transfer Customer'),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: provider.teamMembers.length,
            itemBuilder: (context, index) {
              final member = provider.teamMembers[index];
              return ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(member['name'] ?? 'Unknown'),
                subtitle: Text(member['role'] ?? ''),
                onTap: () async {
                  final success = await provider.transferCustomer(
                    customer.id,
                    member['id'],
                    member['name'],
                  );
                  if (success && mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Transferred to ${member['name']}')),
                    );
                  }
                },
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final url = 'tel:$phone';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<void> _launchWhatsApp(String phone) async {
    // Remove non-digits
    final cleanPhone = phone.replaceAll(RegExp(r'[^\d]'), '');
    final url = 'https://wa.me/$cleanPhone';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _setReminder(Customer customer) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: customer.nextFollowUpAt ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      helpText: 'Set Follow-up Reminder',
    );

    if (picked != null && mounted) {
      final TimeOfDay? time = await showTimePicker(
        context: context,
        initialTime: TimeOfDay.fromDateTime(customer.nextFollowUpAt ?? DateTime.now()),
      );

      if (time != null && mounted) {
        final reminderDate = DateTime(
          picked.year,
          picked.month,
          picked.day,
          time.hour,
          time.minute,
        );

        final success = await context.read<CustomerProvider>().updateCustomer(
          customer.copyWith(nextFollowUpAt: reminderDate),
        );

        if (success && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Reminder set for ${DateFormat('dd MMM, hh:mm a').format(reminderDate)}')),
          );
        }
      }
    }
  }

  void _showCustomerDialog([Customer? customer]) {
    final nameController = TextEditingController(text: customer?.name);
    final phoneController = TextEditingController(text: customer?.phone);
    final emailController = TextEditingController(text: customer?.email);
    final addressController = TextEditingController(text: customer?.address);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(customer == null ? 'Add Customer' : 'Edit Customer'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              TextField(
                controller: phoneController,
                decoration: const InputDecoration(labelText: 'Phone'),
                keyboardType: TextInputType.phone,
              ),
              TextField(
                controller: emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
              ),
              TextField(
                controller: addressController,
                decoration: const InputDecoration(labelText: 'Address'),
                maxLines: 2,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty || phoneController.text.isEmpty) return;

              final auth = context.read<SalesAuthProvider>();
              final newCustomer = Customer(
                id: customer?.id ?? '',
                name: nameController.text,
                phone: phoneController.text,
                email: emailController.text,
                address: addressController.text,
                assignedTo: customer?.assignedTo ?? auth.userId,
                assignedToName: customer?.assignedToName ?? auth.userName,
                status: customer?.status ?? 'LEAD',
              );

              final provider = context.read<CustomerProvider>();
              bool success;
              if (customer == null) {
                success = await provider.addCustomer(newCustomer);
              } else {
                success = await provider.updateCustomer(newCustomer);
              }

              if (success && mounted) {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(customer == null ? 'Customer added successfully!' : 'Customer updated successfully!')),
                );
              } else if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(provider.error ?? 'Failed to save customer')),
                );
              }
            },
            child: Text(customer == null ? 'Add' : 'Save'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<SalesAuthProvider>();
    
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          title: widget.pickMode 
            ? const Text('Select Customer') 
            : TextField(
                controller: _searchController,
                style: TextStyle(color: Theme.of(context).colorScheme.onPrimary),
                cursorColor: Theme.of(context).colorScheme.onPrimary,
                decoration: InputDecoration(
                  hintText: 'Search customers...',
                  hintStyle: TextStyle(color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)),
                  border: InputBorder.none,
                  prefixIcon: Icon(Icons.search, color: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.7)),
                ),
                onChanged: (val) => setState(() => _searchQuery = val.toLowerCase()),
              ),
          actions: [
            if (!widget.pickMode)
              IconButton(
                icon: const Icon(Icons.person_add_alt_1),
                onPressed: _importFromContacts,
                tooltip: 'Import from Contacts',
              ),
          ],
          bottom: TabBar(
            isScrollable: true,
            labelColor: Theme.of(context).colorScheme.onPrimary,
            unselectedLabelColor: Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.6),
            indicatorColor: Theme.of(context).colorScheme.onPrimary,
            indicatorWeight: 3,
            labelStyle: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 0.5),
            tabs: const [
              Tab(text: 'ALL'),
              Tab(text: 'LEADS'),
              Tab(text: 'PROSPECTS'),
              Tab(text: 'ACTIVE'),
            ],
          ),
        ),
        body: Consumer<CustomerProvider>(
          builder: (context, provider, child) {
            if (provider.isLoading) return const Center(child: CircularProgressIndicator());
            
            final filtered = provider.customers.where((c) {
              return c.name.toLowerCase().contains(_searchQuery) || 
                     c.phone.contains(_searchQuery);
            }).toList();

            return TabBarView(
              children: [
                _buildCustomerList(filtered),
                _buildCustomerList(filtered.where((c) => c.status == 'LEAD').toList()),
                _buildCustomerList(filtered.where((c) => c.status == 'PROSPECT').toList()),
                _buildCustomerList(filtered.where((c) => c.status == 'ACTIVE').toList()),
              ],
            );
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: () => _showCustomerDialog(),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }

  Widget _buildCustomerList(List<Customer> customers) {
    final auth = context.read<SalesAuthProvider>();
    if (customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.person_outline, size: 64, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3)),
            const SizedBox(height: 16),
            Text('No customers found', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 16)),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _importFromContacts,
              icon: const Icon(Icons.contacts),
              label: const Text('Import from Contacts'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Theme.of(context).colorScheme.onPrimary,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: customers.length,
      itemBuilder: (context, index) {
        final customer = customers[index];

        return Card(
          elevation: 2,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          clipBehavior: Clip.antiAlias,
          child: widget.pickMode
              ? ListTile(
                  onTap: () => Navigator.pop(context, customer),
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(customer.status),
                    child: Text(customer.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(customer.phone),
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _getStatusColor(customer.status).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      customer.status,
                      style: TextStyle(
                        color: _getStatusColor(customer.status),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                )
              : ExpansionTile(
                  leading: CircleAvatar(
                    backgroundColor: _getStatusColor(customer.status),
                    child: Text(customer.name[0], style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                  title: Row(
                    children: [
                      Expanded(child: Text(customer.name, style: const TextStyle(fontWeight: FontWeight.bold))),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: _getStatusColor(customer.status).withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _getStatusColor(customer.status).withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          customer.status,
                          style: TextStyle(
                            color: _getStatusColor(customer.status),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  subtitle: Text(customer.phone, style: TextStyle(color: Theme.of(context).colorScheme.outline)),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _actionButton(Icons.phone, 'Call', Colors.green, () => _launchPhone(customer.phone)),
                              _actionButton(Icons.message, 'WhatsApp', Colors.teal, () => _launchWhatsApp(customer.phone)),
                              _actionButton(Icons.notifications_active, 'Remind', Colors.purple, () => _setReminder(customer)),
                              _actionButton(Icons.visibility, 'Details', Theme.of(context).colorScheme.primary, () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => CustomerDetailScreen(customer: customer),
                                  ),
                                );
                              }),
                            ],
                          ),
                          const SizedBox(height: 16),
                          if (auth.isTeamLeader || auth.isDirector)
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.tonalIcon(
                                onPressed: () => _showTransferDialog(customer),
                                icon: const Icon(Icons.swap_horiz, size: 18),
                                label: const Text('Transfer / Assign Lead'),
                                style: FilledButton.styleFrom(
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                ),
                              ),
                            ),
                          const Divider(height: 24),
                          Row(
                            children: [
                              const Icon(Icons.person_outline, size: 16, color: Colors.grey),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Assigned to: ${customer.assignedToName ?? "Unassigned"}',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ),
                              TextButton.icon(
                                icon: const Icon(Icons.edit, size: 14),
                                label: const Text('Edit', style: TextStyle(fontSize: 12)),
                                onPressed: () => _showCustomerDialog(customer),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _actionButton(IconData icon, String label, Color color, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(height: 4),
          Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Color _getStatusColor(String status) {
    switch (status) {
      case 'LEAD': return Colors.orange;
      case 'PROSPECT': return Colors.blue;
      case 'ACTIVE': return Colors.green;
      default: return Colors.grey;
    }
  }

  Widget _buildStatusBadge(String status) {
    final color = _getStatusColor(status);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.5)),
      ),
      child: Text(
        status,
        style: TextStyle(color: color, fontSize: 10, fontWeight: FontWeight.bold),
      ),
    );
  }
}
