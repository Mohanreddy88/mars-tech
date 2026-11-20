import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/error_view.dart';
import '../../data/admin_models.dart';
import '../../data/admin_repository.dart';
import '../data/payroll_admin_models.dart';
import '../data/payroll_admin_repository.dart';
import 'payroll_screen.dart' show selectedPayMonthProvider;

/// "Generate Payslip": for the chosen month, every active employee with
/// their eligibility (approved attendance, no pending leave, not already
/// generated); select and generate. Pops `true` when payslips were created.
class GeneratePayrollScreen extends ConsumerStatefulWidget {
  const GeneratePayrollScreen({super.key});

  @override
  ConsumerState<GeneratePayrollScreen> createState() => _GeneratePayrollScreenState();
}

class _GeneratePayrollScreenState extends ConsumerState<GeneratePayrollScreen> {
  late PayMonth _month = ref.read(selectedPayMonthProvider);
  final Map<int, PayrollEligibility?> _eligibility = {}; // null = checking
  final Set<int> _selected = {};
  bool _generating = false;
  bool _generatedAny = false;

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider);
    final existing = ref.watch(payrollMonthProvider(_month));
    final theme = Theme.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.of(context).pop(_generatedAny);
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Generate payslips')),
        body: employees.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(employeesProvider)),
          data: (all) {
            final active = all.where((e) => e.isActive).toList();
            final done = {for (final r in existing.valueOrNull ?? const <PayrollRecord>[]) r.employeeId};
            _checkEligibility(active.where((e) => !done.contains(e.id)));
            final selectable = active
                .where((e) => !done.contains(e.id) && (_eligibility[e.id]?.isEligible ?? false))
                .map((e) => e.id)
                .toSet();
            _selected.removeWhere((id) => !selectable.contains(id));

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _generating ? null : () => _setMonth(_month.previous),
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Expanded(
                        child: Text(_month.label,
                            textAlign: TextAlign.center,
                            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      IconButton(
                        onPressed: _generating ? null : () => _setMonth(_month.next),
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${selectable.length} ready · ${done.length} already generated',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                      TextButton(
                        onPressed: selectable.isEmpty || _generating
                            ? null
                            : () => setState(() => _selected.length == selectable.length
                                ? _selected.clear()
                                : _selected.addAll(selectable)),
                        child: Text(_selected.length == selectable.length && selectable.isNotEmpty
                            ? 'Clear'
                            : 'Select all ready'),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    itemCount: active.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final e = active[i];
                      return _EmployeeRow(
                        employee: e,
                        alreadyGenerated: done.contains(e.id),
                        eligibility: _eligibility[e.id],
                        selected: _selected.contains(e.id),
                        onChanged: selectable.contains(e.id) && !_generating
                            ? (v) => setState(() => v ? _selected.add(e.id) : _selected.remove(e.id))
                            : null,
                      );
                    },
                  ),
                ),
              ],
            );
          },
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
            child: FilledButton.icon(
              onPressed: _selected.isEmpty || _generating ? null : _generate,
              icon: _generating
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.play_arrow),
              label: Text(_selected.isEmpty
                  ? 'Select employees to generate'
                  : 'Generate ${_selected.length} payslip${_selected.length == 1 ? '' : 's'} for ${_month.label}'),
            ),
          ),
        ),
      ),
    );
  }

  void _setMonth(PayMonth m) => setState(() {
        _month = m;
        _eligibility.clear();
        _selected.clear();
      });

  /// Starts an eligibility check for each employee not checked yet this month.
  void _checkEligibility(Iterable<EmployeeSummary> employees) {
    final month = _month;
    for (final e in employees) {
      if (_eligibility.containsKey(e.id)) continue;
      _eligibility[e.id] = null;
      ref.read(payrollAdminRepositoryProvider).eligibility(e.id, month).then((r) {
        if (mounted && _month == month) setState(() => _eligibility[e.id] = r);
      }, onError: (Object err) {
        if (mounted && _month == month) {
          setState(() => _eligibility[e.id] = PayrollEligibility(
              isEligible: false, errors: [ApiException.from(err).message], warnings: const []));
        }
      });
    }
  }

  Future<void> _generate() async {
    final month = _month;
    setState(() => _generating = true);
    try {
      final result = await ref.read(payrollAdminRepositoryProvider).generate(_selected.toList(), month);
      if (result.successCount > 0) _generatedAny = true;
      ref.invalidate(payrollMonthProvider(month));
      ref.invalidate(adminDashboardProvider);
      ref.read(selectedPayMonthProvider.notifier).state = month;
      if (!mounted) return;
      setState(() {
        _generating = false;
        _selected.clear();
      });
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('${result.successCount} generated'
              '${result.failureCount > 0 ? ', ${result.failureCount} failed' : ''}'),
          content: result.errors.isEmpty
              ? Text('Payslips for ${month.label} are ready as Draft. Review and approve them on the Payroll tab.')
              : SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [for (final (name, msg) in result.errors) Text('• $name: $msg')],
                  ),
                ),
          actions: [FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _generating = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    }
  }
}

class _EmployeeRow extends StatelessWidget {
  const _EmployeeRow({
    required this.employee,
    required this.alreadyGenerated,
    required this.eligibility,
    required this.selected,
    required this.onChanged,
  });

  final EmployeeSummary employee;
  final bool alreadyGenerated;

  /// null while the check is still running.
  final PayrollEligibility? eligibility;
  final bool selected;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final String status;
    final Color color;
    if (alreadyGenerated) {
      status = 'Already generated for this month';
      color = scheme.onSurfaceVariant;
    } else if (eligibility == null) {
      status = 'Checking attendance…';
      color = scheme.onSurfaceVariant;
    } else if (eligibility!.isEligible) {
      status = eligibility!.warnings.isEmpty ? 'Ready' : 'Ready · ${eligibility!.warnings.first}';
      color = const Color(0xFF15803D);
    } else {
      status = eligibility!.errors.isEmpty ? 'Not eligible' : eligibility!.errors.first;
      color = scheme.error;
    }

    return Card(
      child: CheckboxListTile(
        value: selected,
        onChanged: onChanged == null ? null : (v) => onChanged!(v ?? false),
        title: Text(employee.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(status, style: TextStyle(color: color)),
        secondary: CircleAvatar(
          child: Text(employee.name.isEmpty ? '?' : employee.name[0].toUpperCase()),
        ),
      ),
    );
  }
}
