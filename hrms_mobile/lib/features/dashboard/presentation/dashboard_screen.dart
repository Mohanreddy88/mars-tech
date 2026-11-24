import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/home_tiles.dart';
import '../../notifications/data/notification_repository.dart';
import '../../assistant/presentation/assistant_screen.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../../school/data/school_repository.dart';
import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: const [AssistantButton(), NotificationBell()],
      ),
      body: dashboard.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(unreadCountProvider);
            ref.invalidate(schoolUnreadProvider);
            ref.invalidate(staffTodayProvider);
            return ref.refresh(dashboardProvider.future);
          },
          child: _DashboardBody(data: data),
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({required this.data});

  final EmployeeDashboard data;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void open(String r) => Routes.open(GoRouter.of(context), r);
    final me = ref.watch(schoolMeProvider).valueOrNull;
    // Class teachers (school features on) get their class at the top
    final teacher = me != null && me.isStaff && me.isTeacher;
    final today = teacher ? ref.watch(staffTodayProvider).valueOrNull : null;
    final unread = teacher ? ref.watch(schoolUnreadProvider).valueOrNull?.messages ?? 0 : 0;
    final className = teacher && me.classes.isNotEmpty ? me.classes.map((c) => c.name).join(', ') : null;

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _GreetingCard(employee: data.employee, classTeacherOf: className),
        const SizedBox(height: 4),
        HomeCounters(counters: [
          if (teacher) ...[
            HomeCounter('Checked in today', today == null ? '–' : '${today.checkedIn}/${today.children}',
                onTap: () => open(Routes.schoolAttendance)),
            HomeCounter('Parent messages', '$unread', highlight: unread > 0, onTap: () => open(Routes.schoolMessages)),
          ],
          HomeCounter('Leave balance', Fmt.days(data.stats.totalLeaveBalance), onTap: () => open(Routes.leave)),
          if (!teacher)
            HomeCounter('Pending approvals', '${data.stats.pendingApprovals}',
                highlight: data.stats.pendingApprovals > 0, onTap: () => open(Routes.leave)),
        ]),
        const Divider(height: 1),
        if (teacher) ...[
          HomeSectionTitle(className == null ? 'My class' : 'My class · $className'),
          HomeTileGrid(tiles: [
            HomeTile('Attendance', Icons.fact_check_outlined, TileColors.attendance, () => open(Routes.schoolAttendance)),
            HomeTile('Daily reports', Icons.photo_library_outlined, TileColors.report, () => open(Routes.schoolAttendance)),
            HomeTile('Messages', Icons.forum_outlined, TileColors.messages, () => open(Routes.schoolMessages), badge: unread),
            HomeTile('Announce', Icons.campaign_outlined, TileColors.news, () => open(Routes.schoolAnnouncements)),
            HomeTile('My class', Icons.groups_outlined, TileColors.school, () => open(Routes.schoolMyClass)),
          ]),
        ],
        const HomeSectionTitle('My work'),
        HomeTileGrid(tiles: [
          HomeTile('Apply leave', Icons.edit_calendar_outlined, TileColors.leave, () => open(Routes.applyLeave)),
          HomeTile('My leave', Icons.beach_access_outlined, TileColors.today, () => open(Routes.leave),
              badge: data.stats.pendingApprovals),
          HomeTile('Payslips', Icons.receipt_long_outlined, TileColors.payroll, () => open(Routes.payslips)),
          HomeTile('Attendance', Icons.event_available_outlined, TileColors.attendance, () => open(Routes.attendance)),
          HomeTile('Profile', Icons.person_outline, TileColors.account, () => open(Routes.profile)),
          HomeTile('Help', Icons.support_agent_outlined, TileColors.help, () => open(Routes.assistant)),
        ]),
        if (data.leaveBalances.isNotEmpty) ...[
          _SectionHeader(title: 'Leave balances', onSeeAll: () => context.go(Routes.leave)),
          SizedBox(
            height: 150,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: data.leaveBalances.length,
              separatorBuilder: (_, __) => const SizedBox(width: 10),
              itemBuilder: (context, i) => _LeaveRing(data.leaveBalances[i], color: _ringColors[i % _ringColors.length]),
            ),
          ),
        ],
        _SectionHeader(title: 'Payslips', onSeeAll: () => context.go(Routes.payslips)),
        if (data.recentPayslips.isEmpty)
          const _EmptyCard('No payslips yet')
        else
          _PayslipCard(latest: data.recentPayslips.first, older: data.recentPayslips.skip(1).take(3).toList()),
        if (data.upcomingLeaves.isNotEmpty) ...[
          const _SectionHeader(title: 'Upcoming leave'),
          Card(
            child: Column(children: [
              for (final l in data.upcomingLeaves)
                _DateRow(
                  date: l.startDate,
                  color: TileColors.leave,
                  title: l.leaveType,
                  subtitle: l.endDate == null || l.endDate == l.startDate
                      ? Fmt.date(l.startDate)
                      : '${Fmt.shortDate(l.startDate)} – ${Fmt.date(l.endDate)}',
                  trailing: Fmt.days(l.totalDays),
                ),
            ]),
          ),
        ],
        const _SectionHeader(title: 'Upcoming public holidays'),
        if (data.upcomingHolidays.isEmpty)
          const _EmptyCard('No public holidays in the next 3 months')
        else
          Card(
            child: Column(children: [
              for (final h in data.upcomingHolidays)
                _DateRow(
                  date: h.date,
                  color: TileColors.today,
                  title: h.name,
                  subtitle: h.date == null ? '' : DateFormat('EEEE').format(h.date!),
                ),
            ]),
          ),
      ],
    );
  }
}

