import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_admin.dart';
import '../data/school_models.dart' show ymdToDate, schoolToday;
import 'school_widgets.dart';
import 'families_screen.dart' show FamilyFormScreen;
import 'setup_widgets.dart';

final _classesProvider = FutureProvider.autoDispose<List<ClassItem>>((ref) => ref.watch(schoolAdminProvider).classes());
final _childrenProvider = FutureProvider.autoDispose<List<ChildRecord>>((ref) => ref.watch(schoolAdminProvider).children());
final _parentsProvider = FutureProvider.autoDispose<List<ParentRecord>>((ref) => ref.watch(schoolAdminProvider).parents());

Future<bool> _confirm(BuildContext context, String title, String message, {String ok = 'Delete'}) async =>
    await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(ok)),
        ],
      ),
    ) ==
    true;

Widget _search(TextEditingController c, String hint, VoidCallback changed) => Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: TextField(
        controller: c,
        onChanged: (_) => changed(),
        decoration: InputDecoration(hintText: hint, prefixIcon: const Icon(Icons.search), isDense: true),
      ),
    );

// ═══════════════════ Classes ═══════════════════

class ClassesScreen extends ConsumerWidget {
  const ClassesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_classesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Classes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(context, ref, null),
        icon: const Icon(Icons.add),
        label: const Text('Add class'),
      ),
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_classesProvider)),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(_classesProvider.future),
          child: items.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No classes yet, e.g. PG, N1, N2, K1, K2.')))])
              : ListView.separated(
                  padding: const EdgeInsets.only(bottom: 88),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    return ListTile(
                      onTap: () => _edit(context, ref, c),
                      leading: CircleAvatar(child: Text(c.name.isEmpty ? '?' : c.name.substring(0, c.name.length.clamp(0, 2)))),
                      title: Text(c.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${c.classTeacherName ?? 'No teacher'}${c.teacherNames.isEmpty ? '' : ' + ${c.teacherNames.join(', ')}'} · ${c.studentCount} child${c.studentCount == 1 ? '' : 'ren'}'),
                      trailing: c.isActive ? const Icon(Icons.chevron_right) : const Pill('Inactive'),
                    );
                  },
                ),
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, ClassItem? c) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ClassSheet(item: c),
    );
    if (saved == true) ref.invalidate(_classesProvider);
  }
}

class _ClassSheet extends ConsumerStatefulWidget {
  const _ClassSheet({this.item});
  final ClassItem? item;

  @override
  ConsumerState<_ClassSheet> createState() => _ClassSheetState();
}

class _ClassSheetState extends ConsumerState<_ClassSheet> {
  late final _name = TextEditingController(text: widget.item?.name ?? '');
  late final _desc = TextEditingController(text: widget.item?.description ?? '');
  late final _order = TextEditingController(text: '${widget.item?.sortOrder ?? 0}');
  late int? _teacher = widget.item?.classTeacherId;
  /// Other teachers of the class (besides the lead).
  late final Set<int> _others = {...?widget.item?.teacherIds};
  late bool _active = widget.item?.isActive ?? true;
  List<EmployeeRef> _teachers = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(schoolAdminProvider).teachers().then((t) {
      if (mounted) setState(() => _teachers = t);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _name.dispose();
    _desc.dispose();
    _order.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(schoolAdminProvider).saveClass(widget.item?.id, {
        'name': _name.text.trim(),
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'classTeacherId': _teacher,
        'teacherIds': _others.where((t) => t != _teacher).toList(),
        'sortOrder': int.tryParse(_order.text.trim()) ?? 0,
        'isActive': _active,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    final c = widget.item!;
    if (!await _confirm(context, 'Delete ${c.name}?', 'Only an empty class can be deleted. Otherwise mark it inactive.')) return;
    if (!mounted) return;
    if (await attempt(context, () => ref.read(schoolAdminProvider).deleteClass(c.id), done: 'Deleted') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherIds = _teachers.map((t) => t.id).toSet();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.item == null ? 'Add class' : 'Edit class', style: Theme.of(context).textTheme.titleLarge),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          TextField(controller: _name, maxLength: 50, decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. N2 or K1 Sunflower')),
          DropdownButtonFormField<int?>(
            value: _teacher != null && !teacherIds.contains(_teacher) && _teachers.isNotEmpty ? null : _teacher,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Lead teacher', helperText: 'The teacher parents see'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('No teacher yet')),
              for (final t in _teachers) DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _teacher = v),
          ),
          if (_teacher != null && _teachers.length > 1) ...[
            const SizedBox(height: 12),
            Text('Other teachers (optional)', style: Theme.of(context).textTheme.labelLarge),
            const Text('They see the class\'s children, attendance and reports, and answer its parents too.',
                style: TextStyle(fontSize: 12)),
            for (final t in _teachers.where((t) => t.id != _teacher))
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                value: _others.contains(t.id),
                title: Text(t.name),
                onChanged: (v) => setState(() => v == true ? _others.add(t.id) : _others.remove(t.id)),
              ),
          ],
          TextField(controller: _desc, maxLength: 200, decoration: const InputDecoration(labelText: 'Description (optional)')),
          TextField(controller: _order, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Order in lists')),
          SwitchListTile(contentPadding: EdgeInsets.zero, title: const Text('Active'), value: _active, onChanged: (v) => setState(() => _active = v)),
          FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
          if (widget.item != null)
            TextButton(onPressed: _delete, child: Text('Delete class', style: TextStyle(color: Theme.of(context).colorScheme.error))),
        ]),
      ),
    );
  }
}

