import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../../providers/leaderboard_provider.dart';
import '../../providers/auth_provider.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final NumberFormat _currencyFormat = NumberFormat.currency(symbol: '₹', decimalDigits: 0);
  
  bool _isAllTime = false;
  late DateTime _selectedMonth;
  final List<DateTime> _months = [];

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _selectedMonth = DateTime(now.year, now.month, 1);
    for (int i = 0; i < 24; i++) { // show up to 2 years history
      _months.add(DateTime(now.year, now.month - i, 1));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchData();
    });
  }

  void _fetchData() {
    context.read<LeaderboardProvider>().fetchLeaderboard(
      isAllTime: _isAllTime,
      selectedMonth: _selectedMonth,
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: theme.cardColor,
        border: Border(bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.1))),
      ),
      child: Row(
        children: [
          const Icon(Icons.filter_list, size: 20),
          const SizedBox(width: 8),
          const Text('Timeframe: ', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(width: 8),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _isAllTime ? 'All Time' : DateFormat('MMM yyyy').format(_selectedMonth),
                isExpanded: true,
                items: [
                  const DropdownMenuItem(value: 'All Time', child: Text('All Time')),
                  ..._months.map((m) {
                    final str = DateFormat('MMM yyyy').format(m);
                    final nowStr = DateFormat('MMM yyyy').format(DateTime.now());
                    return DropdownMenuItem(
                      value: str, 
                      child: Text(str == nowStr ? 'This Month ($str)' : str)
                    );
                  }),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      if (val == 'All Time') {
                        _isAllTime = true;
                      } else {
                        _isAllTime = false;
                        _selectedMonth = _months.firstWhere((m) => DateFormat('MMM yyyy').format(m) == val);
                      }
                    });
                    _fetchData();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final currentUserId = context.read<SalesAuthProvider>().userId;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    return Scaffold(
      appBar: AppBar(
        title: const Text('Sales Leaderboard'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _fetchData,
          )
        ],
      ),
      body: Column(
        children: [
          _buildFilterBar(theme),
          Expanded(
            child: Consumer<LeaderboardProvider>(
              builder: (context, provider, child) {
                if (provider.isLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (provider.error != null) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.error_outline, color: theme.colorScheme.error, size: 64),
                        const SizedBox(height: 24),
                        Text(provider.error!, style: theme.textTheme.titleMedium),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: _fetchData,
                          child: const Text('Retry'),
                        ),
                      ],
                    ),
                  );
                }
                
                if (provider.entries.isEmpty) {
                  return Center(
                    child: Text('No data available for the selected timeframe.', style: theme.textTheme.bodyLarge?.copyWith(color: theme.disabledColor)),
                  );
                }

 
          return ListView.builder(
            padding: const EdgeInsets.all(20.0),
            itemCount: provider.entries.length,
            itemBuilder: (context, index) {
              final entry = provider.entries[index];
              final rank = index + 1;
              final isCurrentUser = entry.agentId == currentUserId;
              
              Widget medalIcon;
              Color highlightColor;
              String rankText = '#$rank';
              
              if (rank == 1) {
                medalIcon = Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Colors.amber, shape: BoxShape.circle),
                  child: const Icon(Icons.emoji_events, color: Colors.white, size: 24),
                );
                highlightColor = Colors.amber;
              } else if (rank == 2) {
                medalIcon = Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFC0C0C0), shape: BoxShape.circle),
                  child: const Icon(Icons.emoji_events, color: Colors.white, size: 24),
                );
                highlightColor = Colors.grey;
              } else if (rank == 3) {
                medalIcon = Container(
                  padding: const EdgeInsets.all(8),
                  decoration: const BoxDecoration(color: Color(0xFFCD7F32), shape: BoxShape.circle),
                  child: const Icon(Icons.emoji_events, color: Colors.white, size: 24),
                );
                highlightColor = Colors.brown;
              } else {
                medalIcon = CircleAvatar(
                  backgroundColor: theme.dividerColor.withValues(alpha: 0.1),
                  radius: 20,
                  child: Text(
                    rankText,
                    style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                  ),
                );
                highlightColor = Colors.transparent;
              }
              
              return Container(
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: isCurrentUser ? theme.colorScheme.primary.withValues(alpha: 0.05) : theme.cardColor,
                  borderRadius: BorderRadius.circular(20),
                  border: isCurrentUser 
                    ? Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.3), width: 2)
                    : Border.all(color: theme.dividerColor.withValues(alpha: 0.1)),
                  boxShadow: rank <= 3 ? [
                    BoxShadow(color: highlightColor.withValues(alpha: 0.2), blurRadius: 15, offset: const Offset(0, 8))
                  ] : [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 10, offset: const Offset(0, 4))
                  ],
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                  leading: medalIcon,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          entry.agentName,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: rank <= 3 || isCurrentUser ? FontWeight.bold : FontWeight.w600,
                            fontSize: rank <= 3 ? 18 : 16,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isCurrentUser) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'YOU',
                            style: TextStyle(fontSize: 10, color: theme.colorScheme.onPrimary, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ]
                    ],
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(entry.role, style: theme.textTheme.bodySmall?.copyWith(letterSpacing: 0.5)),
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        _currencyFormat.format(entry.totalSales),
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                          color: rank <= 3 ? highlightColor : (isDark ? theme.colorScheme.secondary : Colors.green.shade700),
                        ),
                      ),
                      Text('SALES', style: theme.textTheme.bodySmall?.copyWith(fontSize: 9, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
          ),
        ],
      ),
    );
  }
}
