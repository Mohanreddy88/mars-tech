import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../../payroll/data/payroll_admin_models.dart';
import '../data/reports_models.dart';
import '../data/reports_repository.dart';
import 'report_widgets.dart';

final _payrollReportProvider = FutureProvider.autoDispose.family<PayrollReport, PayMonth>(
    (ref, m) => ref.watch(reportsRepositoryProvider).payroll(m));
final _monthlyProvider = FutureProvider.autoDispose.family<MonthlySummary, PayMonth>(
    (ref, m) => ref.watch(reportsRepositoryProvider).monthly(m));
final _directoryProvider = FutureProvider.autoDispose.family<EmployeeDirectory, bool>(
    (ref, inactive) => ref.watch(reportsRepositoryProvider).directory(includeInactive: inactive));
final _attendanceReportProvider =
    FutureProvider.autoDispose.family<AttendanceReport, (DateTime, DateTime)>(
        (ref, r) => ref.watch(reportsRepositoryProvider).attendance(r.$1, r.$2));

String _pct(double fraction) => '${(fraction * 100).toStringAsFixed(1)}%';

/// Month picker row shared by the monthly reports.
class _MonthBar extends StatelessWidget {
  const _MonthBar({required this.month, required this.onChanged});

  final PayMonth month;
  final ValueChanged<PayMonth> onChanged;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(children: [
          IconButton(onPressed: () => onChanged(month.previous), icon: const Icon(Icons.chevron_left)),
          Expanded(
            child: Text(month.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(onPressed: () => onChanged(month.next), icon: const Icon(Icons.chevron_right)),
        ]),
      );
}

// ── Payroll report ────────────────────────────────────────────────────────

/// Payroll by department for a month (all statuses), with Excel export.
class PayrollReportScreen extends ConsumerStatefulWidget {
  const PayrollReportScreen({super.key});

  @override
  ConsumerState<PayrollReportScreen> createState() => _PayrollReportScreenState();
}

class _PayrollReportScreenState extends ConsumerState<PayrollReportScreen> {
  PayMonth _month = PayMonth.now();

  @override
  Widget build(BuildContext context) {
    final report = ref.watch(_payrollReportProvider(_month));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll report'),
        actions: [
          ExcelExportButton(download: () => ref.read(reportsRepositoryProvider).payrollExcel(_month)),
        ],
      ),
      body: Column(children: [
        _MonthBar(month: _month, onChanged: (m) => setState(() => _month = m)),
        Expanded(
          child: report.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_payrollReportProvider(_month))),
            data: (r) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: r.totals.count == 0
                  ? [const _Empty('No payroll for this month.')]
                  : [
                      FigureGrid([
                        ('Payslips', '${r.totals.count}'),
                        ('Net pay', Fmt.money(r.totals.net)),
                        ('Gross pay', Fmt.money(r.totals.gross)),
                        ('Tax (PCB)', Fmt.money(r.totals.tax)),
                        ('EPF (employee)', Fmt.money(r.totals.epf)),
                        ('SOCSO + EIS', Fmt.money(r.totals.socso + r.totals.eis)),
                      ]),
                      const SizedBox(height: 12),
                      ReportCard(
                        title: 'Net pay by department',
                        child: BarList(
                          rows: [for (final (d, t) in r.departments) (d, t.net)],
                          format: Fmt.money,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final (dept, t) in r.departments) ...[
                        ReportCard(
                          title: dept,
                          subtitle: '${t.count} payslip${t.count == 1 ? '' : 's'} · average net ${Fmt.money(t.average)}',
                          child: _Lines([
                            ('Gross', Fmt.money(t.gross)),
                            ('EPF', Fmt.money(t.epf)),
                            ('SOCSO', Fmt.money(t.socso)),
                            ('EIS', Fmt.money(t.eis)),
                            ('Tax (PCB)', Fmt.money(t.tax)),
                            if (t.otherDeductions > 0) ('Other deductions', Fmt.money(t.otherDeductions)),
                            ('Net', Fmt.money(t.net)),
                          ]),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Attendance report ─────────────────────────────────────────────────────

/// Approved attendance between two dates: totals, by department, by
/// employee; Excel export.
class AttendanceReportScreen extends ConsumerStatefulWidget {
  const AttendanceReportScreen({super.key});

  @override
  ConsumerState<AttendanceReportScreen> createState() => _AttendanceReportScreenState();
}

class _AttendanceReportScreenState extends ConsumerState<AttendanceReportScreen> {
  late DateTimeRange _range = () {
    final n = DateTime.now();
    return DateTimeRange(start: DateTime(n.year, n.month, 1), end: DateTime(n.year, n.month, n.day));
  }();

  @override
  Widget build(BuildContext context) {
    final key = (_range.start, _range.end);
    final report = ref.watch(_attendanceReportProvider(key));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance report'),
        actions: [
          ExcelExportButton(
              download: () => ref.read(reportsRepositoryProvider).attendanceExcel(_range.start, _range.end)),
        ],
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: OutlinedButton.icon(
            onPressed: () async {
              final picked = await showDateRangePicker(
                context: context,
                firstDate: DateTime(2020),
                lastDate: DateTime.now(),
                initialDateRange: _range,
              );
              if (picked != null) setState(() => _range = picked);
            },
            icon: const Icon(Icons.date_range_outlined),
            label: Text('${Fmt.date(_range.start)}  –  ${Fmt.date(_range.end)}'),
          ),
        ),
        Expanded(
          child: report.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_attendanceReportProvider(key))),
            data: (r) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: r.counts.total == 0
                  ? [const _Empty('No approved attendance in this period.')]
                  : [
                      FigureGrid([
                        ('Attendance rate', _pct(r.counts.attendanceRate)),
                        ('Working days recorded', '${r.counts.total}'),
                        ('Present', '${r.counts.present}'),
                        ('Half days', '${r.counts.halfDay}'),
                        ('On leave', '${r.counts.leave}'),
                        ('Absent', '${r.counts.absent}'),
                      ]),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 0),
                        child: Text(
                          'Approved attendance only. Weekends (${r.weekendDays}) and public holidays '
                          '(${r.holidayDays}) are not counted.',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ReportCard(
                        title: 'Attendance rate by department',
                        child: BarList(
                          rows: [for (final (d, c) in r.byDepartment) (d, c.attendanceRate * 100)],
                          format: (v) => '${v.toStringAsFixed(1)}%',
                          max: 100,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ReportCard(
                        title: 'By employee',
                        child: Column(children: [
                          for (final e in r.byEmployee)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              title: Text(e.employeeName),
                              subtitle: Text('${e.department} · ${e.present} present · ${e.leave} leave'
                                  '${e.absent > 0 ? ' · ${e.absent} absent' : ''}'),
                              trailing: Text(
                                '${e.hours == e.hours.roundToDouble() ? e.hours.toStringAsFixed(0) : e.hours.toStringAsFixed(1)} h',
                                style: const TextStyle(fontWeight: FontWeight.w600),
                              ),
                            ),
                        ]),
                      ),
                    ],
            ),
          ),
        ),
      ]),
    );
  }
}

