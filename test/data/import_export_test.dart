import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/db.dart';
import 'package:kori/data/io/export_service.dart';
import 'package:kori/data/io/import_service.dart';
import 'package:kori/data/io/xlsx.dart';
import 'package:kori/data/tables/transactions.dart';

void main() {
  late KoriDatabase db;
  late ExportService exporter;
  late ImportService importer;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
    exporter = ExportService(db);
    importer = ImportService(db);
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> addWallet({String name = 'Cash', String currency = 'USD'}) =>
      db.walletsDao.createWallet(
        WalletsCompanion.insert(
          name: name,
          currency: currency,
          color: 0xFF0D9488,
          initialBalanceMinor: const Value(100000),
        ),
      );

  Future<int> categoryNamed(String name) async {
    final all = await db.select(db.categories).get();
    return all.firstWhere((c) => c.name == name).id;
  }

  Uint8List csvOf(String text) => Uint8List.fromList(utf8.encode(text));

  group('export', () {
    test('writes a header and one row per transaction', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      await db.transactionsDao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(25050, 'USD'),
        date: '2026-08-07',
        categoryId: food,
        note: 'Lunch',
      );

      final rows = await exporter.transactionRows();

      expect(rows.first, ExportColumns.transactions);
      expect(rows[1], [
        '2026-08-07',
        'expense',
        250.5,
        'USD',
        'Cash',
        'Food & Dining',
        'Lunch',
        null,
      ]);
    });

    test('writes amounts as numbers so a spreadsheet can total them', () async {
      final wallet = await addWallet();
      await db.transactionsDao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(25050, 'USD'),
        date: '2026-08-07',
      );

      expect((await exporter.transactionRows())[1][2], isA<num>());
    });

    test('names a transfer destination', () async {
      final from = await addWallet(name: 'Cash');
      final to = await addWallet(name: 'Bank');
      await db.transactionsDao.addTransaction(
        walletId: from,
        type: TransactionType.transfer,
        amount: const Money(50000, 'USD'),
        date: '2026-08-07',
        transferToWalletId: to,
      );

      expect((await exporter.transactionRows())[1].last, 'Bank');
    });

    test('includes archived wallets, since they hold history', () async {
      final wallet = await addWallet(name: 'Old card');
      await db.walletsDao.setArchived(wallet, archived: true);

      final rows = await exporter.walletRows();
      expect(rows[1].first, 'Old card');
      expect(rows[1].last, 'yes');
    });

    test('the xlsx has all three sheets', () async {
      await addWallet();
      final sheets = decodeXlsx(await exporter.toXlsx());
      expect(sheets.map((s) => s.name), [
        'Transactions',
        'Wallets',
        'Categories',
      ]);
    });

    test('the csv starts with a BOM', () async {
      await addWallet();
      final bytes = await exporter.toCsv();
      expect(bytes.take(3), [0xEF, 0xBB, 0xBF]);
    });

    test('names files by date', () {
      expect(
        ExportService.fileName('csv', now: DateTime(2026, 8, 7)),
        'kori-2026-08-07.csv',
      );
    });
  });

  group('column mapping', () {
    test('recognises our own headers', () {
      final mapping = ImportService.guessMapping(ExportColumns.transactions);
      expect(mapping[ImportField.date], 0);
      expect(mapping[ImportField.amount], 2);
      expect(mapping[ImportField.note], 6);
    });

    test('recognises what other apps call the same columns', () {
      final mapping = ImportService.guessMapping([
        'Transaction Date',
        'Description',
        'Value',
        'Account',
      ]);
      expect(mapping[ImportField.date], 0);
      expect(mapping[ImportField.note], 1);
      expect(mapping[ImportField.amount], 2);
      expect(mapping[ImportField.wallet], 3);
    });

    test('copes with reordered and extra columns', () {
      final mapping = ImportService.guessMapping([
        'Balance',
        'Amount',
        'Reference',
        'Date',
      ]);
      expect(mapping[ImportField.amount], 1);
      expect(mapping[ImportField.date], 3);
    });

    test('knows when it cannot import', () {
      final preview = ImportService.preview(
        csvOf('Reference,Balance\nabc,123\n'),
        fileName: 'x.csv',
      );
      expect(preview.canImport, isFalse);
    });
  });

  group('planning an import', () {
    test('accepts a file we exported ourselves', () async {
      final wallet = await addWallet();
      final food = await categoryNamed('Food & Dining');
      await db.transactionsDao.addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amount: const Money(25050, 'USD'),
        date: '2026-08-07',
        categoryId: food,
        note: 'Lunch',
      );

      final preview = ImportService.preview(
        await exporter.toCsv(),
        fileName: 'kori.csv',
      );
      final plan = await importer.plan(preview, fallbackCurrency: 'USD');

      expect(plan.valid, hasLength(1));
      expect(plan.invalid, isEmpty);
      expect(plan.newWallets, isEmpty);
      expect(plan.newCategories, isEmpty);
    });

    test('explains each rejected row by line number', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf(
          'Date,Type,Amount,Wallet\n'
          '2026-08-07,expense,25.00,Cash\n'
          'not-a-date,expense,10.00,Cash\n'
          '2026-08-09,expense,abc,Cash\n'
          '2026-02-30,expense,10.00,Cash\n',
        ),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');

      expect(plan.valid, hasLength(1));
      expect(plan.invalid.map((row) => row.line), [3, 4, 5]);
      expect(plan.invalid.first.problem, contains('not-a-date'));
      expect(plan.invalid.last.problem, contains('2026-02-30'));
    });

    test('refuses an ambiguous day-first date rather than guessing', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf(
          'Date,Amount,Wallet\n'
          '25/12/2026,10.00,Cash\n' // day > 12, so unambiguous
          '03/04/2026,10.00,Cash\n', // could be March or April
        ),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');

      expect(plan.valid.single.date, '2026-12-25');
      expect(plan.invalid.single.line, 3);
    });

    test('reads the sign as direction when there is no type column', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf(
          'Date,Amount,Wallet\n2026-08-07,-25.00,Cash\n2026-08-08,4200,Cash\n',
        ),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');

      expect(plan.rows[0].type, TransactionType.expense);
      expect(plan.rows[0].amount, const Money(2500, 'USD'));
      expect(plan.rows[1].type, TransactionType.income);
    });

    test('strips currency symbols and separators from an amount', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf('Date,Amount,Wallet\n2026-08-07,"\$1,234.56",Cash\n'),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');
      expect(plan.valid.single.amount, const Money(123456, 'USD'));
    });

    test('lists wallets and categories it would have to create', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf('Date,Amount,Wallet,Category\n2026-08-07,-25,Savings,Coffee\n'),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');
      expect(plan.newWallets, {'Savings'});
      expect(plan.newCategories, {'Coffee'});
    });

    test('rejects a transfer with no destination, or into itself', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf(
          'Date,Type,Amount,Wallet,Transfer to\n'
          '2026-08-07,transfer,25,Cash,\n'
          '2026-08-08,transfer,25,Cash,Cash\n',
        ),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');
      expect(plan.valid, isEmpty);
      expect(plan.invalid.first.problem, contains('destination'));
      expect(plan.invalid.last.problem, contains('same wallet'));
    });

    test('skips blank lines without complaining', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf('Date,Amount,Wallet\n2026-08-07,-25,Cash\n\n\n'),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(preview, fallbackCurrency: 'USD');
      expect(plan.rows, hasLength(1));
    });

    test('falls back to a chosen wallet when the file names none', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf('Date,Amount\n2026-08-07,-25\n'),
        fileName: 'x.csv',
      );

      final plan = await importer.plan(
        preview,
        fallbackWallet: 'Cash',
        fallbackCurrency: 'USD',
      );
      expect(plan.valid.single.wallet, 'Cash');
    });
  });

  group('committing', () {
    test('writes the rows and creates what was missing', () async {
      await addWallet();
      final preview = ImportService.preview(
        csvOf(
          'Date,Type,Amount,Wallet,Category,Note\n'
          '2026-08-07,expense,25.50,Cash,Food & Dining,Lunch\n'
          '2026-08-08,expense,9.99,Savings,Coffee,Flat white\n',
        ),
        fileName: 'x.csv',
      );
      final plan = await importer.plan(preview, fallbackCurrency: 'USD');

      final imported = await importer.commit(plan, fallbackCurrency: 'USD');

      expect(imported, 2);
      final wallets = await db.select(db.wallets).get();
      expect(wallets.map((w) => w.name), containsAll(['Cash', 'Savings']));
      final rows = await db.transactionsDao.watchEntries().first;
      expect(rows, hasLength(2));
      expect(
        rows.map((r) => r.category?.name),
        containsAll(['Food & Dining', 'Coffee']),
      );
    });

    test('imports nothing at all when one row fails to write', () async {
      await addWallet();

      // Hand-built so the second row reaches the database and is rejected
      // there: amount_minor > 0 is a CHECK constraint.
      const plan = ImportPlan(
        rows: [
          ImportRow(
            line: 2,
            date: '2026-08-07',
            type: TransactionType.expense,
            amount: Money(2500, 'USD'),
            wallet: 'Cash',
          ),
          ImportRow(
            line: 3,
            date: '2026-08-08',
            type: TransactionType.expense,
            amount: Money(0, 'USD'),
            wallet: 'Cash',
          ),
        ],
        newWallets: {},
        newCategories: {},
      );

      await expectLater(
        importer.commit(plan, fallbackCurrency: 'USD'),
        throwsA(isA<Exception>()),
      );
      // The first row was already written when the second failed; the
      // transaction has to have taken it back.
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('moves the balance the same way manual entry would', () async {
      final wallet = await addWallet();
      final preview = ImportService.preview(
        csvOf('Date,Type,Amount,Wallet\n2026-08-07,expense,250,Cash\n'),
        fileName: 'x.csv',
      );
      final plan = await importer.plan(preview, fallbackCurrency: 'USD');
      await importer.commit(plan, fallbackCurrency: 'USD');

      // 1000.00 opening less 250.00.
      expect(await db.walletsDao.balanceOf(wallet), const Money(75000, 'USD'));
    });
  });

  group('the round trip that proves the promise', () {
    test('export, wipe, import — the same transactions come back', () async {
      final cash = await addWallet(name: 'Cash');
      final bank = await addWallet(name: 'Bank');
      final food = await categoryNamed('Food & Dining');
      final salary = await categoryNamed('Salary');

      await db.transactionsDao.addTransaction(
        walletId: cash,
        type: TransactionType.expense,
        amount: const Money(25050, 'USD'),
        date: '2026-08-07',
        categoryId: food,
        note: 'Lunch with ভাত',
      );
      await db.transactionsDao.addTransaction(
        walletId: bank,
        type: TransactionType.income,
        amount: const Money(420000, 'USD'),
        date: '2026-08-01',
        categoryId: salary,
      );
      await db.transactionsDao.addTransaction(
        walletId: cash,
        type: TransactionType.transfer,
        amount: const Money(50000, 'USD'),
        date: '2026-08-03',
        transferToWalletId: bank,
      );

      final before = await exporter.transactionRows();
      final workbook = await exporter.toXlsx();

      // Wipe every transaction, as a restore onto a fresh install would.
      await db.delete(db.transactions).go();
      expect(await db.select(db.transactions).get(), isEmpty);

      final preview = ImportService.preview(
        workbook,
        fileName: 'kori-backup.xlsx',
      );
      final plan = await importer.plan(preview, fallbackCurrency: 'USD');
      expect(
        plan.invalid,
        isEmpty,
        reason: 'our own export must import cleanly',
      );
      await importer.commit(plan, fallbackCurrency: 'USD');

      final after = await exporter.transactionRows();
      expect(after, before);
    });
  });
}
