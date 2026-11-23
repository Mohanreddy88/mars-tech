import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

final _dayProvider = FutureProvider.autoDispose.family<ChildDay, (int, String)>(
    (ref, key) => ref.watch(schoolRepositoryProvider).day(key.$1, key.$2));

final _childNotesProvider = FutureProvider.autoDispose.family<List<ParentNote>, int>(
    (ref, id) => ref.watch(schoolRepositoryProvider).notes(studentId: id));

/// (child, from, to) → days with attendance or a sent report.
final _daysProvider = FutureProvider.autoDispose.family<List<ChildDayMark>, (int, String, String)>(
    (ref, k) => ref.watch(schoolRepositoryProvider).days(k.$1, k.$2, k.$3));

/// Which part of the child's day a home tile opens.
enum ChildDayView {
  /// Arrival / home time and the report for one day (default).
  today('Today'),

  /// The daily report, with the recent days that have one.
  report('Daily report'),

  /// The month at a glance: present / absent.
  attendance('Attendance'),

  /// Report an absence or another pickup, and the notes already sent.
  notes('Absence / pickup');

  const ChildDayView(this.title);
  final String title;

  static ChildDayView parse(String? v) =>
      ChildDayView.values.firstWhere((e) => e.name == v, orElse: () => ChildDayView.today);
}

/// One child's day: arrival and home time (who picked up), the daily report with photos,
/// and (parents) absence / pickup notes to the school. [view] picks the part to show.
class ChildDayScreen extends ConsumerStatefulWidget {
  const ChildDayScreen({super.key, required this.childId, this.date, this.view = ChildDayView.today});
  final int childId;
  final String? date;
  final ChildDayView view;

  @override
  ConsumerState<ChildDayScreen> createState() => _ChildDayScreenState();
}

class _ChildDayScreenState extends ConsumerState<ChildDayScreen> {
  late String _date = widget.date ?? schoolToday();
  late ChildDayView _view = widget.view;

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(_dayProvider((widget.childId, _date)));
    final isParent = ref.watch(schoolMeProvider).valueOrNull?.isParent ?? false;
    final data = day.valueOrNull;
    final today = data?.today ?? schoolToday();

    final List<Widget> content = switch (_view) {
      ChildDayView.today => [
          DayBar(date: _date, today: today, onChanged: (d) => setState(() => _date = d)),
          if (isParent) _noteButtons(),
          _dayCards(day, attendance: true, report: true),
          if (isParent) _MyNotes(childId: widget.childId),
        ],
      ChildDayView.report => [
          DayBar(date: _date, today: today, onChanged: (d) => setState(() => _date = d)),
          _dayCards(day, attendance: false, report: true),
          _RecentReports(childId: widget.childId, selected: _date, onPick: (d) => setState(() => _date = d)),
        ],
      ChildDayView.attendance => [
          _AttendanceMonth(
            childId: widget.childId,
            onPick: (d) => setState(() {
              _date = d;
              _view = ChildDayView.today;
            }),
          ),
        ],
      ChildDayView.notes => [
          if (isParent) _noteButtons(),
          _MyNotes(childId: widget.childId, all: true),
        ],
    };

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_view == ChildDayView.today ? (data?.childName ?? 'My child') : _view.title),
          if (_view != ChildDayView.today && data != null)
            Text(data.childName, style: Theme.of(context).textTheme.bodySmall)
          else if (data?.className != null)
            Text('Class ${data!.className}${data.teacher != null ? ' · ${data.teacher}' : ''}',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_childNotesProvider(widget.childId));
          ref.invalidate(_daysProvider);
          ref.invalidate(_dayProvider((widget.childId, _date)));
          await ref.read(_dayProvider((widget.childId, _date)).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: content,
        ),
      ),
    );
  }

  Widget _noteButtons() => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Row(children: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _note('Absence'),
              icon: const Icon(Icons.sick_outlined, size: 18),
              label: const Text('Report absence'),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton.icon(
              onPressed: () => _note('Pickup'),
              icon: const Icon(Icons.directions_car_outlined, size: 18),
              label: const Text('Other pickup'),
            ),
          ),
        ]),
      );

  Widget _dayCards(AsyncValue<ChildDay> day, {required bool attendance, required bool report}) => day.when(
        skipLoadingOnRefresh: true,
        loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_dayProvider((widget.childId, _date)))),
        data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          if (attendance) _AttendanceCard(day: d),
          if (attendance && report) const SizedBox(height: 10),
          if (report) _ReportCard(day: d),
        ]),
      );

  Future<void> _note(String kind) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ParentNoteSheet(childId: widget.childId, kind: kind),
    );
    if (sent == true) {
      ref.invalidate(_childNotesProvider(widget.childId));
      ref.invalidate(_dayProvider((widget.childId, _date)));
    }
  }
}

