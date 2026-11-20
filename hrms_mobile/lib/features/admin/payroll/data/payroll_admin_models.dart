import 'package:intl/intl.dart';

import '../../../../core/utils/formatters.dart';

/// A payroll month.
class PayMonth {
  const PayMonth(this.year, this.month);

  factory PayMonth.now() {
    final n = DateTime.now();
    return PayMonth(n.year, n.month);
  }

  final int year;
  final int month;

  PayMonth get previous => month == 1 ? PayMonth(year - 1, 12) : PayMonth(year, month - 1);
  PayMonth get next => month == 12 ? PayMonth(year + 1, 1) : PayMonth(year, month + 1);
  String get label => DateFormat('MMMM yyyy').format(DateTime(year, month));

  @override
  bool operator ==(Object other) =>
      other is PayMonth && other.year == year && other.month == month;

  @override
  int get hashCode => Object.hash(year, month);
}

/// Payroll workflow: Draft -> Approved -> Processed (paid). Rejected can be
/// approved again after correcting. (Same rules as the API.)
class PayrollStatus {
  PayrollStatus._();

  static bool canApprove(String s) => s != 'Approved' && s != 'Processed';
  static bool canReject(String s) => s != 'Processed' && s != 'Rejected';
  static bool canProcess(String s) => s == 'Approved';
  static bool canEdit(String s) => s != 'Processed'; // adjustments, delete
}

/// GET /api/payroll (list) and /api/payroll/{id} (detail adds the lists).
class PayrollRecord {
  const PayrollRecord({
    required this.id,
    required this.employeeId,
    required this.employeeName,
    required this.month,
    required this.year,
    required this.monthYear,
    required this.basicSalary,
    required this.allowances,
    required this.otherDeductions,
    required this.epf,
    required this.socso,
    required this.eis,
    required this.tax,
    required this.epfEmployer,
    required this.socsoEmployer,
    required this.eisEmployer,
    required this.grossIncome,
    required this.netSalary,
    required this.status,
    this.employeeCode,
    this.epfEmployeeRate,
    this.epfEmployerRate,
    this.statutoryRateSetName,
    this.attendanceHours,
    this.expectedHours,
    this.paidLeaveDays,
    this.unpaidLeaveDays,
    this.generatedOn,
    this.approverName,
    this.approvedOn,
    this.processorName,
    this.processedOn,
    this.remarks,
    this.isProrated = false,
    this.proratedDays,
    this.totalMonthDays,
    this.adjustments = const [],
    this.leaveLines = const [],
  });

  final int id;
  final int employeeId;
  final String employeeName;
  final String? employeeCode;
  final int month;
  final int year;
  final String monthYear;
  final double basicSalary;
  final double allowances;
  final double otherDeductions;
  final double epf;
  final double socso;
  final double eis;
  final double tax;
  final double epfEmployer;
  final double socsoEmployer;
  final double eisEmployer;
  final double grossIncome;
  final double netSalary;
  final String status;
  final double? epfEmployeeRate;
  final double? epfEmployerRate;
  final String? statutoryRateSetName;
  final double? attendanceHours;
  final double? expectedHours;
  final int? paidLeaveDays;
  final int? unpaidLeaveDays;
  final DateTime? generatedOn;
  final String? approverName;
  final DateTime? approvedOn;
  final String? processorName;
  final DateTime? processedOn;
  final String? remarks;
  final bool isProrated;
  final int? proratedDays;
  final int? totalMonthDays;
  final List<PayrollAdjustmentItem> adjustments;

  /// Leave counted in this payroll, e.g. "AL 03 Nov – 04 Nov · 2 days (paid)".
  final List<String> leaveLines;

  double get totalDeductions => epf + socso + eis + tax + otherDeductions;
  double get employerContributions => epfEmployer + socsoEmployer + eisEmployer;

  static double? _d(Object? v) => (v as num?)?.toDouble();

  factory PayrollRecord.fromJson(Map<String, dynamic> j) => PayrollRecord(
        id: j['id'] as int,
        employeeId: j['employeeId'] as int? ?? 0,
        employeeName: j['employeeName'] as String? ?? '',
        employeeCode: j['employeeCode'] as String?,
        month: j['month'] as int? ?? 1,
        year: j['year'] as int? ?? 2000,
        monthYear: j['monthYear'] as String? ?? '',
        basicSalary: toDouble(j['basicSalary']),
        allowances: toDouble(j['allowances']),
        otherDeductions: toDouble(j['deductions']),
        epf: toDouble(j['epfAmount']),
        socso: toDouble(j['socsoAmount']),
        eis: toDouble(j['eisAmount']),
        tax: toDouble(j['taxAmount']),
        epfEmployer: toDouble(j['epfEmployerAmount']),
        socsoEmployer: toDouble(j['socsoEmployerAmount']),
        eisEmployer: toDouble(j['eisEmployerAmount']),
        grossIncome: toDouble(j['grossIncome']),
        netSalary: toDouble(j['netSalary']),
        status: j['status'] as String? ?? '',
        epfEmployeeRate: _d(j['epfEmployeeRate']),
        epfEmployerRate: _d(j['epfEmployerRate']),
        statutoryRateSetName: j['statutoryRateSetName'] as String?,
        attendanceHours: _d(j['attendanceHours']),
        expectedHours: _d(j['expectedHours']),
        paidLeaveDays: (j['paidLeaveDays'] as num?)?.toInt(),
        unpaidLeaveDays: (j['unpaidLeaveDays'] as num?)?.toInt(),
        generatedOn: tryParseApiDate(j['generatedOn']),
        approverName: j['approverName'] as String?,
        approvedOn: tryParseApiDate(j['approvedOn']),
        processorName: j['processorName'] as String?,
        processedOn: tryParseApiDate(j['processedOn']),
        remarks: j['remarks'] as String?,
        isProrated: j['isProrated'] as bool? ?? false,
        proratedDays: (j['proratedDays'] as num?)?.toInt(),
        totalMonthDays: (j['totalMonthDays'] as num?)?.toInt(),
        adjustments: ((j['adjustments'] as List?) ?? const [])
            .map((a) => PayrollAdjustmentItem.fromJson(a as Map<String, dynamic>))
            .toList(),
        leaveLines: [
          for (final l in ((j['leaveRequests'] as List?) ?? const []).cast<Map<String, dynamic>>())
            '${l['leaveTypeCode'] ?? l['leaveType'] ?? ''}  '
                '${Fmt.shortDate(tryCalendarDate(l['startDate']))} – ${Fmt.shortDate(tryCalendarDate(l['endDate']))}'
                ' · ${Fmt.days(toDouble(l['leaveDays']))} (${l['isPaid'] == true ? 'paid' : 'unpaid'})'
        ],
      );
}

