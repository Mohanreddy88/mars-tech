import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/back_to_home.dart';
import '../../../core/widgets/error_view.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin employee directory: search by name / code / email / department,
/// filter active or inactive. Tap for details.
class EmployeesScreen extends ConsumerStatefulWidget {
  const EmployeesScreen({super.key});

  @override
  ConsumerState<EmployeesScreen> createState() => _EmployeesScreenState();
}

class _EmployeesScreenState extends ConsumerState<EmployeesScreen> {
  String _query = '';
  bool? _active = true; // true = active, false = inactive, null = all

  @override
  Widget build(BuildContext context) {
    final employees = ref.watch(employeesProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(leading: const BackToHomeButton(), title: const Text('Employees')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push(Routes.employeeForm),
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add employee'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              onChanged: (v) => setState(() => _query = v),
              decoration: const InputDecoration(
                hintText: 'Search name, code, email, department',
                prefixIcon: Icon(Icons.search),
                isDense: true,
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final (label, value) in const [('Active', true), ('Inactive', false), ('All', null)])
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(label),
                      selected: _active == value,
                      onSelected: (_) => setState(() => _active = value),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: employees.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) =>
                  ErrorView(error: e, onRetry: () => ref.invalidate(employeesProvider)),
              data: (all) {
                final shown = all
                    .where((e) => _active == null || e.isActive == _active)
                    .where((e) => e.matches(_query))
                    .toList();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(employeesProvider.future),
                  child: shown.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Text('No employees found',
                                  style: theme.textTheme.bodyLarge
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                          itemCount: shown.length + 1,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => i == 0
                              ? Text('${shown.length} of ${all.length}',
                                  style: theme.textTheme.bodySmall
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant))
                              : _EmployeeTile(shown[i - 1]),
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _EmployeeTile extends StatelessWidget {
  const _EmployeeTile(this.e);

  final EmployeeSummary e;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final job = [e.designation, e.departmentName].where((s) => s?.isNotEmpty ?? false).join(' · ');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        onTap: () => context.push(Routes.employeeDetail, extra: e),
        leading: CircleAvatar(
          backgroundColor:
              e.isActive ? theme.colorScheme.primaryContainer : theme.colorScheme.surfaceContainerHighest,
          child: Text(e.name.isEmpty ? '?' : e.name[0].toUpperCase()),
        ),
        title: Text(e.name, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text([e.employeeCode, job].where((s) => s?.isNotEmpty ?? false).join('  ·  '),
            maxLines: 1, overflow: TextOverflow.ellipsis),
        trailing: e.isActive
            ? const Icon(Icons.chevron_right)
            : Text('Inactive',
                style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.error)),
      ),
    );
  }
}