/// Recent days with a sent daily report (last 30 days); tap one to open its report.
class _RecentReports extends ConsumerWidget {
  const _RecentReports({required this.childId, required this.selected, required this.onPick});
  final int childId;
  final String selected;
  final ValueChanged<String> onPick;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = schoolToday();
    final days = ref.watch(_daysProvider((childId, addDays(today, -30), today))).valueOrNull;
    final withReport = (days ?? const <ChildDayMark>[]).where((d) => d.report).toList();
    if (withReport.isEmpty) return const SizedBox.shrink();
    final f = DateFormat('EEE d MMM');
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Recent reports', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final d in withReport)
            ChoiceChip(
              label: Text(f.format(ymdToDate(d.date))),
              selected: d.date == selected,
              onSelected: (_) => onPick(d.date),
            ),
        ]),
      ]),
    );
  }
}

/// A month of attendance: present / absent per day, with totals. Tap a day to open it.
class _AttendanceMonth extends ConsumerStatefulWidget {
  const _AttendanceMonth({required this.childId, required this.onPick});
  final int childId;
  final ValueChanged<String> onPick;

  @override
  ConsumerState<_AttendanceMonth> createState() => _AttendanceMonthState();
}

class _AttendanceMonthState extends ConsumerState<_AttendanceMonth> {
  late DateTime _month = () {
    final t = ymdToDate(schoolToday());
    return DateTime(t.year, t.month);
  }();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = schoolToday();
    final t = ymdToDate(today);
    final first = _month;
    final last = DateTime(first.year, first.month + 1, 0);
    final to = dateToYmd(last).compareTo(today) > 0 ? today : dateToYmd(last);
    final isCurrent = first.year == t.year && first.month == t.month;
    final async = ref.watch(_daysProvider((widget.childId, dateToYmd(first), to)));
    final byDate = {for (final d in async.valueOrNull ?? const <ChildDayMark>[]) d.date: d};
    final present = byDate.values.where((d) => d.present).length;
    final absent = byDate.values.where((d) => d.absent).length;

