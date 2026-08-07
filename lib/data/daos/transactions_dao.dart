import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../db.dart';
import '../tables/categories.dart';
import '../tables/transactions.dart';
import '../tables/wallets.dart';

part 'transactions_dao.g.dart';

/// What the history screen is currently showing.
class TransactionFilter {
  const TransactionFilter({
    this.walletId,
    this.categoryId,
    this.type,
    this.from,
    this.to,
    this.search,
  });

  final int? walletId;
  final int? categoryId;
  final TransactionType? type;

  /// Inclusive `YYYY-MM-DD` bounds.
  final String? from;
  final String? to;

  /// Matches note or category name.
  final String? search;

  bool get isEmpty =>
      walletId == null &&
      categoryId == null &&
      type == null &&
      from == null &&
      to == null &&
      (search == null || search!.trim().isEmpty);

  TransactionFilter copyWith({
    int? walletId,
    int? categoryId,
    TransactionType? type,
    String? from,
    String? to,
    String? search,
    bool clearWallet = false,
    bool clearCategory = false,
    bool clearType = false,
    bool clearDates = false,
  }) {
    return TransactionFilter(
      walletId: clearWallet ? null : walletId ?? this.walletId,
      categoryId: clearCategory ? null : categoryId ?? this.categoryId,
      type: clearType ? null : type ?? this.type,
      from: clearDates ? null : from ?? this.from,
      to: clearDates ? null : to ?? this.to,
      search: search ?? this.search,
    );
  }
}

/// A transaction with the rows needed to render it.
class TransactionEntry {
  const TransactionEntry({
    required this.transaction,
    required this.wallet,
    this.category,
    this.destination,
  });

  final Transaction transaction;
  final Wallet wallet;
  final Category? category;

  /// Destination wallet, for transfers.
  final Wallet? destination;

  Money get amount => Money(transaction.amountMinor, transaction.currency);

  /// Signed for display: negative for expenses, positive for income. Transfers
  /// are neither — they move money without changing the total.
  Money get signedAmount => switch (transaction.type) {
    TransactionType.income => amount,
    TransactionType.expense => -amount,
    TransactionType.transfer => amount,
  };
}

@DriftAccessor(tables: [Transactions, Wallets, Categories])
class TransactionsDao extends DatabaseAccessor<KoriDatabase>
    with _$TransactionsDaoMixin {
  TransactionsDao(super.attachedDatabase);

  /// Newest first. [limit] pages the history screen.
  Stream<List<TransactionEntry>> watchEntries({
    TransactionFilter filter = const TransactionFilter(),
    int? limit,
  }) {
    final destination = alias(wallets, 'destination_wallet');
    final query = select(transactions).join([
      innerJoin(wallets, wallets.id.equalsExp(transactions.walletId)),
      leftOuterJoin(
        categories,
        categories.id.equalsExp(transactions.categoryId),
      ),
      leftOuterJoin(
        destination,
        destination.id.equalsExp(transactions.transferToWalletId),
      ),
    ]);

    if (filter.walletId case final id?) {
      // A transfer belongs to both of its wallets.
      query.where(
        transactions.walletId.equals(id) |
            transactions.transferToWalletId.equals(id),
      );
    }
    if (filter.categoryId case final id?) {
      query.where(transactions.categoryId.equals(id));
    }
    if (filter.type case final type?) {
      query.where(transactions.type.equalsValue(type));
    }
    if (filter.from case final from?) {
      query.where(transactions.date.isBiggerOrEqualValue(from));
    }
    if (filter.to case final to?) {
      query.where(transactions.date.isSmallerOrEqualValue(to));
    }
    if (filter.search?.trim() case final search? when search.isNotEmpty) {
      final pattern = '%${_escapeLike(search)}%';
      query.where(
        transactions.note.like(pattern, escapeChar: r'\') |
            categories.name.like(pattern, escapeChar: r'\'),
      );
    }

    query.orderBy([
      OrderingTerm.desc(transactions.date),
      OrderingTerm.desc(transactions.createdAt),
      OrderingTerm.desc(transactions.id),
    ]);
    if (limit != null) query.limit(limit);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => TransactionEntry(
              transaction: row.readTable(transactions),
              wallet: row.readTable(wallets),
              category: row.readTableOrNull(categories),
              destination: row.readTableOrNull(destination),
            ),
          )
          .toList(),
    );
  }

  Future<TransactionEntry?> entryById(int id) async {
    final destination = alias(wallets, 'destination_wallet');
    final row = await (select(transactions).join([
      innerJoin(wallets, wallets.id.equalsExp(transactions.walletId)),
      leftOuterJoin(
        categories,
        categories.id.equalsExp(transactions.categoryId),
      ),
      leftOuterJoin(
        destination,
        destination.id.equalsExp(transactions.transferToWalletId),
      ),
    ])..where(transactions.id.equals(id))).getSingleOrNull();

    if (row == null) return null;
    return TransactionEntry(
      transaction: row.readTable(transactions),
      wallet: row.readTable(wallets),
      category: row.readTableOrNull(categories),
      destination: row.readTableOrNull(destination),
    );
  }

  /// The currency is taken from [amount] so it always matches the stored value.
  /// Sign is not stored — [type] carries direction.
  Future<int> addTransaction({
    required int walletId,
    required TransactionType type,
    required Money amount,
    required String date,
    int? categoryId,
    String? note,
    int? transferToWalletId,
    int? recurringRuleId,
  }) {
    return into(transactions).insert(
      TransactionsCompanion.insert(
        walletId: walletId,
        type: type,
        amountMinor: amount.abs().minor,
        currency: amount.currency,
        date: date,
        categoryId: Value(categoryId),
        note: Value(_trimToNull(note)),
        transferToWalletId: Value(transferToWalletId),
        recurringRuleId: Value(recurringRuleId),
      ),
    );
  }

  Future<bool> updateTransaction(Transaction transaction) => update(
    transactions,
  ).replace(transaction.copyWith(updatedAt: DateTime.now()));

  Future<int> deleteTransaction(int id) =>
      (delete(transactions)..where((t) => t.id.equals(id))).go();

  /// Re-inserts a deleted row for undo, keeping its original id.
  Future<void> restore(Transaction transaction) =>
      into(transactions).insert(transaction, mode: InsertMode.insertOrReplace);

  static String? _trimToNull(String? value) {
    final trimmed = value?.trim();
    return (trimmed == null || trimmed.isEmpty) ? null : trimmed;
  }

  /// `%` and `_` are wildcards in LIKE; a user searching "50%" means the text.
  static String _escapeLike(String value) => value
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}
