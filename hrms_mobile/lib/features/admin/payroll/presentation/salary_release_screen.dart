import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/file_opener.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../data/payroll_admin_models.dart';
import '../data/payroll_admin_repository.dart';
import 'payroll_screen.dart' show selectedPayMonthProvider;

/// "Salary Release": processed payslips of a month, the bank payment file
/// (CSV, shared to email / Drive / banking app) and emailing payslips.
class SalaryReleaseScreen extends ConsumerStatefulWidget {
  const SalaryReleaseScreen({super.key});

  @override
  ConsumerState<SalaryReleaseScreen> createState() => _SalaryReleaseScreenState();
}

class _SalaryReleaseScreenState extends ConsumerState<SalaryReleaseScreen> {
  late PayMonth _month = ref.read(selectedPayMonthProvider);
  String? _busy;

  @override
  Widget build(BuildContext context) {
    final records = ref.watch(payrollMonthProvider(_month));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Salary release')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              IconButton(onPressed: () => setState(() => _month = _month.previous), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text(_month.label,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(onPressed: () => setState(() => _month = _month.next), icon: const Icon(Icons.chevron_right)),
            ]),
          ),
          Expanded(
            child: records.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(payrollMonthProvider(_month))),
              data: (all) {
                final processed = all.where((r) => r.status == 'Processed').toList();
                final notYet = all.length - processed.length;
                final total = processed.fold<double>(0, (s, r) => s + r.netSalary);
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  children: [
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.payments_outlined),
                        title: Text(Fmt.money(total), style: const TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: Text('${processed.length} processed payslip(s) to pay'
                            '${notYet > 0 ? ' · $notYet not processed yet' : ''}'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: processed.isEmpty || _busy != null ? null : _bankFile,
                      icon: _icon('bank', Icons.file_download_outlined),
                      label: const Text('Bank payment file (CSV)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                      onPressed: processed.isEmpty || _busy != null ? null : () => _emailAll(processed),
                      icon: _icon('email', Icons.forward_to_inbox_outlined),
                      label: Text('Email ${processed.length} payslip(s) to employees'),
                    ),
                    const SizedBox(height: 16),
                    if (processed.isEmpty)
                      Text(
                        all.isEmpty
                            ? 'No payroll for ${_month.label}.'
                            : 'Nothing processed yet for ${_month.label}. Approve and process payslips on the Payroll tab first.',
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      )
                    else
                      Card(
                        child: Column(
                          children: [
                            for (final r in processed)
                              ListTile(
                                dense: true,
                                title: Text(r.employeeName),
                                subtitle: Text(r.employeeCode ?? ''),
                                trailing: Text(Fmt.money(r.netSalary),
                                    style: const TextStyle(fontWeight: FontWeight.w600)),
                              ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _icon(String key, IconData icon) => _busy == key
      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(icon);

  Future<void> _bankFile() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = 'bank');
    try {
      final (bytes, problem) = await ref.read(payrollAdminRepositoryProvider).bankExport(_month);
      if (bytes == null) {
        messenger.showSnackBar(SnackBar(content: Text(problem ?? 'Nothing to export')));
      } else {
        final name = 'BankPayment_${_month.year}_${_month.month.toString().padLeft(2, '0')}.csv';
        final file = await FileOpener.save(bytes, name);
        await FileOpener.share(file, mimeType: 'text/csv', subject: 'Bank payment ${_month.label}');
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<void> _emailAll(List<PayrollRecord> processed) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Email ${processed.length} payslip(s)?'),
        content: Text('Each employee receives their ${_month.label} payslip PDF by email.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = 'email');
    try {
      final msg = await ref.read(payrollAdminRepositoryProvider).emailPayslips(processed.map((r) => r.id).toList());
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}
