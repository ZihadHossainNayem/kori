import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../core/chart_palette.dart';
import '../../../core/icons.dart';
import '../../../core/money.dart';
import '../../../core/theme.dart';
import '../../../data/daos/analytics_dao.dart';

/// Where the money went, as share of total.
///
/// The legend is not optional: several palette steps fall under 3:1 against the
/// light surface, so identity has to be carried by a name as well as a colour.
/// It doubles as the table view — every slice's exact amount is readable.
class CategoryDonut extends StatefulWidget {
  const CategoryDonut({required this.slices, required this.total, super.key});

  final List<CategorySlice> slices;
  final Money total;

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Semantics(
          label: _spokenSummary(),
          excludeSemantics: true,
          child: SizedBox(
            height: 200,
            child: Stack(
              alignment: Alignment.center,
              children: [
                PieChart(
                  PieChartData(
                    sections: [
                      for (final (index, slice) in widget.slices.indexed)
                        _section(context, index, slice),
                    ],
                    centerSpaceRadius: 58,
                    // A 2px surface gap between fills keeps adjacent slices
                    // legible even when their hues are close.
                    sectionsSpace: 2,
                    startDegreeOffset: -90,
                    pieTouchData: PieTouchData(
                      touchCallback: (event, response) => setState(() {
                        _touched = event.isInterestedForInteractions
                            ? response?.touchedSection?.touchedSectionIndex
                            : null;
                      }),
                    ),
                  ),
                ),
                _Center(
                  total: widget.total,
                  highlighted:
                      _touched == null ||
                          _touched! < 0 ||
                          _touched! >= widget.slices.length
                      ? null
                      : widget.slices[_touched!],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        for (final (index, slice) in widget.slices.indexed)
          _LegendRow(
            slice: slice,
            total: widget.total,
            selected: _touched == index,
            onTap: () =>
                setState(() => _touched = _touched == index ? null : index),
          ),
        if (widget.slices.isEmpty)
          Text(
            'No spending in this period',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }

  /// The chart as a sentence. The legend below carries the detail, so this only
  /// needs to say what the shape shows.
  String _spokenSummary() {
    if (widget.slices.isEmpty) return 'No spending in this period';
    final biggest = widget.slices.first;
    final share = widget.total.minor == 0
        ? 0
        : (biggest.total.minor * 100 / widget.total.minor).round();
    return 'Spending by category, ${widget.total.format()} total. '
        'Largest is ${biggest.name} at $share percent.';
  }

  PieChartSectionData _section(
    BuildContext context,
    int index,
    CategorySlice slice,
  ) {
    final selected = _touched == index;
    return PieChartSectionData(
      value: slice.total.minor.toDouble(),
      color: context.chartColorFor(slice.color),
      radius: selected ? 30 : 24,
      showTitle: false,
    );
  }
}

class _Center extends StatelessWidget {
  const _Center({required this.total, this.highlighted});

  final Money total;
  final CategorySlice? highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final slice = highlighted;

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text(
          slice?.name ?? 'Spent',
          style: Theme.of(context).textTheme.labelMedium
              // Text keeps ink colours; the mark beside it carries identity.
              ?.copyWith(color: scheme.onSurfaceVariant),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text(
          (slice?.total ?? total).format(compact: true),
          style: Theme.of(
            context,
          ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({
    required this.slice,
    required this.total,
    required this.selected,
    required this.onTap,
  });

  final CategorySlice slice;
  final Money total;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final share = total.minor == 0
        ? 0
        : (slice.total.minor * 100 / total.minor);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        decoration: BoxDecoration(
          color: selected ? scheme.surfaceContainerHighest : null,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Row(
          children: [
            Icon(
              iconFor(slice.icon),
              size: 16,
              color: context.chartColorFor(slice.color),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                slice.name,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              '${share.toStringAsFixed(0)}%',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Text(
              slice.total.format(),
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)
                  .tabular,
            ),
          ],
        ),
      ),
    );
  }
}
