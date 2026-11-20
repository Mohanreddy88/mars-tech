import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/file_opener.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../presentation/approvals_screen.dart' show askComment;
import '../data/payroll_admin_models.dart';
import '../data/payroll_admin_repository.dart';

/// One payslip (admin): breakdown, attendance/leave used, adjustments and
/// the workflow actions (approve, reject, process, delete, PDF, email).
/// Pops `true` when anything changed.
class PayrollRecordScreen extends ConsumerStatefulWidget {
  const PayrollRecordScreen({super.key, required this.payrollId});

  final int payrollId;

  @override
  ConsumerState<PayrollRecordScreen> createState() => _PayrollRecordScreenState();
}

class _PayrollRecordScreenState extends ConsumerState<PayrollRecordScreen> {
  bool _busy = false;
  bool _changed = false;

  PayrollAdminRepository get _repo => ref.read(payrollAdminRepositoryProvider);

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(payrollDetailProvider(widget.payrollId));
    final p = detail.valueOrNull;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_changed);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(p == null ? 'Payslip' : '${p.employeeName} · ${p.monthYear}'),
          actions: [
            if (p != null)
              PopupMenuButton<String>(
                enabled: !_busy,
                onSelected: (v) => switch (v) {
                  'pdf' => _pdf(p),
                  'email' => _email(p),
                  'delete' => _delete(p),
                  _ => null,
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'pdf', child: ListTile(
                      leading: Icon(Icons.picture_as_pdf_outlined), title: Text('View PDF'))),
                  const PopupMenuItem(value: 'email', child: ListTile(
                      leading: Icon(Icons.email_outlined), title: Text('Email to employee'))),
                  if (PayrollStatus.canEdit(p.status))
                    const PopupMenuItem(value: 'delete', child: ListTile(
                        leading: Icon(Icons.delete_outline), title: Text('Delete payslip'))),
                ],
              ),
          ],
        ),
        body: detail.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(
              error: e, onRetry: () => ref.invalidate(payrollDetailProvider(widget.payrollId))),
          data: (p) => _Body(
            p: p,
            busy: _busy,
            onAddAdjustment: () => _addAdjustment(p),
            onDeleteAdjustment: (a) => _deleteAdjustment(p, a),
          ),
        ),
        bottomNavigationBar: p == null ? null : _actions(p),
      ),
    );
  }

  Widget? _actions(PayrollRecord p) {
    final buttons = <Widget>[
      if (PayrollStatus.canReject(p.status))
        Expanded(
          child: OutlinedButton(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: _busy ? null : () => _reject(p),
            child: const Text('Reject'),
          ),
        ),
      if (PayrollStatus.canApprove(p.status))
        Expanded(
          child: FilledButton(
            onPressed: _busy ? null : () => _approve(p),
            child: const Text('Approve'),
          ),
        ),
      if (PayrollStatus.canProcess(p.status))
        Expanded(
          child: FilledButton.icon(
            onPressed: _busy ? null : () => _process(p),
            icon: const Icon(Icons.payments_outlined),
            label: const Text('Mark processed'),
          ),
        ),
    ];
    if (buttons.isEmpty) return null;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: _busy
            ? const SizedBox(height: 52, child: Center(child: CircularProgressIndicator()))
            : Row(
                children: [
                  for (var i = 0; i < buttons.length; i++) ...[
                    if (i > 0) const SizedBox(width: 12),
                    buttons[i],
                  ],
                ],
              ),
      ),
    );
  }

  Future<void> _run(Future<Object?> Function() action, String done, {bool close = false}) async {
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _busy = true);
    try {
      final result = await action();
      _changed = true;
      messenger.showSnackBar(SnackBar(content: Text(result is String ? result : done)));
      if (close) {
        navigator.pop(true);
        return;
      }
      ref.invalidate(payrollDetailProvider(widget.payrollId));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _approve(PayrollRecord p) async {
    final remarks = await askComment(context,
        title: 'Approve ${p.employeeName}\'s payslip?', action: 'Approve', required: false);
    if (remarks == null) return;
    await _run(() => _repo.approve(p.id, remarks: remarks.isEmpty ? null : remarks), 'Payslip approved');
  }

  Future<void> _reject(PayrollRecord p) async {
    final reason = await askComment(context,
        title: 'Reject ${p.employeeName}\'s payslip?', action: 'Reject', required: true);
    if (reason == null) return;
    await _run(() => _repo.reject(p.id, reason), 'Payslip rejected');
  }

  Future<void> _process(PayrollRecord p) async {
    final ok = await _confirm('Mark as processed?',
        'Net ${Fmt.money(p.netSalary)} for ${p.employeeName}, ${p.monthYear}. '
        'A processed payslip is final and can no longer be changed.', 'Mark processed');
    if (ok) await _run(() => _repo.process(p.id), 'Payslip processed');
  }

  Future<void> _delete(PayrollRecord p) async {
    final ok = await _confirm('Delete this payslip?',
        '${p.employeeName}, ${p.monthYear}. You can generate it again afterwards.', 'Delete');
    if (ok) await _run(() => _repo.delete(p.id), 'Payslip deleted', close: true);
  }

  Future<void> _email(PayrollRecord p) =>
      _run(() => _repo.emailPayslip(p.id), 'Payslip emailed');

  Future<void> _pdf(PayrollRecord p) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await _repo.payslipPdf(p.id);
      final name = 'Payslip_${p.employeeName.replaceAll(' ', '_')}_${p.year}_'
          '${p.month.toString().padLeft(2, '0')}.pdf';
      final file = await FileOpener.save(bytes, name);
      await FileOpener.open(file, mimeType: 'application/pdf', subject: 'Payslip ${p.monthYear}');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _addAdjustment(PayrollRecord p) async {
    final added = await showModalBottomSheet<(String, String, double)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AdjustmentSheet(),
    );
    if (added == null) return;
    final (type, description, amount) = added;
    await _run(() => _repo.addAdjustment(p.id, type, description, amount), 'Adjustment added');
  }

  Future<void> _deleteAdjustment(PayrollRecord p, PayrollAdjustmentItem a) async {
    final ok = await _confirm('Remove adjustment?', '${a.type}: ${a.description} (${Fmt.money(a.amount)})', 'Remove');
    if (ok) await _run(() => _repo.deleteAdjustment(p.id, a.id), 'Adjustment removed');
  }

  Future<bool> _confirm(String title, String body, String action) async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
          ],
        ),
      ) ??
      false;
}

