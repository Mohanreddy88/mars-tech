import '../../../../core/utils/formatters.dart';

int _i(Object? v) => (v as num?)?.toInt() ?? 0;

/// Money totals shared by the payroll report and monthly summary.
class PayrollTotals {
  const PayrollTotals({
    required this.count,
    required this.gross,
    required this.net,
    required this.epf,
    required this.socso,
    required this.eis,
    required this.tax,
    this.otherDeductions = 0,
    this.average = 0,
  });

  final int count;
  final double gross;
  final double net;
  final double epf;
  final double socso;
  final double eis;
  final double tax;
  final double otherDeductions;
  final double average;

  factory PayrollTotals.fromJson(Map<String, dynamic> j, {String countKey = 'totalEmployees'}) =>
      PayrollTotals(
        count: _i(j[countKey] ?? j['employeeCount']),
        gross: toDouble(j['totalGross']),
        net: toDouble(j['totalNet']),
        epf: toDouble(j['totalEpf']),
        socso: toDouble(j['totalSocso']),
        eis: toDouble(j['totalEis']),
        tax: toDouble(j['totalTax']),
        otherDeductions: toDouble(j['totalDeductions']),
        average: toDouble(j['averageSalary']),
      );
}

/// GET /api/reports/department-payroll-summary
class PayrollReport {
  const PayrollReport({required this.monthName, required this.totals, required this.departments});

  final String monthName;
  final PayrollTotals totals;

  /// (department, totals)
  final List<(String, PayrollTotals)> departments;

  factory PayrollReport.fromJson(Map<String, dynamic> j) => PayrollReport(
        monthName: j['monthName'] as String? ?? '',
        totals: PayrollTotals.fromJson((j['totals'] as Map?)?.cast<String, dynamic>() ?? const {}),
        departments: [
          for (final d in ((j['departments'] as List?) ?? const []).cast<Map<String, dynamic>>())
            (d['departmentName'] as String? ?? 'Unassigned', PayrollTotals.fromJson(d, countKey: 'employeeCount'))
        ],
      );
}

/// Attendance counts (working days only; weekends/holidays separate).
class AttendanceCounts {
  const AttendanceCounts({
    required this.total,
    required this.present,
    required this.absent,
    required this.leave,
    required this.halfDay,
  });

  final int total;
  final int present;
  final int absent;
  final int leave;
  final int halfDay;

  /// Present (full + half days) as a share of working-day records.
  double get attendanceRate => total == 0 ? 0 : (present + halfDay) / total;

  factory AttendanceCounts.fromJson(Map<String, dynamic> j) => AttendanceCounts(
        total: _i(j['totalRecords']),
        present: _i(j['presentCount']),
        absent: _i(j['absentCount']),
        leave: _i(j['leaveCount']),
        halfDay: _i(j['halfDayCount']),
      );
}

/// Per-employee totals built from the day records of the attendance report.
class EmployeeAttendance {
  EmployeeAttendance(this.employeeName, this.department);

  final String employeeName;
  final String department;
  int workingDays = 0;
  int present = 0;
  int leave = 0;
  int absent = 0;
  double hours = 0;
}

/// GET /api/reports/attendance-by-date-range (approved attendance only).
class AttendanceReport {
  const AttendanceReport({
    required this.counts,
    required this.weekendDays,
    required this.holidayDays,
    required this.byDepartment,
    required this.byEmployee,
  });

  final AttendanceCounts counts;
  final int weekendDays;
  final int holidayDays;
  final List<(String, AttendanceCounts)> byDepartment;
  final List<EmployeeAttendance> byEmployee;

  factory AttendanceReport.fromJson(Map<String, dynamic> j) {
    final employees = <int, EmployeeAttendance>{};
    for (final r in ((j['records'] as List?) ?? const []).cast<Map<String, dynamic>>()) {
      final status = r['status'] as String? ?? '';
      if (status == 'Weekend' || status == 'Holiday') continue;
      final e = employees.putIfAbsent(_i(r['employeeId']),
          () => EmployeeAttendance(r['employeeName'] as String? ?? '', r['departmentName'] as String? ?? ''));
      e.workingDays++;
      e.hours += toDouble(r['workHours']);
      switch (status) {
        case 'Present' || 'HalfDay':
          e.present++;
        case 'Leave':
          e.leave++;
        case 'Absent':
          e.absent++;
      }
    }
    return AttendanceReport(
      counts: AttendanceCounts.fromJson(j),
      weekendDays: _i(j['weekendCount']),
      holidayDays: _i(j['holidayCount']),
      byDepartment: [
        for (final d in ((j['byDepartment'] as List?) ?? const []).cast<Map<String, dynamic>>())
          (d['department'] as String? ?? 'Unassigned', AttendanceCounts.fromJson(d))
      ],
      byEmployee: employees.values.toList()..sort((a, b) => a.employeeName.compareTo(b.employeeName)),
    );
  }
}

