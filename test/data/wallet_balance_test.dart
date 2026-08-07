// drift exports an `isNull` SQL helper that collides with matcher's.
import 'package:drift/drift.dart' hide isNull;
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

  Future<int> addWallet({
    String name = 'Cash',
    String currency = 'BDT',
    int initialMinor = 0,
  }) {
    return db.walletsDao.createWallet(
      WalletsCompanion.insert(
        name: name,
        currency: currency,
        color: 0xFF0F766E,
        initialBalanceMinor: Value(initialMinor),
      ),
    );
  }

  Future<void> addTransaction({
    required int walletId,
    required TransactionType type,
    required int amountMinor,
    String currency = 'BDT',
    int? transferTo,
    String date = '2026-08-07',
  }) {
    return db
        .into(db.transactions)
        .insert(
          TransactionsCompanion.insert(
            walletId: walletId,
            type: type,
            amountMinor: amountMinor,
            currency: currency,
            date: date,
            transferToWalletId: Value(transferTo),
          ),
        );
  }

  group('seeding', () {
    test('a fresh database starts with default categories', () async {
      final categories = await db.select(db.categories).get();
      expect(categories, hasLength(16));
      expect(
        categories.where((c) => c.type == CategoryType.income),
        hasLength(5),
      );
      expect(
        categories.where((c) => c.type == CategoryType.expense),
        hasLength(11),
      );
    });

    test('categories are ordered for display', () async {
      final categories = await db.select(db.categories).get()
        ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      expect(categories.first.name, 'Food & Dining');
    });
  });

  group('wallet balance', () {
    test('starts at the opening balance', () async {
      final id = await addWallet(initialMinor: 50000);
      expect(await db.walletsDao.balanceOf(id), const Money(50000, 'BDT'));
    });

    test('is zero for a wallet with no opening balance', () async {
      final id = await addWallet();
      expect(await db.walletsDao.balanceOf(id), const Money(0, 'BDT'));
    });

    test('income adds and expense subtracts', () async {
      final id = await addWallet(initialMinor: 10000);
      await addTransaction(
        walletId: id,
        type: TransactionType.income,
        amountMinor: 5000,
      );
      await addTransaction(
        walletId: id,
        type: TransactionType.expense,
        amountMinor: 2500,
      );
      expect(await db.walletsDao.balanceOf(id), const Money(12500, 'BDT'));
    });

    test('goes negative rather than clamping', () async {
      final id = await addWallet(initialMinor: 1000);
      await addTransaction(
        walletId: id,
        type: TransactionType.expense,
        amountMinor: 2500,
      );
      expect(await db.walletsDao.balanceOf(id), const Money(-1500, 'BDT'));
    });

    test('a transfer debits the source and credits the destination', () async {
      final from = await addWallet(name: 'Cash', initialMinor: 100000);
      final to = await addWallet(name: 'Bank', initialMinor: 0);

      await addTransaction(
        walletId: from,
        type: TransactionType.transfer,
        amountMinor: 30000,
        transferTo: to,
      );

      expect(await db.walletsDao.balanceOf(from), const Money(70000, 'BDT'));
      expect(await db.walletsDao.balanceOf(to), const Money(30000, 'BDT'));
    });

    test('transfers in both directions net out', () async {
      final a = await addWallet(name: 'A', initialMinor: 50000);
      final b = await addWallet(name: 'B', initialMinor: 50000);

      await addTransaction(
        walletId: a,
        type: TransactionType.transfer,
        amountMinor: 20000,
        transferTo: b,
      );
      await addTransaction(
        walletId: b,
        type: TransactionType.transfer,
        amountMinor: 5000,
        transferTo: a,
      );

      expect(await db.walletsDao.balanceOf(a), const Money(35000, 'BDT'));
      expect(await db.walletsDao.balanceOf(b), const Money(65000, 'BDT'));
    });

    test('matches a hand-computed mixed fixture', () async {
      // 500.00 + 1200.00 - 85.50 - 300.00 out + 45.25 = 1359.75
      final wallet = await addWallet(initialMinor: 50000);
      final other = await addWallet(name: 'Bank');

      await addTransaction(
        walletId: wallet,
        type: TransactionType.income,
        amountMinor: 120000,
      );
      await addTransaction(
        walletId: wallet,
        type: TransactionType.expense,
        amountMinor: 8550,
      );
      await addTransaction(
        walletId: wallet,
        type: TransactionType.transfer,
        amountMinor: 30000,
        transferTo: other,
      );
      await addTransaction(
        walletId: wallet,
        type: TransactionType.income,
        amountMinor: 4525,
      );

      expect(await db.walletsDao.balanceOf(wallet), const Money(135975, 'BDT'));
      expect(await db.walletsDao.balanceOf(other), const Money(30000, 'BDT'));
    });

    test('deleting a transaction removes its effect', () async {
      final id = await addWallet(initialMinor: 10000);
      final txId = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: id,
              type: TransactionType.expense,
              amountMinor: 4000,
              currency: 'BDT',
              date: '2026-08-07',
            ),
          );
      expect(await db.walletsDao.balanceOf(id), const Money(6000, 'BDT'));

      await (db.delete(db.transactions)..where((t) => t.id.equals(txId))).go();
      expect(await db.walletsDao.balanceOf(id), const Money(10000, 'BDT'));
    });

    test('editing an amount is reflected immediately', () async {
      final id = await addWallet(initialMinor: 10000);
      final txId = await db
          .into(db.transactions)
          .insert(
            TransactionsCompanion.insert(
              walletId: id,
              type: TransactionType.expense,
              amountMinor: 4000,
              currency: 'BDT',
              date: '2026-08-07',
            ),
          );

      await (db.update(db.transactions)..where((t) => t.id.equals(txId))).write(
        const TransactionsCompanion(amountMinor: Value(1000)),
      );

      expect(await db.walletsDao.balanceOf(id), const Money(9000, 'BDT'));
    });

    test('deleting a wallet cascades its transactions away', () async {
      final id = await addWallet(initialMinor: 10000);
      await addTransaction(
        walletId: id,
        type: TransactionType.expense,
        amountMinor: 1000,
      );

      await db.walletsDao.deleteWallet(id);

      expect(await db.walletsDao.balanceOf(id), isNull);
      expect(await db.select(db.transactions).get(), isEmpty);
    });

    test('returns null for a wallet that does not exist', () async {
      expect(await db.walletsDao.balanceOf(999), isNull);
    });
  });

  group('schema constraints', () {
    test('rejects a non-positive amount', () async {
      final id = await addWallet();
      expect(
        () => addTransaction(
          walletId: id,
          type: TransactionType.expense,
          amountMinor: 0,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a transfer with no destination', () async {
      final id = await addWallet();
      expect(
        () => addTransaction(
          walletId: id,
          type: TransactionType.transfer,
          amountMinor: 100,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a non-transfer that has a destination', () async {
      final id = await addWallet();
      final other = await addWallet(name: 'Other');
      expect(
        () => addTransaction(
          walletId: id,
          type: TransactionType.expense,
          amountMinor: 100,
          transferTo: other,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a transfer to the same wallet', () async {
      final id = await addWallet();
      expect(
        () => addTransaction(
          walletId: id,
          type: TransactionType.transfer,
          amountMinor: 100,
          transferTo: id,
        ),
        throwsA(isA<Exception>()),
      );
    });
  });

  group('reactivity', () {
    test('watchWallets pushes a new list when a transaction lands', () async {
      final id = await addWallet(initialMinor: 10000);

      final seen = <Money>[];
      final subscription = db.walletsDao.watchWallets().listen(
        (wallets) => seen.add(wallets.single.balance),
      );
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      expect(seen, [const Money(10000, 'BDT')]);

      await addTransaction(
        walletId: id,
        type: TransactionType.income,
        amountMinor: 2500,
      );
      await pumpEventQueue();

      // The second emission is the point: nothing asked it to refresh.
      expect(seen, [const Money(10000, 'BDT'), const Money(12500, 'BDT')]);
    });

    test('archived wallets are excluded unless asked for', () async {
      final visible = await addWallet(name: 'Cash');
      final hidden = await addWallet(name: 'Old Card');
      await db.walletsDao.setArchived(hidden, archived: true);

      final active = await db.walletsDao.watchWallets().first;
      expect(active.map((w) => w.wallet.id), [visible]);

      final all = await db.walletsDao.watchWallets(includeArchived: true).first;
      expect(all, hasLength(2));
    });
  });
}
