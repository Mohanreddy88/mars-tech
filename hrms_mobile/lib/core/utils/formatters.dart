import 'package:intl/intl.dart';

class Fmt {
  Fmt._();

  static final _money = NumberFormat.currency(symbol: 'RM ', decimalDigits: 2);
  static final _date = DateFormat('dd MMM yyyy');
  static final _shortDate = DateFormat('dd MMM');
  static final _days = NumberFormat('0.#');

  static String money(num value) => _money.format(value);
  static String date(DateTime? value) =>
      value == null ? '-' : _date.format(value.toLocal());
  static String shortDate(DateTime? value) =>
      value == null ? '-' : _shortDate.format(value.toLocal());

  /// 1 -> "1 day", 2.5 -> "2.5 days"
  static String days(num value) =>
      '${_days.format(value)} ${value == 1 ? 'day' : 'days'}';
}

/// Parses a .NET DateTime string. Values without a zone marker are UTC.
DateTime parseApiDate(String value) {
  final hasZone = RegExp(r'(Z|[+-]\d{2}:?\d{2})$').hasMatch(value);
  return DateTime.parse(hasZone ? value : '${value}Z');
}

DateTime? tryParseApiDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  try {
    return parseApiDate(value);
  } catch (_) {
    return null;
  }
}

double toDouble(Object? value) => (value as num?)?.toDouble() ?? 0;

/// A calendar date (no time) as the API expects it: UTC midnight,
/// e.g. 2026-11-05 -> "2026-11-05T00:00:00Z" (same as the web app).
String apiDate(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}'
    '-${day.day.toString().padLeft(2, '0')}T00:00:00Z';

/// The calendar date of an API date-only value (stored as UTC midnight),
/// as a local date with no time, so it never shifts a day by timezone.
DateTime calendarDate(DateTime apiValue) {
  final utc = apiValue.toUtc();
  return DateTime(utc.year, utc.month, utc.day);
}

DateTime? tryCalendarDate(Object? value) {
  final parsed = tryParseApiDate(value);
  return parsed == null ? null : calendarDate(parsed);
}

bool isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
