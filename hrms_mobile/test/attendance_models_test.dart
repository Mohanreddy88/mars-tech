import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/utils/formatters.dart';
import 'package:hrms_mobile/features/attendance/data/attendance_models.dart';

void main() {
  final today = DateTime(2026, 11, 20);

  group('buildPeriodList', () {
    test('half-month cycles for the last 6 months, newest first, none in the future', () {
      final list = buildPeriodList(saved: [], publicHolidays: {}, today: today);
      // May..Nov = 7 months x 2 cycles = 14 (16–30 Nov has started, so it is included).
      expect(list.length, 14);
      expect(list.first.start, DateTime(2026, 11, 16));
      expect(list.first.end, DateTime(2026, 11, 30));
      expect(list.last.start, DateTime(2026, 5, 1));
      expect(list.every((p) => !p.isSaved && p.displayStatus == 'Not started'), isTrue);
    });

    test('February second cycle ends on the last day of the month', () {
      final list = buildPeriodList(
          saved: [], publicHolidays: {}, today: DateTime(2027, 2, 20), monthsBack: 0);
      expect(list.first.end, DateTime(2027, 2, 28));
    });

    test('skips cycles that end before the join date', () {
      final list = buildPeriodList(
          saved: [], publicHolidays: {}, today: today, joinDate: DateTime(2026, 10, 20));
      expect(list.map((p) => p.start), [
        DateTime(2026, 11, 16),
        DateTime(2026, 11, 1),
        DateTime(2026, 10, 16),
      ]);
    });

    test('a saved period replaces its cycle; a saved whole month covers both cycles', () {
      final savedCycle = AttendancePeriod(
          id: 9, start: DateTime(2026, 11, 1), end: DateTime(2026, 11, 15), status: 'Submitted', days: []);
      final savedMonth = AttendancePeriod(
          id: 3, start: DateTime(2026, 10, 1), end: DateTime(2026, 10, 31), status: 'Approved', days: []);
      final list = buildPeriodList(
          saved: [savedCycle, savedMonth],
          publicHolidays: {},
          today: today,
          joinDate: DateTime(2026, 10, 1));
      expect(list.map((p) => (p.id, p.start)), [
        (null, DateTime(2026, 11, 16)),
        (9, DateTime(2026, 11, 1)),
        (3, DateTime(2026, 10, 1)),
      ]);
    });

    test('marks weekends and public holidays on generated days', () {
      final list = buildPeriodList(
          saved: [],
          publicHolidays: {DateTime(2026, 11, 9)},
          today: today,
          monthsBack: 0);
      final firstHalf = list.firstWhere((p) => p.start.day == 1);
      final nov1 = firstHalf.days.first; // Sunday
      final nov9 = firstHalf.days.firstWhere((d) => d.date.day == 9);
      expect(nov1.isWeekend, isTrue);
      expect(nov9.isPublicHoliday, isTrue);
      expect(nov9.isWorkingDay, isFalse);
      // 1–15 Nov 2026: weekends 1, 7, 8, 14, 15 and the 9th is a holiday -> 9 working days.
      expect(firstHalf.workingDays, 9);
    });
  });

  group('AttendanceDay', () {
    test('leave day is sent with 0 hours and the code; comment required', () {
      final d = AttendanceDay(date: DateTime(2026, 11, 3), hours: 8, leaveCode: 'AL');
      expect(d.needsComment, isTrue);
      expect(d.toJson(), {
        'date': '2026-11-03T00:00:00Z',
        'hours': 0,
        'note': 'AL',
        'remarks': null,
        'isPublicHoliday': false,
        'isWeekend': false,
      });
      d.remarks = '  Family trip ';
      expect(d.needsComment, isFalse);
      expect(d.toJson()['remarks'], 'Family trip');
    });

    test('parses API day (UTC midnight) to the same calendar date', () {
      final d = AttendanceDay.fromJson({
        'date': '2026-11-03T00:00:00',
        'hours': 7.5,
        'note': '',
        'isPublicHoliday': false,
        'isWeekend': false,
      });
      expect(d.date, DateTime(2026, 11, 3));
      expect(d.hours, 7.5);
      expect(d.isLeave, isFalse);
    });
  });

  test('period totals and edit rules', () {
    final p = AttendancePeriod(
      id: 1,
      start: DateTime(2026, 11, 2),
      end: DateTime(2026, 11, 4),
      status: 'Rejected',
      days: [
        AttendanceDay(date: DateTime(2026, 11, 2), hours: 8),
        AttendanceDay(date: DateTime(2026, 11, 3), leaveCode: 'MC', remarks: 'Fever'),
        AttendanceDay(date: DateTime(2026, 11, 4)),
      ],
    );
    expect(p.totalHours, 8);
    expect(p.leaveDays, 1);
    expect(p.emptyWorkingDays, 1);
    expect(p.isEditable, isTrue);
    p.status = 'Submitted';
    expect(p.isEditable, isFalse);
  });

  test('apiDate formats a calendar date as UTC midnight', () {
    expect(apiDate(DateTime(2026, 1, 5)), '2026-01-05T00:00:00Z');
  });
}
