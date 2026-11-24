import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

/// Admin: the school day's timings — start, late after, absent if not in by, each session's end,
/// the evening automatic check-out — and the automatic attendance switch.
class SchoolTimesScreen extends ConsumerStatefulWidget {
  const SchoolTimesScreen({super.key});

  @override
  ConsumerState<SchoolTimesScreen> createState() => _SchoolTimesScreenState();
}

class _SchoolTimesScreenState extends ConsumerState<SchoolTimesScreen> {
  static const _fields = [
    ('start', 'School starts', Icons.wb_twilight_outlined),
    ('lateAfter', 'Late after', Icons.timer_outlined),
    ('absentAfter', 'Absent if not in by', Icons.person_off_outlined),
    ('halfDayEnd', 'Half day ends', Icons.schedule_outlined),
    ('fullDayEnd', 'Full day ends', Icons.schedule_outlined),
    ('daycareEnd', 'Daycare ends', Icons.schedule_outlined),
    ('autoCheckOutAt', 'Automatic check-out at', Icons.nightlight_outlined),
  ];

  Map<String, dynamic>? _t;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ref.read(schoolRepositoryProvider).schoolTimes().then((t) {
      if (mounted) setState(() => _t = Map.of(t));
    }).catchError((Object e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    });
  }

  TimeOfDay _parse(String? v) => v == null || v.length < 5
      ? const TimeOfDay(hour: 8, minute: 30)
      : TimeOfDay(hour: int.parse(v.substring(0, 2)), minute: int.parse(v.substring(3, 5)));

  String _fmt(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await ref.read(schoolRepositoryProvider).saveSchoolTimes(_t!);
      if (mounted) {
        setState(() => _t = Map.of(saved));
        toast(context, 'School timings saved');
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = _t;
    return Scaffold(
      appBar: AppBar(
        title: const Text('School day timings'),
        actions: [TextButton(onPressed: t == null || _saving ? null : _save, child: const Text('Save'))],
      ),
      body: t == null
          ? Center(child: _error != null ? Text(_error!) : const CircularProgressIndicator())
          : ListView(padding: const EdgeInsets.fromLTRB(12, 8, 12, 32), children: [
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              Card(
                child: Column(children: [
                  for (final (key, label, icon) in _fields)
                    ListTile(
                      leading: Icon(icon),
                      title: Text(label),
                      trailing: Text(t[key] as String? ?? '—', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                      onTap: () async {
                        final picked = await showTimePicker(context: context, helpText: label, initialTime: _parse(t[key] as String?));
                        if (picked != null) setState(() => t[key] = _fmt(picked));
                      },
                    ),
                ]),
              ),
              Card(
                child: SwitchListTile(
                  title: const Text('Automatic attendance'),
                  subtitle: Text('School days only (not weekends or public holidays):\n'
                      '• ${t['lateAfter']} — parents of children not checked in are asked if they\'re coming\n'
                      '• ${t['absentAfter']} — those children are marked absent (a teacher can still check them in)\n'
                      '• ${t['autoCheckOutAt']} — children not checked out are checked out at their session\'s end'),
                  isThreeLine: true,
                  value: t['auto'] == true,
                  onChanged: (v) => setState(() => t['auto'] = v),
                ),
              ),
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Check-in after "Late after" is marked Late. Check-out suggests the session\'s end time.',
                    style: TextStyle(fontSize: 12)),
              ),
              const SizedBox(height: 8),
              FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save timings')),
            ]),
    );
  }
}
