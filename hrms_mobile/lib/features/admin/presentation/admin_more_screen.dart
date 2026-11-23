import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/back_to_home.dart';
import '../../../core/widgets/home_tiles.dart';
import '../../auth/application/auth_controller.dart';
import '../../school/data/school_repository.dart';

/// Admin "More" tab: every admin page as icon tiles, grouped (School, Attendance & leave,
/// Reports, Master data), then the account actions (change password, sign out) as a list.
class AdminMoreScreen extends ConsumerWidget {
  const AdminMoreScreen({super.key});

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
        ],
      ),
    );
    if (ok == true) await ref.read(authControllerProvider.notifier).logout();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final me = ref.watch(schoolMeProvider).valueOrNull;
    final school = me != null && me.isStaff;
    final unread = school ? ref.watch(schoolUnreadProvider).valueOrNull?.messages ?? 0 : 0;
    final claims = school ? ref.watch(staffTodayProvider).valueOrNull?.feeClaimsPending ?? 0 : 0;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final username = session?.username ?? '';

    void open(String r) => Routes.open(GoRouter.of(context), r);
    Widget grid(List<HomeTile> tiles) =>
        Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: HomeTileGrid(tiles: tiles));

    return Scaffold(
      appBar: AppBar(leading: const BackToHomeButton(), title: const Text('More')),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(schoolMeProvider);
          ref.invalidate(schoolUnreadProvider);
          ref.invalidate(staffTodayProvider);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
                    child: Text(username.isEmpty ? '?' : username[0].toUpperCase(),
                        style: text.titleLarge?.copyWith(color: scheme.onPrimary)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(username,
                          style: text.titleMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                      Text(
                        [
                          'Administrator',
                          if (school && me.school.name.isNotEmpty) me.school.name,
                        ].join(' · '),
                        style: text.bodySmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85)),
                      ),
                    ]),
                  ),
                ]),
              ),
            ),
            if (school) ...[
              const HomeSectionTitle('School'),
              grid([
                HomeTile('Classes', Icons.class_outlined, TileColors.school, () => open(Routes.schoolClasses)),
                HomeTile('Children', Icons.child_care_outlined, TileColors.today, () => open(Routes.schoolChildren)),
                HomeTile('Parents', Icons.family_restroom_outlined, TileColors.office, () => open(Routes.schoolParents)),
                HomeTile('Attendance', Icons.fact_check_outlined, TileColors.attendance, () => open(Routes.schoolAttendance)),
                HomeTile('Messages', Icons.forum_outlined, TileColors.messages, () => open(Routes.schoolMessages),
                    badge: unread),
                HomeTile('Announce', Icons.campaign_outlined, TileColors.news, () => open(Routes.schoolAnnouncements)),
                HomeTile('Fees', Icons.receipt_long_outlined, TileColors.fees, () => open(Routes.schoolFees), badge: claims),
              ]),
            ],
            const HomeSectionTitle('Attendance & leave'),
            grid([
              HomeTile('Attendance history', Icons.history, TileColors.attendance, () => open(Routes.attendanceHistory)),
              HomeTile('Leave balances', Icons.beach_access_outlined, TileColors.leave, () => open(Routes.leaveBalances)),
              HomeTile('Approvals', Icons.pending_actions_outlined, TileColors.note, () => open(Routes.adminApprovals)),
            ]),
            const HomeSectionTitle('Reports & insights'),
            grid([
              HomeTile('Analytics', Icons.insights_outlined, TileColors.reports, () => open(Routes.analytics)),
              HomeTile('Monthly summary', Icons.calendar_view_month_outlined, TileColors.teacher,
                  () => open(Routes.monthlySummary)),
              HomeTile('Payroll report', Icons.request_quote_outlined, TileColors.payroll, () => open(Routes.payrollReport)),
              HomeTile('Attendance report', Icons.fact_check_outlined, TileColors.attendance,
                  () => open(Routes.attendanceReport)),
              HomeTile('Directory', Icons.contacts_outlined, TileColors.people, () => open(Routes.directoryReport)),
              HomeTile('Audit log', Icons.manage_search, TileColors.settings, () => open(Routes.auditLog)),
            ]),
            const HomeSectionTitle('Master data'),
            grid([
              HomeTile('Company settings', Icons.business_outlined, TileColors.school, () => open(Routes.companySettings)),
              HomeTile('Departments', Icons.apartment_outlined, TileColors.people, () => open(Routes.departmentsMaster)),
              HomeTile('Users', Icons.manage_accounts_outlined, TileColors.office, () => open(Routes.usersMaster)),
              HomeTile('Public holidays', Icons.celebration_outlined, TileColors.today, () => open(Routes.holidaysMaster)),
              HomeTile('Banks', Icons.account_balance_outlined, TileColors.fees, () => open(Routes.banksMaster)),
              HomeTile('Statutory rates', Icons.percent, TileColors.payroll, () => open(Routes.statutoryRates)),
              HomeTile('Chatbot', Icons.smart_toy_outlined, TileColors.help, () => open(Routes.chatbotAdmin)),
            ]),
            const HomeSectionTitle('Account'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Card(
                child: Column(children: [
                  ListTile(
                    leading: Icon(Icons.lock_reset_outlined, color: scheme.primary),
                    title: const Text('Change password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.changePassword),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.logout, color: scheme.error),
                    title: Text('Sign out', style: TextStyle(color: scheme.error)),
                    onTap: () => _signOut(context, ref),
                  ),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
