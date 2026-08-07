import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../data/providers.dart';
import 'budget_bar.dart';
import 'budget_form_sheet.dart';
import 'budget_providers.dart';

class BudgetsScreen extends ConsumerWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final month = ref.watch(selectedMonthProvider);
    final budgets = ref.watch(budgetsForMonthProvider(month));

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => showBudgetForm(context, monthKey: month),
        tooltip: 'Add budget',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _MonthSwitcher(month: month),
          Expanded(
            child: switch (budgets) {
              AsyncError(:final error) => Center(child: Text('$error')),
              AsyncData(:final value) when value.isEmpty => _EmptyBudgets(
                month: month,
              ),
              AsyncData(:final value) => ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
                children: [
                  for (final budget in value)
                    Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        child: BudgetBar(
                          budget: budget,
                          onTap: () => showBudgetForm(
                            context,
                            monthKey: month,
                            existing: budget,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              _ => const Center(child: CircularProgressIndicator()),
            },
          ),
        ],
      ),
    );
  }
}

class _MonthSwitcher extends ConsumerWidget {
  const _MonthSwitcher({required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(selectedMonthProvider.notifier);
    final date = parseDayKey('$month-01');
    final isCurrentMonth = month == monthKey(DateTime.now());

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          IconButton(
            onPressed: () => notifier.shift(-1),
            icon: const Icon(Icons.chevron_left),
            tooltip: 'Previous month',
          ),
          Expanded(
            child: Center(
              child: Text(
                DateFormat('MMMM y').format(date),
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ),
          IconButton(
            // No forward limit: budgeting next month before it starts is the
            // whole point of planning.
            onPressed: () => notifier.shift(1),
            icon: const Icon(Icons.chevron_right),
            tooltip: 'Next month',
          ),
          if (!isCurrentMonth)
            IconButton(
              onPressed: () => notifier.set(monthKey(DateTime.now())),
              icon: const Icon(Icons.today),
              tooltip: 'This month',
            ),
        ],
      ),
    );
  }
}

class _EmptyBudgets extends ConsumerWidget {
  const _EmptyBudgets({required this.month});

  final String month;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final previous = _previousMonth(month);
    final previousBudgets = ref.watch(budgetsForMonthProvider(previous)).value;
    final canCopy = previousBudgets != null && previousBudgets.isNotEmpty;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.savings_outlined,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No budgets this month',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Cap a category, or everything at once. Kori warns you at 80% and '
              'again when it is gone.',
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => showBudgetForm(context, monthKey: month),
              icon: const Icon(Icons.add),
              label: const Text('Set a budget'),
            ),
            if (canCopy) ...[
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: () async {
                  final copied = await ref
                      .read(budgetsDaoProvider)
                      .copyMonth(from: previous, to: month);
                  if (!context.mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'Copied $copied budget${copied == 1 ? '' : 's'}',
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.copy_all_outlined),
                label: const Text('Copy last month'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

String _previousMonth(String month) {
  final year = int.parse(month.substring(0, 4));
  final index = int.parse(month.substring(5, 7));
  return monthKey(DateTime(year, index - 1, 1));
}
