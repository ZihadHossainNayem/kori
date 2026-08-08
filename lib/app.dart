import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/dates.dart';
import 'core/theme.dart';
import 'features/analytics/analytics_screen.dart';
import 'features/budgets/budget_providers.dart';
import 'features/budgets/budgets_screen.dart';
import 'features/categories/categories_screen.dart';
import 'features/dashboard/dashboard_screen.dart';
import 'features/data/data_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/rates/rates_screen.dart';
import 'features/recurring/recurring_screen.dart';
import 'features/settings/app_lock_gate.dart';
import 'features/settings/settings_providers.dart';
import 'features/settings/settings_screen.dart';
import 'features/transactions/add_transaction_screen.dart';
import 'features/transactions/transactions_screen.dart';

class KoriApp extends ConsumerStatefulWidget {
  const KoriApp({super.key});

  @override
  ConsumerState<KoriApp> createState() => _KoriAppState();
}

class _KoriAppState extends ConsumerState<KoriApp> with WidgetsBindingObserver {
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
    final seenOnboarding = ref.watch(onboardingSeenProvider);
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    // A fresh install has no wallet and no currency, so it starts in onboarding
    // rather than on an empty dashboard.
    if (seenOnboarding.value == false) {
      return MaterialApp(
        title: 'Kori',
        debugShowCheckedModeBanner: false,
        theme: KoriTheme.light(),
        darkTheme: KoriTheme.dark(),
        themeMode: themeMode,
        home: const OnboardingScreen(),
      );
    }

    return MaterialApp.router(
      title: 'Kori',
      debugShowCheckedModeBanner: false,
      theme: KoriTheme.light(),
      darkTheme: KoriTheme.dark(),
      themeMode: themeMode,
      routerConfig: _router,
      builder: (context, child) =>
          AppLockGate(child: child ?? const SizedBox()),
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
    // fifth tab. Rising from the bottom rather than the platform's default
    // push says "this is the quick-entry sheet," not "a new page."
    GoRoute(
      path: '/add',
      pageBuilder: (context, state) => CustomTransitionPage(
        key: state.pageKey,
        child: const AddTransactionScreen(),
        transitionDuration: const Duration(milliseconds: 320),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (context, animation, _, child) => SlideTransition(
          position: Tween(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).chain(CurveTween(curve: Curves.easeOutCubic)).animate(animation),
          child: child,
        ),
      ),
    ),
    GoRoute(
      path: '/budgets',
      builder: (context, state) => const BudgetsScreen(),
    ),
    GoRoute(path: '/data', builder: (context, state) => const DataScreen()),
    GoRoute(path: '/rates', builder: (context, state) => const RatesScreen()),
    GoRoute(
      path: '/categories',
      builder: (context, state) => const CategoriesScreen(),
    ),
    GoRoute(
      path: '/recurring',
      builder: (context, state) => const RecurringScreen(),
    ),
  ],
);

enum _Tab {
  dashboard(
    '/wallets',
    'Home',
    Icons.account_balance_wallet_outlined,
    Icons.account_balance_wallet,
  ),
  transactions(
    '/transactions',
    'History',
    Icons.receipt_long_outlined,
    Icons.receipt_long,
  ),
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

class _ShellScaffold extends StatefulWidget {
  const _ShellScaffold({required this.shell});

  final StatefulNavigationShell shell;

  @override
  State<_ShellScaffold> createState() => _ShellScaffoldState();
}

class _ShellScaffoldState extends State<_ShellScaffold> {
  bool _fabVisible = true;

  /// Amounts are right-aligned on every screen, which is exactly where the FAB
  /// sits. Yielding while the user scrolls down keeps figures readable without
  /// giving up a one-tap way to record money.
  void _onScroll(UserScrollNotification notification) {
    final visible = switch (notification.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _fabVisible,
    };
    if (visible != _fabVisible) setState(() => _fabVisible = visible);
  }

  @override
  Widget build(BuildContext context) {
    final shell = widget.shell;

    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          _onScroll(notification);
          return false;
        },
        child: shell,
      ),
      floatingActionButton: AnimatedSlide(
        offset: _fabVisible ? Offset.zero : const Offset(0, 2),
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
        child: AnimatedOpacity(
          opacity: _fabVisible ? 1 : 0,
          duration: const Duration(milliseconds: 200),
          child: FloatingActionButton(
            onPressed: () => context.push('/add'),
            tooltip: 'Add transaction',
            child: const Icon(Icons.add),
          ),
        ),
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
