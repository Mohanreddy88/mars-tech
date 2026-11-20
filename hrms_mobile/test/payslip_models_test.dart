import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/payslips/data/payslip_models.dart';

void main() {
  // Shape of GET /api/selfservice/my-payslips/{id} (SelfServiceController).
  final json = <String, dynamic>{
    'id': 7,
    'month': 10,
    'year': 2026,
    'monthName': 'October 2026',
    'basicSalary': 5000,
    'allowances': 500.5,
    'deductions': 120,
    'epfAmount': 605.06,
    'socsoAmount': 29.75,
    'eisAmount': 11.9,
    'taxAmount': 150,
    'epfEmployeeRate': 11,
    'epfEmployerAmount': 715.07,
    'socsoEmployerAmount': 104.15,
    'eisEmployerAmount': 11.9,
    'grossIncome': 5500.5,
    'netSalary': 4583.79,
    'status': 'Approved',
    'generatedOn': '2026-10-31T08:00:00',
    'approverName': 'admin',
    'approvedOn': null,
  };

  test('PayslipDetail parses the API response', () {
    final p = PayslipDetail.fromJson(json);
    expect(p.id, 7);
    expect(p.monthName, 'October 2026');
    expect(p.allowances, 500.5);
    expect(p.otherDeductions, 120);
    expect(p.status, 'Approved');
    expect(p.generatedOn, DateTime.utc(2026, 10, 31, 8));
    expect(p.approvedOn, isNull);
  });

  test('total deductions = statutory + other, and gross - deductions = net', () {
    final p = PayslipDetail.fromJson(json);
    expect(p.totalDeductions, closeTo(605.06 + 29.75 + 11.9 + 150 + 120, 0.001));
    expect(p.grossIncome - p.totalDeductions, closeTo(p.netSalary, 0.001));
    expect(p.totalEmployerContributions, closeTo(831.12, 0.001));
  });

  test('list row parses without the detail-only fields', () {
    final row = Map<String, dynamic>.from(json)
      ..remove('status')
      ..remove('epfEmployerAmount');
    final p = Payslip.fromJson(row);
    expect(p.netSalary, 4583.79);
    expect(p.eis, 11.9);
  });
}
