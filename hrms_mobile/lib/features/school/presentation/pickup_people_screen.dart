import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/error_view.dart';
import '../data/parent_account.dart';
import 'school_widgets.dart';

final _historyProvider = FutureProvider.autoDispose<List<PickupPersonRec>>(
    (ref) => ref.watch(parentAccountRepositoryProvider).pickupPeople(status: 'all'));

/// Office: pick-up people the parents added — approve or reject (with a reason the parent sees).
class PickupPeopleScreen extends ConsumerWidget {
  const PickupPeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Pick-up people'),
          bottom: const TabBar(tabs: [Tab(text: 'To approve'), Tab(text: 'All')]),
        ),
        body: TabBarView(children: [
          _List(provider: pendingPickupPeopleProvider, empty: 'Nothing to approve.'),
          _List(provider: _historyProvider, empty: 'No pick-up people yet.'),
        ]),
      ),
    );
  }
}

class _List extends ConsumerWidget {
  const _List({required this.provider, required this.empty});
  final AutoDisposeFutureProvider<List<PickupPersonRec>> provider;
  final String empty;

  void _refresh(WidgetRef ref) {
    ref.invalidate(pendingPickupPeopleProvider);
    ref.invalidate(_historyProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(provider);
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(provider)),
      data: (items) => RefreshIndicator(
        onRefresh: () async {
          _refresh(ref);
          await ref.read(provider.future);
        },
        child: items.isEmpty
            ? ListView(children: [Padding(padding: const EdgeInsets.all(40), child: Center(child: Text(empty)))])
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                itemCount: items.length,
                itemBuilder: (_, i) => _Card(person: items[i], onChanged: () => _refresh(ref)),
              ),
      ),
    );
  }
}

class _Card extends ConsumerWidget {
  const _Card({required this.person, required this.onChanged});
  final PickupPersonRec person;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = person;
    final repo = ref.read(parentAccountRepositoryProvider);
    final tone = p.approved ? PillTone.good : p.pending ? PillTone.warn : PillTone.bad;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('${p.fullName} · ${p.relationship}',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            ),
            Pill(p.status, tone: tone),
          ]),
          const SizedBox(height: 4),
          Text([
            'For ${p.childName ?? ''}${p.className != null ? ' (${p.className})' : ''}',
            if (p.phone != null) phoneText(p.phone),
            if (p.addedByName != null) 'added by ${p.addedByName}',
          ].join(' · ')),
          if (p.note != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text('“${p.note}”')),
          if (p.rejected && p.rejectReason != null)
            Padding(padding: const EdgeInsets.only(top: 4), child: Text('Reason: ${p.rejectReason}')),
          if (p.pending)
            Row(mainAxisAlignment: MainAxisAlignment.end, children: [
              TextButton(
                onPressed: () async {
                  final reason = await _askReason(context, p.fullName);
                  if (reason == null || !context.mounted) return;
                  if (await attempt(context, () => repo.reject(p.id, reason.isEmpty ? null : reason), done: 'Not approved')) onChanged();
                },
                child: const Text('Reject'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () async {
                  if (await attempt(context, () => repo.approve(p.id), done: '${p.fullName} approved')) onChanged();
                },
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Approve'),
              ),
            ]),
        ]),
      ),
    );
  }

  /// The reason the parent sees, or null if cancelled.
  Future<String?> _askReason(BuildContext context, String name) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Don\'t approve $name?'),
        content: TextField(
          controller: c,
          maxLength: 300,
          minLines: 2,
          maxLines: 3,
          decoration: const InputDecoration(labelText: 'Reason (the parent sees it)', hintText: 'e.g. Please bring their IC to the office first'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, c.text.trim()), child: const Text('Don\'t approve')),
        ],
      ),
    ).whenComplete(c.dispose);
  }
}
