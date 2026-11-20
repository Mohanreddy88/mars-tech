import '../../../core/utils/formatters.dart';

/// GET /api/selfservice/my-profile
class EmployeeProfile {
  const EmployeeProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.phoneCountryCode,
    this.idType,
    this.icPassport,
    this.dateOfBirth,
    this.taxNumber,
    this.departmentName,
    this.designation,
    this.joinDate,
    this.bankId,
    this.bankName,
    this.accountNumber,
  });

  final int id;
  final String name;
  final String email;
  final String? phone;
  final String? phoneCountryCode;
  final String? idType;
  final String? icPassport;
  final DateTime? dateOfBirth;
  final String? taxNumber;
  final String? departmentName;
  final String? designation;
  final DateTime? joinDate;
  final int? bankId;
  final String? bankName;
  final String? accountNumber;

  String get phoneDisplay {
    if (phone == null || phone!.isEmpty) return '';
    final code = phoneCountryCode ?? '';
    return code.isEmpty ? phone! : '$code $phone';
  }

  factory EmployeeProfile.fromJson(Map<String, dynamic> json) => EmployeeProfile(
        id: json['id'] as int,
        name: json['name'] as String? ?? '',
        email: json['email'] as String? ?? '',
        phone: json['phone'] as String?,
        phoneCountryCode: json['phoneCountryCode'] as String?,
        idType: json['idType'] as String?,
        icPassport: json['icPassport'] as String?,
        dateOfBirth: tryCalendarDate(json['dateOfBirth']),
        taxNumber: json['taxNumber'] as String?,
        departmentName: json['departmentName'] as String?,
        designation: json['designation'] as String?,
        joinDate: tryCalendarDate(json['joinDate']),
        bankId: json['bankId'] as int?,
        bankName: json['bankName'] as String?,
        accountNumber: json['accountNumber'] as String?,
      );
}

/// GET /api/banks (active banks)
class Bank {
  const Bank({required this.id, required this.name});

  final int id;
  final String name;

  factory Bank.fromJson(Map<String, dynamic> json) =>
      Bank(id: json['id'] as int, name: json['name'] as String? ?? '');
}
