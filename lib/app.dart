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
    final themeMode = ref.watch(themeModeProvider).value ?? ThemeMode.dark;

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
    // A pushed sheet, not a fifth tab — rising from the bottom says "quick
    // entry," not "new page."
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
  /// Hides on scroll-down, returns on the first flick up — a long list is the
  /// one time the bar is pure obstruction.
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
      // Keeps its slot while hidden and slides fully off — 1.4, not 1.0,
      // carries the shadow away too.
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

/// Every gap in the bar spaces off these two numbers, not separately eyeballed
/// padding — element inset is exactly half the vertical one, which is what
/// keeps every gap equal *and* keeps the end pill's corner concentric with
/// the bar's own.
const _navVerticalInset = 6.0;
const _navElementInset = _navVerticalInset / 2;

/// The one action, centred between the tab pairs — fill and position say
/// "verb," never "fifth tab."
class _AddAction extends StatelessWidget {
  const _AddAction({required this.onTap});

  static const diameter = 44.0;
  static const slot = diameter + _navElementInset * 2;

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: _navElementInset),
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

/// A floating frosted pill — real backdrop blur, not a flat tint, is what
/// sells "floating" over "painted on."
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

    // Android reports a zero-width window on the first frame — nothing to
    // lay out against yet.
    final screenWidth = MediaQuery.sizeOf(context).width;
    if (screenWidth <= 0) return const SizedBox.shrink();

    // Hugs its tabs rather than stretching edge to edge — most of what reads
    // as floating. Bounded so a narrow phone shrinks tabs, not overflows.
    final itemWidth = math.max(
      44.0,
      math.min(66.0, (screenWidth - 44 - _AddAction.slot) / _Tab.values.length),
    );

    // Tinted from onSurface, not a fixed grey, so one value tracks both
    // themes — dark needs the heavier alpha since its bar is already grey.
    final indicatorFill = scheme.onSurface.withValues(
      alpha: isLight ? 0.08 : 0.16,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: gap),
      // heightFactor is load-bearing: without it Align claims the full
      // height offered and the Scaffold reads the bar as full-screen tall.
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: 1,
        child: DecoratedBox(
          // Outside the clip so it isn't cut off; two layers — contact plus
          // ambient — since one blur alone reads as a smudge.
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
                // Makes up the rest of bar-radius-minus-pill-radius so the
                // two corners sit concentric — see _navVerticalInset above.
                padding: const EdgeInsets.symmetric(
                  horizontal: _navVerticalInset - _navElementInset,
                ),
                decoration: BoxDecoration(
                  // A step off the page in dark mode, since a shadow alone is
                  // swallowed by black; light mode already has the border.
                  color:
                      (isLight ? scheme.surface : scheme.surfaceContainerHigh)
                          .withValues(alpha: 0.88),
                  border: Border.all(color: scheme.outlineVariant),
                  borderRadius: shape,
                ),
                // Capped, not clipped — the bar's fixed height would cut off
                // labels under large text scaling.
                child: MediaQuery.withClampedTextScaling(
                  maxScaleFactor: 1.3,
                  child: Stack(
                    children: [
                      // One shared pill gliding to the active tab, behind the
                      // row — crossing the middle, it glides clean under the
                      // raised +.
                      AnimatedPositioned(
                        duration: _navMotion,
                        curve: Curves.easeOutCubic,
                        top: _navVerticalInset,
                        height: _height - _navVerticalInset * 2,
                        left: _indicatorLeft(currentIndex, itemWidth),
                        width: itemWidth - _navElementInset * 2,
                        // A stadium, not a fixed radius, so it rounds off
                        // whichever side is shorter.
                        child: DecoratedBox(
                          decoration: ShapeDecoration(
                            color: indicatorFill,
                            shape: const StadiumBorder(),
                          ),
                        ),
                      ),
                      Row(
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

/// The indicator's x for [index] — tabs past the + shift right by its slot,
/// a real gap in the row.
double _indicatorLeft(int index, double itemWidth) =>
    (index < 2 ? index * itemWidth : index * itemWidth + _AddAction.slot) +
    _navElementInset;

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

    return SizedBox(
      width: width,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: _navElementInset,
          vertical: _navVerticalInset,
        ),
        child: Material(
          // Just the ripple's clip now — the fill lives in the shared
          // sliding indicator behind this row.
          color: Colors.transparent,
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
                // One line always — a wrapped label would be clipped, not
                // just tight, given the bar's fixed height.
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
