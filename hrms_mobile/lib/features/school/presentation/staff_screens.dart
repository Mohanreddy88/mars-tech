import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

/// Attendance & daily reports (class teachers: their classes; admins: all):
/// check in, check out (who picked up), absent, parents' notes, and each child's daily report.
class SchoolAttendanceScreen extends ConsumerStatefulWidget {
  const SchoolAttendanceScreen({super.key, this.date});
  final String? date;

  @override
  ConsumerState<SchoolAttendanceScreen> createState() => _SchoolAttendanceScreenState();
}

class _SchoolAttendanceScreenState extends ConsumerState<SchoolAttendanceScreen> {
  late String _date = widget.date ?? schoolToday();
  int? _classId;
  List<SchoolClassRef> _classes = [];
  AttendanceDay? _data;
  Object? _error;
  bool _loading = true;
  int? _busy;

  SchoolRepository get _repo => ref.read(schoolRepositoryProvider);
  bool get _isToday => _data == null ? _date == schoolToday() : _date == _data!.today;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final me = await ref.read(schoolMeProvider.future);
    if (me.isAdmin) {
      try {
        _classes = await _repo.classes();
      } catch (_) {}
    } else {
      _classes = me.classes;
      if (_classes.length == 1) _classId = _classes.first.id;
    }
    await _load();
  }

  Future<void> _load({bool quiet = false}) async {
    if (!quiet) setState(() => _loading = true);
    try {
      final d = await _repo.attendance(classId: _classId, date: _date);
      if (mounted) setState(() {
        _data = d;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (mounted) setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  Future<void> _run(AttendanceRow r, Future<void> Function() action, String done) async {
    setState(() => _busy = r.studentId);
    final ok = await attempt(context, action, done: done);
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) _load(quiet: true);
  }

  String _hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<String?> _askTime(String title) async {
    final t = await showTimePicker(context: context, helpText: title, initialTime: TimeOfDay.now());
    return t == null ? null : _hhmm(t);
  }

  Future<void> _checkIn(AttendanceRow r) async {
    String? time;
    if (!_isToday) {
      time = await _askTime('Arrival time');
      if (time == null) return;
    }
    await _run(r, () => _repo.checkIn(r.studentId, _date, time: time), '${r.fullName} checked in');
  }

  Future<void> _checkOut(AttendanceRow r) async {
    final result = await showModalBottomSheet<(String, String?)>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickupSheet(row: r, askTime: !_isToday, sessionEnd: _data?.sessionEnd(r.sessionType)),
    );
    if (result == null) return;
    await _run(r, () => _repo.checkOut(r.studentId, _date, result.$1, time: result.$2), '${r.fullName} checked out');
  }

  Future<void> _absent(AttendanceRow r) async {
    final note = r.notes.where((n) => n.isAbsence).firstOrNull;
    final ctrl = TextEditingController(text: note?.message ?? (note != null ? 'Parent reported absence' : ''));
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${r.fullName} is absent'),
        content: TextField(controller: ctrl, maxLength: 300, decoration: const InputDecoration(labelText: 'Reason (optional)')),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('Save')),
        ],
      ),
    );
    if (reason == null) return;
    await _run(r, () => _repo.markAbsent(r.studentId, _date, reason.isEmpty ? null : reason), '${r.fullName} marked absent');
  }

  Future<void> _openReport(AttendanceRow r) async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => ReportEditorScreen(studentId: r.studentId, childName: r.fullName, date: _date),
    ));
    _load(quiet: true);
  }

  Future<void> _publishDrafts() async {
    final ids = _data!.rows.where((r) => r.reportPublished == false).map((r) => r.studentId).toList();
    await attempt(context, () async {
      final n = await _repo.publishReports(_date, ids);
      if (mounted) toast(context, '$n daily report${n == 1 ? '' : 's'} sent to parents.');
    });
    _load(quiet: true);
  }

  @override
  Widget build(BuildContext context) {
    final d = _data;
    final drafts = d?.rows.where((r) => r.reportPublished == false).length ?? 0;
    return Scaffold(
      appBar: AppBar(title: const Text('Attendance & Reports')),
      floatingActionButton: drafts > 0
          ? FloatingActionButton.extended(
              onPressed: _publishDrafts,
              icon: const Icon(Icons.send),
              label: Text('Send $drafts draft report${drafts == 1 ? '' : 's'}'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => _load(quiet: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 96),
          children: [
            if (_classes.length > 1 || (_classes.isNotEmpty && (ref.read(schoolMeProvider).valueOrNull?.isAdmin ?? false)))
              DropdownButtonFormField<int?>(
                value: _classId,
                decoration: const InputDecoration(labelText: 'Class', isDense: true),
                items: [
                  const DropdownMenuItem<int?>(value: null, child: Text('All classes')),
                  for (final c in _classes) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                ],
                onChanged: (v) {
                  _classId = v;
                  _load();
                },
              ),
            DayBar(
              date: _date,
              today: d?.today ?? schoolToday(),
              onChanged: (v) {
                _date = v;
                _load();
              },
            ),
            if (d != null)
              Wrap(spacing: 6, runSpacing: 6, children: [
                Pill('${d.present} present', tone: PillTone.good),
                Pill('${d.goneHome} gone home', tone: PillTone.info),
                Pill('${d.absent} absent', tone: PillTone.bad),
                Pill('${d.notMarked} not marked'),
                Pill('${d.reportsSent}/${d.rows.length} reports sent', tone: PillTone.info),
              ]),
            if (d != null && !d.canEdit)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('🔒 Earlier days are read-only for teachers. Ask the office to correct a past day.'),
              ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              ErrorView(error: _error!, onRetry: _load)
            else if (d!.rows.isEmpty)
              const Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No children here.')))
            else
              for (final r in d.rows) _RowCard(
                row: r,
                canChange: d.canEdit && !r.locked,
                busy: _busy == r.studentId,
                onCheckIn: () => _checkIn(r),
                onCheckOut: () => _checkOut(r),
                onAbsent: () => _absent(r),
                onUndo: () => _run(r, () => _repo.clearAttendance(r.studentId, _date), 'Cleared'),
                onReport: () => _openReport(r),
                onSeen: (n) => _run(r, () => _repo.markNoteSeen(n.id), n.isAbsence ? 'Absence approved' : 'Marked as seen'),
              ),
          ],
        ),
      ),
    );
  }
}

