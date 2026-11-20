import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/network/api_client.dart';
import 'package:hrms_mobile/core/storage/company_store.dart';
import 'package:hrms_mobile/core/storage/session_storage.dart';
import 'package:hrms_mobile/features/auth/application/auth_controller.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';

/// Session storage that keeps everything in memory (no platform keystore in tests).
class _MemoryStorage extends SessionStorage {
  Session? _s;
  @override
  Session? get current => _s;
  @override
  Future<void> save(Session session) async => _s = session;
  @override
  Future<void> clear() async => _s = null;
}

/// A tiny fake HRMS API: tokens "A1"/"A2", refresh tokens "R1"/"R2".
class _FakeApi implements HttpClientAdapter {
  _FakeApi({this.refreshWorks = true});

  final bool refreshWorks;
  String validAccess = 'A2'; // the server only accepts the renewed token
  int refreshCalls = 0;
  final List<String> seen = [];

  ResponseBody _json(int status, Object body) => ResponseBody.fromString(
        jsonEncode(body),
        status,
        headers: {Headers.contentTypeHeader: [Headers.jsonContentType]},
      );

  @override
  Future<ResponseBody> fetch(RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    seen.add('${o.method} ${o.path} ${o.headers['Authorization'] ?? '-'}');
    if (o.path == 'auth/refresh') {
      refreshCalls++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
      if (!refreshWorks) return _json(401, {'message': 'Your session has expired.'});
      return _json(200, {
        'token': 'A2',
        'username': 'u',
        'role': 'Employee',
        'expiresAt': DateTime.now().toUtc().add(const Duration(hours: 8)).toIso8601String(),
        'refreshToken': 'R2',
        'refreshExpiresAt': DateTime.now().toUtc().add(const Duration(days: 30)).toIso8601String(),
      });
    }
    if (o.path == 'auth/logout') return _json(204, {});
    if (o.headers['Authorization'] != 'Bearer $validAccess') return _json(401, {'message': 'expired'});
    return _json(200, {'ok': true, 'path': o.path});
  }

  @override
  void close({bool force = false}) {}
}

Session _session() => Session(
      token: 'A1',
      username: 'u',
      role: 'Employee',
      // Still valid by the clock, but the server rejects it (e.g. key rotated).
      expiresAt: DateTime.now().toUtc().add(const Duration(hours: 1)),
      refreshToken: 'R1',
      refreshExpiresAt: DateTime.now().toUtc().add(const Duration(days: 30)),
    );

(ProviderContainer, Dio, _MemoryStorage) _setUp(_FakeApi api) {
  final storage = _MemoryStorage();
  storage.save(_session());
  final container = ProviderContainer(overrides: [
    sessionStorageProvider.overrideWithValue(storage),
    companyStoreProvider.overrideWithValue(CompanyStore()),
  ]);
  final dio = container.read(dioProvider)..httpClientAdapter = api;
  container.read(authControllerProvider); // build with the saved session
  return (container, dio, storage);
}

void main() {
  test('401 -> refresh once -> request retried with the new token', () async {
    final api = _FakeApi();
    final (container, dio, storage) = _setUp(api);

    final res = await dio.get<Map<String, dynamic>>('selfservice/dashboard');

    expect(res.data!['ok'], isTrue);
    expect(api.refreshCalls, 1);
    expect(storage.current!.token, 'A2');
    expect(storage.current!.refreshToken, 'R2'); // rotated
    expect(api.seen.last, 'GET selfservice/dashboard Bearer A2');
    expect(container.read(sessionExpiredProvider), isFalse);
    container.dispose();
  });

  test('refused refresh -> signed out with the "session expired" message', () async {
    final api = _FakeApi(refreshWorks: false);
    final (container, dio, storage) = _setUp(api);

    await expectLater(dio.get<void>('selfservice/dashboard'), throwsA(isA<DioException>()));

    expect(api.refreshCalls, 1);
    expect(storage.current, isNull);
    expect(container.read(authControllerProvider), isNull);
    expect(container.read(sessionExpiredProvider), isTrue);
    container.dispose();
  });

  test('requests failing together share a single refresh', () async {
    final api = _FakeApi();
    final (container, dio, _) = _setUp(api);

    final results = await Future.wait([
      dio.get<Map<String, dynamic>>('selfservice/dashboard'),
      dio.get<Map<String, dynamic>>('notification/unread-count'),
      dio.get<Map<String, dynamic>>('selfservice/my-payslips'),
    ]);

    expect(results.every((r) => r.data!['ok'] == true), isTrue);
    expect(api.refreshCalls, 1);
    container.dispose();
  });
}
