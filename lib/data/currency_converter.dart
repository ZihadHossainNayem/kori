import '../core/money.dart';
import 'db.dart';

/// Converts between currencies using cached rates.
///
/// Only direct and inverse rates are used — no triangulation through a third
/// currency, which would silently compound two approximations. When a rate is
/// missing the amount is reported as unconvertible rather than guessed, so the
/// dashboard can say so instead of showing a wrong total.
class CurrencyConverter {
  CurrencyConverter(Iterable<ExchangeRate> rates)
    : _rates = {
        for (final rate in rates) '${rate.base}>${rate.quote}': rate.rate,
      };

  const CurrencyConverter.empty() : _rates = const {};

  final Map<String, double> _rates;

  /// Target units per unit of [from], or null if unknown.
  double? rate(String from, String to) {
    final source = from.toUpperCase();
    final target = to.toUpperCase();
    if (source == target) return 1;

    final direct = _rates['$source>$target'];
    if (direct != null) return direct;

    final inverse = _rates['$target>$source'];
    if (inverse != null && inverse != 0) return 1 / inverse;

    return null;
  }

  /// Null when no rate is known.
  Money? convert(Money amount, String target) {
    final found = rate(amount.currency, target);
    if (found == null) return null;
    return amount.convertTo(target, found);
  }

  /// Sums [amounts] into [target].
  ///
  /// [unconvertible] counts amounts left out for want of a rate; the UI must
  /// surface it rather than presenting an incomplete total as complete.
  ({Money total, int unconvertible}) total(
    Iterable<Money> amounts,
    String target,
  ) {
    var total = Money.zero(target);
    var unconvertible = 0;
    for (final amount in amounts) {
      final converted = convert(amount, target);
      if (converted == null) {
        unconvertible += 1;
      } else {
        total += converted;
      }
    }
    return (total: total, unconvertible: unconvertible);
  }
}
