import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/widgets/error_view.dart';
import '../data/school_extras.dart';
import '../data/school_models.dart' show SchoolClassRef, schoolToday, ymdToDate;
import '../data/school_repository.dart' show schoolRepositoryProvider;

String _ymd(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

/// Admin → Timetable: the classes' weekly plan (view only — class teachers set it up) and the
/// daily record: what each class had on any date with the teachers' "what we covered" notes,
/// week by week or day by day.
class AdminTimetableScreen extends ConsumerStatefulWidget {
  const AdminTimetableScreen({super.key});

  @override
  ConsumerState<AdminTimetableScreen> createState() => _AdminTimetableScreenState();
}

class _AdminTimetableScreenState extends ConsumerState<AdminTimetableScreen> {
  late Future<List<SchoolClassRef>> _classes = ref.read(schoolRepositoryProvider).classes();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Timetable'),
          bottom: const TabBar(tabs: [Tab(text: 'Weekly plan'), Tab(text: 'Daily record')]),
        ),
        body: FutureBuilder<List<SchoolClassRef>>(
          future: _classes,
          builder: (context, snap) {
            if (snap.hasError) {
              return ErrorView(
                error: snap.error!,
                onRetry: () => setState(() => _classes = ref.read(schoolRepositoryProvider).classes()),
              );
            }
            if (!snap.hasData) return const Center(child: CircularProgressIndicator());
            final classes = snap.data!;
            if (classes.isEmpty) {
              return const Center(child: Padding(padding: EdgeInsets.all(32), child: Text('No classes yet.')));
            }
            return TabBarView(children: [_PlanTab(classes: classes), _RecordTab(classes: classes)]);
          },
        ),
      ),
    );
  }
}

// ── Weekly plan (view only) ──

class _PlanTab extends ConsumerStatefulWidget {
  const _PlanTab({required this.classes});
  final List<SchoolClassRef> classes;

  @override
  ConsumerState<_PlanTab> createState() => _PlanTabState();
}

class _PlanTabState extends ConsumerState<_PlanTab> with AutomaticKeepAliveClientMixin {
  late int _classId = widget.classes.first.id;
  late final DateTime _today = ymdToDate(schoolToday());
  late int _day = _today.weekday;
  late Future<TimetableWeek> _load = _fetch();

  Future<TimetableWeek> _fetch() => ref.read(schoolExtrasProvider).classTimetable(_classId);

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final monday = _today.subtract(Duration(days: _today.weekday - 1));
    return FutureBuilder<TimetableWeek>(
      future: _load,
      builder: (context, snap) {
        final all = snap.data?.slots ?? const <TimetableSlot>[];
        final used = all.map((s) => s.dayOfWeek).toSet();
        final days = [for (var d = 1; d <= 7; d++) if (d <= 5 || used.contains(d) || d == _today.weekday) d];
        final slots = all.where((s) => s.dayOfWeek == _day).toList();
        return RefreshIndicator(
          onRefresh: () async => setState(() => _load = _fetch()),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              DropdownButtonFormField<int>(
                initialValue: _classId,
                decoration: const InputDecoration(labelText: 'Class', isDense: true),
                items: [for (final c in widget.classes) DropdownMenuItem(value: c.id, child: Text(c.name))],
                onChanged: (v) => setState(() {
                  _classId = v ?? _classId;
                  _load = _fetch();
                }),
              ),
              const SizedBox(height: 8),
              Text(
                'This week: ${DateFormat('EEE d MMM').format(monday)} – ${DateFormat('EEE d MMM y').format(monday.add(const Duration(days: 6)))}. '
                'Set up by the class teachers; the same periods repeat every week.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (final d in days)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ChoiceChip(
                        label: Text('${d == _today.weekday ? 'Today · ' : ''}${weekDayShort[d - 1]} '
                            '${DateFormat('d MMM').format(monday.add(Duration(days: d - 1)))}'),
                        avatar: d == _today.weekday ? const Icon(Icons.circle, size: 8, color: Color(0xFF16A34A)) : null,
                        selected: d == _day,
                        onSelected: (_) => setState(() => _day = d),
                      ),
                    ),
                ]),
              ),
              const SizedBox(height: 8),
              if (snap.hasError)
                ErrorView(error: snap.error!, onRetry: () => setState(() => _load = _fetch()))
              else if (!snap.hasData)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else if (slots.isEmpty)
                const Padding(padding: EdgeInsets.all(32), child: Text('No periods on this day.', textAlign: TextAlign.center))
              else
                for (final s in slots)
                  Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: _Times(s.startTime, s.endTime),
                      title: Text(s.subject, style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text([s.teacherName ?? 'Class teacher', if (s.notes != null) s.notes!].join(' · ')),
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }
}

// ── Daily record ──

class _RecordTab extends ConsumerStatefulWidget {
  const _RecordTab({required this.classes});
  final List<SchoolClassRef> classes;

  @override
  ConsumerState<_RecordTab> createState() => _RecordTabState();
}

class _RecordTabState extends ConsumerState<_RecordTab> with AutomaticKeepAliveClientMixin {
  final String _today = schoolToday();
  int? _classId;
  bool _week = true;
  late DateTime _date = ymdToDate(_today);
  late Future<TimetableRecord> _load = _fetch();

