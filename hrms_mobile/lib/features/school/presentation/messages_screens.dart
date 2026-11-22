import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

/// Opens the "New conversation" form (optionally prefilled), then the new conversation.
/// Used by Messages, the parent home's "Message" buttons and the help chatbot.
Future<void> startNewConversation(BuildContext context, WidgetRef ref,
    {int? studentId, String? kind, String? subject}) async {
  final id = await Navigator.of(context).push<int>(MaterialPageRoute(
    fullscreenDialog: true,
    builder: (_) => NewConversationScreen(studentId: studentId, kind: kind, subject: subject),
  ));
  if (id == null || !context.mounted) return;
  ref.invalidate(conversationsProvider);
  await context.push('${Routes.schoolChat}/$id');
  if (context.mounted) {
    ref.invalidate(conversationsProvider);
    ref.invalidate(schoolUnreadProvider);
  }
}

/// Conversations with the school. Each is about one child, goes to the class teacher or the
/// office, and has a subject. Parents see their children's; teachers their classes'; admins all.
/// Staff start on the open ones (closed = done).
class ConversationsScreen extends ConsumerStatefulWidget {
  const ConversationsScreen({super.key});

  @override
  ConsumerState<ConversationsScreen> createState() => _ConversationsScreenState();
}

class _ConversationsScreenState extends ConsumerState<ConversationsScreen> {
  /// 'Open', 'Closed' or '' (all). Null until we know whether this is a parent.
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(conversationsProvider);
    final me = ref.watch(schoolMeProvider).valueOrNull;
    final filter = _filter ?? (me == null || me.isParent ? '' : 'Open');
    final canStart = me != null && (me.isParent ? me.children.isNotEmpty : me.isStaff);

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: canStart
          ? FloatingActionButton.extended(
              onPressed: () => startNewConversation(context, ref),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New conversation'),
            )
          : null,
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(conversationsProvider)),
        data: (items) {
          final shown = items.where((c) => filter.isEmpty || c.status == filter).toList();
          final openCount = items.where((c) => !c.isClosed).length;
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(schoolUnreadProvider);
              return ref.refresh(conversationsProvider.future);
            },
            child: ListView.separated(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 88),
              itemCount: shown.isEmpty ? 2 : shown.length + 1,
              separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
                    child: SegmentedButton<String>(
                      segments: [
                        ButtonSegment(value: 'Open', label: Text(openCount > 0 ? 'Open ($openCount)' : 'Open')),
                        const ButtonSegment(value: 'Closed', label: Text('Closed')),
                        const ButtonSegment(value: '', label: Text('All')),
                      ],
                      selected: {filter},
                      showSelectedIcon: false,
                      onSelectionChanged: (s) => setState(() => _filter = s.first),
                    ),
                  );
                }
                if (shown.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(24, 80, 24, 24),
                    child: Column(children: [
                      const Icon(Icons.forum_outlined, size: 56),
                      const SizedBox(height: 12),
                      Text(
                        items.isEmpty
                            ? 'No conversations yet'
                            : 'No ${filter == 'Open' ? 'open ' : filter == 'Closed' ? 'closed ' : ''}conversations',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      if (items.isEmpty && canStart) ...[
                        const SizedBox(height: 6),
                        const Text('Tap "New conversation" to ask the class teacher or the school office something.',
                            textAlign: TextAlign.center),
                      ],
                    ]),
                  );
                }
                return _ThreadTile(c: shown[i - 1], isParent: me?.isParent ?? false);
              },
            ),
          );
        },
      ),
    );
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.c, required this.isParent});
  final ConversationSummary c;
  final bool isParent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final when = c.lastMessageAt == null ? '' : _when(c.lastMessageAt!.toLocal());
    final preview = c.lastText == null ? 'No messages yet' : '${c.lastMine ? 'You' : c.lastSender}: ${c.lastText}';
    final about = isParent
        ? '${c.title} · ${c.studentName}'
        : [c.studentName, c.className, c.kind == 'Office' ? 'Office' : 'Class teacher'].whereType<String>().join(' · ');
    return ListTile(
      onTap: () async {
        await context.push('${Routes.schoolChat}/${c.id}');
        ref.invalidate(conversationsProvider);
        ref.invalidate(schoolUnreadProvider);
      },
      leading: CircleAvatar(
        backgroundColor: (c.kind == 'Office' ? scheme.tertiary : scheme.primary).withValues(alpha: 0.12),
        child: Icon(c.kind == 'Office' ? Icons.business_outlined : Icons.person_outline,
            color: c.kind == 'Office' ? scheme.tertiary : scheme.primary),
      ),
      title: Row(children: [
        Flexible(
          child: Text(c.subject, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  fontWeight: c.unread > 0 ? FontWeight.w700 : FontWeight.w500,
                  color: c.isClosed ? scheme.onSurfaceVariant : null)),
        ),
        if (c.isClosed) ...[
          const SizedBox(width: 6),
          const Pill('Closed', tone: PillTone.neutral),
        ],
      ]),
      subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(about, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium),
        Text(preview, maxLines: 1, overflow: TextOverflow.ellipsis),
      ]),
      isThreeLine: true,
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(when, style: Theme.of(context).textTheme.bodySmall),
          if (c.unread > 0) ...[
            const SizedBox(height: 4),
            Badge(label: Text('${c.unread}')),
          ],
        ],
      ),
    );
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) return DateFormat('h:mm a').format(t);
    return DateFormat('d MMM').format(t);
  }
}

