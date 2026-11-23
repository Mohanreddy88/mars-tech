import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/assistant_repository.dart';

void _toast(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: error ? Theme.of(context).colorScheme.error : null,
    ));
}

/// Admin (More → Chatbot): the help chatbot's questions and answers, and the questions it
/// couldn't answer.
class ChatbotAdminScreen extends ConsumerWidget {
  const ChatbotAdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final data = ref.watch(botAdminProvider);
    final unansweredCount = data.valueOrNull?.unansweredCount ?? 0;

    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Chatbot'),
          actions: [
            IconButton(
              tooltip: 'Add starter questions',
              icon: const Icon(Icons.auto_awesome_outlined),
              onPressed: () async {
                try {
                  final added = await ref.read(assistantRepositoryProvider).addStarter();
                  ref.invalidate(botAdminProvider);
                  if (context.mounted) {
                    _toast(context, added > 0 ? '$added questions added. Review and edit the answers.' : 'All starter questions are already there.');
                  }
                } catch (e) {
                  if (context.mounted) _toast(context, ApiException.from(e).message, error: true);
                }
              },
            ),
          ],
          bottom: TabBar(tabs: [
            const Tab(text: 'Questions'),
            Tab(child: Badge(isLabelVisible: unansweredCount > 0, label: Text('$unansweredCount'), child: const Text('Not answered'))),
          ]),
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: 'Add question',
          onPressed: () => _edit(context, ref, null),
          child: const Icon(Icons.add),
        ),
        body: TabBarView(children: [
          data.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(botAdminProvider)),
            data: (d) => RefreshIndicator(
              onRefresh: () {
                ref.invalidate(botAiStatusProvider);
                return ref.refresh(botAdminProvider.future);
              },
              child: d.faqs.isEmpty
                  ? ListView(padding: const EdgeInsets.all(24), children: const [
                      _AiCard(),
                      SizedBox(height: 60),
                      Icon(Icons.smart_toy_outlined, size: 56),
                      SizedBox(height: 12),
                      Center(child: Text('No questions yet')),
                      SizedBox(height: 6),
                      Text('Tap ✨ above to add the ready-made questions, then edit them for your company.',
                          textAlign: TextAlign.center),
                    ])
                  : ListView.separated(
                      padding: const EdgeInsets.only(bottom: 88),
                      itemCount: d.faqs.length + 1,
                      separatorBuilder: (_, i) => i == 0 ? const SizedBox.shrink() : const Divider(height: 1),
                      itemBuilder: (context, i) {
                        if (i == 0) return const Padding(padding: EdgeInsets.fromLTRB(12, 12, 12, 4), child: _AiCard());
                        final f = d.faqs[i - 1];
                        return ListTile(
                          onTap: () => _edit(context, ref, f),
                          title: Text(f.question,
                              style: TextStyle(color: f.isActive ? null : Theme.of(context).disabledColor)),
                          subtitle: Text(
                            '${f.category} · ${BotFaq.audienceLabel(f.audience)}${f.isActive ? '' : ' · Hidden'}\n${f.answer}',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          isThreeLine: true,
                        );
                      },
                    ),
            ),
          ),
          const _UnansweredTab(),
        ]),
      ),
    );
  }

  static Future<void> _edit(BuildContext context, WidgetRef ref, BotFaq? faq, {BotUnanswered? from}) async {
    final d = ref.read(botAdminProvider).valueOrNull;
    if (d == null) return;
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => _FaqForm(faq: faq, from: from, admin: d),
    ));
    if (saved == true) {
      if (from != null) {
        try {
          await ref.read(assistantRepositoryProvider).deleteUnanswered(from.id);
        } catch (_) {}
        ref.invalidate(botUnansweredProvider);
      }
      ref.invalidate(botAdminProvider);
    }
  }
}

/// AI answers: connect the company's Anthropic key, switch on/off, usage.
class _AiCard extends ConsumerStatefulWidget {
  const _AiCard();

  @override
  ConsumerState<_AiCard> createState() => _AiCardState();
}

