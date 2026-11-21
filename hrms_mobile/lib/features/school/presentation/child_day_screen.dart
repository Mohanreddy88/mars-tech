import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/widgets/error_view.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

final _dayProvider = FutureProvider.autoDispose.family<ChildDay, (int, String)>(
    (ref, key) => ref.watch(schoolRepositoryProvider).day(key.$1, key.$2));

final _childNotesProvider = FutureProvider.autoDispose.family<List<ParentNote>, int>(
    (ref, id) => ref.watch(schoolRepositoryProvider).notes(studentId: id));

/// One child's day: arrival and home time (who picked up), the daily report with photos,
/// and (parents) absence / pickup notes to the school.
class ChildDayScreen extends ConsumerStatefulWidget {
  const ChildDayScreen({super.key, required this.childId, this.date});
  final int childId;
  final String? date;

  @override
  ConsumerState<ChildDayScreen> createState() => _ChildDayScreenState();
}

class _ChildDayScreenState extends ConsumerState<ChildDayScreen> {
  late String _date = widget.date ?? schoolToday();

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(_dayProvider((widget.childId, _date)));
    final isParent = ref.watch(schoolMeProvider).valueOrNull?.isParent ?? false;
    final data = day.valueOrNull;

    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(data?.childName ?? 'My child'),
          if (data?.className != null)
            Text('Class ${data!.className}${data.teacher != null ? ' · ${data.teacher}' : ''}',
                style: Theme.of(context).textTheme.bodySmall),
        ]),
      ),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(_childNotesProvider(widget.childId));
          ref.invalidate(_dayProvider((widget.childId, _date)));
          await ref.read(_dayProvider((widget.childId, _date)).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
          children: [
            DayBar(date: _date, today: data?.today ?? schoolToday(), onChanged: (d) => setState(() => _date = d)),
            if (isParent)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
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
              ),
            day.when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(_dayProvider((widget.childId, _date)))),
              data: (d) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _AttendanceCard(day: d),
                const SizedBox(height: 10),
                _ReportCard(day: d),
              ]),
            ),
            if (isParent) _MyNotes(childId: widget.childId),
          ],
        ),
      ),
    );
  }

  Future<void> _note(String kind) async {
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _NoteSheet(childId: widget.childId, kind: kind),
    );
    if (sent == true) {
      ref.invalidate(_childNotesProvider(widget.childId));
      ref.invalidate(_dayProvider((widget.childId, _date)));
    }
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
            step(Icons.login, 'Arrived ${a.checkIn}', 'Checked in by ${a.checkInBy ?? ''}', true),
            a.checkOut != null
                ? step(Icons.home_outlined, 'Went home ${a.checkOut}', 'Picked up by ${a.pickedUpBy ?? ''}', true)
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

class _MyNotes extends ConsumerWidget {
  const _MyNotes({required this.childId});
  final int childId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = schoolToday();
    final notes = (ref.watch(_childNotesProvider(childId)).valueOrNull ?? const [])
        .where((n) => !n.cancelled && n.toDate.compareTo(today) >= 0)
        .toList();
    if (notes.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 16),
      Text('Your notes to the school', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
      const SizedBox(height: 6),
      for (final n in notes)
        Card(
          child: ListTile(
            leading: Icon(n.isAbsence ? Icons.sick_outlined : Icons.directions_car_outlined),
            title: Text(n.isAbsence
                ? 'Absent · ${noteWhen(n)}'
                : '${n.pickupName} picks up · ${noteWhen(n)}${n.pickupTime != null ? ' at ${n.pickupTime}' : ''}'),
            subtitle: Text([
              if (n.message != null) n.message!,
              n.seenByName != null ? 'Seen by ${n.seenByName}' : 'Sent',
            ].join('\n')),
            trailing: TextButton(
              onPressed: () async {
                if (await attempt(context, () => ref.read(schoolRepositoryProvider).cancelNote(n.id), done: 'Note withdrawn')) {
                  ref.invalidate(_childNotesProvider(childId));
                }
              },
              child: const Text('Withdraw'),
            ),
          ),
        ),
    ]);
  }
}

/// Parent: absence (one or more days) or someone else picking up.
class _NoteSheet extends ConsumerStatefulWidget {
  const _NoteSheet({required this.childId, required this.kind});
  final int childId;
  final String kind;

  @override
  ConsumerState<_NoteSheet> createState() => _NoteSheetState();
}

class _NoteSheetState extends ConsumerState<_NoteSheet> {
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
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(context).bottom + 16),
      child: SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
          Text(_absence ? 'Report an absence' : 'Someone else is picking up',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          const Text('The class teacher and the office are told straight away.'),
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
