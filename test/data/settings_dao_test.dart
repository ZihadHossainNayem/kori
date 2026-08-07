import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kori/data/daos/settings_dao.dart';
import 'package:kori/data/db.dart';

void main() {
  late KoriDatabase db;
  late SettingsDao dao;

  setUp(() {
    db = KoriDatabase(NativeDatabase.memory());
    dao = db.settingsDao;
  });

  tearDown(() async {
    await db.close();
  });

  group('preferences', () {
    test('an unset key reads as null', () async {
      expect(await dao.read(PreferenceKeys.displayCurrency), isNull);
    });

    test('writes then reads back', () async {
      await dao.write(PreferenceKeys.displayCurrency, 'BDT');
      expect(await dao.read(PreferenceKeys.displayCurrency), 'BDT');
    });

    test('writing the same key replaces rather than duplicating', () async {
      await dao.write(PreferenceKeys.displayCurrency, 'BDT');
      await dao.write(PreferenceKeys.displayCurrency, 'USD');

      expect(await dao.read(PreferenceKeys.displayCurrency), 'USD');
      expect(await db.select(db.preferences).get(), hasLength(1));
    });

    test('watch emits on change', () async {
      final seen = <String?>[];
      final subscription =
          dao.watch(PreferenceKeys.displayCurrency).listen(seen.add);
      addTearDown(subscription.cancel);

      await pumpEventQueue();
      await dao.write(PreferenceKeys.displayCurrency, 'BDT');
      await pumpEventQueue();

      expect(seen, [null, 'BDT']);
    });

    test('clear removes the key', () async {
      await dao.write(PreferenceKeys.appLock, 'true');
      await dao.clear(PreferenceKeys.appLock);
      expect(await dao.read(PreferenceKeys.appLock), isNull);
    });
  });

  group('exchange rates', () {
    test('upserts and normalises currency codes', () async {
      await dao.upsertRate(base: 'usd', quote: 'bdt', rate: 120);

      final rates = await dao.watchRates().first;
      expect(rates.single.base, 'USD');
      expect(rates.single.quote, 'BDT');
      expect(rates.single.rate, 120);
      expect(rates.single.manual, isTrue);
    });

    test('a second write for the same pair replaces it', () async {
      await dao.upsertRate(base: 'USD', quote: 'BDT', rate: 120);
      await dao.upsertRate(
        base: 'USD',
        quote: 'BDT',
        rate: 122.5,
        manual: false,
        fetchedAt: DateTime(2026, 8, 7),
      );

      final rates = await dao.watchRates().first;
      expect(rates, hasLength(1));
      expect(rates.single.rate, 122.5);
      expect(rates.single.manual, isFalse);
      expect(rates.single.fetchedAt, DateTime(2026, 8, 7));
    });

    test('rejects a non-positive rate', () {
      expect(
        () => dao.upsertRate(base: 'USD', quote: 'BDT', rate: 0),
        throwsA(isA<Exception>()),
      );
    });

    test('rejects a self-referential pair', () {
      expect(
        () => dao.upsertRate(base: 'USD', quote: 'USD', rate: 1),
        throwsA(isA<Exception>()),
      );
    });

    test('deletes a pair', () async {
      await dao.upsertRate(base: 'USD', quote: 'BDT', rate: 120);
      await dao.deleteRate('usd', 'bdt');
      expect(await dao.watchRates().first, isEmpty);
    });
  });
}
