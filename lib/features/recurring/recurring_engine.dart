import '../../core/dates.dart';
import '../../core/money.dart';
import '../../data/db.dart';
import '../../data/tables/transactions.dart';

/// Generates transactions for rules that have come due.
///
/// Runs on device at launch and on resume — there is no server and no background
/// worker, so a phone that was off for a week simply replays what it missed.
class RecurringEngine {
  const RecurringEngine(this._db);

  final KoriDatabase _db;

  /// A dormant daily rule would otherwise generate unbounded rows in one pass.
  static const maxOccurrencesPerRun = 400;

  /// Creates every transaction due on or before today. Returns the count.
  Future<int> catchUp({DateTime? now}) async {
    final today = todayKey(now: now);
    final rules = await _db.recurringDao.due(today);

    var created = 0;
    for (final rule in rules) {
      created += await _replay(rule, today);
    }
    return created;
  }

  Future<int> _replay(RecurringRule rule, String today) async {
    return _db.transaction(() async {
      var date = rule.nextDate;
      var active = true;
      var created = 0;

      while (date.compareTo(today) <= 0 && created < maxOccurrencesPerRun) {
        if (rule.endDate case final end? when date.compareTo(end) > 0) {
          active = false;
          break;
        }

        await _db.transactionsDao.addTransaction(
          walletId: rule.walletId,
          type: rule.type == 'income'
              ? TransactionType.income
              : TransactionType.expense,
          amount: Money(rule.amountMinor, rule.currency),
          date: date,
          categoryId: rule.categoryId,
          note: rule.note,
          recurringRuleId: rule.id,
        );
        created += 1;

        date = advanceRecurrence(
          from: date,
          frequency: rule.frequency,
          anchorDay: rule.anchorDay,
        );
      }

      if (rule.endDate case final end? when date.compareTo(end) > 0) {
        active = false;
      }

      await _db.recurringDao.advance(rule.id, date, active: active);
      return created;
    });
  }
}