class _Body extends StatelessWidget {
  const _Body({
    required this.p,
    required this.busy,
    required this.onAddAdjustment,
    required this.onDeleteAdjustment,
  });

  final PayrollRecord p;
  final bool busy;
  final VoidCallback onAddAdjustment;
  final ValueChanged<PayrollAdjustmentItem> onDeleteAdjustment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final text = theme.textTheme;
    final editable = PayrollStatus.canEdit(p.status);
    String rate(double? v) =>
        v == null ? '' : ' (${v == v.roundToDouble() ? v.toStringAsFixed(0) : v}%)';
    String h(double? v) => v == null ? '—' : (v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v');

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Net pay', style: text.bodyMedium?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
                    Text(Fmt.money(p.netSalary),
                        style: text.headlineSmall?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
                    if (p.employeeCode != null)
                      Text(p.employeeCode!,
                          style: text.bodySmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              StatusChip(p.status),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _Lines('Earnings', [
          ('Basic salary${p.isProrated ? ' (prorated ${p.proratedDays}/${p.totalMonthDays} days)' : ''}', p.basicSalary, false),
          ('Allowances', p.allowances, false),
        ], 'Gross pay', p.grossIncome),
        const SizedBox(height: 12),
        _Lines('Deductions', [
          ('EPF${rate(p.epfEmployeeRate)}', p.epf, true),
          ('SOCSO', p.socso, true),
          ('EIS', p.eis, true),
          ('Tax (PCB)', p.tax, true),
          if (p.otherDeductions > 0) ('Other (unpaid leave / adjustments)', p.otherDeductions, true),
        ], 'Total deductions', -p.totalDeductions),
        const SizedBox(height: 12),
        _Lines('Employer contributions', [
          ('EPF${rate(p.epfEmployerRate)}', p.epfEmployer, false),
          ('SOCSO', p.socsoEmployer, false),
          ('EIS', p.eisEmployer, false),
        ], 'Total', p.employerContributions),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('Adjustments',
                          style: text.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    ),
                    if (editable)
                      TextButton.icon(
                        onPressed: busy ? null : onAddAdjustment,
                        icon: const Icon(Icons.add),
                        label: const Text('Add'),
                      ),
                  ],
                ),
                if (p.adjustments.isEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Text('None', style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)),
                  ),
                for (final a in p.adjustments)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: Text('${a.type}: ${a.description}'),
                    subtitle: a.createdBy == null ? null : Text('by ${a.createdBy}'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('${a.isDeduction ? '- ' : '+ '}${Fmt.money(a.amount)}',
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: a.isDeduction ? scheme.error : const Color(0xFF15803D))),
                        if (editable)
                          IconButton(
                            tooltip: 'Remove',
                            onPressed: busy ? null : () => onDeleteAdjustment(a),
                            icon: const Icon(Icons.close, size: 18),
                          ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        _Info([
          ('Hours worked', '${h(p.attendanceHours)} of ${h(p.expectedHours)} expected'),
          if ((p.paidLeaveDays ?? 0) > 0 || (p.unpaidLeaveDays ?? 0) > 0)
            ('Leave days', '${p.paidLeaveDays ?? 0} paid · ${p.unpaidLeaveDays ?? 0} unpaid'),
          for (final l in p.leaveLines) ('Leave', l),
          if (p.statutoryRateSetName != null) ('Statutory rates', p.statutoryRateSetName!),
          ('Generated', Fmt.date(p.generatedOn)),
          if (p.approvedOn != null) ('Approved', '${Fmt.date(p.approvedOn)}${p.approverName != null ? ' by ${p.approverName}' : ''}'),
          if (p.processedOn != null) ('Processed', '${Fmt.date(p.processedOn)}${p.processorName != null ? ' by ${p.processorName}' : ''}'),
          if (p.remarks?.isNotEmpty ?? false) ('Remarks', p.remarks!),
        ]),
      ],
    );
  }
}

