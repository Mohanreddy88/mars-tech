import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/router/app_router.dart';
import '../../../core/utils/file_opener.dart';
import '../../auth/application/auth_controller.dart';
import '../../school/presentation/messages_screens.dart';
import '../data/assistant_repository.dart';

/// App bar button that opens the help chatbot.
class AssistantButton extends StatelessWidget {
  const AssistantButton({super.key});

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: 'Help assistant',
        onPressed: () => context.push(Routes.assistant),
        icon: const Icon(Icons.support_agent_outlined),
      );
}

/// One line in the chat.
class _Line {
  _Line.bot(this.text, {this.topics, this.questions, this.action, this.handoff, this.ai = false, this.download})
      : mine = false;
  _Line.me(this.text)
      : mine = true,
        topics = null,
        questions = null,
        action = null,
        handoff = null,
        ai = false,
        download = null;

  final bool mine;
  /// Answered by the AI (shown with a small label).
  final bool ai;
  /// A report or document to download (AI answers).
  final BotDownload? download;
  String text;
  final List<BotTopic>? topics;
  final List<BotQuestionRef>? questions;
  final BotAction? action;
  /// Parents, after an unanswered question: offer to message the office about it.
  final String? handoff;
}

/// Under the app bar while AI answers are stopped or just failed: admins see why and where to fix
/// it (red, with a link); everyone else a calm yellow note.
class _NoticeBar extends StatelessWidget {
  const _NoticeBar({required this.notice});
  final BotAiNotice notice;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color fg, IconData icon) = switch (notice.level) {
      'error' => (const Color(0xFFFEF2F2), const Color(0xFF991B1B), Icons.warning_amber_rounded),
      'warning' => (const Color(0xFFFFF7ED), const Color(0xFF9A3412), Icons.warning_amber_rounded),
      _ => (const Color(0xFFFEFCE8), const Color(0xFF713F12), Icons.info_outline),
    };
    final link = notice.link;
    return Material(
      color: bg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(notice.message, style: TextStyle(color: fg, fontSize: 13)),
              if (link != null)
                InkWell(
                  onTap: () => launchUrl(Uri.parse(link), mode: LaunchMode.externalApplication),
                  child: Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('${notice.linkLabel ?? 'Open'} ↗',
                        style: TextStyle(color: fg, fontWeight: FontWeight.w700, decoration: TextDecoration.underline)),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// The help chatbot: pick a topic and a question, or type one. Answers come from the questions
/// and answers the company's admins wrote; an answer can have a button that opens an app page.
class AssistantScreen extends ConsumerStatefulWidget {
  const AssistantScreen({super.key});

  @override
  ConsumerState<AssistantScreen> createState() => _AssistantScreenState();
}

class _AssistantScreenState extends ConsumerState<AssistantScreen> {
  final _text = TextEditingController();
  final _scroll = ScrollController();
  final _lines = <_Line>[];
  final _answers = <int, BotAnswer>{};
  /// Questions and answers so far (text only), sent along so the AI can follow up.
  final _history = <(bool, String)>[];

  void _remember(String question, String answer) {
    _history.addAll([(true, question), (false, answer)]);
    if (_history.length > 20) _history.removeRange(0, _history.length - 20);
  }
  BotStart? _start;
  /// "Smart answers are paused…" (admins: why AI stopped, with a link), shown above the chat.
  BotAiNotice? _notice;
  bool _loading = true;
  bool _failed = false;
  bool _asking = false;

  AssistantRepository get _repo => ref.read(assistantRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final s = await _repo.start();
      if (!mounted) return;
      setState(() {
        _start = s;
        _notice = s.aiNotice;
        _loading = false;
        _answers
          ..clear()
          ..addEntries(s.topics.expand((t) => t.items).map((i) => MapEntry(i.id, i)));
        _lines
          ..clear()
          ..add(_Line.bot(s.greeting, topics: s.topics));
        if (s.topics.isEmpty) _lines.add(_Line.bot('There are no help topics yet, but you can still type a question.'));
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failed = true;
        });
      }
    }
  }

  void _add(List<_Line> lines) {
    setState(() => _lines.addAll(lines));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(_scroll.position.maxScrollExtent,
            duration: const Duration(milliseconds: 250), curve: Curves.easeOut);
      }
    });
  }

  void _pickTopic(BotTopic t) => _add([
        _Line.me(t.category),
        _Line.bot('Here\'s what I can help with about ${t.category.toLowerCase()}:',
            questions: [for (final i in t.items) (id: i.id, question: i.question)]),
      ]);

  void _pickQuestion(BotQuestionRef q) {
    final a = _answers[q.id];
    if (a != null) {
      _add([_Line.me(q.question), _Line.bot(a.answer, action: a.action)]);
      _remember(q.question, a.answer);
    } else {
      _ask(q.question);
    }
  }

  /// Shows the topics again, unless they are already the last thing in the chat.
  void _menu() {
    if (_start == null) return;
    final last = _lines.isEmpty ? null : _lines.last;
    _add([if (last?.topics == null || last!.topics!.isEmpty) _Line.bot('What would you like help with?', topics: _start!.topics)]);
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _asking) return;
    _text.clear();
    await _ask(t);
  }

  Future<void> _ask(String t) async {
    _add([_Line.me(t)]);
    setState(() => _asking = true);
    try {
      final history = _history.length > 10 ? _history.sublist(_history.length - 10) : List.of(_history);
      final r = await _repo.ask(t, history: history);
      if (!mounted) return;
      // AI stopped or failed: show why (this answer came from the list); an AI answer clears it
      if (r.aiNotice != null) {
        setState(() => _notice = r.aiNotice);
      } else if (r.source == 'ai' && _notice != null) {
        setState(() => _notice = null);
      }
      if (r.answer != null) {
        _remember(t, r.answer!.answer);
        _add([
          _Line.bot(r.answer!.answer, action: r.answer!.action, ai: r.source == 'ai', download: r.answer!.download),
          if (r.related.isNotEmpty) _Line.bot('Related questions:', questions: r.related),
        ]);
      } else {
        var text = r.reply ?? 'Sorry, I don\'t know that one.';
        if (r.unanswered && r.related.isNotEmpty) text += ' Maybe one of these helps:';
        _add([
          _Line.bot(text,
              questions: r.related.isEmpty ? null : r.related,
              handoff: r.unanswered && (_start?.canMessageSchool ?? false) ? t : null),
        ]);
      }
    } catch (_) {
      if (mounted) _add([_Line.bot('Sorry, I couldn\'t reach the server. Please try again.')]);
    } finally {
      if (mounted) setState(() => _asking = false);
    }
  }

  /// The app page for an answer's button, or null when this login has no such page.
  /// (The API only offers pages this login may open.)
  String? _routeFor(String key) {
    final session = ref.read(authControllerProvider);
    if (session == null) return null;
    if (session.isParent) {
      return switch (key) {
        'fees' => Routes.parentFees,
        'messages' => Routes.parentMessages,
        'new-message' => '', // opens the form instead
        'announcements' => Routes.parentAnnouncements,
        'notifications' => Routes.notifications,
        'change-password' => Routes.changePassword,
        _ => null,
      };
    }
    final shared = switch (key) {
      'notifications' => Routes.notifications,
      'change-password' => Routes.changePassword,
      'school-attendance' => Routes.schoolAttendance,
      'school-messages' => Routes.schoolMessages,
      _ => null,
    };
    if (shared != null) return shared;
    if (session.isAdmin) {
      return switch (key) {
        'school-fees' => Routes.schoolFees,
        'school-children' => Routes.schoolChildren,
        'approvals' => Routes.adminApprovals,
        'payroll' => Routes.adminPayroll,
        'employees' => Routes.adminEmployees,
        _ => null,
      };
    }
    return switch (key) {
      'apply-leave' => Routes.applyLeave,
      'my-leave' => Routes.leave,
      'payslips' => Routes.payslips,
      'attendance' => Routes.attendance,
      'profile' => Routes.profile,
      'my-class' => Routes.schoolMyClass,
      _ => null,
    };
  }

  void _go(BotAction a) {
    final route = _routeFor(a.key);
    if (route == null) return;
    if (a.key == 'new-message') {
      startNewConversation(context, ref);
    } else {
      // Bottom-tab pages are switched to, other pages open on top
      Routes.open(GoRouter.of(context), route);
    }
  }

  String? _downloading;

  /// Downloads a report the AI offered (e.g. unpaid fees as Excel) and opens it.
  Future<void> _download(BotDownload d) async {
    if (_downloading != null) return;
    setState(() => _downloading = d.path);
    try {
      final (bytes, name) = await _repo.download(d.path);
      final file = await FileOpener.save(bytes, name);
      await FileOpener.open(file, mimeType: FileOpener.mimeFor(name));
    } catch (_) {
      if (mounted) _add([_Line.bot('Sorry, "${d.label}" could not be downloaded. Please try again.')]);
    } finally {
      if (mounted) setState(() => _downloading = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Help assistant'),
        actions: [
          IconButton(tooltip: 'Topics', onPressed: _start == null ? null : _menu, icon: const Icon(Icons.apps_outlined)),
        ],
      ),
      body: Column(children: [
        if (_notice != null) _NoticeBar(notice: _notice!),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _failed
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        const Text('Couldn\'t load the assistant.'),
                        TextButton(onPressed: _load, child: const Text('Try again')),
                      ]),
                    )
                  : ListView.builder(
                      controller: _scroll,
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                      itemCount: _lines.length + (_asking ? 1 : 0),
                      itemBuilder: (context, i) {
                        if (i == _lines.length) {
                          return const Align(
                            alignment: Alignment.centerLeft,
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                            ),
                          );
                        }
                        return _bubble(_lines[i], scheme);
                      },
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _text,
                  maxLength: 500,
                  textInputAction: TextInputAction.send,
                  onSubmitted: (_) => _send(),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: const InputDecoration(hintText: 'Type your question', counterText: '', isDense: true),
                ),
              ),
              const SizedBox(width: 6),
              IconButton.filled(onPressed: _asking || _start == null ? null : _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _bubble(_Line l, ColorScheme scheme) {
    final bg = l.mine ? scheme.primary : scheme.surfaceContainerHighest;
    final fg = l.mine ? scheme.onPrimary : scheme.onSurface;
    final action = l.action;
    return Align(
      alignment: l.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.86),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (l.ai)
              Container(
                margin: const EdgeInsets.only(bottom: 4),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(color: const Color(0xFFF3E8FF), borderRadius: BorderRadius.circular(6)),
                child: const Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 12, color: Color(0xFF7C3AED)),
                  SizedBox(width: 3),
                  Text('AI', style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Color(0xFF7C3AED))),
                ]),
              ),
            Text(l.text, style: TextStyle(color: fg)),
            if (l.topics != null && l.topics!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final t in l.topics!) ActionChip(label: Text(t.category), onPressed: () => _pickTopic(t)),
              ]),
            ],
            if (l.questions != null)
              for (final q in l.questions!)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      backgroundColor: scheme.surface,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    ),
                    onPressed: () => _pickQuestion(q),
                    icon: const Icon(Icons.help_outline, size: 18),
                    label: Text(q.question, textAlign: TextAlign.left),
                  ),
                ),
            if (action != null && _routeFor(action.key) != null) ...[
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () => _go(action),
                icon: const Icon(Icons.arrow_forward, size: 18),
                label: Text(action.label),
              ),
            ],
            if (l.download != null) ...[
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _downloading == null ? () => _download(l.download!) : null,
                icon: _downloading == l.download!.path
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.download, size: 18),
                label: Text(l.download!.label),
              ),
            ],
            if (l.handoff != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(backgroundColor: scheme.surface),
                onPressed: () => startNewConversation(context, ref,
                    kind: 'Office', subject: l.handoff!.length > 150 ? l.handoff!.substring(0, 150) : l.handoff),
                icon: const Icon(Icons.chat_bubble_outline, size: 18),
                label: const Text('Message the school office'),
              ),
            ],
          ]),
        ),
      ),
    );
  }
}
