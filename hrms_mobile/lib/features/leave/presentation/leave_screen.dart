import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/leave_models.dart';
import '../data/leave_repository.dart';

/// Leave tab: this year's balances, my requests (filter by status),
/// request details with cancel, and "Apply" for a new request.
class LeaveScreen extends ConsumerStatefulWidget {
  const LeaveScreen({super.key});

  @override
  ConsumerState<LeaveScreen> createState() => _LeaveScreenState();
}

class _LeaveScreenState extends ConsumerState<LeaveScreen> {
  static const _filters = ['All', 'Pending', 'Approved', 'Rejected', 'Cancelled'];
  String _filter = 'All';
  final int _year = DateTime.now().year;

  Future<void> _refresh() async {
    ref.invalidate(leaveBalancesProvider(_year));
    ref.invalidate(leaveRequestsProvider);
    await ref.read(leaveRequestsProvider.future);
  }

  @override
  Widget build(BuildContext context) {
    final balances = ref.watch(leaveBalancesProvider(_year));
    final requests = ref.watch(leaveRequestsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Leave')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final applied = await context.push<bool>(Routes.applyLeave);
          if (applied == true) _refresh();
        },
        icon: const Icon(Icons.add),
        label: const Text('Apply leave'),
      ),
      body: requests.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorView(error: error, onRetry: _refresh),
        data: (all) {
          final shown =
              _filter == 'All' ? all : all.where((r) => r.status == _filter).toList();
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
              children: [
                _SectionTitle('Balances $_year'),
                balances.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  error: (e, _) => _Message(ApiException.from(e).message),
                  data: (items) => items.isEmpty
                      ? const _Message('No leave balances set up for this year yet.')
                      : _BalanceGrid(items),
                ),
                const _SectionTitle('My requests'),
                SizedBox(
                  height: 44,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    children: [
                      for (final f in _filters)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(f),
                            selected: f == _filter,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                if (shown.isEmpty)
                  _Message(_filter == 'All'
                      ? 'You have not applied for leave yet.'
                      : 'No ${_filter.toLowerCase()} requests.')
                else
                  for (final r in shown) ...[
                    _RequestCard(
                      request: r,
                      onTap: () => _showDetails(r),
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

  Future<void> _showDetails(LeaveRequestItem r) async {
    final cancelled = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _RequestDetailsSheet(request: r),
    );
    if (cancelled == true) _refresh();
  }
}

class _BalanceGrid extends StatelessWidget {
  const _BalanceGrid(this.items);

  final List<LeaveBalanceItem> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 1.55,
      children: [
        for (final b in items)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(b.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium),
                  const Spacer(),
                  Text(Fmt.days(b.balanceDays),
                      style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: theme.colorScheme.primary)),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(value: b.usedFraction, minHeight: 5),
                  ),
                  const SizedBox(height: 4),
                  Text('${Fmt.days(b.usedDays)} used of ${Fmt.days(b.totalDays)}',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request, required this.onTap});

  final LeaveRequestItem request;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = request;
    final range = isSameDay(r.startDate, r.endDate)
        ? Fmt.date(r.startDate)
        : '${Fmt.shortDate(r.startDate)} – ${Fmt.date(r.endDate)}';

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: theme.colorScheme.primaryContainer,
                child: Text(
                  r.leaveTypeCode,
                  style: theme.textTheme.labelMedium?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.leaveTypeName,
                        style: theme.textTheme.titleSmall
                            ?.copyWith(fontWeight: FontWeight.w600)),
                    Text('$range · ${Fmt.days(r.totalDays)}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              StatusChip(r.status),
            ],
          ),
        ),
      ),
    );
  }
}

class _RequestDetailsSheet extends ConsumerStatefulWidget {
  const _RequestDetailsSheet({required this.request});

  final LeaveRequestItem request;

  @override
  ConsumerState<_RequestDetailsSheet> createState() => _RequestDetailsSheetState();
}

class _RequestDetailsSheetState extends ConsumerState<_RequestDetailsSheet> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = widget.request;
    Widget row(String label, String? value) => value == null || value.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 110,
                  child: Text(label,
                      style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                ),
                Expanded(child: Text(value)),
              ],
            ),
          );

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(r.leaveTypeName,
                      style: theme.textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w600)),
                ),
                StatusChip(r.status),
              ],
            ),
            const SizedBox(height: 12),
            row('From', Fmt.date(r.startDate)),
            row('To', Fmt.date(r.endDate)),
            row('Days', Fmt.days(r.totalDays)),
            row('Reason', r.reason),
            row('Applied on', r.requestedOn == null ? null : Fmt.date(r.requestedOn)),
            if (r.status == 'Approved' || r.status == 'Rejected') ...[
              row(r.status == 'Approved' ? 'Approved on' : 'Decided on',
                  r.approvedOn == null ? null : Fmt.date(r.approvedOn)),
              row('Remarks', r.approvalRemarks),
            ],
            if (r.status == 'Cancelled') ...[
              row('Cancelled on', r.cancelledOn == null ? null : Fmt.date(r.cancelledOn)),
              row('Cancel reason', r.cancellationReason),
            ],
            if (r.attachmentName != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _openAttachment,
                  icon: const Icon(Icons.attach_file),
                  label: Text(r.attachmentName!, overflow: TextOverflow.ellipsis),
                ),
              ),
            if (r.canCancel) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size.fromHeight(48),
                  ),
                  onPressed: _busy ? null : _cancel,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.cancel_outlined),
                  label: const Text('Cancel request'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _openAttachment() async {
    final r = widget.request;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final bytes =
          await ref.read(leaveRepositoryProvider).downloadAttachment(r.id);
      final file = await FileOpener.save(bytes, r.attachmentName!);
      await FileOpener.open(file, mimeType: FileOpener.mimeFor(r.attachmentName!));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final reasonCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this leave request?'),
        content: TextField(
          controller: reasonCtrl,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'Reason (optional)'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Cancel request')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await ref
          .read(leaveRepositoryProvider)
          .cancel(widget.request.id, reasonCtrl.text.trim());
      messenger.showSnackBar(const SnackBar(content: Text('Leave request cancelled')));
      navigator.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiException.from(e).message)));
      if (mounted) setState(() => _busy = false);
    }
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 16, 0, 10),
        child: Text(text,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w600)),
      );
}

class _Message extends StatelessWidget {
  const _Message(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(text,
            style: theme.textTheme.bodyMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ),
    );
  }
}
