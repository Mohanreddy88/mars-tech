import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../config/env.dart';
import '../storage/session_storage.dart';

/// Shared Dio instance for all API calls.
///
/// * Attaches the JWT from the current session.
/// * On a 401 from any authenticated call, signs the user out.
///   (When the backend gets a refresh-token endpoint, this is where the
///   refresh-and-retry logic goes.)
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(sessionStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: Env.apiBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        final session = storage.current;
        if (session != null) {
          options.headers['Authorization'] = 'Bearer ${session.token}';
        }
        handler.next(options);
      },
      onError: (error, handler) {
        final isAuthCall = error.requestOptions.path.startsWith('auth/');
        if (error.response?.statusCode == 401 &&
            !isAuthCall &&
            storage.current != null) {
          ref.read(authControllerProvider.notifier).onSessionExpired();
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
