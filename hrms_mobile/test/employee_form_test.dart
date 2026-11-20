import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/admin/data/admin_models.dart';

EmployeeDraft _valid() => EmployeeDraft()
  ..name = 'Ali Bin Abu'
  ..email = 'ali@example.com'
  ..phone = '123456789'
  ..idType = EmployeeDraft.idNric
  ..idNumber = '900101-14-5678'
  ..dateOfBirth = DateTime(1990, 1, 1)
  ..joinDate = DateTime(2024, 3, 1)
  ..salary = 4500;

void main() {
  final today = DateTime(2026, 11, 20);

  test('a complete form is valid and sends cleaned values', () {
    final d = _valid();
    expect(d.validate(today: today), isNull);
    final json = d.toJson();
    expect(json['icPassport'], '900101145678'); // dashes removed, as the API does
    expect(json['idCountry'], 'Malaysia');
    expect(json['phoneCountryCode'], '+60');
    expect(json['dateOfBirth'], '1990-01-01T00:00:00Z');
    expect(json['joinDate'], '2024-03-01T00:00:00Z');
    expect(json['isActive'], isTrue);
  });

  test('same rules as the API (EmployeeIdentity)', () {
    expect((_valid()..idNumber = '12345').validate(today: today), contains('12 digits'));
    expect((_valid()..phone = '12345').validate(today: today), contains('7–12 digits'));
    expect((_valid()..email = 'not-an-email').validate(today: today), contains('email'));
    expect((_valid()..dateOfBirth = DateTime(2015, 1, 1)).validate(today: today), contains('15 years'));
    expect((_valid()..dateOfBirth = DateTime(2027, 1, 1)).validate(today: today), contains('future'));
    expect((_valid()..salary = 0).validate(today: today), contains('salary'));
    expect((_valid()..epfEmployeeRateOverride = 120).validate(today: today), contains('EPF'));
  });

  test('passport needs 8-10 letters/digits and a country; stored in capitals', () {
    final d = _valid()
      ..idType = EmployeeDraft.idPassport
      ..idNumber = 'a1234567';
    expect(d.validate(today: today), contains('country'));
    d.idCountry = 'India';
    expect(d.validate(today: today), isNull);
    expect(d.toJson()['icPassport'], 'A1234567');
    expect(d.toJson()['idCountry'], 'India');
  });

  test('editing keeps the existing values', () {
    final e = EmployeeSummary.fromJson({
      'id': 7,
      'name': 'Siti',
      'email': 's@x.com',
      'isActive': true,
      'phone': '198765432',
      'phoneCountryCode': '+65',
      'idType': 'Passport',
      'icPassport': 'K1234567',
      'idCountry': 'Singapore',
      'departmentId': 2,
      'bankId': 3,
      'salary': 6000,
      'joinDate': '2023-05-01T00:00:00',
      'dateOfBirth': '1992-02-02T00:00:00',
      'epfEmployeeRateOverride': 11,
    });
    final d = EmployeeDraft.from(e);
    expect(d.validate(today: today), isNull);
    expect(d.phoneCountryCode, '+65');
    expect(d.idType, EmployeeDraft.idPassport);
    expect(d.departmentId, 2);
    expect(d.epfEmployeeRateOverride, 11);
    expect((d..isActive = false).toJson()['isActive'], isFalse);
  });

  test('leave balance: new balance = entitlement + carried - used', () {
    final r = LeaveBalanceRow.fromJson({
      'id': 1,
      'employeeId': 1,
      'employeeName': 'A',
      'leaveTypeName': 'Annual Leave',
      'leaveTypeCode': 'AL',
      'totalDays': 12,
      'usedDays': 3,
      'balanceDays': 9,
      'carryForwardDays': 0,
    });
    expect(r.balanceFor(14, 2), 13);
  });
}
