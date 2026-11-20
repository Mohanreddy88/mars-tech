import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/admin/master/data/master_models.dart';

void main() {
  test('company settings: legal name and #RRGGBB brand colour required', () {
    final s = CompanySettings.fromJson({'legalName': 'Mars Tech Sdn Bhd', 'brandColor': '#1e40af'});
    expect(s.validate(), isNull);
    expect(s.toJson()['brandColor'], '#1E40AF');
    s.brandColor = 'blue';
    expect(s.validate(), contains('#'));
    s
      ..brandColor = '#123456'
      ..legalName = ' ';
    expect(s.validate(), contains('legal name'));
  });

  test('users: linked employee name and warning', () {
    final u = UserAccount.fromJson({
      'id': 2,
      'username': 'mohanreddys77',
      'email': 'm@x.com',
      'role': 'Employee',
      'isActive': true,
      'employee': {'id': 1, 'name': 'Mohan', 'employeeCode': 'EMP000001', 'isActive': true},
      'warning': null,
    });
    expect(u.employeeName, 'Mohan');
    expect(u.warning, isNull);
  });

  test('rate set bands parse, open-ended last band', () {
    final r = RateSet.fromJson({
      'id': 1,
      'name': '2026',
      'effectiveFrom': '2026-01-01T00:00:00',
      'isCurrent': true,
      'payrollsUsing': 3,
      'epfEmployeeRate': 11,
      'epfEmployerRate': 13,
      'epfEmployerRateAboveThreshold': 12,
      'epfEmployerThreshold': 5000,
      'socsoBands': [
        {'upTo': 30, 'employee': 0.1, 'employer': 0.4},
        {'upTo': null, 'employee': 29.75, 'employer': 104.15},
      ],
      'taxBands': [
        {'upTo': 5000, 'rate': 0},
        {'upTo': null, 'rate': 30},
      ],
    });
    expect(r.socsoBands.last.$1, isNull);
    expect(r.socsoBands.last.$3, 104.15);
    expect(r.taxBands.first, (5000.0, 0.0));
    expect(r.effectiveFrom, DateTime(2026, 1, 1));
  });
}
