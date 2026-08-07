import 'package:flutter_test/flutter_test.dart';
import 'package:kori/core/dates.dart';
import 'package:kori/core/recurrence.dart';

void main() {
  group('day and month keys', () {
    test('pads single digits', () {
      expect(dayKey(DateTime(2026, 1, 5)), '2026-01-05');
      expect(monthKey(DateTime(2026, 1, 5)), '2026-01');
    });

    test('extracts the month from a day key', () {
      expect(monthOfDayKey('2026-08-07'), '2026-08');
    });

    test('parses back to local midnight', () {
      final parsed = parseDayKey('2026-08-07');
      expect(parsed, DateTime(2026, 8, 7));
      expect(parsed.hour, 0);
    });

    test('round-trips', () {
      for (final date in [
        DateTime(2026, 1, 1),
        DateTime(2026, 2, 29 - 1),
        DateTime(2024, 2, 29),
        DateTime(2026, 12, 31),
      ]) {
        expect(parseDayKey(dayKey(date)), date);
      }
    });

    test('rejects dates that do not exist', () {
      // DateTime() would silently roll Feb 30 into March.
      expect(() => parseDayKey('2026-02-30'), throwsFormatException);
      expect(() => parseDayKey('2026-13-01'), throwsFormatException);
      expect(() => parseDayKey('2025-02-29'), throwsFormatException);
    });
  });

  group('daysInMonth', () {
    test('handles ordinary months', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 4), 30);
    });

    test('handles February and leap years', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2024, 2), 29);
      expect(daysInMonth(2000, 2), 29);
      expect(daysInMonth(1900, 2), 28);
    });
  });

  group('advanceRecurrence', () {
    String next(
      String from,
      RecurrenceFrequency frequency, {
      int anchorDay = 1,
    }) => advanceRecurrence(
      from: from,
      frequency: frequency,
      anchorDay: anchorDay,
    );

    test('advances daily and weekly', () {
      expect(next('2026-08-07', RecurrenceFrequency.daily), '2026-08-08');
      expect(next('2026-08-31', RecurrenceFrequency.daily), '2026-09-01');
      expect(next('2026-08-07', RecurrenceFrequency.weekly), '2026-08-14');
      expect(next('2026-12-28', RecurrenceFrequency.weekly), '2027-01-04');
    });

    test('advances monthly within a year', () {
      expect(
        next('2026-03-15', RecurrenceFrequency.monthly, anchorDay: 15),
        '2026-04-15',
      );
    });

    test('rolls the year over', () {
      expect(
        next('2026-12-10', RecurrenceFrequency.monthly, anchorDay: 10),
        '2027-01-10',
      );
    });

    test('clamps a month-end anchor to a short month', () {
      expect(
        next('2026-01-31', RecurrenceFrequency.monthly, anchorDay: 31),
        '2026-02-28',
      );
      expect(
        next('2024-01-31', RecurrenceFrequency.monthly, anchorDay: 31),
        '2024-02-29',
      );
      expect(
        next('2026-03-31', RecurrenceFrequency.monthly, anchorDay: 31),
        '2026-04-30',
      );
    });

    test('returns to the anchor day after a short month', () {
      // The point of anchorDay: February must not shift the rule permanently.
      var date = '2026-01-31';
      final fired = <String>[];
      for (var i = 0; i < 4; i++) {
        date = next(date, RecurrenceFrequency.monthly, anchorDay: 31);
        fired.add(date);
      }
      expect(fired, ['2026-02-28', '2026-03-31', '2026-04-30', '2026-05-31']);
    });

    test('does not drift across a full year', () {
      var date = '2026-01-30';
      for (var i = 0; i < 12; i++) {
        date = next(date, RecurrenceFrequency.monthly, anchorDay: 30);
      }
      expect(date, '2027-01-30');
    });

    test('advances yearly, clamping Feb 29 anchors', () {
      expect(
        next('2026-06-15', RecurrenceFrequency.yearly, anchorDay: 15),
        '2027-06-15',
      );
      expect(
        next('2024-02-29', RecurrenceFrequency.yearly, anchorDay: 29),
        '2025-02-28',
      );
    });

    test('ignores the anchor for daily and weekly rules', () {
      expect(
        next('2026-08-07', RecurrenceFrequency.daily, anchorDay: 31),
        '2026-08-08',
      );
      expect(
        next('2026-08-07', RecurrenceFrequency.weekly, anchorDay: 31),
        '2026-08-14',
      );
    });
  });

  group('monthBounds', () {
    test('covers the whole month', () {
      final august = monthBounds(DateTime(2026, 8, 7));
      expect(august.start, '2026-08-01');
      expect(august.end, '2026-08-31');
    });

    test('handles February in a leap year', () {
      expect(monthBounds(DateTime(2024, 2, 10)).end, '2024-02-29');
      expect(monthBounds(DateTime(2026, 2, 10)).end, '2026-02-28');
    });
  });
}
