import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../leave/data/leave_models.dart';
import 'admin_models.dart';

/// Admin-only API calls (the server refuses them for employee logins).
class AdminRepository {
  AdminRepository(this._dio);

  final Dio _dio;

  Future<T> _get<T>(String path, T Function(dynamic data) parse,
      {Map<String, dynamic>? query}) async {
    try {
      final res = await _dio.get<dynamic>(path, queryParameters: query);
      return parse(res.data);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> _send(String method, String path, {Object? data}) async {
    try {
      await _dio.request<void>(path, data: data, options: Options(method: method));
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  static List<T> _list<T>(dynamic data, T Function(Map<String, dynamic>) f) =>
      ((data as List?) ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

  /// GET /api/dashboard/admin
  Future<AdminDashboard> dashboard() => _get('dashboard/admin',
      (d) => AdminDashboard.fromJson(d as Map<String, dynamic>));

  // ── Leave approvals ─────────────────────────────────────────────
  Future<List<PendingLeave>> pendingLeaves() =>
      _get('leavemanagement/requests/pending', (d) => _list(d, PendingLeave.fromJson));

  Future<void> approveLeave(int id, {String? remarks}) => _send(
      'PUT', 'leavemanagement/requests/$id/approve',
      data: {'status': 'Approved', 'approvalRemarks': remarks});

  Future<void> rejectLeave(int id, String reason) => _send(
      'PUT', 'leavemanagement/requests/$id/reject',
      data: {'status': 'Rejected', 'approvalRemarks': reason});

  // ── Attendance approvals ────────────────────────────────────────
  Future<List<PendingAttendance>> pendingAttendance() =>
      _get('attendancemanagement/pending', (d) => _list(d, PendingAttendance.fromJson));

  Future<AttendanceReview> attendanceDetails(int id) => _get(
      'attendancemanagement/$id/details',
      (d) => AttendanceReview.fromJson(d as Map<String, dynamic>));

  Future<void> approveAttendance(int id) =>
      _send('POST', 'attendancemanagement/$id/approve');

  Future<void> rejectAttendance(int id, String reason) => _send(
      'POST', 'attendancemanagement/$id/reject',
      data: {'rejectionReason': reason});

  Future<List<int>> attendancePdf(int id) async {
    try {
      final res = await _dio.get<List<int>>('attendancemanagement/$id/pdf',
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)));
      return res.data ?? const [];
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // ── Employees ───────────────────────────────────────────────────
  Future<List<EmployeeSummary>> employees() =>
      _get('employees', (d) => _list(d, EmployeeSummary.fromJson));

  Future<List<LeaveBalanceItem>> employeeLeaveBalances(int employeeId, int year) => _get(
      'leavemanagement/balances/employee/$employeeId',
      (d) => _list(d, LeaveBalanceItem.fromJson),
      query: {'year': year});

  Future<List<EmployeePayrollRow>> employeePayrolls(int employeeId) =>
      _get('payroll/employee/$employeeId', (d) => _list(d, EmployeePayrollRow.fromJson));
}

final adminRepositoryProvider =
    Provider<AdminRepository>((ref) => AdminRepository(ref.watch(dioProvider)));

final adminDashboardProvider = FutureProvider.autoDispose<AdminDashboard>(
    (ref) => ref.watch(adminRepositoryProvider).dashboard());

final pendingLeavesProvider = FutureProvider.autoDispose<List<PendingLeave>>(
    (ref) => ref.watch(adminRepositoryProvider).pendingLeaves());

final pendingAttendanceProvider = FutureProvider.autoDispose<List<PendingAttendance>>(
    (ref) => ref.watch(adminRepositoryProvider).pendingAttendance());

final attendanceReviewProvider = FutureProvider.autoDispose.family<AttendanceReview, int>(
    (ref, id) => ref.watch(adminRepositoryProvider).attendanceDetails(id));

final employeesProvider = FutureProvider.autoDispose<List<EmployeeSummary>>(
    (ref) => ref.watch(adminRepositoryProvider).employees());

final employeeLeaveBalancesProvider =
    FutureProvider.autoDispose.family<List<LeaveBalanceItem>, int>((ref, employeeId) =>
        ref.watch(adminRepositoryProvider).employeeLeaveBalances(employeeId, DateTime.now().year));

final employeePayrollsProvider =
    FutureProvider.autoDispose.family<List<EmployeePayrollRow>, int>(
        (ref, employeeId) => ref.watch(adminRepositoryProvider).employeePayrolls(employeeId));
