import 'dart:convert';

import '../../../../core/utils/formatters.dart';

/// One row of GET /api/audit.
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.username,
    required this.action,
    required this.entityType,
    required this.description,
    this.entityId,
    this.oldValues,
    this.newValues,
    this.ipAddress,
    this.createdAt,
  });

  /// Record types and actions written by the API (for the filters).
  static const entityTypes = [
    'Employee', 'Payroll', 'LeaveRequest', 'AttendancePeriod', 'User', 'CompanySettings', 'StatutoryRates',
  ];

  /// Readable name for a record type ("LeaveRequest" -> "Leave request").
  static String label(String type) => switch (type) {
        'LeaveRequest' => 'Leave request',
        'AttendancePeriod' => 'Attendance',
        'CompanySettings' => 'Company settings',
        'StatutoryRates' => 'Statutory rates',
        'User' => 'Login',
        _ => type,
      };
  static const actions = ['Created', 'Updated', 'Deleted', 'Approved', 'Rejected', 'Generated', 'Processed'];

  final int id;
  final String username;
  final String action;
  final String entityType;
  final String? entityId;
  final String description;
  final String? oldValues;
  final String? newValues;
  final String? ipAddress;
  final DateTime? createdAt;

  factory AuditEntry.fromJson(Map<String, dynamic> j) => AuditEntry(
        id: j['id'] as int,
        username: j['username'] as String? ?? '',
        action: j['action'] as String? ?? '',
        entityType: j['entityType'] as String? ?? '',
        entityId: j['entityId'] as String?,
        description: j['description'] as String? ?? '',
        oldValues: j['oldValues'] as String?,
        newValues: j['newValues'] as String?,
        ipAddress: j['ipAddress'] as String?,
        createdAt: tryParseApiDate(j['createdAt']),
      );

  /// Field-level changes between [oldValues] and [newValues] (JSON objects):
  /// (field, old, new) for every field whose value differs or exists on one side.
  /// Empty when the values are missing or not JSON objects.
  List<(String, String?, String?)> get changes {
    final before = _parse(oldValues);
    final after = _parse(newValues);
    if (before == null && after == null) return const [];
    final keys = {...?before?.keys, ...?after?.keys}.toList()..sort();
    return [
      for (final k in keys)
        if (_text(before?[k]) != _text(after?[k])) (k, _text(before?[k]), _text(after?[k]))
    ];
  }

  /// The recorded values as readable (field, value) rows: the new values,
  /// or the old ones for a deletion. Empty when not a JSON object.
  List<(String, String)> get values {
    final map = _parse(newValues) ?? _parse(oldValues);
    if (map == null) return const [];
    return [for (final e in map.entries) (e.key, _text(e.value) ?? '—')];
  }

  /// True when both sides were recorded and nothing differs (saved unchanged).
  bool get savedWithoutChanges =>
      _parse(oldValues) != null && _parse(newValues) != null && changes.isEmpty;

  static Map<String, dynamic>? _parse(String? json) {
    if (json == null || json.trim().isEmpty) return null;
    try {
      final v = jsonDecode(json);
      return v is Map<String, dynamic> ? v : null;
    } catch (_) {
      return null;
    }
  }

  static String? _text(Object? v) => v == null ? null : (v is String ? v : jsonEncode(v));
}

/// One page of results.
class AuditPage {
  const AuditPage({required this.total, required this.page, required this.totalPages, required this.entries});

  final int total;
  final int page;
  final int totalPages;
  final List<AuditEntry> entries;

  factory AuditPage.fromJson(Map<String, dynamic> j) => AuditPage(
        total: (j['total'] as num?)?.toInt() ?? 0,
        page: (j['page'] as num?)?.toInt() ?? 1,
        totalPages: (j['totalPages'] as num?)?.toInt() ?? 1,
        entries: ((j['logs'] as List?) ?? const [])
            .map((e) => AuditEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}

/// Filters for the audit list.
class AuditFilter {
  const AuditFilter({this.entityType, this.action, this.username, this.from, this.to});

  final String? entityType;
  final String? action;
  final String? username;
  final DateTime? from;
  final DateTime? to;

  bool get isEmpty =>
      entityType == null && action == null && (username ?? '').isEmpty && from == null && to == null;

  Map<String, dynamic> query(int page, int pageSize) => {
        'page': page,
        'pageSize': pageSize,
        if (entityType != null) 'entityType': entityType,
        if (action != null) 'action': action,
        if ((username ?? '').trim().isNotEmpty) 'username': username!.trim(),
        if (from != null) 'from': apiDate(from!),
        if (to != null) 'to': apiDate(to!),
      };

  @override
  bool operator ==(Object other) =>
      other is AuditFilter &&
      other.entityType == entityType &&
      other.action == action &&
      other.username == username &&
      other.from == from &&
      other.to == to;

  @override
  int get hashCode => Object.hash(entityType, action, username, from, to);
}
