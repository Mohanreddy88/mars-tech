import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_admin.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'fees_screens.dart' show ClaimsScreen;
import 'price_lists_screens.dart';
import 'school_widgets.dart';

/// Admin → Fees, like the web page: Invoices (create, select and send, send again, remind),
/// To confirm (parents' "I've paid"), Fee items, Add-ons per child, Settings.
class AdminFeesScreen extends StatelessWidget {
  const AdminFeesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 7,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Fees'),
          bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [
            Tab(text: 'Invoices'),
            Tab(text: 'To confirm'),
            Tab(text: 'Price lists'),
            Tab(text: 'Deposits'),
            Tab(text: 'Fee items'),
            Tab(text: 'Add-ons'),
            Tab(text: 'Settings'),
          ]),
        ),
        body: const TabBarView(children: [
          _InvoicesTab(),
          ClaimsScreen(embedded: true),
          PriceListsTab(),
          DepositsTab(),
          _FeeItemsTab(),
          _AddOnsTab(),
          _SettingsTab(),
        ]),
      ),
    );
  }
}

// ═══════════════════ Invoices ═══════════════════

class _InvoicesTab extends ConsumerStatefulWidget {
  const _InvoicesTab();

  @override
  ConsumerState<_InvoicesTab> createState() => _InvoicesTabState();
}

