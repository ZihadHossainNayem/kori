import 'package:drift/drift.dart';

import 'categories.dart';

/// A spending ceiling for one calendar month. Spend is summed from
/// `transactions` on read, never tracked incrementally, so it cannot fall out
/// of step with the rows it describes.
///
/// SQLite counts NULLs as distinct, so the partial indexes below — not a plain
/// `UNIQUE(category_id, month_key)` — are what allow only one overall budget.
@TableIndex(name: 'idx_budgets_month', columns: {#monthKey})
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_budget_category_month '
  'ON budgets (category_id, month_key) WHERE category_id IS NOT NULL',
)
@TableIndex.sql(
  'CREATE UNIQUE INDEX idx_budget_overall_month '
  'ON budgets (month_key) WHERE category_id IS NULL',
)
class Budgets extends Table {
  IntColumn get id => integer().autoIncrement()();

  /// Null means an overall budget across every expense category.
  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.cascade,
  )();

  /// `YYYY-MM`.
  TextColumn get monthKey => text().withLength(min: 7, max: 7)();

  IntColumn get amountLimitMinor => integer()();

  /// The display currency when the budget was set.
  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// Highest threshold already notified (0, 80, 100), so the 80% alert does not
  /// fire again on every later expense that month.
  IntColumn get notifiedAtPct => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (amount_limit_minor > 0)',
    'CHECK (notified_at_pct BETWEEN 0 AND 100)',
  ];
}
