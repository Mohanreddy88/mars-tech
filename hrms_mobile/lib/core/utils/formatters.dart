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
