import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/push/push_notifications.dart';
import '../../../core/storage/session_storage.dart';
import '../data/auth_repository.dart';
import '../data/session.dart';

/// Holds the signed-in session; `null` means signed out.
/// The router listens to this to decide which screens are reachable.
///
/// The access token lasts hours; the refresh token weeks. [refresh] renews
/// the access token (the API client calls it before expiry and after a 401),
/// so the user only signs in again when the refresh token ends — or when the
/// server ends the session (signed in elsewhere, password reset, disabled).
class AuthController extends Notifier<Session?> {
  Timer? _endTimer;
  Future<bool>? _refreshing;

  SessionStorage get _storage => ref.read(sessionStorageProvider);

  @override
  Session? build() {
    ref.onDispose(() => _endTimer?.cancel());
    final session = _storage.current;
    _scheduleEnd(session);
    return session;
  }

  Future<void> login(String username, String password) async {
    final session = await ref.read(authRepositoryProvider).login(username, password);
    await _setSession(session);
    ref.read(sessionExpiredProvider.notifier).state = false;
  }

  /// Renews the access token. Concurrent callers share one request.
  /// Returns false if the session could not be renewed; when the server
  /// says the session is over, the user is signed out.
  Future<bool> refresh() => _refreshing ??= _doRefresh().whenComplete(() => _refreshing = null);

  Future<bool> _doRefresh() async {
    final current = state;
    if (current == null || !current.canRefresh) return false;
    try {
      final renewed = await ref.read(authRepositoryProvider).refresh(current.refreshToken!);
      await _setSession(renewed);
      return true;
    } on ApiException catch (e) {
      // 400/401: the refresh token is no longer valid -> sign in again.
      // Anything else (offline, server error): keep the session, try later.
      if (e.statusCode == 401 || e.statusCode == 400) onSessionExpired();
      return false;
    }
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

  /// Signs out: tells the server (revokes the refresh token and this phone's
  /// push registration) without waiting on it, then forgets the session.
  Future<void> logout({String? deviceToken}) async {
    _endTimer?.cancel();
    // This phone stops getting the signed-out user's alerts
    deviceToken ??= ref.read(pushNotificationsProvider).token;
    if (state != null) {
      unawaited(ref.read(authRepositoryProvider).logout(deviceToken: deviceToken));
    }
    await _storage.clear();
    state = null;
  }

  /// Called when the session can no longer be used or renewed.
  void onSessionExpired() {
    if (state == null) return;
    ref.read(sessionExpiredProvider.notifier).state = true;
    _endTimer?.cancel();
    _storage.clear();
    state = null;
  }

  Future<void> _setSession(Session session) async {
    await _storage.save(session);
    _scheduleEnd(session);
    state = session;
  }

  /// Sign out when the session can no longer be renewed (refresh token end,
  /// or the access token end for servers without refresh tokens).
  void _scheduleEnd(Session? session) {
    _endTimer?.cancel();
    if (session == null) return;
    final remaining = session.endsAt.difference(DateTime.now().toUtc());
    _endTimer = Timer(remaining.isNegative ? Duration.zero : remaining, onSessionExpired);
  }
}

final authControllerProvider = NotifierProvider<AuthController, Session?>(AuthController.new);

/// True after an automatic sign-out, so the login screen can explain why.
final sessionExpiredProvider = StateProvider<bool>((ref) => false);
