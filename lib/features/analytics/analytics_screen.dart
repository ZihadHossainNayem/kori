import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../../core/theme.dart';
import '../../core/widgets/animated_money.dart';
import '../../core/widgets/loading_skeleton.dart';
import '../../data/daos/analytics_dao.dart';
import 'analytics_providers.dart';
import 'charts/bar_charts.dart';
import 'charts/category_donut.dart';
import 'charts/trend_line.dart';

class AnalyticsScreen extends ConsumerWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final range = ref.watch(analyticsRangeProvider);
    final currency = ref.watch(analyticsCurrencyProvider);
    final totals = ref.watch(analyticsTotalsProvider);
    final categories = ref.watch(categoryBreakdownProvider).value ?? const [];
    final periods = ref.watch(periodTotalsProvider).value ?? const [];
    final weekdays = ref.watch(weekdayTotalsProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('Insights')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          _RangePicker(selected: range),
          switch (totals) {
            AsyncError(:final error) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text('$error'),
            ),
            AsyncData(:final value) => Column(
              children: [
                _Headline(totals: value),
                if (value.uncounted > 0) _Uncounted(count: value.uncounted),
                if (value.income.isZero && value.expense.isZero)
                  const _NothingYet()
                else ...[
                  _Section(
                    title: 'Where it went',
                    child: _Donut(
                      slices: categories,
                      currency: currency,
                      total: value.expense,
                    ),
                  ),
                  _Section(
                    title: 'Spending over time',
                    child: TrendLine(
                      values: [for (final p in periods) p.expense],
                      labels: [for (final p in periods) _label(p.bucket)],
                      colour: context.money.expense,
                    ),
                  ),
                  _Section(
                    title: 'In and out',
                    child: IncomeExpenseBars(
                      periods: periods,
                      labels: [for (final p in periods) _label(p.bucket)],
                    ),
                  ),
                  _Section(
                    title: 'Running total',
                    subtitle:
                        'Income minus spending, added up as the period goes on',
                    child: TrendLine(
                      values: cumulativeNet(periods, currency),
                      labels: [for (final p in periods) _label(p.bucket)],
                      colour: netColour(context, value.net),
                      showZeroLine: true,
                    ),
                  ),
                  _Section(
                    title: 'By day of week',
                    child: WeekdayBars(weekdays: weekdays, currency: currency),
                  ),
                ],
              ],
            ),
            _ => const SizedBox(
              height: 420,
              child: LoadingSkeleton(rows: 3, rowHeight: 120),
            ),
          },
        ],
      ),
    );
  }
}

/// `2026-08` or `2026-08-14` to something short enough for an axis.
String _label(String bucket) {
  if (bucket.length == 7) {
    return DateFormat('MMM').format(parseDayKey('$bucket-01'));
  }
  return DateFormat('d MMM').format(parseDayKey(bucket));
}

class _RangePicker extends ConsumerWidget {
  const _RangePicker({required this.selected});

  final AnalyticsRange selected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          for (final preset in AnalyticsRange.presets()) ...[
            ChoiceChip(
              label: Text(preset.label),
              selected: preset.label == selected.label,
              onSelected: (_) =>
                  ref.read(analyticsRangeProvider.notifier).set(preset),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

/// The three numbers that matter, as text. A chart of three values would be
/// decoration.
class _Headline extends StatelessWidget {
  const _Headline({required this.totals});

  final AnalyticsTotals totals;

  @override
  Widget build(BuildContext context) {
    final money = context.money;
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                totals.net.isNegative
                    ? 'Spent more than you earned'
                    : 'Left over',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 4),
              AnimatedMoneyText(
                amount: totals.net.abs(),
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: totals.net.isNegative ? money.expense : money.income,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  _Stat(
                    label: 'In',
                    value: totals.income,
                    colour: money.income,
                  ),
                  const SizedBox(width: 24),
                  _Stat(
                    label: 'Out',
                    value: totals.expense,
                    colour: money.expense,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.colour});

  final String label;
  final Money value;
  final Color colour;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          value.format(),
          style: Theme.of(context).textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w600)
              .tabular,
        ),
      ],
    );
  }
}

class _Donut extends StatelessWidget {
  const _Donut({
    required this.slices,
    required this.currency,
    required this.total,
  });

  final List<CategorySlice> slices;
  final String currency;
  final Money total;

  @override
  Widget build(BuildContext context) {
    final folded = foldSlices(slices, currency);
    return CategoryDonut(
      slices: [...folded.slices, ?folded.other],
      total: total,
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              if (subtitle case final text?) ...[
                const SizedBox(height: 2),
                Text(
                  text,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _Uncounted extends StatelessWidget {
  const _Uncounted({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 16, color: scheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$count entr${count == 1 ? 'y' : 'ies'} in another currency '
              'left out of these figures',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.error),
            ),
          ),
        ],
      ),
    );
  }
}

class _NothingYet extends StatelessWidget {
  const _NothingYet();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.insights, size: 48, color: scheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text(
            'Nothing to show yet',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'Record a few transactions and this fills in on its own.',
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