class _InvoicesTabState extends ConsumerState<_InvoicesTab> with AutomaticKeepAliveClientMixin {
  late DateTime _month = DateTime(ymdToDate(schoolToday()).year, ymdToDate(schoolToday()).month);
  String? _status;
  int? _classId;
  List<ClassItem> _classes = [];
  final Set<int> _selected = {};
  late Future<InvoiceMonth> _load = _fetch();
  bool _working = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    ref.read(schoolAdminProvider).classes().then((c) {
      if (mounted) setState(() => _classes = c.where((x) => x.isActive).toList());
    }).catchError((_) {});
  }

  Future<InvoiceMonth> _fetch() =>
      ref.read(schoolRepositoryProvider).invoices(_month.year, _month.month, status: _status, classId: _classId);

  void _reload() => setState(() => _load = _fetch());

  Future<void> _run(Future<void> Function() f) async {
    setState(() => _working = true);
    await attempt(context, f);
    if (!mounted) return;
    setState(() => _working = false);
    _reload();
  }

  String _sent(({int sent, int emailed}) r) =>
      '${r.sent} invoice${r.sent == 1 ? '' : 's'} sent${r.emailed > 0 ? ' (${r.emailed} email${r.emailed == 1 ? '' : 's'} with the PDF)' : ''}.';

  Future<void> _generate() async {
    final label = DateFormat('MMMM yyyy').format(_month);
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create invoices'),
        content: Text('Create an invoice for $label for every active child who has none yet? Parents see them only after you send them.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _run(() async {
      final r = await ref.read(schoolAdminProvider).generate(_month.year, _month.month);
      if (!mounted) return;
      toast(context, r.created == 0 && r.skipped.isEmpty
          ? 'Every child already has an invoice for $label.'
          : '${r.created} invoice${r.created == 1 ? '' : 's'} created.${r.skipped.isEmpty ? '' : ' Skipped: ${r.skipped.join(', ')}.'}');
    });
  }

  Future<void> _sendUnsent() => _run(() async {
        final r = await ref.read(schoolAdminProvider).send(_month.year, _month.month, classId: _classId);
        if (mounted) toast(context, _sent(r));
      });

  Future<void> _sendSelected() => _run(() async {
        final r = await ref.read(schoolAdminProvider)
            .send(_month.year, _month.month, invoiceIds: _selected.toList(), resend: true);
        _selected.clear();
        if (mounted) toast(context, _sent(r));
      });

  Future<void> _remind() => _run(() async {
        final n = await ref.read(schoolRepositoryProvider).remind(_month.year, _month.month);
        if (mounted) toast(context, n == 0 ? 'No overdue invoices that were sent.' : '$n reminder${n == 1 ? '' : 's'} sent.');
      });

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final text = Theme.of(context).textTheme;
    return FutureBuilder<InvoiceMonth>(
      future: _load,
      builder: (context, snap) {
        final m = snap.data;
        final notSent = m?.invoices.where((i) => !i.sent && i.status != 'Void').length ?? 0;
        return Scaffold(
          floatingActionButton: _selected.isNotEmpty
              ? FloatingActionButton.extended(
                  onPressed: _working ? null : _sendSelected,
                  icon: const Icon(Icons.send),
                  label: Text('Send selected (${_selected.length})'),
                )
              : null,
          body: RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
              children: [
                Row(children: [
                  IconButton(onPressed: () { _month = DateTime(_month.year, _month.month - 1); _selected.clear(); _reload(); },
                      icon: const Icon(Icons.chevron_left)),
                  Expanded(child: Center(child: Text(DateFormat('MMMM yyyy').format(_month), style: text.titleMedium))),
                  IconButton(onPressed: () { _month = DateTime(_month.year, _month.month + 1); _selected.clear(); _reload(); },
                      icon: const Icon(Icons.chevron_right)),
                ]),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final s in [null, 'Unpaid', 'Partial', 'Paid', 'Overdue', 'ToConfirm'])
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(switch (s) { null => 'All', 'Partial' => 'Part paid', 'ToConfirm' => 'To confirm', _ => s }),
                          selected: _status == s,
                          onSelected: (_) { _status = s; _reload(); },
                        ),
                      ),
                  ]),
                ),
                if (_classes.isNotEmpty)
                  DropdownButtonFormField<int?>(
                    value: _classId,
                    decoration: const InputDecoration(labelText: 'Class', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All classes')),
                      for (final c in _classes) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) { _classId = v; _selected.clear(); _reload(); },
                  ),
                const SizedBox(height: 8),
                Wrap(spacing: 8, runSpacing: 4, children: [
                  FilledButton.tonalIcon(onPressed: _working ? null : _generate, icon: const Icon(Icons.add), label: const Text('Create invoices')),
                  if (notSent > 0)
                    FilledButton.icon(onPressed: _working ? null : _sendUnsent, icon: const Icon(Icons.send_outlined),
                        label: Text('Send $notSent unsent')),
                  if ((m?.overdue ?? 0) > 0)
                    OutlinedButton.icon(onPressed: _working ? null : _remind, icon: const Icon(Icons.notifications_active_outlined),
                        label: Text('Remind ${m!.overdue} overdue')),
                ]),
                const SizedBox(height: 8),
                if (snap.connectionState == ConnectionState.waiting && m == null)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                else if (snap.hasError)
                  ErrorView(error: snap.error!, onRetry: _reload)
                else if (m != null) ...[
                  Row(children: [
                    _Stat('Billed', Fmt.money(m.billed), '${m.count} invoices'),
                    _Stat('Collected', Fmt.money(m.collected), '${m.paid} paid'),
                    _Stat('Outstanding', Fmt.money(m.outstanding), '${m.overdue} overdue'),
                  ]),
                  if (m.invoices.isEmpty)
                    const Padding(padding: EdgeInsets.all(32), child: Text('No invoices here. Use "Create invoices" for this month.', textAlign: TextAlign.center)),
                  for (final i in m.invoices)
                    Card(
                      margin: const EdgeInsets.only(bottom: 6),
                      child: ListTile(
                        contentPadding: const EdgeInsets.only(left: 4, right: 12),
                        leading: i.status == 'Void'
                            ? const SizedBox(width: 40)
                            : Checkbox(
                                value: _selected.contains(i.id),
                                onChanged: (v) => setState(() => v == true ? _selected.add(i.id) : _selected.remove(i.id)),
                              ),
                        onTap: () async {
                          await context.push('${Routes.schoolInvoice}/${i.id}');
                          _reload();
                        },
                        title: Text(i.studentName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${i.invoiceNo} · ${i.className ?? 'No class'}'
                            '${i.sent ? '' : ' · not sent'}${i.pendingClaim ? ' · paid? confirm' : ''}'),
                        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
                          Text(Fmt.money(i.balance > 0 ? i.balance : i.total), style: const TextStyle(fontWeight: FontWeight.w700)),
                          const SizedBox(height: 2),
                          Pill(i.statusLabel, tone: invoiceTone(i)),
                        ]),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, this.sub);
  final String label, value, sub;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(label, style: text.labelSmall),
            FittedBox(child: Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            Text(sub, style: text.bodySmall),
          ]),
        ),
      ),
    );
  }
}

