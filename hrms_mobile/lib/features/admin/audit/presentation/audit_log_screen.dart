import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import '../data/audit_models.dart';
import '../data/audit_repository.dart';

/// Admin audit log: who changed what and when, newest first, filtered by
/// record type, action, user and dates; loads more as you scroll. Tap an
/// entry for the field-by-field changes.
class AuditLogScreen extends ConsumerStatefulWidget {
  const AuditLogScreen({super.key});

  @override
  ConsumerState<AuditLogScreen> createState() => _AuditLogScreenState();
}

class _AuditLogScreenState extends ConsumerState<AuditLogScreen> {
  static final _time = DateFormat('dd MMM yyyy, h:mm a');

  AuditFilter _filter = const AuditFilter();
  final List<AuditEntry> _entries = [];
  int _page = 0;
  int _totalPages = 1;
  int _total = 0;
  bool _loading = false;
  String? _error;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 400) _loadMore();
    });
    _reload();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Bumped on every reload so answers to older requests are ignored.
  int _generation = 0;

  Future<void> _reload() async {
    setState(() {
      _generation++;
      _entries.clear();
      _page = 0;
      _totalPages = 1;
      _error = null;
      _loading = false;
    });
    await _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || _page >= _totalPages) return;
    final gen = _generation;
    setState(() => _loading = true);
    try {
      final p = await ref.read(auditRepositoryProvider).page(_filter, _page + 1);
      if (!mounted || gen != _generation) return; // filters changed meanwhile
      setState(() {
        _entries.addAll(p.entries);
        _page = p.page;
        _totalPages = p.totalPages;
        _total = p.total;
      });
    } catch (e) {
      if (mounted && gen == _generation) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted && gen == _generation) setState(() => _loading = false);
    }
  }

  void _setFilter(AuditFilter f) {
    _filter = f;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = _filter;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Audit log'),
        actions: [
          IconButton(
            tooltip: 'Filters',
            onPressed: _openFilters,
            icon: Badge(isLabelVisible: !f.isEmpty, child: const Icon(Icons.filter_list)),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView.builder(
          controller: _scroll,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          itemCount: _entries.length + 2,
          itemBuilder: (context, i) {
            if (i == 0) {
              // Active filters + count.
              final chips = <Widget>[
                if (f.entityType != null)
                  InputChip(
                    label: Text(AuditEntry.label(f.entityType!)),
                    onDeleted: () => _setFilter(AuditFilter(
                        action: f.action, username: f.username, from: f.from, to: f.to)),
                  ),
                if (f.action != null)
                  InputChip(
                    label: Text(f.action!),
                    onDeleted: () => _setFilter(AuditFilter(
                        entityType: f.entityType, username: f.username, from: f.from, to: f.to)),
                  ),
                if ((f.username ?? '').isNotEmpty)
                  InputChip(
                    label: Text('User: ${f.username}'),
                    onDeleted: () => _setFilter(AuditFilter(
                        entityType: f.entityType, action: f.action, from: f.from, to: f.to)),
                  ),
                if (f.from != null || f.to != null)
                  InputChip(
                    label: Text('${f.from == null ? '…' : Fmt.shortDate(f.from)} – '
                        '${f.to == null ? '…' : Fmt.shortDate(f.to)}'),
                    onDeleted: () => _setFilter(
                        AuditFilter(entityType: f.entityType, action: f.action, username: f.username)),
                  ),
              ];
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (chips.isNotEmpty) Wrap(spacing: 6, runSpacing: 0, children: chips),
                    Text('$_total entr${_total == 1 ? 'y' : 'ies'}',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              );
            }
            if (i == _entries.length + 1) {
              if (_error != null) {
                return Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(children: [
                    Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                    TextButton(onPressed: _loadMore, child: const Text('Try again')),
                  ]),
                );
              }
              if (_loading) {
                return const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator()));
              }
              if (_entries.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text('No audit entries', textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                );
              }
              return const SizedBox(height: 8);
            }
            final e = _entries[i - 1];
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Card(
                clipBehavior: Clip.antiAlias,
                child: ListTile(
                  onTap: () => _showEntry(e),
                  leading: CircleAvatar(child: Icon(_icon(e.action), size: 20)),
                  title: Text(e.description, maxLines: 2, overflow: TextOverflow.ellipsis),
                  subtitle: Text('${e.username} · ${AuditEntry.label(e.entityType)} · '
                      '${e.createdAt == null ? '' : _time.format(e.createdAt!.toLocal())}'),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  static IconData _icon(String action) => switch (action) {
        'Created' => Icons.add_circle_outline,
        'Updated' => Icons.edit_outlined,
        'Deleted' => Icons.delete_outline,
        'Approved' => Icons.check_circle_outline,
        'Rejected' => Icons.cancel_outlined,
        'Generated' => Icons.auto_awesome_outlined,
        'Processed' => Icons.payments_outlined,
        _ => Icons.history,
      };

  Future<void> _openFilters() async {
    final result = await showModalBottomSheet<AuditFilter>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _FilterSheet(initial: _filter),
    );
    if (result != null) _setFilter(result);
  }

  void _showEntry(AuditEntry e) {
    final changes = e.changes;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final theme = Theme.of(ctx);
        final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          maxChildSize: 0.95,
          builder: (ctx, controller) => ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('${e.action} · ${AuditEntry.label(e.entityType)}${e.entityId == null ? '' : ' #${e.entityId}'}',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              Text(e.description),
              const SizedBox(height: 10),
              Text('By ${e.username}'
                  '${e.createdAt == null ? '' : ' · ${_time.format(e.createdAt!.toLocal())}'}'
                  '${e.ipAddress == null ? '' : ' · ${e.ipAddress}'}',
                  style: muted),
              if (changes.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('Changes', style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final (field, before, after) in changes)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(field, style: const TextStyle(fontWeight: FontWeight.w600)),
                        if (before != null)
                          Text('Before: $before', style: TextStyle(color: theme.colorScheme.error)),
                        if (after != null)
                          Text('After: $after', style: const TextStyle(color: Color(0xFF15803D))),
                      ],
                    ),
                  ),
              ] else if (e.values.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(e.savedWithoutChanges ? 'Saved — no fields changed' : 'Values',
                    style: theme.textTheme.titleSmall),
                const SizedBox(height: 6),
                for (final (field, value) in e.values)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      SizedBox(width: 120, child: Text(field, style: muted)),
                      Expanded(child: Text(value)),
                    ]),
                  ),
              ] else if (e.newValues != null || e.oldValues != null) ...[
                const SizedBox(height: 16),
                Text('Details', style: theme.textTheme.titleSmall),
                SelectableText(e.newValues ?? e.oldValues ?? '', style: theme.textTheme.bodySmall),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// Filter sheet: record type, action, username, date range.
class _FilterSheet extends StatefulWidget {
  const _FilterSheet({required this.initial});

  final AuditFilter initial;

  @override
  State<_FilterSheet> createState() => _FilterSheetState();
}

class _FilterSheetState extends State<_FilterSheet> {
  late String? _type = widget.initial.entityType;
  late String? _action = widget.initial.action;
  late final _user = TextEditingController(text: widget.initial.username ?? '');
  late DateTimeRange? _range = widget.initial.from == null || widget.initial.to == null
      ? null
      : DateTimeRange(start: widget.initial.from!, end: widget.initial.to!);

  @override
  void dispose() {
    _user.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Filter audit log', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 12),
            Text('Record', style: theme.textTheme.titleSmall),
            Wrap(spacing: 6, children: [
              for (final t in AuditEntry.entityTypes)
                ChoiceChip(
                  label: Text(AuditEntry.label(t)),
                  selected: _type == t,
                  onSelected: (s) => setState(() => _type = s ? t : null),
                ),
            ]),
            const SizedBox(height: 12),
            Text('Action', style: theme.textTheme.titleSmall),
            Wrap(spacing: 6, children: [
              for (final a in AuditEntry.actions)
                ChoiceChip(
                  label: Text(a),
                  selected: _action == a,
                  onSelected: (s) => setState(() => _action = s ? a : null),
                ),
            ]),
            const SizedBox(height: 12),
            TextField(
              controller: _user,
              decoration: const InputDecoration(labelText: 'Username contains', prefixIcon: Icon(Icons.person_search)),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                  initialDateRange: _range,
                );
                if (picked != null) setState(() => _range = picked);
              },
              icon: const Icon(Icons.date_range_outlined),
              label: Text(_range == null
                  ? 'Any date'
                  : '${Fmt.date(_range!.start)}  –  ${Fmt.date(_range!.end)}'),
            ),
            const SizedBox(height: 16),
            Row(children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: () => Navigator.pop(context, const AuditFilter()),
                  child: const Text('Clear'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: () => Navigator.pop(
                    context,
                    AuditFilter(
                      entityType: _type,
                      action: _action,
                      username: _user.text.trim().isEmpty ? null : _user.text.trim(),
                      from: _range?.start,
                      to: _range?.end,
                    ),
                  ),
                  child: const Text('Apply'),
                ),
              ),
            ]),
          ],
        ),
      ),
    );
  }
}
