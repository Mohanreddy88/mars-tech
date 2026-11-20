import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import 'leave_models.dart';

class LeaveRepository {
  LeaveRepository(this._dio);

  final Dio _dio;

  /// GET /api/selfservice/my-leave-balance?year=
  Future<List<LeaveBalanceItem>> balances(int year) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'selfservice/my-leave-balance',
        queryParameters: {'year': year},
      );
      return ((res.data?['balances'] as List?) ?? const [])
          .map((e) => LeaveBalanceItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/selfservice/my-leave-requests (newest first)
  Future<List<LeaveRequestItem>> requests() async {
    try {
      final res =
          await _dio.get<List<dynamic>>('selfservice/my-leave-requests');
      return (res.data ?? const [])
          .map((e) => LeaveRequestItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/leavemanagement/leave-types/active
  Future<List<LeaveType>> activeTypes() async {
    try {
      final res =
          await _dio.get<List<dynamic>>('leavemanagement/leave-types/active');
      return (res.data ?? const [])
          .map((e) => LeaveType.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/leavemanagement/calculate-days: working days between two dates
  /// (weekends and public holidays excluded).
  Future<double> workingDays(DateTime start, DateTime end) async {
    try {
      final res = await _dio.get<Map<String, dynamic>>(
        'leavemanagement/calculate-days',
        queryParameters: {'startDate': apiDate(start), 'endDate': apiDate(end)},
      );
      return toDouble(res.data?['totalDays']);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/leavemanagement/requests. Returns the new request id.
  Future<int> apply({
    required int employeeId,
    required int leaveTypeId,
    required DateTime start,
    required DateTime end,
    String? reason,
  }) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'leavemanagement/requests',
        data: {
          'employeeId': employeeId,
          'leaveTypeId': leaveTypeId,
          'startDate': apiDate(start),
          'endDate': apiDate(end),
          'reason': reason,
        },
      );
      return res.data!['id'] as int;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/leave-attachments/{leaveRequestId} (multipart "file")
  Future<void> uploadAttachment(int leaveRequestId, LeaveAttachmentFile file) async {
    try {
      await _dio.post<void>(
        'leave-attachments/$leaveRequestId',
        data: FormData.fromMap({
          'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
        }),
        options: Options(sendTimeout: const Duration(seconds: 60)),
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/leave-attachments/{leaveRequestId}: the uploaded document.
  Future<List<int>> downloadAttachment(int leaveRequestId) async {
    try {
      final res = await _dio.get<List<int>>(
        'leave-attachments/$leaveRequestId',
        options: Options(responseType: ResponseType.bytes),
      );
      return res.data ?? const [];
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// PUT /api/leavemanagement/requests/{id}/cancel
  Future<void> cancel(int id, String reason) async {
    try {
      await _dio.put<void>(
        'leavemanagement/requests/$id/cancel',
        data: {'reason': reason},
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final leaveRepositoryProvider =
    Provider<LeaveRepository>((ref) => LeaveRepository(ref.watch(dioProvider)));

final leaveBalancesProvider = FutureProvider.autoDispose
    .family<List<LeaveBalanceItem>, int>(
        (ref, year) => ref.watch(leaveRepositoryProvider).balances(year));

final leaveRequestsProvider = FutureProvider.autoDispose<List<LeaveRequestItem>>(
    (ref) => ref.watch(leaveRepositoryProvider).requests());

final activeLeaveTypesProvider = FutureProvider.autoDispose<List<LeaveType>>(
    (ref) => ref.watch(leaveRepositoryProvider).activeTypes());
