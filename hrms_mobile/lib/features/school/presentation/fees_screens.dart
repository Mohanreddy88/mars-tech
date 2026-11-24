import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import '../data/price_lists.dart' show currentPriceListProvider;
import 'fees_admin_screens.dart';
import 'price_lists_screens.dart' show PriceTermsCard;
import 'school_widgets.dart';

String _due(String ymd) => ymd.isEmpty ? '' : DateFormat('d MMM yyyy').format(ymdToDate(ymd));

/// Parent → Fees: what's still to pay, how to pay, each invoice with its receipts.
class ParentFeesScreen extends ConsumerWidget {
  const ParentFeesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fees = ref.watch(myFeesProvider);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Fees')),
      body: fees.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(myFeesProvider)),
        data: (f) {
          final unpaid = f.invoices.where((i) => i.balance > 0).toList();
          final paid = f.invoices.where((i) => i.balance <= 0).toList();
          return RefreshIndicator(
            onRefresh: () {
              ref.invalidate(currentPriceListProvider);
              return ref.refresh(myFeesProvider.future);
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: f.outstanding > 0 ? scheme.primary : const Color(0xFF16A34A),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(f.outstanding > 0 ? 'To pay' : 'All paid',
                            style: text.bodyMedium?.copyWith(color: Colors.white70)),
                        Text(Fmt.money(f.outstanding),
                            style: text.headlineMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                        if (f.outstanding <= 0 && f.invoices.isNotEmpty)
                          Text('No invoices pending — thank you!', style: text.bodySmall?.copyWith(color: Colors.white)),
                      ]),
                    ),
                    Icon(f.outstanding > 0 ? Icons.account_balance_wallet_outlined : Icons.check_circle,
                        color: Colors.white, size: 36),
                  ]),
                ),
                if (f.paymentInstructions != null && f.outstanding > 0) ...[
                  const SizedBox(height: 12),
                  Card(
                    color: const Color(0xFFF0F9FF),
                    child: Padding(
                      padding: const EdgeInsets.all(14),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('How to pay', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        Text(f.paymentInstructions!),
                      ]),
                    ),
                  ),
                ],
                if (f.invoices.isEmpty)
                  const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No invoices yet.'))),
                if (unpaid.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('To pay', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  for (final i in unpaid) _InvoiceTile(i: i, initiallyExpanded: true),
                ],
                if (paid.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  Text('Paid', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                  for (final i in paid) _InvoiceTile(i: i),
                ],
                // This year's Price & Terms (from the school's price list)
                const SizedBox(height: 16),
                const PriceTermsCard(),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _InvoiceTile extends ConsumerWidget {
  const _InvoiceTile({required this.i, this.initiallyExpanded = false});
  final Invoice i;
  final bool initiallyExpanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.read(schoolRepositoryProvider);
    return Card(
      margin: const EdgeInsets.only(top: 8),
      clipBehavior: Clip.antiAlias,
      child: ExpansionTile(
        initiallyExpanded: initiallyExpanded,
        title: Text('${i.monthName} · ${i.studentName}', style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text('${i.invoiceNo} · due ${_due(i.dueDate)}'),
        trailing: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(Fmt.money(i.balance > 0 ? i.balance : i.total), style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 2),
          Pill(i.statusLabel, tone: invoiceTone(i)),
        ]),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [_InvoiceBody(i: i, repo: repo, parent: true)],
      ),
    );
  }
}