// ═══════════════════ Children ═══════════════════

class ChildrenScreen extends ConsumerStatefulWidget {
  const ChildrenScreen({super.key});

  @override
  ConsumerState<ChildrenScreen> createState() => _ChildrenScreenState();
}

class _ChildrenScreenState extends ConsumerState<ChildrenScreen> {
  final _q = TextEditingController();
  int? _classId;
  bool _showInactive = false;

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(ChildRecord? c) async {
    final saved = await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => ChildFormScreen(child: c)));
    if (saved != null) ref.invalidate(_childrenProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_childrenProvider);
    final classes = ref.watch(_classesProvider).valueOrNull ?? const <ClassItem>[];
    return Scaffold(
      appBar: AppBar(title: const Text('Children')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _open(null), icon: const Icon(Icons.add), label: const Text('Add child')),
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_childrenProvider)),
        data: (all) {
          final q = _q.text.trim().toLowerCase();
          final items = all.where((c) =>
              (_showInactive || c.isActive) &&
              (_classId == null || c.classId == _classId) &&
              (q.isEmpty || c.fullName.toLowerCase().contains(q) || c.parents.any((p) => p.fullName.toLowerCase().contains(q)))).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_childrenProvider.future),
            child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              _search(_q, 'Find a child or parent', () => setState(() {})),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(children: [
                  ChoiceChip(label: const Text('All classes'), selected: _classId == null, onSelected: (_) => setState(() => _classId = null)),
                  for (final c in classes)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: ChoiceChip(label: Text(c.name), selected: _classId == c.id, onSelected: (_) => setState(() => _classId = c.id)),
                    ),
                  const SizedBox(width: 6),
                  FilterChip(label: const Text('Inactive too'), selected: _showInactive, onSelected: (v) => setState(() => _showInactive = v)),
                ]),
              ),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No children here.'))),
              for (final c in items)
                ListTile(
                  onTap: () => _open(c),
                  leading: CircleAvatar(child: Text(c.fullName.isEmpty ? '?' : c.fullName[0])),
                  title: Text(c.fullName, style: TextStyle(fontWeight: FontWeight.w600, color: c.isActive ? null : Colors.grey)),
                  subtitle: Text([
                    c.className ?? 'No class',
                    c.sessionType,
                    c.parents.isEmpty ? 'no parent linked' : c.parents.map((p) => p.fullName).join(', '),
                  ].join(' · ')),
                  trailing: c.medicalNotes != null ? const Icon(Icons.medical_information_outlined, color: Colors.red) : null,
                ),
            ]),
          );
        },
      ),
    );
  }
}

class ChildFormScreen extends ConsumerStatefulWidget {
  const ChildFormScreen({super.key, this.child});
  final ChildRecord? child;

  @override
  ConsumerState<ChildFormScreen> createState() => _ChildFormScreenState();
}

