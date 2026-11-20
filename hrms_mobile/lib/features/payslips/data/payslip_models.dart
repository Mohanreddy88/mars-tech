import '../../../core/utils/formatters.dart';

/// One row of GET /api/selfservice/my-payslips.
class Payslip {
  const Payslip({
    required this.id,
    required this.month,
    required this.year,
    required this.monthName,
    required this.basicSalary,
    required this.allowances,
    required this.otherDeductions,
    required this.epf,
    required this.socso,
    required this.eis,
    required this.tax,
    required this.grossIncome,
    required this.netSalary,
    this.epfEmployeeRate,
    this.generatedOn,
  });

  final int id;
  final int month;
  final int year;

  /// e.g. "November 2026"
  final String monthName;
  final double basicSalary;
  final double allowances;

  /// Unpaid leave and manual deductions (API field `deductions`).
  final double otherDeductions;
  final double epf;
  final double socso;
  final double eis;

  /// PCB / MTD
  final double tax;
  final double grossIncome;
  final double netSalary;
  final double? epfEmployeeRate;
  final DateTime? generatedOn;

  /// Everything taken off gross pay, as on the web payslip.
  double get totalDeductions => epf + socso + eis + tax + otherDeductions;

  factory Payslip.fromJson(Map<String, dynamic> json) => Payslip(
        id: json['id'] as int,
        month: json['month'] as int,
        year: json['year'] as int,
        monthName: json['monthName'] as String? ?? '',
        basicSalary: toDouble(json['basicSalary']),
        allowances: toDouble(json['allowances']),
        otherDeductions: toDouble(json['deductions']),
        epf: toDouble(json['epfAmount']),
        socso: toDouble(json['socsoAmount']),
        eis: toDouble(json['eisAmount']),
        tax: toDouble(json['taxAmount']),
        grossIncome: toDouble(json['grossIncome']),
        netSalary: toDouble(json['netSalary']),
        epfEmployeeRate: (json['epfEmployeeRate'] as num?)?.toDouble(),
        generatedOn: tryParseApiDate(json['generatedOn']),
      );
}

/// GET /api/selfservice/my-payslips/{id}: the list fields plus status,
/// approval and employer contributions.
class PayslipDetail extends Payslip {
  const PayslipDetail({
    required super.id,
    required super.month,
    required super.year,
    required super.monthName,
    required super.basicSalary,
    required super.allowances,
    required super.otherDeductions,
    required super.epf,
    required super.socso,
    required super.eis,
    required super.tax,
    required super.grossIncome,
    required super.netSalary,
    super.epfEmployeeRate,
    super.generatedOn,
    required this.status,
    required this.epfEmployer,
    required this.socsoEmployer,
    required this.eisEmployer,
    this.approverName,
    this.approvedOn,
  });

  final String status;
  final double epfEmployer;
  final double socsoEmployer;
  final double eisEmployer;
  final String? approverName;
  final DateTime? approvedOn;

  double get totalEmployerContributions =>
      epfEmployer + socsoEmployer + eisEmployer;

  factory PayslipDetail.fromJson(Map<String, dynamic> json) {
    final base = Payslip.fromJson(json);
    return PayslipDetail(
      id: base.id,
      month: base.month,
      year: base.year,
      monthName: base.monthName,
      basicSalary: base.basicSalary,
      allowances: base.allowances,
      otherDeductions: base.otherDeductions,
      epf: base.epf,
      socso: base.socso,
      eis: base.eis,
      tax: base.tax,
      grossIncome: base.grossIncome,
      netSalary: base.netSalary,
      epfEmployeeRate: base.epfEmployeeRate,
      generatedOn: base.generatedOn,
      status: json['status'] as String? ?? '',
      epfEmployer: toDouble(json['epfEmployerAmount']),
      socsoEmployer: toDouble(json['socsoEmployerAmount']),
      eisEmployer: toDouble(json['eisEmployerAmount']),
      approverName: json['approverName'] as String?,
      approvedOn: tryParseApiDate(json['approvedOn']),
    );
  }
}

/// A downloaded payslip PDF.
class PayslipPdf {
  const PayslipPdf({required this.bytes, required this.fileName});

  final List<int> bytes;
  final String fileName;
}
