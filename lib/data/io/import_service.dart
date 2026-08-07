import 'dart:convert';

import 'package:csv/csv.dart';
import 'package:drift/drift.dart';

import '../../core/dates.dart';
import '../../core/money.dart';
import '../db.dart';
import '../tables/categories.dart';
import '../tables/transactions.dart';
import '../tables/wallets.dart';
import 'export_service.dart';
import 'xlsx.dart';

/// One field the importer needs, and the header names it recognises.
enum ImportField {
  date('Date', ['date', 'day', 'transaction date', 'posted']),
  type('Type', ['type', 'kind', 'direction']),
  amount('Amount', ['amount', 'value', 'sum', 'total']),
  currency('Currency', ['currency', 'ccy']),
  wallet('Wallet', ['wallet', 'account', 'source']),
  category('Category', ['category', 'tag']),
  note('Note', ['note', 'description', 'memo', 'details', 'payee']),
  transferTo('Transfer to', ['transfer to', 'destination', 'to account']);

  const ImportField(this.label, this.aliases);

  final String label;
  final List<String> aliases;

  bool get required => this == date || this == amount;
}

/// A file's headers, its rows, and the mapping guessed from those headers.
class ImportPreview {
  const ImportPreview({
    required this.headers,
    required this.rows,
    required this.mapping,
  });

  final List<String> headers;
  final List<List<Object?>> rows;

  /// Field to column index. Missing means the user still has to choose.
  final Map<ImportField, int> mapping;

  bool get canImport =>
      ImportField.values.where((f) => f.required).every(mapping.containsKey);
}

/// What a row will do once imported, or why it cannot be.
class ImportRow {
  const ImportRow({
    required this.line,
    this.date,
    this.type,
    this.amount,
    this.wallet,
    this.category,
    this.note,
    this.transferTo,
    this.problem,
  });

  /// Line number in the file, counting the header as line 1.
  final int line;
  final String? date;
  final TransactionType? type;
  final Money? amount;
  final String? wallet;
  final String? category;
  final String? note;
  final String? transferTo;

  /// Null when the row is importable.
  final String? problem;

  bool get isValid => problem == null;
}

class ImportPlan {
  const ImportPlan({required this.rows, required this.newWallets, required this.newCategories});

  final List<ImportRow> rows;

  /// Wallets and categories the file mentions that do not exist yet. Created on
  /// import rather than dropping the rows that reference them.
  final Set<String> newWallets;
  final Set<String> newCategories;

  Iterable<ImportRow> get valid => rows.where((row) => row.isValid);
  Iterable<ImportRow> get invalid => rows.where((row) => !row.isValid);
}

/// Turns a CSV or XLSX file into transactions. Nothing is written until
/// [commit], which runs in one transaction — a failure imports nothing.
class ImportService {
  const ImportService(this._db);

  final KoriDatabase _db;

  /// Parses a file by extension and guesses the column mapping from its headers.
  static ImportPreview preview(Uint8List bytes, {required String fileName}) {
    final rows = fileName.toLowerCase().endsWith('.xlsx')
        ? _firstSheet(bytes)
        : _csvRows(bytes);

    if (rows.isEmpty) {
      throw const FormatException('The file has no rows');
    }

    final headers = [
      for (final cell in rows.first) (cell ?? '').toString().trim(),
    ];

    return ImportPreview(
      headers: headers,
      rows: rows.skip(1).toList(),
      mapping: guessMapping(headers),
    );
  }

  /// Matches on the header text, so reordered or extra columns still work.
  static Map<ImportField, int> guessMapping(List<String> headers) {
    final normalised = [
      for (final header in headers) header.trim().toLowerCase(),
    ];
    final mapping = <ImportField, int>{};

    for (final field in ImportField.values) {
      // Exact alias first, then a contains match, so "Transaction date" is found
      // but "Date" does not swallow "Date posted to account" ahead of it.
      var index = normalised.indexWhere(field.aliases.contains);
      index = index != -1
          ? index
          : normalised.indexWhere(
              (header) => field.aliases.any(header.contains),
            );
      if (index != -1 && !mapping.containsValue(index)) {
        mapping[field] = index;
      }
    }

    return mapping;
  }

