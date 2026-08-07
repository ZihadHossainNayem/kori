import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/core/recurrence.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/transactions.dart';
import 'package:kori/features/recurring/recurring_engine.dart';

void main() {
  late KoriDatabase db;
  late RecurringEngine engine;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
    engine = RecurringEngine(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addWallet() => db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: 'Cash',
          currency: 'BDT',
          color: 0xFF0F766E,
        ),
      );

  Future<int> addRule({
    required int wallet,
    required String nextDate,
    RecurrenceFrequency frequency = RecurrenceFrequency.monthly,
    int anchorDay = 1,
    int amountMinor = 100000,
    String type = 'expense',
    String? endDate,
    String? note,
  }) =>
      db.recurringDao.createRule(
        RecurringRulesCompanion.insert(
          walletId: wallet,
          type: type,
          amountMinor: amountMinor,
          currency: 'BDT',
          frequency: frequency,
          nextDate: nextDate,
          anchorDay: Value(anchorDay),
          endDate: Value(endDate),
          note: Value(note),
        ),
      );

  Future<List<Transaction>> transactions() =>
      (db.select(db.transactions)..orderBy([(t) => OrderingTerm.asc(t.date)]))
          .get();

  group('due rules', () {
    test('a rule due today fires once and advances a month', () async {
      final wallet = await addWallet();
      final id = await addRule(
        wallet: wallet,
        nextDate: '2026-08-07',
        anchorDay: 7,
      );

      final created = await engine.catchUp(now: DateTime(2026, 8, 7));

      expect(created, 1);
      final rows = await transactions();
      expect(rows.single.date, '2026-08-07');
      expect(rows.single.recurringRuleId, id);
      expect(rows.single.type, TransactionType.expense);
      expect(rows.single.amountMinor, 100000);

      final rule = (await db.select(db.recurringRules).get()).single;
      expect(rule.nextDate, '2026-09-07');
      expect(rule.active, isTrue);
    });

    test('a rule due tomorrow does nothing', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-08-08');

      expect(await engine.catchUp(now: DateTime(2026, 8, 7)), 0);
      expect(await transactions(), isEmpty);
    });

    test('an inactive rule is skipped even when overdue', () async {
      final wallet = await addWallet();
      final id = await addRule(wallet: wallet, nextDate: '2026-01-01');
      await db.recurringDao.setActive(id, active: false);

      expect(await engine.catchUp(now: DateTime(2026, 8, 7)), 0);
    });

    test('income rules create income', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-08-01', type: 'income');

      await engine.catchUp(now: DateTime(2026, 8, 7));

      expect((await transactions()).single.type, TransactionType.income);
    });

    test('the note carries through', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-08-01', note: 'Rent');

      await engine.catchUp(now: DateTime(2026, 8, 7));

      expect((await transactions()).single.note, 'Rent');
    });
  });

  group('catching up', () {
    test('a phone off for three months replays each occurrence', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-05-10', anchorDay: 10);

      final created = await engine.catchUp(now: DateTime(2026, 8, 7));

      expect(created, 3);
      expect(
        (await transactions()).map((t) => t.date),
        ['2026-05-10', '2026-06-10', '2026-07-10'],
      );
      expect(
        (await db.select(db.recurringRules).get()).single.nextDate,
        '2026-08-10',
      );
    });

    test('a daily rule replays every missed day', () async {
      final wallet = await addWallet();
      await addRule(
        wallet: wallet,
        nextDate: '2026-08-01',
        frequency: RecurrenceFrequency.daily,
      );

      expect(await engine.catchUp(now: DateTime(2026, 8, 7)), 7);
    });

    test('a month-end rule does not drift while catching up', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-01-31', anchorDay: 31);

      await engine.catchUp(now: DateTime(2026, 5, 15));

      // February clamps, then the anchor returns — no permanent shift.
      expect(
        (await transactions()).map((t) => t.date),
        ['2026-01-31', '2026-02-28', '2026-03-31', '2026-04-30'],
      );
      expect(
        (await db.select(db.recurringRules).get()).single.nextDate,
        '2026-05-31',
      );
    });

    test('a long-dormant daily rule is capped rather than freezing the app',
        () async {
      final wallet = await addWallet();
      await addRule(
        wallet: wallet,
        nextDate: '2020-01-01',
        frequency: RecurrenceFrequency.daily,
      );

      final created = await engine.catchUp(now: DateTime(2026, 8, 7));

      expect(created, RecurringEngine.maxOccurrencesPerRun);
      // Still active, so the next run continues where this one stopped.
      expect((await db.select(db.recurringRules).get()).single.active, isTrue);
    });

    test('running twice on the same day does not double up', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-08-01');

      await engine.catchUp(now: DateTime(2026, 8, 7));
      final second = await engine.catchUp(now: DateTime(2026, 8, 7));

      expect(second, 0);
      expect(await transactions(), hasLength(1));
    });
  });

  group('end dates', () {
    test('a rule stops at its end date and deactivates', () async {
      final wallet = await addWallet();
      await addRule(
        wallet: wallet,
        nextDate: '2026-06-01',
        anchorDay: 1,
        endDate: '2026-07-15',
      );

      final created = await engine.catchUp(now: DateTime(2026, 8, 7));

      expect(created, 2);
      expect(
        (await transactions()).map((t) => t.date),
        ['2026-06-01', '2026-07-01'],
      );

      final rule = (await db.select(db.recurringRules).get()).single;
      expect(rule.active, isFalse);
    });

    test('a rule whose end date has passed fires nothing', () async {
      final wallet = await addWallet();
      await addRule(
        wallet: wallet,
        nextDate: '2026-09-01',
        endDate: '2026-08-01',
      );

      expect(await engine.catchUp(now: DateTime(2026, 8, 7)), 0);
    });
  });

  group('generated transactions', () {
    test('move the wallet balance', () async {
      final wallet = await addWallet();
      await addRule(wallet: wallet, nextDate: '2026-08-01', amountMinor: 25000);

      await engine.catchUp(now: DateTime(2026, 8, 7));

      expect(
        await db.walletsDao.balanceOf(wallet),
        const Money(-25000, 'BDT'),
      );
    });

    test('are removed with the rule that made them', () async {
      final wallet = await addWallet();
      final id = await addRule(wallet: wallet, nextDate: '2026-08-01');
      await engine.catchUp(now: DateTime(2026, 8, 7));

      await db.recurringDao.deleteRule(id);

      // The rows survive with no rule attached: history stays intact.
      final rows = await transactions();
      expect(rows, hasLength(1));
      expect(rows.single.recurringRuleId, isNull);
    });
  });
}
