import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/router/app_router.dart';
import 'package:hrms_mobile/features/admin/presentation/highlights_carousel.dart';

void main() {
  test('highlight cards read from the API and open the right screen', () {
    final c = HighlightCard.fromJson({
      'key': 'leave', 'group': 'hr', 'icon': 'leave', 'tone': 'warn',
      'title': '3 leave requests waiting', 'text': 'Approve or reject them.', 'page': 'approvals', 'action': 'Review',
    });
    expect(c.title, '3 leave requests waiting');
    expect(highlightRoute(c.page), Routes.adminApprovals);
    expect(highlightRoute('approvals-attendance'), '${Routes.adminApprovals}?tab=attendance');
    expect(highlightRoute('pickup-people'), Routes.schoolPickupPeople);
    expect(highlightRoute(null), isNull, reason: '"All caught up" opens nothing');
  });
}