/// On the invoice screen (admins): send / send again, change the lines, cancel the invoice.
class InvoiceAdminActions extends ConsumerWidget {
  const InvoiceAdminActions({super.key, required this.invoice, required this.onChanged});
  final Invoice invoice;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final i = invoice;
    if (i.status == 'Void') return const SizedBox.shrink();
    final admin = ref.read(schoolAdminProvider);
    return Wrap(spacing: 8, runSpacing: 4, children: [
      FilledButton.icon(
        onPressed: () async {
          if (await attempt(context, () async {
            final r = await admin.send(0, 0, invoiceIds: [i.id], resend: true);
            if (context.mounted) {
              toast(context, 'Sent to the parents${r.emailed > 0 ? ' (${r.emailed} email${r.emailed == 1 ? '' : 's'} with the PDF)' : ''}.');
            }
          })) {
            onChanged();
          }
        },
        icon: const Icon(Icons.send),
        label: Text(i.sent ? 'Send again' : 'Send to parents'),
      ),
      OutlinedButton.icon(
        onPressed: () async {
          final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => _EditLinesScreen(invoice: i)));
          if (saved == true) onChanged();
        },
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit lines'),
      ),
      if (i.payments.isEmpty)
        TextButton(
          onPressed: () async {
            final ctrl = TextEditingController();
            final reason = await showDialog<String>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text('Cancel invoice'),
                content: TextField(controller: ctrl, maxLength: 300,
                    decoration: const InputDecoration(labelText: 'Reason', hintText: 'e.g. Child left the school')),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Keep it')),
                  FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Cancel invoice')),
                ],
              ),
            );
            if (reason == null || reason.isEmpty || !context.mounted) return;
            if (await attempt(context, () => admin.voidInvoice(i.id, reason), done: 'Invoice cancelled')) onChanged();
          },
          child: Text('Cancel invoice', style: TextStyle(color: Theme.of(context).colorScheme.error)),
        ),
    ]);
  }
}

/// Change an invoice's lines (a discount is a minus amount), due date and note.
class _EditLinesScreen extends ConsumerStatefulWidget {
  const _EditLinesScreen({required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<_EditLinesScreen> createState() => _EditLinesScreenState();
}

class _EditLinesScreenState extends ConsumerState<_EditLinesScreen> {
  late final List<(TextEditingController, TextEditingController)> _lines = [
    for (final l in widget.invoice.lines)
      (TextEditingController(text: l.description), TextEditingController(text: l.amount.toStringAsFixed(2))),
  ];
  late final _notes = TextEditingController(text: widget.invoice.notes ?? '');
  late String _due = widget.invoice.dueDate;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final l in _lines) {
      l.$1.dispose();
      l.$2.dispose();
    }
    _notes.dispose();
    super.dispose();
  }