/// GET /api/reports/employee-directory
class DirectoryEntry {
  const DirectoryEntry({
    required this.id,
    required this.name,
    required this.email,
    required this.department,
    required this.isActive,
    this.phone,
    this.designation,
    this.joinDate,
  });

  final int id;
  final String name;
  final String email;
  final String department;
  final bool isActive;
  final String? phone;
  final String? designation;
  final DateTime? joinDate;

  factory DirectoryEntry.fromJson(Map<String, dynamic> j) => DirectoryEntry(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        email: j['email'] as String? ?? '',
        department: j['departmentName'] as String? ?? 'Unassigned',
        isActive: j['isActive'] as bool? ?? true,
        phone: j['phone'] as String?,
        designation: j['designation'] as String?,
        joinDate: tryCalendarDate(j['joinDate']),
      );
}

class EmployeeDirectory {
  const EmployeeDirectory({required this.active, required this.inactive, required this.byDepartment});

  final int active;
  final int inactive;
  final List<(String, List<DirectoryEntry>)> byDepartment;

  factory EmployeeDirectory.fromJson(Map<String, dynamic> j) => EmployeeDirectory(
        active: _i(j['activeEmployees']),
        inactive: _i(j['inactiveEmployees']),
        byDepartment: [
          for (final d in ((j['byDepartment'] as List?) ?? const []).cast<Map<String, dynamic>>())
            (
              d['department'] as String? ?? 'Unassigned',
              ((d['employees'] as List?) ?? const [])
                  .map((e) => DirectoryEntry.fromJson(e as Map<String, dynamic>))
                  .toList()
            )
        ],
      );
}

/// GET /api/reports/monthly-summary
class MonthlySummary {
  const MonthlySummary({
    required this.monthName,
    required this.payroll,
    required this.attendance,
    required this.averageWorkHours,
  });

  final String monthName;
  final PayrollTotals payroll;
  final AttendanceCounts attendance;
  final double averageWorkHours;

  factory MonthlySummary.fromJson(Map<String, dynamic> j) {
    final a = (j['attendance'] as Map?)?.cast<String, dynamic>() ?? const {};
    return MonthlySummary(
      monthName: j['monthName'] as String? ?? '',
      payroll: PayrollTotals.fromJson((j['payroll'] as Map?)?.cast<String, dynamic>() ?? const {},
          countKey: 'totalPayslips'),
      attendance: AttendanceCounts.fromJson(a),
      averageWorkHours: toDouble(a['averageWorkHours']),
    );
  }
}

/// One month of GET /api/analytics/payroll-trends
class PayrollTrendPoint {
  const PayrollTrendPoint({
    required this.label,
    required this.gross,
    required this.net,
    required this.deductions,
    required this.payslips,
  });

  final String label;
  final double gross;
  final double net;
  final double deductions;
  final int payslips;

  factory PayrollTrendPoint.fromJson(Map<String, dynamic> j) => PayrollTrendPoint(
        label: j['monthName'] as String? ?? '',
        gross: toDouble(j['totalGross']),
        net: toDouble(j['totalNet']),
        deductions: toDouble(j['totalDeductions']),
        payslips: _i(j['employeeCount']),
      );
}

/// GET /api/analytics/salary-distribution (active employees' basic salary).
class SalaryDistribution {
  const SalaryDistribution({
    required this.bands,
    required this.average,
    required this.median,
    required this.min,
    required this.max,
  });

  /// (band label, employees)
  final List<(String, int)> bands;
  final double average;
  final double median;
  final double min;
  final double max;

  factory SalaryDistribution.fromJson(Map<String, dynamic> j) => SalaryDistribution(
        bands: [
          ('Below RM 3k', _i(j['below3k'])),
          ('RM 3k – 5k', _i(j['range3kTo5k'])),
          ('RM 5k – 8k', _i(j['range5kTo8k'])),
          ('RM 8k – 12k', _i(j['range8kTo12k'])),
          ('RM 12k and above', _i(j['above12k'])),
        ],
        average: toDouble(j['averageSalary']),
        median: toDouble(j['medianSalary']),
        min: toDouble(j['minSalary']),
        max: toDouble(j['maxSalary']),
      );
}

/// GET /api/analytics/attendance-statistics -> byDepartment[]
class DepartmentAttendanceRate {
  const DepartmentAttendanceRate(this.department, this.ratePercent, this.employees);

  final String department;
  final double ratePercent;
  final int employees;

  factory DepartmentAttendanceRate.fromJson(Map<String, dynamic> j) => DepartmentAttendanceRate(
        j['department'] as String? ?? 'Unassigned',
        toDouble(j['attendanceRate']),
        _i(j['employeeCount']),
      );
}
