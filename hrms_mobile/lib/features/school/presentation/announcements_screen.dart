import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/error_view.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

/// School announcements. Parents: notices for the whole school and their children's classes.
/// Teachers and admins also post (teachers to their own classes) and see "read by X of Y".
class AnnouncementsScreen extends ConsumerWidget {
  const AnnouncementsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(announcementsProvider);
    final me = ref.watch(schoolMeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Announcements')),
      floatingActionButton: me != null && me.isStaff
          ? FloatingActionButton.extended(
              onPressed: () async {
                final sent = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(builder: (_) => const ComposeAnnouncementScreen(), fullscreenDialog: true));
                if (sent == true) ref.invalidate(announcementsProvider);
              },
              icon: const Icon(Icons.campaign_outlined),
              label: const Text('New'),
            )
          : null,
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(announcementsProvider)),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(announcementsProvider.future),
          child: items.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                  SizedBox(height: 120),
                  Icon(Icons.campaign_outlined, size: 56),
                  SizedBox(height: 12),
                  Center(child: Text('No announcements yet')),
                ])
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 88),
                  itemCount: items.length,
                  itemBuilder: (context, i) => _AnnouncementCard(a: items[i], staff: me?.isStaff ?? false),
                ),
        ),
      ),
    );
  }
}

class _AnnouncementCard extends ConsumerStatefulWidget {
  const _AnnouncementCard({required this.a, required this.staff});
  final Announcement a;
  final bool staff;

  @override
  ConsumerState<_AnnouncementCard> createState() => _AnnouncementCardState();
}

class _AnnouncementCardState extends ConsumerState<_AnnouncementCard> {
  bool _open = false;
  late bool _read = widget.a.isRead;

  void _toggle() {
    setState(() => _open = !_open);
    if (_open && !_read && !widget.staff) {
      _read = true;
      ref.read(schoolRepositoryProvider).markAnnouncementRead(widget.a.id).then((_) {
        ref.invalidate(schoolUnreadProvider);
      }).catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.a;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final unread = !_read && !widget.staff;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: _toggle,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              if (unread)
                Container(
                  width: 8, height: 8, margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
                ),
              Expanded(
                child: Text(a.title, style: text.titleSmall?.copyWith(fontWeight: unread ? FontWeight.w800 : FontWeight.w600)),
              ),
              if (a.attachmentName != null) Icon(Icons.attach_file, size: 16, color: scheme.onSurfaceVariant),
            ]),
            const SizedBox(height: 4),
            Text(
              '${a.className == null ? 'All parents' : 'Class ${a.className}'} · ${a.createdByName}'
              '${a.createdAt == null ? '' : ' · ${DateFormat('d MMM, h:mm a').format(a.createdAt!.toLocal())}'}',
              style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            Text(a.body, maxLines: _open ? null : 3, overflow: _open ? null : TextOverflow.ellipsis),
            if (_open && a.attachmentName != null) ...[
              const SizedBox(height: 10),
              OutlinedButton.icon(
                onPressed: () => openBytes(context,
                    () => ref.read(schoolRepositoryProvider).announcementAttachment(a.id), a.attachmentName!),
                icon: Icon(a.attachmentType == 'application/pdf' ? Icons.picture_as_pdf_outlined : Icons.image_outlined),
                label: Text(a.attachmentName!, overflow: TextOverflow.ellipsis),
              ),
            ],
            if (widget.staff && a.readCount != null && a.audienceCount != null) ...[
              const SizedBox(height: 8),
              Text('Read by ${a.readCount} of ${a.audienceCount} parent logins',
                  style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            ],
            if (_open && a.canDelete)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Delete announcement?'),
                        content: Text('"${a.title}" will be removed for everyone.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
                        ],
                      ),
                    );
                    if (ok == true && context.mounted &&
                        await attempt(context, () => ref.read(schoolRepositoryProvider).deleteAnnouncement(a.id),
                            done: 'Deleted')) {
                      ref.invalidate(announcementsProvider);
                    }
                  },
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  label: Text('Delete', style: TextStyle(color: scheme.error)),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}

/// Post a notice: to every parent (admins) or one class; optional photo.
class ComposeAnnouncementScreen extends ConsumerStatefulWidget {
  const ComposeAnnouncementScreen({super.key});

  @override
  ConsumerState<ComposeAnnouncementScreen> createState() => _ComposeState();
}

class _ComposeState extends ConsumerState<ComposeAnnouncementScreen> {
  final _title = TextEditingController();
  final _body = TextEditingController();
  int? _classId;
  PickedFile? _file;
  bool _sending = false;
  List<SchoolClassRef> _classes = [];

  @override
  void initState() {
    super.initState();
    final me = ref.read(schoolMeProvider).valueOrNull;
    if (me != null && me.isAdmin) {
      ref.read(schoolRepositoryProvider).classes().then((c) {
        if (mounted) setState(() => _classes = c);
      }).catchError((_) {});
    } else if (me != null) {
      _classes = me.classes;
      if (_classes.length == 1) _classId = _classes.first.id;
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_title.text.trim().isEmpty || _body.text.trim().isEmpty) {
      toast(context, 'Write a title and the message.', error: true);
      return;
    }
    final me = ref.read(schoolMeProvider).valueOrNull;
    if (me != null && !me.isAdmin && _classId == null) {
      toast(context, 'Choose the class.', error: true);
      return;
    }
    setState(() => _sending = true);
    final ok = await attempt(context, () async {
      final n = await ref.read(schoolRepositoryProvider)
          .postAnnouncement(title: _title.text.trim(), body: _body.text.trim(), classId: _classId, file: _file);
      if (mounted) toast(context, 'Sent to $n parent login${n == 1 ? '' : 's'}.');
    });
    if (!mounted) return;
    setState(() => _sending = false);
    if (ok) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(schoolMeProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(
        title: const Text('New announcement'),
        actions: [
          TextButton(onPressed: _sending ? null : _send, child: const Text('Send')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        DropdownButtonFormField<int?>(
          value: _classId,
          decoration: const InputDecoration(labelText: 'To'),
          items: [
            if (me?.isAdmin ?? false) const DropdownMenuItem<int?>(value: null, child: Text('All parents')),
            for (final c in _classes) DropdownMenuItem<int?>(value: c.id, child: Text('Parents of ${c.name}')),
          ],
          onChanged: (v) => setState(() => _classId = v),
        ),
        const SizedBox(height: 12),
        TextField(controller: _title, maxLength: 150, decoration: const InputDecoration(labelText: 'Title')),
        TextField(
          controller: _body,
          minLines: 4,
          maxLines: 12,
          maxLength: 4000,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true),
        ),
        const SizedBox(height: 8),
        if (_file == null)
          OutlinedButton.icon(
            onPressed: () async {
              final f = await pickPhoto(context);
              if (f != null) setState(() => _file = f);
            },
            icon: const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('Add a photo (optional)'),
          )
        else
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.image_outlined),
            title: Text(_file!.name, overflow: TextOverflow.ellipsis),
            trailing: IconButton(onPressed: () => setState(() => _file = null), icon: const Icon(Icons.close)),
          ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _sending ? null : _send,
          icon: _sending
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.send),
          label: const Text('Send to parents'),
        ),
      ]),
    );
  }
}
