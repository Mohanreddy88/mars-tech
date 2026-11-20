import '../../../core/utils/formatters.dart';
import '../../attendance/data/attendance_models.dart';

/// GET /api/dashboard/admin -> stats (+ a few lists we show).
class AdminDashboard {
  const AdminDashboard({
    required this.totalEmployees,
    required this.activeEmployees,
    required this.totalDepartments,
    required this.pendingLeaves,
    required this.pendingAttendance,
    required this.currentMonthPayrolls,
    required this.currentMonthPayrollAmount,
    required this.payrollByStatus,
    required this.departments,
    required this.recentActivities,
  });

  final int totalEmployees;
  final int activeEmployees;
  final int totalDepartments;
  final int pendingLeaves;
  final int pendingAttendance;
  final int currentMonthPayrolls;
  final double currentMonthPayrollAmount;

  /// This month's payrolls grouped by status: (status, count, net total).
  final List<(String, int, double)> payrollByStatus;

  /// (department, employee count)
  final List<(String, int)> departments;
  final List<AdminActivity> recentActivities;

  int get pendingApprovals => pendingLeaves + pendingAttendance;

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    final stats = (json['stats'] as Map?)?.cast<String, dynamic>() ?? const {};
    int i(String k) => (stats[k] as num?)?.toInt() ?? 0;
    List<Map<String, dynamic>> list(String k) =>
        ((json[k] as List?) ?? const []).cast<Map<String, dynamic>>();

    return AdminDashboard(
      totalEmployees: i('totalEmployees'),
      activeEmployees: i('activeEmployees'),
      totalDepartments: i('totalDepartments'),
      pendingLeaves: i('pendingLeaves'),
      pendingAttendance: i('pendingAttendance'),
      currentMonthPayrolls: i('currentMonthPayrolls'),
      currentMonthPayrollAmount: toDouble(stats['currentMonthPayrollAmount']),
      payrollByStatus: [
        for (final p in list('currentMonthPayrolls'))
          (p['status'] as String? ?? '', (p['count'] as num?)?.toInt() ?? 0, toDouble(p['totalAmount']))
      ],
      departments: [
        for (final d in list('departmentStats'))
          (d['departmentName'] as String? ?? 'No department', (d['employeeCount'] as num?)?.toInt() ?? 0)
      ],
      recentActivities: list('recentActivities').map(AdminActivity.fromJson).toList(),
    );
  }
}

class AdminActivity {
  const AdminActivity({
    required this.type,
    required this.employeeName,
    required this.description,
    this.timestamp,
  });

  /// leave_approval | attendance_approval | ...
  final String type;
  final String employeeName;
  final String description;
  final DateTime? timestamp;

  factory AdminActivity.fromJson(Map<String, dynamic> json) => AdminActivity(
        type: json['type'] as String? ?? '',
        employeeName: json['employeeName'] as String? ?? '',
        description: json['description'] as String? ?? '',
        timestamp: tryParseApiDate(json['timestamp']),
      );
}

/// GET /api/leavemanagement/requests/pending
class PendingLeave {
  const PendingLeave({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.leaveTypeName,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    this.reason,
    this.requestedOn,
    this.attachmentName,
  });

  final int id;
  final int employeeId;
  final String employeeName;
  final String leaveTypeName;
  final DateTime startDate;
  final DateTime endDate;
  final double totalDays;
  final String? reason;
  final DateTime? requestedOn;
  final String? attachmentName;

  factory PendingLeave.fromJson(Map<String, dynamic> json) => PendingLeave(
        id: json['id'] as int,
        employeeId: json['employeeId'] as int? ?? 0,
        employeeName: json['employeeName'] as String? ?? '',
        leaveTypeName: json['leaveTypeName'] as String? ?? '',
        startDate: tryCalendarDate(json['startDate']) ?? DateTime.now(),
        endDate: tryCalendarDate(json['endDate']) ?? DateTime.now(),
        totalDays: toDouble(json['totalDays']),
        reason: json['reason'] as String?,
        requestedOn: tryParseApiDate(json['requestedOn']),
        attachmentName: json['attachmentName'] as String?,
      );
}

/// GET /api/attendancemanagement/pending
class PendingAttendance {
  const PendingAttendance({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.start,
    required this.end,
    required this.totalHours,
    required this.leaveCount,
    this.submittedAt,
  });

  final int id;
  final int employeeId;
  final String employeeName;
  final DateTime start;
  final DateTime end;
  final double totalHours;
  final int leaveCount;
  final DateTime? submittedAt;

  String get label => start.month == end.month
      ? '${Fmt.shortDate(start)} – ${Fmt.date(end)}'
      : '${Fmt.date(start)} – ${Fmt.date(end)}';

  factory PendingAttendance.fromJson(Map<String, dynamic> json) => PendingAttendance(
        id: json['id'] as int,
        employeeId: json['employeeId'] as int? ?? 0,
        employeeName: json['employeeName'] as String? ?? '',
        start: tryCalendarDate(json['startDate']) ?? DateTime.now(),
        end: tryCalendarDate(json['endDate']) ?? DateTime.now(),
        totalHours: toDouble(json['totalHours']),
        leaveCount: (json['leaveCount'] as num?)?.toInt() ?? 0,
        submittedAt: tryParseApiDate(json['submittedAt']),
      );
}