/// A child to pick in the "New conversation" form.
typedef _ChildOption = ({int id, String name, String? className, String? teacher});

/// New conversation: which child, to whom (class teacher / office), subject and first message.
/// Pops with the new conversation's id.
class NewConversationScreen extends ConsumerStatefulWidget {
  const NewConversationScreen({super.key, this.studentId, this.kind, this.subject});
  final int? studentId;
  final String? kind;
  final String? subject;

  @override
  ConsumerState<NewConversationScreen> createState() => _NewConversationScreenState();
}

class _NewConversationScreenState extends ConsumerState<NewConversationScreen> {
  late final TextEditingController _subject = TextEditingController(text: widget.subject ?? '');
  final _body = TextEditingController();
  int? _studentId;
  String? _kind;
  PickedFile? _file;
  bool _sending = false;
  Future<List<_ChildOption>>? _children;

  @override
  void initState() {
    super.initState();
    _studentId = widget.studentId;
    _kind = widget.kind;
  }

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<List<_ChildOption>> _loadChildren(SchoolMe me) async {
    if (me.isParent) {
      return [
        for (final c in me.children) (id: c.id, name: c.fullName, className: c.className, teacher: c.classTeacherName)
      ];
    }
    // Staff: the children they may message (the API limits teachers to their classes)
    final list = await ref.read(schoolRepositoryProvider).students();
    return [for (final s in list) (id: s.id, name: s.fullName, className: s.className, teacher: null)];
  }

  Future<void> _send(SchoolMe me) async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (_studentId == null) return toast(context, 'Choose the child.', error: true);
    if (subject.isEmpty) return toast(context, 'Enter a subject.', error: true);
    if (body.isEmpty && _file == null) return toast(context, 'Write a message.', error: true);
    final canChoose = me.isParent || me.isAdmin;
    final kind = canChoose ? (_kind ?? 'Teacher') : 'Teacher';
    setState(() => _sending = true);
    try {
      final id = await ref.read(schoolRepositoryProvider).startConversation(
          studentId: _studentId!, kind: kind, subject: subject, body: body, file: _file);
      if (mounted) Navigator.of(context).pop(id);
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final meAsync = ref.watch(schoolMeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('New conversation')),
      body: meAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(schoolMeProvider)),
        data: (me) {
          _children ??= _loadChildren(me);
          _kind ??= me.isAdmin && !me.isParent ? 'Office' : 'Teacher';
          final canChoose = me.isParent || me.isAdmin;
          return FutureBuilder<List<_ChildOption>>(
            future: _children,
            builder: (context, snap) {
              if (snap.hasError) {
                return ErrorView(error: snap.error!, onRetry: () => setState(() => _children = _loadChildren(me)));
              }
              if (!snap.hasData) return const Center(child: CircularProgressIndicator());
              final children = snap.data!;
              if (_studentId != null && !children.any((c) => c.id == _studentId)) _studentId = null;
              if (_studentId == null && children.length == 1) _studentId = children.first.id;
              final teacher = children.where((c) => c.id == _studentId).firstOrNull?.teacher;

              return ListView(padding: const EdgeInsets.all(16), children: [
                DropdownButtonFormField<int>(
                  value: _studentId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'About', border: OutlineInputBorder()),
                  hint: const Text('Choose the child'),
                  items: [
                    for (final c in children)
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(c.className == null ? c.name : '${c.name} (${c.className})',
                            overflow: TextOverflow.ellipsis),
                      ),
                  ],
                  onChanged: _sending ? null : (v) => setState(() => _studentId = v),
                ),
                if (canChoose) ...[
                  const SizedBox(height: 16),
                  Text('To', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'Teacher',
                        icon: const Icon(Icons.person_outline),
                        label: Text(me.isParent && teacher != null ? 'Teacher ($teacher)' : 'Class teacher',
                            overflow: TextOverflow.ellipsis),
                      ),
                      const ButtonSegment(value: 'Office', icon: Icon(Icons.business_outlined), label: Text('Office')),
                    ],
                    selected: {_kind!},
                    onSelectionChanged: _sending ? null : (s) => setState(() => _kind = s.first),
                  ),
                ],
                const SizedBox(height: 16),
                TextField(
                  controller: _subject,
                  maxLength: 150,
                  enabled: !_sending,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: 'Subject',
                    hintText: me.isParent ? 'e.g. Sick leave tomorrow' : 'e.g. Field trip consent',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _body,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: 4000,
                  enabled: !_sending,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(labelText: 'Message', alignLabelWithHint: true, border: OutlineInputBorder()),
                ),
                const SizedBox(height: 4),
                if (_file == null)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _sending
                          ? null
                          : () async {
                              final f = await pickPhoto(context);
                              if (f != null) setState(() => _file = f);
                            },
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: const Text('Add a photo'),
                    ),
                  )
                else
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.image_outlined),
                    title: Text(_file!.name, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                        onPressed: _sending ? null : () => setState(() => _file = null), icon: const Icon(Icons.close)),
                  ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: _sending ? null : () => _send(me),
                  icon: _sending
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.send),
                  label: const Text('Send'),
                ),
              ]);
            },
          );
        },
      ),
    );
  }
}

