import 'dart:convert';
import 'dart:typed_data';

import 'package:csv/csv.dart';

import '../../core/money.dart';
import '../db.dart';
import '../tables/transactions.dart';
import 'xlsx.dart';

/// Column headings. Import matches on these names, not positions, so a
/// reordered spreadsheet still imports.
abstract final class ExportColumns {
  static const date = 'Date';
  static const type = 'Type';
  static const amount = 'Amount';
  static const currency = 'Currency';
  static const wallet = 'Wallet';
  static const category = 'Category';
  static const note = 'Note';
  static const transferTo = 'Transfer to';

  static const transactions = [
    date,
    type,
    amount,
    currency,
    wallet,
    category,
    note,
    transferTo,
  ];

  static const wallets = [
    'Name',
    'Type',
    'Currency',
    'Opening balance',
    'Archived',
  ];

  static const categories = ['Name', 'Type'];
}

/// Reads the database out as plain rows. Amounts go out as numbers so a
/// spreadsheet can total them.
class ExportService {
  const ExportService(this._db);

  final KoriDatabase _db;

  Future<List<XlsxSheet>> sheets() async {
    return [
      XlsxSheet(name: 'Transactions', rows: await transactionRows()),
      XlsxSheet(name: 'Wallets', rows: await walletRows()),
      XlsxSheet(name: 'Categories', rows: await categoryRows()),
    ];
  }

  Future<List<List<Object?>>> transactionRows() async {
    final entries = await _db.transactionsDao.watchEntries().first;

    return [
      ExportColumns.transactions,
      for (final entry in entries)
        [
          entry.transaction.date,
          entry.transaction.type.name,
          _number(entry.amount),
          entry.transaction.currency,
          entry.wallet.name,
          entry.category?.name,
          entry.transaction.note,
          entry.destination?.name,
        ],
    ];
  }

  Future<List<List<Object?>>> walletRows() async {
    final wallets = await _db.walletsDao.watchWallets(includeArchived: true).first;

    return [
      ExportColumns.wallets,
      for (final entry in wallets)
        [
          entry.wallet.name,
          entry.wallet.type.name,
          entry.wallet.currency,
          _number(
            Money(entry.wallet.initialBalanceMinor, entry.wallet.currency),
          ),
          entry.wallet.archived ? 'yes' : 'no',
        ],
    ];
  }

  Future<List<List<Object?>>> categoryRows() async {
    final categories = await _db.select(_db.categories).get();

    return [
      ExportColumns.categories,
      for (final category in categories) [category.name, category.type.name],
    ];
  }

  Future<Uint8List> toXlsx() async => encodeXlsx(await sheets());

  /// Transactions only. CSV has one table, and the transactions are the part
  /// anyone actually wants to open elsewhere.
  Future<Uint8List> toCsv() async {
    final rows = await transactionRows();
    // addBom so spreadsheets read non-Latin notes as UTF-8, not mojibake.
    final text = Csv(addBom: true).encode(rows);
    return Uint8List.fromList(utf8.encode(text));
  }

  /// `kori-2026-08-07.csv`
  static String fileName(String extension, {DateTime? now}) {
    final date = now ?? DateTime.now();
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return 'kori-${date.year}-$month-$day.$extension';
  }

  /// Exact for the amounts money actually takes, and a number rather than text
  /// so it sums in a spreadsheet.
  static num _number(Money money) => num.parse(money.toPlainString());
}

/// Rebuilds a [TransactionType] from an exported name.
TransactionType? transactionTypeFromName(String value) {
  final normalised = value.trim().toLowerCase();
  for (final type in TransactionType.values) {
    if (type.name == normalised) return type;
  }
  // Names other apps use for the same thing.
  return switch (normalised) {
    'debit' || 'withdrawal' || 'out' || 'spending' => TransactionType.expense,
    'credit' || 'deposit' || 'in' => TransactionType.income,
    'move' => TransactionType.transfer,
    _ => null,
  };
}
