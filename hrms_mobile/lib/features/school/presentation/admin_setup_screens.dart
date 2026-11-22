import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_admin.dart';
import '../data/school_models.dart' show ymdToDate, dateToYmd, schoolToday;
import 'school_widgets.dart';

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
                      subtitle: Text('${c.classTeacherName ?? 'No teacher'} · ${c.studentCount} child${c.studentCount == 1 ? '' : 'ren'}'),
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
            decoration: const InputDecoration(labelText: 'Class teacher'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('No teacher yet')),
              for (final t in _teachers) DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _teacher = v),
          ),
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
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ChildFormScreen(child: c)));
    if (saved == true) ref.invalidate(_childrenProvider);
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
  late Set<int> _parentIds = {...?c?.parents.map((p) => p.id)};
  List<ClassItem> _classes = [];
  List<ParentRecord> _parents = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final admin = ref.read(schoolAdminProvider);
    admin.classes().then((v) { if (mounted) setState(() => _classes = v.where((x) => x.isActive || x.id == _classId).toList()); }).catchError((_) {});
    admin.parents().then((v) { if (mounted) setState(() => _parents = v); }).catchError((_) {});
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
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(schoolAdminProvider).saveChild(c?.id, {
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
        'parentIds': _parentIds.toList(),
        'allowDuplicate': allowDuplicate,
      });
      if (mounted) {
        toast(context, c == null ? 'Child added' : 'Saved');
        Navigator.pop(context, true);
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

  Future<void> _pickDate(String? current, ValueChanged<String?> set) async {
    final d = await showDatePicker(
      context: context,
      initialDate: current != null ? ymdToDate(current) : DateTime(DateTime.now().year - 3),
      firstDate: DateTime(2000),
      lastDate: ymdToDate(schoolToday()),
    );
    if (d != null) setState(() => set(dateToYmd(d)));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('d MMM yyyy');
    final heading = Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: .6);
    return Scaffold(
      appBar: AppBar(
        title: Text(c == null ? 'Add child' : 'Edit child'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextField(controller: _name, maxLength: 150, decoration: const InputDecoration(labelText: 'Full name')),
        DropdownButtonFormField<int?>(
          value: _classes.any((x) => x.id == _classId) ? _classId : null,
          decoration: const InputDecoration(labelText: 'Class'),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('No class yet')),
            for (final x in _classes) DropdownMenuItem<int?>(value: x.id, child: Text(x.name)),
          ],
          onChanged: (v) => setState(() => _classId = v),
        ),
        DropdownButtonFormField<String>(
          value: _session,
          decoration: const InputDecoration(labelText: 'Session'),
          items: [for (final s in sessionTypes) DropdownMenuItem(value: s, child: Text(s))],
          onChanged: (v) => setState(() => _session = v ?? 'Full day'),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Date of birth'),
          subtitle: Text(_dob == null ? 'Not set' : fmt.format(ymdToDate(_dob!))),
          trailing: const Icon(Icons.event_outlined),
          onTap: () => _pickDate(_dob, (v) => _dob = v),
        ),
        DropdownButtonFormField<String?>(
          value: _gender,
          decoration: const InputDecoration(labelText: 'Gender'),
          items: const [
            DropdownMenuItem(value: null, child: Text('—')),
            DropdownMenuItem(value: 'Boy', child: Text('Boy')),
            DropdownMenuItem(value: 'Girl', child: Text('Girl')),
          ],
          onChanged: (v) => setState(() => _gender = v),
        ),
        TextField(controller: _adm, maxLength: 30, decoration: const InputDecoration(labelText: 'Admission no. (optional)')),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Joined on'),
          subtitle: Text(_joined == null ? 'Not set' : fmt.format(ymdToDate(_joined!))),
          trailing: const Icon(Icons.event_outlined),
          onTap: () => _pickDate(_joined, (v) => _joined = v),
        ),
        const SizedBox(height: 12),
        Text('HEALTH AND SAFETY', style: heading),
        TextField(controller: _med, maxLength: 1000, maxLines: 3, minLines: 1,
            decoration: const InputDecoration(labelText: 'Allergies / medical notes', hintText: 'Shown to the class teacher')),
        TextField(controller: _ecName, maxLength: 150, decoration: const InputDecoration(labelText: 'Emergency contact name')),
        TextField(controller: _ecPhone, maxLength: 20, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Emergency contact phone', hintText: '012-345 6789')),
        TextField(controller: _notes, maxLength: 1000, maxLines: 3, minLines: 1, decoration: const InputDecoration(labelText: 'Other notes (optional)')),
        const SizedBox(height: 12),
        Text('PARENTS', style: heading),
        const Text('One mother, one father, any guardians. New parents are added under Parents.', style: TextStyle(fontSize: 12)),
        if (_parents.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No parents yet.')),
        for (final p in _parents.where((p) => p.isActive || _parentIds.contains(p.id)))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _parentIds.contains(p.id),
            title: Text('${p.fullName} (${p.relationship})'),
            subtitle: p.phone == null ? null : Text(phoneText(p.phone)),
            onChanged: (v) => setState(() => v == true ? _parentIds.add(p.id) : _parentIds.remove(p.id)),
          ),
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
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => ParentFormScreen(parent: p)));
    if (saved == true) ref.invalidate(_parentsProvider);
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
                    p.children.isEmpty ? 'No child linked' : p.children.map((c) => c.fullName).join(', '),
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

