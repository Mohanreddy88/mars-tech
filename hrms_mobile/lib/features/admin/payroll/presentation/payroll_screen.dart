import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../data/admin_repository.dart';
import '../data/payroll_admin_models.dart';
import '../data/payroll_admin_repository.dart';

/// The month shown on the Payroll tab (kept while moving between pages).
final selectedPayMonthProvider = StateProvider<PayMonth>((ref) => PayMonth.now());

/// Admin "Payroll Processing": one month's payslips, status summary,
/// approve-all / process-all, and links to Generate, Salary Release and
/// Year-End.
class PayrollScreen extends ConsumerStatefulWidget {
  const PayrollScreen({super.key});

  @override
  ConsumerState<PayrollScreen> createState() => _PayrollScreenState();
}

class _PayrollScreenState extends ConsumerState<PayrollScreen> {
  static const _filters = ['All', 'Draft', 'Approved', 'Processed', 'Rejected'];
  String _filter = 'All';
  String? _bulkBusy;

  void _refresh(PayMonth m) {
    ref.invalidate(payrollMonthProvider(m));
    ref.invalidate(adminDashboardProvider);
  }

  @override
  Widget build(BuildContext context) {
    final month = ref.watch(selectedPayMonthProvider);
    final records = ref.watch(payrollMonthProvider(month));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Payroll'),
        actions: [
          IconButton(
            tooltip: 'Salary release',
            icon: const Icon(Icons.account_balance_outlined),
            onPressed: () => context.push(Routes.salaryRelease),
          ),
          IconButton(
            tooltip: 'Year-end reports',
            icon: const Icon(Icons.summarize_outlined),
            onPressed: () => context.push(Routes.yearEnd),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final generated = await context.push<bool>(Routes.generatePayroll);
          if (generated == true) _refresh(ref.read(selectedPayMonthProvider));
        },
        icon: const Icon(Icons.add),
        label: const Text('Generate'),
      ),
      body: Column(
        children: [
          _MonthSwitcher(
            month: month,
            onChanged: (m) => ref.read(selectedPayMonthProvider.notifier).state = m,
          ),
          Expanded(
            child: records.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e, onRetry: () => _refresh(month)),
              data: (all) {
                final shown =
                    _filter == 'All' ? all : all.where((r) => r.status == _filter).toList();
                final drafts = all.where((r) => r.status == 'Draft').toList();
                final approved = all.where((r) => r.status == 'Approved').toList();

                return RefreshIndicator(
                  onRefresh: () async => _refresh(month),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    children: [
                      _Summary(records: all),
                      if (drafts.isNotEmpty || approved.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            if (drafts.isNotEmpty)
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _bulkBusy == null
                                      ? () => _bulk('approve', drafts, month)
                                      : null,
                                  icon: _bulkBusy == 'approve'
                                      ? const SizedBox(
                                          width: 16, height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.done_all),
                                  label: Text('Approve ${drafts.length}'),
                                ),
                              ),
                            if (drafts.isNotEmpty && approved.isNotEmpty) const SizedBox(width: 10),
                            if (approved.isNotEmpty)
                              Expanded(
                                child: FilledButton.tonalIcon(
                                  onPressed: _bulkBusy == null
                                      ? () => _bulk('process', approved, month)
                                      : null,
                                  icon: _bulkBusy == 'process'
                                      ? const SizedBox(
                                          width: 16, height: 16,
                                          child: CircularProgressIndicator(strokeWidth: 2))
                                      : const Icon(Icons.payments_outlined),
                                  label: Text('Process ${approved.length}'),
                                ),
                              ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 44,
                        child: ListView(
                          scrollDirection: Axis.horizontal,
                          children: [
                            for (final f in _filters)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  label: Text(f),
                                  selected: f == _filter,
                                  onSelected: (_) => setState(() => _filter = f),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      if (all.isEmpty)
                        _Empty(month: month)
                      else if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Text('No ${_filter.toLowerCase()} payslips.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        )
                      else
                        for (final r in shown) ...[
                          _RecordCard(
                            record: r,
                            onTap: () async {
                              final changed =
                                  await context.push<bool>('${Routes.payrollRecord}/${r.id}');
                              if (changed == true) _refresh(month);
                            },
                          ),
                          const SizedBox(height: 8),
                        ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Approve every draft, or process every approved payslip, of the month.
  Future<void> _bulk(String action, List<PayrollRecord> items, PayMonth m) async {
    final approve = action == 'approve';
    final total = items.fold<double>(0, (s, r) => s + r.netSalary);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(approve ? 'Approve ${items.length} payslips?' : 'Process ${items.length} payslips?'),
        content: Text(approve
            ? 'All draft payslips for ${m.label} (net ${Fmt.money(total)}) will be approved.'
            : 'Marks ${items.length} approved payslips for ${m.label} as processed (paid), '
                'net ${Fmt.money(total)}. Processed payslips can no longer be changed.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(approve ? 'Approve all' : 'Process all')),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(payrollAdminRepositoryProvider);
    setState(() => _bulkBusy = action);
    var done = 0;
    final failed = <String>[];
    for (final r in items) {
      try {
        approve ? await repo.approve(r.id) : await repo.process(r.id);
        done++;
      } catch (e) {
        failed.add('${r.employeeName}: ${ApiException.from(e).message}');
      }
    }
    if (!mounted) return;
    setState(() => _bulkBusy = null);
    _refresh(m);
    messenger.showSnackBar(SnackBar(
      duration: Duration(seconds: failed.isEmpty ? 4 : 8),
      content: Text('${approve ? 'Approved' : 'Processed'} $done of ${items.length}'
          '${failed.isEmpty ? '' : '\n${failed.join('\n')}'}'),
    ));
  }
}

class _MonthSwitcher extends StatelessWidget {
  const _MonthSwitcher({required this.month, required this.onChanged});

  final PayMonth month;
  final ValueChanged<PayMonth> onChanged;

  @override
  Widget build(BuildContext context) {
    final isCurrentOrLater = !DateTime(month.year, month.month)
        .isBefore(DateTime(DateTime.now().year, DateTime.now().month));
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Previous month',
            onPressed: () => onChanged(month.previous),
            icon: const Icon(Icons.chevron_left),
          ),
          Expanded(
            child: Text(month.label,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          ),
          IconButton(
            tooltip: 'Next month',
            onPressed: isCurrentOrLater ? null : () => onChanged(month.next),
            icon: const Icon(Icons.chevron_right),
          ),
        ],
      ),
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.records});

  final List<PayrollRecord> records;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final net = records.fold<double>(0, (s, r) => s + r.netSalary);
    final gross = records.fold<double>(0, (s, r) => s + r.grossIncome);
    final byStatus = <String, int>{};
    for (final r in records) {
      byStatus[r.status] = (byStatus[r.status] ?? 0) + 1;
    }
    final soft = scheme.onPrimary.withValues(alpha: 0.8);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net payroll', style: text.bodyMedium?.copyWith(color: soft)),
          Text(Fmt.money(net),
              style: text.headlineSmall?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('${records.length} payslips · gross ${Fmt.money(gross)}',
              style: text.bodySmall?.copyWith(color: soft)),
          if (byStatus.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in byStatus.entries) StatusChip(e.key, label: '${e.key} ${e.value}'),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onTap});

  final PayrollRecord record;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = record;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              CircleAvatar(
                child: Text(r.employeeName.isEmpty ? '?' : r.employeeName[0].toUpperCase()),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.employeeName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(
                      [r.employeeCode, 'Gross ${Fmt.money(r.grossIncome)}']
                          .where((s) => s?.isNotEmpty ?? false)
                          .join(' · '),
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Fmt.money(r.netSalary),
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  StatusChip(r.status),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.month});

  final PayMonth month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 16),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 48, color: theme.colorScheme.primary),
          const SizedBox(height: 12),
          Text('No payroll for ${month.label} yet', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Use Generate to create payslips from approved attendance.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
