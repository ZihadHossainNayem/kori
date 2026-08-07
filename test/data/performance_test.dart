import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/dates.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/daos/analytics_dao.dart';
import 'package:kori/data/daos/transactions_dao.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/transactions.dart';

/// Guards the queries that back the screens against a history that has grown.
///
/// The budgets are generous — this catches an accidental full scan or an N+1,
/// not small regressions, and a loaded CI machine should not fail it.
void main() {
  late KoriDatabase db;
  const transactionCount = 5000;

  setUpAll(() async {
    db = KoriDatabase(NativeDatabase.memory());

    final wallets = [
      for (var index = 0; index < 4; index++)
        await db.walletsDao.createWallet(
          WalletsCompanion.insert(
            name: 'Wallet $index',
            currency: 'USD',
            color: 0xFF0D9488,
            initialBalanceMinor: const Value(1000000),
          ),
        ),
    ];
    final categories = await db.select(db.categories).get();
    final expenseCategories = categories
        .where((c) => c.type.name == 'expense')
        .toList();

    // Three years of daily-ish activity, spread across wallets and categories.
    await db.batch((batch) {
      for (var index = 0; index < transactionCount; index++) {
        final date = DateTime(2024, 1, 1).add(Duration(hours: index * 5));
        batch.insert(
          db.transactions,
          TransactionsCompanion.insert(
            walletId: wallets[index % wallets.length],
            type: index % 7 == 0
                ? TransactionType.income
                : TransactionType.expense,
            amountMinor: 500 + index % 90000,
            currency: 'USD',
            date: dayKey(date),
            categoryId: Value(
              expenseCategories[index % expenseCategories.length].id,
            ),
            note: Value('Entry $index'),
          ),
        );
      }
    });
  });

  tearDownAll(() async {
    await db.close();
  });

  Future<Duration> time(Future<void> Function() action) async {
    final stopwatch = Stopwatch()..start();
    await action();
    return stopwatch.elapsed;
  }

  test('the seed really is $transactionCount rows', () async {
    expect(await db.select(db.transactions).get(), hasLength(transactionCount));
  });

  test('a wallet balance stays fast', () async {
    final elapsed = await time(() async {
      final balance = await db.walletsDao.balanceOf(1);
      expect(balance, isNotNull);
    });
    expect(elapsed.inMilliseconds, lessThan(300));
  });

  test('the dashboard reads every wallet balance at once', () async {
    final elapsed = await time(() async {
      final wallets = await db.walletsDao.watchWallets().first;
      expect(wallets, hasLength(4));
    });
    expect(elapsed.inMilliseconds, lessThan(500));
  });

  test('the history screen pages instead of loading everything', () async {
    final elapsed = await time(() async {
      final page = await db.transactionsDao.watchEntries(limit: 50).first;
      expect(page, hasLength(50));
    });
    // A page must not cost what the whole table costs.
    expect(elapsed.inMilliseconds, lessThan(200));
  });

  test('searching a note stays usable', () async {
    final elapsed = await time(() async {
      final results = await db.transactionsDao
          .watchEntries(
            filter: const TransactionFilter(search: 'Entry 4999'),
            limit: 50,
          )
          .first;
      expect(results, isNotEmpty);
    });
    expect(elapsed.inMilliseconds, lessThan(500));
  });

  test('a month of analytics is aggregated in SQL, not in Dart', () async {
    final elapsed = await time(() async {
      final slices = await db.analyticsDao
          .watchCategoryBreakdown(
            from: '2025-06-01',
            to: '2025-06-30',
            currency: 'USD',
          )
          .first;
      expect(slices, isNotEmpty);
    });
    expect(elapsed.inMilliseconds, lessThan(300));
  });

  test('three years of monthly totals stays fast', () async {
    final elapsed = await time(() async {
      final periods = await db.analyticsDao
          .watchPeriodTotals(
            from: '2024-01-01',
            to: '2026-12-31',
            currency: 'USD',
            granularity: Granularity.month,
          )
          .first;
      expect(periods.length, greaterThan(20));
    });
    expect(elapsed.inMilliseconds, lessThan(300));
  });

  test('budget spend is summed without loading the rows', () async {
    await db.budgetsDao.setBudget(
      monthKey: '2025-06',
      limit: const Money(1000000, 'USD'),
    );

    final elapsed = await time(() async {
      final budgets = await db.budgetsDao.forMonth('2025-06');
      expect(budgets.single.spent.minor, greaterThan(0));
    });
    expect(elapsed.inMilliseconds, lessThan(300));
  });

  test('a full export completes in reasonable time', () async {
    final elapsed = await time(() async {
      final rows = await db.transactionsDao.watchEntries().first;
      expect(rows, hasLength(transactionCount));
    });
    // Reading the lot is allowed to be slower — it happens once, on demand.
    expect(elapsed.inMilliseconds, lessThan(3000));
  });
}
