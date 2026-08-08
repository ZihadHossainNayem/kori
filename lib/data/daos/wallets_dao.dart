import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../db.dart';
import '../tables/transactions.dart';
import '../tables/wallets.dart';

part 'wallets_dao.g.dart';

/// Current balance per wallet, derived rather than stored — a trigger-maintained
/// column corrupts permanently on one bad branch, with nothing to detect it.
///
/// Raw SQL rather than a drift view: drift's analyser mistyped the join
/// (`wallets.id` as `String?`), and a real view lets an exported `.db` explain
/// its own balances in any SQLite browser. Amounts are stored positive, so
/// every branch states its own sign.
const String walletBalancesViewSql = '''
CREATE VIEW wallet_balances AS
SELECT
  wallets.id AS wallet_id,
  wallets.initial_balance_minor + COALESCE(SUM(
    CASE
      WHEN transactions.wallet_id = wallets.id
           AND transactions.type = 'income'   THEN transactions.amount_minor
      WHEN transactions.wallet_id = wallets.id
           AND transactions.type = 'expense'  THEN -transactions.amount_minor
      WHEN transactions.wallet_id = wallets.id
           AND transactions.type = 'transfer' THEN -transactions.amount_minor
      WHEN transactions.transfer_to_wallet_id = wallets.id
           AND transactions.type = 'transfer' THEN transactions.amount_minor
      ELSE 0
    END
  ), 0) AS balance_minor
FROM wallets
LEFT JOIN transactions
  ON transactions.wallet_id = wallets.id
  OR transactions.transfer_to_wallet_id = wallets.id
GROUP BY wallets.id
''';

/// Replaces the view with the definition above, on every open.
///
/// `CREATE VIEW IF NOT EXISTS` would keep an old definition forever, so dropping
/// first is what stops any migration path leaving this stale.
Future<void> syncWalletBalancesView(KoriDatabase db) async {
  await db.customStatement('DROP VIEW IF EXISTS wallet_balances');
  await db.customStatement(walletBalancesViewSql);
}

class WalletWithBalance {
  const WalletWithBalance({required this.wallet, required this.balance});

  final Wallet wallet;
  final Money balance;
}

@DriftAccessor(tables: [Wallets, Transactions])
class WalletsDao extends DatabaseAccessor<KoriDatabase> with _$WalletsDaoMixin {
  WalletsDao(super.attachedDatabase);

  /// Wallets in display order with live balances. `readsFrom` is what makes this
  /// reactive, so no screen has to remember to refresh itself.
  Stream<List<WalletWithBalance>> watchWallets({bool includeArchived = false}) {
    final where = includeArchived ? '' : 'WHERE wallets.archived = 0 ';
    return customSelect(
      'SELECT wallets.*, wallet_balances.balance_minor '
      'FROM wallets '
      'JOIN wallet_balances ON wallet_balances.wallet_id = wallets.id '
      '$where'
      'ORDER BY wallets.sort_order, wallets.id',
      readsFrom: {wallets, transactions},
    ).watch().map((rows) => rows.map(_mapRow).toList());
  }

  /// Null if the wallet does not exist.
  Future<Money?> balanceOf(int walletId) async {
    final row = await customSelect(
      'SELECT wallets.currency, wallet_balances.balance_minor '
      'FROM wallets '
      'JOIN wallet_balances ON wallet_balances.wallet_id = wallets.id '
      'WHERE wallets.id = ?',
      variables: [Variable<int>(walletId)],
      readsFrom: {wallets, transactions},
    ).getSingleOrNull();

    if (row == null) return null;
    return Money(row.read<int>('balance_minor'), row.read<String>('currency'));
  }

  Future<int> createWallet(WalletsCompanion wallet) =>
      into(wallets).insert(wallet);

  /// Counts rows on either side of a transfer. Used to lock a wallet's currency
  /// once money has been recorded in it — transactions store their own currency,
  /// so switching afterwards would leave the balance summing mixed units.
  Future<int> transactionCount(int walletId) async {
    final count = transactions.id.count();
    final row =
        await (selectOnly(transactions)
              ..addColumns([count])
              ..where(
                transactions.walletId.equals(walletId) |
                    transactions.transferToWalletId.equals(walletId),
              ))
            .getSingle();
    return row.read(count) ?? 0;
  }

  Future<bool> updateWallet(Wallet wallet) =>
      update(wallets).replace(wallet.copyWith(updatedAt: DateTime.now()));

  /// Prefer this to deletion in the UI: archiving keeps history, whereas
  /// deleting a wallet cascades its transactions away.
  Future<int> setArchived(int walletId, {required bool archived}) =>
      (update(wallets)..where((w) => w.id.equals(walletId))).write(
        WalletsCompanion(
          archived: Value(archived),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<int> deleteWallet(int walletId) =>
      (delete(wallets)..where((w) => w.id.equals(walletId))).go();

  WalletWithBalance _mapRow(QueryRow row) {
    final wallet = wallets.map(row.data);
    return WalletWithBalance(
      wallet: wallet,
      balance: Money(row.read<int>('balance_minor'), wallet.currency),
    );
  }
}
