import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_extras.dart';
import '../data/school_models.dart' show SchoolClassRef, schoolToday, ymdToDate;
import '../data/school_repository.dart' show schoolMeProvider;

/// Class timetable (class teachers): set up the class's week — add, edit or delete a period, or copy
/// one day to other days. Admins see it on the website; parents on their child's page.
class ClassTimetableScreen extends ConsumerStatefulWidget {
  const ClassTimetableScreen({super.key});

  @override
  ConsumerState<ClassTimetableScreen> createState() => _ClassTimetableScreenState();
}

class _ClassTimetableScreenState extends ConsumerState<ClassTimetableScreen> {
  int? _classId;
  final int _todayDow = ymdToDate(schoolToday()).weekday;
  late int _day = _todayDow;
  /// This week's Monday: the plan repeats weekly; the dates just help people find their way.
  late final DateTime _monday = ymdToDate(schoolToday()).subtract(Duration(days: _todayDow - 1));

  static String _fmt(DateTime d, {bool year = true}) => DateFormat(year ? 'EEE d MMM y' : 'EEE d MMM').format(d);
  Future<TimetableWeek>? _load;
  List<({int id, String name})> _teachers = const [];

  SchoolExtrasRepository get _repo => ref.read(schoolExtrasProvider);

  @override
  void initState() {
    super.initState();
    _repo.timetableTeachers().then((t) {
      if (mounted) setState(() => _teachers = t);
    }).catchError((_) {});
  }

  void _reload() => setState(() => _load = _repo.classTimetable(_classId!));

  void _snack(String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _edit({TimetableSlot? slot, String? startAfter}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _PeriodSheet(
        repo: _repo,
        classId: _classId!,
        day: slot?.dayOfWeek ?? _day,
        slot: slot,
        startAfter: startAfter,
        teachers: _teachers,
      ),
    );
    if (saved == true) _reload();
  }