class _AiCardState extends ConsumerState<_AiCard> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String done) async {
    setState(() => _busy = true);
    try {
      await action();
      ref.invalidate(botAiStatusProvider);
      if (mounted) _toast(context, done);
    } catch (e) {
      if (mounted) _toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _connect() async {
    final key = await showDialog<String>(context: context, builder: (_) => const _ConnectDialog());
    if (key == null || !mounted) return;
    await _run(() => ref.read(assistantRepositoryProvider).connectKey(key),
        'AI connected. AI answers are on for everyone in the company.');
  }

  Future<void> _disconnect() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Disconnect AI?'),
        content: const Text('Your Anthropic API key is removed. The chatbot goes back to answering from the questions list. '
            'You can connect again at any time.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Disconnect')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() => ref.read(assistantRepositoryProvider).disconnectKey(), 'AI disconnected');
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(botAiStatusProvider).valueOrNull;
    if (status == null) return const SizedBox.shrink();
    const purple = Color(0xFF7C3AED);
    final text = Theme.of(context).textTheme;
    final description = !status.configured
        ? 'Connect your company\'s Anthropic (Claude) account so the chatbot can answer personal questions: '
            'fees owed, today\'s attendance, leave, payslips, unpaid invoices. Each person only sees what their login allows. '
            'Until then the chatbot answers from this list.'
        : '${status.keySource == 'company' ? 'Connected with your key ${status.keyHint ?? ''}. Billed to your Anthropic account. ' : 'Using the server\'s AI key. '}'
            'Personal questions are answered from each person\'s own records. Up to ${status.dailyLimit} per person per day.';

    return Card(
      color: status.enabled ? const Color(0xFFFAF5FF) : null,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const CircleAvatar(radius: 20, backgroundColor: Color(0xFFEDE9FE), child: Icon(Icons.auto_awesome, color: purple, size: 20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('AI answers${status.configured ? (status.enabled ? (status.problem != null ? ' · On, not working' : ' · On') : ' · Off') : ' · Not connected'}',
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                if (status.problem != null) _AiProblem(status: status),
                const SizedBox(height: 2),
                Text(description, style: text.bodySmall),
                const _ConsoleLink(),
                if (status.keyUnreadable && !status.configured)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('The saved key can no longer be read. Please connect it again.',
                        style: text.bodySmall?.copyWith(color: Theme.of(context).colorScheme.error)),
                  ),
                if (status.configured) ...[
                  const SizedBox(height: 4),
                  Text('Today: ${status.todayQuestions} · Last 30 days: ${status.monthQuestions}', style: text.labelSmall),
                ],
              ]),
            ),
            if (status.configured)
              _busy
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                  : Switch(
                      value: status.enabled,
                      onChanged: (on) => _run(() => ref.read(assistantRepositoryProvider).setAi(on),
                          on ? 'AI answers switched on' : 'AI answers switched off'),
                    ),
          ]),
          Align(
            alignment: Alignment.centerRight,
            child: Wrap(spacing: 4, children: [
              if (!status.configured || status.keySource == 'server')
                FilledButton.icon(
                  onPressed: _busy ? null : _connect,
                  icon: const Icon(Icons.power_outlined, size: 18),
                  label: Text(status.configured ? 'Use our own key' : 'Connect AI'),
                ),
              if (status.keySource == 'company') ...[
                TextButton(onPressed: _busy ? null : _connect, child: const Text('Replace key')),
                TextButton(
                  onPressed: _busy ? null : _disconnect,
                  child: Text('Disconnect', style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              ],
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Asks for the Anthropic API key, with the steps to get one. Pops with the key.
/// Anthropic Console, where the company signs up, adds credit and creates its API key.
const anthropicConsoleUrl = 'https://console.anthropic.com/';

/// "Need an API key? Open the Anthropic Console" — opens it in the browser.
class _ConsoleLink extends StatelessWidget {
  const _ConsoleLink();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.center, children: [
        Text('Need an API key or more credit? ', style: Theme.of(context).textTheme.bodySmall),
        InkWell(
          onTap: () async {
            final ok = await launchUrl(Uri.parse(anthropicConsoleUrl), mode: LaunchMode.externalApplication);
            if (!ok && context.mounted) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(const SnackBar(content: Text('Could not open $anthropicConsoleUrl')));
            }
          },
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('Open the Anthropic Console',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                    decoration: TextDecoration.underline)),
            const SizedBox(width: 2),
            Icon(Icons.open_in_new, size: 14, color: Theme.of(context).colorScheme.primary),
          ]),
        ),
      ]),
    );
  }
}

