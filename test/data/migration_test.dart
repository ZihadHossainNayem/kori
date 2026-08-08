import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/tables/transactions.dart';

import 'schema/snapshot.dart';

/// A local-first app cannot ask anyone to reinstall, so a broken migration is
/// permanent data loss on someone's phone. These tests are the guard rail.
void main() {
  late Directory temp;

  setUp(() async {
    temp = await Directory.systemTemp.createTemp('kori-migration');
  });

  tearDown(() async {
    await temp.delete(recursive: true);
  });

  Future<KoriDatabase> openFile(String name) async {
    final db = KoriDatabase(NativeDatabase(File('${temp.path}/$name')));
    // Opening is lazy; touch it so beforeOpen has run before we assert.
    await db.customSelect('SELECT 1').get();
    return db;
  }

  group('schema version', () {
    test('matches the recorded snapshot', () async {
      final db = KoriDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      final actual = await schemaSnapshotOf(db);
      final file = File('test/data/schema/v${db.schemaVersion}.sql');

      if (Platform.environment.containsKey('RECORD_SCHEMA')) {
        await file.writeAsString(actual);
        return;
      }

      expect(
        file.existsSync(),
        isTrue,
        reason:
            'No snapshot for schema v${db.schemaVersion}. Write the migration, '
            'then record it: RECORD_SCHEMA=1 flutter test $_self',
      );
      expect(
        actual,
        await file.readAsString(),
        reason:
            'The schema changed without a version bump. Every device already '
            'holds v${db.schemaVersion}, so bump schemaVersion, add an '
            'onUpgrade step, and re-record: RECORD_SCHEMA=1 flutter test $_self',
      );
    });

    test('every version from 1 up has a snapshot', () {
      final db = KoriDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      for (var version = 1; version <= db.schemaVersion; version++) {
        expect(
          File('test/data/schema/v$version.sql').existsSync(),
          isTrue,
          reason: 'Missing test/data/schema/v$version.sql',
        );
      }
    });
  });

  group('wallet_balances view', () {
    Future<int> balanceOf(KoriDatabase db, int walletId) async {
      final row = await db
          .customSelect(
            'SELECT balance_minor FROM wallet_balances WHERE wallet_id = ?',
            variables: [Variable.withInt(walletId)],
          )
          .getSingle();
      return row.read<int>('balance_minor');
    }

    Future<int> seedWallet(KoriDatabase db) async {
      final walletId = await db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: 'Cash',
          currency: 'BDT',
          color: 0xFF0D9488,
          initialBalanceMinor: const Value(100000),
        ),
      );
      await db.transactionsDao.addTransaction(
        walletId: walletId,
        type: TransactionType.expense,
        amount: Money(25000, 'BDT'),
        date: '2026-08-07',
      );
      return walletId;
    }

    test('comes back after being dropped', () async {
      var db = await openFile('dropped.sqlite');
      final walletId = await seedWallet(db);
      await db.customStatement('DROP VIEW wallet_balances');
      await db.close();

      db = await openFile('dropped.sqlite');
      addTearDown(db.close);

      expect(await balanceOf(db, walletId), 75000);
    });

    test('replaces a stale definition rather than keeping it', () async {
      var db = await openFile('stale.sqlite');
      final walletId = await seedWallet(db);

      // What a migration on an older release would leave behind: a view that
      // still answers, with the wrong number.
      await db.customStatement('DROP VIEW wallet_balances');
      await db.customStatement(
        'CREATE VIEW wallet_balances AS '
        'SELECT id AS wallet_id, 0 AS balance_minor FROM wallets',
      );
      expect(await balanceOf(db, walletId), 0);
      await db.close();

      db = await openFile('stale.sqlite');
      addTearDown(db.close);

      expect(await balanceOf(db, walletId), 75000);
    });
  });

  test('the budget indexes survive into a real database', () async {
    final db = await openFile('budgets.sqlite');
    addTearDown(db.close);

    await db.budgetsDao.setBudget(
      monthKey: '2026-08',
      limit: Money(300000, 'BDT'),
    );

    // Straight past the DAO, because the rule has to hold in SQLite itself.
    await expectLater(
      db.customStatement(
        'INSERT INTO budgets (month_key, amount_limit_minor, currency) '
        "VALUES ('2026-08', 400000, 'BDT')",
      ),
      throwsA(isA<Exception>()),
    );
  });
}

const _self = 'test/data/migration_test.dart';
