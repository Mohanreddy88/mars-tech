import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/features/leave/data/leave_models.dart';

void main() {
  test('LeaveRequestItem parses my-leave-requests row; only Pending can be cancelled', () {
    final r = LeaveRequestItem.fromJson({
      'id': 4,
      'leaveTypeId': 1,
      'leaveTypeName': 'Annual Leave',
      'leaveTypeCode': 'AL',
      'startDate': '2026-12-01T00:00:00',
      'endDate': '2026-12-03T00:00:00',
      'totalDays': 3,
      'reason': 'Trip',
      'status': 'Pending',
      'requestedOn': '2026-11-20T04:00:00',
      'approvedBy': null,
      'approvedOn': null,
      'approvalRemarks': null,
      'cancelledOn': null,
      'cancellationReason': null,
      'attachmentName': 'mc.pdf',
    });
    expect(r.startDate, DateTime(2026, 12, 1));
    expect(r.endDate, DateTime(2026, 12, 3));
    expect(r.totalDays, 3);
    expect(r.attachmentName, 'mc.pdf');
    expect(r.canCancel, isTrue);

    for (final s in ['Approved', 'Rejected', 'Cancelled']) {
      final other = LeaveRequestItem.fromJson({
        'id': 1,
        'startDate': '2026-12-01T00:00:00',
        'endDate': '2026-12-01T00:00:00',
        'status': s,
      });
      expect(other.canCancel, isFalse, reason: s);
    }
  });

  test('LeaveBalanceItem used fraction is clamped', () {
    final b = LeaveBalanceItem.fromJson({
      'leaveTypeId': 1,
      'leaveTypeName': 'Annual Leave',
      'leaveTypeCode': 'AL',
      'totalDays': 14,
      'usedDays': 3.5,
      'balanceDays': 10.5,
      'carryForwardDays': 0,
    });
    expect(b.usedFraction, closeTo(0.25, 0.0001));
    final over = LeaveBalanceItem.fromJson({
      'leaveTypeId': 2,
      'totalDays': 0,
      'usedDays': 2,
      'balanceDays': 0,
    });
    expect(over.usedFraction, 0);
  });
}
