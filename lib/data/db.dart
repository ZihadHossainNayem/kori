import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

// db.g.dart is part of this library and needs these enums in scope.
import '../core/recurrence.dart';
import 'daos/analytics_dao.dart';
import 'daos/budgets_dao.dart';
import 'daos/categories_dao.dart';
import 'daos/recurring_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/transactions_dao.dart';
import 'daos/wallets_dao.dart';
import 'seed.dart';
import 'tables/budgets.dart';
import 'tables/categories.dart';
import 'tables/misc.dart';
import 'tables/recurring_rules.dart';
import 'tables/transactions.dart';
import 'tables/wallets.dart';

part 'db.g.dart';

@DriftDatabase(
  tables: [
    Wallets,
    Categories,
    Transactions,
    RecurringRules,
    Budgets,
    ExchangeRates,
    Preferences,
  ],
  daos: [
    WalletsDao,
    CategoriesDao,
    TransactionsDao,
    BudgetsDao,
    RecurringDao,
    AnalyticsDao,
    SettingsDao,
  ],
)
class KoriDatabase extends _$KoriDatabase {
  /// Opens the on-device database. Pass an [executor] in tests for an in-memory
  /// instance.
  KoriDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'kori'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (migrator) async {
          await migrator.createAll();
          await _createPartialIndexes();
          await createWalletBalancesView(this);
        },
        beforeOpen: (details) async {
          // Off by default in SQLite; without it the schema's cascade and
          // set-null rules are decoration.
          await customStatement('PRAGMA foreign_keys = ON');
          if (details.wasCreated) {
            await seedDefaults(this);
          }
        },
      );

  /// SQLite treats NULLs as distinct in a unique index, so a plain
  /// `UNIQUE(category_id, month_key)` would accept unlimited overall budgets for
  /// one month. Two partial indexes state the real rule.
  Future<void> _createPartialIndexes() async {
    await customStatement(
      'CREATE UNIQUE INDEX idx_budget_category_month '
      'ON budgets (category_id, month_key) WHERE category_id IS NOT NULL',
    );
    await customStatement(
      'CREATE UNIQUE INDEX idx_budget_overall_month '
      'ON budgets (month_key) WHERE category_id IS NULL',
    );
  }
}