class ParentFormScreen extends ConsumerStatefulWidget {
  const ParentFormScreen({super.key, this.parent});
  final ParentRecord? parent;

  @override
  ConsumerState<ParentFormScreen> createState() => _ParentFormScreenState();
}

class _ParentFormScreenState extends ConsumerState<ParentFormScreen> {
  ParentRecord? get p => widget.parent;
  late final _name = TextEditingController(text: p?.fullName ?? '');
  late final _email = TextEditingController(text: p?.email ?? '');
  late final _phone = TextEditingController(text: phoneText(p?.phone));
  final _password = TextEditingController();
  late String _rel = p?.relationship ?? 'Mother';
  late bool _active = p?.isActive ?? true;
  late bool _createLogin = p == null;
  late Set<int> _childIds = {...?p?.children.map((c) => c.id)};
  List<ChildRecord> _children = [];
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(schoolAdminProvider).children().then((v) { if (mounted) setState(() => _children = v); }).catchError((_) {});
  }

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
      final note = await ref.read(schoolAdminProvider).saveParent(p?.id, {
        'fullName': _name.text.trim(),
        'email': _email.text.trim().isEmpty ? null : _email.text.trim(),
        'phone': _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'relationship': _rel,
        'isActive': _active,
        'studentIds': _childIds.toList(),
        'createLogin': p == null ? _createLogin : (!p!.hasLogin && _createLogin),
        'password': _password.text.isEmpty ? null : _password.text,
      });
      if (mounted) {
        toast(context, note == null ? 'Saved' : 'Saved: $note');
        Navigator.pop(context, true);
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
    final heading = Theme.of(context).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: .6);
    final hasLogin = p?.hasLogin ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text(p == null ? 'Add parent' : 'Edit parent'),
        actions: [TextButton(onPressed: _saving ? null : _save, child: const Text('Save'))],
      ),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
        if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
        TextField(controller: _name, maxLength: 150, decoration: const InputDecoration(labelText: 'Full name')),
        DropdownButtonFormField<String>(
          value: _rel,
          decoration: const InputDecoration(labelText: 'Relationship'),
          items: [for (final r in relationships) DropdownMenuItem(value: r, child: Text(r))],
          onChanged: (v) => setState(() => _rel = v ?? 'Mother'),
        ),
        TextField(controller: _email, maxLength: 150, keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: 'Email', helperText: hasLogin ? 'The login (${p!.username}) uses this email.' : null)),
        TextField(controller: _phone, maxLength: 20, keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone', hintText: '012-345 6789')),
        const SizedBox(height: 12),
        Text('CHILDREN', style: heading),
        if (_children.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('No children yet. You can link them later.')),
        for (final c in _children.where((c) => c.isActive || _childIds.contains(c.id)))
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _childIds.contains(c.id),
            title: Text(c.fullName),
            subtitle: Text([
              c.className ?? 'No class',
              if (c.parents.any((x) => x.id != p?.id)) 'linked to ${c.parents.where((x) => x.id != p?.id).map((x) => '${x.fullName} (${x.relationship})').join(', ')}',
            ].join(' · ')),
            onChanged: (v) => setState(() => v == true ? _childIds.add(c.id) : _childIds.remove(c.id)),
          ),
        const SizedBox(height: 12),
        Text('PARENT LOGIN', style: heading),
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
          TextField(controller: _password, maxLength: 100,
              decoration: const InputDecoration(labelText: 'Set a new password (optional)',
                  helperText: 'For parents who can\'t get the email; they choose their own at sign-in.')),
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
