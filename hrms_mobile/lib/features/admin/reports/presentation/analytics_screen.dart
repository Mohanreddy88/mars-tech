import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import '../data/reports_models.dart';
import '../data/reports_repository.dart';
import 'report_widgets.dart';

final _headcountProvider = FutureProvider.autoDispose<List<(String, int)>>(
    (ref) => ref.watch(reportsRepositoryProvider).headcountByDepartment());
final _trendProvider = FutureProvider.autoDispose.family<List<PayrollTrendPoint>, int>(
    (ref, months) => ref.watch(reportsRepositoryProvider).payrollTrend(months));
final _salaryProvider = FutureProvider.autoDispose<SalaryDistribution>(
    (ref) => ref.watch(reportsRepositoryProvider).salaryDistribution());
final _attendanceRateProvider = FutureProvider.autoDispose.family<List<DepartmentAttendanceRate>, int>(
    (ref, year) => ref.watch(reportsRepositoryProvider).attendanceRates(year));

/// Admin analytics: headcount by department, payroll trend, salary bands,
/// attendance rate by department. Single-series bars, values as text.
class AnalyticsScreen extends ConsumerStatefulWidget {
  const AnalyticsScreen({super.key});

  @override
  ConsumerState<AnalyticsScreen> createState() => _AnalyticsScreenState();
}

class _AnalyticsScreenState extends ConsumerState<AnalyticsScreen> {
  int _months = 6;
  final int _year = DateTime.now().year;

  Future<void> _refresh() async {
    ref
      ..invalidate(_headcountProvider)
      ..invalidate(_trendProvider(_months))
      ..invalidate(_salaryProvider)
      ..invalidate(_attendanceRateProvider(_year));
  }

  @override
  Widget build(BuildContext context) {
    final headcount = ref.watch(_headcountProvider);
    final trend = ref.watch(_trendProvider(_months));
    final salary = ref.watch(_salaryProvider);
    final rates = ref.watch(_attendanceRateProvider(_year));
    final theme = Theme.of(context);

    Widget section<T>(AsyncValue<T> v, Widget Function(T) build) => v.when(
          loading: () => const Padding(padding: EdgeInsets.all(12), child: LinearProgressIndicator()),
          error: (e, _) => Text(ApiException.from(e).message, style: TextStyle(color: theme.colorScheme.error)),
          data: build,
        );

    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            ReportCard(
              title: 'Net payroll by month',
              subtitle: 'Tap a month for details',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerRight,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: const [
                        ButtonSegment(value: 6, label: Text('6 months')),
                        ButtonSegment(value: 12, label: Text('12 months')),
                      ],
                      selected: {_months},
                      onSelectionChanged: (s) => setState(() => _months = s.first),
                    ),
                  ),
                  const SizedBox(height: 12),
                  section(
                    trend,
                    (points) => ColumnChart(
                      key: ValueKey(_months),
                      labels: [for (final p in points) p.label],
                      values: [for (final p in points) p.net],
                      format: Fmt.money,
                      details: (i) {
                        final p = points[i];
                        return Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(p.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                              const SizedBox(height: 4),
                              _kv('Net pay', Fmt.money(p.net)),
                              _kv('Gross pay', Fmt.money(p.gross)),
                              _kv('Deductions', Fmt.money(p.deductions)),
                              _kv('Payslips', '${p.payslips}'),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            ReportCard(
              title: 'Active employees by department',
              child: section(
                headcount,
                (rows) => BarList(
                  rows: [for (final (d, n) in rows) (d, n.toDouble())],
                  format: (v) => v.toStringAsFixed(0),
                ),
              ),
            ),
            const SizedBox(height: 12),
            ReportCard(
              title: 'Basic salary bands',
              subtitle: 'Active employees',
              child: section(
                salary,
                (s) => Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    BarList(
                      rows: [for (final (b, n) in s.bands) (b, n.toDouble())],
                      format: (v) => v.toStringAsFixed(0),
                    ),
                    const SizedBox(height: 8),
                    _kv('Average', Fmt.money(s.average)),
                    _kv('Median', Fmt.money(s.median)),
                    _kv('Lowest – highest', '${Fmt.money(s.min)} – ${Fmt.money(s.max)}'),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            ReportCard(
              title: 'Attendance rate by department · $_year',
              subtitle: 'Share of recorded days with a full day worked',
              child: section(
                rates,
                (rows) => BarList(
                  rows: [for (final r in rows) (r.department, r.ratePercent)],
                  format: (v) => '${v.toStringAsFixed(1)}%',
                  max: 100,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(children: [
          Expanded(child: Text(k, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))),
          Text(v, style: const TextStyle(fontWeight: FontWeight.w600)),
        ]),
      );
}
