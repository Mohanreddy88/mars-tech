import '../../../core/utils/formatters.dart';

/// Mirrors the anonymous object returned by
/// GET /api/selfservice/dashboard (SelfServiceController.GetEmployeeDashboard).
class EmployeeDashboard {
  EmployeeDashboard({
    required this.employee,
    required this.stats,
    required this.leaveBalances,
    required this.recentPayslips,
    required this.upcomingLeaves,
    required this.upcomingHolidays,
  });

  final DashboardEmployee employee;
  final DashboardStats stats;
  final List<LeaveBalance> leaveBalances;
  final List<PayslipSummary> recentPayslips;
  final List<UpcomingLeave> upcomingLeaves;
  final List<Holiday> upcomingHolidays;

  factory EmployeeDashboard.fromJson(Map<String, dynamic> json) =>
      EmployeeDashboard(
        employee: DashboardEmployee.fromJson(
            json['employee'] as Map<String, dynamic>),
        stats: DashboardStats.fromJson(json['stats'] as Map<String, dynamic>),
        leaveBalances: _list(json['leaveBalances'], LeaveBalance.fromJson),
        recentPayslips: _list(json['recentPayslips'], PayslipSummary.fromJson),
        upcomingLeaves: _list(json['upcomingLeaves'], UpcomingLeave.fromJson),
        upcomingHolidays: _list(json['upcomingHolidays'], Holiday.fromJson),
      );
}

List<T> _list<T>(Object? value, T Function(Map<String, dynamic>) parse) =>
    (value as List<dynamic>? ?? const [])
        .map((e) => parse(e as Map<String, dynamic>))
        .toList();

class DashboardEmployee {
  DashboardEmployee({
    required this.id,
    required this.name,
    required this.email,
    this.employeeCode,
    this.designation,
    this.departmentName,
    this.joinDate,
  });

  final int id;
  final String name;
  final String email;
  final String? employeeCode;
  final String? designation;
  final String? departmentName;
  final DateTime? joinDate;

  String get firstName => name.trim().split(RegExp(r'\s+')).first;

  factory DashboardEmployee.fromJson(Map<String, dynamic> json) =>
      DashboardEmployee(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        employeeCode: json['employeeCode'] as String?,
        designation: json['designation'] as String?,
        departmentName: json['departmentName'] as String?,
        joinDate: tryParseApiDate(json['joinDate']),
      );
}

class DashboardStats {
  DashboardStats({
    required this.totalLeaveBalance,
    required this.totalLeaveUsed,
    required this.pendingApprovals,
    required this.currentMonthAttendance,
  });

  final double totalLeaveBalance;
  final double totalLeaveUsed;
  final int pendingApprovals;
  final int currentMonthAttendance;

  factory DashboardStats.fromJson(Map<String, dynamic> json) => DashboardStats(
        totalLeaveBalance: toDouble(json['totalLeaveBalance']),
        totalLeaveUsed: toDouble(json['totalLeaveUsed']),
        pendingApprovals: (json['pendingApprovals'] as num?)?.toInt() ?? 0,
        currentMonthAttendance:
            (json['currentMonthAttendance'] as num?)?.toInt() ?? 0,
      );
}

class LeaveBalance {
  LeaveBalance({
    required this.code,
    required this.name,
    required this.totalDays,
    required this.usedDays,
    required this.balanceDays,
  });

  final String code;
  final String name;
  final double totalDays;
  final double usedDays;
  final double balanceDays;

  /// Share of entitlement already used, 0..1.
  double get usedFraction =>
      totalDays <= 0 ? 0 : (usedDays / totalDays).clamp(0, 1).toDouble();

  factory LeaveBalance.fromJson(Map<String, dynamic> json) => LeaveBalance(
        code: json['leaveTypeCode'] as String? ?? '',
        name: json['leaveTypeName'] as String? ?? '',
        totalDays: toDouble(json['totalDays']),
        usedDays: toDouble(json['usedDays']),
        balanceDays: toDouble(json['balanceDays']),
      );
}

class PayslipSummary {
  PayslipSummary({
    required this.id,
    required this.monthYear,
    required this.netSalary,
    required this.status,
  });

  final int id;
  final String monthYear;
  final double netSalary;
  final String status;

  factory PayslipSummary.fromJson(Map<String, dynamic> json) => PayslipSummary(
        id: json['id'] as int,
        monthYear: json['monthYear'] as String? ?? '',
        netSalary: toDouble(json['netSalary']),
        status: json['status'] as String? ?? '',
      );
}

class UpcomingLeave {
  UpcomingLeave({
    required this.id,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
  });

  final int id;
  final String leaveType;
  final DateTime? startDate;
  final DateTime? endDate;
  final double totalDays;

  factory UpcomingLeave.fromJson(Map<String, dynamic> json) => UpcomingLeave(
        id: json['id'] as int,
        leaveType: json['leaveType'] as String? ?? '',
        startDate: tryParseApiDate(json['startDate']),
        endDate: tryParseApiDate(json['endDate']),
        totalDays: toDouble(json['totalDays']),
      );
}

class Holiday {
  Holiday({required this.id, required this.name, required this.date});

  final int id;
  final String name;
  final DateTime? date;

  factory Holiday.fromJson(Map<String, dynamic> json) => Holiday(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        date: tryParseApiDate(json['date']),
      );
}
