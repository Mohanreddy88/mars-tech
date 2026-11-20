import 'package:flutter/foundation.dart';

/// Where the app finds the HRMS API.
///
/// * `--dart-define=API_BASE_URL=...` fixes one server (local development,
///   or a build made for a single company):
///     flutter run --dart-define=API_BASE_URL=https://uat.marshrms.com/api
/// * Debug builds without it use the local API as seen from the Android
///   emulator (10.0.2.2 = this PC, port 64559 from launchSettings.json).
/// * Release builds without it ask for the company on the login screen:
///   each company has its own address, `https://<code>.marshrms.com/api`
///   (an empty code = the main site, `https://marshrms.com/api`).
///   `--dart-define=API_DOMAIN=uat.marshrms.com` points a release build at UAT.
class Env {
  Env._();

  static const String _definedBaseUrl = String.fromEnvironment('API_BASE_URL');
  static const String domain = String.fromEnvironment('API_DOMAIN', defaultValue: 'marshrms.com');

  static const String _localDebugUrl = 'http://10.0.2.2:64559/api';

  /// The fixed server, or null when the user picks a company.
  static String? get fixedBaseUrl {
    if (_definedBaseUrl.isNotEmpty) return _withSlash(_definedBaseUrl);
    if (kDebugMode) return _withSlash(_localDebugUrl);
    return null;
  }

  static bool get asksForCompany => fixedBaseUrl == null;

  /// API address for a company code (null/empty = the main site).
  static String urlForCompany(String? code) {
    final c = (code ?? '').trim().toLowerCase();
    return c.isEmpty ? 'https://$domain/api/' : 'https://$c.$domain/api/';
  }

  /// Same rule as the server's company codes (PlatformController.SlugRule);
  /// "admin" is the Super Admin portal, not a company.
  static String? companyCodeError(String code) {
    final c = code.trim().toLowerCase();
    if (c.isEmpty) return null; // main site
    if (c == 'admin') return '"admin" is not a company code.';
    if (!RegExp(r'^[a-z][a-z0-9-]{0,28}[a-z0-9]$').hasMatch(c)) {
      return 'Use the code from your company\'s web address, e.g. "acme" for acme.$domain.';
    }
    return null;
  }

  /// Always ends with '/', so request paths are written without a leading
  /// slash (e.g. 'auth/login').
  static String _withSlash(String url) => url.endsWith('/') ? url : '$url/';
}
