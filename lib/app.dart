import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
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
  /// Reading a long list is the one time the bar is pure obstruction, so it
  /// leaves on the way down and comes straight back on the first flick up.
  bool _navVisible = true;

  StatefulNavigationShell get shell => widget.shell;

  void _goBranch(int index) {
    if (index != shell.currentIndex) HapticFeedback.selectionClick();
    // A tab arrives at its own scroll position, which says nothing about
    // whether the bar should be hidden — always start it visible.
    setState(() => _navVisible = true);
    shell.goBranch(
      index,
      // Re-tapping the current tab returns it to its root.
      initialLocation: index == shell.currentIndex,
    );
  }

  bool _onScroll(UserScrollNotification n) {
    // depth 0 only, so a horizontal carousel inside a page cannot drive it.
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    // A page that barely scrolls has nothing to reclaim, and hiding the bar on
    // its few pixels of travel just makes it flicker.
    if (n.metrics.maxScrollExtent < 120) {
      if (!_navVisible) setState(() => _navVisible = true);
      return false;
    }

    final visible = switch (n.direction) {
      ScrollDirection.reverse => false,
      ScrollDirection.forward => true,
      ScrollDirection.idle => _navVisible,
    };
    if (visible != _navVisible) setState(() => _navVisible = visible);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // The bar is translucent, so content should be visible — faintly,
      // blurred — scrolling underneath it, not stop dead at its top edge.
      extendBody: true,
      body: NotificationListener<UserScrollNotification>(
        onNotification: _onScroll,
        child: shell,
      ),
      // Keeps its slot in the layout while hidden and slides out of it, so the
      // page never reflows. 1.4 rather than 1.0 carries the shadow off too.
      bottomNavigationBar: AnimatedSlide(
        offset: _navVisible ? Offset.zero : const Offset(0, 1.4),
        duration: _navMotion,
        curve: Curves.easeOutCubic,
        child: _NavBar(
          currentIndex: shell.currentIndex,
          onTap: _goBranch,
          onAdd: () => context.push('/add'),
        ),
      ),
    );
  }
}

/// One duration for everything the bar does, so hiding and resizing never look
/// like two separate animations that happen to overlap.
const _navMotion = Duration(milliseconds: 240);

/// The one action, as a filled circle at the centre of the nav pill, between
/// the two tab pairs. Fill and position both say "verb" — it is never
/// mistaken for a fifth tab, and it costs the bar no second floating object
/// to stack against.
class _AddAction extends StatelessWidget {
  const _AddAction({required this.onTap});

  static const diameter = 44.0;
  static const slot = diameter + 12; // the gap that separates it from the tabs

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Tooltip(
        message: 'Add transaction',
        child: Material(
          color: scheme.primary,
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox.square(
              dimension: diameter,
              child: Icon(Icons.add, size: 20, color: scheme.onPrimary),
            ),
          ),
        ),
      ),
    );
  }
}

/// A floating frosted pill, inset from the edges so content runs past it on
/// every side. Real backdrop blur rather than a flat tint — a translucent bar
/// over a solid one is what sells it as floating rather than painted on.
class _NavBar extends StatelessWidget {
  const _NavBar({
    required this.currentIndex,
    required this.onTap,
    required this.onAdd,
  });

  static const _height = 56.0;

  final int currentIndex;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isLight = theme.brightness == Brightness.light;
    final shape = BorderRadius.circular(_height / 2);

    // Clears the home indicator where there is one; keeps a deliberate gap
    // where there is not, so the pill never looks stuck to the bezel.
    final gap = math.max(MediaQuery.paddingOf(context).bottom, 12.0);

    // Android reports a zero-width window on the first frame, which makes every
    // width below negative. Nothing to lay out against until there is a size.
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth <= 0) return const SizedBox.shrink();

    // The bar hugs its tabs and centres rather than stretching edge to edge —
    // that inset is most of what makes it read as floating. Bounded so a narrow
    // phone shrinks the tabs instead of overflowing.
    final itemWidth = math.max(
      44.0,
      math.min(66.0, (screenWidth - 44 - _AddAction.slot) / _Tab.values.length),
    );

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      // Loosens the Scaffold's tight width so the bar can size to its tabs.
      // heightFactor is load-bearing: without it Align takes every pixel of
      // height offered and the Scaffold reads the bar as full-screen tall.
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: DecoratedBox(
          // Outside the clip, which would cut a shadow away. Two layers —
          // contact plus ambient; one blur alone reads as a grey smudge.
          decoration: BoxDecoration(
            borderRadius: shape,
            boxShadow: [
              BoxShadow(
                color: scheme.shadow.withValues(alpha: isLight ? 0.06 : 0.5),
                blurRadius: 4,
                offset: const Offset(0, 1),
              ),
              BoxShadow(
                color: scheme.shadow.withValues(alpha: isLight ? 0.14 : 0.6),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: shape,
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                height: _height,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                decoration: BoxDecoration(
                  // A step off the page in dark mode, so the bar separates from
                  // black without relying on a shadow that black swallows. In
                  // light mode the page is already white, so the border does it.
                  color:
                      (isLight ? scheme.surface : scheme.surfaceContainerHigh)
                          .withValues(alpha: 0.88),
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: shape,
                ),
                // The bar is a fixed height, so unbounded text scaling would
                // clip the labels outright. Capped rather than clipped.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final tab in _Tab.values.take(2))
                        _NavItem(
                          tab: tab,
                          current: currentIndex,
                          onTap: onTap,
                          width: itemWidth,
                        ),
                      _AddAction(onTap: onAdd),
                      for (final tab in _Tab.values.skip(2))
                        _NavItem(
                          tab: tab,
                          current: currentIndex,
                          onTap: onTap,
                          width: itemWidth,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.tab,
    required this.current,
    required this.onTap,
    required this.width,
  });

  final _Tab tab;
  final int current;
  final ValueChanged<int> onTap;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final index = _Tab.values.indexOf(tab);
    final selected = index == current;
    // onSurface, not primary: green is reserved for money, so the active tab
    // is carried by ink and weight rather than by the accent.
    final colour = selected ? scheme.onSurface : scheme.onSurfaceVariant;

    // Tinted from onSurface rather than a fixed grey, so one value tracks both
    // themes. Dark needs the heavier step — the bar it sits on is already grey.
    final fill = scheme.onSurface.withValues(
      alpha: theme.brightness == Brightness.light ? 0.08 : 0.16,
    );

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
        child: Material(
          // The indicator, and the surface the ripple is clipped to — one
          // shape doing both, so the tap target and the fill can never drift.
          color: selected ? fill : Colors.transparent,
          shape: const StadiumBorder(),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () => onTap(index),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  selected ? tab.selectedIcon : tab.icon,
                  color: colour,
                  size: 20,
                ),
                const SizedBox(height: 2),
                // One line, always. The bar is a fixed height, so a label that
                // wrapped would be clipped rather than merely tight.
                Text(
                  tab.label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colour,
                    fontSize: 10,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
