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

/// Message threads: one per child with the class teacher, one with the office.
/// Parents see their children's; teachers their classes'; admins all.
class ConversationsScreen extends ConsumerWidget {
  const ConversationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(conversationsProvider);
    final me = ref.watch(schoolMeProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Messages')),
      floatingActionButton: me != null && me.isParent && me.children.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: () => _newThread(context, ref, me),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('New message'),
            )
          : null,
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(conversationsProvider)),
        data: (items) => RefreshIndicator(
          onRefresh: () {
            ref.invalidate(schoolUnreadProvider);
            return ref.refresh(conversationsProvider.future);
          },
          child: items.isEmpty
              ? ListView(physics: const AlwaysScrollableScrollPhysics(), children: const [
                  SizedBox(height: 120),
                  Icon(Icons.forum_outlined, size: 56),
                  SizedBox(height: 12),
                  Center(child: Text('No messages yet')),
                ])
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _ThreadTile(c: items[i]),
                ),
        ),
      ),
    );
  }

  /// Parent: choose the child and teacher/office, then open (or start) that thread.
  Future<void> _newThread(BuildContext context, WidgetRef ref, SchoolMe me) async {
    final choice = await showModalBottomSheet<(int, String)>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(shrinkWrap: true, children: [
          for (final c in me.children) ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text('${c.fullName}: class teacher'),
              subtitle: Text(c.classTeacherName ?? 'Class teacher'),
              onTap: () => Navigator.pop(ctx, (c.id, 'Teacher')),
            ),
            ListTile(
              leading: const Icon(Icons.business_outlined),
              title: Text('${c.fullName}: school office'),
              onTap: () => Navigator.pop(ctx, (c.id, 'Office')),
            ),
          ],
        ]),
      ),
    );
    if (choice == null || !context.mounted) return;
    try {
      final id = await ref.read(schoolRepositoryProvider).openConversation(choice.$1, choice.$2);
      if (context.mounted) {
        await context.push('${Routes.schoolChat}/$id');
        ref.invalidate(conversationsProvider);
      }
    } catch (e) {
      if (context.mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }
}

class _ThreadTile extends ConsumerWidget {
  const _ThreadTile({required this.c});
  final ConversationSummary c;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final when = c.lastMessageAt == null ? '' : _when(c.lastMessageAt!.toLocal());
    final preview = c.lastText == null ? 'No messages yet' : '${c.lastMine ? 'You' : c.lastSender}: ${c.lastText}';
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
      title: Text(c.title, maxLines: 1, overflow: TextOverflow.ellipsis,
          style: TextStyle(fontWeight: c.unread > 0 ? FontWeight.w700 : FontWeight.w500)),
      subtitle: Text(preview, maxLines: 2, overflow: TextOverflow.ellipsis),
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

/// One thread: messages (oldest first), photos and PDFs, "Seen" on my last message.
/// New messages arrive by refreshing every few seconds while the screen is open.
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
        _page = page;
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
          _page = MessagePage(title: _page!.title, subtitle: _page!.subtitle, messages: _page!.messages,
              hasMore: older.hasMore, seenUpTo: _page!.seenUpTo);
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
      });
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final page = _page;
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
      ),
      body: Column(children: [
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