    Widget cell(DateTime d) {
      final ymd = dateToYmd(d);
      final mark = byDate[ymd];
      final future = ymd.compareTo(today) > 0;
      final weekend = d.weekday >= DateTime.saturday;
      final (Color bg, Color fg) = mark?.present == true
          ? (const Color(0xFFDCFCE7), const Color(0xFF166534))
          : mark?.absent == true
              ? (theme.colorScheme.errorContainer, theme.colorScheme.onErrorContainer)
              : (Colors.transparent, future || weekend ? theme.disabledColor : theme.colorScheme.onSurface);
      return InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: future ? null : () => widget.onPick(ymd),
        child: Container(
          margin: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(8),
            border: ymd == today ? Border.all(color: theme.colorScheme.primary, width: 1.5) : null,
          ),
          alignment: Alignment.center,
          child: Text('${d.day}', style: TextStyle(color: fg, fontWeight: mark != null ? FontWeight.w700 : null)),
        ),
      );
    }

    final lead = first.weekday - 1; // weeks start on Monday
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        IconButton(
          icon: const Icon(Icons.chevron_left),
          tooltip: 'Previous month',
          onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
        ),
        Expanded(
          child: Text(DateFormat('MMMM yyyy').format(first),
              textAlign: TextAlign.center, style: theme.textTheme.titleMedium),
        ),
        IconButton(
          icon: const Icon(Icons.chevron_right),
          tooltip: 'Next month',
          onPressed: isCurrent ? null : () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
        ),
      ]),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(children: [
            Row(children: [
              for (final w in const ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'])
                Expanded(child: Text(w, textAlign: TextAlign.center, style: theme.textTheme.labelSmall)),
            ]),
            const SizedBox(height: 4),
            GridView.count(
              crossAxisCount: 7,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                for (var i = 0; i < lead; i++) const SizedBox.shrink(),
                for (var d = 1; d <= last.day; d++) cell(DateTime(first.year, first.month, d)),
              ],
            ),
            if (async.isLoading) const LinearProgressIndicator(minHeight: 2),
            if (async.hasError)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(ApiException.from(async.error!).message, style: TextStyle(color: theme.colorScheme.error)),
              ),
          ]),
        ),
      ),
      const SizedBox(height: 8),
      Wrap(spacing: 8, runSpacing: 6, children: [
        Pill('Present: $present', tone: PillTone.good),
        Pill('Absent: $absent', tone: absent > 0 ? PillTone.bad : PillTone.neutral),
      ]),
      const SizedBox(height: 6),
      Text('Tap a day to see arrival, pickup and the daily report.',
          style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
    ]);
  }
}

class _AttendanceCard extends StatelessWidget {
  const _AttendanceCard({required this.day});
  final ChildDay day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final a = day.attendance;
    Widget step(IconData icon, String title, String sub, bool done) => ListTile(
          contentPadding: EdgeInsets.zero,
          leading: CircleAvatar(
            backgroundColor: done ? const Color(0xFFDCFCE7) : scheme.surfaceContainerHighest,
            child: Icon(icon, color: done ? const Color(0xFF16A34A) : scheme.onSurfaceVariant),
          ),
          title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text(sub),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('At school', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          if (a == null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(day.date == day.today ? 'Not checked in yet.' : 'No attendance recorded.'),
            )
          else if (a.absent)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Pill('Absent${a.absenceReason != null ? ': ${a.absenceReason}' : ''}', tone: PillTone.bad),
            )
          else ...[
            step(Icons.login, 'Arrived ${a.checkIn}${a.isLate ? ' · late' : ''}', 'Checked in by ${a.checkInBy ?? ''}', true),
            a.checkOut != null
                ? step(Icons.home_outlined, 'Went home ${a.checkOut}',
                    a.autoCheckOut ? 'End of the day (checked out automatically)' : 'Picked up by ${a.pickedUpBy ?? ''}', true)
                : step(Icons.home_outlined, 'Still at school', 'You\'ll be told when your child is picked up.', false),
          ],
          for (final n in day.notes)
            Container(
              margin: const EdgeInsets.only(top: 8, bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: n.isAbsence ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2FE),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Note: ${n.isAbsence ? 'absent' : '${n.pickupName} picks up${n.pickupTime != null ? ' at ${n.pickupTime}' : ''}'}'
                '${n.seenByName != null ? ' · seen by ${n.seenByName}' : ''}',
              ),
            ),
        ]),
      ),
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({required this.day});
  final ChildDay day;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final r = day.report;
    Widget row(String label, String value) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            SizedBox(width: 90, child: Text(label, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
            Expanded(child: Text(value)),
          ]),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Daily report', style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          if (r == null)
            Text(day.date == day.today ? 'The teacher sends it at the end of the day.' : 'No report for this day.')
          else ...[
            if (r.mood != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text('${moods[r.mood] ?? ''} ${r.mood} today', style: text.titleMedium),
              ),
            if (r.breakfast != null || r.lunch != null || r.snack != null)
              row('Meals', [
                if (r.breakfast != null) 'Breakfast: ${r.breakfast}',
                if (r.lunch != null) 'Lunch: ${r.lunch}',
                if (r.snack != null) 'Tea: ${r.snack}',
              ].join('\n')),
            row('Nap', r.napFrom == null && r.napTo == null ? 'No nap' : '${r.napFrom ?? '?'} – ${r.napTo ?? '?'}'),
            if (r.toilet != null) row('Toilet', r.toilet!),
            if (r.activities != null) row('Activities', r.activities!),
            if (r.teacherNote != null)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFFF5F3FF), borderRadius: BorderRadius.circular(8)),
                child: Text('${r.teacherNote} — ${r.updatedByName}'),
              ),
            if (r.photoIds.isNotEmpty) ...[
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 3,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                children: [for (final id in r.photoIds) ProtectedPhoto(provider: reportPhotoProvider(id))],
              ),
            ],
          ],
        ]),
      ),
    );
  }
}

