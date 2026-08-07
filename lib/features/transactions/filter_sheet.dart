import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../data/providers.dart';
import '../../data/tables/categories.dart';
import '../../data/tables/transactions.dart';
import 'transaction_providers.dart';

Future<void> showFilterSheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    useRootNavigator: true,
    builder: (_) => const _FilterSheet(),
  );
}

class _FilterSheet extends ConsumerWidget {
  const _FilterSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(transactionFilterProvider);
    final notifier = ref.read(transactionFilterProvider.notifier);
    final wallets = ref.watch(walletsProvider).value ?? const [];
    final expenses =
        ref.watch(categoriesProvider(CategoryType.expense)).value ?? const [];
    final incomes =
        ref.watch(categoriesProvider(CategoryType.income)).value ?? const [];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Filter',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              TextButton(
                onPressed: () {
                  notifier.clearFilters();
                  Navigator.of(context).pop();
                },
                child: const Text('Clear'),
              ),
            ],
          ),
        ),
        Flexible(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            children: [
              _Label('Type'),
              Wrap(
                spacing: 8,
                children: [
                  for (final type in TransactionType.values)
                    FilterChip(
                      label: Text(_typeLabel(type)),
                      selected: filter.type == type,
                      onSelected: (selected) =>
                          notifier.setType(selected ? type : null),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _Label('Wallet'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in wallets)
                    FilterChip(
                      avatar: Icon(iconFor(option.wallet.icon), size: 18),
                      label: Text(option.wallet.name),
                      selected: filter.walletId == option.wallet.id,
                      onSelected: (selected) => notifier
                          .setWallet(selected ? option.wallet.id : null),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _Label('Category'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final category in [...expenses, ...incomes])
                    FilterChip(
                      avatar: Icon(
                        iconFor(category.icon),
                        size: 18,
                        color: Color(category.color),
                      ),
                      label: Text(category.name),
                      selected: filter.categoryId == category.id,
                      onSelected: (selected) =>
                          notifier.setCategory(selected ? category.id : null),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              _Label('When'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final range in _quickRanges())
                    FilterChip(
                      label: Text(range.label),
                      selected:
                          filter.from == range.from && filter.to == range.to,
                      onSelected: (selected) => notifier.setRange(
                        selected ? range.from : null,
                        selected ? range.to : null,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.labelLarge),
    );
  }
}

String _typeLabel(TransactionType type) => switch (type) {
      TransactionType.expense => 'Expense',
      TransactionType.income => 'Income',
      TransactionType.transfer => 'Transfer',
    };

class _QuickRange {
  const _QuickRange(this.label, this.from, this.to);
  final String label;
  final String from;
  final String to;
}

List<_QuickRange> _quickRanges() {
  final now = DateTime.now();
  final thisMonth = monthBounds(now);
  final lastMonthDate = DateTime(now.year, now.month - 1, 1);
  final lastMonth = monthBounds(lastMonthDate);

  return [
    _QuickRange('This month', thisMonth.start, thisMonth.end),
    _QuickRange('Last month', lastMonth.start, lastMonth.end),
    _QuickRange(
      'Last 3 months',
      dayKey(DateTime(now.year, now.month - 2, 1)),
      thisMonth.end,
    ),
    _QuickRange(
      'This year',
      dayKey(DateTime(now.year, 1, 1)),
      dayKey(DateTime(now.year, 12, 31)),
    ),
  ];
}