/// Lines, totals, payments with receipt PDFs, invoice PDF.
class _InvoiceBody extends ConsumerWidget {
  const _InvoiceBody({required this.i, required this.repo, this.parent = false});
  final Invoice i;
  final SchoolRepository repo;
  final bool parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final waiting = i.waitingClaim;
    final rejected = i.rejectedClaim;
    Widget line(String l, double v, {bool bold = false}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(children: [
            Expanded(child: Text(l, style: bold ? const TextStyle(fontWeight: FontWeight.w700) : null)),
            Text(v < 0 ? '- ${Fmt.money(-v)}' : Fmt.money(v),
                style: TextStyle(fontWeight: bold ? FontWeight.w700 : null, color: v < 0 ? const Color(0xFF15803D) : null)),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      for (final l in i.lines) line(l.description, l.amount),
      const Divider(),
      line('Total', i.total, bold: true),
      if (i.amountPaid > 0) line('Paid', -i.amountPaid),
      line('Balance', i.balance, bold: true),
      if (i.notes != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(i.notes!, style: const TextStyle(fontStyle: FontStyle.italic))),
      for (final p in i.payments)
        ListTile(
          contentPadding: EdgeInsets.zero,
          dense: true,
          leading: const Icon(Icons.check_circle, color: Color(0xFF16A34A)),
          title: Text('${Fmt.money(p.amount)} · ${_due(p.paidOn)} · ${p.method}'),
          subtitle: Text('Receipt ${p.receiptNo}${p.reference != null ? ' · ${p.reference}' : ''}'),
          trailing: IconButton(
            tooltip: 'Receipt PDF',
            icon: const Icon(Icons.picture_as_pdf_outlined),
            onPressed: () => openBytes(context, () => repo.receiptPdf(p.id), '${p.receiptNo}.pdf'),
          ),
        ),
      if (waiting != null)
        _Banner(
          color: const Color(0xFFFFFBEB),
          text: parent
              ? 'You reported paying ${Fmt.money(waiting.amount)} on ${_due(waiting.paidOn)}. Waiting for the school to confirm.'
              : '${waiting.createdByName} reported paying ${Fmt.money(waiting.amount)} (${waiting.method}). See "To confirm".',
        )
      else if (rejected != null)
        _Banner(color: const Color(0xFFFEF2F2), text: 'Payment of ${Fmt.money(rejected.amount)} not confirmed: ${rejected.rejectReason ?? ''}'),
      const SizedBox(height: 4),
      if (parent && i.balance > 0 && waiting == null)
        FilledButton.icon(
          onPressed: () async {
            final sent = await showModalBottomSheet<bool>(
              context: context,
              isScrollControlled: true,
              showDragHandle: true,
              builder: (_) => _ClaimSheet(invoice: i),
            );
            if (sent == true) ref.invalidate(myFeesProvider);
          },
          icon: const Icon(Icons.check_circle_outline),
          label: const Text("I've paid"),
        ),
      OutlinedButton.icon(
        onPressed: () => openBytes(context, () => repo.invoicePdf(i.id), '${i.invoiceNo}.pdf'),
        icon: const Icon(Icons.picture_as_pdf_outlined),
        label: const Text('Invoice PDF'),
      ),
    ]);
  }
}

/// Admin → one invoice: lines, payments, PDFs, record a payment.
class InvoiceScreen extends ConsumerStatefulWidget {
  const InvoiceScreen({super.key, required this.invoiceId});
  final int invoiceId;

  @override
  ConsumerState<InvoiceScreen> createState() => _InvoiceScreenState();
}

class _InvoiceScreenState extends ConsumerState<InvoiceScreen> {
  Invoice? _inv;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final i = await ref.read(schoolRepositoryProvider).invoice(widget.invoiceId);
      if (mounted) setState(() => _inv = i);
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _pay(Invoice i) async {
    final updated = await showModalBottomSheet<Invoice>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PaymentSheet(invoice: i),
    );
    if (updated != null && mounted) setState(() => _inv = updated);
  }

  @override
  Widget build(BuildContext context) {
    final i = _inv;
    final repo = ref.read(schoolRepositoryProvider);
    return Scaffold(
      appBar: AppBar(title: Text(i?.invoiceNo ?? 'Invoice')),
      floatingActionButton: i != null && i.status != 'Void' && i.balance > 0
          ? FloatingActionButton.extended(
              onPressed: () => _pay(i),
              icon: const Icon(Icons.payments_outlined),
              label: const Text('Record payment'),
            )
          : null,
      body: _error != null
          ? ErrorView(error: _error!, onRetry: _load)
          : i == null
              ? const Center(child: CircularProgressIndicator())
              : ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 96), children: [
                  Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(i.studentName, style: Theme.of(context).textTheme.titleLarge),
                        Text('${i.monthName} · due ${_due(i.dueDate)}${i.sent ? '' : ' · not sent yet'}'),
                      ]),
                    ),
                    Pill(i.statusLabel, tone: invoiceTone(i)),
                  ]),
                  const SizedBox(height: 12),
                  Card(child: Padding(padding: const EdgeInsets.all(14), child: _InvoiceBody(i: i, repo: repo))),
                  const SizedBox(height: 8),
                  InvoiceAdminActions(invoice: i, onChanged: _load),
                ]),
    );
  }
}