class _RowCard extends StatelessWidget {
  const _RowCard({required this.row, required this.canChange, required this.busy, required this.onCheckIn, required this.onCheckOut,
      required this.onAbsent, required this.onUndo, required this.onReport, required this.onSeen});
  final AttendanceRow row;
  /// Teachers: only today, and not once the child is absent.
  final bool canChange;
  final bool busy;
  final VoidCallback onCheckIn, onCheckOut, onAbsent, onUndo, onReport;
  final ValueChanged<ParentNote> onSeen;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final a = row.attendance;
    final reportLabel = row.reportPublished == null ? 'Write report' : row.reportPublished! ? 'Report sent' : 'Report draft';
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: a?.absent == true ? scheme.errorContainer.withValues(alpha: 0.35) : row.expectedAbsent ? const Color(0xFFFFFBEB) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(row.fullName, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                Text('${row.className ?? 'No class'} · ${row.sessionType}', style: text.bodySmall),
              ]),
            ),
            if (busy) const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
          if (row.medicalNotes != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('⚕ ${row.medicalNotes}', style: text.bodySmall?.copyWith(color: scheme.error, fontWeight: FontWeight.w600)),
            ),
          for (final n in row.notes)
            Container(
              margin: const EdgeInsets.only(top: 6),
              padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
              decoration: BoxDecoration(
                color: n.isAbsence ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(children: [
                Expanded(
                  child: Text(
                    n.isAbsence
                        ? 'Absent${n.fromDate == n.toDate ? '' : ' (${noteWhen(n)})'}${n.message != null ? ': ${n.message}' : ''} — ${n.createdByName}'
                        : 'Pickup: ${n.pickupName}${n.pickupTime != null ? ' at ${n.pickupTime}' : ''}'
                            '${n.pickupPhone != null ? ' · ${phoneText(n.pickupPhone)}' : ''} — ${n.createdByName}',
                    style: text.bodySmall,
                  ),
                ),
                n.seenByName == null
                    ? TextButton(onPressed: () => onSeen(n), child: Text(n.isAbsence ? 'Approve' : 'Seen'))
                    : const Padding(padding: EdgeInsets.all(8), child: Icon(Icons.done_all, size: 18, color: Color(0xFF16A34A))),
              ]),
            ),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
            if (a == null && row.locked) ...[
              const Pill('Absent: reported by the parent (approved)', tone: PillTone.bad),
            ] else if (a == null && !canChange) ...[
              const Pill('Not marked'),
            ] else if (a == null) ...[
              FilledButton.icon(onPressed: busy ? null : onCheckIn, icon: const Icon(Icons.login, size: 18), label: const Text('Check in')),
              OutlinedButton(onPressed: busy ? null : onAbsent, child: const Text('Absent')),
            ] else if (a.absent) ...[
              Pill('Absent${a.autoAbsent ? ' (automatic)' : ''}${a.absenceReason != null ? ': ${a.absenceReason}' : ''}',
                  tone: PillTone.bad),
              // Marked absent automatically but arrived after all: checking in makes them present (late)
              if (a.autoAbsent && canChange)
                TextButton.icon(onPressed: busy ? null : onCheckIn, icon: const Icon(Icons.login, size: 18), label: const Text('Arrived')),
            ] else ...[
              Pill('In ${a.checkIn}', tone: PillTone.good),
              if (a.isLate) const Pill('Late', tone: PillTone.warn),
              if (a.checkOut != null)
                Pill('Home ${a.checkOut} · ${a.autoCheckOut ? 'automatic' : a.pickedUpBy ?? ''}', tone: PillTone.info)
              else if (canChange)
                OutlinedButton.icon(onPressed: busy ? null : onCheckOut, icon: const Icon(Icons.logout, size: 18), label: const Text('Check out')),
            ],
            if (a != null && canChange) TextButton(onPressed: busy ? null : onUndo, child: const Text('Undo')),
          ]),
          const Divider(height: 16),
          InkWell(
            onTap: onReport,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                Icon(row.reportPublished == true ? Icons.check_circle : Icons.edit_note,
                    color: row.reportPublished == true ? const Color(0xFF16A34A) : scheme.primary),
                const SizedBox(width: 8),
                Expanded(child: Text('$reportLabel${row.reportMood != null ? ' ${moods[row.reportMood] ?? ''}' : ''}'
                    '${row.reportPhotos > 0 ? ' · ${row.reportPhotos} photo${row.reportPhotos == 1 ? '' : 's'}' : ''}')),
                const Icon(Icons.chevron_right),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Who collected the child (parents, a pickup note's person, or someone else) and, for a past day, when.
class _PickupSheet extends StatefulWidget {
  const _PickupSheet({required this.row, required this.askTime, this.sessionEnd});
  /// When the child's session ends ("16:30"): suggested as the time for a past day, or once it has passed today.
  final String? sessionEnd;
  final AttendanceRow row;
  final bool askTime;

  @override
  State<_PickupSheet> createState() => _PickupSheetState();
}

class _PickupSheetState extends State<_PickupSheet> {
  late final List<String> _choices = [
    for (final n in widget.row.notes.where((n) => !n.isAbsence && n.pickupName != null)) '${n.pickupName} (pickup note)',
    for (final p in widget.row.parents) p.label,
  ];
  late String? _who = _choices.isEmpty ? null : _choices.first;
  final _other = TextEditingController();
  late TimeOfDay? _time = _suggested();

  TimeOfDay? _suggested() {
    final e = widget.sessionEnd;
    if (e == null || e.length < 5) return null;
    final end = TimeOfDay(hour: int.parse(e.substring(0, 2)), minute: int.parse(e.substring(3, 5)));
    final now = TimeOfDay.now();
    final passed = now.hour * 60 + now.minute > end.hour * 60 + end.minute;
    return widget.askTime || passed ? end : null;
  }

  @override
  void dispose() {
    _other.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final other = _who == null;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Check out ${widget.row.fullName}', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        const Text('Picked up by'),
        for (final c in _choices)
          RadioListTile<String?>(value: c, groupValue: _who, title: Text(c), contentPadding: EdgeInsets.zero,
              onChanged: (v) => setState(() => _who = v)),
        RadioListTile<String?>(value: null, groupValue: _who, title: const Text('Someone else'), contentPadding: EdgeInsets.zero,
            onChanged: (v) => setState(() => _who = null)),
        if (other) ...[
          TextField(controller: _other, maxLength: 150,
              decoration: const InputDecoration(labelText: 'Name (and relation)', hintText: 'e.g. Grandma Lim')),
          const Text('Not a parent and no pickup note: check their ID and call a parent if unsure.',
              style: TextStyle(color: Color(0xFFB45309), fontSize: 12)),
        ],
        if (widget.askTime || _time != null)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.schedule),
            title: const Text('Time'),
            subtitle: Text(_time?.format(context) ?? 'Choose'),
            onTap: () async {
              final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 17, minute: 0));
              if (t != null) setState(() => _time = t);
            },
          ),
        const SizedBox(height: 8),
        FilledButton(
          onPressed: () {
            final who = (other ? _other.text : _who!).replaceAll(' (pickup note)', '').trim();
            if (who.isEmpty) return;
            if (widget.askTime && _time == null) return;
            final t = _time == null
                ? null
                : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';
            Navigator.pop(context, (who, t));
          },
          child: const Text('Save'),
        ),
      ]),
    );
  }
}