class _ChildFormScreenState extends ConsumerState<ChildFormScreen> {
  ChildRecord? get c => widget.child;
  late final _name = TextEditingController(text: c?.fullName ?? '');
  late final _adm = TextEditingController(text: c?.admissionNo ?? '');
  late final _med = TextEditingController(text: c?.medicalNotes ?? '');
  late final _ecName = TextEditingController(text: c?.emergencyContactName ?? '');
  late final _ecPhone = TextEditingController(text: phoneText(c?.emergencyContactPhone));
  late final _notes = TextEditingController(text: c?.notes ?? '');
  late int? _classId = c?.classId;
  late String _session = c?.sessionType ?? 'Full day';
  late String? _gender = c?.gender;
  late String? _dob = c?.dateOfBirth;
  late String? _joined = c?.joinedOn;
  late bool _active = c?.isActive ?? true;
  // One mother, one father, any guardians
  late int? _motherId = c?.mother?.id;
  late int? _fatherId = c?.father?.id;
  /// Single parent: no mother / father to record (then that box isn't required).
  late bool _noMother = c?.noMotherOnRecord ?? false;
  late bool _noFather = c?.noFatherOnRecord ?? false;
  String? _motherError, _fatherError;
  late final Set<int> _guardianIds = {...?c?.parents.where((p) => p.relationship == 'Guardian').map((p) => p.id)};
  List<ClassItem> _classes = [];
  List<ParentRecord> _parents = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final admin = ref.read(schoolAdminProvider);
    admin.classes().then((v) { if (mounted) setState(() => _classes = v.where((x) => x.isActive || x.id == _classId).toList()); }).catchError((_) {});
    _loadParents();
  }

  void _loadParents() =>
      ref.read(schoolAdminProvider).parents().then((v) { if (mounted) setState(() => _parents = v); }).catchError((_) {});

  /// "+ Add a new mother/father/guardian": the parent form, then back here with the new parent chosen.
  Future<int?> _addParent(String relationship) async {
    final id = await Navigator.of(context).push<int>(
        MaterialPageRoute(builder: (_) => ParentFormScreen(initialRelationship: relationship)));
    if (id != null) {
      final v = await ref.read(schoolAdminProvider).parents().catchError((_) => _parents);
      if (mounted) setState(() => _parents = v);
    }
    return id;
  }

  @override
  void dispose() {
    for (final t in [_name, _adm, _med, _ecName, _ecPhone, _notes]) {
      t.dispose();
    }
    super.dispose();
  }

  String? _t(TextEditingController t) => t.text.trim().isEmpty ? null : t.text.trim();

  Future<void> _save({bool allowDuplicate = false}) async {
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await ref.read(schoolAdminProvider).saveChild(c?.id, {
        'fullName': _name.text.trim(),
        'admissionNo': _t(_adm),
        'dateOfBirth': _dob,
        'gender': _gender,
        'classId': _classId,
        'sessionType': _session,
        'joinedOn': _joined,
        'medicalNotes': _t(_med),
        'emergencyContactName': _t(_ecName),
        'emergencyContactPhone': _t(_ecPhone),
        'notes': _t(_notes),
        'isActive': _active,
        'parentIds': [if (_motherId != null) _motherId!, if (_fatherId != null) _fatherId!, ..._guardianIds],
        'noMotherOnRecord': _noMother,
        'noFatherOnRecord': _noFather,
        'allowDuplicate': allowDuplicate,
      });
      if (mounted) {
        toast(context, c == null ? 'Child added' : 'Saved');
        Navigator.pop(context, id); // the child's id (truthy for "saved")
      }
    } on PossibleDuplicate catch (d) {
      if (!mounted) return;
      final yes = await _confirm(context, 'Already on the list?', d.message, ok: "Yes, it's a different child");
      if (yes && mounted) return _save(allowDuplicate: true);
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm(context, 'Delete ${c!.fullName}?',
        'To keep messages and fee records, mark the child inactive instead.')) return;
    if (!mounted) return;
    if (await attempt(context, () => ref.read(schoolAdminProvider).deleteChild(c!.id), done: 'Deleted') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final today = ymdToDate(schoolToday());
    final guardians = _parents.where((p) => p.relationship == 'Guardian' && (p.isActive || _guardianIds.contains(p.id))).toList();
    final siblings = c?.siblings ?? const <SiblingRef>[];
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Add child' : 'Edit child'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ...spaced([
          TextField(controller: _name, maxLength: 150, textCapitalization: TextCapitalization.words,
              decoration: boxDecoration('Full name', icon: Icons.child_care_outlined)),
          DateField(
            label: 'Date of birth',
            value: _dob,
            onChanged: (v) => setState(() => _dob = v),
            firstDate: DateTime(2000),
            lastDate: today,
            initialDate: DateTime(today.year - 3, today.month, today.day),
          ),
          DropdownButtonFormField<String?>(
            value: _gender,
            decoration: boxDecoration('Gender', icon: Icons.wc_outlined),
            items: const [
              DropdownMenuItem(value: null, child: Text('Not set')),
              DropdownMenuItem(value: 'Boy', child: Text('Boy')),
              DropdownMenuItem(value: 'Girl', child: Text('Girl')),
            ],
            onChanged: (v) => setState(() => _gender = v),
          ),
          DropdownButtonFormField<int?>(
            value: _classes.any((x) => x.id == _classId) ? _classId : null,
            decoration: boxDecoration('Class', icon: Icons.class_outlined),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('No class yet')),
              for (final x in _classes) DropdownMenuItem<int?>(value: x.id, child: Text(x.name)),
            ],
            onChanged: (v) => setState(() => _classId = v),
          ),
          DropdownButtonFormField<String>(
            value: _session,
            decoration: boxDecoration('Session', icon: Icons.schedule_outlined),
            items: [for (final s in sessionTypes) DropdownMenuItem(value: s, child: Text(s))],
            onChanged: (v) => setState(() => _session = v ?? 'Full day'),
          ),
          DateField(
            label: 'Joined on',
            value: _joined,
            icon: Icons.event_available_outlined,
            onChanged: (v) => setState(() => _joined = v),
            firstDate: DateTime(2000),
            lastDate: today.add(const Duration(days: 365)),
            initialDate: today,
          ),
          TextField(controller: _adm, maxLength: 30, decoration: boxDecoration('Admission no. (optional)', icon: Icons.tag)),
        ]),
        const SectionTitle('Parents',
            subtitle: 'Mother and father are required. For a single parent, tick "No … on record". '
                'For brothers and sisters, choose the same parents.'),
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
        if (guardians.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Guardians (optional)', style: Theme.of(context).textTheme.labelLarge),
          for (final p in guardians)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _guardianIds.contains(p.id),
              title: Text(p.fullName),
              subtitle: p.phone == null ? null : Text(phoneText(p.phone)),
              onChanged: (v) => setState(() => v == true ? _guardianIds.add(p.id) : _guardianIds.remove(p.id)),
            ),
        ],
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () async {
              final id = await _addParent('Guardian');
              if (id != null) setState(() => _guardianIds.add(id));
            },
            icon: const Icon(Icons.person_add_alt, size: 18),
            label: const Text('Add a guardian'),
          ),
        ),
        if (siblings.isNotEmpty) ...[
          const SectionTitle('Brothers and sisters', subtitle: 'From the parents above.'),
          const SizedBox(height: 4),
          for (final s in siblings)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.people_outline),
              title: Text(s.fullName, style: TextStyle(color: s.isActive ? null : Colors.grey)),
              subtitle: Text([s.via, if (s.className != null) s.className!].join(' · ')),
            ),
        ],
        const SectionTitle('Health and safety'),
        formGap,
        ...spaced([
          TextField(controller: _med, maxLength: 1000, maxLines: 3, minLines: 2,
              decoration: boxDecoration('Allergies / medical notes', hint: 'Shown to the class teacher', icon: Icons.medical_information_outlined)),
          TextField(controller: _ecName, maxLength: 150, textCapitalization: TextCapitalization.words,
              decoration: boxDecoration('Emergency contact name', icon: Icons.contact_emergency_outlined)),
          TextField(controller: _ecPhone, maxLength: 20, keyboardType: TextInputType.phone,
              decoration: boxDecoration('Emergency contact phone', hint: '012-345 6789', icon: Icons.phone_outlined)),
          TextField(controller: _notes, maxLength: 1000, maxLines: 3, minLines: 2,
              decoration: boxDecoration('Other notes (optional)', icon: Icons.notes_outlined)),
        ]),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: Text(_active ? 'At the school' : 'Left the school'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        if (c != null)
          TextButton(onPressed: _delete, child: Text('Delete child', style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}

// ═══════════════════ Parents ═══════════════════

class ParentsScreen extends ConsumerStatefulWidget {
  const ParentsScreen({super.key});

  @override
  ConsumerState<ParentsScreen> createState() => _ParentsScreenState();
}

class _ParentsScreenState extends ConsumerState<ParentsScreen> {
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Future<void> _open(ParentRecord? p) async {
    final saved = await Navigator.of(context).push<Object>(MaterialPageRoute(builder: (_) => ParentFormScreen(parent: p)));
    if (saved != null) ref.invalidate(_parentsProvider);

    // A new mother or father: offer to set up the family straight away, so each child gets both parents
    if (p != null || saved is! int || !mounted) return;
    final added = (await ref.read(_parentsProvider.future)).where((x) => x.id == saved).firstOrNull;
    if (added == null || added.relationship == 'Guardian' || !mounted) return;
    final isMother = added.relationship == 'Mother';
    final yes = await _confirm(context, 'Set up the family now?',
        'Choose the ${isMother ? 'father' : 'mother'} of ${added.fullName}\'s children (or tick '
        '"No ${isMother ? 'father' : 'mother'} on record") and add the children.',
        ok: 'Set up family');
    if (!yes || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => FamilyFormScreen(
              initialMotherId: isMother ? added.id : null,
              initialFatherId: isMother ? null : added.id,
            )));
    ref.invalidate(_parentsProvider);
  }

  @override
  Widget build(BuildContext context) {
    final list = ref.watch(_parentsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Parents')),
      floatingActionButton: FloatingActionButton.extended(onPressed: () => _open(null), icon: const Icon(Icons.person_add_alt), label: const Text('Add parent')),
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_parentsProvider)),
        data: (all) {
          final q = _q.text.trim().toLowerCase();
          final items = all.where((p) => q.isEmpty || p.fullName.toLowerCase().contains(q) ||
              (p.email ?? '').toLowerCase().contains(q) || (p.phone ?? '').contains(q) ||
              p.children.any((c) => c.fullName.toLowerCase().contains(q))).toList();
          return RefreshIndicator(
            onRefresh: () => ref.refresh(_parentsProvider.future),
            child: ListView(padding: const EdgeInsets.only(bottom: 88), children: [
              _search(_q, 'Find a parent, email, phone or child', () => setState(() {})),
              if (items.isEmpty) const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No parents here.'))),
              for (final p in items)
                ListTile(
                  onTap: () => _open(p),
                  leading: const CircleAvatar(child: Icon(Icons.family_restroom)),
                  title: Text('${p.fullName} (${p.relationship})',
                      style: TextStyle(fontWeight: FontWeight.w600, color: p.isActive ? null : Colors.grey)),
                  subtitle: Text([
                    p.children.isEmpty
                        ? 'No child linked'
                        : p.children.map((c) => c.others.isEmpty ? c.fullName : '${c.fullName} (with ${c.others.map((o) => o.split(' (').first).join(', ')})').join(', '),
                    if (p.phone != null) phoneText(p.phone),
                  ].join(' · ')),
                  trailing: !p.hasLogin
                      ? const Pill('No login')
                      : !p.loginActive
                          ? const Pill('Login off')
                          : p.loginPending
                              ? const Pill('Invited', tone: PillTone.warn)
                              : const Pill('Login', tone: PillTone.good),
                ),
            ]),
          );
        },
      ),
    );
  }
}

