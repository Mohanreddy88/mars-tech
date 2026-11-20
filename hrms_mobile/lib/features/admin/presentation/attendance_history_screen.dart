import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin "Attendance History": every attendance period, filtered by status
/// and employee. Tap to review (approve / reject when still Submitted).
class AttendanceHistoryScreen extends ConsumerStatefulWidget {
  const AttendanceHistoryScreen({super.key});

  @override
  ConsumerState<AttendanceHistoryScreen> createState() => _AttendanceHistoryScreenState();
}

class _AttendanceHistoryScreenState extends ConsumerState<AttendanceHistoryScreen> {
  static const _statuses = ['All', 'Submitted', 'Approved', 'Rejected', 'Draft'];
  String _status = 'All';
  int? _employeeId;

  String? get _statusParam => _status == 'All' ? null : _status;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(attendanceHistoryProvider(_statusParam));
    final employees = ref.watch(employeesProvider).valueOrNull ?? const <EmployeeSummary>[];
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance history')),
      body: Column(
        children: [
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                for (final s in _statuses)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(s),
                      selected: _status == s,
                      onSelected: (_) => setState(() => _status = s),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: DropdownButtonFormField<int?>(
              initialValue: _employeeId,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Employee',
                prefixIcon: Icon(Icons.person_search_outlined),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem<int?>(value: null, child: Text('All employees')),
                for (final e in employees) DropdownMenuItem<int?>(value: e.id, child: Text(e.name)),
              ],
              onChanged: (v) => setState(() => _employeeId = v),
            ),
          ),
          Expanded(
            child: list.when(
              skipLoadingOnRefresh: true,
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => ErrorView(
                  error: e, onRetry: () => ref.invalidate(attendanceHistoryProvider(_statusParam))),
              data: (all) {
                final shown =
                    _employeeId == null ? all : all.where((p) => p.employeeId == _employeeId).toList();
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(attendanceHistoryProvider(_statusParam).future),
                  child: shown.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Center(
                              child: Text('No attendance periods',
                                  style: theme.textTheme.bodyLarge
                                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ),
                          ],
                        )
                      : ListView.separated(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _Tile(
                            p: shown[i],
                            onTap: () async {
                              final decided = await context
                                  .push<bool>('${Routes.attendanceReview}/${shown[i].id}');
                              if (decided == true) {
                                ref.invalidate(attendanceHistoryProvider(_statusParam));
                                ref.invalidate(pendingAttendanceProvider);
                                ref.invalidate(adminDashboardProvider);
                              }
                            },
                          ),
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

class _Tile extends StatelessWidget {
  const _Tile({required this.p, required this.onTap});

  final AttendanceHistoryItem p;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final h = p.totalHours;
    final details = [
      '${h == h.roundToDouble() ? h.toStringAsFixed(0) : h} h',
      if (p.leaveCount > 0) '${p.leaveCount} leave',
      if (p.status == 'Approved' && p.approvedAt != null) 'approved ${Fmt.shortDate(p.approvedAt)}',
      if (p.status == 'Submitted' && p.submittedAt != null) 'sent ${Fmt.shortDate(p.submittedAt)}',
    ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.employeeName,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                    Text(p.label, style: theme.textTheme.bodyMedium),
                    Text(details,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    if (p.status == 'Rejected' && (p.rejectionReason?.isNotEmpty ?? false))
                      Text('Reason: ${p.rejectionReason}',
                          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error)),
                  ],
                ),
              ),
              StatusChip(p.status),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }
}
