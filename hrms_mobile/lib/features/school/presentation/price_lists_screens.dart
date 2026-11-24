import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/price_lists.dart';
import '../data/school_admin.dart' show money;
import '../data/school_repository.dart';
import 'school_widgets.dart';
import 'setup_widgets.dart';

// School → Fees → Price lists and Deposits (admins), and Price & Terms (parents). Same as the website.

String _date(String ymd) {
  final d = DateTime.tryParse(ymd);
  return d == null ? ymd : DateFormat('d MMM yyyy').format(d);
}

/// Fees → Price lists: one per academic year; tap to edit, "New year" copies the last one.
class PriceListsTab extends ConsumerWidget {
  const PriceListsTab({super.key});

  Future<void> _new(BuildContext context, WidgetRef ref, List<PriceListRec> lists) async {
    final year = DateTime.now().year + 1;
    final name = TextEditingController(text: '$year');
    var from = DateTime(year - 1, 11, 1);
    int? copyFrom = lists.where((l) => l.current).firstOrNull?.id ?? lists.firstOrNull?.id;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: const Text('New year\'s price list'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(controller: name, decoration: boxDecoration('Name', hint: '2027')),
            formGap,
            DateField(
              label: 'Prices apply from', value: DateFormat('yyyy-MM-dd').format(from), icon: Icons.event,
              firstDate: DateTime(2020), lastDate: DateTime(2100),
              onChanged: (v) => set(() => from = v == null ? from : DateTime.parse(v)),
            ),
            formGap,
            DropdownButtonFormField<int?>(
              value: copyFrom,
              decoration: boxDecoration('Copy from'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Start fresh')),
                for (final l in lists) DropdownMenuItem(value: l.id, child: Text(l.name)),
              ],
              onChanged: (v) => set(() => copyFrom = v),
            ),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Create')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      final p = await ref.read(priceListsRepositoryProvider).create(name.text.trim(), DateFormat('yyyy-MM-dd').format(from), copyFrom);
      ref.invalidate(priceListsProvider);
      if (context.mounted) {
        await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PriceListScreen(list: p)));
        ref.invalidate(priceListsProvider);
      }
    } catch (e) {
      if (context.mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(priceListsProvider);
    return lists.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(priceListsProvider)),
      data: (all) => RefreshIndicator(
        onRefresh: () => ref.refresh(priceListsProvider.future),
        child: ListView(padding: const EdgeInsets.fromLTRB(12, 12, 12, 88), children: [
          const Text('One price list per academic year: session hours, meals, monthly fees, registration, supplies and '
              'deposit. Invoices use the one in force; its hours also set the school timings.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 10),
          FilledButton.icon(onPressed: () => _new(context, ref, all), icon: const Icon(Icons.add), label: const Text('New year\'s price list')),
          const SizedBox(height: 10),
          if (all.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No price list yet.'))),
          for (final l in all)
            Card(
              child: ListTile(
                title: Text('Price & Terms ${l.name}', style: const TextStyle(fontWeight: FontWeight.w700)),
                subtitle: Text('From ${_date(l.effectiveFrom)}\n'
                    '${l.offered.map((s) => '${s.sessionType} ${s.start}–${s.end} · ${money(s.monthlyFee)}').join('\n')}'),
                isThreeLine: true,
                trailing: l.current ? const Pill('In force', tone: PillTone.good) : const Icon(Icons.chevron_right),
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute(builder: (_) => PriceListScreen(list: l)));
                  ref.invalidate(priceListsProvider);
                },
              ),
            ),
        ]),
      ),
    );
  }
}

/// Edit one price list: sessions (offered, hours, meals, monthly fee), other charges, twice-a-year months, terms.
class PriceListScreen extends ConsumerStatefulWidget {
  const PriceListScreen({super.key, required this.list});
  final PriceListRec list;

  @override
  ConsumerState<PriceListScreen> createState() => _PriceListScreenState();
}

class _PriceListScreenState extends ConsumerState<PriceListScreen> {
  late final PriceListRec p = PriceListRec.fromJson({...widget.list.toJson(), 'current': widget.list.current});
  late final _terms = TextEditingController(text: p.terms ?? '');
  bool _saving = false;
  String? _error;
  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  @override
  void dispose() {
    _terms.dispose();
    super.dispose();
  }

