import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_controller.dart';
import '../storage/company_store.dart';
import '../storage/session_storage.dart';

/// Shared Dio instance for all API calls, pointed at the chosen company.
///
/// * Attaches the access token of the current session.
/// * Renews the token shortly before it expires, and after a 401 renews it
///   once and retries the request. If the session cannot be renewed the user
///   is signed out (AuthController.refresh).
final dioProvider = Provider<Dio>((ref) {
  final storage = ref.watch(sessionStorageProvider);

  final dio = Dio(
    BaseOptions(
      baseUrl: ref.watch(apiBaseUrlProvider),
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Accept': 'application/json'},
    ),
  );

  bool isAuthCall(RequestOptions o) => o.path.startsWith('auth/');
  AuthController auth() => ref.read(authControllerProvider.notifier);

  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        var session = storage.current;
        // Renew a token that is about to expire before using it.
        if (session != null && !isAuthCall(options) &&
            session.expiresWithin(const Duration(minutes: 1)) && session.canRefresh) {
          await auth().refresh();
          session = storage.current;
        }
        if (session != null) {
          options.headers['Authorization'] = 'Bearer ${session.token}';
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        final options = error.requestOptions;
        final retried = options.extra['retried'] == true;
        if (error.response?.statusCode == 401 && !isAuthCall(options) && !retried &&
            storage.current != null) {
          // The token was rejected: renew once and repeat the request.
          if (storage.current!.canRefresh && await auth().refresh()) {
            options.extra['retried'] = true;
            options.headers['Authorization'] = 'Bearer ${storage.current!.token}';
            try {
              return handler.resolve(await dio.fetch(options));
            } on DioException catch (e) {
              return handler.next(e);
            }
          }
          auth().onSessionExpired();
        }
        handler.next(error);
      },
    ),
  );

  return dio;
});
