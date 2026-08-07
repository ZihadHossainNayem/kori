import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../db.dart';
import '../tables/categories.dart';
import '../tables/transactions.dart';

part 'analytics_dao.g.dart';

/// Whether a series steps by day or by month.
enum Granularity { day, month }

class CategorySlice {
  const CategorySlice({
    required this.name,
    required this.icon,
    required this.color,
    required this.total,
    this.categoryId,
  });

  final int? categoryId;
  final String name;
  final String icon;
  final int color;
  final Money total;
}

class PeriodTotal {
  const PeriodTotal({
    required this.bucket,
    required this.income,
    required this.expense,
  });

  /// `YYYY-MM-DD` or `YYYY-MM`, matching the requested granularity.
  final String bucket;
  final Money income;
  final Money expense;

  Money get net => income - expense;
}

class WeekdayTotal {
  const WeekdayTotal({
    required this.weekday,
    required this.expense,
    required this.count,
  });

  /// 1 = Monday through 7 = Sunday, matching DateTime.
  final int weekday;
  final Money expense;
  final int count;
}

class AnalyticsTotals {
  const AnalyticsTotals({
    required this.income,
    required this.expense,
    required this.uncounted,
  });

  final Money income;
  final Money expense;

  /// Rows left out because they are in another currency. Shown, never hidden.
  final int uncounted;

  Money get net => income - expense;
}

/// Every figure here is aggregated in SQL rather than in Dart, so a year of
/// history costs one indexed scan instead of loading every row into memory.
///
/// All queries take a single currency: converting inside SQL would need rates we
/// deliberately keep out of the database, so rows in other currencies are counted
/// and reported instead of being silently mixed in.
@DriftAccessor(tables: [Transactions, Categories])
class AnalyticsDao extends DatabaseAccessor<KoriDatabase>
    with _$AnalyticsDaoMixin {
  AnalyticsDao(super.attachedDatabase);

  Stream<AnalyticsTotals> watchTotals({
    required String from,
    required String to,
    required String currency,
  }) {
    return customSelect(
      '''
SELECT
  COALESCE(SUM(CASE WHEN type = 'income'  AND currency = ?3
                    THEN amount_minor END), 0) AS income,
  COALESCE(SUM(CASE WHEN type = 'expense' AND currency = ?3
                    THEN amount_minor END), 0) AS expense,
  COALESCE(SUM(CASE WHEN type != 'transfer' AND currency != ?3
                    THEN 1 END), 0) AS uncounted
FROM transactions
WHERE date BETWEEN ?1 AND ?2
''',
      variables: [
        Variable<String>(from),
        Variable<String>(to),
        Variable<String>(currency),
      ],
      readsFrom: {transactions},
    ).watchSingle().map(
          (row) => AnalyticsTotals(
            income: Money(row.read<int>('income'), currency),
            expense: Money(row.read<int>('expense'), currency),
            uncounted: row.read<int>('uncounted'),
          ),
        );
  }

  /// Expenses grouped by category, largest first. A null category becomes
  /// "Uncategorised" rather than being dropped.
  Stream<List<CategorySlice>> watchCategoryBreakdown({
    required String from,
    required String to,
    required String currency,
  }) {
    return customSelect(
      '''
SELECT
  categories.id AS category_id,
  categories.name AS name,
  categories.icon AS icon,
  categories.color AS color,
  SUM(transactions.amount_minor) AS total
FROM transactions
LEFT JOIN categories ON categories.id = transactions.category_id
WHERE transactions.type = 'expense'
  AND transactions.currency = ?3
  AND transactions.date BETWEEN ?1 AND ?2
GROUP BY categories.id
ORDER BY total DESC
''',
      variables: [
        Variable<String>(from),
        Variable<String>(to),
        Variable<String>(currency),
      ],
      readsFrom: {transactions, categories},
    ).watch().map(
          (rows) => rows
              .map(
                (row) => CategorySlice(
                  categoryId: row.readNullable<int>('category_id'),
                  name: row.readNullable<String>('name') ?? 'Uncategorised',
                  icon: row.readNullable<String>('icon') ?? 'tag',
                  color: row.readNullable<int>('color') ?? 0xFF6B7280,
                  total: Money(row.read<int>('total'), currency),
                ),
              )
              .toList(),
        );
  }

  /// Income and expense per bucket, oldest first. Buckets with no activity are
  /// absent; callers fill gaps so a quiet month still shows as zero.
  Stream<List<PeriodTotal>> watchPeriodTotals({
    required String from,
    required String to,
    required String currency,
    required Granularity granularity,
  }) {
    final length = granularity == Granularity.month ? 7 : 10;
    return customSelect(
      '''
SELECT
  SUBSTR(date, 1, $length) AS bucket,
  COALESCE(SUM(CASE WHEN type = 'income'  THEN amount_minor END), 0) AS income,
  COALESCE(SUM(CASE WHEN type = 'expense' THEN amount_minor END), 0) AS expense
FROM transactions
WHERE type != 'transfer'
  AND currency = ?3
  AND date BETWEEN ?1 AND ?2
GROUP BY bucket
ORDER BY bucket
''',
      variables: [
        Variable<String>(from),
        Variable<String>(to),
        Variable<String>(currency),
      ],
      readsFrom: {transactions},
    ).watch().map(
          (rows) => rows
              .map(
                (row) => PeriodTotal(
                  bucket: row.read<String>('bucket'),
                  income: Money(row.read<int>('income'), currency),
                  expense: Money(row.read<int>('expense'), currency),
                ),
              )
              .toList(),
        );
  }

  /// Expenses by day of week, to expose a habit a date series hides.
  Stream<List<WeekdayTotal>> watchWeekdayTotals({
    required String from,
    required String to,
    required String currency,
  }) {
    return customSelect(
      '''
SELECT
  CAST(STRFTIME('%w', date) AS INTEGER) AS dow,
  SUM(amount_minor) AS total,
  COUNT(*) AS entries
FROM transactions
WHERE type = 'expense'
  AND currency = ?3
  AND date BETWEEN ?1 AND ?2
GROUP BY dow
ORDER BY dow
''',
      variables: [
        Variable<String>(from),
        Variable<String>(to),
        Variable<String>(currency),
      ],
      readsFrom: {transactions},
    ).watch().map(
          (rows) => rows.map((row) {
            // SQLite counts Sunday as 0; DateTime counts Monday as 1.
            final sqliteDow = row.read<int>('dow');
            return WeekdayTotal(
              weekday: sqliteDow == 0 ? 7 : sqliteDow,
              expense: Money(row.read<int>('total'), currency),
              count: row.read<int>('entries'),
            );
          }).toList()
            ..sort((a, b) => a.weekday.compareTo(b.weekday)),
        );
  }
}
