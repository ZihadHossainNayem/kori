import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/money.dart';
import '../../../core/theme.dart';

/// A single series over time — spending per period, or running net.
///
/// One series, so no legend box: the card title names it. Values are labelled at
/// the axis and on touch, never on every point.
class TrendLine extends StatelessWidget {
  const TrendLine({
    required this.values,
    required this.labels,
    required this.colour,
    this.showZeroLine = false,
    super.key,
  });

  final List<Money> values;
  final List<String> labels;
  final Color colour;

  /// Draws a baseline at zero, for a series that can go negative.
  final bool showZeroLine;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    if (values.length < 2) {
      return _NotEnoughData(points: values.length);
    }

    final minor = values.map((v) => v.minor.toDouble()).toList();
    final lowest = minor.reduce((a, b) => a < b ? a : b);
    final highest = minor.reduce((a, b) => a > b ? a : b);
    // Never a zero-height band: a flat series should read as flat, not blank.
    final padding = ((highest - lowest).abs() * 0.15).clamp(1.0, double.infinity);

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minY: showZeroLine ? (lowest < 0 ? lowest - padding : 0) : lowest - padding,
          maxY: highest + padding,
          lineBarsData: [
            LineChartBarData(
              spots: [
                for (final (index, value) in minor.indexed)
                  FlSpot(index.toDouble(), value),
              ],
              color: colour,
              barWidth: 2,
              isCurved: false,
              dotData: FlDotData(
                // Markers only when the series is short enough to read them.
                show: values.length <= 14,
                getDotPainter: (spot, percent, bar, index) =>
                    FlDotCirclePainter(
                  radius: 4,
                  color: colour,
                  strokeWidth: 2,
                  strokeColor: scheme.surface,
                ),
              ),
              belowBarData: BarAreaData(
                show: true,
                color: colour.withValues(alpha: 0.12),
                applyCutOffY: showZeroLine,
                cutOffY: 0,
              ),
            ),
          ],
          extraLinesData: showZeroLine
              ? ExtraLinesData(
                  horizontalLines: [
                    HorizontalLine(
                      y: 0,
                      color: scheme.outlineVariant,
                      strokeWidth: 1,
                    ),
                  ],
                )
              : const ExtraLinesData(),
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            horizontalInterval: (highest - lowest).abs() < 1
                ? null
                : (highest - lowest).abs() / 3,
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
                  if (value != meta.min && value != meta.max) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(
                      Money(value.round(), values.first.currency)
                          .format(compact: true),
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                      textAlign: TextAlign.right,
                    ),
                  );
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final index = value.round();
                  // First and last only: every label collides on a narrow phone.
                  if (index != 0 && index != labels.length - 1) {
                    return const SizedBox.shrink();
                  }
                  if (index < 0 || index >= labels.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      labels[index],
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (spot) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final spot in spots)
                  LineTooltipItem(
                    '${labels[spot.x.round().clamp(0, labels.length - 1)]}\n'
                    '${Money(spot.y.round(), values.first.currency).format()}',
                    TextStyle(
                      color: scheme.onInverseSurface,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
              ],
            ),
            getTouchedSpotIndicator: (bar, indexes) => [
              for (final _ in indexes)
                TouchedSpotIndicatorData(
                  FlLine(color: scheme.outline, strokeWidth: 1),
                  FlDotData(
                    getDotPainter: (spot, percent, bar, index) =>
                        FlDotCirclePainter(
                      radius: 5,
                      color: colour,
                      strokeWidth: 2,
                      strokeColor: scheme.surface,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotEnoughData extends StatelessWidget {
  const _NotEnoughData({required this.points});

  final int points;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 180,
      child: Center(
        child: Text(
          points == 0
              ? 'Nothing recorded in this period'
              : 'One period only — a trend needs at least two',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
      ),
    );
  }
}

/// Colour for a net series: green when ahead, expense red when behind.
Color netColour(BuildContext context, Money net) =>
    net.isNegative ? context.money.expense : context.money.income;
