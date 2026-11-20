import '../../../core/utils/formatters.dart';

/// Mirrors HrmsApi `LoginResponse` (login and /auth/refresh).
class Session {
  const Session({
    required this.token,
    required this.username,
    required this.role,
    required this.expiresAt,
    this.employeeId,
    this.mustChangePassword = false,
    this.refreshToken,
    this.refreshExpiresAt,
  });

  /// Access token (JWT) sent with every request.
  final String token;
  final String username;
  final String role;

  /// When [token] stops working (UTC).
  final DateTime expiresAt;
  final int? employeeId;
  final bool mustChangePassword;

  /// Swapped for a new [token] at /auth/refresh, so the user stays signed in
  /// for weeks instead of hours. Null for servers without refresh support.
  final String? refreshToken;
  final DateTime? refreshExpiresAt;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);

  /// The access token expires within [margin] (refresh before using it).
  bool expiresWithin(Duration margin) => DateTime.now().toUtc().add(margin).isAfter(expiresAt);

  bool get canRefresh =>
      refreshToken != null &&
      refreshExpiresAt != null &&
      DateTime.now().toUtc().isBefore(refreshExpiresAt!);

  /// Still worth keeping: the access token works or can be renewed.
  bool get isUsable => !isExpired || canRefresh;

  /// When the user must sign in again at the latest.
  DateTime get endsAt => canRefresh ? refreshExpiresAt! : expiresAt;

  bool get isAdmin => role.toLowerCase() == 'admin';

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
        expiresAt: parseApiDate(json['expiresAt'] as String).toUtc(),
        employeeId: json['employeeId'] as int?,
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
        refreshToken: json['refreshToken'] as String?,
        refreshExpiresAt: tryParseApiDate(json['refreshExpiresAt'])?.toUtc(),
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'role': role,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'employeeId': employeeId,
        'mustChangePassword': mustChangePassword,
        'refreshToken': refreshToken,
        'refreshExpiresAt': refreshExpiresAt?.toUtc().toIso8601String(),
      };

  Session copyWith({bool? mustChangePassword}) => Session(
        token: token,
        username: username,
        role: role,
        expiresAt: expiresAt,
        employeeId: employeeId,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
        refreshToken: refreshToken,
        refreshExpiresAt: refreshExpiresAt,
      );
}
