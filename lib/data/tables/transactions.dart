import 'package:drift/drift.dart';

import 'categories.dart';
import 'recurring_rules.dart';
import 'wallets.dart';

/// A transfer is one row, not a matched pair, so a crash cannot leave half of
/// one behind.
enum TransactionType { income, expense, transfer }

@TableIndex(name: 'idx_tx_wallet_date', columns: {#walletId, #date})
@TableIndex(name: 'idx_tx_date', columns: {#date})
@TableIndex(name: 'idx_tx_category_date', columns: {#categoryId, #date})
@TableIndex(name: 'idx_tx_transfer_target', columns: {#transferToWalletId})
class Transactions extends Table {
  IntColumn get id => integer().autoIncrement()();

  @ReferenceName('transactions')
  IntColumn get walletId =>
      integer().references(Wallets, #id, onDelete: KeyAction.cascade)();

  /// Null for transfers, and for rows whose category was deleted.
  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  TextColumn get type => textEnum<TransactionType>()();

  /// Always positive; direction comes from [type]. Keeps the balance view's
  /// arithmetic explicit instead of hiding it in a sign.
  IntColumn get amountMinor => integer()();

  /// Copied from the wallet at write time, so history survives a later change
  /// to the wallet's currency.
  TextColumn get currency => text().withLength(min: 3, max: 3)();

  TextColumn get note => text().nullable()();

  /// Calendar day as `YYYY-MM-DD`. Text, not a timestamp — see `core/dates.dart`.
  TextColumn get date => text().withLength(min: 10, max: 10)();

  /// Set if and only if [type] is [TransactionType.transfer].
  @ReferenceName('incomingTransfers')
  IntColumn get transferToWalletId => integer().nullable().references(
    Wallets,
    #id,
    onDelete: KeyAction.setNull,
  )();

  IntColumn get recurringRuleId => integer().nullable().references(
    RecurringRules,
    #id,
    onDelete: KeyAction.setNull,
  )();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  /// Unused so far. It is what would make optional end-to-end-encrypted sync
  /// possible later without a migration.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (amount_minor > 0)',
    // A transfer has a destination; nothing else does.
    "CHECK ((type = 'transfer') = (transfer_to_wallet_id IS NOT NULL))",
    'CHECK (transfer_to_wallet_id IS NULL '
        'OR transfer_to_wallet_id != wallet_id)',
    "CHECK (type != 'transfer' OR category_id IS NULL)",
  ];
}
