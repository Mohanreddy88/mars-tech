import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/session_storage.dart';
import '../data/auth_repository.dart';
import '../data/session.dart';

/// Holds the signed-in session; `null` means signed out.
/// The router listens to this to decide which screens are reachable.
class AuthController extends Notifier<Session?> {
  Timer? _expiryTimer;

  SessionStorage get _storage => ref.read(sessionStorageProvider);

  @override
  Session? build() {
    ref.onDispose(() => _expiryTimer?.cancel());
    final session = _storage.current;
    _scheduleExpiry(session);
    return session;
  }

  Future<void> login(String username, String password) async {
    final session =
        await ref.read(authRepositoryProvider).login(username, password);
    await _storage.save(session);
    ref.read(sessionExpiredProvider.notifier).state = false;
    _scheduleExpiry(session);
    state = session;
  }

  Future<void> changePassword({
    required String oldPassword,
    required String newPassword,
    required String confirmPassword,
  }) async {
    await ref.read(authRepositoryProvider).changePassword(
          oldPassword: oldPassword,
          newPassword: newPassword,
          confirmPassword: confirmPassword,
        );
    final current = state;
    if (current != null && current.mustChangePassword) {
      final updated = current.copyWith(mustChangePassword: false);
      await _storage.save(updated);
      state = updated;
    }
  }

  Future<void> logout() async {
    _expiryTimer?.cancel();
    await _storage.clear();
    state = null;
  }

  /// Called when the API rejects the token or it reaches its expiry time.
  void onSessionExpired() {
    if (state == null) return;
    ref.read(sessionExpiredProvider.notifier).state = true;
    logout();
  }

  /// Without a refresh token the JWT cannot be renewed, so sign out
  /// when it expires rather than letting the next request fail.
  void _scheduleExpiry(Session? session) {
    _expiryTimer?.cancel();
    if (session == null) return;
    final remaining = session.expiresAt.difference(DateTime.now().toUtc());
    _expiryTimer = Timer(
      remaining.isNegative ? Duration.zero : remaining,
      onSessionExpired,
    );
  }
}

final authControllerProvider =
    NotifierProvider<AuthController, Session?>(AuthController.new);

/// True after an automatic sign-out, so the login screen can explain why.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);
