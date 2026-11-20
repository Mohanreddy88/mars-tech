import 'package:flutter/material.dart';

import '../data/attendance_models.dart';

/// One day of an attendance period: date, weekend/holiday tag, comment,
/// and the hours or leave code. Tappable when [onTap] is set.
class AttendanceDayRow extends StatelessWidget {
  const AttendanceDayRow({super.key, required this.day, required this.label, this.onTap});

  final AttendanceDay day;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final offDay = !day.isWorkingDay;

    final String value;
    final Color bg, fg;
    if (day.isLeave) {
      value = day.leaveCode!;
      bg = const Color(0xFFFEF3C7);
      fg = const Color(0xFF92400E);
    } else if (day.hours > 0) {
      final h = day.hours;
      value = '${h == h.roundToDouble() ? h.toStringAsFixed(0) : h} h';
      bg = scheme.primaryContainer;
      fg = scheme.onPrimaryContainer;
    } else {
      value = offDay ? '—' : '0 h';
      bg = scheme.surfaceContainerHighest;
      fg = scheme.onSurfaceVariant;
    }

    final tag = day.isPublicHoliday ? 'Public holiday' : day.isWeekend ? 'Weekend' : null;
    final subtitle = [
      if (tag != null) tag,
      if (day.remarks?.trim().isNotEmpty ?? false) day.remarks!.trim(),
    ].join(' · ');

    return ListTile(
      onTap: onTap,
      tileColor: offDay ? scheme.surfaceContainerLow : null,
      title: Text(label,
          style: TextStyle(
              color: offDay ? scheme.onSurfaceVariant : null,
              fontWeight: FontWeight.w500)),
      subtitle: day.needsComment
          ? Text('Comment required for leave', style: TextStyle(color: scheme.error))
          : subtitle.isEmpty
              ? null
              : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Container(
        constraints: const BoxConstraints(minWidth: 56),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
        child: Text(value,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelLarge?.copyWith(color: fg, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