// ── Employee directory ────────────────────────────────────────────────────

/// Employees grouped by department; Excel export.
class DirectoryReportScreen extends ConsumerStatefulWidget {
  const DirectoryReportScreen({super.key});

  @override
  ConsumerState<DirectoryReportScreen> createState() => _DirectoryReportScreenState();
}

class _DirectoryReportScreenState extends ConsumerState<DirectoryReportScreen> {
  bool _includeInactive = false;

  @override
  Widget build(BuildContext context) {
    final dir = ref.watch(_directoryProvider(_includeInactive));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee directory'),
        actions: [ExcelExportButton(download: () => ref.read(reportsRepositoryProvider).employeesExcel())],
      ),
      body: dir.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_directoryProvider(_includeInactive))),
        data: (d) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Include inactive employees'),
              subtitle: Text('${d.active} active${_includeInactive ? ' · ${d.inactive} inactive' : ''}'),
              value: _includeInactive,
              onChanged: (v) => setState(() => _includeInactive = v),
            ),
            ReportCard(
              title: 'Employees by department',
              child: BarList(
                rows: [for (final (dept, list) in d.byDepartment) (dept, list.length.toDouble())],
                format: (v) => v.toStringAsFixed(0),
              ),
            ),
            for (final (dept, list) in d.byDepartment) ...[
              const SizedBox(height: 12),
              ReportCard(
                title: '$dept (${list.length})',
                child: Column(children: [
                  for (final e in list)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(e.name + (e.isActive ? '' : '  (inactive)')),
                      subtitle: Text([e.designation, e.email, e.phone]
                          .where((s) => s?.isNotEmpty ?? false)
                          .join(' · ')),
                      trailing: e.joinDate == null
                          ? null
                          : Text('Joined\n${Fmt.date(e.joinDate)}',
                              textAlign: TextAlign.right, style: theme.textTheme.bodySmall),
                    ),
                ]),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── Monthly summary ───────────────────────────────────────────────────────

/// Payroll and attendance at a glance for one month.
class MonthlySummaryScreen extends ConsumerStatefulWidget {
  const MonthlySummaryScreen({super.key});

  @override
  ConsumerState<MonthlySummaryScreen> createState() => _MonthlySummaryScreenState();
}

class _MonthlySummaryScreenState extends ConsumerState<MonthlySummaryScreen> {
  PayMonth _month = PayMonth.now();

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(_monthlyProvider(_month));
    return Scaffold(
      appBar: AppBar(title: const Text('Monthly summary')),
      body: Column(children: [
        _MonthBar(month: _month, onChanged: (m) => setState(() => _month = m)),
        Expanded(
          child: s.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_monthlyProvider(_month))),
            data: (m) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              children: [
                ReportCard(
                  title: 'Payroll',
                  child: m.payroll.count == 0
                      ? const _Empty('No payroll for this month.')
                      : FigureGrid([
                          ('Payslips', '${m.payroll.count}'),
                          ('Net pay', Fmt.money(m.payroll.net)),
                          ('Gross pay', Fmt.money(m.payroll.gross)),
                          ('Average net', Fmt.money(m.payroll.average)),
                          ('EPF', Fmt.money(m.payroll.epf)),
                          ('Tax (PCB)', Fmt.money(m.payroll.tax)),
                        ]),
                ),
                const SizedBox(height: 12),
                ReportCard(
                  title: 'Attendance (approved)',
                  child: m.attendance.total == 0
                      ? const _Empty('No approved attendance for this month.')
                      : FigureGrid([
                          ('Attendance rate', _pct(m.attendance.attendanceRate)),
                          ('Avg hours / day', m.averageWorkHours.toStringAsFixed(1)),
                          ('Present', '${m.attendance.present}'),
                          ('Half days', '${m.attendance.halfDay}'),
                          ('On leave', '${m.attendance.leave}'),
                          ('Absent', '${m.attendance.absent}'),
                        ]),
                ),
              ],
            ),
          ),
        ),
      ]),
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines(this.rows);

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Column(children: [
      for (final (label, value) in rows)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [Expanded(child: Text(label, style: muted)), Text(value)]),
        ),
    ]);
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(text,
            textAlign: TextAlign.center,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
      );
}
