import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/router/app_router.dart';
import 'package:hrms_mobile/features/admin/data/admin_models.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';

Session _session(String role) => Session(
      token: 't',
      username: 'u',
      role: role,
      expiresAt: DateTime.utc(2099),
    );

void main() {
  group('role areas', () {
    final admin = _session('Admin');
    final employee = _session('Employee');

    test('home screen per role', () {
      expect(Routes.homeFor(admin), Routes.adminHome);
      expect(Routes.homeFor(employee), Routes.dashboard);
    });

    test('admins are kept out of employee screens and vice versa', () {
      expect(Routes.isWrongArea(admin, Routes.leave), isTrue);
      expect(Routes.isWrongArea(admin, '${Routes.payslips}/3'), isTrue);
      expect(Routes.isWrongArea(admin, Routes.adminApprovals), isFalse);
      expect(Routes.isWrongArea(admin, Routes.notifications), isFalse);

      expect(Routes.isWrongArea(employee, Routes.adminHome), isTrue);
      expect(Routes.isWrongArea(employee, '${Routes.attendanceReview}/5'), isTrue);
      expect(Routes.isWrongArea(employee, Routes.attendance), isFalse);
      // '/attendance-review' must not be mistaken for '/attendance/...'.
      expect(Routes.isWrongArea(admin, '${Routes.attendanceReview}/5'), isFalse);
    });
  });

  test('AdminDashboard parses /api/dashboard/admin', () {
    final d = AdminDashboard.fromJson({
      'stats': {
        'totalEmployees': 5,
        'activeEmployees': 4,
        'totalDepartments': 3,
        'pendingLeaves': 2,
        'pendingAttendance': 1,
        'currentMonthPayrolls': 4,
        'currentMonthPayrollAmount': 40000.5,
      },
      'currentMonthPayrolls': [
        {'status': 'Draft', 'count': 3, 'totalAmount': 30000},
        {'status': 'Approved', 'count': 1, 'totalAmount': 10000.5},
      ],
      'departmentStats': [
        {'departmentName': 'Engineering', 'employeeCount': 2},
      ],
      'recentActivities': [
        {
          'type': 'leave_approval',
          'employeeName': 'A',
          'description': 'Annual Leave approved',
          'timestamp': '2026-11-20T04:00:00',
        },
      ],
    });
    expect(d.pendingApprovals, 3);
    expect(d.currentMonthPayrollAmount, 40000.5);
    expect(d.payrollByStatus.first, ('Draft', 3, 30000.0));
    expect(d.departments.single, ('Engineering', 2));
    expect(d.recentActivities.single.timestamp, DateTime.utc(2026, 11, 20, 4));
  });

  test('EmployeeSummary search matches name, code, department', () {
    final e = EmployeeSummary.fromJson({
      'id': 1,
      'name': 'Mohan Reddy',
      'email': 'm@x.com',
      'isActive': true,
      'employeeCode': 'EMP000001',
      'departmentName': 'Engineering',
    });
    expect(e.matches('mohan'), isTrue);
    expect(e.matches('emp0000'), isTrue);
    expect(e.matches('ENGINEER'), isTrue);
    expect(e.matches('finance'), isFalse);
    expect(e.matches('  '), isTrue);
  });

  test('AttendanceReview parses days and leave lines', () {
    final r = AttendanceReview.fromJson({
      'id': 7,
      'employeeName': 'A',
      'employeeDepartment': 'Engineering',
      'status': 'Submitted',
      'startDate': '2026-11-01T00:00:00',
      'endDate': '2026-11-15T00:00:00',
      'days': [
        {'date': '2026-11-02T00:00:00', 'hours': 8, 'note': null, 'isPublicHoliday': false, 'isWeekend': false},
        {'date': '2026-11-03T00:00:00', 'hours': 0, 'note': 'AL', 'remarks': 'Trip', 'isPublicHoliday': false, 'isWeekend': false},
      ],
      'approvedLeaves': [],
      'pendingLeaves': [
        {'leaveTypeCode': 'AL', 'startDate': '2026-11-03T00:00:00', 'endDate': '2026-11-03T00:00:00', 'totalDays': 1},
      ],
    });
    expect(r.totalHours, 8);
    expect(r.leaveDays, 1);
    expect(r.pendingLeaves.single, contains('AL'));
    expect(r.pendingLeaves.single, contains('1 day'));
  });
}