/// One conversation: messages (oldest first), photos and PDFs, "Seen" on my last message.
/// New messages arrive by refreshing every few seconds while the screen is open.
/// Staff can close it when done; sending a message reopens it.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.conversationId});
  final int conversationId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  MessagePage? _page;
  List<ChatMessage> _messages = [];
  Object? _error;
  bool _sending = false;
  bool _loadingOlder = false;
  bool _statusBusy = false;
  PickedFile? _file;
  Timer? _poll;

  SchoolRepository get _repo => ref.read(schoolRepositoryProvider);
  int get _myId => ref.read(schoolMeProvider).valueOrNull?.userId ?? 0;

  @override
  void initState() {
    super.initState();
    _load(first: true);
    _poll = Timer.periodic(const Duration(seconds: 6), (_) => _load());
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 40) _loadOlder();
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load({bool first = false}) async {
    try {
      final page = await _repo.messages(widget.conversationId);
      if (!mounted) return;
      final older = _messages.where((m) => page.messages.isEmpty || m.id < page.messages.first.id);
      final changed = page.messages.isNotEmpty && (_messages.isEmpty || page.messages.last.id != _messages.last.id);
      setState(() {
        _page = page.copyWith(hasMore: first ? page.hasMore : _page?.hasMore ?? page.hasMore);
        _messages = [...older, ...page.messages];
        _error = null;
      });
      if ((first || changed) && _messages.isNotEmpty) {
        unawaited(_repo.markRead(widget.conversationId, _messages.last.id).catchError((_) {}));
        ref.invalidate(schoolUnreadProvider);
      }
    } catch (e) {
      if (mounted && first) setState(() => _error = e);
    }
  }

  Future<void> _loadOlder() async {
    if (_loadingOlder || _page == null || !_page!.hasMore || _messages.isEmpty) return;
    _loadingOlder = true;
    try {
      final older = await _repo.messages(widget.conversationId, before: _messages.first.id);
      if (mounted) {
        setState(() {
          _messages = [...older.messages, ..._messages];
          _page = _page!.copyWith(hasMore: older.hasMore);
        });
      }
    } catch (_) {
      // Try again on the next scroll
    } finally {
      _loadingOlder = false;
    }
  }

  Future<void> _send() async {
    final body = _text.text.trim();
    if ((body.isEmpty && _file == null) || _sending) return;
    setState(() => _sending = true);
    try {
      final msg = await _repo.send(widget.conversationId, body, _file);
      if (!mounted) return;
      setState(() {
        _messages = [..._messages, msg];
        _text.clear();
        _file = null;
        // A message reopens a closed conversation
        if (_page != null && _page!.isClosed) _page = _page!.copyWith(status: 'Open');
      });
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _toggleClosed() async {
    final page = _page;
    if (page == null || _statusBusy) return;
    final close = !page.isClosed;
    setState(() => _statusBusy = true);
    try {
      final status = await _repo.setConversationClosed(widget.conversationId, close);
      if (!mounted) return;
      final me = ref.read(schoolMeProvider).valueOrNull;
      setState(() => _page = _page!.copyWith(status: status, closedByName: me?.name));
      ref.invalidate(conversationsProvider);
      toast(context, close ? 'Conversation closed' : 'Conversation reopened');
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _statusBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final page = _page;
    final me = ref.watch(schoolMeProvider).valueOrNull;
    final isStaff = me?.isStaff ?? false;
    // "Seen" goes under my latest message once the other side has read that far
    var myLastId = 0;
    for (final m in _messages) {
      if (m.senderUserId == _myId) myLastId = m.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(page?.title ?? 'Messages', maxLines: 1, overflow: TextOverflow.ellipsis),
          if (page != null)
            Text(page.subtitle, style: Theme.of(context).textTheme.bodySmall, maxLines: 1, overflow: TextOverflow.ellipsis),
        ]),
        actions: [
          if (page != null && (isStaff || page.isClosed))
            _statusBusy
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                : IconButton(
                    tooltip: page.isClosed ? 'Reopen' : 'Close (done)',
                    onPressed: _toggleClosed,
                    icon: Icon(page.isClosed ? Icons.lock_open_outlined : Icons.check_circle_outline),
                  ),
        ],
      ),
      body: Column(children: [
        if (page != null && page.isClosed)
          Container(
            width: double.infinity,
            color: scheme.secondaryContainer,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              'Closed${page.closedByName != null ? ' by ${page.closedByName}' : ''}. Sending a message opens it again.',
              style: TextStyle(color: scheme.onSecondaryContainer, fontSize: 13),
            ),
          ),
        Expanded(
          child: _error != null
              ? ErrorView(error: _error!, onRetry: () => _load(first: true))
              : page == null
                  ? const Center(child: CircularProgressIndicator())
                  : _messages.isEmpty
                      ? const Center(child: Text('No messages yet. Say hello!'))
                      : ListView.builder(
                          controller: _scroll,
                          reverse: true,
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                          itemCount: _messages.length,
                          itemBuilder: (context, i) {
                            final m = _messages[_messages.length - 1 - i];
                            final mine = m.senderUserId == _myId;
                            return _Bubble(
                              m: m,
                              mine: mine,
                              seen: mine && m.id == myLastId && page.seenUpTo >= m.id,
                            );
                          },
                        ),
        ),
        if (_file != null)
          Container(
            color: scheme.surfaceContainerHighest,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(children: [
              const Icon(Icons.image_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(child: Text(_file!.name, overflow: TextOverflow.ellipsis)),
              IconButton(onPressed: () => setState(() => _file = null), icon: const Icon(Icons.close, size: 18)),
            ]),
          ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              IconButton(
                tooltip: 'Attach a photo',
                onPressed: _sending
                    ? null
                    : () async {
                        final f = await pickPhoto(context);
                        if (f != null) setState(() => _file = f);
                      },
                icon: const Icon(Icons.add_photo_alternate_outlined),
              ),
              Expanded(
                child: TextField(
                  controller: _text,
                  minLines: 1,
                  maxLines: 5,
                  maxLength: 4000,
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Write a message', counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(
                onPressed: _sending ? null : _send,
                icon: _sending
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.send),
              ),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _Bubble extends ConsumerWidget {
  const _Bubble({required this.m, required this.mine, required this.seen});
  final ChatMessage m;
  final bool mine;
  final bool seen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final bg = mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = mine ? scheme.onPrimary : scheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.78),
        child: Column(
          crossAxisAlignment: mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!mine)
              Padding(
                padding: const EdgeInsets.only(left: 6, bottom: 2),
                child: Text('${m.senderName} · ${m.senderRole}', style: text.labelSmall),
              ),
            Container(
              margin: const EdgeInsets.only(bottom: 2),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (m.hasPhoto)
                  Padding(
                    padding: EdgeInsets.only(bottom: m.body.isEmpty ? 0 : 8),
                    child: ProtectedPhoto(provider: messagePhotoProvider(m.id), size: 200),
                  )
                else if (m.attachmentName != null)
                  InkWell(
                    onTap: () => openBytes(context,
                        () => ref.read(schoolRepositoryProvider).messageAttachment(m.id), m.attachmentName!),
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(Icons.picture_as_pdf_outlined, color: fg),
                      const SizedBox(width: 6),
                      Flexible(child: Text(m.attachmentName!, style: TextStyle(color: fg, decoration: TextDecoration.underline))),
                    ]),
                  ),
                if (m.body.isNotEmpty) Text(m.body, style: TextStyle(color: fg)),
              ]),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 6, right: 6, bottom: 8),
              child: Text(
                '${DateFormat('d MMM, h:mm a').format(m.sentAt.toLocal())}${seen ? ' · Seen' : ''}',
                style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
