/// Build-time configuration.
///
/// Override the API URL per build, e.g.
///   flutter run --dart-define=API_BASE_URL=https://uat.marshrms.com/api
///
/// The company is picked from the host name (as on the web), so a company app
/// build uses that company's address, e.g. https://<code>.marshrms.com/api.
///
/// Default points at the local .NET API (port 64559 from launchSettings.json)
/// as seen from the Android emulator, where 10.0.2.2 is the host machine.
class Env {
  Env._();

  static const String _rawApiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://10.0.2.2:64559/api',
  );

  /// Always ends with '/', so request paths are written without a leading
  /// slash (e.g. 'auth/login').
  static String get apiBaseUrl =>
      _rawApiBaseUrl.endsWith('/') ? _rawApiBaseUrl : '$_rawApiBaseUrl/';
}
