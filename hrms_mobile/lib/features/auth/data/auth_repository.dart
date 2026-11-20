import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import 'session.dart';

class AuthRepository {
  AuthRepository(this._dio);

  final Dio _dio;

  /// POST /api/auth/login
  Future<Session> login(String username, String password) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'auth/login',
        data: {'username': username, 'password': password},
      );
      return Session.fromJson(res.data!);
    } catch (e) {
      final error = ApiException.from(e);
      if (error.statusCode == 401) {
        throw ApiException('Invalid username or password.', statusCode: 401);
      }
      throw error;
    }
  }

  /// POST /api/auth/forgot-password. Returns the server's message.
  Future<String> forgotPassword(String email) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'auth/forgot-password',
        data: {'email': email},
      );
      return res.data?['message'] as String? ??
          'If that email exists, a reset link has been sent.';
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/selfservice/change-password
  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    try {
      await _dio.post<void>(
        'selfservice/change-password',
        data: {
          'oldPassword': oldPassword,
          'newPassword': newPassword,
          'confirmPassword': confirmPassword,
        },
      );
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final authRepositoryProvider =
    Provider<AuthRepository>((ref) => AuthRepository(ref.watch(dioProvider)));
