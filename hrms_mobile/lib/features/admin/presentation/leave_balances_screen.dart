import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin "Leave Balance": every employee's balances for a year, adjust a
/// balance's entitlement / carry forward, set up balances for employees
/// who have none yet.
class LeaveBalancesScreen extends ConsumerStatefulWidget {
  const LeaveBalancesScreen({super.key});

  @override
  ConsumerState<LeaveBalancesScreen> createState() => _LeaveBalancesScreenState();
}

class _LeaveBalancesScreenState extends ConsumerState<LeaveBalancesScreen> {
  int _year = DateTime.now().year;
  String _query = '';
  int? _settingUp;

  @override
  Widget build(BuildContext context) {
    final rows = ref.watch(allLeaveBalancesProvider(_year));
    final employees = ref.watch(employeesProvider).valueOrNull ?? const <EmployeeSummary>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave balances')),
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
                onPressed: _year > DateTime.now().year ? null : () => setState(() => _year++),
                icon: const Icon(Icons.chevron_right),
              ),
            ]),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: const InputDecoration(
                hintText: 'Search employee',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          Expanded(
            child: rows.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  ErrorView(error: e, onRetry: () => ref.invalidate(allLeaveBalancesProvider(_year))),
              data: (all) {
                // Group by employee; active employees with no balances get a set-up card.
                final byEmployee = <int, List<LeaveBalanceRow>>{};
                for (final r in all) {
                  byEmployee.putIfAbsent(r.employeeId, () => []).add(r);
                }
                final missing = employees
                    .where((e) => e.isActive && !byEmployee.containsKey(e.id))
                    .where((e) => _query.isEmpty || e.name.toLowerCase().contains(_query))
                    .toList();
                final groups = byEmployee.values
                    .where((g) => _query.isEmpty || g.first.employeeName.toLowerCase().contains(_query))
                    .toList();

                if (groups.isEmpty && missing.isEmpty) {
                  return Center(
                    child: Text('No leave balances for $_year',
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  );
                }
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(allLeaveBalancesProvider(_year).future),
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      for (final e in missing)
                        Card(
                          child: ListTile(
                            title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text('No leave balances for $_year'),
                            trailing: _settingUp == e.id
                                ? const SizedBox(
                                    width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                                : TextButton(
                                    onPressed: _settingUp == null ? () => _setUp(e) : null,
                                    child: const Text('Set up'),
                                  ),
                          ),
                        ),
                      for (final g in groups) ...[
                        const SizedBox(height: 8),
                        _EmployeeBalances(rows: g, onEdit: _edit),
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

  Future<void> _setUp(EmployeeSummary e) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _settingUp = e.id);
    try {
      await ref.read(adminRepositoryProvider).initializeLeaveBalances(e.id, _year);
      ref.invalidate(allLeaveBalancesProvider(_year));
      messenger.showSnackBar(SnackBar(content: Text('Leave balances set up for ${e.name}')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(err).message)));
    } finally {
      if (mounted) setState(() => _settingUp = null);
    }
  }

  Future<void> _edit(LeaveBalanceRow r) async {
    final result = await showModalBottomSheet<(double, double)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditSheet(row: r),
    );
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(adminRepositoryProvider).updateLeaveBalance(r.id, result.$1, result.$2);
      ref.invalidate(allLeaveBalancesProvider(_year));
      ref.invalidate(employeeLeaveBalancesProvider(r.employeeId));
      messenger.showSnackBar(SnackBar(content: Text('${r.leaveTypeName} updated for ${r.employeeName}')));
    } catch (err) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(err).message)));
    }
  }
}

class _EmployeeBalances extends StatelessWidget {
  const _EmployeeBalances({required this.rows, required this.onEdit});

  final List<LeaveBalanceRow> rows;
  final ValueChanged<LeaveBalanceRow> onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = rows.first;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        shape: const Border(),
        title: Text(first.employeeName, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(
          '${first.employeeCode ?? ''}  ·  ${rows.length} leave types',
          style: theme.textTheme.bodySmall,
        ),
        children: [
          for (final r in rows)
            ListTile(
              dense: true,
              onTap: () => onEdit(r),
              title: Text(r.leaveTypeName),
              subtitle: Text('${Fmt.days(r.usedDays)} used of ${Fmt.days(r.totalDays)}'
                  '${r.carryForwardDays > 0 ? ' + ${Fmt.days(r.carryForwardDays)} carried' : ''}'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${Fmt.days(r.balanceDays)} left',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  const SizedBox(width: 4),
                  const Icon(Icons.edit_outlined, size: 18),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Edit entitlement and carry forward. Pops (totalDays, carryForwardDays).
class _EditSheet extends StatefulWidget {
  const _EditSheet({required this.row});

  final LeaveBalanceRow row;

  @override
  State<_EditSheet> createState() => _EditSheetState();
}

class _EditSheetState extends State<_EditSheet> {
  late final _total = TextEditingController(text: _fmt(widget.row.totalDays));
  late final _carry = TextEditingController(text: _fmt(widget.row.carryForwardDays));

  static String _fmt(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : '$v';

  @override
  void dispose() {
    _total.dispose();
    _carry.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    final total = double.tryParse(_total.text);
    final carry = double.tryParse(_carry.text.isEmpty ? '0' : _carry.text);
    final valid = total != null && total >= 0 && carry != null && carry >= 0;
    final newBalance = valid ? r.balanceFor(total, carry) : null;
    final theme = Theme.of(context);
    final formatters = [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}'))];

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('${r.leaveTypeName} — ${r.employeeName}',
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('${Fmt.days(r.usedDays)} already used', style: theme.textTheme.bodySmall),
          const SizedBox(height: 16),
          TextField(
            controller: _total,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: formatters,
            decoration: const InputDecoration(labelText: 'Entitlement (days)'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _carry,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: formatters,
            decoration: const InputDecoration(labelText: 'Carried forward (days)'),
          ),
          const SizedBox(height: 12),
          if (newBalance != null)
            Text('New balance: ${Fmt.days(newBalance)}',
                style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: newBalance < 0 ? theme.colorScheme.error : null)),
          const SizedBox(height: 12),
          FilledButton(
            onPressed: valid ? () => Navigator.pop(context, (total, carry)) : null,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
