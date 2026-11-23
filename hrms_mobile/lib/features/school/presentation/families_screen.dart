import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_admin.dart';
import 'admin_setup_screens.dart' show ChildFormScreen, ParentFormScreen;
import 'school_widgets.dart';
import 'setup_widgets.dart';

// School → Families: a mother and father and their children on one screen. Saving sets the
// same mother and father on every child. Half-siblings are two families sharing a parent:
// Rudvik → Mounika + Mohan, Arjun → Mounika + Narsi (Mounika is the same parent in both).

final _familiesProvider = FutureProvider.autoDispose<List<FamilyRecord>>((ref) => ref.watch(schoolAdminProvider).families());

class FamiliesScreen extends ConsumerStatefulWidget {
  const FamiliesScreen({super.key});

  @override
  ConsumerState<FamiliesScreen> createState() => _FamiliesScreenState();
}

class _FamiliesScreenState extends ConsumerState<FamiliesScreen> {
  final _q = TextEditingController();
  bool _onlyIncomplete = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(FamilyRecord? f) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => FamilyFormScreen(family: f)));
    if (saved == true) ref.invalidate(_familiesProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_familiesProvider);
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Families')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(null),
        icon: const Icon(Icons.add),
        label: const Text('Add family'),
      ),
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_familiesProvider)),
        data: (all) {
          final q = _q.text.trim().toLowerCase();
          bool matches(FamilyRecord f) =>
              q.isEmpty ||
              (f.mother?.fullName.toLowerCase().contains(q) ?? false) ||
              (f.father?.fullName.toLowerCase().contains(q) ?? false) ||
              f.children.any((c) => c.fullName.toLowerCase().contains(q));
          final incomplete = all.where((f) => f.incomplete).length;
          final items = all.where((f) => matches(f) && (!_onlyIncomplete || f.incomplete)).toList();

          return RefreshIndicator(
            onRefresh: () => ref.refresh(_familiesProvider.future),
            child: ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 88), children: [
              TextField(
                controller: _q,
                onChanged: (_) => setState(() {}),
                decoration: const InputDecoration(
                    hintText: 'Find a parent or child', prefixIcon: Icon(Icons.search), isDense: true),
              ),
              const SizedBox(height: 8),
              Text('Set the mother and father once for all their children. A child with a different '
                  'father or mother (half-brother or sister) is in a separate family that shares the parent.',
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (incomplete > 0) ...[
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerLeft,
                  child: FilterChip(
                    avatar: const Icon(Icons.warning_amber_rounded, size: 18),
                    label: Text('Missing mother or father ($incomplete)'),
                    selected: _onlyIncomplete,
                    onSelected: (v) => setState(() => _onlyIncomplete = v),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No families here.'))),
              for (final f in items) ...[
                _FamilyCard(family: f, onTap: () => _open(f)),
                const SizedBox(height: 8),
              ],
            ]),
          );
        },
      ),
    );
  }
}

class _FamilyCard extends StatelessWidget {
  const _FamilyCard({required this.family, required this.onTap});
  final FamilyRecord family;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final f = family;
    Widget parent(String role, ({int id, String fullName, String? phone, bool hasLogin})? p, bool none) => Row(children: [
          SizedBox(width: 62, child: Text(role, style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          Expanded(
            child: p == null
                ? (none
                    ? Text('None on record (single parent)', style: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontStyle: FontStyle.italic))
                    : Text('Not set', style: TextStyle(color: theme.colorScheme.error, fontStyle: FontStyle.italic)))
                : Text(p.phone == null ? p.fullName : '${p.fullName} · ${phoneText(p.phone)}',
                    style: const TextStyle(fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
          ),
        ]);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            parent('Mother', f.mother, f.noMother),
            const SizedBox(height: 4),
            parent('Father', f.father, f.noFather),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final c in f.children)
                Chip(
                  avatar: const Icon(Icons.child_care_outlined, size: 18),
                  label: Text(c.className == null ? c.fullName : '${c.fullName} · ${c.className}',
                      style: TextStyle(color: c.isActive ? null : Colors.grey)),
                  visualDensity: VisualDensity.compact,
                ),
            ]),
          ]),
        ),
      ),
    );
  }
}

