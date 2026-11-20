import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/admin/audit/data/audit_models.dart';

AuditEntry _entry({String? oldValues, String? newValues}) => AuditEntry.fromJson({
      'id': 1,
      'username': 'admin',
      'action': 'Updated',
      'entityType': 'Employee',
      'entityId': '1',
      'description': 'Updated employee',
      'oldValues': oldValues,
      'newValues': newValues,
      'createdAt': '2026-11-20T04:00:00',
    });

void main() {
  test('changes lists only fields that differ, sorted', () {
    final e = _entry(
      oldValues: '{"Name":"Ali","Salary":4000,"IsActive":true}',
      newValues: '{"Name":"Ali","Salary":4500,"IsActive":false,"Designation":"Engineer"}',
    );
    expect(e.changes, [
      ('Designation', null, 'Engineer'),
      ('IsActive', 'true', 'false'),
      ('Salary', '4000', '4500'),
    ]);
  });

  test('created entry (no old values) lists every new field; bad JSON gives none', () {
    expect(_entry(newValues: '{"Name":"Ali"}').changes, [('Name', null, 'Ali')]);
    expect(_entry(newValues: 'not json').changes, isEmpty);
    expect(_entry().changes, isEmpty);
  });

  test('saved unchanged: no changes, values shown as rows', () {
    final e = _entry(oldValues: '{"Name":"Ali","Salary":12000.0}', newValues: '{"Name":"Ali","Salary":12000.0}');
    expect(e.changes, isEmpty);
    expect(e.savedWithoutChanges, isTrue);
    expect(e.values, [('Name', 'Ali'), ('Salary', '12000.0')]);
    expect(_entry(newValues: '{"Name":"Ali"}').savedWithoutChanges, isFalse);
  });

  test('filter query includes only what is set', () {
    final q = AuditFilter(entityType: 'Payroll', username: ' admin ', from: DateTime(2026, 11, 1))
        .query(2, 30);
    expect(q, {
      'page': 2,
      'pageSize': 30,
      'entityType': 'Payroll',
      'username': 'admin',
      'from': '2026-11-01T00:00:00Z',
    });
    expect(const AuditFilter().isEmpty, isTrue);
    expect(AuditEntry.label('LeaveRequest'), 'Leave request');
  });
}