/// The parent's notes to the school. Normally the upcoming ones; with [all], also the last
/// 30 days and withdrawn ones (the Absence / pickup page).
class _MyNotes extends ConsumerWidget {
  const _MyNotes({required this.childId, this.all = false});
  final int childId;
  final bool all;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = schoolToday();
    final async = ref.watch(_childNotesProvider(childId));
    final list = async.valueOrNull ?? const <ParentNote>[];
    final upcoming = list.where((n) => !n.cancelled && n.toDate.compareTo(today) >= 0).toList()
      ..sort((a, b) => a.fromDate.compareTo(b.fromDate));
    final past = all ? list.where((n) => n.cancelled || n.toDate.compareTo(today) < 0).toList() : const <ParentNote>[];
    final titleStyle = Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700);

    if (all && async.isLoading && list.isEmpty) {
      return const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()));
    }
    if (upcoming.isEmpty && past.isEmpty) {
      return all
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Text('No notes yet. Use the buttons above to tell the school your child will be absent, '
                  'or that someone else will pick them up.'),
            )
          : const SizedBox.shrink();
    }

    Widget card(ParentNote n, {required bool canWithdraw}) => Card(
          child: ListTile(
            leading: Icon(n.isAbsence ? Icons.sick_outlined : Icons.directions_car_outlined),
            title: Text(n.isAbsence
                ? 'Absent · ${noteWhen(n)}'
                : '${n.pickupName} picks up · ${noteWhen(n)}${n.pickupTime != null ? ' at ${n.pickupTime}' : ''}'),
            subtitle: Text([
              if (n.message != null) n.message!,
              n.cancelled ? 'Withdrawn' : (n.seenByName != null ? 'Seen by ${n.seenByName}' : 'Sent'),
            ].join('\n')),
            trailing: canWithdraw
                ? TextButton(
                    onPressed: () async {
                      if (await attempt(context, () => ref.read(schoolRepositoryProvider).cancelNote(n.id),
                          done: 'Note withdrawn')) {
                        ref.invalidate(_childNotesProvider(childId));
                      }
                    },
                    child: const Text('Withdraw'),
                  )
                : null,
          ),
        );

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      if (upcoming.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text(all ? 'Upcoming' : 'Your notes to the school', style: titleStyle),
        const SizedBox(height: 6),
        for (final n in upcoming) card(n, canWithdraw: true),
      ],
      if (past.isNotEmpty) ...[
        const SizedBox(height: 16),
        Text('Earlier and withdrawn', style: titleStyle),
        const SizedBox(height: 6),
        for (final n in past) card(n, canWithdraw: false),
      ],
    ]);
  }
}

/// Parent: absence (one or more days) or someone else picking up.
class ParentNoteSheet extends ConsumerStatefulWidget {
  const ParentNoteSheet({super.key, required this.childId, required this.kind});
  final int childId;
  final String kind;

  @override
  ConsumerState<ParentNoteSheet> createState() => _ParentNoteSheetState();
}

