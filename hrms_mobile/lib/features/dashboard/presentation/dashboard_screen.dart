import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../data/dashboard_models.dart';
import '../data/dashboard_repository.dart';

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dashboard = ref.watch(dashboardProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Home')),
      body: dashboard.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(dashboardProvider),
        ),
        data: (data) => RefreshIndicator(
          onRefresh: () => ref.refresh(dashboardProvider.future),
          child: _DashboardBody(data: data),
        ),
      ),
    );
  }
}

class _DashboardBody extends StatelessWidget {
  const _DashboardBody({required this.data});

  final EmployeeDashboard data;

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        _GreetingCard(employee: data.employee),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _StatTile(
                label: 'Leave balance',
                value: Fmt.days(data.stats.totalLeaveBalance),
                icon: Icons.beach_access_outlined,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _StatTile(
                label: 'Pending approvals',
                value: '${data.stats.pendingApprovals}',
                icon: Icons.hourglass_top_outlined,
              ),
            ),
          ],
        ),
        if (data.leaveBalances.isNotEmpty) ...[
          _SectionHeader(
            title: 'Leave balances',
            onSeeAll: () => context.go(Routes.leave),
          ),
          Card(
            child: Column(
              children: [
                for (final b in data.leaveBalances) _LeaveBalanceRow(b),
              ],
            ),
          ),
        ],
        _SectionHeader(
          title: 'Recent payslips',
          onSeeAll: () => context.go(Routes.payslips),
        ),
        if (data.recentPayslips.isEmpty)
          const _EmptyCard('No payslips yet')
        else
          Card(
            child: Column(
              children: [
                for (final p in data.recentPayslips)
                  ListTile(
                    leading: const Icon(Icons.receipt_long_outlined),
                    title: Text(p.monthYear),
                    subtitle: Text(p.status),
                    trailing: Text(
                      Fmt.money(p.netSalary),
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        if (data.upcomingLeaves.isNotEmpty) ...[
          const _SectionHeader(title: 'Upcoming leave'),
          Card(
            child: Column(
              children: [
                for (final l in data.upcomingLeaves)
                  ListTile(
                    leading: const Icon(Icons.flight_takeoff_outlined),
                    title: Text(l.leaveType),
                    subtitle: Text(
                        '${Fmt.shortDate(l.startDate)} – ${Fmt.date(l.endDate)}'),
                    trailing: Text(Fmt.days(l.totalDays)),
                  ),
              ],
            ),
          ),
        ],
        const _SectionHeader(title: 'Upcoming public holidays'),
        if (data.upcomingHolidays.isEmpty)
          const _EmptyCard('No public holidays in the next 3 months')
        else
          Card(
            child: Column(
              children: [
                for (final h in data.upcomingHolidays)
                  ListTile(
                    leading: const Icon(Icons.celebration_outlined),
                    title: Text(h.name),
                    trailing: Text(Fmt.date(h.date)),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

class _GreetingCard extends StatelessWidget {
  const _GreetingCard({required this.employee});

  final DashboardEmployee employee;

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

class _StatTile extends StatelessWidget {
  const _StatTile(
      {required this.label, required this.value, required this.icon});

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(height: 12),
            Text(value,
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
            Text(label,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}

class _LeaveBalanceRow extends StatelessWidget {
  const _LeaveBalanceRow(this.balance);

  final LeaveBalance balance;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                  child: Text(balance.name, style: theme.textTheme.bodyLarge)),
              Text(
                '${Fmt.days(balance.balanceDays)} left',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: balance.usedFraction,
              minHeight: 6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${Fmt.days(balance.usedDays)} used of ${Fmt.days(balance.totalDays)}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
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
