import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin view of one employee: details, this year's leave balances and
/// payroll history. (Editing employees stays on the website.)
class EmployeeDetailScreen extends ConsumerWidget {
  const EmployeeDetailScreen({super.key, required this.employee});

  final EmployeeSummary employee;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = employee;
    final balances = ref.watch(employeeLeaveBalancesProvider(e.id));
    final payrolls = ref.watch(employeePayrollsProvider(e.id));
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Scaffold(
      appBar: AppBar(title: Text(e.name)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: [
          _Header(e),
          const SizedBox(height: 12),
          _Info('Contact', [
            ('Email', e.email),
            ('Mobile', e.phoneDisplay),
          ]),
          const SizedBox(height: 12),
          _Info('Employment', [
            ('Employee code', e.employeeCode),
            ('Department', e.departmentName),
            ('Designation', e.designation),
            ('Joined', e.joinDate == null ? null : Fmt.date(e.joinDate)),
            ('Basic salary', e.salary == null ? null : Fmt.money(e.salary!)),
          ]),
          const SizedBox(height: 12),
          _Info('Personal', [
            (e.idType?.isNotEmpty == true ? e.idType! : 'IC / Passport', e.icPassport),
            ('Date of birth', e.dateOfBirth == null ? null : Fmt.date(e.dateOfBirth)),
            ('Gender', e.gender),
            ('Tax number', e.taxNumber),
          ]),
          const SizedBox(height: 12),
          _Info('Bank', [
            ('Bank', e.bankName),
            ('Account number', e.accountNumber),
          ]),
          _Section('Leave balances ${DateTime.now().year}'),
          Card(
            child: balances.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              error: (err, _) => ListTile(title: Text(ApiException.from(err).message)),
              data: (items) => items.isEmpty
                  ? ListTile(title: Text('No leave balances for this year', style: muted))
                  : Column(
                      children: [
                        for (final b in items)
                          ListTile(
                            dense: true,
                            title: Text(b.name),
                            subtitle: Text('${Fmt.days(b.usedDays)} used of ${Fmt.days(b.totalDays)}'),
                            trailing: Text('${Fmt.days(b.balanceDays)} left',
                                style: const TextStyle(fontWeight: FontWeight.w600)),
                          ),
                      ],
                    ),
            ),
          ),
          const _Section('Payroll history'),
          Card(
            child: payrolls.when(
              loading: () => const Padding(
                  padding: EdgeInsets.all(16), child: LinearProgressIndicator()),
              error: (err, _) => ListTile(title: Text(ApiException.from(err).message)),
              data: (rows) => rows.isEmpty
                  ? ListTile(title: Text('No payroll yet', style: muted))
                  : Column(
                      children: [
                        for (final p in rows.take(12))
                          ListTile(
                            dense: true,
                            title: Text(p.monthYear),
                            subtitle: Row(children: [StatusChip(p.status)]),
                            trailing: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                Text(Fmt.money(p.netSalary),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                                Text('Gross ${Fmt.money(p.grossIncome)}',
                                    style: theme.textTheme.bodySmall),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
          ),
          const SizedBox(height: 12),
          Text('To edit this employee, use the website.',
              textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.e);

  final EmployeeSummary e;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final job = [e.designation, e.departmentName].where((s) => s?.isNotEmpty ?? false).join(' · ');
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
            child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase(),
                style: text.headlineSmall?.copyWith(color: scheme.onPrimary)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.name,
                    style: text.titleLarge
                        ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                if (job.isNotEmpty)
                  Text(job,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85))),
                const SizedBox(height: 6),
                StatusChip(e.isActive ? 'Approved' : 'Cancelled',
                    label: e.isActive ? 'Active' : 'Inactive'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.title, this.rows);

  final String title;
  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(label, style: muted)),
                    Expanded(
                      child: Text(value == null || value.isEmpty ? '—' : value,
                          textAlign: TextAlign.right),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
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
            style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
      );
}
