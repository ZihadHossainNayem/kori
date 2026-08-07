import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/daos/analytics_dao.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/transactions.dart';

void main() {
  late KoriDatabase db;
  late AnalyticsDao dao;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
    dao = db.analyticsDao;
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addWallet({String currency = 'BDT'}) => db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: 'Cash',
          currency: currency,
          color: 0xFF0D9488,
        ),
      );

  Future<int> categoryNamed(String name) async {
    final all = await db.select(db.categories).get();
    return all.firstWhere((c) => c.name == name).id;
  }

  Future<void> record(
    int wallet,
    int minor,
    String date, {
    TransactionType type = TransactionType.expense,
    int? categoryId,
    String currency = 'BDT',
    int? transferTo,
  }) =>
      db.transactionsDao.addTransaction(
        walletId: wallet,
        type: type,
        amount: Money(minor, currency),
        date: date,
        categoryId: categoryId,
        transferToWalletId: transferTo,
      );

  group('totals', () {
    test('separates income from expense', () async {
      final wallet = await addWallet();
      await record(wallet, 30000, '2026-08-05');
      await record(wallet, 120000, '2026-08-06', type: TransactionType.income);

      final totals = await dao
          .watchTotals(from: '2026-08-01', to: '2026-08-31', currency: 'BDT')
          .first;

      expect(totals.income, const Money(120000, 'BDT'));
      expect(totals.expense, const Money(30000, 'BDT'));
      expect(totals.net, const Money(90000, 'BDT'));
      expect(totals.uncounted, 0);
    });

    test('excludes transfers', () async {
      final wallet = await addWallet();
      final other = await addWallet();
      await record(wallet, 50000, '2026-08-05', transferTo: other,
          type: TransactionType.transfer);

      final totals = await dao
          .watchTotals(from: '2026-08-01', to: '2026-08-31', currency: 'BDT')
          .first;

      expect(totals.income, const Money(0, 'BDT'));
      expect(totals.expense, const Money(0, 'BDT'));
      expect(totals.uncounted, 0);
    });

    test('counts other currencies instead of mixing them in', () async {
      final bdt = await addWallet();
      final usd = await addWallet(currency: 'USD');
      await record(bdt, 30000, '2026-08-05');
      await record(usd, 4000, '2026-08-06', currency: 'USD');

      final totals = await dao
          .watchTotals(from: '2026-08-01', to: '2026-08-31', currency: 'BDT')
          .first;

      expect(totals.expense, const Money(30000, 'BDT'));
      expect(totals.uncounted, 1);
    });

    test('respects the range bounds inclusively', () async {
      final wallet = await addWallet();
      await record(wallet, 100, '2026-07-31');
      await record(wallet, 200, '2026-08-01');
      await record(wallet, 400, '2026-08-31');
      await record(wallet, 800, '2026-09-01');

      final totals = await dao
          .watchTotals(from: '2026-08-01', to: '2026-08-31', currency: 'BDT')
          .first;

      expect(totals.expense, const Money(600, 'BDT'));
    });

    test('an empty range totals to zero, not an error', () async {
      final totals = await dao
          .watchTotals(from: '2026-08-01', to: '2026-08-31', currency: 'BDT')
          .first;

      expect(totals.income, const Money(0, 'BDT'));
      expect(totals.net, const Money(0, 'BDT'));
    });
  });

  group('category breakdown', () {
    test('groups expenses by category, largest first', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      final rent = await categoryNamed('Rent');

      await record(wallet, 20000, '2026-08-05', categoryId: food);
      await record(wallet, 10000, '2026-08-06', categoryId: food);
      await record(wallet, 90000, '2026-08-07', categoryId: rent);

      final slices = await dao
          .watchCategoryBreakdown(
            from: '2026-08-01',
            to: '2026-08-31',
            currency: 'BDT',
          )
          .first;

      expect(slices.map((s) => s.name), ['Rent', 'Food & Dining']);
      expect(slices.first.total, const Money(90000, 'BDT'));
      expect(slices.last.total, const Money(30000, 'BDT'));
    });

    test('keeps uncategorised spending visible', () async {
      final wallet = await addWallet();
      await record(wallet, 5000, '2026-08-05');

      final slices = await dao
          .watchCategoryBreakdown(
            from: '2026-08-01',
            to: '2026-08-31',
            currency: 'BDT',
          )
          .first;

      expect(slices.single.name, 'Uncategorised');
      expect(slices.single.categoryId, isNull);
    });

    test('ignores income', () async {
      final wallet = await addWallet();
      final salary = await categoryNamed('Salary');
      await record(wallet, 500000, '2026-08-05',
          type: TransactionType.income, categoryId: salary);

      final slices = await dao
          .watchCategoryBreakdown(
            from: '2026-08-01',
            to: '2026-08-31',
            currency: 'BDT',
          )
          .first;

      expect(slices, isEmpty);
    });

    test('carries the category colour and icon for the chart', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      await record(wallet, 100, '2026-08-05', categoryId: food);

      final slice = (await dao
              .watchCategoryBreakdown(
                from: '2026-08-01',
                to: '2026-08-31',
                currency: 'BDT',
              )
              .first)
          .single;

      expect(slice.icon, 'utensils');
      expect(slice.color, 0xFFF97316);
    });
  });

  group('period totals', () {
    test('buckets by month', () async {
      final wallet = await addWallet();
      await record(wallet, 10000, '2026-06-15');
      await record(wallet, 20000, '2026-07-15');
      await record(wallet, 30000, '2026-07-20');

      final periods = await dao
          .watchPeriodTotals(
            from: '2026-06-01',
            to: '2026-08-31',
            currency: 'BDT',
            granularity: Granularity.month,
          )
          .first;

      expect(periods.map((p) => p.bucket), ['2026-06', '2026-07']);
      expect(periods.last.expense, const Money(50000, 'BDT'));
    });

    test('buckets by day', () async {
      final wallet = await addWallet();
      await record(wallet, 10000, '2026-08-05');
      await record(wallet, 20000, '2026-08-05');
      await record(wallet, 30000, '2026-08-06');

      final periods = await dao
          .watchPeriodTotals(
            from: '2026-08-01',
            to: '2026-08-31',
            currency: 'BDT',
            granularity: Granularity.day,
          )
          .first;

      expect(periods.map((p) => p.bucket), ['2026-08-05', '2026-08-06']);
      expect(periods.first.expense, const Money(30000, 'BDT'));
    });

    test('reports net per bucket', () async {
      final wallet = await addWallet();
      await record(wallet, 120000, '2026-08-01', type: TransactionType.income);
      await record(wallet, 45000, '2026-08-02');

      final period = (await dao
              .watchPeriodTotals(
                from: '2026-08-01',
                to: '2026-08-31',
                currency: 'BDT',
                granularity: Granularity.month,
              )
              .first)
          .single;

      expect(period.net, const Money(75000, 'BDT'));
    });

    test('omits buckets with no activity', () async {
      final wallet = await addWallet();
      await record(wallet, 10000, '2026-06-15');
      await record(wallet, 10000, '2026-08-15');

      final periods = await dao
          .watchPeriodTotals(
            from: '2026-06-01',
            to: '2026-08-31',
            currency: 'BDT',
            granularity: Granularity.month,
          )
          .first;

      // July is absent; callers fill the gap so a quiet month reads as zero.
      expect(periods.map((p) => p.bucket), ['2026-06', '2026-08']);
    });
  });

  group('weekday totals', () {
    test('maps SQLite Sunday to DateTime Sunday', () async {
      final wallet = await addWallet();
      // 2026-08-09 is a Sunday, 2026-08-10 a Monday.
      await record(wallet, 5000, '2026-08-09');
      await record(wallet, 7000, '2026-08-10');

      final weekdays = await dao
          .watchWeekdayTotals(
            from: '2026-08-01',
            to: '2026-08-31',
            currency: 'BDT',
          )
          .first;

      final monday = weekdays.firstWhere((w) => w.weekday == DateTime.monday);
      final sunday = weekdays.firstWhere((w) => w.weekday == DateTime.sunday);
      expect(monday.expense, const Money(7000, 'BDT'));
      expect(sunday.expense, const Money(5000, 'BDT'));
      // Sunday sorts last, not first.
      expect(weekdays.last.weekday, DateTime.sunday);
    });

    test('counts entries as well as totals', () async {
      final wallet = await addWallet();
      await record(wallet, 1000, '2026-08-10');
      await record(wallet, 2000, '2026-08-10');

      final monday = (await dao
              .watchWeekdayTotals(
                from: '2026-08-01',
                to: '2026-08-31',
                currency: 'BDT',
              )
              .first)
          .single;

      expect(monday.count, 2);
      expect(monday.expense, const Money(3000, 'BDT'));
    });
  });

  test('streams update when a transaction lands', () async {
    final wallet = await addWallet();
    final seen = <Money>[];
    final subscription = dao
        .watchTotals(from: '2026-08-01', to: '2026-08-31', currency: 'BDT')
        .listen((totals) => seen.add(totals.expense));
    addTearDown(subscription.cancel);

    await pumpEventQueue();
    await record(wallet, 2500, '2026-08-07');
    await pumpEventQueue();

    expect(seen, [const Money(0, 'BDT'), const Money(2500, 'BDT')]);
  });
}