  Future<void> _copy(List<TimetableSlot> all) async {
    final from = _day;
    final count = all.where((s) => s.dayOfWeek == from).length;
    if (count == 0) {
      _snack('${weekDayShort[from - 1]} has no periods to copy.');
      return;
    }
    final targets = <int>{};
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text('Copy ${weekDayShort[from - 1]} ($count periods) to'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            for (var d = 1; d <= 7; d++)
              if (d != from)
                CheckboxListTile(
                  dense: true,
                  value: targets.contains(d),
                  title: Text(weekDayShort[d - 1]),
                  onChanged: (v) => set(() => v == true ? targets.add(d) : targets.remove(d)),
                ),
            const Text('The chosen days\' periods are replaced.', style: TextStyle(color: Color(0xFFB45309))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Copy')),
          ],
        ),
      ),
    );
    if (ok != true || targets.isEmpty) return;
    try {
      final n = await _repo.copyDay(_classId!, from, targets.toList());
      _snack('$n periods copied.');
      _reload();
    } on ApiException catch (e) {
      _snack(e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(schoolMeProvider);
    return me.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(appBar: AppBar(title: const Text('Class timetable · weekly plan')), body: ErrorView(error: e, onRetry: () => ref.invalidate(schoolMeProvider))),
      data: (me) {
        final List<SchoolClassRef> classes = me.classes;
        if (classes.isEmpty) {
          return Scaffold(
            appBar: AppBar(title: const Text('Class timetable · weekly plan')),
            body: const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: Text('You are not named as a teacher of any class yet — ask the office.', textAlign: TextAlign.center)),
            ),
          );
        }
        if (_classId == null || !classes.any((c) => c.id == _classId)) {
          _classId = classes.first.id;
          _load = _repo.classTimetable(_classId!);
        }
        return FutureBuilder<TimetableWeek>(
          future: _load,
          builder: (context, snap) {
            final all = snap.data?.slots ?? const <TimetableSlot>[];
            final slots = all.where((s) => s.dayOfWeek == _day).toList();
            final used = all.map((s) => s.dayOfWeek).toSet();
            final days = [for (var d = 1; d <= 7; d++) if (d <= 5 || used.contains(d) || d == _day) d];
            return Scaffold(
              appBar: AppBar(
                title: const Text('Class timetable · weekly plan'),
                actions: [
                  IconButton(
                    tooltip: 'Copy this day to other days',
                    onPressed: snap.hasData ? () => _copy(all) : null,
                    icon: const Icon(Icons.copy_all_outlined),
                  ),
                ],
              ),
              floatingActionButton: FloatingActionButton.extended(
                onPressed: snap.hasData ? () => _edit(startAfter: slots.isEmpty ? null : slots.last.endTime) : null,
                icon: const Icon(Icons.add),
                label: const Text('Add period'),
              ),
              body: RefreshIndicator(
                onRefresh: () async => _reload(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 96),
                  children: [
                    if (classes.length > 1)
                      DropdownButtonFormField<int>(
                        initialValue: _classId,
                        decoration: const InputDecoration(labelText: 'Class', isDense: true),
                        items: [for (final c in classes) DropdownMenuItem(value: c.id, child: Text(c.name))],
                        onChanged: (v) {
                          _classId = v;
                          _reload();
                        },
                      )
                    else
                      Text('Class ${classes.first.name}', style: Theme.of(context).textTheme.titleSmall),
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(color: const Color(0xFFEFF6FF), borderRadius: BorderRadius.circular(8)),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text('This week: ${_fmt(_monday, year: false)} – ${_fmt(_monday.add(const Duration(days: 6)))}',
                            style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF1E40AF))),
                        const SizedBox(height: 2),
                        const Text('The same periods repeat every week, so a change applies from today onwards. '
                            'Daily "what we covered" notes go under My timetable.'),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final d in days)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: ChoiceChip(
                              label: Text('${d == _todayDow ? 'Today · ' : ''}${weekDayShort[d - 1]} ${DateFormat('d MMM').format(_monday.add(Duration(days: d - 1)))} '
                                  '(${all.where((s) => s.dayOfWeek == d).length})'),
                              avatar: d == _todayDow ? const Icon(Icons.circle, size: 8, color: Color(0xFF16A34A)) : null,
                              selected: d == _day,
                              onSelected: (_) => setState(() => _day = d),
                            ),
                          ),
                        ActionChip(
                          label: const Text('Weekend'),
                          onPressed: () => setState(() => _day = _day == 6 ? 7 : 6),
                        ),
                      ]),
                    ),
                    const SizedBox(height: 8),
                    if (snap.connectionState == ConnectionState.waiting && !snap.hasData)
                      const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
                    else if (snap.hasError)
                      ErrorView(error: snap.error!, onRetry: _reload)
                    else if (slots.isEmpty)
                      Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text('No periods on ${weekDayShort[_day - 1]} yet. Tap "Add period".', textAlign: TextAlign.center),
                      )
                    else
                      for (final s in slots)
                        Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            onTap: () => _edit(slot: s),
                            leading: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(s.startTime, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
                              Text(s.endTime, style: Theme.of(context).textTheme.bodySmall),
                            ]),
                            title: Text(s.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                            subtitle: Text([if (s.teacherName != null) s.teacherName!, if (s.notes != null) s.notes!].join(' · ')),
                            trailing: const Icon(Icons.edit_outlined),
                          ),
                        ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

/// Add / edit one period.
class _PeriodSheet extends StatefulWidget {
  const _PeriodSheet({required this.repo, required this.classId, required this.day, this.slot, this.startAfter, required this.teachers});
  final SchoolExtrasRepository repo;
  final int classId;
  final int day;
  final TimetableSlot? slot;
  final String? startAfter;
  final List<({int id, String name})> teachers;

  @override
  State<_PeriodSheet> createState() => _PeriodSheetState();
}

