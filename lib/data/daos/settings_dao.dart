import 'package:drift/drift.dart';

import '../db.dart';
import '../tables/misc.dart';

part 'settings_dao.g.dart';

/// Preference keys, in one place so a typo cannot silently create a second
/// setting that nothing reads.
abstract final class PreferenceKeys {
  static const displayCurrency = 'display_currency';
  static const themeMode = 'theme_mode';
  static const appLock = 'app_lock';
  static const onboardingSeen = 'onboarding_seen';
  static const lastWalletId = 'last_wallet_id';
}

@DriftAccessor(tables: [Preferences, ExchangeRates])
class SettingsDao extends DatabaseAccessor<KoriDatabase>
    with _$SettingsDaoMixin {
  SettingsDao(super.attachedDatabase);

  Stream<String?> watch(String key) =>
      (select(preferences)..where((p) => p.key.equals(key)))
          .watchSingleOrNull()
          .map((row) => row?.value);

  Future<String?> read(String key) async {
    final row = await (select(
      preferences,
    )..where((p) => p.key.equals(key))).getSingleOrNull();
    return row?.value;
  }

  Future<void> write(String key, String value) => into(preferences).insert(
    PreferencesCompanion.insert(key: key, value: value),
    mode: InsertMode.insertOrReplace,
  );

  Future<int> clear(String key) =>
      (delete(preferences)..where((p) => p.key.equals(key))).go();

  Stream<List<ExchangeRate>> watchRates() =>
      (select(exchangeRates)..orderBy([
            (r) => OrderingTerm.asc(r.base),
            (r) => OrderingTerm.asc(r.quote),
          ]))
          .watch();

  Future<void> upsertRate({
    required String base,
    required String quote,
    required double rate,
    bool manual = true,
    DateTime? fetchedAt,
  }) {
    return into(exchangeRates).insert(
      ExchangeRatesCompanion.insert(
        base: base.toUpperCase(),
        quote: quote.toUpperCase(),
        rate: rate,
        manual: Value(manual),
        fetchedAt: Value(fetchedAt),
      ),
      mode: InsertMode.insertOrReplace,
    );
  }

  Future<int> deleteRate(String base, String quote) =>
      (delete(exchangeRates)..where(
            (r) =>
                r.base.equals(base.toUpperCase()) &
                r.quote.equals(quote.toUpperCase()),
          ))
          .go();
}