/// GET /api/attendancemanagement/{id}/details: the period with its days and
/// the employee's leave in that period (to check leave codes against).
class AttendanceReview {
  const AttendanceReview({
    required this.id,
    required this.employeeName,
    required this.department,
    required this.status,
    required this.start,
    required this.end,
    required this.days,
    required this.approvedLeaves,
    required this.pendingLeaves,
    this.rejectionReason,
  });

  final int id;
  final String employeeName;
  final String department;
  final String status;
  final DateTime start;
  final DateTime end;
  final List<AttendanceDay> days;

  /// "AL 02 Nov – 03 Nov (2 days)" style lines.
  final List<String> approvedLeaves;
  final List<String> pendingLeaves;
  final String? rejectionReason;

  double get totalHours =>
      days.where((d) => !d.isLeave).fold(0.0, (sum, d) => sum + d.hours);
  int get leaveDays => days.where((d) => d.isLeave).length;

  String get label => start.month == end.month
      ? '${Fmt.shortDate(start)} – ${Fmt.date(end)}'
      : '${Fmt.date(start)} – ${Fmt.date(end)}';

  static List<String> _leaveLines(Object? list) => [
        for (final l in ((list as List?) ?? const []).cast<Map<String, dynamic>>())
          '${l['leaveTypeCode'] ?? l['leaveType'] ?? ''}  '
              '${Fmt.shortDate(tryCalendarDate(l['startDate']))} – '
              '${Fmt.shortDate(tryCalendarDate(l['endDate']))}  '
              '(${Fmt.days(toDouble(l['totalDays']))})'
      ];

  factory AttendanceReview.fromJson(Map<String, dynamic> json) => AttendanceReview(
        id: json['id'] as int,
        employeeName: json['employeeName'] as String? ?? '',
        department: json['employeeDepartment'] as String? ?? '',
        status: json['status'] as String? ?? '',
        start: tryCalendarDate(json['startDate']) ?? DateTime.now(),
        end: tryCalendarDate(json['endDate']) ?? DateTime.now(),
        rejectionReason: json['rejectionReason'] as String?,
        days: ((json['days'] as List?) ?? const [])
            .map((d) => AttendanceDay.fromJson(d as Map<String, dynamic>))
            .toList(),
        approvedLeaves: _leaveLines(json['approvedLeaves']),
        pendingLeaves: _leaveLines(json['pendingLeaves']),
      );
}

/// One row of GET /api/employees (admin).
class EmployeeSummary {
  const EmployeeSummary({
    required this.id,
    required this.name,
    required this.email,
    required this.isActive,
    this.employeeCode,
    this.phone,
    this.phoneCountryCode,
    this.departmentName,
    this.designation,
    this.joinDate,
    this.salary,
    this.bankName,
    this.accountNumber,
    this.gender,
    this.idType,
    this.icPassport,
    this.taxNumber,
    this.dateOfBirth,
  });

  final int id;
  final String name;
  final String email;
  final bool isActive;
  final String? employeeCode;
  final String? phone;
  final String? phoneCountryCode;
  final String? departmentName;
  final String? designation;
  final DateTime? joinDate;
  final double? salary;
  final String? bankName;
  final String? accountNumber;
  final String? gender;
  final String? idType;
  final String? icPassport;
  final String? taxNumber;
  final DateTime? dateOfBirth;

  String get phoneDisplay {
    if (phone == null || phone!.isEmpty) return '';
    final code = phoneCountryCode ?? '';
    return code.isEmpty ? phone! : '$code $phone';
  }

  /// Case-insensitive match on name, code, email, department or designation.
  bool matches(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return true;
    return [name, email, employeeCode, departmentName, designation]
        .any((s) => s != null && s.toLowerCase().contains(q));
  }

  factory EmployeeSummary.fromJson(Map<String, dynamic> json) => EmployeeSummary(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        isActive: json['isActive'] as bool? ?? true,
        employeeCode: json['employeeCode'] as String?,
        phone: json['phone'] as String?,
        phoneCountryCode: json['phoneCountryCode'] as String?,
        departmentName: json['departmentName'] as String?,
        designation: json['designation'] as String?,
        joinDate: tryCalendarDate(json['joinDate']),
        salary: (json['salary'] as num?)?.toDouble(),
        bankName: json['bankName'] as String?,
        accountNumber: json['accountNumber'] as String?,
        gender: json['gender'] as String?,
        idType: json['idType'] as String?,
        icPassport: json['icPassport'] as String?,
        taxNumber: json['taxNumber'] as String?,
        dateOfBirth: tryCalendarDate(json['dateOfBirth']),
      );
}

/// One row of GET /api/payroll/employee/{id}
class EmployeePayrollRow {
  const EmployeePayrollRow({
    required this.id,
    required this.monthYear,
    required this.grossIncome,
    required this.netSalary,
    required this.status,
  });

  final int id;
  final String monthYear;
  final double grossIncome;
  final double netSalary;
  final String status;

  factory EmployeePayrollRow.fromJson(Map<String, dynamic> json) => EmployeePayrollRow(
        id: json['id'] as int,
        monthYear: json['monthYear'] as String? ?? '',
        grossIncome: toDouble(json['grossIncome']),
        netSalary: toDouble(json['netSalary']),
        status: json['status'] as String? ?? '',
      );
}
