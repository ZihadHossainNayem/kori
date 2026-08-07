import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/money.dart';
import '../../data/daos/transactions_dao.dart';
import '../../data/providers.dart';
import '../../data/tables/transactions.dart';

/// Held outside the widget so a rebuild or tab switch does not lose the filter.
class TransactionFilterNotifier extends Notifier<TransactionFilter> {
  @override
  TransactionFilter build() => const TransactionFilter();

  void setSearch(String value) => state = state.copyWith(search: value);

  void setWallet(int? id) => state =
      id == null ? state.copyWith(clearWallet: true) : state.copyWith(walletId: id);

  void setCategory(int? id) => state = id == null
      ? state.copyWith(clearCategory: true)
      : state.copyWith(categoryId: id);

  void setType(TransactionType? type) => state = type == null
      ? state.copyWith(clearType: true)
      : state.copyWith(type: type);

  void setRange(String? from, String? to) => state = (from == null && to == null)
      ? state.copyWith(clearDates: true)
      : state.copyWith(from: from, to: to);

  /// Keeps the search text, which stays visible in its field.
  void clearFilters() => state = TransactionFilter(search: state.search);

  void clearAll() => state = const TransactionFilter();
}

final transactionFilterProvider =
    NotifierProvider<TransactionFilterNotifier, TransactionFilter>(
  TransactionFilterNotifier.new,
);

/// How many rows the history screen has asked for so far.
class TransactionLimitNotifier extends Notifier<int> {
  static const pageSize = 50;

  @override
  int build() => pageSize;

  void loadMore() => state += pageSize;

  void reset() => state = pageSize;
}

final transactionLimitProvider =
    NotifierProvider<TransactionLimitNotifier, int>(
  TransactionLimitNotifier.new,
);

final transactionEntriesProvider = StreamProvider<List<TransactionEntry>>((ref) {
  final filter = ref.watch(transactionFilterProvider);
  final limit = ref.watch(transactionLimitProvider);
  return ref
      .watch(transactionsDaoProvider)
      .watchEntries(filter: filter, limit: limit);
});

/// One calendar day of transactions, with the day's net movement.
class TransactionDay {
  const TransactionDay({
    required this.date,
    required this.entries,
    required this.net,
  });

  final String date;
  final List<TransactionEntry> entries;

  /// Income minus expenses. Transfers excluded: moving your own money between
  /// wallets changes nothing.
  final Money? net;
}

/// Groups an already-sorted list into days — one pass, no extra query.
List<TransactionDay> groupByDay(List<TransactionEntry> entries) {
  final days = <TransactionDay>[];
  var index = 0;

  while (index < entries.length) {
    final date = entries[index].transaction.date;
    final group = <TransactionEntry>[];
    while (index < entries.length && entries[index].transaction.date == date) {
      group.add(entries[index]);
      index += 1;
    }

    // Only total when the day shares one currency, or it would mix units.
    final spendable = group
        .where((e) => e.transaction.type != TransactionType.transfer)
        .toList();
    final currencies = spendable.map((e) => e.amount.currency).toSet();
    final net = currencies.length == 1
        ? Money.sum(
            spendable.map((e) => e.signedAmount),
            fallbackCurrency: currencies.first,
          )
        : null;

    days.add(TransactionDay(date: date, entries: group, net: net));
  }

  return days;
}