/// "AI isn't working: your Anthropic credit has run out…" — shown until an AI answer works again.
class _AiProblem extends StatelessWidget {
  const _AiProblem({required this.status});
  final BotAiStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final at = DateTime.tryParse(status.problemAt ?? '');
    final when = at == null ? null : DateFormat('d MMM, h:mm a').format(at.toLocal());
    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 4),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: scheme.errorContainer, borderRadius: BorderRadius.circular(8)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(Icons.warning_amber_rounded, color: scheme.onErrorContainer, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text.rich(
            TextSpan(children: [
              const TextSpan(text: 'AI isn\'t working: ', style: TextStyle(fontWeight: FontWeight.w700)),
              TextSpan(text: status.problem),
              TextSpan(
                text: [
                  if (when != null) '\nLast tried $when',
                  if (status.problemCount > 1) ' · ${status.problemCount} questions in a row',
                  '. People got answers from the list instead.',
                ].join(),
              ),
            ]),
            style: TextStyle(color: scheme.onErrorContainer, fontSize: 13),
          ),
        ),
      ]),
    );
  }
}

class _ConnectDialog extends StatefulWidget {
  const _ConnectDialog();

  @override
  State<_ConnectDialog> createState() => _ConnectDialogState();
}

class _ConnectDialogState extends State<_ConnectDialog> {
  final _key = TextEditingController();
  bool _hidden = true;
  String? _error;

  @override
  void dispose() {
    _key.dispose();
    super.dispose();
  }

  void _submit() {
    final key = _key.text.trim();
    if (!key.startsWith('sk-ant-')) {
      setState(() => _error = 'Paste the whole API key; it starts with sk-ant-.');
      return;
    }
    Navigator.pop(context, key);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Connect AI (Anthropic Claude)'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('1. Sign up or sign in at the Anthropic Console and add credits under Plans & Billing.\n'
              '2. Under API keys, create a key (e.g. "Mars HRMS") and copy it.\n'
              '3. Paste it here. It is tested before saving.', style: text.bodySmall),
          const _ConsoleLink(),
          const SizedBox(height: 12),
          TextField(
            controller: _key,
            obscureText: _hidden,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(
              labelText: 'Anthropic API key',
              hintText: 'sk-ant-…',
              errorText: _error,
              border: const OutlineInputBorder(),
              suffixIcon: IconButton(
                icon: Icon(_hidden ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hidden = !_hidden),
              ),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 8),
          Text('Stored encrypted for your company only. AI usage is billed to this Anthropic account.', style: text.labelSmall),
        ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Connect')),
      ],
    );
  }
}