class _PeriodSheetState extends State<_PeriodSheet> {
  late int _day = widget.slot?.dayOfWeek ?? widget.day;
  late TimeOfDay _start = _parse(widget.slot?.startTime ?? widget.startAfter ?? '09:00');
  late TimeOfDay _end = widget.slot != null
      ? _parse(widget.slot!.endTime)
      : TimeOfDay(hour: (_start.hour + 1).clamp(0, 23), minute: _start.minute);
  late final _subject = TextEditingController(text: widget.slot?.subject ?? '');
  late final _notes = TextEditingController(text: widget.slot?.notes ?? '');
  late int? _teacher = widget.slot?.teacherEmployeeId;
  bool _saving = false;
  String? _error;

  static TimeOfDay _parse(String hm) {
    final p = hm.split(':');
    return TimeOfDay(hour: int.tryParse(p[0]) ?? 9, minute: p.length > 1 ? int.tryParse(p[1]) ?? 0 : 0);
  }

  static String _hm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _subject.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _pick(bool start) async {
    final t = await showTimePicker(context: context, initialTime: start ? _start : _end);
    if (t == null) return;
    setState(() {
      if (start) {
        _start = t;
        if (_hm(_end).compareTo(_hm(t)) <= 0) _end = TimeOfDay(hour: (t.hour + 1).clamp(0, 23), minute: t.minute);
      } else {
        _end = t;
      }
    });
  }

  Future<void> _save() async {
    final subject = _subject.text.trim();
    if (subject.isEmpty) return setState(() => _error = 'Enter what is taught (subject or activity).');
    if (_hm(_end).compareTo(_hm(_start)) <= 0) return setState(() => _error = 'The end time must be after the start time.');
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.repo.saveSlot(
        id: widget.slot?.id, classId: widget.classId, dayOfWeek: _day, startTime: _hm(_start), endTime: _hm(_end),
        subject: subject, teacherEmployeeId: _teacher, notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() {
        _saving = false;
        _error = e.message;
      });
    }
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete period'),
        content: Text('Delete ${widget.slot!.subject} (${weekDayShort[widget.slot!.dayOfWeek - 1]} ${widget.slot!.startTime})?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await widget.repo.deleteSlot(widget.slot!.id);
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final teacherIds = widget.teachers.map((t) => t.id).toSet();
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, 16 + MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(widget.slot == null ? 'Add period' : 'Edit period', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
          DropdownButtonFormField<int>(
            initialValue: _day,
            decoration: const InputDecoration(labelText: 'Day'),
            items: [for (var d = 1; d <= 7; d++) DropdownMenuItem(value: d, child: Text(weekDayShort[d - 1]))],
            onChanged: (v) => setState(() => _day = v ?? _day),
          ),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(true),
                icon: const Icon(Icons.schedule),
                label: Text('From ${_hm(_start)}'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => _pick(false),
                icon: const Icon(Icons.schedule),
                label: Text('To ${_hm(_end)}'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          TextField(
            controller: _subject,
            maxLength: 100,
            decoration: const InputDecoration(labelText: 'Subject / activity', hintText: 'e.g. Phonics, Circle time, Lunch'),
          ),
          DropdownButtonFormField<int?>(
            initialValue: teacherIds.contains(_teacher) ? _teacher : null,
            decoration: const InputDecoration(labelText: 'Teacher'),
            items: [
              const DropdownMenuItem<int?>(value: null, child: Text('The class teacher')),
              for (final t in widget.teachers) DropdownMenuItem<int?>(value: t.id, child: Text(t.name)),
            ],
            onChanged: (v) => setState(() => _teacher = v),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notes,
            maxLength: 500,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Plan / notes (optional)'),
          ),
          const SizedBox(height: 8),
          Row(children: [
            if (widget.slot != null)
              TextButton.icon(
                onPressed: _saving ? null : _delete,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Delete'),
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.error),
              ),
            const Spacer(),
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
          ]),
        ]),
      ),
    );
  }
}
