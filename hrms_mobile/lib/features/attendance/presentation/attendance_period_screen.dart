import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/utils/file_opener.dart';
import '../../../core/widgets/status_chip.dart';
import '../data/attendance_models.dart';
import '../data/attendance_repository.dart';
import 'day_row.dart';

/// One attendance period: a row per day. Editable while Draft / Rejected
/// (or not saved yet): set hours or a leave code + comment, fill all empty
/// weekdays at once, save as draft, or submit for approval.
/// Pops `true` when something was saved.
class AttendancePeriodScreen extends ConsumerStatefulWidget {
  const AttendancePeriodScreen({super.key, required this.period});

  final AttendancePeriod period;

  @override
  ConsumerState<AttendancePeriodScreen> createState() =>
      _AttendancePeriodScreenState();
}

enum _Busy { save, submit, pdf }

class _AttendancePeriodScreenState extends ConsumerState<AttendancePeriodScreen> {
  static const _defaultHours = 8.0;
  static final _dayFmt = DateFormat('EEE, d MMM');

  late final AttendancePeriod _p;
  bool _dirty = false;
  bool _savedSomething = false;
  _Busy? _busy;

  @override
  void initState() {
    super.initState();
    // Work on a copy so leaving without saving changes nothing.
    final src = widget.period;
    _p = AttendancePeriod(
      id: src.id,
      start: src.start,
      end: src.end,
      status: src.status,
      rejectionReason: src.rejectionReason,
      submittedAt: src.submittedAt,
      approvedAt: src.approvedAt,
      days: src.days.map((d) => d.copy()).toList(),
    );
  }

  bool get _editable => _p.isEditable && _busy == null;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final codes = ref.watch(leaveCodesProvider).valueOrNull ?? const <String>[];

    // Every way back (app bar, system back/gesture) comes through here, so the
    // list always learns whether something was saved.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_dirty && !await _confirmDiscard()) return;
        if (context.mounted) Navigator.of(context).pop(_savedSomething);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(_p.label),
          actions: [
            if (_p.isSaved)
              IconButton(
                tooltip: 'Download PDF',
                onPressed: _busy == null ? _openPdf : null,
                icon: _busy == _Busy.pdf
                    ? const SizedBox(
                        width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _SummaryCard(period: _p),
            if (_p.status == 'Rejected' && (_p.rejectionReason?.isNotEmpty ?? false))
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _Banner(
                  icon: Icons.error_outline,
                  color: theme.colorScheme.errorContainer,
                  onColor: theme.colorScheme.onErrorContainer,
                  text: 'Rejected: ${_p.rejectionReason}\nCorrect the days and submit again.',
                ),
              ),
            if (!_p.isEditable)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _Banner(
                  icon: Icons.lock_outline,
                  color: theme.colorScheme.surfaceContainerHighest,
                  onColor: theme.colorScheme.onSurfaceVariant,
                  text: _p.status == 'Approved'
                      ? 'This period is approved and can no longer be changed.'
                      : 'Submitted for approval. You can change it again if it is rejected.',
                ),
              ),
            if (_p.isEditable && _p.emptyWorkingDays > 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: OutlinedButton.icon(
                  onPressed: _editable ? _fillWeekdays : null,
                  icon: const Icon(Icons.auto_fix_high_outlined),
                  label: Text('Fill ${_p.emptyWorkingDays} empty weekdays with '
                      '${_defaultHours.toStringAsFixed(0)} h'),
                ),
              ),
            const SizedBox(height: 12),
            Card(
              child: Column(
                children: [
                  for (var i = 0; i < _p.days.length; i++) ...[
                    if (i > 0) const Divider(height: 1),
                    AttendanceDayRow(
                      day: _p.days[i],
                      label: _dayFmt.format(_p.days[i].date),
                      onTap: _editable ? () => _editDay(_p.days[i], codes) : null,
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: !_p.isEditable
            ? null
            : SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(52)),
                          onPressed: _busy == null ? _saveDraft : null,
                          child: _busy == _Busy.save
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Save draft'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _busy == null ? _submit : null,
                          child: _busy == _Busy.submit
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(strokeWidth: 2))
                              : const Text('Submit'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }

  void _fillWeekdays() {
    setState(() {
      for (final d in _p.days) {
        if (d.isWorkingDay && !d.isLeave && d.hours == 0) d.hours = _defaultHours;
      }
      _dirty = true;
    });
  }

  Future<void> _editDay(AttendanceDay day, List<String> codes) async {
    final edited = await showModalBottomSheet<AttendanceDay>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _DayEditor(day: day, label: _dayFmt.format(day.date), codes: codes),
    );
    if (edited == null) return;
    setState(() {
      day
        ..hours = edited.hours
        ..leaveCode = edited.leaveCode
        ..remarks = edited.remarks;
      _dirty = true;
    });
  }

  /// Saves the period; returns false (after showing why) when it failed.
  Future<bool> _save() async {
    try {
      _p.id = await ref.read(attendanceRepositoryProvider).save(_p);
      if (_p.status != 'Rejected') _p.status = 'Draft';
      _dirty = false;
      _savedSomething = true;
      return true;
    } catch (e) {
      _snack(ApiException.from(e).message);
      return false;
    }
  }

  Future<void> _saveDraft() async {
    setState(() => _busy = _Busy.save);
    final ok = await _save();
    if (!mounted) return;
    setState(() => _busy = null);
    if (ok) _snack('Draft saved');
  }

  Future<void> _submit() async {
    final missingComments = _p.days.where((d) => d.needsComment).toList();
    if (missingComments.isNotEmpty) {
      _snack('Add a comment for each leave day first: '
          '${missingComments.map((d) => '${_dayFmt.format(d.date)} (${d.leaveCode})').join(', ')}');
      return;
    }
    final empty = _p.emptyWorkingDays;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for approval?'),
        content: Text(
          '${empty > 0 ? '$empty working day(s) have no hours or leave. ' : ''}'
          'After submitting you cannot change this period unless it is rejected.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Submit')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busy = _Busy.submit);
    final navigator = Navigator.of(context);
    if (await _save()) {
      try {
        await ref.read(attendanceRepositoryProvider).submit(_p.id!);
        _snack('Attendance submitted for approval');
        navigator.pop(true);
        return;
      } catch (e) {
        _snack(ApiException.from(e).message);
      }
    }
    if (mounted) setState(() => _busy = null);
  }

  Future<void> _openPdf() async {
    setState(() => _busy = _Busy.pdf);
    try {
      final bytes = await ref.read(attendanceRepositoryProvider).pdf(_p.id!);
      final name = 'Attendance_${DateFormat('yyyy-MM-dd').format(_p.start)}.pdf';
      final file = await FileOpener.save(bytes, name);
      await FileOpener.open(file, mimeType: 'application/pdf', subject: 'Attendance ${_p.label}');
    } catch (e) {
      _snack(ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  Future<bool> _confirmDiscard() async =>
      await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Discard changes?'),
          content: const Text('Your changes to this period have not been saved.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep editing')),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Discard')),
          ],
        ),
      ) ??
      false;

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.period});

  final AttendancePeriod period;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    Widget figure(String label, String value) => Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(value,
                  style: text.titleLarge?.copyWith(
                      color: scheme.onPrimary, fontWeight: FontWeight.w700)),
              Text(label,
                  style: text.bodySmall
                      ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
            ],
          ),
        );
    final h = period.totalHours;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text('Status',
                    style: text.bodyMedium
                        ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.8))),
              ),
              StatusChip(period.displayStatus),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              figure('Hours', h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toStringAsFixed(1)),
              figure('Leave days', '${period.leaveDays}'),
              figure('Working days', '${period.workingDays}'),
            ],
          ),
        ],
      ),
    );
  }
}

