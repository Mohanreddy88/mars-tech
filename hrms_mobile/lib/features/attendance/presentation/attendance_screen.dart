import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';

/// Attendance tab: half-month periods (newest first) with status and totals.
class AttendanceScreen extends ConsumerWidget {
  const AttendanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final periods = ref.watch(attendancePeriodsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Attendance')),
      body: periods.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(
          error: error,
          onRetry: () => ref.invalidate(attendancePeriodsProvider),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(attendancePeriodsProvider.future),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            itemCount: list.length + 1,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              if (i == 0) return const _Intro();
              final p = list[i - 1];
              return _PeriodCard(
                period: p,
                onTap: () async {
                  final changed = await context.push<bool>(
                      Routes.attendancePeriod, extra: p);
                  if (changed == true) ref.invalidate(attendancePeriodsProvider);
                },
              );
            },
          ),
        ),
      ),
    );
  }
}

class _Intro extends StatelessWidget {
  const _Intro();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      'Fill in your hours (or a leave code) for each day, then submit the '
      'period for approval. Payroll uses approved attendance.',
      style: theme.textTheme.bodySmall
          ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.onTap});

  final AttendancePeriod period;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = period;
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final summary = !p.isSaved
        ? '${p.workingDays} working days to fill in'
        : [
            '${_hours(p.totalHours)} h',
            if (p.leaveDays > 0) '${p.leaveDays} leave',
            if (p.isEditable && p.emptyWorkingDays > 0) '${p.emptyWorkingDays} empty',
          ].join(' · ');

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
          child: Row(
            children: [
              Icon(
                p.status == 'Approved'
                    ? Icons.verified_outlined
                    : p.isEditable
                        ? Icons.edit_calendar_outlined
                        : Icons.event_available_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.label,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(summary, style: muted),
                  ],
                ),
              ),
              StatusChip(p.displayStatus),
              const Icon(Icons.chevron_right),
            ],
          ),
        ),
      ),
    );
  }

  static String _hours(double h) =>
      h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1);
}