class _PaymentSheet extends ConsumerStatefulWidget {
  const _PaymentSheet({required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<_PaymentSheet> createState() => _PaymentSheetState();
}

class _PaymentSheetState extends ConsumerState<_PaymentSheet> {
  late final _amount = TextEditingController(text: widget.invoice.balance.toStringAsFixed(2));
  final _ref = TextEditingController();
  String _method = 'Cash';
  String _date = schoolToday();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount received.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final inv = await ref.read(schoolRepositoryProvider).addPayment(widget.invoice.id,
          amount: amount, paidOn: _date, method: _method, reference: _ref.text.trim().isEmpty ? null : _ref.text.trim());
      if (mounted) {
        toast(context, 'Payment recorded. Receipt ${inv.payments.isEmpty ? '' : inv.payments.last.receiptNo}');
        Navigator.pop(context, inv);
      }
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
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Record payment', style: Theme.of(context).textTheme.titleLarge),
        Text('Balance ${Fmt.money(widget.invoice.balance)}'),
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        const SizedBox(height: 8),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(labelText: 'Amount received (RM)'),
        ),
        DropdownButtonFormField<String>(
          value: _method,
          decoration: const InputDecoration(labelText: 'Method'),
          items: [for (final m in paymentMethods) DropdownMenuItem(value: m, child: Text(m))],
          onChanged: (v) => setState(() => _method = v ?? 'Cash'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.event_outlined),
          title: const Text('Paid on'),
          subtitle: Text(_due(_date)),
          onTap: () async {
            final d = await showDatePicker(
              context: context,
              initialDate: ymdToDate(_date),
              firstDate: ymdToDate(schoolToday()).subtract(const Duration(days: 365)),
              lastDate: ymdToDate(schoolToday()),
            );
            if (d != null) setState(() => _date = dateToYmd(d));
          },
        ),
        TextField(controller: _ref, maxLength: 100, decoration: const InputDecoration(labelText: 'Reference (optional)')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Record payment'),
        ),
      ]),
    );
  }
}


class _Banner extends StatelessWidget {
  const _Banner({required this.color, required this.text});
  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(top: 8),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(8)),
        child: Text(text),
      );
}

/// Parent: "I've paid" — amount, date, how, reference, a photo of the transfer slip.
class _ClaimSheet extends ConsumerStatefulWidget {
  const _ClaimSheet({required this.invoice});
  final Invoice invoice;

  @override
  ConsumerState<_ClaimSheet> createState() => _ClaimSheetState();
}

class _ClaimSheetState extends ConsumerState<_ClaimSheet> {
  late final _amount = TextEditingController(text: widget.invoice.balance.toStringAsFixed(2));
  final _ref = TextEditingController();
  final _note = TextEditingController();
  String _method = 'Bank transfer';
  String _date = schoolToday();
  PickedFile? _slip;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _amount.dispose();
    _ref.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter the amount you paid.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(schoolRepositoryProvider).createClaim(widget.invoice.id,
          amount: amount, paidOn: _date, method: _method,
          reference: _ref.text.trim().isEmpty ? null : _ref.text.trim(),
          note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          slip: _slip);
      if (mounted) {
        toast(context, 'Sent. The school will check it and send your receipt.');
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text("I've paid", style: Theme.of(context).textTheme.titleLarge),
          Text('${widget.invoice.monthName} · ${widget.invoice.studentName} · balance ${Fmt.money(widget.invoice.balance)}'),
          if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          const SizedBox(height: 8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Amount paid (RM)'),
          ),
          DropdownButtonFormField<String>(
            value: _method,
            decoration: const InputDecoration(labelText: 'How'),
            items: [for (final m in paymentMethods.where((m) => m != 'Cash')) DropdownMenuItem(value: m, child: Text(m))],
            onChanged: (v) => setState(() => _method = v ?? 'Bank transfer'),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: const Text('Date paid'),
            subtitle: Text(_due(_date)),
            onTap: () async {
              final d = await showDatePicker(
                context: context,
                initialDate: ymdToDate(_date),
                firstDate: ymdToDate(schoolToday()).subtract(const Duration(days: 120)),
                lastDate: ymdToDate(schoolToday()),
              );
              if (d != null) setState(() => _date = dateToYmd(d));
            },
          ),
          TextField(controller: _ref, maxLength: 100, decoration: const InputDecoration(labelText: 'Reference (optional)')),
          if (_slip == null)
            OutlinedButton.icon(
              onPressed: () async {
                final f = await pickPhoto(context);
                if (f != null) setState(() => _slip = f);
              },
              icon: const Icon(Icons.receipt_long_outlined),
              label: const Text('Add the transfer slip (recommended)'),
            )
          else
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.image_outlined),
              title: Text(_slip!.name, overflow: TextOverflow.ellipsis),
              trailing: IconButton(onPressed: () => setState(() => _slip = null), icon: const Icon(Icons.close)),
            ),
          TextField(controller: _note, maxLength: 500, decoration: const InputDecoration(labelText: 'Note (optional)')),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send to the school'),
          ),
        ]),
      ),
    );
  }
}

