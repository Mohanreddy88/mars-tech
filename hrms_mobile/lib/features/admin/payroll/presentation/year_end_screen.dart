import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import '../../../../core/widgets/error_view.dart';
import '../data/payroll_admin_models.dart';
import '../data/payroll_admin_repository.dart';

/// "Year-End Reports": year-to-date totals per employee and the EA form
/// (emailed to the employee as a PDF when the year is complete).
class YearEndScreen extends ConsumerStatefulWidget {
  const YearEndScreen({super.key});

  @override
  ConsumerState<YearEndScreen> createState() => _YearEndScreenState();
}

class _YearEndScreenState extends ConsumerState<YearEndScreen> {
  int _year = DateTime.now().year;
  int? _sending;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(yearEndProvider(_year));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Year-end reports')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Row(children: [
              IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
              Expanded(
                child: Text('$_year',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              ),
              IconButton(
                onPressed: _year >= DateTime.now().year ? null : () => setState(() => _year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ),
          Expanded(
            child: list.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(yearEndProvider(_year))),
              data: (items) => items.isEmpty
                  ? Center(
                      child: Text('No payroll records for $_year.',
                          style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: items.length + 1,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (_, i) => i == 0
                          ? Text(
                              'EA forms are available once the year is complete '
                              '(current year: all 12 months processed).',
                              style: theme.textTheme.bodySmall
                                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                          : _EmployeeCard(
                              e: items[i - 1],
                              sending: _sending == items[i - 1].employeeId,
                              onEmail: _sending == null ? () => _emailEa(items[i - 1]) : null,
                            ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _emailEa(YearEndEmployee e) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _sending = e.employeeId);
    try {
      final msg = await ref.read(payrollAdminRepositoryProvider).emailEaForm(e.employeeId, _year);
      messenger.showSnackBar(SnackBar(content: Text(msg)));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(err).message)));
    } finally {
      if (mounted) setState(() => _sending = null);
    }
  }
}

class _EmployeeCard extends StatelessWidget {
  const _EmployeeCard({required this.e, required this.sending, required this.onEmail});

  final YearEndEmployee e;
  final bool sending;
  final VoidCallback? onEmail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    Widget fig(String label, double v) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [Text(label, style: muted), Text(Fmt.money(v), style: const TextStyle(fontWeight: FontWeight.w600))],
          ),
        );

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(e.employeeName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      Text([e.employeeCode, e.departmentName].where((s) => s?.isNotEmpty ?? false).join(' · '),
                          style: muted),
                    ],
                  ),
                ),
                Text('${e.monthsProcessed} month${e.monthsProcessed == 1 ? '' : 's'}', style: muted),
              ],
            ),
            const SizedBox(height: 10),
            Row(children: [fig('Gross', e.ytdGross), fig('Net', e.ytdNet), fig('Tax (PCB)', e.ytdTax)]),
            const SizedBox(height: 6),
            Row(children: [fig('EPF', e.ytdEpf), fig('SOCSO', e.ytdSocso), fig('EIS', e.ytdEis)]),
            const SizedBox(height: 6),
            if (e.isEaReady)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: e.hasEmail ? onEmail : null,
                  icon: sending
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.email_outlined),
                  label: Text(e.hasEmail ? 'Email EA form' : 'No email on file'),
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(top: 4, bottom: 4),
                child: Text(e.notReadyReason ?? 'EA form not ready yet', style: muted),
              ),
          ],
        ),
      ),
    );
  }
}
