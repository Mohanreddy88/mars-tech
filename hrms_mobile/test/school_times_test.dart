import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/school/data/school_models.dart';

void main() {
  test('attendance shows late / automatic and suggests the session end for check-out', () {
    final day = AttendanceDay.fromJson({
      'date': '2026-11-23', 'today': '2026-11-23', 'rows': [], 'summary': {},
      'times': {'halfDayEnd': '12:30', 'fullDayEnd': '16:30', 'daycareEnd': '18:30', 'lateAfter': '09:00'},
    });
    expect(day.sessionEnd('Half day'), '12:30');
    expect(day.sessionEnd('Full day'), '16:30');
    expect(day.sessionEnd('Daycare'), '18:30');

    final a = AttendanceInfo.fromJson({'status': 'Present', 'checkIn': '09:12', 'isLate': true, 'autoCheckOut': true})!;
    expect(a.isLate, isTrue);
    expect(a.autoCheckOut, isTrue);
    expect(AttendanceInfo.fromJson({'status': 'Absent', 'autoAbsent': true})!.autoAbsent, isTrue);
  });
}
