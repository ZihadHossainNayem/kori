import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../data/providers.dart';
import '../recurring/recurring_engine.dart';
import 'budget_alerts.dart';

final notificationsProvider = Provider<FlutterLocalNotificationsPlugin>(
  (ref) => FlutterLocalNotificationsPlugin(),
);

final budgetAlertsProvider = Provider<BudgetAlerts>(
  (ref) => BudgetAlerts(
    ref.watch(databaseProvider),
    ref.watch(notificationsProvider),
  ),
);

final recurringEngineProvider = Provider<RecurringEngine>(
  (ref) => RecurringEngine(ref.watch(databaseProvider)),
);

/// Which month the budgets screen is showing, as `YYYY-MM`.
class SelectedMonthNotifier extends Notifier<String> {
  @override
  String build() => monthKey(DateTime.now());

  void set(String month) => state = month;

  void shift(int months) {
    final year = int.parse(state.substring(0, 4));
    final month = int.parse(state.substring(5, 7));
    state = monthKey(DateTime(year, month + months, 1));
  }
}

final selectedMonthProvider = NotifierProvider<SelectedMonthNotifier, String>(
  SelectedMonthNotifier.new,
);