  double get _total => _lines.fold(0.0, (s, l) => s + (double.tryParse(l.$2.text.trim()) ?? 0));

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(schoolAdminProvider).updateInvoice(
          widget.invoice.id,
          [for (final l in _lines) (l.$1.text.trim(), double.tryParse(l.$2.text.trim()) ?? 0)],
          _due,
          _notes.text.trim().isEmpty ? null : _notes.text.trim());
      if (mounted) {
        toast(context, 'Saved');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit ${widget.invoice.invoiceNo}'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        for (var n = 0; n < _lines.length; n++)
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(flex: 3, child: TextField(controller: _lines[n].$1, maxLength: 150, decoration: const InputDecoration(labelText: 'Description'))),
            const SizedBox(width: 8),
            Expanded(
              flex: 2,
              child: TextField(
                controller: _lines[n].$2,
                keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                decoration: const InputDecoration(labelText: 'RM'),
                onChanged: (_) => setState(() {}),
              ),
            ),
            IconButton(onPressed: () => setState(() => _lines.removeAt(n)), icon: const Icon(Icons.close)),
          ]),
        Wrap(spacing: 8, children: [
          OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add((TextEditingController(), TextEditingController(text: '0.00')))),
            icon: const Icon(Icons.add), label: const Text('Add line'),
          ),
          OutlinedButton.icon(
            onPressed: () => setState(() => _lines.add((TextEditingController(text: 'Discount'), TextEditingController(text: '-0.00')))),
            icon: const Icon(Icons.remove), label: const Text('Add discount'),
          ),
        ]),
        const SizedBox(height: 8),
        Text('Total ${Fmt.money(_total)} · already paid ${Fmt.money(widget.invoice.amountPaid)}',
            style: const TextStyle(fontWeight: FontWeight.w700)),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Due date'),
          subtitle: Text(DateFormat('d MMM yyyy').format(ymdToDate(_due))),
          trailing: const Icon(Icons.event_outlined),
          onTap: () async {
            final d = await showDatePicker(context: context, initialDate: ymdToDate(_due),
                firstDate: ymdToDate(_due).subtract(const Duration(days: 365)), lastDate: ymdToDate(_due).add(const Duration(days: 365)));
            if (d != null) setState(() => _due = dateToYmd(d));
          },
        ),
        TextField(controller: _notes, maxLength: 500, decoration: const InputDecoration(labelText: 'Note on the invoice (optional)')),
      ]),
    );
  }
}

// ═══════════════════ Fee items ═══════════════════

final _feeItemsProvider = FutureProvider.autoDispose<List<FeeItem>>((ref) => ref.watch(schoolAdminProvider).feeItems());

class _FeeItemsTab extends ConsumerWidget {
  const _FeeItemsTab();

  Future<void> _edit(BuildContext context, WidgetRef ref, FeeItem? item, String kind) async {
    final saved = await showModalBottomSheet<bool>(
      context: context, isScrollControlled: true, showDragHandle: true,
      builder: (_) => _FeeItemSheet(item: item, kind: kind),
    );
    if (saved == true) ref.invalidate(_feeItemsProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_feeItemsProvider);
    final text = Theme.of(context).textTheme;
    Widget section(String title, String sub, String kind, List<FeeItem> items) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Padding(
            padding: const EdgeInsets.only(top: 12, bottom: 4),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text(sub, style: text.bodySmall),
              ])),
              TextButton.icon(onPressed: () => _edit(context, ref, null, kind), icon: const Icon(Icons.add), label: const Text('Add')),
            ]),
          ),
          if (items.isEmpty) const Card(child: Padding(padding: EdgeInsets.all(16), child: Text('None yet.'))),
          for (final i in items)
            Card(
              margin: const EdgeInsets.only(bottom: 6),
              child: ListTile(
                onTap: () => _edit(context, ref, i, kind),
                title: Text(i.name, style: TextStyle(fontWeight: FontWeight.w600, color: i.isActive ? null : Colors.grey)),
                subtitle: Text('${i.isSession ? '${i.sessionType} · ' : ''}${i.children} child${i.children == 1 ? '' : 'ren'}${i.isActive ? '' : ' · off'}'),
                trailing: Text(Fmt.money(i.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
            ),
        ]);
    return list.when(
      skipLoadingOnRefresh: true,
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_feeItemsProvider)),
      data: (items) => RefreshIndicator(
        onRefresh: () => ref.refresh(_feeItemsProvider.future),
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 0, 12, 24), children: [
          section('Monthly fee per session', 'Every child pays the fee for their session.', 'Session', items.where((i) => i.isSession).toList()),
          section('Add-ons', 'Optional extras, e.g. Mandarin. Tick children under Add-ons.', 'AddOn', items.where((i) => !i.isSession).toList()),
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text('A new price applies to invoices created from now on.', style: TextStyle(fontSize: 12)),
          ),
        ]),
      ),
    );
  }
}

