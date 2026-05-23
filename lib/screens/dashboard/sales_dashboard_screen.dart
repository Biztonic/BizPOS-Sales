import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../providers/auth_provider.dart';
import '../../providers/sales_provider.dart';
import '../../providers/commission_provider.dart';
import '../../providers/team_provider.dart';
import '../../providers/system_config_provider.dart';

import '../sales_flow/catalog_browser_screen.dart';

import 'package:fl_chart/fl_chart.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:intl/intl.dart';

import '../sales_flow/invoice_conversion_screen.dart';
import '../hierarchy/my_team_screen.dart';
import '../hierarchy/director_dashboard_screen.dart';
import '../customers/customer_list_screen.dart';
import '../admin/product_management_screen.dart';
import '../admin/user_management_screen.dart';
import '../admin/system_settings_screen.dart';
import '../../widgets/responsive_layout.dart';
import '../../utils/image_helper.dart';
import '../../models/quotation.dart';
import '../sales_flow/quotation_generator_screen.dart';
import '../../services/pdf_service.dart';


class SalesDashboardScreen extends StatefulWidget {
  const SalesDashboardScreen({super.key});

  @override
  State<SalesDashboardScreen> createState() => _SalesDashboardScreenState();
}

class _SalesDashboardScreenState extends State<SalesDashboardScreen> {
  int _selectedIndex = 0;
  DateTime _selectedMonth = DateTime.now();

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  void _changeMonth(int monthsToAdd) {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + monthsToAdd, 1);
    });
    _loadData();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    final auth = context.read<SalesAuthProvider>();
    if (auth.isLoggedIn) {
      final salesProvider = context.read<SalesProvider>();
      final commissionProvider = context.read<CommissionProvider>();
      
      if (auth.isSuperAdmin) {
        salesProvider.fetchTransactions(isSuperAdmin: auth.isSuperAdmin); // No agentId = fetch all
        salesProvider.fetchQuotations(isSuperAdmin: auth.isSuperAdmin); // No agentId = fetch all
        salesProvider.startGlobalStatsListener();
      } else {
        salesProvider.fetchTransactions(agentId: auth.userId, isSuperAdmin: auth.isSuperAdmin);
        salesProvider.fetchQuotations(agentId: auth.userId, isSuperAdmin: auth.isSuperAdmin);
        commissionProvider.startListeningToCommissions(agentId: auth.userId);
        commissionProvider.startListeningToProgress(
          agentId: auth.userId, 
          role: auth.userRole, 
          isPermanentDirector: auth.isPermanentDirector,
          selectedMonth: _selectedMonth,
        );
      }

      if (auth.isTeamLeader || auth.isDirector) {
        context.read<TeamProvider>().fetchTeamMembers(auth.userId);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<SalesAuthProvider>();
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('BizPOS Sales'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                context.read<SalesProvider>().clearData();
                auth.signOut();
                Navigator.of(context).pushReplacementNamed('/login');
              } else if (value == 'profile') {
                Navigator.pushNamed(context, '/profile');
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'profile',
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundImage: auth.photoUrl != null ? CachedNetworkImageProvider(auth.photoUrl!) : null,
                    child: auth.photoUrl == null ? const Icon(Icons.person) : null,
                  ),
                  title: Text(auth.userName.isNotEmpty ? auth.userName : auth.userEmail, style: theme.textTheme.titleSmall),
                  subtitle: Text(auth.userEmail, style: theme.textTheme.bodySmall),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(value: 'logout', child: Text('Sign Out')),
            ],
          ),
        ],
      ),
      drawer: Drawer(
        child: Column(
          children: [
            UserAccountsDrawerHeader(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                ),
              ),
              currentAccountPicture: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: ClipOval(
                  child: auth.photoUrl != null
                      ? CachedNetworkImage(
                          imageUrl: auth.photoUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => const CircularProgressIndicator(color: Colors.white),
                          errorWidget: (context, url, error) => const Icon(Icons.person, color: Colors.white, size: 40),
                        )
                      : const Icon(Icons.person, color: Colors.white, size: 40),
                ),
              ),
              accountName: Text(auth.userName.isNotEmpty ? auth.userName : 'User', style: const TextStyle(fontWeight: FontWeight.bold)),
              accountEmail: Text(auth.userRole, style: const TextStyle(color: Colors.white70)),
              otherAccountsPictures: [
                Hero(
                  tag: 'logo',
                  child: Image.asset(
                    'assets/images/logo.png',
                    width: 32,
                    height: 32,
                    errorBuilder: (context, error, stackTrace) => const Icon(Icons.point_of_sale, color: Colors.white, size: 24),
                  ),
                ),
              ],
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  _drawerItem(Icons.person_outline, 'My Profile', theme.colorScheme.primary, () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/profile');
                  }, theme),
                  _drawerItem(Icons.people_outline, 'Customers', Colors.teal, () {
                    Navigator.pop(context);
                    Navigator.push(context, MaterialPageRoute(builder: (_) => const CustomerListScreen()));
                  }, theme, subtitle: 'Manage your client list'),
                  _drawerItem(Icons.leaderboard_outlined, 'Leaderboard', Colors.amber, () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/leaderboard');
                  }, theme, subtitle: 'View top performers'),
                  _drawerItem(Icons.account_balance_wallet_outlined, 'My Account', Colors.indigo, () {
                    Navigator.pop(context);
                    Navigator.pushNamed(context, '/account');
                  }, theme, subtitle: 'Income & expenses'),
                  const Divider(),
                  if (!auth.isSuperAdmin) ...[
                    if (auth.isTeamLeader || auth.isDirector)
                      _drawerItem(Icons.group_outlined, 'My Team', Colors.blue, () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const MyTeamScreen()));
                      }, theme, subtitle: 'Manage your team'),
                    if (auth.isDirector)
                      _drawerItem(Icons.insights_outlined, 'Director Insights', Colors.orange, () {
                        Navigator.pop(context);
                        Navigator.push(context, MaterialPageRoute(builder: (_) => const DirectorDashboardScreen()));
                      }, theme, subtitle: 'Global performance'),
                  ],
                  if (auth.isSuperAdmin) ...[
                    Padding(
                      padding: const EdgeInsets.only(left: 16, top: 16, bottom: 8),
                      child: Text('CONFIGURATION', style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.disabledColor)),
                    ),
                    _drawerItem(Icons.inventory_2_outlined, 'Products', Colors.deepPurple, () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const ProductManagementScreen()));
                    }, theme),
                    _drawerItem(Icons.manage_accounts_outlined, 'Users', Colors.blue, () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const UserManagementScreen()));
                    }, theme),
                    _drawerItem(Icons.settings_outlined, 'System Settings', theme.disabledColor, () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => const SystemSettingsScreen()));
                    }, theme),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      body: Consumer2<SalesProvider, CommissionProvider>(
        builder: (context, sales, commission, _) {
          return ResponsiveLayout(
            mobile: IndexedStack(
              index: _selectedIndex,
              children: auth.isSuperAdmin 
                ? [
                    _buildSuperAdminOverview(auth, sales, commission, theme),
                    const SystemSettingsScreen(),
                    const UserManagementScreen(),
                  ]
                : [
                    _buildOverviewTab(auth, sales, commission, theme),
                    _buildQuotationsTab(sales, theme),
                    _buildTransactionsTab(sales, theme),
                    _buildIncomeTab(commission, theme, sales),
                    if (auth.isTeamLeader || auth.isDirector)
                      _buildTeamTab(),
                  ],
            ),
          );
        },
      ),
      floatingActionButton: auth.isSuperAdmin ? null : FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const CatalogBrowserScreen()),
          );
        },
        icon: const Icon(Icons.add_shopping_cart),
        label: const Text('New Sale / Quote'),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        onDestinationSelected: (i) => setState(() => _selectedIndex = i),
        destinations: auth.isSuperAdmin
            ? const [
                NavigationDestination(icon: Icon(Icons.admin_panel_settings_outlined), selectedIcon: Icon(Icons.admin_panel_settings), label: 'Admin'),
                NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'Settings'),
                NavigationDestination(icon: Icon(Icons.people_outlined), selectedIcon: Icon(Icons.people), label: 'Users'),
              ]
            : [
                NavigationDestination(icon: Icon(Icons.dashboard_outlined), selectedIcon: Icon(Icons.dashboard), label: 'Overview'),
                NavigationDestination(icon: Icon(Icons.description_outlined), selectedIcon: Icon(Icons.description), label: 'Quotes'),
                NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Sales'),
                NavigationDestination(icon: Icon(Icons.monetization_on_outlined), selectedIcon: Icon(Icons.monetization_on), label: 'Income'),
                if (auth.isTeamLeader || auth.isDirector)
                  NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Team'),
              ],
      ),
    );
  }

  Widget _drawerItem(IconData icon, String title, Color color, VoidCallback onTap, ThemeData theme, {String? subtitle}) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
        child: Icon(icon, color: color, size: 20),
      ),
      title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
      subtitle: subtitle != null ? Text(subtitle, style: theme.textTheme.bodySmall) : null,
      onTap: onTap,
      dense: true,
    );
  }

  Widget _buildTeamTab() {
    return const MyTeamScreen();
  }

  Widget _buildSuperAdminOverview(SalesAuthProvider auth, SalesProvider sales, CommissionProvider commission, ThemeData theme) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'System Administration',
            style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Global configuration and oversight',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor),
          ),
          const SizedBox(height: 24),
          
          // High Level Stats
            Row(
            children: [
              Expanded(
                child: _buildAdminStatCard(
                  'Total Agents', 
                  '${sales.totalAgents}', 
                  Icons.people_outline, 
                  theme.colorScheme.primary,
                  theme,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildAdminStatCard(
                  'Total Sales (Global)', 
                  '₹${sales.totalSales.toStringAsFixed(0)}', 
                  Icons.account_balance_outlined, 
                  Colors.green,
                  theme,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildAdminStatCard(
            'Monthly Target Achievement (Avg)', 
            '${sales.avgAchievement.toStringAsFixed(1)}%', 
            Icons.trending_up, 
            Colors.orange,
            theme,
          ),
          
          const SizedBox(height: 24),
          Text(
            'Configuration Shortcuts',
            style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildConfigShortcut(
            'Commission Rates',
            'Base: ${context.read<SystemConfigProvider>().baseCommissionRate.toStringAsFixed(0)}%, Team: ${context.read<SystemConfigProvider>().teamLeaderOverrideRate.toStringAsFixed(0)}%, Pool: ${context.read<SystemConfigProvider>().directorPoolRate.toStringAsFixed(0)}%',
            Icons.percent,
            () => setState(() => _selectedIndex = 1),
            theme,
          ),
          _buildConfigShortcut(
            'Registration Policy',
            'New registrations: ${context.read<SystemConfigProvider>().allowNewRegistrations ? "ALLOWED" : "BLOCKED"}',
            Icons.app_registration,
            () => setState(() => _selectedIndex = 1),
            theme,
          ),
          _buildConfigShortcut(
            'User Management',
            'Manage roles and hierarchy',
            Icons.manage_accounts_outlined,
            () => setState(() => _selectedIndex = 2),
            theme,
          ),
        ],
      ),
    );
  }

  Widget _buildAdminStatCard(String title, String value, IconData icon, Color color, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 16),
            Text(title, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 4),
            Text(value, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigShortcut(String title, String subtitle, IconData icon, VoidCallback onTap, ThemeData theme) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: theme.colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: theme.colorScheme.primary),
        ),
        title: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        trailing: const Icon(Icons.arrow_forward_ios, size: 14),
      ),
    );
  }

  Widget _buildOverviewTab(SalesAuthProvider auth, SalesProvider sales, CommissionProvider commission, ThemeData theme) {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Header Greeting
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Hi ${auth.userName},',
                style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                auth.userRole,
                style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.secondary, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 20),

          // Month Navigation
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: theme.cardColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  onPressed: () => _changeMonth(-1),
                  color: theme.colorScheme.primary,
                ),
                Text(
                  DateFormat('MMMM yyyy').format(_selectedMonth),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  onPressed: () => _changeMonth(1),
                  color: theme.colorScheme.primary,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Role Progress Banner
          _buildRoleBanner(auth, theme),
          const SizedBox(height: 16),
          // Target Progress
          if (!auth.isDirector)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!auth.isTeamLeader) ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Target: ₹${commission.targetAmount.toStringAsFixed(0)}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text('Role: ${commission.currentRole}', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: commission.progressToTarget,
                        backgroundColor: theme.dividerColor.withValues(alpha: 0.1),
                        color: Colors.green,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text('Current Sales: ₹${commission.currentMonthSales.toStringAsFixed(0)} (${(commission.progressToTarget * 100).toStringAsFixed(1)}%)', style: theme.textTheme.bodySmall),
                    ] else ...[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text('Director Progress:', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                          Text('${commission.activeRecruitsCount} / ${commission.recruitsTarget} recruits', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      const SizedBox(height: 12),
                      LinearProgressIndicator(
                        value: commission.progressToDirector,
                        backgroundColor: theme.dividerColor.withValues(alpha: 0.1),
                        color: theme.colorScheme.primary,
                        minHeight: 8,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      const SizedBox(height: 8),
                      Text('Achieve 10 recruits hitting target to become Director', style: theme.textTheme.bodySmall),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          
          if (auth.isTeamLeader) _buildTeamPulse(commission, theme),
          if (auth.isDirector) _buildStrategicSummary(commission, theme),

          const SizedBox(height: 16),

          if (auth.isTeamLeader || auth.isDirector) ...[
            _buildBusinessPieChart(commission.currentMonthSales, commission.teamMonthSales, theme),
            const SizedBox(height: 16),
          ],

          // Stats Cards
          ResponsiveGrid(
            crossAxisCountMobile: 2,
            crossAxisCountTablet: 4,
            crossAxisCountDesktop: 4,
            childAspectRatio: ResponsiveLayout.isMobile(context) ? 1.6 : 1.8,
            children: [
              _buildStatCard('Total Sales', '₹${(auth.isSuperAdmin ? sales.totalSales : commission.currentMonthSales).toStringAsFixed(0)}', Icons.trending_up, Colors.green, theme),
              _buildStatCard('Est. Payout', '₹${commission.totalMonthlyEstimate.toStringAsFixed(0)}', Icons.account_balance_wallet_outlined, Colors.blue, theme),
              _buildStatCard('Earned', '₹${commission.totalEarned.toStringAsFixed(0)}', Icons.monetization_on_outlined, Colors.orange, theme),
              _buildStatCard('Pending', '₹${commission.totalPending.toStringAsFixed(0)}', Icons.pending_actions, Colors.purple, theme),
              _buildStatCard('Expenses', '₹${commission.approvedExpensesThisMonth.toStringAsFixed(0)}', Icons.receipt_long, Colors.teal, theme),
            ],
          ),
          const SizedBox(height: 24),

          // Recent Transactions
          Text('Recent Transactions', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          if (sales.transactions.where((t) => t.agentId == auth.userId).isEmpty)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 48, color: theme.disabledColor),
                      const SizedBox(height: 16),
                      Text('No transactions yet.\nStart recording sales!', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium?.copyWith(color: theme.hintColor)),
                    ],
                  ),
                ),
              ),
            )
          else
            ...sales.transactions.where((t) => t.agentId == auth.userId).take(5).map((t) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: (t.status == 'Completed' ? Colors.green : Colors.orange).withValues(alpha: 0.1),
                      child: Icon(
                        t.status == 'Completed' ? Icons.check : Icons.pending,
                        color: t.status == 'Completed' ? Colors.green : Colors.orange,
                        size: 20,
                      ),
                    ),
                    title: Text('₹${t.amount.toStringAsFixed(2)}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                    subtitle: Text('${t.paymentMethod} • ${t.customerName ?? "Walk-in"}', style: theme.textTheme.bodySmall),
                    trailing: Text(t.status, style: theme.textTheme.labelSmall?.copyWith(
                      color: t.status == 'Completed' ? Colors.green : Colors.orange,
                      fontWeight: FontWeight.bold,
                    )),
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildTransactionsTab(SalesProvider sales, ThemeData theme) {
    final auth = context.read<SalesAuthProvider>();
    
    // Filter transactions: Show all if Super Admin, otherwise only current user's
    final filteredTransactions = auth.isSuperAdmin 
        ? sales.transactions 
        : sales.transactions.where((t) => t.agentId == auth.userId).toList();

    if (sales.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filteredTransactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long_outlined, size: 64, color: theme.disabledColor),
            const SizedBox(height: 16),
            Text('No sales transactions', style: theme.textTheme.titleLarge?.copyWith(color: theme.hintColor)),
            const SizedBox(height: 8),
          ],
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredTransactions.length,
          itemBuilder: (context, index) {
            final t = filteredTransactions[index];
            final statusColor = _getStatusColor(t.status);
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: statusColor.withValues(alpha: 0.1),
                  child: Icon(Icons.receipt_long_outlined, color: statusColor, size: 20),
                ),
                title: Text('₹${t.amount.toStringAsFixed(2)}', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                subtitle: Text('${t.customerName ?? "Walk-in"} • ${t.paymentMethod}\n${DateFormat('dd MMM yyyy').format(t.createdAt)}', style: theme.textTheme.bodySmall),
                isThreeLine: true,
                trailing: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
                  ),
                  child: Text(t.status, style: theme.textTheme.labelSmall?.copyWith(color: statusColor, fontWeight: FontWeight.bold)),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildBusinessPieChart(double selfBusiness, double teamBusiness, ThemeData theme) {
    if (selfBusiness == 0 && teamBusiness == 0) return const SizedBox.shrink();

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Business Analytics', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            SizedBox(
              height: 200,
              child: PieChart(
                PieChartData(
                  sectionsSpace: 4,
                  centerSpaceRadius: 40,
                  sections: [
                    PieChartSectionData(
                      color: theme.colorScheme.primary,
                      value: selfBusiness,
                      title: 'Self\n${(selfBusiness/(selfBusiness+teamBusiness)*100).toStringAsFixed(1)}%',
                      radius: 50,
                      titleStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                    if (teamBusiness > 0)
                      PieChartSectionData(
                        color: theme.colorScheme.secondary,
                        value: teamBusiness,
                        title: 'Team\n${(teamBusiness/(selfBusiness+teamBusiness)*100).toStringAsFixed(1)}%',
                        radius: 50,
                        titleStyle: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildLegend(theme.colorScheme.primary, 'Self: ₹${selfBusiness.toStringAsFixed(0)}', theme),
                const SizedBox(width: 16),
                if (teamBusiness > 0)
                  _buildLegend(theme.colorScheme.secondary, 'Team: ₹${teamBusiness.toStringAsFixed(0)}', theme),
              ],
            )
          ],
        ),
      ),
    );
  }

  Widget _buildLegend(Color color, String text, ThemeData theme) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(text, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }

  Widget _buildQuotationsTab(SalesProvider sales, ThemeData theme) {
    final auth = context.read<SalesAuthProvider>();
    
    // Filter quotations: Show all if Super Admin, otherwise only current user's
    final filteredQuotations = auth.isSuperAdmin 
        ? sales.quotations 
        : sales.quotations.where((q) => q.agentId == auth.userId).toList();

    if (sales.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (filteredQuotations.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.description, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text('No pending quotations', style: TextStyle(fontSize: 18, color: Colors.grey)),
            SizedBox(height: 8),
            Text('Tap the + button to create a new one', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 800),
        child: ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: filteredQuotations.length,
          itemBuilder: (context, index) {
            final q = filteredQuotations[index];
            final isPending = q.status == 'PENDING' || q.status == 'SENT';
            final isConverted = q.status == 'CONVERTED';

            return Card(
              margin: const EdgeInsets.only(bottom: 16),
              elevation: 2,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Column(
                  children: [
                    // Main Info Area
                    ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      leading: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: _getStatusColor(q.status).withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.description_outlined, color: _getStatusColor(q.status), size: 24),
                      ),
                      title: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '₹${q.totalAmount.toStringAsFixed(2)}',
                              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _buildStatusChip(q.status, theme),
                        ],
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              q.customerName ?? "Unknown Customer",
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '${q.items.length} items • Valid until: ${DateFormat('dd MMM').format(q.validUntil)}',
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                            ),
                          ],
                        ),
                      ),
                      isThreeLine: true,
                    ),
                    
                    const Divider(height: 1, indent: 16, endIndent: 16),
                    
                    // Action Row (Ensures consistency in height)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 4,
                        runSpacing: 4,
                        children: [
                          // Shared actions
                          TextButton.icon(
                            onPressed: () => _shareQuotation(q),
                            icon: const Icon(Icons.share, size: 18),
                            label: const Text('Share PDF', style: TextStyle(fontSize: 13)),
                            style: TextButton.styleFrom(foregroundColor: Colors.blueGrey),
                          ),
                          
                          if (isPending) ...[
                            TextButton.icon(
                              onPressed: () => _editQuotation(q),
                              icon: const Icon(Icons.edit, size: 18),
                              label: const Text('Edit', style: TextStyle(fontSize: 13)),
                              style: TextButton.styleFrom(foregroundColor: Colors.blue),
                            ),
                            TextButton.icon(
                              onPressed: () => _confirmDeleteQuotation(q.id),
                              icon: const Icon(Icons.delete, size: 18),
                              label: const Text('Delete', style: TextStyle(fontSize: 13)),
                              style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
                            ),
                            ElevatedButton(
                              onPressed: () => _openInvoiceConversion(q),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                elevation: 0,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              child: const Text('Convert', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                            ),
                          ],
                          
                          if (isConverted)
                            Padding(
                              padding: const EdgeInsets.only(right: 8.0, top: 8.0, bottom: 8.0),
                              child: Text(
                                'Finalized',
                                style: TextStyle(color: Colors.grey[500], fontStyle: FontStyle.italic, fontSize: 12),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildStatusChip(String status, ThemeData theme) {
    Color color;
    switch (status) {
      case 'CONVERTED':
        color = Colors.green;
        break;
      case 'SENT':
      case 'PENDING':
        color = theme.colorScheme.primary;
        break;
      case 'REJECTED':
        color = Colors.red;
        break;
      default:
        color = theme.disabledColor;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Text(
        status,
        style: theme.textTheme.labelSmall?.copyWith(color: color, fontWeight: FontWeight.bold),
      ),
    );
  }

  Future<void> _shareQuotation(Quotation q) async {
    try {
      await PdfService.generateAndShareQuotation(q);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error generating PDF: $e')),
      );
    }
  }

  void _editQuotation(Quotation quotation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => QuotationGeneratorScreen(
          cartItems: quotation.items,
          quotation: quotation,
        ),
      ),
    );
  }

  Future<void> _confirmDeleteQuotation(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Quotation?'),
        content: const Text('Are you sure you want to delete this quotation? This action cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      final success = await context.read<SalesProvider>().deleteQuotation(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(success ? 'Quotation deleted' : 'Failed to delete quotation')),
        );
      }
    }
  }

  void _openInvoiceConversion(Quotation quotation) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InvoiceConversionScreen(quotation: quotation),
      ),
    );
  }

  Widget _buildIncomeTab(CommissionProvider commission, ThemeData theme, SalesProvider sales) {
    if (commission.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    
    return DefaultTabController(
      length: 2,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 800),
          child: Column(
            children: [
              TabBar(
                tabs: const [
                  Tab(text: 'Monthly View'),
                  Tab(text: 'Yearly View'),
                ],
                labelStyle: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                unselectedLabelStyle: theme.textTheme.titleSmall,
                labelColor: theme.colorScheme.primary,
                unselectedLabelColor: theme.hintColor,
                indicatorColor: theme.colorScheme.primary,
                indicatorSize: TabBarIndicatorSize.tab,
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    _buildIncomeTabContent(commission, theme, sales, isMonthly: true),
                    _buildIncomeTabContent(commission, theme, sales, isMonthly: false),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
  Widget _buildIncomeTabContent(CommissionProvider commission, ThemeData theme, SalesProvider sales, {required bool isMonthly}) {
    final dataMap = isMonthly ? commission.commissionsByMonth : commission.commissionsByYear;
    final sortedKeys = dataMap.keys.toList()..sort((a, b) => b.compareTo(a));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        if (isMonthly) ...[
          _buildFinancialSummary(sales, theme),
          const SizedBox(height: 16),
          _buildCommissionBreakdownHeader(commission, theme, context),
          const SizedBox(height: 16),
        ],
        if (dataMap.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.monetization_on, size: 48, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('No income data available', style: TextStyle(fontSize: 16, color: Colors.grey)),
                ],
              ),
            ),
          )
        else ...[
          _buildCommissionGraph(dataMap, isMonthly: isMonthly),
        const SizedBox(height: 24),
        const Text('Breakdown', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        ...sortedKeys.map((key) {
          final amount = dataMap[key]!;
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: const Color(0xFF00ACC1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.calendar_today, color: Color(0xFF00ACC1), size: 20),
              ),
              title: Text(isMonthly ? _formatMonth(key) : key, style: const TextStyle(fontWeight: FontWeight.bold)),
              trailing: Text('₹${amount.toStringAsFixed(2)}', style: const TextStyle(
                fontWeight: FontWeight.bold, 
                fontSize: 16,
                color: Colors.green,
              )),
            ),
          );
        }),
        const SizedBox(height: 24),
        const Text('Recent Transactions', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
        const SizedBox(height: 12),
        ...commission.commissions.take(10).map((c) => Card(
          margin: const EdgeInsets.only(bottom: 8),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: c.status == 'Paid' ? Colors.green : Colors.orange,
              child: const Icon(Icons.monetization_on, color: Colors.white, size: 20),
            ),
            title: Text('₹${c.amount.toStringAsFixed(2)}', style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text('Sale: ₹${c.saleAmount.toStringAsFixed(0)} @ ${c.rate}%\n${c.status}'),
            isThreeLine: true,
            trailing: Text(
              '${c.createdAt.day}/${c.createdAt.month}',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        )),
        ],
      ],
    );
  }

  Widget _buildCommissionGraph(Map<String, double> data, {required bool isMonthly}) {
    if (data.isEmpty) return const SizedBox.shrink();

    // Take last 6 entries for graph
    final keys = data.keys.toList()..sort();
    final recentKeys = keys.length > 6 ? keys.sublist(keys.length - 6) : keys;
    final maxVal = data.values.fold(0.0, (m, v) => v > m ? v : m);

    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isMonthly ? 'Monthly Performance' : 'Yearly Performance',
              style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF00ACC1)),
            ),
            const SizedBox(height: 20),
            SizedBox(
              height: 150,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: recentKeys.map((key) {
                  final val = data[key]!;
                  final heightFactor = maxVal > 0 ? val / maxVal : 0.0;
                  return Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Container(
                        width: 30,
                        height: (120 * heightFactor).clamp(4.0, 120.0),
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [Color(0xFF00ACC1), Color(0xFF00B8D4)],
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        isMonthly ? key.split('-').last : key.substring(2),
                        style: const TextStyle(fontSize: 10, color: Colors.grey),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatMonth(String monthKey) {
    try {
      final parts = monthKey.split('-');
      final year = parts[0];
      final month = int.parse(parts[1]);
      final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[month - 1]} $year';
    } catch (e) {
      return monthKey;
    }
  }

  Widget _buildFinancialSummary(SalesProvider sales, ThemeData theme) {
    final now = DateTime.now();
    final currentMonthTransactions = sales.transactions.where((t) => 
      t.createdAt.year == now.year && t.createdAt.month == now.month).toList();

    double totalPaid = 0;
    double totalPartial = 0;
    double totalPending = 0;

    for (var t in currentMonthTransactions) {
      if (t.paymentStatus == 'Paid') totalPaid += t.amount;
      else if (t.paymentStatus == 'Partial') totalPartial += t.amount;
      else totalPending += t.amount;
    }

    final totalRevenue = totalPaid + totalPartial + totalPending;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Monthly Revenue Breakdown', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  DateFormat('MMMM yyyy').format(now),
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildRevenueRow('Total Revenue (All)', '₹${totalRevenue.toStringAsFixed(0)}', Colors.blue, theme, isBold: true),
          const Divider(height: 24),
          _buildRevenueRow('Paid Sales', '₹${totalPaid.toStringAsFixed(0)}', Colors.green, theme),
          _buildRevenueRow('Partial Payments', '₹${totalPartial.toStringAsFixed(0)}', Colors.orange, theme),
          _buildRevenueRow('Pending/Unpaid', '₹${totalPending.toStringAsFixed(0)}', Colors.red, theme),
        ],
      ),
    );
  }

  Widget _buildRevenueRow(String label, String value, Color color, ThemeData theme, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Text(label, style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              )),
            ],
          ),
          Text(value, style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            color: color,
          )),
        ],
      ),
    );
  }

  Widget _buildCommissionBreakdownHeader(CommissionProvider commission, ThemeData theme, BuildContext context) {
    final config = context.watch<SystemConfigProvider>();
    final baseRate = config.baseCommissionRate;
    final excessRate = config.excessCommissionRate;
    final overrideRate = config.teamLeaderOverrideRate;
    final poolRate = config.directorPoolRate;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.primary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Estimated Monthly Payout', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          _buildBreakdownRow('Fixed Salary', '₹${commission.monthlySalary.toStringAsFixed(0)}', commission.monthlySalary > 0, theme),
          _buildBreakdownRow('Excess Commission (${excessRate.toStringAsFixed(0)}%)', '₹${commission.excessCommission.toStringAsFixed(0)}', commission.monthlySalary > 0, theme),
          _buildBreakdownRow('Performance Comm. (${baseRate.toStringAsFixed(0)}%)', '₹${(commission.baseEarnings).toStringAsFixed(0)}', commission.monthlySalary == 0, theme),
          if (commission.teamOverride > 0)
            _buildBreakdownRow('Team Override (${overrideRate.toStringAsFixed(0)}%)', '₹${commission.teamOverride.toStringAsFixed(0)}', true, theme),
          if (commission.globalPoolShare > 0)
            _buildBreakdownRow('Global Pool Share (${poolRate.toStringAsFixed(0)}%)', '₹${commission.globalPoolShare.toStringAsFixed(0)}', true, theme),
          if (commission.approvedExpensesThisMonth > 0)
            _buildBreakdownRow('Reimbursements (Expenses)', '₹${commission.approvedExpensesThisMonth.toStringAsFixed(0)}', true, theme),
          const Divider(),
          _buildBreakdownRow('Total Estimate', '₹${commission.totalMonthlyEstimate.toStringAsFixed(0)}', true, theme, isTotal: true),
        ],
      ),
    );
  }

  Widget _buildBreakdownRow(String label, String value, bool visible, ThemeData theme, {bool isTotal = false}) {
    if (!visible) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: isTotal ? FontWeight.bold : FontWeight.normal)),
          Text(value, style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: isTotal ? FontWeight.bold : FontWeight.normal,
            color: isTotal ? (theme.brightness == Brightness.dark ? Colors.greenAccent : Colors.green) : null,
          )),
        ],
      ),
    );
  }

  Widget _buildStatCard(String title, String value, IconData icon, Color color, ThemeData theme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 16),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title, 
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value, 
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold, 
                  color: Theme.of(context).brightness == Brightness.dark && color == Colors.green ? Colors.greenAccent : color
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBanner(SalesAuthProvider auth, ThemeData theme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    String message = "Keep pushing to hit your target!";
    IconData icon = Icons.trending_up;
    Color color = Colors.blue;
    
    if (auth.isDirector) {
      message = "Leading the organization to excellence.";
      icon = Icons.stars_outlined;
      color = isDark ? Colors.orangeAccent : Colors.orange;
    } else if (auth.isTeamLeader) {
      final targetRecruits = context.read<CommissionProvider>().recruitsTarget;
      final currentRecruits = context.read<CommissionProvider>().activeRecruitsCount;
      message = "Next Level: Director ($currentRecruits/$targetRecruits recruits reached target)";
      icon = Icons.stars_outlined;
      color = theme.colorScheme.primary;
    } else {
      final target = context.read<CommissionProvider>().targetAmount;
      message = "Next Level: Team Leader (at ₹${target.toStringAsFixed(0)} sales)";
      icon = Icons.emoji_events_outlined;
      color = isDark ? Colors.greenAccent : Colors.green;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.8), color],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 12, offset: const Offset(0, 6))],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(auth.userRole, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
                Text(message, style: const TextStyle(color: Colors.white70, fontSize: 13)),
                if (auth.userProfile?['referralCode'] != null && (auth.isTeamLeader || auth.isDirector)) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.copy_all, color: Colors.white, size: 14),
                        const SizedBox(width: 4),
                        Text(
                          'REFERRAL CODE: ${auth.userProfile?['referralCode']}',
                          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 11, letterSpacing: 1),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTeamPulse(CommissionProvider commission, ThemeData theme) {
    final overrideRate = context.read<SystemConfigProvider>().teamLeaderOverrideRate;
    final teamSales = commission.teamMonthSales;
    final override = teamSales * (overrideRate / 100);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Team Pulse', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                _buildTeamStat('Team Sales', '₹${teamSales.toStringAsFixed(0)}', theme.colorScheme.primary, theme),
                _buildTeamStat('Your Override (${overrideRate.toStringAsFixed(0)}%)', '₹${override.toStringAsFixed(0)}', Theme.of(context).brightness == Brightness.dark ? Colors.greenAccent : Colors.green, theme),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTeamStat(String label, String value, Color color, ThemeData theme) {
    return Expanded(
      child: Column(
        children: [
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.hintColor)),
          const SizedBox(height: 4),
          Text(value, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color)),
        ],
      ),
    );
  }

  Widget _buildStrategicSummary(CommissionProvider commission, ThemeData theme) {
    final fmt = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 24),
        Text('Strategic Summary', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.1)),
          ),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [theme.colorScheme.primary, theme.colorScheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('Global Pool Share', style: TextStyle(color: Colors.white70, fontWeight: FontWeight.w500)),
                    Text(
                      fmt.format(commission.globalPoolShare),
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 24),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(color: Colors.white24),
                const SizedBox(height: 16),
                const Text(
                  'As Director, you share in 12% of the company\'s total revenue pool.',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(String status) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    switch (status) {
      case 'Completed':
        return isDark ? Colors.greenAccent : Colors.green;
      case 'Pending':
        return Colors.orange;
      case 'Cancelled':
        return Colors.red;
      case 'Refunded':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  void _showEditReferralCodeDialog(BuildContext context, SalesAuthProvider auth) {
    final controller = TextEditingController(text: auth.userProfile?['referralCode'] ?? '');
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Customize Referral Code'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Choose a unique 4-letter code for your team recruits.'),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              maxLength: 4,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'New Referral Code',
                hintText: 'e.g. BOSS, LEAD, JONY',
                border: OutlineInputBorder(),
                counterText: '',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () async {
              if (controller.text.length != 4) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Code must be exactly 4 letters')),
                );
                return;
              }
              final success = await auth.updateReferralCode(controller.text);
              if (mounted) {
                if (success) {
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Referral code updated!'), backgroundColor: Colors.green),
                  );
                } else if (auth.error != null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(auth.error!), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('SAVE'),
          ),
        ],
      ),
    );
  }
}