/// The teacher's report on one child's day: meals, nap, toilet, mood, activities, note, photos.
class ReportEditorScreen extends ConsumerStatefulWidget {
  const ReportEditorScreen({super.key, required this.studentId, required this.childName, required this.date});
  final int studentId;
  final String childName;
  final String date;

  @override
  ConsumerState<ReportEditorScreen> createState() => _ReportEditorScreenState();
}

class _ReportEditorScreenState extends ConsumerState<ReportEditorScreen> {
  DailyReport _r = const DailyReport();
  final _toilet = TextEditingController();
  final _activities = TextEditingController();
  final _note = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  bool _uploading = false;

  SchoolRepository get _repo => ref.read(schoolRepositoryProvider);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _toilet.dispose();
    _activities.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final day = await _repo.day(widget.studentId, widget.date);
      if (!mounted) return;
      setState(() {
        _r = day.report ?? const DailyReport();
        _toilet.text = _r.toilet ?? '';
        _activities.text = _r.activities ?? '';
        _note.text = _r.teacherNote ?? '';
        _loading = false;
      });
    } catch (e) {
      if (mounted) {
        toast(context, ApiException.from(e).message, error: true);
        setState(() => _loading = false);
      }
    }
  }

  DailyReport _current() => DailyReport(
        breakfast: _r.breakfast, lunch: _r.lunch, snack: _r.snack, napFrom: _r.napFrom, napTo: _r.napTo, mood: _r.mood,
        toilet: _toilet.text.trim().isEmpty ? null : _toilet.text.trim(),
        activities: _activities.text.trim().isEmpty ? null : _activities.text.trim(),
        teacherNote: _note.text.trim().isEmpty ? null : _note.text.trim(),
      );

  DailyReport _with({String? breakfast, String? lunch, String? snack, String? mood, String? napFrom, String? napTo,
          bool clearNap = false}) =>
      DailyReport(
        id: _r.id,
        breakfast: breakfast ?? _r.breakfast,
        lunch: lunch ?? _r.lunch,
        snack: snack ?? _r.snack,
        mood: mood ?? _r.mood,
        napFrom: clearNap ? null : napFrom ?? _r.napFrom,
        napTo: clearNap ? null : napTo ?? _r.napTo,
        publishedAt: _r.publishedAt,
        photoIds: _r.photoIds,
      );

  Future<void> _save({required bool publish}) async {
    setState(() => _saving = true);
    try {
      final saved = await _repo.saveReport(widget.studentId, widget.date, _current(), publish: publish);
      if (!mounted) return;
      toast(context, publish ? 'Sent to the parents.' : 'Saved.');
      if (publish || saved.published) {
        Navigator.pop(context);
      } else {
        setState(() => _r = saved);
      }
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _addPhoto() async {
    final f = await pickPhoto(context);
    if (f == null || !mounted) return;
    setState(() => _uploading = true);
    try {
      // Keep what's typed: save the text first, then the photo
      await _repo.saveReport(widget.studentId, widget.date, _current());
      await _repo.addReportPhoto(widget.studentId, widget.date, f);
      final day = await _repo.day(widget.studentId, widget.date);
      if (mounted && day.report != null) setState(() => _r = day.report!);
    } catch (e) {
      if (mounted) toast(context, ApiException.from(e).message, error: true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _removePhoto(int id) async {
    if (await attempt(context, () => _repo.deleteReportPhoto(id))) {
      setState(() => _r = DailyReport(
            id: _r.id, breakfast: _r.breakfast, lunch: _r.lunch, snack: _r.snack, napFrom: _r.napFrom, napTo: _r.napTo,
            mood: _r.mood, publishedAt: _r.publishedAt, photoIds: _r.photoIds.where((p) => p != id).toList(),
          ));
    }
  }

  Future<void> _pickNap(bool start) async {
    final cur = start ? _r.napFrom : _r.napTo;
    final init = cur == null
        ? TimeOfDay(hour: start ? 12 : 14, minute: start ? 30 : 0)
        : TimeOfDay(hour: int.parse(cur.substring(0, 2)), minute: int.parse(cur.substring(3, 5)));
    final t = await showTimePicker(context: context, initialTime: init, helpText: start ? 'Nap from' : 'Nap until');
    if (t == null) return;
    final v = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    setState(() => _r = start ? _with(napFrom: v) : _with(napTo: v));
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    Widget heading(String s) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 6),
          child: Text(s.toUpperCase(), style: text.labelSmall?.copyWith(fontWeight: FontWeight.w700, letterSpacing: .6)),
        );
    Widget meal(String label, String? value, String Function(String) set) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(children: [
            SizedBox(width: 90, child: Text(label)),
            Expanded(
              child: Wrap(spacing: 6, children: [
                for (final m in mealAmounts)
                  ChoiceChip(label: Text(m), selected: value == m, onSelected: (on) => setState(() => set(on ? m : ''))),
              ]),
            ),
          ]),
        );

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.childName),
          Text('Daily report · ${MaterialLocalizations.of(context).formatMediumDate(ymdToDate(widget.date))}', style: text.bodySmall),
        ]),
      ),
      bottomNavigationBar: _loading
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                child: Row(children: [
                  if (!_r.published)
                    Expanded(
                      child: OutlinedButton(onPressed: _saving ? null : () => _save(publish: false), child: const Text('Save draft')),
                    ),
                  if (!_r.published) const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      onPressed: _saving ? null : () => _save(publish: !_r.published),
                      child: Text(_r.published ? 'Save changes' : 'Send to parents'),
                    ),
                  ),
                ]),
              ),
            ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
              if (_r.published)
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFDCFCE7), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Already sent to the parents. Saved changes show to them straight away.'),
                ),
              heading('Meals'),
              meal('Breakfast', _r.breakfast, (v) => (_r = _with(breakfast: v)).breakfast ?? ''),
              meal('Lunch', _r.lunch, (v) => (_r = _with(lunch: v)).lunch ?? ''),
              meal('Tea', _r.snack, (v) => (_r = _with(snack: v)).snack ?? ''),
              heading('Nap'),
              Row(children: [
                Expanded(child: OutlinedButton(onPressed: () => _pickNap(true), child: Text('From ${_r.napFrom ?? '—'}'))),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton(onPressed: () => _pickNap(false), child: Text('Until ${_r.napTo ?? '—'}'))),
                IconButton(onPressed: () => setState(() => _r = _with(clearNap: true)), icon: const Icon(Icons.clear), tooltip: 'No nap'),
              ]),
              heading('Toilet / diaper'),
              TextField(controller: _toilet, maxLength: 200, decoration: const InputDecoration(hintText: 'e.g. Diaper changed 3 times')),
              heading('Mood'),
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final e in moods.entries)
                  ChoiceChip(
                    label: Text('${e.value} ${e.key}'),
                    selected: _r.mood == e.key,
                    onSelected: (on) => setState(() => _r = _with(mood: on ? e.key : '')),
                  ),
              ]),
              heading('Activities and learning'),
              TextField(controller: _activities, maxLength: 1000, minLines: 2, maxLines: 6,
                  decoration: const InputDecoration(hintText: 'e.g. Painting with leaves, counting to 10')),
              heading('Note to parents (optional)'),
              TextField(controller: _note, maxLength: 1000, minLines: 1, maxLines: 4,
                  decoration: const InputDecoration(hintText: 'e.g. Please bring a spare set of clothes')),
              heading('Photos (${_r.photoIds.length} of 6)'),
              Wrap(spacing: 8, runSpacing: 8, children: [
                for (final id in _r.photoIds)
                  Stack(children: [
                    ProtectedPhoto(provider: reportPhotoProvider(id), size: 96),
                    Positioned(
                      top: 2, right: 2,
                      child: InkWell(
                        onTap: () => _removePhoto(id),
                        child: const CircleAvatar(radius: 12, backgroundColor: Colors.black54,
                            child: Icon(Icons.close, size: 14, color: Colors.white)),
                      ),
                    ),
                  ]),
                if (_r.photoIds.length < 6)
                  InkWell(
                    onTap: _uploading ? null : _addPhoto,
                    child: Container(
                      width: 96, height: 96,
                      decoration: BoxDecoration(
                        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant, width: 2),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Center(
                        child: _uploading
                            ? const CircularProgressIndicator(strokeWidth: 2)
                            : const Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.photo_camera_outlined), Text('Add')]),
                      ),
                    ),
                  ),
              ]),
            ]),
    );
  }
}

