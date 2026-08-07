import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/dates.dart';
import '../../core/icons.dart';
import '../../core/theme.dart';
import '../../data/daos/transactions_dao.dart';
import '../../data/providers.dart';
import '../../data/tables/transactions.dart';
import 'add_transaction_screen.dart';
import 'filter_sheet.dart';
import 'transaction_providers.dart';

class TransactionsScreen extends ConsumerStatefulWidget {
  const TransactionsScreen({super.key});

  @override
  ConsumerState<TransactionsScreen> createState() => _TransactionsScreenState();
}

class _TransactionsScreenState extends ConsumerState<TransactionsScreen> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _scroll
      ..removeListener(_maybeLoadMore)
      ..dispose();
    _search.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 400) {
      ref.read(transactionLimitProvider.notifier).loadMore();
    }
  }

  Future<void> _edit(TransactionEntry entry) async {
    await Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => AddTransactionScreen(entry: entry),
      ),
    );
  }

  Future<void> _delete(TransactionEntry entry) async {
    final dao = ref.read(transactionsDaoProvider);
    final messenger = ScaffoldMessenger.of(context);
    await dao.deleteTransaction(entry.transaction.id);

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('Deleted ${entry.amount.format()}'),
        action: SnackBarAction(
          label: 'Undo',
          // Restores the original row, id included.
          onPressed: () => dao.restore(entry.transaction),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = ref.watch(transactionEntriesProvider);
    final filter = ref.watch(transactionFilterProvider);
    final filtersActive = filter.walletId != null ||
        filter.categoryId != null ||
        filter.type != null ||
        filter.from != null;

    return Scaffold(
      appBar: AppBar(
        title: _searching
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search notes and categories',
                  border: InputBorder.none,
                  filled: false,
                ),
                onChanged: (value) {
                  ref.read(transactionLimitProvider.notifier).reset();
                  ref.read(transactionFilterProvider.notifier).setSearch(value);
                },
              )
            : const Text('History'),
        actions: [
          IconButton(
            tooltip: _searching ? 'Close search' : 'Search',
            icon: Icon(_searching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() => _searching = !_searching);
              if (!_searching) {
                _search.clear();
                ref.read(transactionFilterProvider.notifier).setSearch('');
              }
            },
          ),
          IconButton(
            tooltip: 'Filter',
            icon: Badge(
              isLabelVisible: filtersActive,
              child: const Icon(Icons.tune),
            ),
            onPressed: () => showFilterSheet(context),
          ),
        ],
      ),
      body: switch (entries) {
        AsyncError(:final error) => Center(child: Text('$error')),
        AsyncData(:final value) when value.isEmpty => _EmptyHistory(
            filtered: filtersActive || !filter.isEmpty,
            onClear: () {
              _search.clear();
              ref.read(transactionFilterProvider.notifier).clearAll();
            },
          ),
        AsyncData(:final value) => _DayList(
            days: groupByDay(value),
            controller: _scroll,
            onEdit: _edit,
            onDelete: _delete,
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({
    required this.days,
    required this.controller,
    required this.onEdit,
    required this.onDelete,
  });

  final List<TransactionDay> days;
  final ScrollController controller;
  final ValueChanged<TransactionEntry> onEdit;
  final ValueChanged<TransactionEntry> onDelete;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: controller,
      padding: const EdgeInsets.only(bottom: 96),
      itemCount: days.length,
      itemBuilder: (context, index) {
        final day = days[index];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DayHeader(day: day),
            for (final entry in day.entries)
              _TransactionRow(
                entry: entry,
                onTap: () => onEdit(entry),
                onDismissed: () => onDelete(entry),
              ),
          ],
        );
      },
    );
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.day});

  final TransactionDay day;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final net = day.net;

    return Container(
      color: scheme.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _dayLabel(day.date),
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ),
          if (net != null && !net.isZero)
            Text(
              net.isNegative ? net.format() : '+${net.format()}',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: net.isNegative
                        ? context.money.expense
                        : context.money.income,
                  ),
            ),
        ],
      ),
    );
  }
}

String _dayLabel(String key) {
  final today = todayKey();
  if (key == today) return 'Today';
  final yesterday = dayKey(DateTime.now().subtract(const Duration(days: 1)));
  if (key == yesterday) return 'Yesterday';

  final date = parseDayKey(key);
  final sameYear = date.year == DateTime.now().year;
  return DateFormat(sameYear ? 'EEEE, d MMMM' : 'd MMMM y').format(date);
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({
    required this.entry,
    required this.onTap,
    required this.onDismissed,
  });

  final TransactionEntry entry;
  final VoidCallback onTap;
  final VoidCallback onDismissed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final transaction = entry.transaction;
    final isTransfer = transaction.type == TransactionType.transfer;

    final colour = switch (transaction.type) {
      TransactionType.income => context.money.income,
      TransactionType.expense => context.money.expense,
      TransactionType.transfer => context.money.transfer,
    };

    final iconColour = isTransfer
        ? colour
        : Color(entry.category?.color ?? scheme.outline.toARGB32());
    final icon = isTransfer
        ? Icons.swap_horiz
        : iconFor(entry.category?.icon ?? 'tag');

    final title = isTransfer
        ? '${entry.wallet.name} → ${entry.destination?.name ?? '—'}'
        : entry.category?.name ?? 'Uncategorised';

    final subtitleParts = [
      if (!isTransfer) entry.wallet.name,
      if (transaction.note case final note? when note.isNotEmpty) note,
    ];

    return Dismissible(
      key: ValueKey(transaction.id),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => onDismissed(),
      background: Container(
        color: scheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 24),
        child: Icon(Icons.delete_outline, color: scheme.onErrorContainer),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: iconColour.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 20, color: iconColour),
        ),
        title: Text(title, overflow: TextOverflow.ellipsis),
        subtitle: subtitleParts.isEmpty
            ? null
            : Text(subtitleParts.join(' · '), overflow: TextOverflow.ellipsis),
        trailing: Text(
          isTransfer
              ? entry.amount.format()
              : entry.signedAmount.isNegative
                  ? entry.signedAmount.format()
                  : '+${entry.signedAmount.format()}',
          style: Theme.of(context)
              .textTheme
              .titleSmall
              ?.copyWith(color: colour, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}

class _EmptyHistory extends StatelessWidget {
  const _EmptyHistory({required this.filtered, required this.onClear});

  final bool filtered;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              filtered ? Icons.filter_alt_off_outlined : Icons.receipt_long,
              size: 48,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              filtered ? 'Nothing matches' : 'No transactions yet',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              filtered
                  ? 'Try widening the filter or clearing it.'
                  : 'Tap + to record the first one.',
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .bodyMedium
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
            if (filtered) ...[
              const SizedBox(height: 20),
              OutlinedButton(onPressed: onClear, child: const Text('Clear')),
            ],
          ],
        ),
      ),
    );
  }
}
