import 'package:intl/intl.dart';

const Set<String> _zeroDecimalCurrencies = {
  'BIF', 'CLP', 'DJF', 'GNF', 'ISK', 'JPY', 'KMF', 'KRW', 'PYG',
  'RWF', 'UGX', 'VND', 'VUV', 'XAF', 'XOF', 'XPF',
};

const Set<String> _threeDecimalCurrencies = {
  'BHD', 'IQD', 'JOD', 'KWD', 'LYD', 'OMR', 'TND',
};

final RegExp _digitsOnly = RegExp(r'^\d+$');

/// An amount of money as a whole number of minor units — paisa, cents, fils.
///
/// Never a `double`: floating-point error is invisible until totals stop
/// matching. Mixing currencies throws; cross rates go through [convertTo].
class Money implements Comparable<Money> {
  const Money(this.minor, this.currency);

  const Money.zero(this.currency) : minor = 0;

  /// Negative is meaningful: an overdrawn wallet, a month that lost money.
  final int minor;

  /// ISO-4217 code, upper case.
  final String currency;

  /// Decimal places for [currency]: 2 for most, 0 for JPY/KRW/VND, 3 for KWD.
  static int decimalsFor(String currency) {
    final code = currency.toUpperCase();
    if (_zeroDecimalCurrencies.contains(code)) return 0;
    if (_threeDecimalCurrencies.contains(code)) return 3;
    return 2;
  }

  int get decimals => decimalsFor(currency);

  bool get isZero => minor == 0;
  bool get isNegative => minor < 0;

  Money operator +(Money other) {
    _assertSameCurrency(other, '+');
    return Money(minor + other.minor, currency);
  }

  Money operator -(Money other) {
    _assertSameCurrency(other, '-');
    return Money(minor - other.minor, currency);
  }

  Money operator -() => Money(-minor, currency);

  Money abs() => Money(minor.abs(), currency);

  /// Multiplies by a factor, rounding to a whole minor unit. For percentages
  /// like budget thresholds — not for FX, which needs [convertTo].
  Money scale(num factor) => Money((minor * factor).round(), currency);

  /// Sums [amounts], which must share a currency. An empty sum has no currency
  /// of its own, hence [fallbackCurrency].
  static Money sum(Iterable<Money> amounts, {required String fallbackCurrency}) {
    var total = Money.zero(fallbackCurrency);
    var started = false;
    for (final amount in amounts) {
      total = started ? total + amount : amount;
      started = true;
    }
    return total;
  }

  /// Converts at [rate], given as target units per source unit.
  ///
  /// [rate] is a `double` because rates are approximate anyway, but the result
  /// rounds to a whole minor unit immediately so nothing float-shaped is stored.
  Money convertTo(String target, double rate) {
    final targetCode = target.toUpperCase();
    final shift = decimalsFor(targetCode) - decimals;
    var converted = minor * rate;
    if (shift > 0) {
      for (var i = 0; i < shift; i++) {
        converted *= 10;
      }
    } else if (shift < 0) {
      for (var i = 0; i < -shift; i++) {
        converted /= 10;
      }
    }
    return Money(converted.round(), targetCode);
  }

  /// Parses typed or imported text: `1234`, `1,234.56`, `-89.9`.
  ///
  /// Shifts digits as text rather than via `double`, so `0.07` cannot arrive as
  /// `0.06999…`. Excess precision rounds half-up. Null if not a number.
  static Money? tryParse(String input, String currency) {
    final decimals = decimalsFor(currency);
    var text = input.trim().replaceAll(',', '').replaceAll(' ', '');
    if (text.isEmpty) return null;

    var negative = false;
    if (text.startsWith('-')) {
      negative = true;
      text = text.substring(1);
    } else if (text.startsWith('+')) {
      text = text.substring(1);
    }
    if (text.isEmpty) return null;

    final parts = text.split('.');
    if (parts.length > 2) return null;
    // A bare "." carries no digits.
    if (parts[0].isEmpty && (parts.length < 2 || parts[1].isEmpty)) return null;

    final whole = parts[0].isEmpty ? '0' : parts[0];
    if (!_digitsOnly.hasMatch(whole)) return null;

    var fraction = parts.length == 2 ? parts[1] : '';
    if (fraction.isNotEmpty && !_digitsOnly.hasMatch(fraction)) return null;

    var roundUp = false;
    if (fraction.length > decimals) {
      roundUp = int.parse(fraction[decimals]) >= 5;
      fraction = fraction.substring(0, decimals);
    } else {
      fraction = fraction.padRight(decimals, '0');
    }

    final parsed = int.tryParse('$whole$fraction');
    if (parsed == null) return null;

    final value = parsed + (roundUp ? 1 : 0);
    return Money(negative ? -value : value, currency.toUpperCase());
  }

  /// Decimal text without a symbol — `1234.56`. For CSV cells and edit fields.
  String toPlainString() {
    final sign = isNegative ? '-' : '';
    final digits = minor.abs().toString().padLeft(decimals + 1, '0');
    if (decimals == 0) return '$sign$digits';
    final split = digits.length - decimals;
    return '$sign${digits.substring(0, split)}.${digits.substring(split)}';
  }

  /// Formats with the currency symbol. [compact] collapses thousands to
  /// `৳12.3k` so amounts fit dense rows and chart labels.
  String format({String? locale, bool compact = false}) {
    final format = NumberFormat.simpleCurrency(
      locale: locale,
      name: currency,
      decimalDigits: compact ? 0 : decimals,
    );

    if (!compact) return format.format(_asMajorDouble());

    final symbol = format.currencySymbol;
    final absMinor = minor.abs();
    final unit = _pow10(decimals);
    final sign = isNegative ? '-' : '';

    for (final threshold in _compactThresholds) {
      if (absMinor >= threshold.multiplier * unit) {
        final value = absMinor / (threshold.multiplier * unit);
        final text = value >= 100 || value == value.roundToDouble()
            ? value.round().toString()
            : value.toStringAsFixed(1);
        return '$sign$symbol$text${threshold.suffix}';
      }
    }
    return format.format(_asMajorDouble());
  }

  /// For chart plotting only, which is approximate by nature. Never feed the
  /// result back into stored data.
  double toDoubleForCharts() => _asMajorDouble();

  double _asMajorDouble() => minor / _pow10(decimals);

  static int _pow10(int exponent) {
    var result = 1;
    for (var i = 0; i < exponent; i++) {
      result *= 10;
    }
    return result;
  }

  void _assertSameCurrency(Money other, String operation) {
    if (other.currency != currency) {
      throw ArgumentError(
        'Cannot apply "$operation" to $currency and ${other.currency}. '
        'Convert one side with convertTo() first.',
      );
    }
  }

  @override
  int compareTo(Money other) {
    _assertSameCurrency(other, 'compareTo');
    return minor.compareTo(other.minor);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is Money && other.minor == minor && other.currency == currency;

  @override
  int get hashCode => Object.hash(minor, currency);

  @override
  String toString() => 'Money(${toPlainString()} $currency)';
}

class _CompactThreshold {
  const _CompactThreshold(this.multiplier, this.suffix);
  final int multiplier;
  final String suffix;
}

const List<_CompactThreshold> _compactThresholds = [
  _CompactThreshold(1000000000, 'B'),
  _CompactThreshold(1000000, 'M'),
  _CompactThreshold(1000, 'k'),
];
