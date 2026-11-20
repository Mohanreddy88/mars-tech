import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../features/auth/data/session.dart';

/// Persists the login session in the platform keystore (Android Keystore /
/// iOS Keychain) and keeps an in-memory copy for synchronous access.
class SessionStorage {
  SessionStorage([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  static const _key = 'hrms_session';

  final FlutterSecureStorage _storage;
  Session? _current;

  Session? get current => _current;

  /// Loads the saved session. Unreadable sessions, and ones that can no
  /// longer be used or renewed, are discarded.
  Future<void> load() async {
    try {
      final raw = await _storage.read(key: _key);
      if (raw == null) return;
      final session =
          Session.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      if (!session.isUsable) {
        await clear();
      } else {
        _current = session;
      }
    } catch (_) {
      await clear();
    }
  }

  Future<void> save(Session session) async {
    _current = session;
    await _storage.write(key: _key, value: jsonEncode(session.toJson()));
  }

  Future<void> clear() async {
    _current = null;
    try {
      await _storage.delete(key: _key);
    } catch (_) {
      // Nothing else to do; the in-memory session is already gone.
    }
  }
}

/// Overridden in main() with an instance that has already been loaded.
final sessionStorageProvider = Provider<SessionStorage>(
  (ref) => throw UnimplementedError('sessionStorageProvider must be overridden'),
);