/// Add or edit a family: mother, father and their children.
class FamilyFormScreen extends ConsumerStatefulWidget {
  const FamilyFormScreen({super.key, this.family, this.initialMotherId, this.initialFatherId});
  final FamilyRecord? family;
  /// New family started from a parent just added ("Set up her family now?").
  final int? initialMotherId;
  final int? initialFatherId;

  @override
  ConsumerState<FamilyFormScreen> createState() => _FamilyFormScreenState();
}

class _FamilyFormScreenState extends ConsumerState<FamilyFormScreen> {
  late int? _motherId = widget.family?.mother?.id ?? widget.initialMotherId;
  late int? _fatherId = widget.family?.father?.id ?? widget.initialFatherId;
  /// Single parent: "No mother / father on record" ticked (then that box isn't required).
  late bool _noMother = widget.family?.noMother ?? false;
  late bool _noFather = widget.family?.noFather ?? false;
  String? _motherError, _fatherError;
  /// Children in the family when the screen opened (to know who was taken out).
  late final Set<int> _original = {...?widget.family?.children.map((c) => c.id)};
  late final List<int> _childIds = [...?widget.family?.children.map((c) => c.id)];
  List<ParentRecord> _parents = [];
  List<ChildRecord> _children = [];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final admin = ref.read(schoolAdminProvider);
      final results = await Future.wait([admin.parents(), admin.children()]);
      if (!mounted) return;
      setState(() {
        _parents = results[0] as List<ParentRecord>;
        _children = results[1] as List<ChildRecord>;
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = ApiException.from(e).message;
          _loading = false;
        });
      }
    }
  }

  Future<int?> _addParent(String relationship) async {
    final id = await Navigator.of(context).push<Object>(
        MaterialPageRoute(builder: (_) => ParentFormScreen(initialRelationship: relationship)));
    if (id is! int) return null;
    await _load();
    return id;
  }

  ChildRecord? _child(int id) => _children.where((c) => c.id == id).firstOrNull;

  /// What changes for this child when saved, e.g. "father Narsi → Mohan".
  String? _change(ChildRecord c) {
    final parts = <String>[];
    void side(String role, StudentParentRef? now, int? chosen) {
      if (chosen == null || now?.id == chosen) return;
      final name = _parents.where((p) => p.id == chosen).firstOrNull?.fullName ?? '?';
      parts.add(now == null ? '$role: $name' : '$role ${now.fullName} → $name');
    }
    side('mother', c.mother, _motherId);
    side('father', c.father, _fatherId);
    if (_noMother && c.mother != null) parts.add('mother ${c.mother!.fullName} removed');
    if (_noFather && c.father != null) parts.add('father ${c.father!.fullName} removed');
    return parts.isEmpty ? null : parts.join(', ');
  }

  Future<void> _addExistingChild() async {
    final choices = _children.where((c) => !_childIds.contains(c.id) && c.isActive).toList()
      ..sort((a, b) => a.fullName.compareTo(b.fullName));
    final id = await pickFromList<int>(
      context,
      title: 'Add a child to the family',
      items: [for (final c in choices) c.id],
      label: (id) => _child(id)!.fullName,
      subtitle: (id) {
        final c = _child(id)!;
        return [
          c.className ?? 'No class',
          if (c.parents.isNotEmpty) c.parents.map((p) => '${p.fullName} (${p.relationship})').join(', '),
        ].join(' · ');
      },
      searchHint: 'Search by child or parent',
      actions: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('Add a new child'),
          onTap: () => Navigator.of(context).pop(-1),
        ),
        const Divider(height: 1),
      ],
    );
    if (id == null || !mounted) return;
    if (id == -1) {
      final newId = await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => const ChildFormScreen()));
      if (newId is! int) return;
      await _load();
      if (mounted) setState(() => _childIds.add(newId));
    } else {
      setState(() => _childIds.add(id));
    }
  }

  Future<void> _save() async {
    // Both parents, unless "no mother / father on record" is ticked (single parent)
    final motherMissing = _motherId == null && !_noMother;
    final fatherMissing = _fatherId == null && !_noFather;
    if (motherMissing || fatherMissing) {
      setState(() {
        _motherError = motherMissing ? 'Choose the mother, or tick "No mother on record".' : null;
        _fatherError = fatherMissing ? 'Choose the father, or tick "No father on record".' : null;
        _error = 'Please complete the parents.';
      });
      return;
    }
    if (_motherId == null && _fatherId == null) {
      setState(() => _error = 'A family needs at least a mother or a father.');
      return;
    }
    if (_childIds.isEmpty && _original.isEmpty) {
      setState(() => _error = 'Add at least one child.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Taken out: unlinked from the parents this family had when it was opened
      final removed = _original.where((id) => !_childIds.contains(id)).toList();
      final f = widget.family;
      final hadParents = f != null && (f.mother != null || f.father != null);
      if (removed.isNotEmpty && hadParents && (f.mother?.id != _motherId || f.father?.id != _fatherId)) {
        await ref.read(schoolAdminProvider).saveFamily(
            motherId: f.mother?.id, fatherId: f.father?.id, studentIds: const [], removeStudentIds: removed);
      }
      await ref.read(schoolAdminProvider).saveFamily(
        motherId: _motherId,
        fatherId: _fatherId,
        studentIds: _childIds,
        removeStudentIds: f != null && f.mother?.id == _motherId && f.father?.id == _fatherId ? removed : const [],
        noMother: _noMother,
        noFather: _noFather,
      );
      if (mounted) {
        toast(context, 'Family saved');
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
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.family == null ? 'Add family' : 'Edit family'),
        actions: [TextButton(onPressed: _saving || _loading ? null : _save, child: const Text('Save'))],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
                ),
              const SectionTitle('Parents',
                  subtitle: 'Mother and father are required: choose an existing parent or add a new one. '
                      'For a single parent, tick "No … on record".'),
              formGap,
              RequiredParentSlot(
                relationship: 'Mother',
                parents: _parents,
                selectedId: _motherId,
                none: _noMother,
                error: _motherError,
                onChanged: (id) => setState(() {
                  _motherId = id;
                  _motherError = null;
                }),
                onNoneChanged: (v) => setState(() {
                  _noMother = v;
                  _motherError = null;
                  if (v) _motherId = null;
                }),
                onAddNew: () => _addParent('Mother'),
              ),
              formGap,
              RequiredParentSlot(
                relationship: 'Father',
                parents: _parents,
                selectedId: _fatherId,
                none: _noFather,
                error: _fatherError,
                onChanged: (id) => setState(() {
                  _fatherId = id;
                  _fatherError = null;
                }),
                onNoneChanged: (v) => setState(() {
                  _noFather = v;
                  _fatherError = null;
                  if (v) _fatherId = null;
                }),
                onAddNew: () => _addParent('Father'),
              ),
              const SectionTitle('Children', subtitle: 'Brothers and sisters with these parents.'),
              const SizedBox(height: 4),
              if (_childIds.isEmpty)
                const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No children yet.')),
              for (final id in _childIds)
                Builder(builder: (context) {
                  final c = _child(id);
                  if (c == null) return const SizedBox.shrink();
                  final change = _change(c);
                  return Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.child_care_outlined)),
                      title: Text(c.fullName),
                      subtitle: Text(change == null
                          ? (c.className ?? 'No class')
                          : 'Will change: $change'),
                      subtitleTextStyle: change == null ? null : TextStyle(color: theme.colorScheme.tertiary),
                      trailing: IconButton(
                        icon: const Icon(Icons.close),
                        tooltip: 'Take out of this family',
                        onPressed: () => setState(() => _childIds.remove(id)),
                      ),
                    ),
                  );
                }),
              Align(
                alignment: Alignment.centerLeft,
                child: OutlinedButton.icon(
                  onPressed: _addExistingChild,
                  icon: const Icon(Icons.add),
                  label: const Text('Add child'),
                ),
              ),
              const SizedBox(height: 20),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save family')),
            ]),
    );
  }
}
