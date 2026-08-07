import 'package:drift/drift.dart';

import '../../core/recurrence.dart';
import 'categories.dart';
import 'wallets.dart';

/// A standing instruction to create a transaction on a schedule. Evaluated on
/// device at launch and resume, so a phone that was off for a week catches up.
@TableIndex(name: 'idx_rules_due', columns: {#active, #nextDate})
class RecurringRules extends Table {
  IntColumn get id => integer().autoIncrement()();

  IntColumn get walletId =>
      integer().references(Wallets, #id, onDelete: KeyAction.cascade)();

  IntColumn get categoryId => integer().nullable().references(
    Categories,
    #id,
    onDelete: KeyAction.setNull,
  )();

  /// Income or expense; transfers are not schedulable.
  TextColumn get type => text()();

  IntColumn get amountMinor => integer()();

  TextColumn get currency => text().withLength(min: 3, max: 3)();

  TextColumn get note => text().nullable()();

  TextColumn get frequency => textEnum<RecurrenceFrequency>()();

  /// Day of month the rule was created for, 1–31. Kept separate from
  /// [nextDate] so month-end rules do not drift — see `advanceRecurrence`.
  IntColumn get anchorDay => integer().withDefault(const Constant(1))();

  /// Next occurrence, `YYYY-MM-DD`.
  TextColumn get nextDate => text().withLength(min: 10, max: 10)();

  /// Inclusive last date. Null runs forever.
  TextColumn get endDate => text().withLength(min: 10, max: 10).nullable()();

  BoolColumn get active => boolean().withDefault(const Constant(true))();

  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  List<String> get customConstraints => [
    'CHECK (amount_minor > 0)',
    "CHECK (type IN ('income', 'expense'))",
    'CHECK (anchor_day BETWEEN 1 AND 31)',
  ];
}