class PayrollAdjustmentItem {
  const PayrollAdjustmentItem({
    required this.id,
    required this.type,
    required this.description,
    required this.amount,
    this.createdBy,
  });

  /// Allowance, Bonus, Overtime (added to pay) or Deduction.
  final String type;
  final int id;
  final String description;
  final double amount;
  final String? createdBy;

  static const types = ['Allowance', 'Bonus', 'Overtime', 'Deduction'];
  bool get isDeduction => type == 'Deduction';

  factory PayrollAdjustmentItem.fromJson(Map<String, dynamic> j) => PayrollAdjustmentItem(
        id: j['id'] as int,
        type: j['adjustmentType'] as String? ?? '',
        description: j['description'] as String? ?? '',
        amount: toDouble(j['amount']),
        createdBy: j['createdBy'] as String?,
      );
}

/// GET /api/payroll/eligibility/{employeeId}/{month}/{year}
class PayrollEligibility {
  const PayrollEligibility({
    required this.isEligible,
    required this.errors,
    required this.warnings,
  });

  final bool isEligible;
  final List<String> errors;
  final List<String> warnings;

  factory PayrollEligibility.fromJson(Map<String, dynamic> j) => PayrollEligibility(
        isEligible: j['isEligible'] as bool? ?? false,
        errors: ((j['errors'] as List?) ?? const []).map((e) => '$e').toList(),
        warnings: ((j['warnings'] as List?) ?? const []).map((e) => '$e').toList(),
      );
}

/// POST /api/payroll/generate-bulk result.
class BulkGenerateResult {
  const BulkGenerateResult({
    required this.successCount,
    required this.failureCount,
    required this.errors,
  });

  final int successCount;
  final int failureCount;

  /// (employee name, message)
  final List<(String, String)> errors;

  factory BulkGenerateResult.fromJson(Map<String, dynamic> j) => BulkGenerateResult(
        successCount: (j['successCount'] as num?)?.toInt() ?? 0,
        failureCount: (j['failureCount'] as num?)?.toInt() ?? 0,
        errors: [
          for (final e in ((j['errors'] as List?) ?? const []).cast<Map<String, dynamic>>())
            (e['employeeName'] as String? ?? '', e['errorMessage'] as String? ?? '')
        ],
      );
}

/// One employee in GET /api/payroll/year-end-summary/{year}
class YearEndEmployee {
  const YearEndEmployee({
    required this.employeeId,
    required this.employeeName,
    required this.monthsProcessed,
    required this.ytdGross,
    required this.ytdEpf,
    required this.ytdSocso,
    required this.ytdEis,
    required this.ytdTax,
    required this.ytdNet,
    required this.isEaReady,
    required this.hasEmail,
    this.employeeCode,
    this.departmentName,
    this.notReadyReason,
  });

  final int employeeId;
  final String employeeName;
  final String? employeeCode;
  final String? departmentName;
  final int monthsProcessed;
  final double ytdGross;
  final double ytdEpf;
  final double ytdSocso;
  final double ytdEis;
  final double ytdTax;
  final double ytdNet;
  final bool isEaReady;
  final bool hasEmail;
  final String? notReadyReason;

  factory YearEndEmployee.fromJson(Map<String, dynamic> j) => YearEndEmployee(
        employeeId: j['employeeId'] as int,
        employeeName: j['employeeName'] as String? ?? '',
        employeeCode: j['employeeCode'] as String?,
        departmentName: j['departmentName'] as String?,
        monthsProcessed: (j['monthsProcessed'] as num?)?.toInt() ?? 0,
        ytdGross: toDouble(j['ytdGross']),
        ytdEpf: toDouble(j['ytdEpf']),
        ytdSocso: toDouble(j['ytdSocso']),
        ytdEis: toDouble(j['ytdEis']),
        ytdTax: toDouble(j['ytdTax']),
        ytdNet: toDouble(j['ytdNet']),
        isEaReady: j['isEaReady'] as bool? ?? false,
        hasEmail: j['hasEmail'] as bool? ?? false,
        notReadyReason: j['notReadyReason'] as String?,
      );
}
