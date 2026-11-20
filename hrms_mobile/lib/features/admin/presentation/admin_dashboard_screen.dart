import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/data/notification_repository.dart';
import '../../notifications/presentation/notifications_screen.dart';
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin'),
        actions: const [NotificationBell()],
      ),
      body: dashboard.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(adminDashboardProvider)),
        data: (d) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(unreadCountProvider);
            return ref.refresh(adminDashboardProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              _Header(username: username, d: d),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.groups_outlined,
                      value: '${d.activeEmployees}',
                      label: 'Active employees',
                      onTap: () => context.go(Routes.adminEmployees),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Tile(
                      icon: Icons.pending_actions_outlined,
                      value: '${d.pendingApprovals}',
                      label: 'Pending approvals',
                      highlight: d.pendingApprovals > 0,
                      onTap: () => context.go(Routes.adminApprovals),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _Tile(
                      icon: Icons.beach_access_outlined,
                      value: '${d.pendingLeaves}',
                      label: 'Leave to approve',
                      onTap: () => context.go(Routes.adminApprovals),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _Tile(
                      icon: Icons.event_available_outlined,
                      value: '${d.pendingAttendance}',
                      label: 'Attendance to approve',
                      onTap: () => context.go('${Routes.adminApprovals}?tab=attendance'),
                    ),
                  ),
                ],
              ),
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
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.username, required this.d});

  final String username;
  final AdminDashboard d;

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
                  '${d.totalEmployees} employees · ${d.totalDepartments} departments',
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

class _Tile extends StatelessWidget {
  const _Tile({
    required this.icon,
    required this.value,
    required this.label,
    this.onTap,
    this.highlight = false,
  });

  final IconData icon;
  final String value;
  final String label;
  final VoidCallback? onTap;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight ? const Color(0xFFB45309) : theme.colorScheme.primary;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 12),
              Text(value,
                  style: theme.textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w700, color: highlight ? color : null)),
              Text(label,
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
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
