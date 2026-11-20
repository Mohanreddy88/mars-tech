import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';
import '../../leave/data/leave_repository.dart';
import '../../profile/data/profile_models.dart';
import '../../profile/data/profile_repository.dart';
import 'attendance_models.dart';

class AttendanceRepository {
  AttendanceRepository(this._dio);

  final Dio _dio;

  /// GET /api/selfservice/attendance-periods (with days)
  Future<List<AttendancePeriod>> savedPeriods() async {
    try {
      final res = await _dio.get<List<dynamic>>('selfservice/attendance-periods');
      return (res.data ?? const [])
          .map((e) => AttendancePeriod.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/publicholidays?year= -> calendar dates
  Future<Set<DateTime>> publicHolidays(int year) async {
    try {
      final res = await _dio
          .get<List<dynamic>>('publicholidays', queryParameters: {'year': year});
      return {
        for (final h in res.data ?? const [])
          if (tryCalendarDate((h as Map<String, dynamic>)['date']) case final d?) d
      };
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/selfservice/attendance-periods (create or update a draft).
  /// Returns the period id.
  Future<int> save(AttendancePeriod period) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'selfservice/attendance-periods',
        data: period.toJson(),
      );
      return res.data!['id'] as int;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/selfservice/attendance-periods/{id}/submit
  Future<void> submit(int id) async {
    try {
      await _dio.post<void>('selfservice/attendance-periods/$id/submit');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/selfservice/attendance-periods/{id}/pdf
  Future<List<int>> pdf(int id) async {
    try {
      final res = await _dio.get<List<int>>(
        'selfservice/attendance-periods/$id/pdf',
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 60),
        ),
      );
      return res.data ?? const [];
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final attendanceRepositoryProvider = Provider<AttendanceRepository>(
    (ref) => AttendanceRepository(ref.watch(dioProvider)));

/// All periods shown in the Attendance tab, newest first.
final attendancePeriodsProvider =
    FutureProvider.autoDispose<List<AttendancePeriod>>((ref) async {
  final repo = ref.watch(attendanceRepositoryProvider);
  final today = DateTime.now();
  final List<AttendancePeriod> saved;
  final EmployeeProfile profile;
  final Set<DateTime> holidaysThisYear, holidaysLastYear;
  try {
    (saved, profile, holidaysThisYear, holidaysLastYear) = await (
      repo.savedPeriods(),
      ref.watch(profileRepositoryProvider).fetch(),
      // The list reaches 6 months back, so it can span two years.
      repo.publicHolidays(today.year),
      repo.publicHolidays(today.year - 1),
    ).wait;
  } on ParallelWaitError catch (e) {
    // Surface the first real API error (e.g. "Employee profile not found").
    final errors = e.errors as (AsyncError?, AsyncError?, AsyncError?, AsyncError?);
    throw [errors.$1, errors.$2, errors.$3, errors.$4].firstWhere((x) => x != null)!.error;
  }
  return buildPeriodList(
    saved: saved,
    publicHolidays: {...holidaysThisYear, ...holidaysLastYear},
    today: DateTime(today.year, today.month, today.day),
    joinDate: profile.joinDate,
  );
});

/// Leave codes allowed on attendance days (active leave type codes).
final leaveCodesProvider = FutureProvider.autoDispose<List<String>>((ref) async {
  final types = await ref.watch(leaveRepositoryProvider).activeTypes();
  return types.map((t) => t.code.toUpperCase()).where((c) => c.isNotEmpty).toList();
});
