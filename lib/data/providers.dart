import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'currency_converter.dart';
import 'daos/categories_dao.dart';
import 'daos/settings_dao.dart';
import 'daos/transactions_dao.dart';
import 'daos/wallets_dao.dart';
import 'db.dart';
import 'tables/categories.dart';

/// The single database instance for the app's lifetime.
///
/// Tests override it with an in-memory executor:
/// `databaseProvider.overrideWithValue(KoriDatabase(NativeDatabase.memory()))`.
final Provider<KoriDatabase> databaseProvider = Provider<KoriDatabase>((ref) {
  final database = KoriDatabase();
  ref.onDispose(database.close);
  return database;
});

final walletsDaoProvider = Provider<WalletsDao>(
  (ref) => ref.watch(databaseProvider).walletsDao,
);
final categoriesDaoProvider = Provider<CategoriesDao>(
  (ref) => ref.watch(databaseProvider).categoriesDao,
);
final transactionsDaoProvider = Provider<TransactionsDao>(
  (ref) => ref.watch(databaseProvider).transactionsDao,
);
final settingsDaoProvider = Provider<SettingsDao>(
  (ref) => ref.watch(databaseProvider).settingsDao,
);

final walletsProvider = StreamProvider<List<WalletWithBalance>>(
  (ref) => ref.watch(walletsDaoProvider).watchWallets(),
);

final categoriesProvider =
    StreamProvider.family<List<Category>, CategoryType>(
  (ref, type) => ref.watch(categoriesDaoProvider).watchByType(type),
);

final exchangeRatesProvider = StreamProvider<CurrencyConverter>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watchRates()
      .map(CurrencyConverter.new),
);

/// The currency totals are shown in. Defaults to the device locale's currency
/// until the user picks one, so the first launch is already sensible.
final displayCurrencyProvider = StreamProvider<String>(
  (ref) => ref
      .watch(settingsDaoProvider)
      .watch(PreferenceKeys.displayCurrency)
      .map((stored) => stored ?? deviceDefaultCurrency()),
);

/// The currency of the device's locale — BDT for en_BD, JPY for ja_JP. Falls
/// back to USD when the locale has no currency data.
///
/// Catches broadly on purpose: intl throws ArgumentError (an Error, not an
/// Exception) for locales it has no data for, and picking a default currency
/// must never be able to break startup.
String deviceDefaultCurrency() {
  try {
    final locale = PlatformDispatcher.instance.locale.toString();
    return NumberFormat.simpleCurrency(locale: locale).currencyName ?? 'USD';
  } catch (_) {
    return 'USD';
  }
}
