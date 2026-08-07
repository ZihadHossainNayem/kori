import 'package:drift/drift.dart';

/// Descriptive only — drives the default icon and grouping, never behaviour.
enum WalletType { cash, bank, mobile, card, savings, other }

/// A place money sits. One currency per wallet, so every stored amount is
/// unambiguous and conversion happens only at display time.
@TableIndex(name: 'idx_wallets_sort', columns: {#archived, #sortOrder})
class Wallets extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get name => text().withLength(min: 1, max: 60)();

  TextColumn get type =>
      textEnum<WalletType>().withDefault(const Constant('cash'))();

  /// ISO-4217 code, upper case.
  TextColumn get currency => text().withLength(min: 3, max: 3)();

  /// Balance before any recorded transaction. The current balance is derived —
  /// see the `wallet_balances` view.
  IntColumn get initialBalanceMinor =>
      integer().withDefault(const Constant(0))();

  /// ARGB.
  IntColumn get color => integer()();

  /// Key into the app's icon map, not a font code point, so the icon set can
  /// change without a migration.
  TextColumn get icon => text().withDefault(const Constant('wallet'))();

  /// Archived wallets keep their history but leave pickers and totals.
  BoolColumn get archived => boolean().withDefault(const Constant(false))();

  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}
