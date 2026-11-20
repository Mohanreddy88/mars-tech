import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import '../../payroll/data/payroll_admin_models.dart';
import 'reports_models.dart';

/// Reports and analytics (Admin only on the API).
class ReportsRepository {
  ReportsRepository(this._dio);

  final Dio _dio;

  Future<T> _get<T>(String path, T Function(dynamic) parse, [Map<String, dynamic>? query]) async {
    try {
      final r = await _dio.get<dynamic>(path, queryParameters: query);
      return parse(r.data);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  static Map<String, dynamic> _map(dynamic d) => (d as Map).cast<String, dynamic>();
  static List<Map<String, dynamic>> _rows(dynamic d) => ((d as List?) ?? const []).cast<Map<String, dynamic>>();

  Future<PayrollReport> payroll(PayMonth m) => _get('reports/department-payroll-summary',
      (d) => PayrollReport.fromJson(_map(d)), {'year': m.year, 'month': m.month});

  Future<AttendanceReport> attendance(DateTime from, DateTime to) => _get(
      'reports/attendance-by-date-range',
      (d) => AttendanceReport.fromJson(_map(d)),
      {'startDate': apiDate(from), 'endDate': apiDate(to)});

  Future<EmployeeDirectory> directory({required bool includeInactive}) => _get(
      'reports/employee-directory',
      (d) => EmployeeDirectory.fromJson(_map(d)),
      {'includeInactive': includeInactive});

  Future<MonthlySummary> monthly(PayMonth m) => _get('reports/monthly-summary',
      (d) => MonthlySummary.fromJson(_map(d)), {'year': m.year, 'month': m.month});

  // ── Analytics ───────────────────────────────────────────────────
  Future<List<(String, int)>> headcountByDepartment() => _get(
      'analytics/employee-count-by-department',
      (d) => [
            for (final r in _rows(d))
              (r['departmentName'] as String? ?? 'Unassigned', (r['employeeCount'] as num?)?.toInt() ?? 0)
          ]);

  Future<List<PayrollTrendPoint>> payrollTrend(int months) => _get('analytics/payroll-trends',
      (d) => _rows(d).map(PayrollTrendPoint.fromJson).toList(), {'months': months});

  Future<SalaryDistribution> salaryDistribution() =>
      _get('analytics/salary-distribution', (d) => SalaryDistribution.fromJson(_map(d)));

  Future<List<DepartmentAttendanceRate>> attendanceRates(int year) => _get(
      'analytics/attendance-statistics',
      (d) => _rows(_map(d)['byDepartment']).map(DepartmentAttendanceRate.fromJson).toList(),
      {'year': year});

  // ── Excel exports (shared through the share sheet) ──────────────
  Future<(List<int>, String)> _excel(String path, String fallbackName, [Map<String, dynamic>? query]) async {
    try {
      final r = await _dio.get<List<int>>(path,
          queryParameters: query,
          options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 90)));
      final cd = r.headers.value('content-disposition');
      final name = cd == null ? null : RegExp(r'filename="?([^";]+)"?').firstMatch(cd)?.group(1);
      return (r.data ?? const <int>[], name ?? fallbackName);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<(List<int>, String)> payrollExcel(PayMonth m) => _excel('reports/export/payroll-excel',
      'Payroll_${m.month}_${m.year}.xlsx', {'year': m.year, 'month': m.month});

  Future<(List<int>, String)> employeesExcel() =>
      _excel('reports/export/employees-excel', 'Employees.xlsx');

  Future<(List<int>, String)> attendanceExcel(DateTime from, DateTime to) => _excel(
      'reports/export/attendance-excel',
      'Attendance.xlsx',
      {'startDate': apiDate(from), 'endDate': apiDate(to)});
}

final reportsRepositoryProvider =
    Provider<ReportsRepository>((ref) => ReportsRepository(ref.watch(dioProvider)));
