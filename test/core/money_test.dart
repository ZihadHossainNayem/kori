import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/money.dart';

void main() {
  group('decimalsFor', () {
    test('defaults to two places', () {
      expect(Money.decimalsFor('BDT'), 2);
      expect(Money.decimalsFor('USD'), 2);
      expect(Money.decimalsFor('EUR'), 2);
    });

    test('knows zero-decimal currencies', () {
      expect(Money.decimalsFor('JPY'), 0);
      expect(Money.decimalsFor('KRW'), 0);
      expect(Money.decimalsFor('VND'), 0);
    });

    test('knows three-decimal currencies', () {
      expect(Money.decimalsFor('KWD'), 3);
      expect(Money.decimalsFor('BHD'), 3);
      expect(Money.decimalsFor('OMR'), 3);
    });

    test('is case insensitive', () {
      expect(Money.decimalsFor('jpy'), 0);
      expect(Money.decimalsFor('kwd'), 3);
    });
  });

  group('tryParse', () {
    test('shifts whole numbers into minor units', () {
      expect(Money.tryParse('1234', 'BDT'), const Money(123400, 'BDT'));
      expect(Money.tryParse('0', 'BDT'), const Money(0, 'BDT'));
    });

    test('handles decimals and group separators', () {
      expect(Money.tryParse('12.34', 'BDT'), const Money(1234, 'BDT'));
      expect(Money.tryParse('1,234.56', 'BDT'), const Money(123456, 'BDT'));
      expect(Money.tryParse('1 234.56', 'BDT'), const Money(123456, 'BDT'));
    });

    test('pads short fractions', () {
      expect(Money.tryParse('12.3', 'BDT'), const Money(1230, 'BDT'));
      expect(Money.tryParse('.5', 'BDT'), const Money(50, 'BDT'));
    });

    test('handles signs', () {
      expect(Money.tryParse('-89.9', 'BDT'), const Money(-8990, 'BDT'));
      expect(Money.tryParse('+12', 'BDT'), const Money(1200, 'BDT'));
    });

    test('rounds excess precision half-up', () {
      expect(Money.tryParse('0.005', 'BDT'), const Money(1, 'BDT'));
      expect(Money.tryParse('0.004', 'BDT'), const Money(0, 'BDT'));
      expect(Money.tryParse('1.235', 'BDT'), const Money(124, 'BDT'));
      expect(Money.tryParse('1.234', 'BDT'), const Money(123, 'BDT'));
    });

    test('respects currency precision', () {
      expect(Money.tryParse('100', 'JPY'), const Money(100, 'JPY'));
      expect(Money.tryParse('100.6', 'JPY'), const Money(101, 'JPY'));
      expect(Money.tryParse('12.345', 'KWD'), const Money(12345, 'KWD'));
      expect(Money.tryParse('12.3456', 'KWD'), const Money(12346, 'KWD'));
    });

    test('avoids binary floating-point error', () {
      // Via double, 0.07 * 100 is 6.999… and truncates to 6.
      expect(Money.tryParse('0.07', 'USD'), const Money(7, 'USD'));
      expect(Money.tryParse('1.005', 'USD'), const Money(101, 'USD'));
      expect(Money.tryParse('8.615', 'USD'), const Money(862, 'USD'));
    });

    test('rejects non-numbers', () {
      expect(Money.tryParse('abc', 'BDT'), isNull);
      expect(Money.tryParse('', 'BDT'), isNull);
      expect(Money.tryParse('   ', 'BDT'), isNull);
      expect(Money.tryParse('1.2.3', 'BDT'), isNull);
      expect(Money.tryParse('.', 'BDT'), isNull);
      expect(Money.tryParse('-', 'BDT'), isNull);
      expect(Money.tryParse('12a', 'BDT'), isNull);
    });

    test('normalises the currency code', () {
      expect(Money.tryParse('1', 'bdt')?.currency, 'BDT');
    });
  });

  group('toPlainString', () {
    test('renders two-decimal currencies', () {
      expect(const Money(123456, 'BDT').toPlainString(), '1234.56');
      expect(const Money(5, 'BDT').toPlainString(), '0.05');
      expect(const Money(0, 'BDT').toPlainString(), '0.00');
      expect(const Money(-8990, 'BDT').toPlainString(), '-89.90');
    });

    test('renders zero- and three-decimal currencies', () {
      expect(const Money(100, 'JPY').toPlainString(), '100');
      expect(const Money(0, 'JPY').toPlainString(), '0');
      expect(const Money(12345, 'KWD').toPlainString(), '12.345');
      expect(const Money(5, 'KWD').toPlainString(), '0.005');
    });

    test('round-trips through tryParse', () {
      for (final money in [
        const Money(123456, 'BDT'),
        const Money(-8990, 'USD'),
        const Money(100, 'JPY'),
        const Money(12345, 'KWD'),
        const Money(0, 'BDT'),
      ]) {
        expect(Money.tryParse(money.toPlainString(), money.currency), money);
      }
    });
  });

  group('arithmetic', () {
    test('adds and subtracts', () {
      expect(
        const Money(1000, 'BDT') + const Money(250, 'BDT'),
        const Money(1250, 'BDT'),
      );
      expect(
        const Money(1000, 'BDT') - const Money(250, 'BDT'),
        const Money(750, 'BDT'),
      );
    });

    test('goes negative rather than clamping', () {
      expect(
        const Money(100, 'BDT') - const Money(250, 'BDT'),
        const Money(-150, 'BDT'),
      );
    });

    test('negates and takes absolute value', () {
      expect(-const Money(500, 'BDT'), const Money(-500, 'BDT'));
      expect(const Money(-500, 'BDT').abs(), const Money(500, 'BDT'));
    });

    test('refuses to mix currencies', () {
      expect(
        () => const Money(100, 'BDT') + const Money(100, 'USD'),
        throwsArgumentError,
      );
      expect(
        () => const Money(100, 'BDT') - const Money(100, 'USD'),
        throwsArgumentError,
      );
      expect(
        () => const Money(100, 'BDT').compareTo(const Money(100, 'USD')),
        throwsArgumentError,
      );
    });

    test('scales for percentage thresholds', () {
      expect(const Money(10000, 'BDT').scale(0.8), const Money(8000, 'BDT'));
      // Rounds rather than truncating.
      expect(const Money(333, 'BDT').scale(0.5), const Money(167, 'BDT'));
    });

    test('sums a list', () {
      expect(
        Money.sum(
          const [Money(100, 'BDT'), Money(250, 'BDT'), Money(-50, 'BDT')],
          fallbackCurrency: 'BDT',
        ),
        const Money(300, 'BDT'),
      );
    });

    test('sums an empty list to zero in the fallback currency', () {
      expect(
        Money.sum(const [], fallbackCurrency: 'USD'),
        const Money(0, 'USD'),
      );
    });
  });

  group('convertTo', () {
    test('converts between equal-precision currencies', () {
      // 100.00 USD at 120 BDT per USD.
      expect(
        const Money(10000, 'USD').convertTo('BDT', 120),
        const Money(1200000, 'BDT'),
      );
    });

    test('shifts precision when decimals differ', () {
      // 1000 JPY (0 decimals) at 0.0064 USD per JPY = 6.40 USD.
      expect(
        const Money(1000, 'JPY').convertTo('USD', 0.0064),
        const Money(640, 'USD'),
      );
      // 10.00 USD at 157 JPY per USD = 1570 JPY.
      expect(
        const Money(1000, 'USD').convertTo('JPY', 157),
        const Money(1570, 'JPY'),
      );
    });

    test('rounds to a whole minor unit', () {
      expect(
        const Money(1, 'USD').convertTo('BDT', 1.235),
        const Money(1, 'BDT'),
      );
    });

    test('normalises the target code', () {
      expect(const Money(100, 'USD').convertTo('bdt', 1).currency, 'BDT');
    });
  });

  group('comparison', () {
    test('orders amounts', () {
      expect(const Money(100, 'BDT') < const Money(200, 'BDT'), isTrue);
      expect(const Money(200, 'BDT') > const Money(100, 'BDT'), isTrue);
      expect(const Money(100, 'BDT') <= const Money(100, 'BDT'), isTrue);
      expect(const Money(100, 'BDT') >= const Money(100, 'BDT'), isTrue);
    });

    test('treats value and currency as identity', () {
      expect(const Money(100, 'BDT'), const Money(100, 'BDT'));
      expect(const Money(100, 'BDT'), isNot(const Money(100, 'USD')));
      expect(
        const Money(100, 'BDT').hashCode,
        const Money(100, 'BDT').hashCode,
      );
    });

    test('reports zero and sign', () {
      expect(const Money.zero('BDT').isZero, isTrue);
      expect(const Money(-1, 'BDT').isNegative, isTrue);
      expect(const Money(1, 'BDT').isNegative, isFalse);
    });
  });

  group('format', () {
    test('includes the amount', () {
      expect(
        const Money(123456, 'USD').format(locale: 'en_US'),
        contains('1,234.56'),
      );
    });

    test('collapses thousands when compact', () {
      expect(
        const Money(123400, 'USD').format(locale: 'en_US', compact: true),
        contains('1.2k'),
      );
      expect(
        const Money(12345600, 'USD').format(locale: 'en_US', compact: true),
        contains('123k'),
      );
      expect(
        const Money(500000000, 'USD').format(locale: 'en_US', compact: true),
        contains('5M'),
      );
    });

    test('keeps small amounts unabbreviated when compact', () {
      final formatted =
          const Money(45600, 'USD').format(locale: 'en_US', compact: true);
      expect(formatted, isNot(contains('k')));
      expect(formatted, contains('456'));
    });

    test('marks negatives when compact', () {
      expect(
        const Money(-123400, 'USD').format(locale: 'en_US', compact: true),
        startsWith('-'),
      );
    });
  });
}
