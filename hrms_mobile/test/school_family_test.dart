import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/router/app_router.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';
import 'package:hrms_mobile/features/school/data/school_admin.dart';
import 'package:hrms_mobile/features/school/presentation/child_day_screen.dart';

void main() {
  group('families', () {
    test('a family reads its mother, father and children', () {
      final f = FamilyRecord.fromJson({
        'mother': {'id': 1, 'fullName': 'Mounika', 'phone': '+60123456789', 'hasLogin': true},
        'father': {'id': 2, 'fullName': 'Mohan', 'phone': null, 'hasLogin': false},
        'children': [
          {'id': 7, 'fullName': 'Rudvik Reddy', 'className': 'K1', 'isActive': true, 'guardians': [{'id': 4, 'fullName': 'Gran'}]},
        ],
      });
      expect(f.mother!.fullName, 'Mounika');
      expect(f.mother!.hasLogin, isTrue);
      expect(f.father!.id, 2);
      expect(f.children.single.fullName, 'Rudvik Reddy');
      expect(f.children.single.guardians, ['Gran']);
    });

    test('a single-mother family is complete; a missing father nobody confirmed is not', () {
      final single = FamilyRecord.fromJson({
        'mother': {'id': 1, 'fullName': 'Mounika'}, 'father': null, 'noFather': true,
        'children': [{'id': 9, 'fullName': 'Arjun'}],
      });
      expect(single.noFather, isTrue);
      expect(single.incomplete, isFalse);

      final gap = FamilyRecord.fromJson({'mother': {'id': 1, 'fullName': 'Mounika'}, 'father': null, 'children': []});
      expect(gap.incomplete, isTrue);

      final c = ChildRecord.fromJson({'id': 9, 'fullName': 'Arjun', 'noFatherOnRecord': true});
      expect(c.noFatherOnRecord, isTrue);
      expect(c.noMotherOnRecord, isFalse);
    });

    test('children with no parents linked have no mother or father', () {
      final f = FamilyRecord.fromJson({'mother': null, 'father': null, 'children': [{'id': 9, 'fullName': 'Arjun'}]});
      expect(f.mother, isNull);
      expect(f.father, isNull);
      expect(f.children.single.isActive, isTrue);
    });

    test('a child knows its mother, father and siblings', () {
      final c = ChildRecord.fromJson({
        'id': 7, 'fullName': 'Rudvik Reddy', 'sessionType': 'Full day', 'isActive': true,
        'parents': [
          {'id': 1, 'fullName': 'Mounika', 'relationship': 'Mother'},
          {'id': 2, 'fullName': 'Mohan', 'relationship': 'Father'},
        ],
        'siblings': [
          {'id': 9, 'fullName': 'Arjun', 'via': 'Same mother', 'isActive': true},
        ],
      });
      expect(c.mother!.fullName, 'Mounika');
      expect(c.father!.fullName, 'Mohan');
      expect(c.siblings.single.via, 'Same mother');
    });

    test('a parent shows each child with the other parent', () {
      final p = ParentRecord.fromJson({
        'id': 1, 'fullName': 'Mounika', 'relationship': 'Mother',
        'children': [
          {'id': 7, 'fullName': 'Rudvik Reddy', 'otherParents': [{'id': 2, 'fullName': 'Mohan', 'relationship': 'Father'}]},
          {'id': 9, 'fullName': 'Arjun', 'otherParents': [{'id': 3, 'fullName': 'Narsi', 'relationship': 'Father'}]},
        ],
      });
      expect(p.children.map((c) => c.others.single), ['Mohan (Father)', 'Narsi (Father)']);
    });
  });

  group('parent home tiles', () {
    test('each tile opens its own part of the child page', () {
      expect(ChildDayView.parse('report'), ChildDayView.report);
      expect(ChildDayView.parse('attendance'), ChildDayView.attendance);
      expect(ChildDayView.parse('notes'), ChildDayView.notes);
      expect(ChildDayView.parse(null), ChildDayView.today);
      expect(ChildDayView.parse('nonsense'), ChildDayView.today);
    });

    test('Families is an admin-only page', () {
      final parent = Session(token: 't', username: 'u', role: 'Parent', expiresAt: DateTime.utc(2099));
      final employee = Session(token: 't', username: 'u', role: 'Employee', expiresAt: DateTime.utc(2099));
      expect(Routes.isWrongArea(parent, Routes.schoolFamilies), isTrue);
      expect(Routes.isWrongArea(employee, Routes.schoolFamilies), isTrue);
    });
  });
}
