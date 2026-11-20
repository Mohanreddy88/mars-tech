import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../profile/data/profile_repository.dart' show banksProvider;
import '../../data/admin_repository.dart' show departmentsProvider;
import '../data/master_models.dart';
import '../data/master_repository.dart';

Future<bool> _confirm(BuildContext context, String title, String body, String action) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(action)),
        ],
      ),
    ) ??
    false;

void _snack(BuildContext context, String m) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

// ── Departments / Banks ───────────────────────────────────────────────────

/// Departments or banks: list (active and inactive), add, edit, deactivate, delete.
class MasterListScreen extends ConsumerWidget {
  const MasterListScreen({super.key, required this.kind});

  final MasterKind kind;

  String get _title => kind == MasterKind.departments ? 'Departments' : 'Banks';

  void _refreshAll(WidgetRef ref) {
    ref.invalidate(masterItemsProvider(kind));
    // Dropdowns elsewhere in the app (employee form, profile).
    kind == MasterKind.departments ? ref.invalidate(departmentsProvider) : ref.invalidate(banksProvider);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final items = ref.watch(masterItemsProvider(kind));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(_title)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: Text('Add ${kind.singular.toLowerCase()}'),
      ),
      body: items.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(masterItemsProvider(kind))),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(masterItemsProvider(kind).future),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final it = list[i];
              return Card(
                child: ListTile(
                  onTap: () => _edit(context, ref, it),
                  title: Text(it.name,
                      style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: it.isActive ? null : theme.colorScheme.onSurfaceVariant)),
                  subtitle: Text([
                    if (it.description?.isNotEmpty ?? false) it.description!,
                    if (it.employeeCount != null) '${it.employeeCount} active employee${it.employeeCount == 1 ? '' : 's'}',
                    if (!it.isActive) 'Inactive',
                  ].join(' · ')),
                  trailing: IconButton(
                    tooltip: 'Delete',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () async {
                      final ok = await _confirm(context, 'Delete ${it.name}?',
                          'This cannot be undone. To keep it in history, edit it and turn off "Active" instead.',
                          'Delete');
                      if (!ok) return;
                      try {
                        await ref.read(masterRepositoryProvider).deleteItem(kind, it.id);
                        _refreshAll(ref);
                        if (context.mounted) _snack(context, '${it.name} deleted');
                      } catch (e) {
                        if (context.mounted) _snack(context, ApiException.from(e).message);
                      }
                    },
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, MasterItem? it) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MasterItemSheet(kind: kind, item: it),
    );
    if (saved == true) _refreshAll(ref);
  }
}

class _MasterItemSheet extends ConsumerStatefulWidget {
  const _MasterItemSheet({required this.kind, this.item});

  final MasterKind kind;
  final MasterItem? item;

  @override
  ConsumerState<_MasterItemSheet> createState() => _MasterItemSheetState();
}

class _MasterItemSheetState extends ConsumerState<_MasterItemSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late bool _active = widget.item?.isActive ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDept = widget.kind == MasterKind.departments;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(widget.item == null ? 'Add ${widget.kind.singular.toLowerCase()}' : 'Edit ${widget.item!.name}',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 16),
          TextField(
            controller: _name,
            autofocus: widget.item == null,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(labelText: 'Name'),
          ),
          if (isDept) ...[
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              decoration: const InputDecoration(labelText: 'Description (optional)'),
            ),
          ],
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Active'),
            subtitle: Text(isDept ? 'Inactive departments are hidden when choosing one'
                : 'Inactive banks are hidden from employees\' bank choice'),
            value: _active,
            onChanged: (v) => setState(() => _active = v),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Save'),
          ),
        ],
      ),
    );
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(masterRepositoryProvider).saveItem(widget.kind,
          id: widget.item?.id, name: _name.text, description: _desc.text, isActive: _active);
      navigator.pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = ApiException.from(e).message;
      });
    }
  }
}

// ── Public holidays ───────────────────────────────────────────────────────

/// Public holidays per year: add, edit, delete. Used for attendance and leave days.
class HolidaysScreen extends ConsumerStatefulWidget {
  const HolidaysScreen({super.key});

  @override
  ConsumerState<HolidaysScreen> createState() => _HolidaysScreenState();
}

