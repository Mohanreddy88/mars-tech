import '../../../core/utils/formatters.dart';

/// GET /api/leavemanagement/leave-types/active
class LeaveType {
  const LeaveType({
    required this.id,
    required this.name,
    required this.code,
    this.description,
    this.isPaid = true,
  });

  final int id;
  final String name;

  /// e.g. "AL", "MC" (also used as the leave code on attendance days)
  final String code;
  final String? description;
  final bool isPaid;

  factory LeaveType.fromJson(Map<String, dynamic> json) => LeaveType(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        code: json['code'] as String? ?? '',
        description: json['description'] as String?,
        isPaid: json['isPaid'] as bool? ?? true,
      );
}

/// One row of GET /api/selfservice/my-leave-balance -> balances[]
class LeaveBalanceItem {
  const LeaveBalanceItem({
    required this.leaveTypeId,
    required this.name,
    required this.code,
    required this.totalDays,
    required this.usedDays,
    required this.balanceDays,
    required this.carryForwardDays,
  });

  final int leaveTypeId;
  final String name;
  final String code;
  final double totalDays;
  final double usedDays;
  final double balanceDays;
  final double carryForwardDays;

  double get usedFraction =>
      totalDays <= 0 ? 0 : (usedDays / totalDays).clamp(0, 1).toDouble();

  factory LeaveBalanceItem.fromJson(Map<String, dynamic> json) =>
      LeaveBalanceItem(
        leaveTypeId: json['leaveTypeId'] as int,
        name: json['leaveTypeName'] as String? ?? '',
        code: json['leaveTypeCode'] as String? ?? '',
        totalDays: toDouble(json['totalDays']),
        usedDays: toDouble(json['usedDays']),
        balanceDays: toDouble(json['balanceDays']),
        carryForwardDays: toDouble(json['carryForwardDays']),
      );
}

/// One row of GET /api/selfservice/my-leave-requests
class LeaveRequestItem {
  const LeaveRequestItem({
    required this.id,
    required this.leaveTypeName,
    required this.leaveTypeCode,
    required this.startDate,
    required this.endDate,
    required this.totalDays,
    required this.status,
    this.reason,
    this.requestedOn,
    this.approvedOn,
    this.approvalRemarks,
    this.cancelledOn,
    this.cancellationReason,
    this.attachmentName,
  });

  final int id;
  final String leaveTypeName;
  final String leaveTypeCode;
  final DateTime startDate;
  final DateTime endDate;
  final double totalDays;

  /// Pending, Approved, Rejected, Cancelled
  final String status;
  final String? reason;
  final DateTime? requestedOn;
  final DateTime? approvedOn;
  final String? approvalRemarks;
  final DateTime? cancelledOn;
  final String? cancellationReason;
  final String? attachmentName;

  /// Same rule as the web app: only requests not yet decided can be cancelled.
  bool get canCancel => status == 'Pending';

  factory LeaveRequestItem.fromJson(Map<String, dynamic> json) =>
      LeaveRequestItem(
        id: json['id'] as int,
        leaveTypeName: json['leaveTypeName'] as String? ?? '',
        leaveTypeCode: json['leaveTypeCode'] as String? ?? '',
        startDate: tryCalendarDate(json['startDate']) ?? DateTime.now(),
        endDate: tryCalendarDate(json['endDate']) ?? DateTime.now(),
        totalDays: toDouble(json['totalDays']),
        status: json['status'] as String? ?? '',
        reason: json['reason'] as String?,
        requestedOn: tryParseApiDate(json['requestedOn']),
        approvedOn: tryParseApiDate(json['approvedOn']),
        approvalRemarks: json['approvalRemarks'] as String?,
        cancelledOn: tryParseApiDate(json['cancelledOn']),
        cancellationReason: json['cancellationReason'] as String?,
        attachmentName: json['attachmentName'] as String?,
      );
}

/// A file picked to attach to a leave request (PDF / JPG / PNG, max 5 MB).
class LeaveAttachmentFile {
  const LeaveAttachmentFile({required this.name, required this.bytes});

  final String name;
  final List<int> bytes;

  static const maxBytes = 5 * 1024 * 1024;
  static const allowedExtensions = ['pdf', 'jpg', 'jpeg', 'png'];
}
