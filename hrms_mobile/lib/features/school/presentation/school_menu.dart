import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../data/school_repository.dart';

/// "School" block for staff: on the employee Home (class teachers) and the admin More tab.
/// Hidden when the company has no school features or the user has no school role.
class SchoolMenuCard extends ConsumerWidget {
  const SchoolMenuCard({super.key, this.heading});

  /// Optional heading widget shown above the card (the admin More tab's style).
  final Widget? heading;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(schoolMeProvider).valueOrNull;
    if (me == null || !me.isStaff) return const SizedBox.shrink();
    final unread = ref.watch(schoolUnreadProvider).valueOrNull?.messages ?? 0;
    final scheme = Theme.of(context).colorScheme;

    Widget item(IconData icon, String title, String subtitle, String route, {int badge = 0}) => ListTile(
          leading: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: [
            if (badge > 0) Badge(label: Text('$badge')),
            const Icon(Icons.chevron_right),
          ]),
          onTap: () async {
            await context.push(route);
            ref.invalidate(schoolUnreadProvider);
          },
        );

    final items = <Widget>[
      if (me.isAdmin) ...[
        item(Icons.class_outlined, 'Classes', 'Classes and class teachers', Routes.schoolClasses),
        item(Icons.child_care_outlined, 'Children', 'Class, session, health notes, parents', Routes.schoolChildren),
        item(Icons.family_restroom_outlined, 'Parents', 'Parents, their children and logins', Routes.schoolParents),
      ],
      if (me.isTeacher && !me.isAdmin)
        item(Icons.groups_outlined, 'My Class', 'Children, medical notes, parents\' phones', Routes.schoolMyClass),
      item(Icons.fact_check_outlined, 'Attendance & reports', 'Check in / out, absences, daily reports', Routes.schoolAttendance),
      item(Icons.chat_bubble_outline, 'Messages', 'Parents of your ${me.isAdmin ? 'school' : 'class'}', Routes.schoolMessages,
          badge: unread),
      item(Icons.campaign_outlined, 'Announcements', 'Notices to parents', Routes.schoolAnnouncements),
      if (me.isAdmin) item(Icons.payments_outlined, 'Fees', 'Invoices, to confirm, fee items, settings', Routes.schoolFees),
    ];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (heading != null) heading!,
      Card(
        child: Column(children: [
          for (var i = 0; i < items.length; i++) ...[
            if (i > 0) const Divider(height: 1),
            items[i],
          ],
        ]),
      ),
    ]);
  }
}