  Set<int> get _twice => p.twiceAYearMonths.split(',').map((e) => int.tryParse(e.trim()) ?? 0).where((m) => m > 0).toSet();

  double _upon(PriceSession s) =>
      s.monthlyFee + p.charges.where((c) => c.kind != 'Deposit' && (c.sessionType == null || c.sessionType == s.sessionType)).fold(0.0, (a, c) => a + c.amount);
  double _second(PriceSession s) =>
      s.monthlyFee + p.charges.where((c) => c.kind == 'Deposit' && (c.sessionType == null || c.sessionType == s.sessionType)).fold(0.0, (a, c) => a + c.amount);

  Future<String?> _time(String current) async {
    final parts = current.split(':');
    final t = await showTimePicker(
        context: context, initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 8, minute: int.tryParse(parts.last) ?? 0));
    return t == null ? null : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    p.terms = _terms.text.trim().isEmpty ? null : _terms.text.trim();
    try {
      await ref.read(priceListsRepositoryProvider).save(p);
      if (mounted) {
        toast(context, 'Price list saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _editCharge(PriceCharge? existing) async {
    final c = existing ?? PriceCharge(name: '', kind: 'OneTime', amount: 0);
    final name = TextEditingController(text: c.name);
    final amount = TextEditingController(text: c.amount == 0 ? '' : c.amount.toStringAsFixed(2));
    var kind = c.kind;
    String? session = c.sessionType;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text(existing == null ? 'Add charge' : 'Edit charge'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              TextField(controller: name, decoration: boxDecoration('Name', hint: 'e.g. Registration')),
              formGap,
              DropdownButtonFormField<String>(
                value: kind,
                isExpanded: true,
                decoration: boxDecoration('When'),
                items: [for (final e in chargeKinds.entries) DropdownMenuItem(value: e.key, child: Text(e.value))],
                onChanged: (v) => set(() => kind = v ?? 'OneTime'),
              ),
              formGap,
              TextField(controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true), decoration: boxDecoration('Amount (RM)')),
              formGap,
              DropdownButtonFormField<String?>(
                value: session,
                decoration: boxDecoration('For'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('Every child')),
                  for (final s in p.sessions) DropdownMenuItem(value: s.sessionType, child: Text('${s.sessionType} only')),
                ],
                onChanged: (v) => set(() => session = v),
              ),
            ]),
          ),
          actions: [
            if (existing != null) TextButton(onPressed: () => Navigator.pop(ctx, 'delete'), child: const Text('Remove')),
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, 'ok'), child: const Text('OK')),
          ],
        ),
      ),
    );
    if (result == null) return;
    setState(() {
      if (result == 'delete') {
        p.charges.remove(existing);
        return;
      }
      c
        ..name = name.text.trim()
        ..kind = kind
        ..amount = double.tryParse(amount.text.trim()) ?? 0
        ..sessionType = session;
      if (existing == null) p.charges.add(c);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text('Price list ${p.name}'),
        actions: [
          IconButton(
            tooltip: 'Price & Terms PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => openBytes(context, () => ref.read(schoolRepositoryProvider).priceListPdf(p.id), 'Price-and-Terms-${p.name}.pdf'),
          ),
          TextButton(onPressed: _saving ? null : _save, child: const Text('Save')),
        ],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (_error != null) Padding(padding: const EdgeInsets.only(bottom: 10), child: Text(_error!, style: TextStyle(color: theme.colorScheme.error))),
        ...spaced([
          TextFormField(initialValue: p.name, decoration: boxDecoration('Name', hint: '2027'), onChanged: (v) => p.name = v.trim()),
          DateField(
            label: 'Prices apply from', value: p.effectiveFrom, icon: Icons.event,
            firstDate: DateTime(2020), lastDate: DateTime(2100),
            onChanged: (v) => setState(() => p.effectiveFrom = v ?? p.effectiveFrom),
          ),
        ]),
        const SectionTitle('Sessions', subtitle: 'Hours, meals and monthly fee. Daycare is optional.'),
        for (final s in p.sessions)
          Card(
            margin: const EdgeInsets.only(top: 8),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.sessionType, style: const TextStyle(fontWeight: FontWeight.w700)),
                  subtitle: Text(s.offered ? 'Offered' : 'Not offered this year'),
                  value: s.offered,
                  onChanged: (v) => setState(() => s.offered = v),
                ),
                if (s.offered) ...[
                  Row(children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.login, size: 18),
                        label: Text('Starts ${s.start}'),
                        onPressed: () async {
                          final t = await _time(s.start);
                          if (t != null) setState(() => s.start = t);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.logout, size: 18),
                        label: Text('Ends ${s.end}'),
                        onPressed: () async {
                          final t = await _time(s.end);
                          if (t != null) setState(() => s.end = t);
                        },
                      ),
                    ),
                  ]),
                  formGap,
                  TextFormField(
                    initialValue: s.monthlyFee == 0 ? '' : s.monthlyFee.toStringAsFixed(2),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: boxDecoration('Monthly fee (RM)', icon: Icons.payments_outlined),
                    onChanged: (v) => setState(() => s.monthlyFee = double.tryParse(v.trim()) ?? 0),
                  ),
                  formGap,
                  TextFormField(
                    initialValue: s.mealsIncluded ?? '',
                    decoration: boxDecoration('Meals included', hint: 'breakfast, lunch & tea-break', icon: Icons.restaurant_outlined),
                    onChanged: (v) => s.mealsIncluded = v.trim().isEmpty ? null : v.trim(),
                  ),
                  const SizedBox(height: 8),
                  Text('Upon registration ${money(_upon(s))} · 2nd month ${money(_second(s))}',
                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600)),
                ],
              ]),
            ),
          ),
        const SectionTitle('Other charges', subtitle: 'Registration, uniform, supplies, deposit…'),
        for (final c in p.charges)
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(c.name.isEmpty ? '(no name)' : c.name),
            subtitle: Text('${chargeKinds[c.kind] ?? c.kind} · ${c.sessionType == null ? 'every child' : '${c.sessionType} only'}'),
            trailing: Text(money(c.amount), style: const TextStyle(fontWeight: FontWeight.w700)),
            onTap: () => _editCharge(c),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(onPressed: () => _editCharge(null), icon: const Icon(Icons.add), label: const Text('Add charge')),
        ),
        const SectionTitle('Twice-a-year charges are billed in', subtitle: 'Also at registration; not again within 3 months of joining.'),
        Wrap(spacing: 6, children: [
          for (var m = 1; m <= 12; m++)
            FilterChip(
              label: Text(_months[m - 1]),
              selected: _twice.contains(m),
              onSelected: (on) => setState(() {
                final set = _twice;
                on ? set.add(m) : set.remove(m);
                p.twiceAYearMonths = (set.toList()..sort()).join(',');
              }),
            ),
        ]),
        const SectionTitle('Terms (printed under the prices)'),
        formGap,
        TextField(controller: _terms, maxLines: 4, minLines: 2, maxLength: 2000, decoration: boxDecoration('Terms', hint: 'School fees are collected monthly…')),
        const SizedBox(height: 12),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save price list')),
        if (DateTime.tryParse(p.effectiveFrom)?.isAfter(DateTime.now()) ?? false)
          TextButton(
            onPressed: () async {
              if (await attempt(context, () => ref.read(priceListsRepositoryProvider).delete(p.id), done: 'Deleted') && context.mounted) {
                Navigator.pop(context);
              }
            },
            child: Text('Delete price list', style: TextStyle(color: theme.colorScheme.error)),
          ),
      ]),
    );
  }
}

