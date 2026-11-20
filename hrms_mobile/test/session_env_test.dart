import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/core/config/env.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';

Session _session({required Duration access, Duration? refresh}) {
  final now = DateTime.now().toUtc();
  return Session(
    token: 't',
    username: 'u',
    role: 'Employee',
    expiresAt: now.add(access),
    refreshToken: refresh == null ? null : 'r',
    refreshExpiresAt: refresh == null ? null : now.add(refresh),
  );
}

void main() {
  group('Session with refresh token', () {
    test('expired access token is still usable while the refresh token is valid', () {
      final s = _session(access: const Duration(minutes: -5), refresh: const Duration(days: 20));
      expect(s.isExpired, isTrue);
      expect(s.canRefresh, isTrue);
      expect(s.isUsable, isTrue);
      expect(s.endsAt, s.refreshExpiresAt);
    });

    test('without a refresh token the session ends with the access token', () {
      final s = _session(access: const Duration(hours: 1));
      expect(s.canRefresh, isFalse);
      expect(s.endsAt, s.expiresAt);
      expect(_session(access: const Duration(minutes: -1)).isUsable, isFalse);
    });

    test('expired refresh token: not usable once the access token expires', () {
      final s = _session(access: const Duration(minutes: -1), refresh: const Duration(days: -1));
      expect(s.canRefresh, isFalse);
      expect(s.isUsable, isFalse);
    });

    test('refresh fields survive saving and loading', () {
      final s = _session(access: const Duration(hours: 1), refresh: const Duration(days: 30));
      final back = Session.fromJson(s.toJson());
      expect(back.refreshToken, 'r');
      expect(back.refreshExpiresAt!.difference(s.refreshExpiresAt!).inSeconds.abs(), lessThan(1));
      expect(s.copyWith(mustChangePassword: true).refreshToken, 'r');
      expect(s.expiresWithin(const Duration(hours: 2)), isTrue);
      expect(s.expiresWithin(const Duration(minutes: 1)), isFalse);
    });
  });

  group('company address', () {
    test('code -> company sub-domain; empty -> main site', () {
      expect(Env.urlForCompany('acme'), 'https://acme.${Env.domain}/api/');
      expect(Env.urlForCompany(' ACME '), 'https://acme.${Env.domain}/api/');
      expect(Env.urlForCompany(''), 'https://${Env.domain}/api/');
      expect(Env.urlForCompany(null), 'https://${Env.domain}/api/');
    });

    test('codes follow the server rule; admin is reserved', () {
      expect(Env.companyCodeError(''), isNull);
      expect(Env.companyCodeError('acme'), isNull);
      expect(Env.companyCodeError('mars-tech2'), isNull);
      expect(Env.companyCodeError('admin'), isNotNull);
      expect(Env.companyCodeError('a'), isNotNull); // too short
      expect(Env.companyCodeError('-acme'), isNotNull);
      expect(Env.companyCodeError('acme.com'), isNotNull);
    });

    test('debug/test builds use a fixed local server, so no company is asked', () {
      expect(Env.fixedBaseUrl, isNotNull);
      expect(Env.asksForCompany, isFalse);
    });
  });
}