class _HolidaysScreenState extends ConsumerState<HolidaysScreen> {
  int _year = DateTime.now().year;
  static final _fmt = DateFormat('EEE, d MMM');

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(holidaysProvider(_year));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Public holidays')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Add holiday'),
      ),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(children: [
            IconButton(onPressed: () => setState(() => _year--), icon: const Icon(Icons.chevron_left)),
            Expanded(
              child: Text('$_year',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
            ),
            IconButton(onPressed: () => setState(() => _year++), icon: const Icon(Icons.chevron_right)),
          ]),
        ),
        Expanded(
          child: list.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(holidaysProvider(_year))),
            data: (items) => items.isEmpty
                ? Center(
                    child: Text('No public holidays for $_year',
                        style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)))
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 96),
                    itemCount: items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final h = items[i];
                      return Card(
                        child: ListTile(
                          onTap: () => _edit(h),
                          leading: CircleAvatar(child: Text('${h.date.day}')),
                          title: Text(h.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text('${_fmt.format(h.date)} · '
                              '${h.isNational ? 'National' : (h.state?.isNotEmpty ?? false) ? h.state! : 'State'}'),
                          trailing: IconButton(
                            tooltip: 'Delete',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _delete(h),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      ]),
    );
  }

  Future<void> _delete(Holiday h) async {
    final ok = await _confirm(
        context, 'Delete ${h.name}?', '${_fmt.format(h.date)} $_year will become a working day.', 'Delete');
    if (!ok) return;
    try {
      await ref.read(masterRepositoryProvider).deleteHoliday(h.id);
      ref.invalidate(holidaysProvider(_year));
      if (mounted) _snack(context, '${h.name} deleted');
    } catch (e) {
      if (mounted) _snack(context, ApiException.from(e).message);
    }
  }

  Future<void> _edit(Holiday? h) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _HolidaySheet(holiday: h, year: _year),
    );
    if (saved == true) ref.invalidate(holidaysProvider(_year));
  }
}

class _HolidaySheet extends ConsumerStatefulWidget {
  const _HolidaySheet({this.holiday, required this.year});

  final Holiday? holiday;
  final int year;

  @override
  ConsumerState<_HolidaySheet> createState() => _HolidaySheetState();
}

class _HolidaySheetState extends ConsumerState<_HolidaySheet> {
  late final _name = TextEditingController(text: widget.holiday?.name ?? '');
  late final _state = TextEditingController(text: widget.holiday?.state ?? '');
  late final _desc = TextEditingController(text: widget.holiday?.description ?? '');
  late DateTime? _date = widget.holiday?.date;
  late bool _national = widget.holiday?.isNational ?? true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _state.dispose();
    _desc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.holiday == null ? 'Add public holiday' : 'Edit holiday',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () async {
                  final picked = await showDatePicker(
                    context: context,
                    firstDate: DateTime(widget.year - 1),
                    lastDate: DateTime(widget.year + 2, 12, 31),
                    initialDate: _date ?? DateTime(widget.year, DateTime.now().month, DateTime.now().day),
                  );
                  if (picked != null) setState(() => _date = picked);
                },
                icon: const Icon(Icons.event_outlined),
                label: Text(_date == null ? 'Select date' : DateFormat('EEEE, d MMMM yyyy').format(_date!)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('National holiday'),
                subtitle: const Text('Off = applies to one state only'),
                value: _national,
                onChanged: (v) => setState(() => _national = v),
              ),
              if (!_national)
                TextField(
                  controller: _state,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(labelText: 'State (e.g. Selangor)'),
                ),
              const SizedBox(height: 12),
              TextField(controller: _desc, decoration: const InputDecoration(labelText: 'Description (optional)')),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Save'),
              ),
            ],
          ),
        ),
      );

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _date == null) {
      setState(() => _error = 'Enter a name and pick the date.');
      return;
    }
    final navigator = Navigator.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(masterRepositoryProvider).saveHoliday(
          id: widget.holiday?.id,
          name: _name.text,
          date: _date!,
          isNational: _national,
          state: _state.text,
          description: _desc.text);
      navigator.pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = ApiException.from(e).message;
      });
    }
  }
}
