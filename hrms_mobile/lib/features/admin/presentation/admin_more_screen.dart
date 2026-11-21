import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../school/presentation/school_menu.dart';

/// Admin "More" tab: account (change password, sign out) and the admin
/// modules that don't have their own tab.
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
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final username = session?.username ?? '';

    Widget item(IconData icon, String title, String subtitle, String route) => ListTile(
          leading: Icon(icon, color: scheme.primary),
          title: Text(title),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => context.push(route),
        );

    return Scaffold(
      appBar: AppBar(
        title: const Text('More'),
        actions: [
          TextButton.icon(
            onPressed: () => _signOut(context, ref),
            icon: const Icon(Icons.logout),
            label: const Text('Sign out'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
                  child: Text(username.isEmpty ? '?' : username[0].toUpperCase(),
                      style: text.titleLarge?.copyWith(color: scheme.onPrimary)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(username,
                          style: text.titleMedium
                              ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                      Text('Administrator',
                          style: text.bodySmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85))),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SchoolMenuCard(heading: _Heading('School')),
          const _Heading('Attendance & leave'),
          Card(
            child: Column(children: [
              item(Icons.history, 'Attendance history', 'All periods, by status and employee',
                  Routes.attendanceHistory),
              const Divider(height: 1),
              item(Icons.beach_access_outlined, 'Leave balances', 'Entitlements per employee and year',
                  Routes.leaveBalances),
            ]),
          ),
          const _Heading('Reports & insights'),
          Card(
            child: Column(children: [
              item(Icons.insights_outlined, 'Analytics', 'Payroll trend, headcount, salary bands',
                  Routes.analytics),
              const Divider(height: 1),
              item(Icons.calendar_view_month_outlined, 'Monthly summary', 'Payroll and attendance for a month',
                  Routes.monthlySummary),
              const Divider(height: 1),
              item(Icons.request_quote_outlined, 'Payroll report', 'By department · Excel export',
                  Routes.payrollReport),
              const Divider(height: 1),
              item(Icons.fact_check_outlined, 'Attendance report', 'Date range, by employee · Excel export',
                  Routes.attendanceReport),
              const Divider(height: 1),
              item(Icons.contacts_outlined, 'Employee directory', 'By department · Excel export',
                  Routes.directoryReport),
              const Divider(height: 1),
              item(Icons.manage_search, 'Audit log', 'Who changed what, and when', Routes.auditLog),
            ]),
          ),
          const _Heading('Master data'),
          Card(
            child: Column(children: [
              item(Icons.apartment_outlined, 'Departments', 'Add, rename, deactivate', Routes.departmentsMaster),
              const Divider(height: 1),
              item(Icons.account_balance_outlined, 'Banks', 'Banks for salary payment', Routes.banksMaster),
              const Divider(height: 1),
              item(Icons.celebration_outlined, 'Public holidays', 'Per year, national or state', Routes.holidaysMaster),
              const Divider(height: 1),
              item(Icons.manage_accounts_outlined, 'Users', 'Logins, roles, passwords', Routes.usersMaster),
              const Divider(height: 1),
              item(Icons.business_outlined, 'Company settings', 'Details on payslips and EA forms',
                  Routes.companySettings),
              const Divider(height: 1),
              item(Icons.percent, 'Statutory rates', 'EPF, SOCSO, EIS, PCB (view)', Routes.statutoryRates),
            ]),
          ),
          const _Heading('Account'),
          Card(
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
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 20, 0, 8),
        child: Text(text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}