/// Bottom sheet to edit one day. Pops an edited copy, or null when cancelled.
class _DayEditor extends StatefulWidget {
  const _DayEditor({required this.day, required this.label, required this.codes});

  final AttendanceDay day;
  final String label;
  final List<String> codes;

  @override
  State<_DayEditor> createState() => _DayEditorState();
}

class _DayEditorState extends State<_DayEditor> {
  late final AttendanceDay _d = widget.day.copy();
  late final _remarks = TextEditingController(text: widget.day.remarks ?? '');

  @override
  void dispose() {
    _remarks.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String fmt(double h) => h == h.roundToDouble() ? h.toStringAsFixed(0) : h.toString();

    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.label,
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            Text('Hours worked', style: theme.textTheme.titleSmall),
            const SizedBox(height: 8),
            Row(
              children: [
                IconButton.outlined(
                  onPressed: _d.isLeave || _d.hours <= 0
                      ? null
                      : () => setState(() => _d.hours = (_d.hours - 0.5).clamp(0, 24)),
                  icon: const Icon(Icons.remove),
                ),
                Expanded(
                  child: Text(
                    _d.isLeave ? '—' : '${fmt(_d.hours)} h',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                IconButton.outlined(
                  onPressed: _d.isLeave || _d.hours >= 24
                      ? null
                      : () => setState(() => _d.hours = (_d.hours + 0.5).clamp(0, 24)),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                for (final h in const [0.0, 4.0, 8.0, 9.0])
                  ChoiceChip(
                    label: Text('${fmt(h)} h'),
                    selected: !_d.isLeave && _d.hours == h,
                    onSelected: (_) => setState(() {
                      _d.leaveCode = null;
                      _d.hours = h;
                    }),
                  ),
              ],
            ),
            if (widget.codes.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Or on leave', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final c in widget.codes)
                    ChoiceChip(
                      label: Text(c),
                      selected: _d.leaveCode == c,
                      onSelected: (sel) => setState(() {
                        _d.leaveCode = sel ? c : null;
                        if (sel) _d.hours = 0;
                      }),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: _remarks,
              maxLength: 200,
              decoration: InputDecoration(
                labelText: _d.isLeave ? 'Comment (required for leave)' : 'Comment (optional)',
              ),
            ),
            const SizedBox(height: 8),
            FilledButton(
              onPressed: () {
                _d.remarks = _remarks.text.trim().isEmpty ? null : _remarks.text.trim();
                Navigator.pop(context, _d);
              },
              child: const Text('Done'),
            ),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({
    required this.icon,
    required this.color,
    required this.onColor,
    required this.text,
  });

  final IconData icon;
  final Color color;
  final Color onColor;
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: onColor, size: 20),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: onColor))),
          ],
        ),
      );
}
