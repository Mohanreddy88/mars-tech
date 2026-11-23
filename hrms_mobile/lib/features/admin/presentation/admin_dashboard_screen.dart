import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/home_tiles.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/data/notification_repository.dart';
import '../../assistant/presentation/assistant_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../school/data/parent_account.dart';
import '../../school/data/school_repository.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin home: headcount, pending approvals, this month's payroll,
/// departments and recent activity.
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(adminDashboardProvider);
    final username = ref.watch(authControllerProvider)?.username ?? '';
    final me = ref.watch(schoolMeProvider).valueOrNull;
    final school = me != null && me.isStaff;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: const [AssistantButton(), NotificationBell()],
      ),
      body: dashboard.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(adminDashboardProvider)),
        data: (d) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(unreadCountProvider);
            ref.invalidate(schoolUnreadProvider);
            ref.invalidate(staffTodayProvider);
            return ref.refresh(adminDashboardProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(bottom: 24),
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: _Header(username: username, d: d, schoolName: school ? me.school.name : null),
              ),
              _NeedsYou(d: d, school: school),
              const Divider(height: 1),
              if (school) ...[
                const HomeSectionTitle('School'),
                const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: _SchoolTiles()),
              ],
              const HomeSectionTitle('HR & payroll'),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 8), child: _HrTiles(d: d)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _Section('Payroll — ${DateFormat('MMMM yyyy').format(DateTime.now())}'),
              Card(
                child: d.payrollByStatus.isEmpty
                    ? const ListTile(
                        leading: Icon(Icons.receipt_long_outlined),
                        title: Text('No payroll generated this month yet'),
                      )
                    : Column(
                        children: [
                          ListTile(
                            leading: const Icon(Icons.payments_outlined),
                            title: Text(Fmt.money(d.currentMonthPayrollAmount),
                                style: const TextStyle(fontWeight: FontWeight.w700)),
                            subtitle: Text('${d.currentMonthPayrolls} payslips (net total)'),
                          ),
                          const Divider(height: 1),
                          for (final (status, count, total) in d.payrollByStatus)
                            ListTile(
                              dense: true,
                              title: Row(children: [StatusChip(status)]),
                              subtitle: Text('$count ${count == 1 ? 'payslip' : 'payslips'}'),
                              trailing: Text(Fmt.money(total)),
                            ),
                        ],
                      ),
              ),
              if (d.departments.isNotEmpty) ...[
                _Section('Departments (${d.totalDepartments})'),
                Card(
                  child: Column(
                    children: [
                      for (final (name, count) in d.departments)
                        ListTile(
                          dense: true,
                          leading: const Icon(Icons.apartment_outlined),
                          title: Text(name),
                          trailing: Text('$count'),
                        ),
                    ],
                  ),
                ),
              ],
              if (d.recentActivities.isNotEmpty) ...[
                const _Section('Recent activity'),
                Card(
                  child: Column(
                    children: [
                      for (final a in d.recentActivities) _ActivityTile(a),
                    ],
                  ),
                ),
              ],
                ]),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "Needs you" counters: approvals, children checked in today, unread parent messages,
/// parents' payments to confirm (the last three only with the school features).
class _NeedsYou extends ConsumerWidget {
  const _NeedsYou({required this.d, required this.school});
  final AdminDashboard d;
  final bool school;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(String r) => Routes.open(GoRouter.of(context), r);
    if (!school) {
      return HomeCounters(counters: [
        HomeCounter('Leave to approve', '${d.pendingLeaves}',
            highlight: d.pendingLeaves > 0, onTap: () => open(Routes.adminApprovals)),
        HomeCounter('Attendance to approve', '${d.pendingAttendance}',
            highlight: d.pendingAttendance > 0, onTap: () => open('${Routes.adminApprovals}?tab=attendance')),
        HomeCounter('Active employees', '${d.activeEmployees}', onTap: () => open(Routes.adminEmployees)),
      ]);
    }
    final today = ref.watch(staffTodayProvider).valueOrNull;
    final unread = ref.watch(schoolUnreadProvider).valueOrNull?.messages ?? 0;
    final claims = today?.feeClaimsPending ?? 0;
    return HomeCounters(counters: [
      HomeCounter('To approve', '${d.pendingApprovals}',
          highlight: d.pendingApprovals > 0, onTap: () => open(Routes.adminApprovals)),
      HomeCounter('Checked in today', today == null ? '–' : '${today.checkedIn}/${today.children}',
          onTap: () => open(Routes.schoolAttendance)),
      HomeCounter('Parent messages', '$unread', highlight: unread > 0, onTap: () => open(Routes.schoolMessages)),
      HomeCounter('Payments to confirm', '$claims', highlight: claims > 0, onTap: () => open(Routes.schoolFees)),
    ]);
  }
}