/// Admin: payments parents reported — view the slip, confirm (payment + receipt) or say why not.
class ClaimsScreen extends ConsumerStatefulWidget {
  const ClaimsScreen({super.key, this.embedded = false});

  /// Inside the Fees tabs (no app bar of its own).
  final bool embedded;

  @override
  ConsumerState<ClaimsScreen> createState() => _ClaimsScreenState();
}

class _ClaimsScreenState extends ConsumerState<ClaimsScreen> {
  late Future<List<PaymentClaim>> _load = ref.read(schoolRepositoryProvider).claims();
  int? _busy;

  void _reload() => setState(() => _load = ref.read(schoolRepositoryProvider).claims());

  Future<void> _confirm(PaymentClaim c) async {
    setState(() => _busy = c.id);
    final ok = await attempt(context, () => ref.read(schoolRepositoryProvider).confirmClaim(c.id),
        done: 'Confirmed. Receipt sent to ${c.createdByName}.');
    if (mounted) setState(() => _busy = null);
    if (ok) _reload();
  }

  Future<void> _reject(PaymentClaim c) async {
    final ctrl = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Not confirmed'),
        content: TextField(
          controller: ctrl,
          maxLength: 300,
          decoration: const InputDecoration(labelText: 'Tell the parent why', hintText: 'e.g. Not received in our account yet'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Send')),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !mounted) return;
    if (await attempt(context, () => ref.read(schoolRepositoryProvider).rejectClaim(c.id, reason), done: 'The parent was told.')) {
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final body = FutureBuilder<List<PaymentClaim>>(
        future: _load,
        builder: (context, snap) {
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: _reload);
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final list = snap.data!;
          if (list.isEmpty) return const Center(child: Text('Nothing to confirm.'));
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final c = list[i];
                return Card(
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${c.studentName} · ${Fmt.money(c.amount)}', style: const TextStyle(fontWeight: FontWeight.w700)),
                      Text('${c.invoiceNo} · balance ${Fmt.money(c.invoiceBalance)}'),
                      Text('${_due(c.paidOn)} · ${c.method}${c.reference != null ? ' · Ref ${c.reference}' : ''}'),
                      Text('From ${c.createdByName}${c.note != null ? ': "${c.note}"' : ''}', style: Theme.of(context).textTheme.bodySmall),
                      const SizedBox(height: 8),
                      Wrap(spacing: 8, runSpacing: 4, children: [
                        if (c.hasSlip)
                          OutlinedButton.icon(
                            onPressed: () => openBytes(context, () => ref.read(schoolRepositoryProvider).claimSlip(c.id),
                                c.slipName ?? (c.slipIsPdf ? 'slip.pdf' : 'slip.jpg')),
                            icon: const Icon(Icons.receipt_long_outlined),
                            label: const Text('Slip'),
                          ),
                        FilledButton.icon(
                          onPressed: _busy == c.id ? null : () => _confirm(c),
                          icon: const Icon(Icons.check),
                          label: const Text('Confirm'),
                        ),
                        TextButton(onPressed: _busy == c.id ? null : () => _reject(c), child: const Text('Not received')),
                      ]),
                    ]),
                  ),
                );
              },
            ),
          );
        },
      );
    if (widget.embedded) return body;
    return Scaffold(appBar: AppBar(title: const Text('Payments to confirm')), body: body);
  }
}