class _FeeItemSheet extends ConsumerStatefulWidget {
  const _FeeItemSheet({this.item, required this.kind});
  final FeeItem? item;
  final String kind;

  @override
  ConsumerState<_FeeItemSheet> createState() => _FeeItemSheetState();
}

class _FeeItemSheetState extends ConsumerState<_FeeItemSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _amount = TextEditingController(text: widget.item?.amount.toStringAsFixed(2) ?? '');
  late String _kind = widget.item?.kind ?? widget.kind;
  late String _session = widget.item?.sessionType ?? 'Full day';
  late bool _active = widget.item?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(schoolAdminProvider).saveFeeItem(widget.item?.id, {
        'name': _name.text.trim(),
        'kind': _kind,
        'sessionType': _kind == 'Session' ? _session : null,
        'amount': double.tryParse(_amount.text.trim()) ?? 0,
        'sortOrder': widget.item?.sortOrder ?? 0,
        'isActive': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.item == null ? (_kind == 'Session' ? 'Add a session fee' : 'Add an add-on') : 'Edit fee item',
              style: Theme.of(context).textTheme.titleLarge),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          TextField(controller: _name, maxLength: 100,
              decoration: InputDecoration(labelText: 'Name', hintText: _kind == 'Session' ? 'e.g. Full day tuition' : 'e.g. Mandarin class')),
          DropdownButtonFormField<String>(
            value: _kind,
            decoration: const InputDecoration(labelText: 'Type'),
            items: const [
              DropdownMenuItem(value: 'Session', child: Text('Monthly session fee')),
              DropdownMenuItem(value: 'AddOn', child: Text('Add-on')),
            ],
            onChanged: (v) => setState(() => _kind = v ?? 'Session'),
          ),
          if (_kind == 'Session')
            DropdownButtonFormField<String>(
              value: _session,
              decoration: const InputDecoration(labelText: 'For session'),
              items: [for (final s in sessionTypes) DropdownMenuItem(value: s, child: Text(s))],
              onChanged: (v) => setState(() => _session = v ?? 'Full day'),
            ),
          TextField(controller: _amount, keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'Per month (RM)')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('In use'), value: _active, onChanged: (v) => setState(() => _active = v)),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          if (widget.item != null)
            TextButton(
              onPressed: () async {
                if (await attempt(context, () => ref.read(schoolAdminProvider).deleteFeeItem(widget.item!.id), done: 'Deleted') && mounted) {
                  Navigator.pop(context, true);
                }
              },
              child: Text('Delete', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
        ]),
      ),
    );
  }
}

// ═══════════════════ Add-ons per child ═══════════════════

class _AddOnsTab extends ConsumerStatefulWidget {
  const _AddOnsTab();

  @override
  ConsumerState<_AddOnsTab> createState() => _AddOnsTabState();
}

class _AddOnsTabState extends ConsumerState<_AddOnsTab> {
  late Future<(List<({int id, String name, double amount})>, List<AddOnChild>)> _load = ref.read(schoolAdminProvider).addOns();

