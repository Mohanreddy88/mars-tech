import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import 'payroll_admin_models.dart';

/// Admin payroll API (/api/payroll, Admin role only).
class PayrollAdminRepository {
  PayrollAdminRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// Server message from a `{ message }` response, or [fallback].
  static String _msg(Response<dynamic> r, String fallback) =>
      (r.data is Map ? (r.data as Map)['message'] as String? : null) ?? fallback;

  Future<List<PayrollRecord>> forMonth(PayMonth m) => _call(() async {
        final r = await _dio.get<List<dynamic>>('payroll',
            queryParameters: {'month': m.month, 'year': m.year});
        return (r.data ?? const [])
            .map((e) => PayrollRecord.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<PayrollRecord> detail(int id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('payroll/$id');
        return PayrollRecord.fromJson(r.data!);
      });

  Future<PayrollEligibility> eligibility(int employeeId, PayMonth m) => _call(() async {
        final r = await _dio
            .get<Map<String, dynamic>>('payroll/eligibility/$employeeId/${m.month}/${m.year}');
        return PayrollEligibility.fromJson(r.data!);
      });

  Future<BulkGenerateResult> generate(List<int> employeeIds, PayMonth m) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('payroll/generate-bulk',
            data: {'employeeIds': employeeIds, 'month': m.month, 'year': m.year},
            options: Options(receiveTimeout: const Duration(minutes: 2)));
        return BulkGenerateResult.fromJson(r.data!);
      });

  Future<void> approve(int id, {String? remarks}) =>
      _call(() => _dio.post<void>('payroll/$id/approve', data: {'remarks': remarks}));

  Future<void> reject(int id, String reason) =>
      _call(() => _dio.post<void>('payroll/$id/reject', data: {'reason': reason}));

  Future<void> process(int id) => _call(() => _dio.post<void>('payroll/$id/process'));

  Future<void> delete(int id) => _call(() => _dio.delete<void>('payroll/$id'));

  Future<void> addAdjustment(int id, String type, String description, double amount) => _call(
      () => _dio.post<void>('payroll/$id/adjustment',
          data: {'adjustmentType': type, 'description': description, 'amount': amount}));

  Future<void> deleteAdjustment(int id, int adjustmentId) =>
      _call(() => _dio.delete<void>('payroll/$id/adjustment/$adjustmentId'));

  Future<List<int>> payslipPdf(int id) => _call(() async {
        final r = await _dio.get<List<int>>('payroll/pdf/$id',
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)));
        return r.data ?? const [];
      });

  Future<String> emailPayslip(int id) => _call(() async {
        final r = await _dio.post<dynamic>('payroll/email/$id');
        return _msg(r, 'Payslip emailed');
      });

  Future<String> emailPayslips(List<int> ids) => _call(() async {
        final r = await _dio.post<dynamic>('payroll/email-bulk', data: ids);
        return _msg(r, 'Payslips emailed');
      });

  /// Bank payment CSV for processed payroll; null (with the reason) when
  /// there is nothing processed for that month.
  Future<(List<int>?, String?)> bankExport(PayMonth m) => _call(() async {
        final r = await _dio.get<List<int>>('payroll/bank-export',
            queryParameters: {'month': m.month, 'year': m.year},
            options: Options(responseType: ResponseType.bytes));
        final type = r.headers.value('content-type') ?? '';
        if (type.contains('json')) {
          return (null, 'No processed payroll for ${m.label} to export.');
        }
        return (r.data, null);
      });

  Future<List<YearEndEmployee>> yearEnd(int year) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('payroll/year-end-summary/$year');
        return ((r.data?['employees'] as List?) ?? const [])
            .map((e) => YearEndEmployee.fromJson(e as Map<String, dynamic>))
            .toList();
      });

  Future<String> emailEaForm(int employeeId, int year) => _call(() async {
        final r = await _dio.post<dynamic>('payroll/email-ea-form/$employeeId/$year');
        return _msg(r, 'EA form emailed');
      });
}

final payrollAdminRepositoryProvider = Provider<PayrollAdminRepository>(
    (ref) => PayrollAdminRepository(ref.watch(dioProvider)));

final payrollMonthProvider = FutureProvider.autoDispose.family<List<PayrollRecord>, PayMonth>(
    (ref, m) => ref.watch(payrollAdminRepositoryProvider).forMonth(m));

final payrollDetailProvider = FutureProvider.autoDispose.family<PayrollRecord, int>(
    (ref, id) => ref.watch(payrollAdminRepositoryProvider).detail(id));

final yearEndProvider = FutureProvider.autoDispose.family<List<YearEndEmployee>, int>(
    (ref, year) => ref.watch(payrollAdminRepositoryProvider).yearEnd(year));
