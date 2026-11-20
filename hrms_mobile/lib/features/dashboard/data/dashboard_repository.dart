import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'dashboard_models.dart';

class DashboardRepository {
  DashboardRepository(this._dio);

  final Dio _dio;

  /// GET /api/selfservice/dashboard
  Future<EmployeeDashboard> fetch() async {
    try {
      final res =
          await _dio.get<Map<String, dynamic>>('selfservice/dashboard');
      return EmployeeDashboard.fromJson(res.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final dashboardRepositoryProvider = Provider<DashboardRepository>(
    (ref) => DashboardRepository(ref.watch(dioProvider)));

final dashboardProvider = FutureProvider.autoDispose<EmployeeDashboard>(
    (ref) => ref.watch(dashboardRepositoryProvider).fetch());
