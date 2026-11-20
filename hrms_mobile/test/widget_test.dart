import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hrms_mobile/app.dart';
import 'package:hrms_mobile/core/storage/session_storage.dart';
import 'package:hrms_mobile/core/storage/company_store.dart';
import 'package:hrms_mobile/features/auth/data/session.dart';

void main() {
  group('Session', () {
    test('parses LoginResponse JSON from HrmsApi', () {
      final session = Session.fromJson({
        'token': 'abc',
        'username': 'jdoe',
        'role': 'Employee',
        'expiresAt': '2099-01-01T00:00:00',
        'employeeId': 7,
        'mustChangePassword': true,
      });

      expect(session.username, 'jdoe');
      expect(session.employeeId, 7);
      expect(session.mustChangePassword, isTrue);
      expect(session.expiresAt.isUtc, isTrue);
      expect(session.isExpired, isFalse);
    });

    test('round-trips through toJson', () {
      final original = Session(
        token: 't',
        username: 'u',
        role: 'Admin',
        expiresAt: DateTime.utc(2099, 1, 1),
      );
      final copy = Session.fromJson(original.toJson());
      expect(copy.expiresAt, original.expiresAt);
      expect(copy.isAdmin, isTrue);
    });
  });

  testWidgets('signed-out user lands on the login screen', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sessionStorageProvider.overrideWithValue(SessionStorage()),
          companyStoreProvider.overrideWithValue(CompanyStore()),
        ],
        child: const HrmsApp(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Welcome back'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Sign in'), findsOneWidget);
  });
}
