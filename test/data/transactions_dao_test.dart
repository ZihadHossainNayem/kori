import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/daos/transactions_dao.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/categories.dart';
import 'package:kori/data/tables/transactions.dart';

void main() {
  late KoriDatabase db;
  late TransactionsDao dao;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
    dao = db.transactionsDao;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addWallet({String name = 'Cash', String currency = 'BDT'}) =>
      db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: name,
          currency: currency,
          color: 0xFF0F766E,
        ),
      );

  Future<int> categoryNamed(String name) async {
    final all = await db.select(db.categories).get();
    return all.firstWhere((c) => c.name == name).id;
  }

  group('adding', () {
    test('stores the amount unsigned with direction in the type', () async {
      final wallet = await addWallet();
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(-2500, 'BDT'),
        date: '2026-08-07',
      );

      final stored = (await db.select(db.transactions).get()).single;
      expect(stored.amountMinor, 2500);
      expect(stored.type, TransactionType.expense);
    });

    test('takes the currency from the amount', () async {
      final wallet = await addWallet(currency: 'USD');
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.income,
        amount: const Money(1000, 'USD'),
        date: '2026-08-07',
      );

      expect((await db.select(db.transactions).get()).single.currency, 'USD');
    });

    test('normalises a blank note to null', () async {
      final wallet = await addWallet();
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.income,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
        note: '   ',
      );

      expect((await db.select(db.transactions).get()).single.note, isNull);
    });
  });

  group('entries', () {
    test('joins the wallet, category and transfer destination', () async {
      final cash = await addWallet(name: 'Cash');
      final bank = await addWallet(name: 'Bank');
      final food = await categoryNamed('Food & Dining');

      await dao.addTransaction(
        walletId: cash,
        type: TransactionType.expense,
        amount: const Money(500, 'BDT'),
        date: '2026-08-07',
        categoryId: food,
      );
      await dao.addTransaction(
        walletId: cash,
        type: TransactionType.transfer,
        amount: const Money(1000, 'BDT'),
        date: '2026-08-07',
        transferToWalletId: bank,
      );

      final entries = await dao.watchEntries().first;
      final transfer = entries.firstWhere(
        (e) => e.transaction.type == TransactionType.transfer,
      );
      final expense = entries.firstWhere(
        (e) => e.transaction.type == TransactionType.expense,
      );

      expect(expense.wallet.name, 'Cash');
      expect(expense.category?.name, 'Food & Dining');
      expect(expense.destination, isNull);
      expect(transfer.destination?.name, 'Bank');
      expect(transfer.category, isNull);
    });

    test('signs amounts for display without changing storage', () async {
      final wallet = await addWallet();
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(500, 'BDT'),
        date: '2026-08-07',
      );
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.income,
        amount: const Money(700, 'BDT'),
        date: '2026-08-07',
      );

      final entries = await dao.watchEntries().first;
      expect(
        entries.map((e) => e.signedAmount.minor).toList()..sort(),
        [-500, 700],
      );
    });

    test('orders newest first', () async {
      final wallet = await addWallet();
      for (final date in ['2026-08-01', '2026-08-09', '2026-08-05']) {
        await dao.addTransaction(
          walletId: wallet,
          type: TransactionType.expense,
          amount: const Money(100, 'BDT'),
          date: date,
        );
      }

      final entries = await dao.watchEntries().first;
      expect(
        entries.map((e) => e.transaction.date),
        ['2026-08-09', '2026-08-05', '2026-08-01'],
      );
    });

    test('honours the limit', () async {
      final wallet = await addWallet();
      for (var day = 1; day <= 5; day++) {
        await dao.addTransaction(
          walletId: wallet,
          type: TransactionType.expense,
          amount: const Money(100, 'BDT'),
          date: '2026-08-0$day',
        );
      }

      expect(await dao.watchEntries(limit: 2).first, hasLength(2));
    });
  });

  group('filtering', () {
    test('by wallet includes transfers into that wallet', () async {
      final cash = await addWallet(name: 'Cash');
      final bank = await addWallet(name: 'Bank');

      await dao.addTransaction(
        walletId: cash,
        type: TransactionType.transfer,
        amount: const Money(1000, 'BDT'),
        date: '2026-08-07',
        transferToWalletId: bank,
      );

      // The transfer belongs to both wallets' histories.
      expect(
        await dao.watchEntries(filter: TransactionFilter(walletId: cash)).first,
        hasLength(1),
      );
      expect(
        await dao.watchEntries(filter: TransactionFilter(walletId: bank)).first,
        hasLength(1),
      );
    });

    test('by type', () async {
      final wallet = await addWallet();
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.income,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
      );
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(200, 'BDT'),
        date: '2026-08-07',
      );

      final expenses = await dao
          .watchEntries(
            filter: const TransactionFilter(type: TransactionType.expense),
          )
          .first;
      expect(expenses.single.amount, const Money(200, 'BDT'));
    });

    test('by category', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      final rent = await categoryNamed('Rent');

      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
        categoryId: food,
      );
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(900, 'BDT'),
        date: '2026-08-07',
        categoryId: rent,
      );

      final entries =
          await dao.watchEntries(filter: TransactionFilter(categoryId: rent)).first;
      expect(entries.single.amount, const Money(900, 'BDT'));
    });

    test('by inclusive date range', () async {
      final wallet = await addWallet();
      for (final date in ['2026-07-31', '2026-08-01', '2026-08-31', '2026-09-01']) {
        await dao.addTransaction(
          walletId: wallet,
          type: TransactionType.expense,
          amount: const Money(100, 'BDT'),
          date: date,
        );
      }

      final august = await dao
          .watchEntries(
            filter: const TransactionFilter(from: '2026-08-01', to: '2026-08-31'),
          )
          .first;
      expect(
        august.map((e) => e.transaction.date),
        ['2026-08-31', '2026-08-01'],
      );
    });

    test('by note and category name', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');

      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
        note: 'Rickshaw to office',
      );
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(200, 'BDT'),
        date: '2026-08-07',
        categoryId: food,
      );

      expect(
        await dao
            .watchEntries(filter: const TransactionFilter(search: 'rickshaw'))
            .first,
        hasLength(1),
      );
      expect(
        await dao
            .watchEntries(filter: const TransactionFilter(search: 'dining'))
            .first,
        hasLength(1),
      );
    });

    test('treats LIKE wildcards in a search as literal text', () async {
      final wallet = await addWallet();
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
        note: '50% deposit',
      );
      await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(200, 'BDT'),
        date: '2026-08-07',
        note: 'lunch',
      );

      // Unescaped, "%" would match every row.
      final results = await dao
          .watchEntries(filter: const TransactionFilter(search: '%'))
          .first;
      expect(results.single.transaction.note, '50% deposit');
    });

    test('combines filters', () async {
      final cash = await addWallet(name: 'Cash');
      final bank = await addWallet(name: 'Bank');
      await dao.addTransaction(
        walletId: cash,
        type: TransactionType.expense,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
      );
      await dao.addTransaction(
        walletId: bank,
        type: TransactionType.expense,
        amount: const Money(200, 'BDT'),
        date: '2026-08-07',
      );
      await dao.addTransaction(
        walletId: cash,
        type: TransactionType.income,
        amount: const Money(300, 'BDT'),
        date: '2026-08-07',
      );

      final entries = await dao
          .watchEntries(
            filter: TransactionFilter(
              walletId: cash,
              type: TransactionType.expense,
            ),
          )
          .first;
      expect(entries.single.amount, const Money(100, 'BDT'));
    });

    test('an empty filter reports itself as empty', () {
      expect(const TransactionFilter().isEmpty, isTrue);
      expect(const TransactionFilter(search: '  ').isEmpty, isTrue);
      expect(const TransactionFilter(walletId: 1).isEmpty, isFalse);
    });
  });

  group('editing and deleting', () {
    test('deletes and restores with the same id, for undo', () async {
      final wallet = await addWallet();
      final id = await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(2500, 'BDT'),
        date: '2026-08-07',
        note: 'Lunch',
      );

      final entry = await dao.entryById(id);
      expect(entry?.transaction.note, 'Lunch');

      await dao.deleteTransaction(id);
      expect(await dao.entryById(id), isNull);

      await dao.restore(entry!.transaction);
      final restored = await dao.entryById(id);
      expect(restored?.transaction.id, id);
      expect(restored?.transaction.note, 'Lunch');
    });

    test('updates an amount', () async {
      final wallet = await addWallet();
      final id = await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(2500, 'BDT'),
        date: '2026-08-07',
      );

      final entry = await dao.entryById(id);
      await dao.updateTransaction(
        entry!.transaction.copyWith(amountMinor: 900),
      );

      expect((await dao.entryById(id))?.transaction.amountMinor, 900);
    });

    test('entryById returns null for a missing row', () async {
      expect(await dao.entryById(404), isNull);
    });
  });

  group('categories dao', () {
    test('watches only the requested type, ordered for display', () async {
      final income = await db.categoriesDao
          .watchByType(CategoryType.income)
          .first;
      expect(income, hasLength(5));
      expect(income.first.name, 'Salary');
    });

    test('archived categories drop out', () async {
      final food = await categoryNamed('Food & Dining');
      await db.categoriesDao.setArchived(food, archived: true);

      final visible =
          await db.categoriesDao.watchByType(CategoryType.expense).first;
      expect(visible.map((c) => c.name), isNot(contains('Food & Dining')));

      final all = await db.categoriesDao
          .watchByType(CategoryType.expense, includeArchived: true)
          .first;
      expect(all.map((c) => c.name), contains('Food & Dining'));
    });

    test('reorder rewrites sortOrder to match', () async {
      final expenses =
          await db.categoriesDao.watchByType(CategoryType.expense).first;
      final reversed = expenses.reversed.map((c) => c.id).toList();

      await db.categoriesDao.reorder(reversed);

      final after =
          await db.categoriesDao.watchByType(CategoryType.expense).first;
      expect(after.map((c) => c.id), reversed);
    });

    test('deleting a category leaves its transactions with no category', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      final id = await dao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(100, 'BDT'),
        date: '2026-08-07',
        categoryId: food,
      );

      await db.categoriesDao.deleteCategory(food);

      final entry = await dao.entryById(id);
      expect(entry, isNotNull);
      expect(entry!.transaction.categoryId, isNull);
    });
  });
}