/// My Class: the children of the teacher's classes, medical notes, parents' phone numbers.
class MyClassScreen extends ConsumerWidget {
  const MyClassScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(_myClassProvider);
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('My Class')),
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_myClassProvider)),
        data: (kids) => RefreshIndicator(
          onRefresh: () => ref.refresh(_myClassProvider.future),
          child: kids.isEmpty
              ? ListView(children: const [Padding(padding: EdgeInsets.all(40), child: Center(child: Text('No children in your class yet.')))])
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: kids.length,
                  itemBuilder: (context, i) {
                    final k = kids[i];
                    return Card(
                      child: ExpansionTile(
                        title: Text(k.fullName, style: const TextStyle(fontWeight: FontWeight.w600)),
                        subtitle: Text('${k.className ?? ''} · ${k.sessionType}'),
                        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (k.medicalNotes != null)
                            Text('⚕ ${k.medicalNotes}', style: text.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error)),
                          for (final p in k.parents)
                            ListTile(
                              contentPadding: EdgeInsets.zero,
                              dense: true,
                              leading: const Icon(Icons.person_outline),
                              title: Text(p.label),
                              subtitle: p.phone == null ? null : Text(phoneText(p.phone)),
                              trailing: p.phone == null
                                  ? null
                                  : IconButton(
                                      tooltip: 'Copy number',
                                      icon: const Icon(Icons.copy, size: 18),
                                      onPressed: () {
                                        Clipboard.setData(ClipboardData(text: p.phone!));
                                        toast(context, 'Number copied');
                                      },
                                    ),
                            ),
                          if (k.emergencyContactName != null || k.emergencyContactPhone != null)
                            Text('Emergency: ${k.emergencyContactName ?? ''} ${phoneText(k.emergencyContactPhone)}', style: text.bodySmall),
                        ],
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }
}

final _myClassProvider = FutureProvider.autoDispose<List<StudentInfo>>((ref) => ref.watch(schoolRepositoryProvider).students());
