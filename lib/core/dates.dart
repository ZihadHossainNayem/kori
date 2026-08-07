/// Calendar-date helpers.
///
/// Dates are stored as `YYYY-MM-DD` text. Grouping is always by local calendar
/// day or month, and text dates make that a string comparison in SQL with no
/// timezone ambiguity at day boundaries.
library;

import 'recurrence.dart';

/// `YYYY-MM-DD` for the local calendar day of [date].
String dayKey(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$month-$day';
}

/// `YYYY-MM` for [date].
String monthKey(DateTime date) =>
    '${date.year.toString().padLeft(4, '0')}-'
    '${date.month.toString().padLeft(2, '0')}';

/// The `YYYY-MM` part of a `YYYY-MM-DD` key.
String monthOfDayKey(String key) => key.substring(0, 7);

/// Parses a `YYYY-MM-DD` key to local midnight. Throws rather than letting a
/// bad date silently become today, or Feb 30 roll into March.
DateTime parseDayKey(String key) {
  final year = int.parse(key.substring(0, 4));
  final month = int.parse(key.substring(5, 7));
  final day = int.parse(key.substring(8, 10));
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    throw FormatException('Not a real calendar date', key);
  }
  return parsed;
}

String todayKey({DateTime? now}) => dayKey(now ?? DateTime.now());

int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

/// The next occurrence after [from].
///
/// [anchorDay] is the rule's day of month, reapplied each period and clamped to
/// the target month's length. That is what stops drift: an anchor of 31 fires on
/// Jan 31, Feb 28, Mar 31, whereas adding a month to the last fired date walks
/// it to Mar 3 and onwards. Ignored for daily and weekly rules.
String advanceRecurrence({
  required String from,
  required RecurrenceFrequency frequency,
  required int anchorDay,
}) {
  final current = parseDayKey(from);

  switch (frequency) {
    case RecurrenceFrequency.daily:
      return dayKey(current.add(const Duration(days: 1)));

    case RecurrenceFrequency.weekly:
      return dayKey(current.add(const Duration(days: 7)));

    case RecurrenceFrequency.monthly:
      var year = current.year;
      var month = current.month + 1;
      if (month > 12) {
        month = 1;
        year += 1;
      }
      return dayKey(
        DateTime(year, month, _clampDay(anchorDay, year, month)),
      );

    case RecurrenceFrequency.yearly:
      final year = current.year + 1;
      final month = current.month;
      return dayKey(
        DateTime(year, month, _clampDay(anchorDay, year, month)),
      );
  }
}

int _clampDay(int day, int year, int month) {
  final limit = daysInMonth(year, month);
  if (day < 1) return 1;
  return day > limit ? limit : day;
}

/// Inclusive first and last day keys of [date]'s month.
({String start, String end}) monthBounds(DateTime date) {
  final last = daysInMonth(date.year, date.month);
  return (
    start: dayKey(DateTime(date.year, date.month, 1)),
    end: dayKey(DateTime(date.year, date.month, last)),
  );
}
