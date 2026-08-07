import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/categories.dart';
import 'package:kori/data/tables/transactions.dart';

void main() {
  late KoriDatabase db;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<List<String>> namesOf(
    CategoryType type, {
    bool includeArchived = false,
  }) async {
    final rows = await db.categoriesDao
        .watchByType(type, includeArchived: includeArchived)
        .first;
    return [for (final row in rows) row.name];
  }

  Future<int> categoryNamed(String name) async {
    final all = await db.select(db.categories).get();
    return all.firstWhere((c) => c.name == name).id;
  }

  test('a new category lands after the seeded ones', () async {
    await db.categoriesDao.createCategory(
      CategoriesCompanion.insert(
        name: 'School fees',
        type: CategoryType.expense,
        color: 0xFF3B82F6,
        sortOrder: const Value(500),
      ),
    );

    expect((await namesOf(CategoryType.expense)).last, 'School fees');
  });

  test('reorder writes the order it was given', () async {
    final before = await db.categoriesDao
        .watchByType(CategoryType.income)
        .first;
    final ids = [for (final row in before) row.id].reversed.toList();

    await db.categoriesDao.reorder(ids);

    final after = await db.categoriesDao.watchByType(CategoryType.income).first;
    expect([for (final row in after) row.id], ids);
  });

  test('archiving hides a category without touching its history', () async {
    final walletId = await db.walletsDao.createWallet(
      WalletsCompanion.insert(name: 'Cash', currency: 'BDT', color: 0xFF0D9488),
    );
    final groceries = await categoryNamed('Groceries');
    await db.transactionsDao.addTransaction(
      walletId: walletId,
      type: TransactionType.expense,
      amount: Money(50000, 'BDT'),
      date: '2026-08-07',
      categoryId: groceries,
    );

    await db.categoriesDao.setArchived(groceries, archived: true);

    expect(await namesOf(CategoryType.expense), isNot(contains('Groceries')));
    expect(
      await namesOf(CategoryType.expense, includeArchived: true),
      contains('Groceries'),
    );

    final tx = await db.select(db.transactions).getSingle();
    expect(tx.categoryId, groceries);
  });

  test(
    'deleting keeps the transaction but drops its category and budget',
    () async {
      final walletId = await db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: 'Cash',
          currency: 'BDT',
          color: 0xFF0D9488,
        ),
      );
      final groceries = await categoryNamed('Groceries');
      await db.transactionsDao.addTransaction(
        walletId: walletId,
        type: TransactionType.expense,
        amount: Money(50000, 'BDT'),
        date: '2026-08-07',
        categoryId: groceries,
      );
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: Money(100000, 'BDT'),
        categoryId: groceries,
      );

      await db.categoriesDao.deleteCategory(groceries);

      // The money spent is a fact; the label on it was the user's to remove.
      final tx = await db.select(db.transactions).getSingle();
      expect(tx.categoryId, isNull);
      expect(tx.amountMinor, 50000);
      expect(await db.select(db.budgets).get(), isEmpty);
    },
  );
}