const _ringColors = [
  TileColors.leave, TileColors.attendance, TileColors.report, TileColors.office, TileColors.today, TileColors.fees,
];

/// One leave type: a ring showing days left out of the entitlement.
class _LeaveRing extends StatelessWidget {
  const _LeaveRing(this.b, {required this.color});
  final LeaveBalance b;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final left = b.totalDays <= 0 ? 0.0 : (b.balanceDays / b.totalDays).clamp(0.0, 1.0);
    return SizedBox(
      width: 118,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => context.go(Routes.leave),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 12, 8, 8),
            child: Column(children: [
              SizedBox(
                width: 64,
                height: 64,
                child: Stack(alignment: Alignment.center, children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: left.toDouble(),
                      strokeWidth: 7,
                      strokeCap: StrokeCap.round,
                      backgroundColor: color.withValues(alpha: 0.15),
                      valueColor: AlwaysStoppedAnimation(color),
                    ),
                  ),
                  Text(Fmt.days(b.balanceDays), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                ]),
              ),
              const SizedBox(height: 8),
              Text(b.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelLarge),
              Text('left of ${Fmt.days(b.totalDays)}', style: text.bodySmall),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The latest payslip large (month, net pay, status) and the previous ones as small chips.
class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.latest, required this.older});
  final PayslipSummary latest;
  final List<PayslipSummary> older;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        InkWell(
          onTap: () => context.go('${Routes.payslips}/${latest.id}'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(shape: BoxShape.circle, color: TileColors.payroll.withValues(alpha: 0.14)),
                child: const Icon(Icons.receipt_long_outlined, color: TileColors.payroll, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(latest.monthYear, style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  Text(Fmt.money(latest.netSalary), style: text.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
                  Text('Net pay · ${latest.status}', style: text.bodySmall),
                ]),
              ),
              const Icon(Icons.chevron_right),
            ]),
          ),
        ),
        if (older.isNotEmpty) ...[
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
            child: Wrap(spacing: 8, runSpacing: 6, children: [
              for (final p in older)
                ActionChip(
                  avatar: const Icon(Icons.description_outlined, size: 16),
                  label: Text('${p.monthYear} · ${Fmt.money(p.netSalary)}'),
                  onPressed: () => context.go('${Routes.payslips}/${p.id}'),
                ),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// A calendar-style date badge (day number over month) with a title, e.g. a holiday.
class _DateRow extends StatelessWidget {
  const _DateRow({required this.date, required this.color, required this.title, required this.subtitle, this.trailing});
  final DateTime? date;
  final Color color;
  final String title;
  final String subtitle;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return ListTile(
      leading: Container(
        width: 46,
        height: 50,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.14), borderRadius: BorderRadius.circular(10)),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(date == null ? '–' : '${date!.day}',
              style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color, height: 1.1)),
          Text(date == null ? '' : DateFormat('MMM').format(date!).toUpperCase(),
              style: text.labelSmall?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ]),
      ),
      title: Text(title),
      subtitle: subtitle.isEmpty ? null : Text(subtitle),
      trailing: trailing == null ? null : Text(trailing!, style: text.titleSmall),
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.employee, this.classTeacherOf});

  final DashboardEmployee employee;
  /// Class names when this employee is a class teacher (school features).
  final String? classTeacherOf;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final subtitle = [employee.designation, employee.departmentName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 26,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
            child: Text(
              employee.firstName.isEmpty
                  ? '?'
                  : employee.firstName[0].toUpperCase(),
              style: text.titleLarge?.copyWith(color: scheme.onPrimary),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Hello, ${employee.firstName}',
                    style: text.titleLarge?.copyWith(
                        color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: text.bodyMedium?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.85))),
                if (classTeacherOf != null)
                  Text('Class teacher · $classTeacherOf',
                      style: text.bodyMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                if (employee.employeeCode != null)
                  Text(employee.employeeCode!,
                      style: text.bodySmall?.copyWith(
                          color: scheme.onPrimary.withValues(alpha: 0.7))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.onSeeAll});

  final String title;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
      child: Row(
        children: [
          Expanded(
            child: Text(title,
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (onSeeAll != null)
            TextButton(onPressed: onSeeAll, child: const Text('See all')),
        ],
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}