  DateTime get _monday => _date.subtract(Duration(days: _date.weekday - 1));
  DateTime get _from => _week ? _monday : _date;
  DateTime get _to => _week ? _monday.add(const Duration(days: 6)) : _date;

  bool get _isCurrent {
    final t = ymdToDate(_today);
    return _week ? _ymd(_monday) == _ymd(t.subtract(Duration(days: t.weekday - 1))) : _ymd(_date) == _today;
  }

  Future<TimetableRecord> _fetch() => ref.read(schoolExtrasProvider).timetableRecord(_classId, _ymd(_from), _ymd(_to));

  void _reload() => setState(() => _load = _fetch());

  void _move(int n) {
    _date = _date.add(Duration(days: n * (_week ? 7 : 1)));
    _reload();
  }

  Future<void> _pickDate() async {
    final d = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      helpText: 'Go to date',
    );
    if (d == null) return;
    _date = d;
    _reload();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final text = Theme.of(context).textTheme;
    final range = _week
        ? '${DateFormat('d MMM').format(_from)} – ${DateFormat('d MMM y').format(_to)}'
        : DateFormat('EEEE d MMM y').format(_date);
    return FutureBuilder<TimetableRecord>(
      future: _load,
      builder: (context, snap) {
        final r = snap.data;
        final days = r == null
            ? const <RecordDay>[]
            : _week
                ? r.days.where((d) => d.dayOfWeek <= 5 || d.periods.isNotEmpty).toList()
                : r.days;
        return RefreshIndicator(
          onRefresh: () async => _reload(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              Row(children: [
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    initialValue: _classId,
                    decoration: const InputDecoration(labelText: 'Class', isDense: true),
                    items: [
                      const DropdownMenuItem<int?>(value: null, child: Text('All classes')),
                      for (final c in widget.classes) DropdownMenuItem<int?>(value: c.id, child: Text(c.name)),
                    ],
                    onChanged: (v) {
                      _classId = v;
                      _reload();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                SegmentedButton<bool>(
                  segments: const [ButtonSegment(value: true, label: Text('Week')), ButtonSegment(value: false, label: Text('Day'))],
                  selected: {_week},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) {
                    final from = _from, to = _to;
                    _week = s.first;
                    // Day view opens on the date shown if it's in the week, else that week's Monday
                    if (!_week && (_date.isBefore(from) || _date.isAfter(to))) _date = from;
                    _reload();
                  },
                ),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                IconButton(onPressed: () => _move(-1), icon: const Icon(Icons.chevron_left), tooltip: _week ? 'Previous week' : 'Previous day'),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: Column(children: [
                      Text(range, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700), textAlign: TextAlign.center),
                      Text('Tap to pick a date', style: text.bodySmall),
                    ]),
                  ),
                ),
                IconButton(onPressed: () => _move(1), icon: const Icon(Icons.chevron_right), tooltip: _week ? 'Next week' : 'Next day'),
              ]),
              if (!_isCurrent)
                Center(
                  child: TextButton(
                    onPressed: () {
                      _date = ymdToDate(_today);
                      _reload();
                    },
                    child: Text(_week ? 'Back to this week' : 'Back to today'),
                  ),
                ),
              if (r != null && r.periods > 0)
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(8)),
                  child: Row(children: [
                    const Icon(Icons.fact_check_outlined, color: Color(0xFF16A34A), size: 20),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Notes written: ${r.written} of ${r.periods} periods')),
                  ]),
                ),
              if (snap.hasError)
                ErrorView(error: snap.error!, onRetry: _reload)
              else if (r == null)
                const Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator()))
              else
                for (final d in days) ...[
                  if (_week)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 12, 4, 6),
                      child: Row(children: [
                        Text(DateFormat('EEEE d MMM').format(ymdToDate(d.date)),
                            style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
                        if (d.date == r.today) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
                            decoration: BoxDecoration(color: const Color(0xFF16A34A), borderRadius: BorderRadius.circular(10)),
                            child: const Text('Today', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700)),
                          ),
                        ],
                      ]),
                    ),
                  if (d.periods.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
                      child: Text(_week ? 'No periods' : 'Nothing was on the timetable this day.', style: text.bodySmall),
                    )
                  else
                    for (final p in d.periods) _RecordCard(period: p, showClass: _classId == null, past: d.date.compareTo(r.today) <= 0),
                ],
            ],
          ),
        );
      },
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.period, required this.showClass, required this.past});
  final RecordPeriod period;
  final bool showClass;
  final bool past;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final p = period;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _Times(p.startTime, p.endTime),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(p.subject, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
              Text([if (showClass) p.className, p.teacherName ?? 'Class teacher'].join(' · '), style: text.bodySmall),
              const SizedBox(height: 6),
              if (p.note != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(color: const Color(0xFFFFFBEB), borderRadius: BorderRadius.circular(8)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(p.note!),
                    if (p.noteBy != null) Text('— ${p.noteBy}', style: text.bodySmall?.copyWith(color: const Color(0xFF92400E))),
                  ]),
                )
              else
                Text(past ? 'No note written' : 'Planned',
                    style: text.bodySmall?.copyWith(color: Colors.grey, fontStyle: FontStyle.italic)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class _Times extends StatelessWidget {
  const _Times(this.start, this.end);
  final String start;
  final String end;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        Text(start, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF2563EB))),
        Text(end, style: Theme.of(context).textTheme.bodySmall),
      ]);
}
