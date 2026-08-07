import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/transactions.dart';

void main() {
  late KoriDatabase db;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addWallet({String currency = 'BDT'}) => db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: 'Cash',
          currency: currency,
          color: 0xFF0F766E,
        ),
      );

  Future<int> categoryNamed(String name) async {
    final all = await db.select(db.categories).get();
    return all.firstWhere((c) => c.name == name).id;
  }

  Future<void> spend(
    int wallet,
    int minor, {
    int? categoryId,
    String date = '2026-08-07',
    String currency = 'BDT',
    TransactionType type = TransactionType.expense,
  }) =>
      db.transactionsDao.addTransaction(
        walletId: wallet,
        type: type,
        amount: Money(minor, currency),
        date: date,
        categoryId: categoryId,
      );

  group('setting budgets', () {
    test('creates a category budget', () async {
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(500000, 'BDT'),
        categoryId: food,
      );

      final budgets = await db.budgetsDao.forMonth('2026-08');
      expect(budgets, hasLength(1));
      expect(budgets.single.label, 'Food & Dining');
      expect(budgets.single.limit, const Money(500000, 'BDT'));
    });

    test('a second write for the same category replaces it', () async {
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(500000, 'BDT'),
        categoryId: food,
      );
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(600000, 'BDT'),
        categoryId: food,
      );

      final budgets = await db.budgetsDao.forMonth('2026-08');
      expect(budgets, hasLength(1));
      expect(budgets.single.limit, const Money(600000, 'BDT'));
    });

    test('an overall budget coexists with category budgets', () async {
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(2000000, 'BDT'));
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(500000, 'BDT'),
        categoryId: food,
      );

      final budgets = await db.budgetsDao.forMonth('2026-08');
      expect(budgets, hasLength(2));
      // Overall sorts first.
      expect(budgets.first.isOverall, isTrue);
      expect(budgets.first.label, 'Everything');
    });

    test('only one overall budget per month survives', () async {
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(1000, 'BDT'));
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(2000, 'BDT'));

      final budgets = await db.budgetsDao.forMonth('2026-08');
      expect(budgets, hasLength(1));
      expect(budgets.single.limit, const Money(2000, 'BDT'));
    });

    test('months are independent', () async {
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(1000, 'BDT'));
      await db.budgetsDao
          .setBudget(monthKey: '2026-09', limit: const Money(3000, 'BDT'));

      expect(await db.budgetsDao.forMonth('2026-08'), hasLength(1));
      expect(
        (await db.budgetsDao.forMonth('2026-09')).single.limit,
        const Money(3000, 'BDT'),
      );
    });
  });

  group('spend', () {
    test('sums expenses in the category and month', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(100000, 'BDT'),
        categoryId: food,
      );

      await spend(wallet, 25000, categoryId: food);
      await spend(wallet, 15000, categoryId: food, date: '2026-08-20');

      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      expect(budget.spent, const Money(40000, 'BDT'));
      expect(budget.remaining, const Money(60000, 'BDT'));
      expect(budget.percent, 40);
      expect(budget.isOver, isFalse);
    });

    test('ignores other categories, months, income and transfers', () async {
      final wallet = await addWallet();
      final other = await addWallet();
      final food = await categoryNamed('Food & Dining');
      final rent = await categoryNamed('Rent');
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(100000, 'BDT'),
        categoryId: food,
      );

      await spend(wallet, 25000, categoryId: food);
      await spend(wallet, 90000, categoryId: rent);
      await spend(wallet, 90000, categoryId: food, date: '2026-07-31');
      await spend(wallet, 90000, categoryId: food, date: '2026-09-01');
      await spend(
        wallet,
        90000,
        categoryId: food,
        type: TransactionType.income,
      );
      await db.transactionsDao.addTransaction(
        walletId: wallet,
        type: TransactionType.transfer,
        amount: const Money(90000, 'BDT'),
        date: '2026-08-07',
        transferToWalletId: other,
      );

      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      expect(budget.spent, const Money(25000, 'BDT'));
    });

    test('an overall budget counts every expense category', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      final rent = await categoryNamed('Rent');
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(100000, 'BDT'));

      await spend(wallet, 25000, categoryId: food);
      await spend(wallet, 30000, categoryId: rent);
      await spend(wallet, 5000);

      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      expect(budget.spent, const Money(60000, 'BDT'));
    });

    test('counts foreign-currency expenses separately instead of adding them',
        () async {
      final bdt = await addWallet();
      final usd = await addWallet(currency: 'USD');
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(100000, 'BDT'),
        categoryId: food,
      );

      await spend(bdt, 25000, categoryId: food);
      await spend(usd, 5000, categoryId: food, currency: 'USD');

      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      // 50.00 USD is not 50000 paisa, so it is reported, not summed.
      expect(budget.spent, const Money(25000, 'BDT'));
      expect(budget.uncountedInOtherCurrencies, 1);
    });

    test('reports overspending without letting the bar overflow', () async {
      final wallet = await addWallet();
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));
      await spend(wallet, 15000);

      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      expect(budget.isOver, isTrue);
      expect(budget.percent, 150);
      expect(budget.fraction, 1.0);
      expect(budget.remaining, const Money(-5000, 'BDT'));
    });

    test('updates reactively as spending lands', () async {
      final wallet = await addWallet();
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));

      final seen = <Money>[];
      final subscription = db.budgetsDao
          .watchForMonth('2026-08')
          .listen((rows) => seen.add(rows.single.spent));
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await spend(wallet, 2500);
      await pumpEventQueue();

      expect(seen, [const Money(0, 'BDT'), const Money(2500, 'BDT')]);
    });
  });

  group('alert bookkeeping', () {
    test('markNotified records the threshold', () async {
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));
      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      expect(budget.notifiedAtPct, 0);

      await db.budgetsDao.markNotified(budget.id, 80);
      expect(
        (await db.budgetsDao.forMonth('2026-08')).single.notifiedAtPct,
        80,
      );
    });

    test('changing the limit re-arms the alerts', () async {
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));
      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      await db.budgetsDao.markNotified(budget.id, 100);

      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(50000, 'BDT'));

      expect((await db.budgetsDao.forMonth('2026-08')).single.notifiedAtPct, 0);
    });

    test('rewriting the same limit leaves the alerts alone', () async {
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));
      final budget = (await db.budgetsDao.forMonth('2026-08')).single;
      await db.budgetsDao.markNotified(budget.id, 80);

      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));

      expect((await db.budgetsDao.forMonth('2026-08')).single.notifiedAtPct, 80);
    });
  });

  group('copying a month', () {
    test('copies budgets that the target month lacks', () async {
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao
          .setBudget(monthKey: '2026-08', limit: const Money(20000, 'BDT'));
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(5000, 'BDT'),
        categoryId: food,
      );

      final copied =
          await db.budgetsDao.copyMonth(from: '2026-08', to: '2026-09');

      expect(copied, 2);
      expect(await db.budgetsDao.forMonth('2026-09'), hasLength(2));
    });

    test('never overwrites a budget already set in the target month', () async {
      final food = await categoryNamed('Food & Dining');
      await db.budgetsDao.setBudget(
        monthKey: '2026-08',
        limit: const Money(5000, 'BDT'),
        categoryId: food,
      );
      await db.budgetsDao.setBudget(
        monthKey: '2026-09',
        limit: const Money(9999, 'BDT'),
        categoryId: food,
      );

      final copied =
          await db.budgetsDao.copyMonth(from: '2026-08', to: '2026-09');

      expect(copied, 0);
      expect(
        (await db.budgetsDao.forMonth('2026-09')).single.limit,
        const Money(9999, 'BDT'),
      );
    });
  });

  test('deleting a budget leaves its transactions alone', () async {
    final wallet = await addWallet();
    await db.budgetsDao
        .setBudget(monthKey: '2026-08', limit: const Money(10000, 'BDT'));
    await spend(wallet, 2500);

    final budget = (await db.budgetsDao.forMonth('2026-08')).single;
    await db.budgetsDao.deleteBudget(budget.id);

    expect(await db.budgetsDao.forMonth('2026-08'), isEmpty);
    expect(await db.select(db.transactions).get(), hasLength(1));
  });

  test('deleting a category takes its budget with it', () async {
    final food = await categoryNamed('Food & Dining');
    await db.budgetsDao.setBudget(
      monthKey: '2026-08',
      limit: const Money(5000, 'BDT'),
      categoryId: food,
    );

    await db.categoriesDao.deleteCategory(food);

    expect(await db.budgetsDao.forMonth('2026-08'), isEmpty);
  });
}
