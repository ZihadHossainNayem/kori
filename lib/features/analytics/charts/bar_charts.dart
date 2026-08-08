import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/daos/analytics_dao.dart';

/// Income beside expense per period.
///
/// Two series on one shared axis — never two scales. A legend is always present,
/// so the pairing is not carried by colour alone.
class IncomeExpenseBars extends StatelessWidget {
  const IncomeExpenseBars({
    required this.periods,
    required this.labels,
    super.key,
  });

  final List<PeriodTotal> periods;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = context.money;

    if (periods.isEmpty) {
      return const _Empty(text: 'Nothing recorded in this period');
    }

    final highest = periods
        .map(
          (p) =>
              [p.income.minor, p.expense.minor].reduce((a, b) => a > b ? a : b),
        )
        .reduce((a, b) => a > b ? a : b)
        .toDouble();

    return Column(
      children: [
        Semantics(
          label:
              'Income and spending over ${periods.length} periods. '
              'Latest: in ${periods.last.income.format()}, '
              'out ${periods.last.expense.format()}.',
          excludeSemantics: true,
          child: SizedBox(
            height: 180,
            child: BarChart(
              BarChartData(
                maxY: highest == 0 ? 1 : highest * 1.15,
                // 2px of surface between the two rods of a pair.
                groupsSpace: 14,
                barGroups: [
                  for (final (index, period) in periods.indexed)
                    BarChartGroupData(
                      x: index,
                      barsSpace: 2,
                      barRods: [
                        _rod(period.income.minor.toDouble(), money.income),
                        _rod(period.expense.minor.toDouble(), money.expense),
                      ],
                    ),
                ],
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: highest == 0 ? null : highest / 2,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: scheme.outlineVariant.withValues(alpha: 0.5),
                    strokeWidth: 1,
                  ),
                ),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 52,
                      getTitlesWidget: (value, meta) {
                        if (value != meta.max) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: Text(
                            Money(
                              value.round(),
                              periods.first.income.currency,
                            ).format(compact: true),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) {
                        final index = value.round();
                        if (index < 0 || index >= labels.length) {
                          return const SizedBox.shrink();
                        }
                        // Thin the labels so they never collide.
                        final step = (labels.length / 4).ceil();
                        if (labels.length > 5 && index % step != 0) {
                          return const SizedBox.shrink();
                        }
                        return Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            labels[index],
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: scheme.onSurfaceVariant),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => scheme.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) =>
                        BarTooltipItem(
                          '${labels[groupIndex]}\n'
                          '${rodIndex == 0 ? 'In' : 'Out'} '
                          '${Money(rod.toY.round(), periods.first.income.currency).format()}',
                          TextStyle(
                            color: scheme.onInverseSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ).tabular,
                        ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Legend(
          entries: [
            (label: 'Money in', colour: money.income),
            (label: 'Money out', colour: money.expense),
          ],
        ),
      ],
    );
  }

  BarChartRodData _rod(double value, Color colour) => BarChartRodData(
    toY: value,
    color: colour,
    width: 9,
    // Rounded at the data end only, anchored to the baseline.
    borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
  );
}

/// Expenses by day of week — the habit a date series hides.
class WeekdayBars extends StatelessWidget {
  const WeekdayBars({
    required this.weekdays,
    required this.currency,
    super.key,
  });

  final List<WeekdayTotal> weekdays;
  final String currency;

  static const _names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (weekdays.isEmpty) {
      return const _Empty(text: 'No spending in this period');
    }

    // Fill the missing days so a quiet Tuesday reads as zero, not as absent.
    final byWeekday = {for (final day in weekdays) day.weekday: day};
    final filled = [
      for (var weekday = 1; weekday <= 7; weekday++)
        byWeekday[weekday] ??
            WeekdayTotal(
              weekday: weekday,
              expense: Money.zero(currency),
              count: 0,
            ),
    ];
    final highest = filled
        .map((day) => day.expense.minor)
        .reduce((a, b) => a > b ? a : b)
        .toDouble();
    final busiest = filled.reduce(
      (a, b) => a.expense.minor >= b.expense.minor ? a : b,
    );

    return Column(
      children: [
        Semantics(
          label:
              'Spending by day of week. Most on '
              '${_fullName(busiest.weekday)}, ${busiest.expense.format()}.',
          excludeSemantics: true,
          child: SizedBox(
            height: 160,
            child: BarChart(
              BarChartData(
                maxY: highest == 0 ? 1 : highest * 1.15,
                barGroups: [
                  for (final (index, day) in filled.indexed)
                    BarChartGroupData(
                      x: index,
                      barRods: [
                        BarChartRodData(
                          toY: day.expense.minor.toDouble(),
                          // One series, so one colour; the busiest day is picked
                          // out by weight rather than a second hue.
                          color: day.weekday == busiest.weekday && highest > 0
                              ? context.money.expense
                              : context.money.expense.withValues(alpha: 0.35),
                          width: 18,
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                        ),
                      ],
                    ),
                ],
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _names[value.round().clamp(0, 6)],
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: scheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
                ),
                barTouchData: BarTouchData(
                  touchTooltipData: BarTouchTooltipData(
                    getTooltipColor: (group) => scheme.inverseSurface,
                    getTooltipItem: (group, groupIndex, rod, rodIndex) {
                      final day = filled[groupIndex];
                      return BarTooltipItem(
                        '${_names[groupIndex]}\n${day.expense.format()}\n'
                        '${day.count} entr${day.count == 1 ? 'y' : 'ies'}',
                        TextStyle(
                          color: scheme.onInverseSurface,
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ).tabular,
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
        if (highest > 0) ...[
          const SizedBox(height: 8),
          Text(
            'Most goes out on ${_fullName(busiest.weekday)} — '
            '${busiest.expense.format()}',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  static String _fullName(int weekday) => const [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ][weekday - 1];
}

class _Legend extends StatelessWidget {
  const _Legend({required this.entries});

  final List<({String label, Color colour})> entries;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final entry in entries) ...[
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: entry.colour,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            entry.label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 16),
        ],
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 160,
      child: Center(
        child: Text(
          text,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
