import 'package:flutter/material.dart';

import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/daos/budgets_dao.dart';

/// One budget's progress. Colour carries the state, so it reads at a glance
/// without parsing the numbers.
class BudgetBar extends StatelessWidget {
  const BudgetBar({required this.budget, this.onTap, super.key});

  final BudgetProgress budget;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final money = context.money;

    final colour = budget.isOver
        ? money.expense
        : budget.percent >= 80
        ? money.overBudget
        : Color(budget.categoryColor ?? scheme.primary.toARGB32());

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(KoriRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  budget.isOverall
                      ? Icons.all_inclusive
                      : iconFor(budget.categoryIcon ?? 'tag'),
                  size: 18,
                  color: colour,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    budget.label,
                    style: Theme.of(context).textTheme.titleSmall,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Text(
                  '${budget.percent}%',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: colour,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            TweenAnimationBuilder<double>(
              tween: Tween(end: budget.fraction),
              duration: const Duration(milliseconds: 600),
              curve: Curves.easeOutCubic,
              builder: (context, fraction, _) => ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: fraction,
                  minHeight: 8,
                  backgroundColor: scheme.surfaceContainerHighest,
                  valueColor: AlwaysStoppedAnimation(colour),
                ),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${budget.spent.format()} of ${budget.limit.format()}',
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant)
                        .tabular,
                  ),
                ),
                Text(
                  budget.isOver
                      ? 'over by ${budget.remaining.abs().format()}'
                      : '${budget.remaining.format()} left',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(
                        color: budget.isOver
                            ? money.expense
                            : scheme.onSurfaceVariant,
                      )
                      .tabular,
                ),
              ],
            ),
            if (budget.uncountedInOtherCurrencies > 0) ...[
              const SizedBox(height: 4),
              Text(
                '${budget.uncountedInOtherCurrencies} expense'
                '${budget.uncountedInOtherCurrencies == 1 ? '' : 's'} in another '
                'currency not counted',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