class _ParentNoteSheetState extends ConsumerState<ParentNoteSheet> {
  late String _from = schoolToday();
  late String _to = schoolToday();
  TimeOfDay? _time;
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _msg = TextEditingController();
  bool _saving = false;
  String? _error;

  bool get _absence => widget.kind == 'Absence';

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _msg.dispose();
    super.dispose();
  }

  Future<String?> _pickDate(String current, String min) async {
    final d = await showDatePicker(
      context: context,
      initialDate: ymdToDate(current),
      firstDate: ymdToDate(min),
      lastDate: ymdToDate(schoolToday()).add(const Duration(days: 365)),
    );
    return d == null ? null : dateToYmd(d);
  }

  Future<void> _save() async {
    if (!_absence && _name.text.trim().isEmpty) {
      setState(() => _error = 'Who will pick your child up?');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(schoolRepositoryProvider).createNote({
        'studentId': widget.childId,
        'kind': widget.kind,
        'fromDate': _from,
        'toDate': _absence ? _to : null,
        'pickupName': _absence ? null : _name.text.trim(),
        'pickupPhone': _absence || _phone.text.trim().isEmpty ? null : _phone.text.trim(),
        'pickupTime': _time == null
            ? null
            : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
        'message': _msg.text.trim().isEmpty ? null : _msg.text.trim(),
      });
      if (mounted) {
        toast(context, 'Sent. The teacher and office have been told.');
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
    String label(String ymd) => MaterialLocalizations.of(context).formatMediumDate(ymdToDate(ymd));
    // Another pickup only makes sense on a day the child is at school
    final absentNote = _absence
        ? null
        : (ref.watch(_childNotesProvider(widget.childId)).valueOrNull ?? const <ParentNote>[])
            .where((n) => n.isAbsence && !n.cancelled && n.fromDate.compareTo(_from) <= 0 && n.toDate.compareTo(_from) >= 0)
            .firstOrNull;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(_absence ? 'Report an absence' : 'Someone else is picking up',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('The class teacher and the office are told straight away.'),
          if (absentNote != null) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: const Color(0xFFFEF3C7), borderRadius: BorderRadius.circular(8)),
              child: Text('You reported your child absent on ${label(_from)} (${noteWhen(absentNote)}), so no pickup '
                  'is needed. Choose another day, or withdraw the absence first.'),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 12),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_outlined),
            title: Text(_absence ? 'First day' : 'Day'),
            subtitle: Text(label(_from)),
            onTap: () async {
              final d = await _pickDate(_from, schoolToday());
              if (d != null) setState(() {
                _from = d;
                if (_to.compareTo(d) < 0) _to = d;
              });
            },
          ),
          if (_absence)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.event_available_outlined),
              title: const Text('Last day'),
              subtitle: Text(label(_to)),
              onTap: () async {
                final d = await _pickDate(_to, _from);
                if (d != null) setState(() => _to = d);
              },
            )
          else ...[
            TextField(controller: _name, maxLength: 150,
                decoration: const InputDecoration(labelText: 'Who will pick up', hintText: 'e.g. Grandma Lim')),
            TextField(controller: _phone, keyboardType: TextInputType.phone, maxLength: 20,
                decoration: const InputDecoration(labelText: 'Their phone (optional)', hintText: '012-345 6789')),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.schedule),
              title: const Text('Around what time (optional)'),
              subtitle: Text(_time?.format(context) ?? 'Not set'),
              onTap: () async {
                final t = await showTimePicker(context: context, initialTime: _time ?? const TimeOfDay(hour: 15, minute: 0));
                if (t != null) setState(() => _time = t);
              },
            ),
          ],
          TextField(
            controller: _msg,
            maxLength: 1000,
            minLines: 2,
            maxLines: 4,
            decoration: InputDecoration(labelText: _absence ? 'Reason (optional)' : 'Message (optional)'),
          ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _saving || absentNote != null ? null : _save,
            child: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Send to the school'),
          ),
        ]),
      ),
    );
  }
}
