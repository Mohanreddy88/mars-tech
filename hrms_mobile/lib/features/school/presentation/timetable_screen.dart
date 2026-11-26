import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/error_view.dart';
import '../data/school_extras.dart';
import '../data/school_models.dart' show schoolToday, ymdToDate;
import '../data/school_repository.dart' show schoolMeProvider;
import 'package:go_router/go_router.dart';
import '../../../core/router/app_router.dart' show Routes;
import 'school_widgets.dart';

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Timetable, hour by hour. Without [studentId]: "My timetable" (the signed-in teacher's periods,
/// with a "what we covered" note per period). With [studentId]: the child's class timetable
/// (parents), notes read-only.
class TimetableScreen extends ConsumerStatefulWidget {
  const TimetableScreen({super.key, this.studentId, this.title});
  final int? studentId;
  final String? title;

  @override
  ConsumerState<TimetableScreen> createState() => _TimetableScreenState();
}

class _TimetableScreenState extends ConsumerState<TimetableScreen> {
  late final String _today = schoolToday();
  late String _date = _today;
  late Future<TimetableWeek> _load = _fetch();
  int? _day;

  Future<TimetableWeek> _fetch() {
    final repo = ref.read(schoolExtrasProvider);
    return widget.studentId == null ? repo.myTimetable(_date) : repo.childTimetable(widget.studentId!, _date);
  }

  void _go(String date) => setState(() {
        _date = date;
        _day = null;
        _load = _fetch();
      });

  /// "Today, " / "Yesterday, " / "Tomorrow, " before the date.
  String _relative() {
    final diff = ymdToDate(_date).difference(ymdToDate(_today)).inDays;
    return switch (diff) { 0 => 'Today, ', -1 => 'Yesterday, ', 1 => 'Tomorrow, ', _ => '' };
  }

  void _shift(int days) => _go(_ymd(ymdToDate(_date).add(Duration(days: days))));

  @override
  Widget build(BuildContext context) {
    final mine = widget.studentId == null;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (mine ? 'My timetable' : 'Timetable')),
        actions: [
          // Class teachers set up their class's week
          if (mine && (ref.watch(schoolMeProvider).valueOrNull?.isTeacher ?? false))
            TextButton.icon(
              label: const Text('Weekly plan'),
              onPressed: () async {
                await context.push(Routes.schoolClassTimetable);
                if (mounted) _go(_date);
              },
              icon: const Icon(Icons.edit_calendar_outlined),
            ),
        ],
      ),
      body: FutureBuilder<TimetableWeek>(
        future: _load,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting && !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) return ErrorView(error: snap.error!, onRetry: () => _go(_date));
          final w = snap.data!;
          final day = _day ?? w.dayOfWeek;
          final used = w.slots.map((s) => s.dayOfWeek).toSet();
          final days = [for (var d = 1; d <= 7; d++) if (d <= 5 || used.contains(d)) d];
          final slots = w.slots.where((s) => s.dayOfWeek == day).toList();
          final logDay = day == w.dayOfWeek;

          return RefreshIndicator(
            onRefresh: () async => _go(_date),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
              children: [
                if (!mine && w.className != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text('Class ${w.className}', style: Theme.of(context).textTheme.titleSmall),
                  ),
                Row(children: [
                  IconButton(onPressed: () => _shift(-1), icon: const Icon(Icons.chevron_left)),
                  Expanded(
                    child: Center(
                      child: Text(
                        '${_relative()}${DateFormat('EEE d MMM').format(ymdToDate(_date))}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  ),
                  IconButton(onPressed: () => _shift(1), icon: const Icon(Icons.chevron_right)),
                ]),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: [
                    for (final d in days)
                      Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: ChoiceChip(
                          label: Text(weekDayShort[d - 1]),
                          selected: d == day,
                          avatar: d == w.dayOfWeek ? const Icon(Icons.circle, size: 8, color: Color(0xFF16A34A)) : null,
                          onSelected: (_) => setState(() => _day = d),
                        ),
                      ),
                  ]),
                ),
                if (mine && _date != _today)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      _date.compareTo(_today) < 0
                          ? '🔒 Earlier days are read-only.'
                          : 'Coming up — notes can be written on the day.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                const SizedBox(height: 8),
                if (w.slots.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      mine
                          ? "No periods yet. Class teachers set up their class's week with the Weekly plan button above."
                          : 'The school hasn\'t set up this class\'s timetable yet.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else if (slots.isEmpty)
                  const Padding(padding: EdgeInsets.all(32), child: Text('No periods on this day.', textAlign: TextAlign.center))
                else
                  for (final s in slots) _PeriodCard(slot: s, date: w.date, showClass: mine, logDay: logDay, today: _date == _today),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _PeriodCard extends ConsumerStatefulWidget {
  const _PeriodCard({required this.slot, required this.date, required this.showClass, required this.logDay, required this.today});
  final TimetableSlot slot;
  final String date;
  final bool showClass;
  final bool logDay;
  final bool today;

  @override
  ConsumerState<_PeriodCard> createState() => _PeriodCardState();
}

class _PeriodCardState extends ConsumerState<_PeriodCard> {
  bool get _now {
    if (!widget.today || !widget.logDay) return false;
    final t = DateFormat('HH:mm').format(DateTime.now());
    return widget.slot.startTime.compareTo(t) <= 0 && t.compareTo(widget.slot.endTime) < 0;
  }

  Future<void> _editNote() async {
    final ctrl = TextEditingController(text: widget.slot.log?.note ?? '');
    final note = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.viewInsetsOf(ctx).bottom + 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('${widget.slot.subject} · ${widget.slot.startTime}–${widget.slot.endTime}',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 8),
          TextField(
            controller: ctrl,
            autofocus: true,
            maxLines: 4,
            maxLength: 1000,
            decoration: const InputDecoration(labelText: 'What we covered', hintText: 'What did the children do / learn?'),
          ),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text), child: const Text('Save')),
        ]),
      ),
    );
    if (note == null || !mounted) return;
    TimetableLog? log;
    final ok = await attempt(context, () async => log = await ref.read(schoolExtrasProvider).saveLog(widget.slot.id, widget.date, note));
    if (ok && mounted) setState(() => widget.slot.log = note.trim().isEmpty ? null : log);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.slot;
    final text = Theme.of(context).textTheme;
    final now = _now;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: now ? const Color(0xFFF0FDF4) : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: now ? const Color(0xFF16A34A) : Colors.transparent),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            width: 52,
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Text(s.startTime, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text(s.endTime, style: text.bodySmall),
            ]),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Flexible(child: Text(s.subject, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
                if (now) ...[const SizedBox(width: 6), const Pill('Now', tone: PillTone.good)],
              ]),
              Text([
                if (widget.showClass) s.className,
                if (s.teacherName != null) s.teacherName!,
              ].join(' · '), style: text.bodySmall),
              if (s.notes != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(s.notes!)),
              if (widget.logDay && s.log != null)
                Container(
                  margin: const EdgeInsets.only(top: 8),
                  padding: const EdgeInsets.all(8),
                  width: double.infinity,
                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('WHAT WE COVERED', style: text.labelSmall?.copyWith(color: const Color(0xFF92400E), fontWeight: FontWeight.w700)),
                    Text(s.log!.note),
                    Text(s.log!.updatedByName, style: text.bodySmall),
                  ]),
                ),
              if (widget.logDay && s.canWriteLog)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _editNote,
                    icon: const Icon(Icons.edit_note, size: 18),
                    label: Text(s.log == null ? 'Add what we covered' : 'Edit note'),
                  ),
                ),
            ]),
          ),
        ]),
      ),
    );
  }
}
