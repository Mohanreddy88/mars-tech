import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../data/payslip_models.dart';
import '../data/payslip_repository.dart';

/// One payslip: net pay, earnings, deductions, employer contributions,
/// and PDF actions (view, share, email to me).
class PayslipDetailScreen extends ConsumerStatefulWidget {
  const PayslipDetailScreen({super.key, required this.payslipId});

  final int payslipId;

  @override
  ConsumerState<PayslipDetailScreen> createState() =>
      _PayslipDetailScreenState();
}

enum _PdfAction { view, share, email }

class _PayslipDetailScreenState extends ConsumerState<PayslipDetailScreen> {
  _PdfAction? _busy;

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(payslipDetailProvider(widget.payslipId));

    return Scaffold(
      appBar: AppBar(
        title: Text(detail.valueOrNull?.monthName ?? 'Payslip'),
      ),
      body: detail.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () =>
              ref.invalidate(payslipDetailProvider(widget.payslipId)),
        ),
        data: (p) => _Body(payslip: p),
      ),
      bottomNavigationBar: detail.valueOrNull == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: _busy == null
                            ? () => _run(_PdfAction.view, detail.value!)
                            : null,
                        icon: _icon(_PdfAction.view, Icons.picture_as_pdf_outlined),
                        label: const Text('View PDF'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton.outlined(
                      tooltip: 'Share PDF',
                      onPressed: _busy == null
                          ? () => _run(_PdfAction.share, detail.value!)
                          : null,
                      icon: _icon(_PdfAction.share, Icons.share_outlined),
                    ),
                    IconButton.outlined(
                      tooltip: 'Email PDF to me',
                      onPressed: _busy == null
                          ? () => _run(_PdfAction.email, detail.value!)
                          : null,
                      icon: _icon(_PdfAction.email, Icons.email_outlined),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _icon(_PdfAction action, IconData icon) => _busy == action
      ? const SizedBox(
          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
      : Icon(icon);

  Future<void> _run(_PdfAction action, PayslipDetail p) async {
    setState(() => _busy = action);
    final messenger = ScaffoldMessenger.of(context);
    final repo = ref.read(payslipRepositoryProvider);
    try {
      if (action == _PdfAction.email) {
        final message = await repo.emailPdf(p.id);
        messenger.showSnackBar(SnackBar(content: Text(message)));
        return;
      }

      final pdf = await repo.downloadPdf(
        p.id,
        fallbackName: 'Payslip_${p.year}_${p.month.toString().padLeft(2, '0')}.pdf',
      );
      final file = await FileOpener.save(pdf.bytes, pdf.fileName);
      const mime = 'application/pdf';
      final subject = 'Payslip ${p.monthName}';
      if (action == _PdfAction.view) {
        await FileOpener.open(file, mimeType: mime, subject: subject);
      } else {
        await FileOpener.share(file, mimeType: mime, subject: subject);
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }
}

class _Body extends StatelessWidget {
  const _Body({required this.payslip});

  final PayslipDetail payslip;

  @override
  Widget build(BuildContext context) {
    final p = payslip;
    final epfLabel = p.epfEmployeeRate == null
        ? 'EPF'
        : 'EPF (${_rate(p.epfEmployeeRate!)}%)';

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        _NetPayCard(payslip: p),
        const SizedBox(height: 16),
        _Section(
          title: 'Earnings',
          rows: [
            _Line('Basic salary', p.basicSalary),
            _Line('Allowances', p.allowances),
          ],
          totalLabel: 'Gross pay',
          total: p.grossIncome,
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Deductions',
          rows: [
            _Line(epfLabel, p.epf),
            _Line('SOCSO', p.socso),
            _Line('EIS', p.eis),
            _Line('Tax (PCB)', p.tax),
            if (p.otherDeductions > 0)
              _Line('Other (unpaid leave / adjustments)', p.otherDeductions),
          ],
          totalLabel: 'Total deductions',
          total: p.totalDeductions,
          negative: true,
        ),
        const SizedBox(height: 12),
        _Section(
          title: 'Employer contributions',
          subtitle: 'Paid by the company on top of your salary',
          rows: [
            _Line('EPF', p.epfEmployer),
            _Line('SOCSO', p.socsoEmployer),
            _Line('EIS', p.eisEmployer),
          ],
          totalLabel: 'Total',
          total: p.totalEmployerContributions,
        ),
        const SizedBox(height: 12),
        _InfoCard(payslip: p),
      ],
    );
  }

  static String _rate(double v) =>
      v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
}

class _NetPayCard extends StatelessWidget {
  const _NetPayCard({required this.payslip});

  final PayslipDetail payslip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Net pay',
                    style: text.bodyMedium?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.8))),
                const SizedBox(height: 4),
                Text(Fmt.money(payslip.netSalary),
                    style: text.headlineSmall?.copyWith(
                        color: scheme.onPrimary, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (payslip.status.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: scheme.onPrimary.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(payslip.status,
                  style: text.labelMedium?.copyWith(color: scheme.onPrimary)),
            ),
        ],
      ),
    );
  }
}

class _Line {
  const _Line(this.label, this.amount);

  final String label;
  final double amount;
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.rows,
    required this.totalLabel,
    required this.total,
    this.subtitle,
    this.negative = false,
  });

  final String title;
  final String? subtitle;
  final List<_Line> rows;
  final String totalLabel;
  final double total;

  /// Shows amounts with a minus sign (deductions).
  final bool negative;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    String amount(double v) => negative && v > 0 ? '- ${Fmt.money(v)}' : Fmt.money(v);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w600)),
            if (subtitle != null) Text(subtitle!, style: muted),
            const SizedBox(height: 8),
            for (final r in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Expanded(child: Text(r.label)),
                    Text(amount(r.amount)),
                  ],
                ),
              ),
            const Divider(height: 20),
            Row(
              children: [
                Expanded(
                  child: Text(totalLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                ),
                Text(
                  amount(total),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: negative ? theme.colorScheme.error : null,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.payslip});

  final PayslipDetail payslip;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            children: [
              Expanded(child: Text(label, style: muted)),
              Text(value),
            ],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          children: [
            row('Generated on', Fmt.date(payslip.generatedOn)),
            if (payslip.approvedOn != null)
              row('Approved on', Fmt.date(payslip.approvedOn)),
            if (payslip.approverName != null && payslip.approverName!.isNotEmpty)
              row('Approved by', payslip.approverName!),
          ],
        ),
      ),
    );
  }
}