class _Lines extends StatelessWidget {
  const _Lines(this.title, this.rows, this.totalLabel, this.total);

  final String title;

  /// (label, amount, isDeduction)
  final List<(String, double, bool)> rows;
  final String totalLabel;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String amount(double v, bool minus) => minus && v > 0 ? '- ${Fmt.money(v)}' : Fmt.money(v);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (final (label, value, minus) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [Expanded(child: Text(label)), Text(amount(value, minus))]),
              ),
            const Divider(height: 18),
            Row(children: [
              Expanded(child: Text(totalLabel, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(total < 0 ? '- ${Fmt.money(-total)}' : Fmt.money(total),
                  style: TextStyle(
                      fontWeight: FontWeight.w700, color: total < 0 ? theme.colorScheme.error : null)),
            ]),
          ],
        ),
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info(this.rows);

  final List<(String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final muted = TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          children: [
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(label, style: muted)),
                    Expanded(child: Text(value, textAlign: TextAlign.right)),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet: type, description, amount. Pops (type, description, amount).
class _AdjustmentSheet extends StatefulWidget {
  const _AdjustmentSheet();

  @override
  State<_AdjustmentSheet> createState() => _AdjustmentSheetState();
}

class _AdjustmentSheetState extends State<_AdjustmentSheet> {
  String _type = PayrollAdjustmentItem.types.first;
  final _desc = TextEditingController();
  final _amount = TextEditingController();

  @override
  void dispose() {
    _desc.dispose();
    _amount.dispose();
    super.dispose();
  }

  double? get _value => double.tryParse(_amount.text.trim());

  @override
  Widget build(BuildContext context) {
    final valid = _desc.text.trim().isNotEmpty && (_value ?? 0) > 0;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add adjustment',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: [
              for (final t in PayrollAdjustmentItem.types)
                ChoiceChip(
                  label: Text(t),
                  selected: _type == t,
                  onSelected: (_) => setState(() => _type = t),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _desc,
            onChanged: (_) => setState(() {}),
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _amount,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}'))],
            decoration: const InputDecoration(labelText: 'Amount', prefixText: 'RM '),
          ),
          const SizedBox(height: 8),
          Text(
            _type == 'Deduction' ? 'Reduces net pay.' : 'Added to pay.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: valid ? () => Navigator.pop(context, (_type, _desc.text.trim(), _value!)) : null,
            child: const Text('Add'),
          ),
        ],
      ),
    );
  }
}