  /// Validates every row against the wallets and categories that exist.
  Future<ImportPlan> plan(
    ImportPreview preview, {
    String? fallbackWallet,
    required String fallbackCurrency,
  }) async {
    final wallets = await _db.select(_db.wallets).get();
    final categories = await _db.select(_db.categories).get();
    final walletNames = {for (final w in wallets) w.name.toLowerCase()};
    final categoryNames = {for (final c in categories) c.name.toLowerCase()};

    final rows = <ImportRow>[];
    final newWallets = <String>{};
    final newCategories = <String>{};

    for (final (index, raw) in preview.rows.indexed) {
      final line = index + 2;
      String? cell(ImportField field) {
        final column = preview.mapping[field];
        if (column == null || column >= raw.length) return null;
        final value = raw[column];
        final text = value is String ? value.trim() : value?.toString().trim();
        return (text == null || text.isEmpty) ? null : text;
      }

      // A trailing blank line is not an error.
      if (raw.every((cell) => cell == null || '$cell'.trim().isEmpty)) continue;

      final dateText = cell(ImportField.date);
      final normalisedDate = _normaliseDate(dateText);
      if (normalisedDate == null) {
        rows.add(ImportRow(
          line: line,
          problem: dateText == null
              ? 'No date'
              : 'Date "$dateText" is not a date we recognise',
        ));
        continue;
      }

      final currency = (cell(ImportField.currency) ?? fallbackCurrency)
          .toUpperCase();
      final amountText = cell(ImportField.amount);
      final parsed = amountText == null
          ? null
          : Money.tryParse(amountText.replaceAll(RegExp(r'[^\d.,+-]'), ''), currency);
      if (parsed == null || parsed.minor == 0) {
        rows.add(ImportRow(
          line: line,
          problem: amountText == null
              ? 'No amount'
              : 'Amount "$amountText" is not a number',
        ));
        continue;
      }

      // A leading minus is how most exports mark an expense.
      final typeText = cell(ImportField.type);
      final type = typeText == null
          ? (parsed.isNegative ? TransactionType.expense : TransactionType.income)
          : transactionTypeFromName(typeText);
      if (type == null) {
        rows.add(ImportRow(
          line: line,
          problem: 'Type "$typeText" is neither income, expense nor transfer',
        ));
        continue;
      }

      final walletName = cell(ImportField.wallet) ?? fallbackWallet;
      if (walletName == null) {
        rows.add(ImportRow(line: line, problem: 'No wallet, and none chosen'));
        continue;
      }

      final transferTo = cell(ImportField.transferTo);
      if (type == TransactionType.transfer && transferTo == null) {
        rows.add(ImportRow(
          line: line,
          problem: 'A transfer needs a destination wallet',
        ));
        continue;
      }
      if (transferTo != null &&
          transferTo.toLowerCase() == walletName.toLowerCase()) {
        rows.add(ImportRow(
          line: line,
          problem: 'Transfers into the same wallet make no sense',
        ));
        continue;
      }

      if (!walletNames.contains(walletName.toLowerCase())) {
        newWallets.add(walletName);
      }
      if (transferTo != null &&
          !walletNames.contains(transferTo.toLowerCase())) {
        newWallets.add(transferTo);
      }

      final categoryName =
          type == TransactionType.transfer ? null : cell(ImportField.category);
      if (categoryName != null &&
          !categoryNames.contains(categoryName.toLowerCase())) {
        newCategories.add(categoryName);
      }

      rows.add(ImportRow(
        line: line,
        date: normalisedDate,
        type: type,
        amount: parsed.abs(),
        wallet: walletName,
        category: categoryName,
        note: cell(ImportField.note),
        transferTo: transferTo,
      ));
    }

    return ImportPlan(
      rows: rows,
      newWallets: newWallets,
      newCategories: newCategories,
    );
  }