/// School tiles for admins: the whole school.
class _SchoolTiles extends ConsumerWidget {
  const _SchoolTiles();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(String r) => Routes.open(GoRouter.of(context), r);
    final unread = ref.watch(schoolUnreadProvider).valueOrNull?.messages ?? 0;
    final claims = ref.watch(staffTodayProvider).valueOrNull?.feeClaimsPending ?? 0;
    return HomeTileGrid(tiles: [
      HomeTile('Attendance', Icons.fact_check_outlined, TileColors.attendance, () => open(Routes.schoolAttendance)),
      HomeTile('Messages', Icons.forum_outlined, TileColors.messages, () => open(Routes.schoolMessages), badge: unread),
      HomeTile('Announce', Icons.campaign_outlined, TileColors.news, () => open(Routes.schoolAnnouncements)),
      HomeTile('Fees', Icons.receipt_long_outlined, TileColors.fees, () => open(Routes.schoolFees), badge: claims),
      HomeTile('Children', Icons.child_care_outlined, TileColors.today, () => open(Routes.schoolChildren)),
      HomeTile('Parents', Icons.family_restroom_outlined, TileColors.office, () => open(Routes.schoolParents)),
      HomeTile('Families', Icons.diversity_3_outlined, TileColors.teacher, () => open(Routes.schoolFamilies)),
      HomeTile('Pick-up people', Icons.how_to_reg_outlined, TileColors.note, () => open(Routes.schoolPickupPeople),
          badge: ref.watch(pendingPickupPeopleProvider).valueOrNull?.length ?? 0),
      HomeTile('Classes', Icons.class_outlined, TileColors.school, () => open(Routes.schoolClasses)),
    ]);
  }
}

/// HR tiles: employees, approvals, payroll, reports, leave, settings, help.
class _HrTiles extends StatelessWidget {
  const _HrTiles({required this.d});
  final AdminDashboard d;

  @override
  Widget build(BuildContext context) {
    void open(String r) => Routes.open(GoRouter.of(context), r);
    return HomeTileGrid(tiles: [
      HomeTile('Employees', Icons.groups_outlined, TileColors.people, () => open(Routes.adminEmployees)),
      HomeTile('Approvals', Icons.pending_actions_outlined, TileColors.note, () => open(Routes.adminApprovals),
          badge: d.pendingApprovals),
      HomeTile('Payroll', Icons.payments_outlined, TileColors.payroll, () => open(Routes.adminPayroll)),
      HomeTile('Reports', Icons.bar_chart_outlined, TileColors.reports, () => open(Routes.monthlySummary)),
      HomeTile('Leave balances', Icons.beach_access_outlined, TileColors.leave, () => open(Routes.leaveBalances)),
      HomeTile('Holidays', Icons.celebration_outlined, TileColors.today, () => open(Routes.holidaysMaster)),
      HomeTile('Chatbot', Icons.smart_toy_outlined, TileColors.help, () => open(Routes.chatbotAdmin)),
      HomeTile('Settings', Icons.settings_outlined, TileColors.settings, () => open(Routes.companySettings)),
    ]);
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.username, required this.d, this.schoolName});

  final String username;
  final AdminDashboard d;
  final String? schoolName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
            child: Icon(Icons.admin_panel_settings_outlined, color: scheme.onPrimary),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello, $username',
                    style: text.titleLarge
                        ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (schoolName != null && schoolName!.isNotEmpty) schoolName!,
                    '${d.totalEmployees} employees · ${d.totalDepartments} departments',
                  ].join('\n'),
                  style: text.bodyMedium?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActivityTile extends StatelessWidget {
  const _ActivityTile(this.a);

  final AdminActivity a;

  static final _time = DateFormat('dd MMM, h:mm a');

  @override
  Widget build(BuildContext context) {
    final icon = a.type.startsWith('leave')
        ? Icons.beach_access_outlined
        : a.type.startsWith('attendance')
            ? Icons.event_available_outlined
            : Icons.history;
    return ListTile(
      dense: true,
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(a.employeeName),
      subtitle: Text(a.description),
      trailing: a.timestamp == null
          ? null
          : Text(_time.format(a.timestamp!.toLocal()),
              style: Theme.of(context).textTheme.bodySmall),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      );
}
