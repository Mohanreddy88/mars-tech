import '../../../core/utils/formatters.dart';

/// Mirrors HrmsApi `LoginResponse`.
class Session {
  const Session({
    required this.token,
    required this.username,
    required this.role,
    required this.expiresAt,
    this.employeeId,
    this.mustChangePassword = false,
  });

  final String token;
  final String username;
  final String role;
  final DateTime expiresAt;
  final int? employeeId;
  final bool mustChangePassword;

  bool get isExpired => DateTime.now().toUtc().isAfter(expiresAt);
  bool get isAdmin => role.toLowerCase() == 'admin';

  factory Session.fromJson(Map<String, dynamic> json) => Session(
        token: json['token'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
        expiresAt: parseApiDate(json['expiresAt'] as String).toUtc(),
        employeeId: json['employeeId'] as int?,
        mustChangePassword: json['mustChangePassword'] as bool? ?? false,
      );

  Map<String, dynamic> toJson() => {
        'token': token,
        'username': username,
        'role': role,
        'expiresAt': expiresAt.toUtc().toIso8601String(),
        'employeeId': employeeId,
        'mustChangePassword': mustChangePassword,
      };

  Session copyWith({bool? mustChangePassword}) => Session(
        token: token,
        username: username,
        role: role,
        expiresAt: expiresAt,
        employeeId: employeeId,
        mustChangePassword: mustChangePassword ?? this.mustChangePassword,
      );
}