  /// Writes the valid rows, creating any missing wallets and categories first.
  /// All of it in one transaction: a failure imports nothing.
  Future<int> commit(ImportPlan plan, {required String fallbackCurrency}) {
    return _db.transaction(() async {
      final wallets = await _db.select(_db.wallets).get();
      final categories = await _db.select(_db.categories).get();
      final walletIds = {
        for (final wallet in wallets) wallet.name.toLowerCase(): wallet.id,
      };
      final categoryIds = {
        for (final category in categories)
          '${category.name.toLowerCase()}:${category.type.name}': category.id,
      };

      for (final name in plan.newWallets) {
        walletIds[name.toLowerCase()] = await _db.walletsDao.createWallet(
          WalletsCompanion.insert(
            name: name,
            currency: fallbackCurrency,
            color: 0xFF6366F1,
            type: const Value(WalletType.other),
          ),
        );
      }

      for (final name in plan.newCategories) {
        for (final type in CategoryType.values) {
          final key = '${name.toLowerCase()}:${type.name}';
          if (categoryIds.containsKey(key)) continue;
          categoryIds[key] = await _db.categoriesDao.createCategory(
            CategoriesCompanion.insert(
              name: name,
              type: type,
              color: 0xFF6366F1,
              sortOrder: const Value(999),
            ),
          );
        }
      }

      var imported = 0;
      for (final row in plan.valid) {
        final walletId = walletIds[row.wallet!.toLowerCase()];
        if (walletId == null) continue;

        final categoryType = row.type == TransactionType.income
            ? CategoryType.income
            : CategoryType.expense;

        await _db.transactionsDao.addTransaction(
          walletId: walletId,
          type: row.type!,
          amount: row.amount!,
          date: row.date!,
          categoryId: row.category == null
              ? null
              : categoryIds['${row.category!.toLowerCase()}:${categoryType.name}'],
          note: row.note,
          transferToWalletId: row.transferTo == null
              ? null
              : walletIds[row.transferTo!.toLowerCase()],
        );
        imported++;
      }

      return imported;
    });
  }

  static List<List<Object?>> _csvRows(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    // Strip a BOM, which would otherwise land inside the first header.
    if (text.startsWith('\u{FEFF}')) text = text.substring(1);
    // autoDetect picks up the semicolons European exports use.
    return Csv().decode(text);
  }

  static List<List<Object?>> _firstSheet(Uint8List bytes) {
    final sheets = decodeXlsx(bytes);
    if (sheets.isEmpty) throw const FormatException('The workbook has no sheets');
    return sheets.first.rows;
  }
}

final _isoDate = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})');
final _slashDate = RegExp(r'^(\d{1,2})[/.](\d{1,2})[/.](\d{4})');

/// Accepts the shapes other apps export, and refuses anything ambiguous rather
/// than guessing at a date that would land in the wrong month.
String? _normaliseDate(String? value) {
  if (value == null) return null;
  final text = value.trim();

  if (_isoDate.firstMatch(text) case final match?) {
    return _safeDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  // Day-first: unambiguous only when the first number cannot be a month.
  if (_slashDate.firstMatch(text) case final match?) {
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    final year = int.parse(match.group(3)!);
    if (first > 12 && second <= 12) return _safeDate(year, second, first);
    if (second > 12 && first <= 12) return _safeDate(year, first, second);
    // 03/04/2026 could be either; refuse instead of picking.
    return null;
  }

  return null;
}

String? _safeDate(int year, int month, int day) {
  if (month < 1 || month > 12 || day < 1) return null;
  if (day > daysInMonth(year, month)) return null;
  return dayKey(DateTime(year, month, day));
}
