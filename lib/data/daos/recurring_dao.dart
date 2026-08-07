import 'package:drift/drift.dart';

import '../../core/money.dart';
import '../db.dart';
import '../tables/categories.dart';
import '../tables/recurring_rules.dart';
import '../tables/wallets.dart';

part 'recurring_dao.g.dart';

/// A rule with the wallet and category it writes to.
class RecurringRuleDetails {
  const RecurringRuleDetails({
    required this.rule,
    required this.wallet,
    this.category,
  });

  final RecurringRule rule;
  final Wallet wallet;
  final Category? category;

  Money get amount => Money(rule.amountMinor, rule.currency);
}

@DriftAccessor(tables: [RecurringRules, Wallets, Categories])
class RecurringDao extends DatabaseAccessor<KoriDatabase>
    with _$RecurringDaoMixin {
  RecurringDao(super.attachedDatabase);

  Stream<List<RecurringRuleDetails>> watchRules() {
    final query =
        select(recurringRules).join([
          innerJoin(wallets, wallets.id.equalsExp(recurringRules.walletId)),
          leftOuterJoin(
            categories,
            categories.id.equalsExp(recurringRules.categoryId),
          ),
        ])..orderBy([
          OrderingTerm.desc(recurringRules.active),
          OrderingTerm.asc(recurringRules.nextDate),
        ]);

    return query.watch().map(
      (rows) => rows
          .map(
            (row) => RecurringRuleDetails(
              rule: row.readTable(recurringRules),
              wallet: row.readTable(wallets),
              category: row.readTableOrNull(categories),
            ),
          )
          .toList(),
    );
  }

  /// Active rules due on or before [today], oldest first so a phone that was off
  /// for a week replays in order.
  Future<List<RecurringRule>> due(String today) {
    return (select(recurringRules)
          ..where(
            (r) =>
                r.active.equals(true) & r.nextDate.isSmallerOrEqualValue(today),
          )
          ..orderBy([(r) => OrderingTerm.asc(r.nextDate)]))
        .get();
  }

  Future<int> createRule(RecurringRulesCompanion rule) =>
      into(recurringRules).insert(rule);

  Future<bool> updateRule(RecurringRule rule) =>
      update(recurringRules).replace(rule.copyWith(updatedAt: DateTime.now()));

  Future<int> setActive(int id, {required bool active}) =>
      (update(recurringRules)..where((r) => r.id.equals(id))).write(
        RecurringRulesCompanion(
          active: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );

  Future<int> deleteRule(int id) =>
      (delete(recurringRules)..where((r) => r.id.equals(id))).go();

  /// Advances a rule after it fires. [active] goes false once past its end date.
  Future<int> advance(int id, String nextDate, {required bool active}) =>
      (update(recurringRules)..where((r) => r.id.equals(id))).write(
        RecurringRulesCompanion(
          nextDate: Value(nextDate),
          active: Value(active),
          updatedAt: Value(DateTime.now()),
        ),
      );
}
