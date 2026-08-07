import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/daos/analytics_dao.dart';
import '../../data/providers.dart';

/// The period the insights screen is showing.
class AnalyticsRange {
  const AnalyticsRange({
    required this.label,
    required this.from,
    required this.to,
  });

  final String label;
  final String from;
  final String to;

  /// Daily points for short spans, monthly for long ones — 60 daily points is a
  /// readable line, 400 is a smear.
  Granularity get granularity {
    final span = parseDayKey(to).difference(parseDayKey(from)).inDays;
    return span > 70 ? Granularity.month : Granularity.day;
  }

  static AnalyticsRange thisMonth([DateTime? now]) {
    final bounds = monthBounds(now ?? DateTime.now());
    return AnalyticsRange(
      label: 'This month',
      from: bounds.start,
      to: bounds.end,
    );
  }

  static AnalyticsRange lastMonth([DateTime? now]) {
    final date = now ?? DateTime.now();
    final bounds = monthBounds(DateTime(date.year, date.month - 1, 1));
    return AnalyticsRange(
      label: 'Last month',
      from: bounds.start,
      to: bounds.end,
    );
  }

  static AnalyticsRange lastThreeMonths([DateTime? now]) {
    final date = now ?? DateTime.now();
    return AnalyticsRange(
      label: '3 months',
      from: dayKey(DateTime(date.year, date.month - 2, 1)),
      to: monthBounds(date).end,
    );
  }

  static AnalyticsRange thisYear([DateTime? now]) {
    final date = now ?? DateTime.now();
    return AnalyticsRange(
      label: 'This year',
      from: dayKey(DateTime(date.year, 1, 1)),
      to: dayKey(DateTime(date.year, 12, 31)),
    );
  }

  static List<AnalyticsRange> presets([DateTime? now]) => [
        thisMonth(now),
        lastMonth(now),
        lastThreeMonths(now),
        thisYear(now),
      ];
}

class AnalyticsRangeNotifier extends Notifier<AnalyticsRange> {
  @override
  AnalyticsRange build() => AnalyticsRange.thisMonth();

  void set(AnalyticsRange range) => state = range;
}

final analyticsRangeProvider =
    NotifierProvider<AnalyticsRangeNotifier, AnalyticsRange>(
  AnalyticsRangeNotifier.new,
);

/// The currency every figure on the screen is expressed in.
final analyticsCurrencyProvider = Provider<String>(
  (ref) => ref.watch(displayCurrencyProvider).value ?? 'USD',
);

final analyticsTotalsProvider = StreamProvider<AnalyticsTotals>((ref) {
  final range = ref.watch(analyticsRangeProvider);
  return ref.watch(analyticsDaoProvider).watchTotals(
        from: range.from,
        to: range.to,
        currency: ref.watch(analyticsCurrencyProvider),
      );
});

final categoryBreakdownProvider =
    StreamProvider<List<CategorySlice>>((ref) {
  final range = ref.watch(analyticsRangeProvider);
  return ref.watch(analyticsDaoProvider).watchCategoryBreakdown(
        from: range.from,
        to: range.to,
        currency: ref.watch(analyticsCurrencyProvider),
      );
});

final periodTotalsProvider = StreamProvider<List<PeriodTotal>>((ref) {
  final range = ref.watch(analyticsRangeProvider);
  return ref.watch(analyticsDaoProvider).watchPeriodTotals(
        from: range.from,
        to: range.to,
        currency: ref.watch(analyticsCurrencyProvider),
        granularity: range.granularity,
      );
});

final weekdayTotalsProvider = StreamProvider<List<WeekdayTotal>>((ref) {
  final range = ref.watch(analyticsRangeProvider);
  return ref.watch(analyticsDaoProvider).watchWeekdayTotals(
        from: range.from,
        to: range.to,
        currency: ref.watch(analyticsCurrencyProvider),
      );
});

/// Running net across [periods] — the "am I actually getting ahead" series.
List<Money> cumulativeNet(List<PeriodTotal> periods, String currency) {
  var running = Money.zero(currency);
  return [
    for (final period in periods) running += period.net,
  ];
}

/// Slices to draw, with everything past [keep] folded into one "Other".
///
/// A ninth colour is never invented: the palette has a fixed set of validated
/// slots, and past that the tail becomes a single grey slice.
({List<CategorySlice> slices, CategorySlice? other}) foldSlices(
  List<CategorySlice> all,
  String currency, {
  int keep = 8,
}) {
  if (all.length <= keep) return (slices: all, other: null);

  final tail = all.skip(keep);
  final total = Money.sum(
    tail.map((slice) => slice.total),
    fallbackCurrency: currency,
  );
  return (
    slices: all.take(keep).toList(),
    other: CategorySlice(
      name: 'Other (${tail.length})',
      icon: 'more-horizontal',
      color: 0xFF6B7280,
      total: total,
    ),
  );
}
