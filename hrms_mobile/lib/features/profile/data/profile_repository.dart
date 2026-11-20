import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'profile_models.dart';

class ProfileRepository {
  ProfileRepository(this._dio);

  final Dio _dio;

  /// GET /api/selfservice/my-profile
  Future<EmployeeProfile> fetch() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('selfservice/my-profile');
      return EmployeeProfile.fromJson(res.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/selfservice/my-profile: the fields an employee may change.
  /// (Email is deliberately not editable here: the login is linked to the
  /// employee by email, so changing it is an HR task.)
  Future<void> update({String? phone, int? bankId, String? accountNumber}) async {
    try {
      await _dio.post<void>('selfservice/my-profile', data: {
        'phone': phone,
        'bankId': bankId,
        'accountNumber': accountNumber,
      });
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// GET /api/banks
  Future<List<Bank>> banks() async {
    try {
      final res = await _dio.get<List<dynamic>>('banks');
      return (res.data ?? const [])
          .map((e) => Bank.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final profileRepositoryProvider =
    Provider<ProfileRepository>((ref) => ProfileRepository(ref.watch(dioProvider)));

final profileProvider = FutureProvider.autoDispose<EmployeeProfile>(
    (ref) => ref.watch(profileRepositoryProvider).fetch());

final banksProvider = FutureProvider.autoDispose<List<Bank>>(
    (ref) => ref.watch(profileRepositoryProvider).banks());
