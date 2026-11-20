import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../data/payslip_models.dart';
import '../data/payslip_repository.dart';

/// Payslips tab: year filter, year-to-date totals, one card per month.
class PayslipsScreen extends ConsumerStatefulWidget {
  const PayslipsScreen({super.key});

  @override
  ConsumerState<PayslipsScreen> createState() => _PayslipsScreenState();
}

class _PayslipsScreenState extends ConsumerState<PayslipsScreen> {
  /// Selected year; null until data arrives (then the newest year).
  int? _year;

  @override
  Widget build(BuildContext context) {
    final payslips = ref.watch(payslipsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Payslips')),
      body: payslips.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(payslipsProvider),
        ),
        data: (all) {
          final years = {for (final p in all) p.year}.toList()
            ..sort((a, b) => b.compareTo(a));
          final year =
              (_year != null && years.contains(_year)) ? _year : years.firstOrNull;
          final shown = all.where((p) => p.year == year).toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(payslipsProvider.future),
            child: all.isEmpty
                ? const _EmptyState()
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                    children: [
                      if (years.length > 1)
                        SizedBox(
                          height: 48,
                          child: ListView(
                            scrollDirection: Axis.horizontal,
                            children: [
                              for (final y in years)
                                Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: ChoiceChip(
                                    label: Text('$y'),
                                    selected: y == year,
                                    onSelected: (_) => setState(() => _year = y),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      _YearSummary(year: year!, payslips: shown),
                      const SizedBox(height: 16),
                      for (final p in shown) ...[
                        _PayslipCard(
                          payslip: p,
                          onTap: () =>
                              context.push('${Routes.payslips}/${p.id}'),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ],
                  ),
          );
        },
      ),
    );
  }
}

class _YearSummary extends StatelessWidget {
  const _YearSummary({required this.year, required this.payslips});

  final int year;
  final List<Payslip> payslips;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    double sum(double Function(Payslip) f) =>
        payslips.fold(0, (total, p) => total + f(p));

    final onPrimarySoft = scheme.onPrimary.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: scheme.primary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Net pay in $year',
              style: text.bodyMedium?.copyWith(color: onPrimarySoft)),
          const SizedBox(height: 4),
          Text(Fmt.money(sum((p) => p.netSalary)),
              style: text.headlineSmall?.copyWith(
                  color: scheme.onPrimary, fontWeight: FontWeight.w700)),
          const SizedBox(height: 16),
          Row(
            children: [
              _SummaryFigure('Gross', Fmt.money(sum((p) => p.grossIncome))),
              _SummaryFigure('EPF', Fmt.money(sum((p) => p.epf))),
              _SummaryFigure('Tax (PCB)', Fmt.money(sum((p) => p.tax))),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            '${payslips.length} ${payslips.length == 1 ? 'payslip' : 'payslips'}',
            style: text.bodySmall?.copyWith(color: onPrimarySoft),
          ),
        ],
      ),
    );
  }
}

class _SummaryFigure extends StatelessWidget {
  const _SummaryFigure(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: text.bodySmall
                  ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
          Text(value,
              style: text.bodyMedium?.copyWith(
                  color: scheme.onPrimary, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

class _PayslipCard extends StatelessWidget {
  const _PayslipCard({required this.payslip, required this.onTap});

  final Payslip payslip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Icon(Icons.receipt_long_outlined,
                    color: theme.colorScheme.onPrimaryContainer),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(payslip.monthName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text('Gross ${Fmt.money(payslip.grossIncome)}', style: muted),
                    Text('Deductions ${Fmt.money(payslip.totalDeductions)}',
                        style: muted),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Net', style: muted),
                  Text(Fmt.money(payslip.netSalary),
                      style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary)),
                ],
              ),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // ListView so pull-to-refresh still works on an empty list.
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.receipt_long_outlined,
            size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text('No payslips yet',
            textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(
          'Your payslips will appear here once payroll has been run.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
