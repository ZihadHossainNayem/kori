import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../../data/daos/budgets_dao.dart';
import '../../data/db.dart';

/// Warns once when a budget passes 80%, and again when it passes 100%.
///
/// Evaluated on the same write path that records a transaction, so no background
/// work is needed. `notifiedAtPct` on the budget row is what keeps the 80% alert
/// from firing again on every later expense that month.
class BudgetAlerts {
  BudgetAlerts(this._db, this._notifications);

  final KoriDatabase _db;
  final FlutterLocalNotificationsPlugin _notifications;

  /// Highest first: passing 100% should announce the overspend, not the warning.
  static const thresholds = [100, 80];

  static const _channelId = 'budget_alerts';

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _notifications.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        // Asked for explicitly in [requestPermission] instead, so the prompt
        // does not appear on first launch before anything needs it.
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Returns false when the user declines, in which case budgets still work —
  /// they just do not announce themselves.
  Future<bool> requestPermission() async {
    await init();

    final android = _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android != null) {
      return await android.requestNotificationsPermission() ?? false;
    }

    final ios = _notifications
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    if (ios != null) {
      return await ios.requestPermissions(alert: true, sound: true) ?? false;
    }

    return false;
  }

  /// Checks every budget for [monthKey] and announces newly crossed thresholds.
  /// Returns whether any budget newly crossed 100% — the caller's cue for a
  /// heavier in-app haptic than a plain save.
  Future<bool> evaluate(String monthKey) async {
    final budgets = await _db.budgetsDao.forMonth(monthKey);
    var overBudget = false;
    for (final budget in budgets) {
      final crossed = thresholds.firstWhere(
        (t) => budget.percent >= t && budget.notifiedAtPct < t,
        orElse: () => 0,
      );
      if (crossed == 0) continue;
      if (crossed >= 100) overBudget = true;

      // Recording money must never fail because a notification could not be
      // shown — permissions revoked, no platform under test, anything.
      // Unmarked means it will simply try again next time.
      try {
        await _announce(budget, crossed);
      } catch (_) {
        continue;
      }
      await _db.budgetsDao.markNotified(budget.id, crossed);
    }
    return overBudget;
  }

  Future<void> _announce(BudgetProgress budget, int threshold) async {
    await init();

    final over = threshold >= 100;
    final title = over
        ? '${budget.label} budget spent'
        : '${budget.label} budget at ${budget.percent}%';
    final body = over
        ? '${budget.spent.format()} of ${budget.limit.format()}. '
              'Over by ${(budget.spent - budget.limit).format()}.'
        : '${budget.spent.format()} of ${budget.limit.format()}. '
              '${budget.remaining.format()} left.';

    await _notifications.show(
      // Stable per budget and threshold, so re-announcing replaces rather than
      // stacking duplicates.
      id: budget.id * 10 + (over ? 1 : 0),
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Budget alerts',
          channelDescription:
              'Tells you when a budget is nearly or fully spent',
          importance: Importance.defaultImportance,
        ),
        iOS: DarwinNotificationDetails(),
      ),
    );
  }
}
