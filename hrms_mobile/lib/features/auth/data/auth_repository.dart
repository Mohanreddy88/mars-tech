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

  /// POST /api/auth/refresh: a new session from the refresh token (the old
  /// refresh token stops working). Throws ApiException 401 when the session
  /// ended (expired, signed in elsewhere, password reset, login disabled).
  Future<Session> refresh(String refreshToken) async {
    try {
      final res = await _dio.post<Map<String, dynamic>>(
        'auth/refresh',
        data: {'refreshToken': refreshToken},
      );
      return Session.fromJson(res.data!);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  /// POST /api/auth/logout: revoke the refresh token and this phone's push
  /// registration. Best effort; signing out locally never waits on it.
  Future<void> logout({String? deviceToken}) async {
    try {
      await _dio.post<void>('auth/logout', data: {'deviceToken': deviceToken},
          options: Options(sendTimeout: const Duration(seconds: 5), receiveTimeout: const Duration(seconds: 5)));
    } catch (_) {
      // Offline or already signed out: the refresh token simply expires.
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
