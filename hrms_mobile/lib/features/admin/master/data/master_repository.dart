import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_client.dart';
import '../../../../core/network/api_exception.dart';
import '../../../../core/utils/formatters.dart';
import 'master_models.dart';

/// The two simple master lists.
enum MasterKind {
  departments('departments', 'Department'),
  banks('banks', 'Bank');

  const MasterKind(this.path, this.singular);

  final String path;
  final String singular;
}

/// Master data API (writes are Admin only on the server).
class MasterRepository {
  MasterRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  static List<Map<String, dynamic>> _rows(dynamic d) => ((d as List?) ?? const []).cast<Map<String, dynamic>>();

  // ── Departments / banks ─────────────────────────────────────────
  /// Includes inactive ones (".../all").
  Future<List<MasterItem>> items(MasterKind k) => _call(() async {
        final r = await _dio.get<dynamic>('${k.path}/all');
        return _rows(r.data).map(MasterItem.fromJson).toList();
      });

  Future<void> saveItem(MasterKind k, {int? id, required String name, String? description, required bool isActive}) {
    final body = {
      'name': name.trim(),
      'isActive': isActive,
      if (k == MasterKind.departments) 'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
    };
    return _call(() => id == null
        ? _dio.post<void>(k.path, data: body)
        : _dio.put<void>('${k.path}/$id', data: body));
  }

  Future<void> deleteItem(MasterKind k, int id) => _call(() => _dio.delete<void>('${k.path}/$id'));

  // ── Public holidays ─────────────────────────────────────────────
  Future<List<Holiday>> holidays(int year) => _call(() async {
        final r = await _dio.get<dynamic>('publicholidays', queryParameters: {'year': year});
        return _rows(r.data).map(Holiday.fromJson).toList();
      });

  Future<void> saveHoliday({int? id, required String name, required DateTime date, required bool isNational,
      String? state, String? description}) {
    final body = {
      'name': name.trim(),
      'date': apiDate(date),
      'isNational': isNational,
      'state': isNational || (state ?? '').trim().isEmpty ? null : state!.trim(),
      'description': (description ?? '').trim().isEmpty ? null : description!.trim(),
    };
    return _call(() => id == null
        ? _dio.post<void>('publicholidays', data: body)
        : _dio.put<void>('publicholidays/$id', data: body));
  }

  Future<void> deleteHoliday(int id) => _call(() => _dio.delete<void>('publicholidays/$id'));

  // ── Users (logins) ──────────────────────────────────────────────
  Future<List<UserAccount>> users() => _call(() async {
        final r = await _dio.get<dynamic>('users');
        return _rows(r.data).map(UserAccount.fromJson).toList();
      });

  Future<List<AvailableEmployee>> availableEmployees() => _call(() async {
        final r = await _dio.get<dynamic>('users/available-employees');
        return _rows(r.data).map(AvailableEmployee.fromJson).toList();
      });

  /// Employee logins are linked to an employee (username/email from it);
  /// Admin / User logins need a username and email. A set-password email is sent.
  Future<void> createUser({required String role, int? employeeId, String? username, String? email}) =>
      _call(() => _dio.post<void>('users', data: {
            'role': role,
            'employeeId': employeeId,
            'username': (username ?? '').trim().isEmpty ? null : username!.trim(),
            'email': (email ?? '').trim().isEmpty ? null : email!.trim(),
          }));

  /// [password] empty = keep the current one (a new one must be changed at next login).
  Future<void> updateUser(UserAccount u,
          {required String username, required String email, required String role, required bool isActive, String? password}) =>
      _call(() => _dio.put<void>('users/${u.id}', data: {
            'username': username.trim(),
            'email': email.trim(),
            'role': role,
            'isActive': isActive,
            'password': (password ?? '').isEmpty ? null : password,
          }));

  Future<void> sendWelcome(int userId) => _call(() => _dio.post<void>('users/$userId/send-welcome'));

  Future<void> deleteUser(int userId) => _call(() => _dio.delete<void>('users/$userId'));

  // ── Company settings ────────────────────────────────────────────
  Future<CompanySettings> companySettings() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('company-settings');
        return CompanySettings.fromJson(r.data!);
      });

  Future<void> saveCompanySettings(CompanySettings s) =>
      _call(() => _dio.put<void>('company-settings', data: s.toJson()));

  // ── Statutory rates (view) ──────────────────────────────────────
  Future<List<RateSet>> rateSets() => _call(() async {
        final r = await _dio.get<dynamic>('statutoryrates');
        return _rows(r.data).map(RateSet.fromJson).toList();
      });
}

final masterRepositoryProvider = Provider<MasterRepository>((ref) => MasterRepository(ref.watch(dioProvider)));

final masterItemsProvider = FutureProvider.autoDispose.family<List<MasterItem>, MasterKind>(
    (ref, k) => ref.watch(masterRepositoryProvider).items(k));
final holidaysProvider = FutureProvider.autoDispose.family<List<Holiday>, int>(
    (ref, year) => ref.watch(masterRepositoryProvider).holidays(year));
final usersProvider =
    FutureProvider.autoDispose<List<UserAccount>>((ref) => ref.watch(masterRepositoryProvider).users());
final companySettingsProvider = FutureProvider.autoDispose<CompanySettings>(
    (ref) => ref.watch(masterRepositoryProvider).companySettings());
final rateSetsProvider =
    FutureProvider.autoDispose<List<RateSet>>((ref) => ref.watch(masterRepositoryProvider).rateSets());