final _depositsProvider = FutureProvider.autoDispose.family<List<DepositRec>, bool>(
    (ref, all) => ref.watch(priceListsRepositoryProvider).deposits(all: all));

/// Fees → Deposits: refundable deposits held; return by refund or by deducting from an unpaid invoice.
class DepositsTab extends ConsumerStatefulWidget {
  const DepositsTab({super.key});

  @override
  ConsumerState<DepositsTab> createState() => _DepositsTabState();
}

class _DepositsTabState extends ConsumerState<DepositsTab> {
  bool _all = false;

  Future<void> _return(DepositRec d) async {
    var how = 'refund';
    int? invoiceId = d.openInvoices.firstOrNull?.id;
    final note = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          title: Text('Return ${d.childName}\'s deposit (${money(d.amount)})'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero, value: 'refund', groupValue: how,
                title: const Text('Refunded (cash or bank transfer)'), onChanged: (v) => set(() => how = v!),
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero, value: 'deduct', groupValue: how,
                title: Text('Deduct from an unpaid invoice${d.openInvoices.isEmpty ? ' (none unpaid)' : ''}'),
                onChanged: d.openInvoices.isEmpty ? null : (v) => set(() => how = v!),
              ),
              if (how == 'deduct')
                DropdownButtonFormField<int>(
                  value: invoiceId,
                  isExpanded: true,
                  decoration: boxDecoration('Invoice'),
                  items: [
                    for (final i in d.openInvoices)
                      DropdownMenuItem(value: i.id, child: Text('${i.invoiceNo} · balance ${money(i.balance)}')),
                  ],
                  onChanged: (v) => set(() => invoiceId = v),
                ),
              formGap,
              TextField(controller: note, decoration: boxDecoration('Note (optional)', hint: 'e.g. Bank transfer 12 Dec')),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    if (await attempt(context,
        () => ref.read(priceListsRepositoryProvider).settle(d.id, how, invoiceId: how == 'deduct' ? invoiceId : null,
            note: note.text.trim().isEmpty ? null : note.text.trim()),
        done: 'Deposit returned')) {
      ref.invalidate(_depositsProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_depositsProvider(_all));
    return list.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_depositsProvider)),
      data: (rows) {
        final held = rows.where((r) => r.held).fold(0.0, (a, r) => a + r.amount);
        return RefreshIndicator(
          onRefresh: () => ref.refresh(_depositsProvider(_all).future),
          child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 24), children: [
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Show returned deposits too'),
              value: _all,
              onChanged: (v) => setState(() => _all = v),
            ),
            Text('Held: ${money(held)}', style: const TextStyle(fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            if (rows.isEmpty) const Padding(padding: EdgeInsets.all(24), child: Center(child: Text('No deposits held.'))),
            for (final d in rows)
              Card(
                child: ListTile(
                  title: Text('${d.childName}${d.className != null ? ' · ${d.className}' : ''}'),
                  subtitle: Text([
                    '${d.description} ${money(d.amount)}',
                    if (d.invoiceNo != null) 'billed on ${d.invoiceNo}',
                    if (d.note != null) d.note!,
                  ].join(' · ')),
                  trailing: d.held
                      ? TextButton(onPressed: () => _return(d), child: const Text('Return'))
                      : Pill(d.status, tone: PillTone.good),
                ),
              ),
          ]),
        );
      },
    );
  }
}

