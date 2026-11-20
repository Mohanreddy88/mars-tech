import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../config/env.dart';

/// The company the user signs in to (release builds), remembered between
/// app starts. Its code decides the API address: `<code>.marshrms.com`.
class CompanyStore {
  CompanyStore([FlutterSecureStorage? storage])
      : _storage = storage ??
            const FlutterSecureStorage(aOptions: AndroidOptions(encryptedSharedPreferences: true));

  static const _key = 'hrms_company';

  final FlutterSecureStorage _storage;
  String? _code;

  /// Saved company code ('' = main site), or null if none chosen yet.
  String? get code => _code;

  Future<void> load() async {
    try {
      _code = await _storage.read(key: _key);
    } catch (_) {
      _code = null;
    }
  }

  Future<void> save(String code) async {
    _code = code.trim().toLowerCase();
    await _storage.write(key: _key, value: _code);
  }
}

/// Overridden in main() with a loaded instance.
final companyStoreProvider =
    Provider<CompanyStore>((ref) => throw UnimplementedError('companyStoreProvider must be overridden'));

/// The chosen company code; changing it rebuilds the API client.
final companyCodeProvider = StateProvider<String?>((ref) => ref.read(companyStoreProvider).code);

/// The API address in use.
final apiBaseUrlProvider = Provider<String>(
    (ref) => Env.fixedBaseUrl ?? Env.urlForCompany(ref.watch(companyCodeProvider)));
