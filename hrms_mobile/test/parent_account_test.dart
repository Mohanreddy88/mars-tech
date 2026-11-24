import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/router/app_router.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';
import 'package:hrms_mobile/features/school/data/parent_account.dart';

void main() {
  test('the Account page reads the parent, children, contacts and pick-up people', () {
    final a = ParentAccount.fromJson({
      'parent': {'id': 1, 'fullName': 'Mounika', 'email': 'm@home.test', 'phone': '+60123456789', 'relationship': 'Mother'},
      'children': [
        {
          'id': 7, 'fullName': 'Rudvik Reddy', 'sessionType': 'Full day', 'className': 'K1', 'dateOfBirth': '2021-05-04T00:00:00',
          'contacts': [
            {'id': 1, 'fullName': 'Mounika', 'relationship': 'Mother', 'isMe': true},
            {'id': 2, 'fullName': 'Mohan', 'relationship': 'Father', 'phone': '+60198765432', 'isMe': false},
          ],
          'pickupPeople': [
            {'id': 5, 'studentId': 7, 'fullName': 'Grandma', 'relationship': 'Grandmother', 'status': 'Pending'},
            {'id': 6, 'studentId': 7, 'fullName': 'Driver', 'relationship': 'Driver', 'status': 'Rejected', 'rejectReason': 'Bring IC'},
          ],
        },
      ],
    });
    expect(a.fullName, 'Mounika');
    final c = a.children.single;
    expect(c.dateOfBirth, '2021-05-04');
    expect(c.contacts.map((x) => x.fullName), ['Mounika', 'Mohan']);
    expect(c.contacts.first.isMe, isTrue);
    expect(c.pickupPeople.first.pending, isTrue);
    expect(c.pickupPeople.last.rejected, isTrue);
    expect(c.pickupPeople.last.rejectReason, 'Bring IC');
  });

  test('pick-up notifications open the right page', () {
    Session s(String role) => Session(token: 't', username: 'u', role: role, expiresAt: DateTime.utc(2099));
    expect(Routes.fromWebLink(s('Admin'), '/school/pickup-people'), Routes.schoolPickupPeople);
    expect(Routes.fromWebLink(s('Parent'), '/parent/account'), Routes.parentAccount);
    expect(Routes.isWrongArea(s('Parent'), Routes.schoolPickupPeople), isTrue);
  });
}
