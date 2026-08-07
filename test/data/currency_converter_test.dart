import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';
import 'package:kori/data/currency_converter.dart';
import 'package:kori/data/db.dart';

ExchangeRate _rate(String base, String quote, double rate) =>
    ExchangeRate(base: base, quote: quote, rate: rate, manual: true);

void main() {
  group('rate lookup', () {
    test('a currency converts to itself at 1', () {
      const converter = CurrencyConverter.empty();
      expect(converter.rate('BDT', 'BDT'), 1);
      expect(converter.rate('bdt', 'BDT'), 1);
    });

    test('uses a direct rate', () {
      final converter = CurrencyConverter([_rate('USD', 'BDT', 120)]);
      expect(converter.rate('USD', 'BDT'), 120);
    });

    test('inverts a rate stored the other way round', () {
      final converter = CurrencyConverter([_rate('USD', 'BDT', 125)]);
      expect(converter.rate('BDT', 'USD'), closeTo(1 / 125, 1e-12));
    });

    test('returns null instead of triangulating', () {
      // USD->BDT and USD->EUR are known, but EUR->BDT is not. Chaining them
      // would compound two approximations into a number we cannot justify.
      final converter = CurrencyConverter([
        _rate('USD', 'BDT', 120),
        _rate('USD', 'EUR', 0.92),
      ]);
      expect(converter.rate('EUR', 'BDT'), isNull);
    });

    test('returns null for an unknown pair', () {
      const converter = CurrencyConverter.empty();
      expect(converter.rate('USD', 'BDT'), isNull);
    });
  });

  group('convert', () {
    test('converts between two-decimal currencies', () {
      final converter = CurrencyConverter([_rate('USD', 'BDT', 120)]);
      expect(
        converter.convert(const Money(10000, 'USD'), 'BDT'),
        const Money(1200000, 'BDT'),
      );
    });

    test('handles differing precision', () {
      final converter = CurrencyConverter([_rate('USD', 'JPY', 157)]);
      expect(
        converter.convert(const Money(1000, 'USD'), 'JPY'),
        const Money(1570, 'JPY'),
      );
    });

    test('returns null when the rate is unknown', () {
      const converter = CurrencyConverter.empty();
      expect(converter.convert(const Money(100, 'USD'), 'BDT'), isNull);
    });
  });

  group('total', () {
    test('sums mixed currencies into the target', () {
      final converter = CurrencyConverter([_rate('USD', 'BDT', 120)]);
      final result = converter.total(const [
        Money(50000, 'BDT'),
        Money(10000, 'USD'),
      ], 'BDT');
      expect(result.total, const Money(1250000, 'BDT'));
      expect(result.unconvertible, 0);
    });

    test(
      'counts amounts it could not convert rather than dropping them silently',
      () {
        final converter = CurrencyConverter([_rate('USD', 'BDT', 120)]);
        final result = converter.total(const [
          Money(50000, 'BDT'),
          Money(10000, 'EUR'),
        ], 'BDT');
        expect(result.total, const Money(50000, 'BDT'));
        expect(result.unconvertible, 1);
      },
    );

    test('an empty list totals to zero in the target', () {
      const converter = CurrencyConverter.empty();
      final result = converter.total(const [], 'BDT');
      expect(result.total, const Money(0, 'BDT'));
      expect(result.unconvertible, 0);
    });
  });
}
