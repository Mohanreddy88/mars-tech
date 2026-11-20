import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../../attendance/presentation/day_row.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';
import 'approvals_screen.dart';

/// Admin review of one submitted attendance period: every day, the
/// employee's leave in the period, then approve or reject (with reason).
/// Pops `true` when a decision was made.
class AttendanceReviewScreen extends ConsumerStatefulWidget {
  const AttendanceReviewScreen({super.key, required this.periodId});

  final int periodId;

  @override
  ConsumerState<AttendanceReviewScreen> createState() => _AttendanceReviewScreenState();
}

class _AttendanceReviewScreenState extends ConsumerState<AttendanceReviewScreen> {
  static final _dayFmt = DateFormat('EEE, d MMM');
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final review = ref.watch(attendanceReviewProvider(widget.periodId));
    final r = review.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Text(r?.employeeName ?? 'Attendance'),
        actions: [
          if (r != null)
            IconButton(
              tooltip: 'Download PDF',
              onPressed: _busy ? null : () => _pdf(r),
              icon: const Icon(Icons.picture_as_pdf_outlined),
            ),
        ],
      ),
      body: review.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
            error: e, onRetry: () => ref.invalidate(attendanceReviewProvider(widget.periodId))),
        data: (r) => ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _Header(r),
            if (r.pendingLeaves.isNotEmpty)
              _Note(
                icon: Icons.warning_amber_rounded,
                color: const Color(0xFFFEF3C7),
                onColor: const Color(0xFF92400E),
                title: 'Leave in this period is still pending',
                lines: r.pendingLeaves,
              ),
            if (r.approvedLeaves.isNotEmpty)
              _Note(
                icon: Icons.check_circle_outline,
                color: const Color(0xFFDCFCE7),
                onColor: const Color(0xFF166534),
                title: 'Approved leave in this period',
                lines: r.approvedLeaves,
              ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < r.days.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    AttendanceDayRow(day: r.days[i], label: _dayFmt.format(r.days[i].date)),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: r == null || r.status != 'Submitted'
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(52),
                          foregroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: _busy ? null : () => _reject(r),
                        child: const Text('Reject'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _busy ? null : () => _approve(r),
                        child: _busy
                            ? const SizedBox(
                                width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('Approve'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  Future<void> _approve(AttendanceReview r) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Approve attendance?'),
        content: Text('${r.employeeName}, ${r.label}.\n'
            '${r.pendingLeaves.isNotEmpty ? 'Note: some leave in this period is still pending.\n' : ''}'
            'Leave days on the timesheet are recorded as approved leave.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Approve')),
        ],
      ),
    );
    if (ok != true) return;
    await _decide(() => ref.read(adminRepositoryProvider).approveAttendance(r.id), 'Attendance approved');
  }

  Future<void> _reject(AttendanceReview r) async {
    final reason = await askComment(context,
        title: 'Reject attendance?', action: 'Reject', required: true,
        hint: 'What should ${r.employeeName} correct?');
    if (reason == null) return;
    await _decide(
        () => ref.read(adminRepositoryProvider).rejectAttendance(r.id, reason), 'Attendance rejected');
  }

  Future<void> _decide(Future<void> Function() action, String done) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _pdf(AttendanceReview r) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes = await ref.read(adminRepositoryProvider).attendancePdf(r.id);
      final name = 'Attendance_${r.employeeName.replaceAll(' ', '_')}_'
          '${DateFormat('yyyy-MM-dd').format(r.start)}.pdf';
      final file = await FileOpener.save(bytes, name);
      await FileOpener.open(file, mimeType: 'application/pdf');
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _Header extends StatelessWidget {
  const _Header(this.r);

  final AttendanceReview r;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final h = r.totalHours;
    Widget fig(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: text.titleLarge
                      ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
              Text(label,
                  style: text.bodySmall?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
            ],
          ),
        );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.label,
                        style: text.titleMedium
                            ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                    if (r.department.isNotEmpty)
                      Text(r.department,
                          style: text.bodySmall
                              ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
                  ],
                ),
              ),
              StatusChip(r.status),
            ],
          ),
          const SizedBox(height: 12),
          Row(children: [
            fig('Hours', h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1)),
            fig('Leave days', '${r.leaveDays}'),
            fig('Days', '${r.days.length}'),
          ]),
        ],
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.title,
    required this.lines,
  });

  final IconData icon;
  final Color color;
  final Color onColor;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 12),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onColor, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(color: onColor, fontWeight: FontWeight.w600)),
                  for (final l in lines) Text(l, style: TextStyle(color: onColor)),
                ],
              ),
            ),
          ],
        ),
      );
}
