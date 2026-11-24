import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/back_to_home.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../leave/data/leave_repository.dart';
import '../data/admin_models.dart';
import '../data/admin_repository.dart';

/// Admin approvals: pending leave requests and submitted attendance periods.
class ApprovalsScreen extends ConsumerWidget {
  const ApprovalsScreen({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leaves = ref.watch(pendingLeavesProvider).valueOrNull?.length;
    final attendance = ref.watch(pendingAttendanceProvider).valueOrNull?.length;
    String label(String name, int? n) => n == null || n == 0 ? name : '$name ($n)';

    return DefaultTabController(
      length: 2,
      initialIndex: initialTab,
      child: Scaffold(
        appBar: AppBar(
          leading: const BackToHomeButton(),
          title: const Text('Approvals'),
          bottom: TabBar(
            tabs: [
              Tab(text: label('Leave', leaves)),
              Tab(text: label('Attendance', attendance)),
            ],
          ),
        ),
        body: const TabBarView(children: [_LeaveTab(), _AttendanceTab()]),
      ),
    );
  }
}

/// Asks for an optional (approve) or required (reject) comment.
/// Returns null when cancelled.
Future<String?> askComment(
  BuildContext context, {
  required String title,
  required String action,
  required bool required,
  String hint = '',
}) {
  final ctrl = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setState) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          minLines: 1,
          maxLines: 3,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            labelText: required ? 'Reason (required)' : 'Remarks (optional)',
            hintText: hint,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(
            onPressed: required && ctrl.text.trim().isEmpty
                ? null
                : () => Navigator.pop(ctx, ctrl.text.trim()),
            child: Text(action),
          ),
        ],
      ),
    ),
  );
}

void _snack(BuildContext context, String message) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));

class _LeaveTab extends ConsumerWidget {
  const _LeaveTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pendingLeavesProvider);
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(pendingLeavesProvider)),
      data: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(pendingLeavesProvider.future),
        child: items.isEmpty
            ? const _AllDone('No leave requests waiting for approval.')
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _LeaveCard(items[i]),
              ),
      ),
    );
  }
}

class _LeaveCard extends ConsumerStatefulWidget {
  const _LeaveCard(this.r);

  final PendingLeave r;

  @override
  ConsumerState<_LeaveCard> createState() => _LeaveCardState();
}

class _LeaveCardState extends ConsumerState<_LeaveCard> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.r;
    final range = isSameDay(r.startDate, r.endDate)
        ? Fmt.date(r.startDate)
        : '${Fmt.shortDate(r.startDate)} – ${Fmt.date(r.endDate)}';
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(r.employeeName.isEmpty ? '?' : r.employeeName[0].toUpperCase()),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(r.employeeName,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      Text(r.leaveTypeName, style: muted),
                    ],
                  ),
                ),
                Text(Fmt.days(r.totalDays),
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              ],
            ),
            const SizedBox(height: 10),
            Row(children: [
              const Icon(Icons.date_range_outlined, size: 18),
              const SizedBox(width: 6),
              Text(range),
            ]),
            if (r.reason?.isNotEmpty ?? false) ...[
              const SizedBox(height: 6),
              Text('“${r.reason}”', style: theme.textTheme.bodyMedium),
            ],
            if (r.requestedOn != null) ...[
              const SizedBox(height: 4),
              Text('Applied ${Fmt.date(r.requestedOn)}', style: muted),
            ],
            if (r.attachmentName != null)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _openAttachment,
                  icon: const Icon(Icons.attach_file, size: 18),
                  label: Text(r.attachmentName!, overflow: TextOverflow.ellipsis),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    onPressed: _busy ? null : _reject,
                    child: const Text('Reject'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(40)),
                    onPressed: _busy ? null : _approve,
                    child: _busy
                        ? const SizedBox(
                            width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Approve'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve() async {
    final remarks = await askComment(context,
        title: 'Approve ${widget.r.employeeName}\'s leave?', action: 'Approve', required: false);
    if (remarks == null) return;
    await _do(() => ref.read(adminRepositoryProvider).approveLeave(widget.r.id,
        remarks: remarks.isEmpty ? null : remarks), 'Leave approved');
  }

  Future<void> _reject() async {
    final reason = await askComment(context,
        title: 'Reject ${widget.r.employeeName}\'s leave?', action: 'Reject', required: true,
        hint: 'The employee will see this reason');
    if (reason == null) return;
    await _do(() => ref.read(adminRepositoryProvider).rejectLeave(widget.r.id, reason),
        'Leave rejected');
  }

  Future<void> _do(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      if (!mounted) return;
      _snack(context, done);
      ref.invalidate(pendingLeavesProvider);
      ref.invalidate(adminDashboardProvider);
    } catch (e) {
      if (mounted) _snack(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openAttachment() async {
    setState(() => _busy = true);
    try {
      final name = widget.r.attachmentName!;
      final bytes = await ref.read(leaveRepositoryProvider).downloadAttachment(widget.r.id);
      final file = await FileOpener.save(bytes, name);
      await FileOpener.open(file, mimeType: FileOpener.mimeFor(name));
    } catch (e) {
      if (mounted) _snack(context, ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _AttendanceTab extends ConsumerWidget {
  const _AttendanceTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(pendingAttendanceProvider);
    final theme = Theme.of(context);
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) =>
          ErrorView(error: e, onRetry: () => ref.invalidate(pendingAttendanceProvider)),
      data: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(pendingAttendanceProvider.future),
        child: items.isEmpty
            ? const _AllDone('No attendance waiting for approval.')
            : ListView.separated(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                itemCount: items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final p = items[i];
                  final h = p.totalHours;
                  return Card(
                    clipBehavior: Clip.antiAlias,
                    child: ListTile(
                      contentPadding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
                      leading: CircleAvatar(
                        child: Text(p.employeeName.isEmpty ? '?' : p.employeeName[0].toUpperCase()),
                      ),
                      title: Text(p.employeeName,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(
                        '${p.label}\n${h == h.roundToDouble() ? h.toStringAsFixed(0) : h} h'
                        '${p.leaveCount > 0 ? ' · ${p.leaveCount} leave' : ''}'
                        '${p.submittedAt != null ? ' · sent ${Fmt.shortDate(p.submittedAt)}' : ''}',
                        style: theme.textTheme.bodySmall,
                      ),
                      isThreeLine: true,
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () async {
                        final decided =
                            await context.push<bool>('${Routes.attendanceReview}/${p.id}');
                        if (decided == true) {
                          ref.invalidate(pendingAttendanceProvider);
                          ref.invalidate(adminDashboardProvider);
                        }
                      },
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _AllDone extends StatelessWidget {
  const _AllDone(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(32),
      children: [
        const SizedBox(height: 80),
        Icon(Icons.task_alt, size: 56, color: theme.colorScheme.primary),
        const SizedBox(height: 12),
        Text('All caught up', textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(text,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}