/// Add / edit a parent. Pops with the parent's id when saved (so the child and family screens can
/// pick a parent they just added), or `true` when deleted. Children are linked on the child's
/// screen or under Families, where the mother and father are set together.
class ParentFormScreen extends ConsumerStatefulWidget {
  const ParentFormScreen({super.key, this.parent, this.initialRelationship});
  final ParentRecord? parent;
  /// For a new parent: "Mother", "Father" or "Guardian".
  final String? initialRelationship;

  @override
  ConsumerState<ParentFormScreen> createState() => _ParentFormScreenState();
}

class _ParentFormScreenState extends ConsumerState<ParentFormScreen> {
  ParentRecord? get p => widget.parent;
  late final _name = TextEditingController(text: p?.fullName ?? '');
  late final _email = TextEditingController(text: p?.email ?? '');
  late final _phone = TextEditingController(text: phoneText(p?.phone));
  final _password = TextEditingController();
  late String _rel = p?.relationship ?? widget.initialRelationship ?? 'Mother';
  late bool _active = p?.isActive ?? true;
  late bool _createLogin = p == null;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    for (final t in [_name, _email, _phone, _password]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_password.text.isNotEmpty && _password.text.length < 8) {
      setState(() => _error = 'The password must be at least 8 characters.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final r = await ref.read(schoolAdminProvider).saveParent(p?.id, {
        'fullName': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'relationship': _rel,
        'isActive': _active,
        // null = keep the children as they are (set on the child's screen or under Families)
        'studentIds': null,
        'createLogin': p == null ? _createLogin : (!p!.hasLogin && _createLogin),
        'password': _password.text.isEmpty ? null : _password.text,
      });
      if (mounted) {
        toast(context, r.message == null ? 'Saved' : 'Saved: ${r.message}');
        Navigator.pop(context, r.id);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _invite() async {
    try {
      final msg = await ref.read(schoolAdminProvider).inviteParent(p!.id);
      if (mounted) toast(context, msg);
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    }
  }

  Future<void> _delete() async {
    if (!await _confirm(context, 'Delete ${p!.fullName}?',
        '${p!.hasLogin ? 'Their login is removed too. ' : ''}Their past messages stay in the threads.')) return;
    if (!mounted) return;
    if (await attempt(context, () => ref.read(schoolAdminProvider).deleteParent(p!.id), done: 'Deleted') && mounted) {
      Navigator.pop(context, true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasLogin = p?.hasLogin ?? false;
    final children = p?.children ?? const [];
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Add ${(widget.initialRelationship ?? 'parent').toLowerCase()}' : 'Edit parent'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ...spaced([
          TextField(controller: _name, maxLength: 150, textCapitalization: TextCapitalization.words,
              decoration: boxDecoration('Full name', icon: Icons.person_outline)),
          DropdownButtonFormField<String>(
            value: _rel,
            decoration: boxDecoration('Relationship to the child', icon: Icons.family_restroom_outlined),
            items: [for (final r in relationships) DropdownMenuItem(value: r, child: Text(r))],
            onChanged: (v) => setState(() => _rel = v ?? 'Mother'),
          ),
          TextField(controller: _email, maxLength: 150, keyboardType: TextInputType.emailAddress, autocorrect: false,
              decoration: boxDecoration('Email', icon: Icons.email_outlined,
                  helper: hasLogin ? 'The login (${p!.username}) uses this email.' : 'Needed for the parent app login.')),
          TextField(controller: _phone, maxLength: 20, keyboardType: TextInputType.phone,
              decoration: boxDecoration('Phone', hint: '012-345 6789', icon: Icons.phone_outlined)),
        ]),
        if (p != null) ...[
          const SectionTitle('Children', subtitle: 'Linked on the child\'s screen or under Families.'),
          if (children.isEmpty)
            const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No child linked yet.')),
          for (final c in children)
            ListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              leading: const Icon(Icons.child_care_outlined),
              title: Text(c.fullName),
              subtitle: Text([
                c.className ?? 'No class',
                c.others.isEmpty ? 'no other parent' : 'with ${c.others.join(', ')}',
              ].join(' · ')),
            ),
        ],
        const SectionTitle('Parent login'),
        if (!hasLogin)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('Create a login and email a set-password link'),
            value: _createLogin,
            onChanged: (v) => setState(() => _createLogin = v),
          )
        else ...[
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(p!.username ?? ''),
            subtitle: Text(!p!.loginActive ? 'Login switched off' : p!.loginPending ? 'Invited — password not set yet' : 'Active'),
            trailing: TextButton(onPressed: _invite, child: const Text('Send link')),
          ),
          const SizedBox(height: 4),
          TextField(controller: _password, maxLength: 100,
              decoration: boxDecoration('Set a new password (optional)', icon: Icons.lock_reset_outlined,
                  helper: 'For parents who can\'t get the email; they choose their own at sign-in.')),
        ],
        if (p != null && !hasLogin)
          Align(alignment: Alignment.centerLeft, child: TextButton(onPressed: _invite, child: const Text('Create login now and email the link'))),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Active'),
          subtitle: Text(_active ? 'Can use the parent portal' : 'Inactive (login switched off)'),
          value: _active,
          onChanged: (v) => setState(() => _active = v),
        ),
        const SizedBox(height: 8),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save')),
        if (p != null)
          TextButton(onPressed: _delete, child: Text('Delete parent', style: TextStyle(color: Theme.of(context).colorScheme.error))),
      ]),
    );
  }
}
