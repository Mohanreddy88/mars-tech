import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/admin/payroll/data/payroll_admin_models.dart';

void main() {
  test('PayMonth steps across year boundaries', () {
    expect(const PayMonth(2026, 1).previous, const PayMonth(2025, 12));
    expect(const PayMonth(2026, 12).next, const PayMonth(2027, 1));
    expect(const PayMonth(2026, 11).label, 'November 2026');
  });

  test('status rules match the API', () {
    expect(PayrollStatus.canApprove('Draft'), isTrue);
    expect(PayrollStatus.canApprove('Rejected'), isTrue);
    expect(PayrollStatus.canApprove('Approved'), isFalse);
    expect(PayrollStatus.canProcess('Approved'), isTrue);
    expect(PayrollStatus.canProcess('Draft'), isFalse);
    expect(PayrollStatus.canReject('Processed'), isFalse);
    expect(PayrollStatus.canEdit('Processed'), isFalse);
    expect(PayrollStatus.canEdit('Approved'), isTrue);
  });

  test('PayrollRecord parses /api/payroll/{id} with adjustments and leave', () {
    final p = PayrollRecord.fromJson({
      'id': 3,
      'employeeId': 1,
      'employeeCode': 'EMP000001',
      'employeeName': 'Mohan',
      'month': 11,
      'year': 2026,
      'monthYear': 'November 2026',
      'basicSalary': 12000,
      'allowances': 0,
      'deductions': 0,
      'epfAmount': 240,
      'socsoAmount': 19.75,
      'eisAmount': 0,
      'taxAmount': 1534.07,
      'epfEmployerAmount': 240,
      'socsoEmployerAmount': 87.5,
      'eisEmployerAmount': 0,
      'epfEmployeeRate': 2,
      'grossIncome': 12000,
      'netSalary': 10206.18,
      'status': 'Draft',
      'attendanceHours': 168,
      'expectedHours': 168,
      'generatedOn': '2026-11-20T04:11:00',
      'adjustments': [
        {'id': 9, 'adjustmentType': 'Bonus', 'description': 'Q4', 'amount': 500, 'createdBy': 'admin'},
      ],
      'leaveRequests': [
        {'leaveTypeCode': 'AL', 'startDate': '2026-11-03T00:00:00', 'endDate': '2026-11-04T00:00:00', 'leaveDays': 2, 'isPaid': true},
      ],
    });
    expect(p.totalDeductions, closeTo(1793.82, 0.001));
    expect(p.grossIncome - p.totalDeductions, closeTo(p.netSalary, 0.001));
    expect(p.employerContributions, 327.5);
    expect(p.adjustments.single.type, 'Bonus');
    expect(p.adjustments.single.isDeduction, isFalse);
    expect(p.leaveLines.single, contains('2 days (paid)'));
  });

  test('bulk result and eligibility parse', () {
    final r = BulkGenerateResult.fromJson({
      'successCount': 2,
      'failureCount': 1,
      'errors': [
        {'employeeId': 4, 'employeeName': 'Ali', 'errorMessage': 'No approved attendance'},
      ],
    });
    expect(r.errors.single, ('Ali', 'No approved attendance'));

    final e = PayrollEligibility.fromJson({
      'isEligible': false,
      'errors': ['No attendance records found for this month.'],
      'warnings': [],
    });
    expect(e.isEligible, isFalse);
    expect(e.errors.single, startsWith('No attendance'));
  });
}
