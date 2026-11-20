import '../../../core/utils/formatters.dart';

/// One day of an attendance period: hours worked, or a leave code
/// (AL, MC, ... = active leave type codes) with a comment.
class AttendanceDay {
  AttendanceDay({
    required this.date,
    this.hours = 0,
    this.leaveCode,
    this.remarks,
    this.isPublicHoliday = false,
    bool? isWeekend,
  }) : isWeekend = isWeekend ??
            (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday);

  /// Calendar date (local, no time).
  final DateTime date;
  double hours;
  String? leaveCode;
  String? remarks;
  bool isPublicHoliday;
  final bool isWeekend;

  bool get isLeave => leaveCode != null && leaveCode!.isNotEmpty;
  bool get isWorkingDay => !isWeekend && !isPublicHoliday;

  /// A leave day must have a comment before the period can be submitted
  /// (same rule as the API).
  bool get needsComment => isLeave && (remarks == null || remarks!.trim().isEmpty);

  AttendanceDay copy() => AttendanceDay(
        date: date,
        hours: hours,
        leaveCode: leaveCode,
        remarks: remarks,
        isPublicHoliday: isPublicHoliday,
        isWeekend: isWeekend,
      );

  factory AttendanceDay.fromJson(Map<String, dynamic> json) {
    final note = (json['note'] as String?)?.trim();
    return AttendanceDay(
      date: tryCalendarDate(json['date']) ?? DateTime.now(),
      hours: toDouble(json['hours']),
      leaveCode: note == null || note.isEmpty ? null : note,
      remarks: json['remarks'] as String?,
      isPublicHoliday: json['isPublicHoliday'] as bool? ?? false,
      isWeekend: json['isWeekend'] as bool?,
    );
  }

  /// Body of one entry in POST /api/selfservice/attendance-periods.
  Map<String, dynamic> toJson() => {
        'date': apiDate(date),
        'hours': isLeave ? 0 : hours,
        'note': isLeave ? leaveCode : null,
        'remarks': (remarks == null || remarks!.trim().isEmpty) ? null : remarks!.trim(),
        'isPublicHoliday': isPublicHoliday,
        'isWeekend': isWeekend,
      };
}

/// An attendance period (the web app uses half months: 1–15 and 16–end).
/// [id] is null for a period that has not been saved on the server yet.
class AttendancePeriod {
  AttendancePeriod({
    required this.start,
    required this.end,
    required this.days,
    this.id,
    this.status = 'Draft',
    this.rejectionReason,
    this.submittedAt,
    this.approvedAt,
  });

  int? id;
  final DateTime start;
  final DateTime end;
  String status;
  final String? rejectionReason;
  final DateTime? submittedAt;
  final DateTime? approvedAt;
  final List<AttendanceDay> days;

  bool get isSaved => id != null;

  /// Draft / Rejected (or not saved yet) can be changed; Submitted / Approved cannot.
  bool get isEditable => status == 'Draft' || status == 'Rejected';

  /// Status shown to the user: an unsaved period is "Not started".
  String get displayStatus => isSaved ? status : 'Not started';

  double get totalHours =>
      days.where((d) => !d.isLeave).fold(0.0, (sum, d) => sum + d.hours);
  int get leaveDays => days.where((d) => d.isLeave).length;
  int get workingDays => days.where((d) => d.isWorkingDay).length;

  /// Working days with neither hours nor leave filled in.
  int get emptyWorkingDays =>
      days.where((d) => d.isWorkingDay && !d.isLeave && d.hours == 0).length;

  String get label => start.month == end.month
      ? '${Fmt.shortDate(start)} – ${Fmt.date(end)}'
      : '${Fmt.date(start)} – ${Fmt.date(end)}';

  bool contains(DateTime day) => !day.isBefore(start) && !day.isAfter(end);

  factory AttendancePeriod.fromJson(Map<String, dynamic> json) => AttendancePeriod(
        id: json['id'] as int,
        start: tryCalendarDate(json['startDate']) ?? DateTime.now(),
        end: tryCalendarDate(json['endDate']) ?? DateTime.now(),
        status: json['status'] as String? ?? 'Draft',
        rejectionReason: json['rejectionReason'] as String?,
        submittedAt: tryParseApiDate(json['submittedAt']),
        approvedAt: tryParseApiDate(json['approvedAt']),
        days: ((json['days'] as List?) ?? const [])
            .map((d) => AttendanceDay.fromJson(d as Map<String, dynamic>))
            .toList(),
      );

  /// Body of POST /api/selfservice/attendance-periods.
  Map<String, dynamic> toJson() => {
        'id': id,
        'startDate': apiDate(start),
        'endDate': apiDate(end),
        'days': days.map((d) => d.toJson()).toList(),
      };
}

/// Builds the list of periods shown in the app, like the web page:
/// half-month cycles for the last [monthsBack] months up to now (not before
/// the join date), with saved server periods taking their place, plus any
/// other saved periods. Newest first.
List<AttendancePeriod> buildPeriodList({
  required List<AttendancePeriod> saved,
  required Set<DateTime> publicHolidays,
  required DateTime today,
  DateTime? joinDate,
  int monthsBack = 6,
}) {
  final result = <AttendancePeriod>[...saved];
  bool alreadySaved(DateTime start, DateTime end) =>
      saved.any((p) => isSameDay(p.start, start) && isSameDay(p.end, end));

  for (var offset = -monthsBack; offset <= 0; offset++) {
    final month = DateTime(today.year, today.month + offset, 1);
    final cycles = [
      (DateTime(month.year, month.month, 1), DateTime(month.year, month.month, 15)),
      (DateTime(month.year, month.month, 16), DateTime(month.year, month.month + 1, 0)),
    ];
    for (final (start, end) in cycles) {
      if (start.isAfter(today)) continue; // future cycle
      if (joinDate != null && end.isBefore(joinDate)) continue;
      // A whole-month saved period (older data) also covers this cycle.
      if (alreadySaved(start, end) ||
          saved.any((p) => p.contains(start) && p.contains(end))) {
        continue;
      }
      result.add(AttendancePeriod(
        start: start,
        end: end,
        days: [
          for (var d = start; !d.isAfter(end); d = DateTime(d.year, d.month, d.day + 1))
            AttendanceDay(
              date: d,
              isPublicHoliday: publicHolidays.any((h) => isSameDay(h, d)),
            ),
        ],
      ));
    }
  }
  result.sort((a, b) => b.start.compareTo(a.start));
  return result;
}