  Future<void> _toggle(AddOnChild c, int itemId, bool on) async {
    final before = [...c.addOnIds];
    setState(() => on ? c.addOnIds.add(itemId) : c.addOnIds.remove(itemId));
    try {
      await ref.read(schoolAdminProvider).setAddOns(c.id, c.addOnIds);
    } catch (e) {
      if (!mounted) return;
      setState(() => c.addOnIds = before);
      toast(context, ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: _load,
      builder: (context, snap) {
        if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => setState(() => _load = ref.read(schoolAdminProvider).addOns()));
        if (!snap.hasData) return const Center(child: CircularProgressIndicator());
        final (items, kids) = snap.data!;
        if (items.isEmpty) {
          return const Center(child: Padding(padding: EdgeInsets.all(32),
              child: Text('No add-ons yet. Add them under Fee items (e.g. Mandarin), then tick the children here.', textAlign: TextAlign.center)));
        }
        return ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
          const Text('Saved as you tick. Included in invoices created from now on.', style: TextStyle(fontSize: 12)),
          for (final c in kids)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(c.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('${c.className ?? 'No class'} · ${c.sessionType}', style: Theme.of(context).textTheme.bodySmall),
                  Wrap(spacing: 6, children: [
                    for (final i in items)
                      FilterChip(
                        label: Text('${i.name} ${Fmt.money(i.amount)}'),
                        selected: c.addOnIds.contains(i.id),
                        onSelected: (v) => _toggle(c, i.id, v),
                      ),
                  ]),
                ]),
              ),
            ),
        ]);
      },
    );
  }
}

// ═══════════════════ Settings ═══════════════════

class _SettingsTab extends ConsumerStatefulWidget {
  const _SettingsTab();

  @override
  ConsumerState<_SettingsTab> createState() => _SettingsTabState();
}

class _SettingsTabState extends ConsumerState<_SettingsTab> {
  final _disc = TextEditingController();
  final _due = TextEditingController();
  final _how = TextEditingController();
  bool _loaded = false;
  bool _saving = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    ref.read(schoolAdminProvider).feeSettings().then((s) {
      if (!mounted) return;
      setState(() {
        _disc.text = s.siblingDiscountPercent.toString();
        _due.text = '${s.feeDueDay}';
        _how.text = s.paymentInstructions ?? '';
        _loaded = true;
      });
    }).catchError((Object e) {
      if (mounted) setState(() => _error = e);
    });
  }

  @override
  void dispose() {
    _disc.dispose();
    _due.dispose();
    _how.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) return ErrorView(error: _error!, onRetry: () {});
    if (!_loaded) return const Center(child: CircularProgressIndicator());
    return ListView(padding: const EdgeInsets.all(16), children: [
      TextField(controller: _disc, keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Sibling discount (%)',
              helperText: 'Off the 2nd and later child of a family; the eldest pays in full. 0 = none.')),
      const SizedBox(height: 12),
      TextField(controller: _due, keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Fees due on day (1–28)')),
      const SizedBox(height: 12),
      TextField(controller: _how, maxLength: 1000, minLines: 3, maxLines: 6,
          decoration: const InputDecoration(labelText: 'How to pay (on invoices and for parents)', alignLabelWithHint: true,
              hintText: 'e.g. Maybank 5123 4567 8901 (Golden Montessori Sdn Bhd)')),
      const SizedBox(height: 8),
      FilledButton(
        onPressed: _saving
            ? null
            : () async {
                setState(() => _saving = true);
                await attempt(context, () => ref.read(schoolAdminProvider).saveFeeSettings(FeeSettings(
                      siblingDiscountPercent: double.tryParse(_disc.text.trim()) ?? 0,
                      feeDueDay: int.tryParse(_due.text.trim()) ?? 7,
                      paymentInstructions: _how.text.trim().isEmpty ? null : _how.text.trim(),
                    )), done: 'Fee settings saved');
                if (mounted) setState(() => _saving = false);
              },
        child: Text(_saving ? 'Saving…' : 'Save settings'),
      ),
    ]);
  }
}