class _UnansweredTab extends ConsumerWidget {
  const _UnansweredTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(botUnansweredProvider);
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(botUnansweredProvider)),
      data: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(botUnansweredProvider.future),
        child: items.isEmpty
            ? ListView(children: const [
                SizedBox(height: 120),
                Icon(Icons.sentiment_satisfied_outlined, size: 56),
                SizedBox(height: 12),
                Center(child: Text('Every question so far had an answer')),
              ])
            : ListView.separated(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final u = items[i];
                  return ListTile(
                    title: Text(u.text),
                    subtitle: Text('${u.audience == 'Parent' ? 'A parent' : 'Staff'} · '
                        '${DateFormat('d MMM, h:mm a').format(u.askedAt.toLocal())}'),
                    onTap: () => ChatbotAdminScreen._edit(context, ref, null, from: u),
                    trailing: IconButton(
                      tooltip: 'Remove',
                      icon: const Icon(Icons.close),
                      onPressed: () async {
                        try {
                          await ref.read(assistantRepositoryProvider).deleteUnanswered(u.id);
                          ref.invalidate(botUnansweredProvider);
                          ref.invalidate(botAdminProvider);
                        } catch (e) {
                          if (context.mounted) _toast(context, ApiException.from(e).message, error: true);
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

/// Add or edit a question and answer. Pops true when saved or deleted.
class _FaqForm extends ConsumerStatefulWidget {
  const _FaqForm({this.faq, this.from, required this.admin});
  final BotFaq? faq;
  final BotUnanswered? from;
  final BotAdminList admin;

  @override
  ConsumerState<_FaqForm> createState() => _FaqFormState();
}

class _FaqFormState extends ConsumerState<_FaqForm> {
  late final _question = TextEditingController(text: widget.faq?.question ?? widget.from?.text ?? '');
  late final _answer = TextEditingController(text: widget.faq?.answer ?? '');
  late final _keywords = TextEditingController(text: widget.faq?.keywords ?? '');
  late final _category = TextEditingController(text: widget.faq?.category ?? '');
  late String _audience = widget.faq?.audience ?? widget.from?.audience ?? 'All';
  late String? _action = widget.faq?.action;
  late bool _active = widget.faq?.isActive ?? true;
  bool _busy = false;

  @override
  void dispose() {
    _question.dispose();
    _answer.dispose();
    _keywords.dispose();
    _category.dispose();
    super.dispose();
  }

  List<({String key, String label, String audience})> get _actions => widget.admin.actions
      .where((a) => _audience == 'All' ? a.audience == 'All' : a.audience == _audience || a.audience == 'All')
      .toList();

  Future<void> _save() async {
    if (_question.text.trim().isEmpty || _answer.text.trim().isEmpty) {
      _toast(context, 'Enter the question and the answer.', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(assistantRepositoryProvider).save(widget.faq?.id, {
        'category': _category.text.trim(),
        'question': _question.text.trim(),
        'answer': _answer.text.trim(),
        'keywords': _keywords.text.trim(),
        'audience': _audience,
        'action': _actions.any((a) => a.key == _action) ? _action : null,
        'sortOrder': widget.faq?.sortOrder,
        'isActive': _active,
      });
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this question?'),
        content: const Text('To keep it for later, switch "Active" off instead.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    setState(() => _busy = true);
    try {
      await ref.read(assistantRepositoryProvider).delete(widget.faq!.id);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) _toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final actions = _actions;
    if (_action != null && !actions.any((a) => a.key == _action)) _action = null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.faq == null ? 'Add question' : 'Edit question'),
        actions: [
          if (widget.faq != null)
            IconButton(tooltip: 'Delete', onPressed: _busy ? null : _delete, icon: const Icon(Icons.delete_outline)),
          TextButton(onPressed: _busy ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        TextField(
          controller: _question,
          maxLength: 300,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(labelText: 'Question', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _answer,
          maxLength: 4000,
          minLines: 4,
          maxLines: 12,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            labelText: 'Answer',
            helperText: 'You can use {company}, {phone}, {feeDueDay}',
            alignLabelWithHint: true,
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keywords,
          maxLength: 500,
          decoration: const InputDecoration(
            labelText: 'Keywords (optional)',
            helperText: 'Other words people may type, separated by commas',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _category,
          maxLength: 60,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Topic', hintText: 'General', border: OutlineInputBorder()),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _audience,
          decoration: const InputDecoration(labelText: 'Shown to', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem(value: 'All', child: Text('Everyone')),
            const DropdownMenuItem(value: 'Employee', child: Text('Staff only')),
            if (widget.admin.schoolFeatures || _audience == 'Parent')
              const DropdownMenuItem(value: 'Parent', child: Text('Parents only')),
          ],
          onChanged: (v) => setState(() => _audience = v ?? 'All'),
        ),
        const SizedBox(height: 16),
        DropdownButtonFormField<String?>(
          value: _action,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Button under the answer', border: OutlineInputBorder()),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('None')),
            for (final a in actions) DropdownMenuItem<String?>(value: a.key, child: Text('Open "${a.label}"')),
          ],
          onChanged: (v) => setState(() => _action = v),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: const Text('Shown in the chatbot'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
      ]),
    );
  }
}
