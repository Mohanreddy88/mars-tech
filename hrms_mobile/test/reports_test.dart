import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/admin/reports/data/reports_models.dart';

void main() {
  test('attendance report: per-employee totals skip weekends and holidays', () {
    final r = AttendanceReport.fromJson({
      'totalRecords': 4,
      'presentCount': 2,
      'absentCount': 0,
      'leaveCount': 1,
      'halfDayCount': 1,
      'weekendCount': 2,
      'holidayCount': 0,
      'byDepartment': [
        {'department': 'Engineering', 'totalRecords': 4, 'presentCount': 2, 'leaveCount': 1, 'halfDayCount': 1, 'absentCount': 0},
      ],
      'records': [
        {'employeeId': 1, 'employeeName': 'B', 'departmentName': 'Engineering', 'status': 'Present', 'workHours': 8},
        {'employeeId': 1, 'employeeName': 'B', 'departmentName': 'Engineering', 'status': 'HalfDay', 'workHours': 4},
        {'employeeId': 1, 'employeeName': 'B', 'departmentName': 'Engineering', 'status': 'Weekend', 'workHours': 0},
        {'employeeId': 2, 'employeeName': 'A', 'departmentName': 'Engineering', 'status': 'Present', 'workHours': 8},
        {'employeeId': 2, 'employeeName': 'A', 'departmentName': 'Engineering', 'status': 'Leave', 'workHours': 0, 'leaveCode': 'AL'},
        {'employeeId': 2, 'employeeName': 'A', 'departmentName': 'Engineering', 'status': 'Weekend', 'workHours': 0},
      ],
    });
    expect(r.counts.attendanceRate, 0.75); // (2 present + 1 half day) / 4
    expect(r.byEmployee.map((e) => e.employeeName), ['A', 'B']); // sorted by name
    final b = r.byEmployee[1];
    expect(b.workingDays, 2);
    expect(b.present, 2);
    expect(b.hours, 12);
    expect(r.byEmployee[0].leave, 1);
    expect(r.byDepartment.single.$2.attendanceRate, 0.75);
  });

  test('payroll report and monthly summary parse totals', () {
    final p = PayrollReport.fromJson({
      'monthName': 'November 2026',
      'departments': [
        {'departmentName': 'Engineering', 'employeeCount': 2, 'totalNet': 20000, 'totalGross': 24000, 'averageSalary': 10000},
      ],
      'totals': {'totalEmployees': 2, 'totalNet': 20000, 'totalGross': 24000, 'totalTax': 3000},
    });
    expect(p.totals.count, 2);
    expect(p.departments.single.$1, 'Engineering');
    expect(p.departments.single.$2.average, 10000);

    final m = MonthlySummary.fromJson({
      'monthName': 'November 2026',
      'payroll': {'totalPayslips': 1, 'totalNet': 10206.18, 'averageSalary': 10206.18},
      'attendance': {'totalRecords': 20, 'presentCount': 18, 'leaveCount': 2, 'averageWorkHours': 8},
    });
    expect(m.payroll.count, 1);
    expect(m.attendance.attendanceRate, 0.9);
    expect(m.averageWorkHours, 8);
  });

  test('salary distribution keeps band order', () {
    final s = SalaryDistribution.fromJson({
      'below3k': 1, 'range3kTo5k': 2, 'range5kTo8k': 0, 'range8kTo12k': 3, 'above12k': 1,
      'averageSalary': 7000, 'medianSalary': 6000, 'minSalary': 2500, 'maxSalary': 15000,
    });
    expect(s.bands.map((b) => b.$2), [1, 2, 0, 3, 1]);
    expect(s.bands.first.$1, 'Below RM 3k');
  });
}