/// Parents: this year's "Price & Terms" (from the price list in force), with the PDF.
class PriceTermsCard extends ConsumerWidget {
  const PriceTermsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = ref.watch(currentPriceListProvider).valueOrNull;
    if (p == null) return const SizedBox.shrink();
    final text = Theme.of(context).textTheme;
    Widget row(String label, String value, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(children: [
            Expanded(child: Text(label)),
            Text(value, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            Expanded(child: Text('Price & Terms, ${p.name}', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            IconButton(
              tooltip: 'PDF',
              icon: const Icon(Icons.picture_as_pdf_outlined),
              onPressed: () => openBytes(context, () => ref.read(schoolRepositoryProvider).priceListPdf(p.id), 'Price-and-Terms-${p.name}.pdf'),
            ),
          ]),
          Text('From ${_date(p.effectiveFrom)}', style: text.bodySmall),
          for (final s in p.offered) ...[
            const Divider(),
            Text(s.sessionType, style: const TextStyle(fontWeight: FontWeight.w700)),
            row('Hours', '${s.start} – ${s.end}'),
            row('Monthly school fees', money(s.monthlyFee), bold: true),
            if (s.mealsIncluded != null) row('Meals included', s.mealsIncluded!),
            for (final c in p.charges.where((c) => c.kind != 'Deposit' && (c.sessionType == null || c.sessionType == s.sessionType)))
              row(c.kind == 'TwiceAYear' ? '${c.name} (twice a year)' : c.name, money(c.amount)),
            row('Total upon registration', money(s.uponRegistration), bold: true),
            for (final d in p.charges.where((c) => c.kind == 'Deposit' && (c.sessionType == null || c.sessionType == s.sessionType)))
              row('${d.name} (refundable, 2nd month)', money(d.amount)),
            if (s.secondMonth != s.monthlyFee) row('2nd month payable', money(s.secondMonth), bold: true),
          ],
          if (p.terms != null) ...[const Divider(), Text(p.terms!, style: text.bodySmall)],
        ]),
      ),
    );
  }
}
