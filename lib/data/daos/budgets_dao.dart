import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../db.dart';
import '../tables/budgets.dart';
import '../tables/categories.dart';
import '../tables/transactions.dart';

part 'budgets_dao.g.dart';

/// A budget with the month's spend against it.
class BudgetProgress {
  const BudgetProgress({
    required this.id,
    required this.monthKey,
    required this.limit,
    required this.spent,
    required this.notifiedAtPct,
    this.categoryId,
    this.categoryName,
    this.categoryIcon,
    this.categoryColor,
    this.uncountedInOtherCurrencies = 0,
  });

  final int id;
  final String monthKey;
  final Money limit;
  final Money spent;
  final int notifiedAtPct;

  /// Null for an overall budget across every expense category.
  final int? categoryId;
  final String? categoryName;
  final String? categoryIcon;
  final int? categoryColor;

  /// Expenses in the period the budget could not count, for want of a shared
  /// currency. Surfaced rather than hidden so the bar is never quietly wrong.
  final int uncountedInOtherCurrencies;

  bool get isOverall => categoryId == null;
  String get label => categoryName ?? 'Everything';

  Money get remaining => limit - spent;
  bool get isOver => spent > limit;

  /// 0.0 to 1.0 for the bar; overspending clamps rather than overflowing.
  double get fraction {
    if (limit.minor <= 0) return 0;
    final raw = spent.minor / limit.minor;
    return raw.clamp(0.0, 1.0);
  }

  /// Whole percent spent, uncapped, for labels and alert thresholds.
  int get percent =>
      limit.minor <= 0 ? 0 : (spent.minor * 100 / limit.minor).floor();
}

@DriftAccessor(tables: [Budgets, Categories, Transactions])
class BudgetsDao extends DatabaseAccessor<KoriDatabase> with _$BudgetsDaoMixin {
  BudgetsDao(super.attachedDatabase);

  static const _progressSql = '''
SELECT
  budgets.id,
  budgets.category_id,
  budgets.month_key,
  budgets.amount_limit_minor,
  budgets.currency,
  budgets.notified_at_pct,
  categories.name AS category_name,
  categories.icon AS category_icon,
  categories.color AS category_color,
  COALESCE((
    SELECT SUM(t.amount_minor) FROM transactions t
    WHERE t.type = 'expense'
      AND SUBSTR(t.date, 1, 7) = budgets.month_key
      AND t.currency = budgets.currency
      AND (budgets.category_id IS NULL OR t.category_id = budgets.category_id)
  ), 0) AS spent_minor,
  COALESCE((
    SELECT COUNT(*) FROM transactions t
    WHERE t.type = 'expense'
      AND SUBSTR(t.date, 1, 7) = budgets.month_key
      AND t.currency != budgets.currency
      AND (budgets.category_id IS NULL OR t.category_id = budgets.category_id)
  ), 0) AS uncounted
FROM budgets
LEFT JOIN categories ON categories.id = budgets.category_id
WHERE budgets.month_key = ?
ORDER BY budgets.category_id IS NULL DESC, categories.sort_order, categories.id
''';

  Stream<List<BudgetProgress>> watchForMonth(String monthKey) {
    return customSelect(
      _progressSql,
      variables: [Variable<String>(monthKey)],
      readsFrom: {budgets, categories, transactions},
    ).watch().map((rows) => rows.map(_map).toList());
  }

  Future<List<BudgetProgress>> forMonth(String monthKey) async {
    final rows = await customSelect(
      _progressSql,
      variables: [Variable<String>(monthKey)],
      readsFrom: {budgets, categories, transactions},
    ).get();
    return rows.map(_map).toList();
  }

  /// One budget per category per month, and one overall — enforced by partial
  /// unique indexes, so this replaces rather than duplicating.
  Future<void> setBudget({
    required String monthKey,
    required Money limit,
    int? categoryId,
  }) async {
    final existing = await _find(monthKey, categoryId);
    if (existing == null) {
      await into(budgets).insert(
        BudgetsCompanion.insert(
          monthKey: monthKey,
          amountLimitMinor: limit.minor,
          currency: limit.currency,
          categoryId: Value(categoryId),
        ),
      );
      return;
    }

    // Raising a limit re-arms the alerts the old limit already fired.
    final resetAlerts = limit.minor != existing.amountLimitMinor;
    await (update(budgets)..where((b) => b.id.equals(existing.id))).write(
      BudgetsCompanion(
        amountLimitMinor: Value(limit.minor),
        currency: Value(limit.currency),
        notifiedAtPct: resetAlerts ? const Value(0) : const Value.absent(),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  Future<int> deleteBudget(int id) =>
      (delete(budgets)..where((b) => b.id.equals(id))).go();

  /// Records the highest threshold already announced, so an alert fires once.
  Future<int> markNotified(int id, int percent) =>
      (update(budgets)..where((b) => b.id.equals(id))).write(
        BudgetsCompanion(
          notifiedAtPct: Value(percent),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Copies every budget from [from] into [to], skipping any already set.
  Future<int> copyMonth({required String from, required String to}) async {
    final source = await (select(budgets)..where((b) => b.monthKey.equals(from)))
        .get();
    final target = await (select(budgets)..where((b) => b.monthKey.equals(to)))
        .get();
    final taken = target.map((b) => b.categoryId).toSet();

    final missing =
        source.where((b) => !taken.contains(b.categoryId)).toList();
    if (missing.isEmpty) return 0;

    await batch((batch) {
      batch.insertAll(budgets, [
        for (final budget in missing)
          BudgetsCompanion.insert(
            monthKey: to,
            amountLimitMinor: budget.amountLimitMinor,
            currency: budget.currency,
            categoryId: Value(budget.categoryId),
          ),
      ]);
    });
    return missing.length;
  }

  Future<Budget?> _find(String monthKey, int? categoryId) {
    final query = select(budgets)..where((b) => b.monthKey.equals(monthKey));
    if (categoryId == null) {
      query.where((b) => b.categoryId.isNull());
    } else {
      query.where((b) => b.categoryId.equals(categoryId));
    }
    return query.getSingleOrNull();
  }

  BudgetProgress _map(QueryRow row) {
    final currency = row.read<String>('currency');
    return BudgetProgress(
      id: row.read<int>('id'),
      monthKey: row.read<String>('month_key'),
      limit: Money(row.read<int>('amount_limit_minor'), currency),
      spent: Money(row.read<int>('spent_minor'), currency),
      notifiedAtPct: row.read<int>('notified_at_pct'),
      categoryId: row.readNullable<int>('category_id'),
      categoryName: row.readNullable<String>('category_name'),
      categoryIcon: row.readNullable<String>('category_icon'),
      categoryColor: row.readNullable<int>('category_color'),
      uncountedInOtherCurrencies: row.read<int>('uncounted'),
    );
  }
}
