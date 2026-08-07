import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/dates.dart';
import 'core/theme.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/budgets/budget_providers.dart';
import 'features/budgets/budgets_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/recurring/recurring_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/transactions/add_transaction_screen.dart';
import 'features/transactions/transactions_screen.dart';

class KoriApp extends ConsumerStatefulWidget {
  const KoriApp({super.key});

  @override
  ConsumerState<KoriApp> createState() => _KoriAppState();
}

class _KoriAppState extends ConsumerState<KoriApp>
    with WidgetsBindingObserver {
  /// Per instance, not a top-level final: a global router keeps its tab state
  /// for the life of the process and leaks it between widget tests.
  late final GoRouter _router = _buildRouter();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // After the first frame, so recurring catch-up never delays startup.
    WidgetsBinding.instance.addPostFrameCallback((_) => _catchUpRecurring());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _catchUpRecurring();
  }

  /// Replays anything the phone missed while it was off or the app closed.
  Future<void> _catchUpRecurring() async {
    final created = await ref.read(recurringEngineProvider).catchUp();
    if (created > 0) {
      await ref.read(budgetAlertsProvider).evaluate(monthKey(DateTime.now()));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Kori',
      debugShowCheckedModeBanner: false,
      theme: KoriTheme.light(),
      darkTheme: KoriTheme.dark(),
      themeMode: ThemeMode.system,
      routerConfig: _router,
    );
  }
}

/// Each tab keeps its own stack, so leaving History mid-filter and coming back
/// does not discard what the user set up.
GoRouter _buildRouter() => GoRouter(
  initialLocation: _Tab.dashboard.path,
  routes: [
    // '/' is not a branch path: it prefixes every other route, which made
    // branch matching ambiguous and opened the app on the last matching tab.
    GoRoute(path: '/', redirect: (_, _) => _Tab.dashboard.path),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => _ShellScaffold(shell: shell),
      branches: [
        for (final tab in _Tab.values)
          StatefulShellBranch(
            routes: [GoRoute(path: tab.path, builder: tab.build)],
          ),
      ],
    ),
    // Above the shell: recording money is a focused, dismissable task, not a
    // fifth tab.
    GoRoute(
      path: '/add',
      builder: (context, state) => const AddTransactionScreen(),
    ),
    GoRoute(
      path: '/budgets',
      builder: (context, state) => const BudgetsScreen(),
    ),
    GoRoute(
      path: '/recurring',
      builder: (context, state) => const RecurringScreen(),
    ),
  ],
);

enum _Tab {
  dashboard('/wallets', 'Home', Icons.account_balance_wallet_outlined,
      Icons.account_balance_wallet),
  transactions('/transactions', 'History', Icons.receipt_long_outlined,
      Icons.receipt_long),
  analytics('/analytics', 'Insights', Icons.pie_chart_outline, Icons.pie_chart),
  settings('/settings', 'Settings', Icons.settings_outlined, Icons.settings);

  const _Tab(this.path, this.label, this.icon, this.selectedIcon);

  final String path;
  final String label;
  final IconData icon;
  final IconData selectedIcon;

  Widget build(BuildContext context, GoRouterState state) => switch (this) {
        _Tab.dashboard => const DashboardScreen(),
        _Tab.transactions => const TransactionsScreen(),
        _Tab.analytics => const AnalyticsScreen(),
        _Tab.settings => const SettingsScreen(),
      };
}

class _ShellScaffold extends StatelessWidget {
  const _ShellScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.push('/add'),
        tooltip: 'Add transaction',
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: shell.currentIndex,
        onDestinationSelected: (index) => shell.goBranch(
          index,
          // Re-tapping the current tab returns it to its root.
          initialLocation: index == shell.currentIndex,
        ),
        destinations: [
          for (final tab in _Tab.values)
            NavigationDestination(
              icon: Icon(tab.icon),
              selectedIcon: Icon(tab.selectedIcon),
              label: tab.label,
            ),
        ],
      ),
    );
  }
}
