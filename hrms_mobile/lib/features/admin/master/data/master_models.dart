import '../../../../core/utils/formatters.dart';

/// A department or bank: the two simple "name + active" master lists.
class MasterItem {
  const MasterItem({
    required this.id,
    required this.name,
    required this.isActive,
    this.description,
    this.employeeCount,
  });

  final int id;
  final String name;
  final bool isActive;

  /// Departments only.
  final String? description;
  final int? employeeCount;

  factory MasterItem.fromJson(Map<String, dynamic> j) => MasterItem(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        isActive: j['isActive'] as bool? ?? true,
        description: j['description'] as String?,
        employeeCount: (j['employeeCount'] as num?)?.toInt(),
      );
}

/// GET /api/publicholidays
class Holiday {
  const Holiday({
    required this.id,
    required this.name,
    required this.date,
    required this.isNational,
    this.state,
    this.description,
  });

  final int id;
  final String name;
  final DateTime date;
  final bool isNational;
  final String? state;
  final String? description;

  factory Holiday.fromJson(Map<String, dynamic> j) => Holiday(
        id: j['id'] as int,
        name: j['name'] as String? ?? '',
        date: tryCalendarDate(j['date']) ?? DateTime.now(),
        isNational: j['isNational'] as bool? ?? true,
        state: j['state'] as String?,
        description: j['description'] as String?,
      );
}

/// GET /api/users
class UserAccount {
  const UserAccount({
    required this.id,
    required this.username,
    required this.email,
    required this.role,
    required this.isActive,
    this.employeeName,
    this.warning,
  });

  static const roles = ['Admin', 'Employee', 'User'];

  final int id;
  final String username;
  final String email;
  final String role;
  final bool isActive;
  final String? employeeName;

  /// e.g. "No employee record with this email"
  final String? warning;

  factory UserAccount.fromJson(Map<String, dynamic> j) => UserAccount(
        id: j['id'] as int,
        username: j['username'] as String? ?? '',
        email: j['email'] as String? ?? '',
        role: j['role'] as String? ?? '',
        isActive: j['isActive'] as bool? ?? true,
        employeeName: (j['employee'] as Map?)?['name'] as String?,
        warning: j['warning'] as String?,
      );
}

/// GET /api/users/available-employees: active employees without a login.
class AvailableEmployee {
  const AvailableEmployee({required this.id, required this.name, required this.email});

  final int id;
  final String name;
  final String email;

  factory AvailableEmployee.fromJson(Map<String, dynamic> j) => AvailableEmployee(
      id: j['id'] as int, name: j['name'] as String? ?? '', email: j['email'] as String? ?? '');
}

/// GET/PUT /api/companysettings
class CompanySettings {
  CompanySettings.fromJson(Map<String, dynamic> j)
      : legalName = j['legalName'] as String? ?? '',
        displayName = j['displayName'] as String? ?? '',
        registrationNo = j['registrationNo'] as String? ?? '',
        employerTaxNo = j['employerTaxNo'] as String? ?? '',
        taxBranch = j['taxBranch'] as String? ?? '',
        address = j['address'] as String? ?? '',
        phone = j['phone'] as String? ?? '',
        website = j['website'] as String? ?? '',
        hrOfficerName = j['hrOfficerName'] as String? ?? '',
        hrOfficerPosition = j['hrOfficerPosition'] as String? ?? '',
        brandColor = j['brandColor'] as String? ?? '#C62828';

  String legalName;
  String displayName;
  String registrationNo;
  String employerTaxNo;
  String taxBranch;
  String address;
  String phone;
  String website;
  String hrOfficerName;
  String hrOfficerPosition;

  /// "#RRGGBB"
  String brandColor;

  static bool isHexColor(String v) => RegExp(r'^#[0-9A-Fa-f]{6}$').hasMatch(v);

  String? validate() {
    if (legalName.trim().length < 2) return 'Enter the company\'s legal name.';
    if (!isHexColor(brandColor)) return 'Brand colour must look like #1E40AF.';
    return null;
  }

  Map<String, dynamic> toJson() => {
        'legalName': legalName.trim(),
        'displayName': displayName.trim(),
        'registrationNo': registrationNo,
        'employerTaxNo': employerTaxNo,
        'taxBranch': taxBranch,
        'address': address,
        'phone': phone,
        'website': website,
        'hrOfficerName': hrOfficerName,
        'hrOfficerPosition': hrOfficerPosition,
        'brandColor': brandColor.toUpperCase(),
      };
}

/// GET /api/statutoryrates (view only on mobile).
class RateSet {
  const RateSet({
    required this.id,
    required this.name,
    required this.effectiveFrom,
    required this.isCurrent,
    required this.payrollsUsing,
    required this.epfEmployee,
    required this.epfEmployer,
    required this.epfEmployerAbove,
    required this.epfThreshold,
    required this.eisEmployee,
    required this.eisEmployer,
    required this.eisCeiling,
    required this.taxRelief,
    required this.socsoBands,
    required this.taxBands,
    this.notes,
  });

  final int id;
  final String name;
  final DateTime effectiveFrom;
  final bool isCurrent;
  final int payrollsUsing;
  final double epfEmployee;
  final double epfEmployer;
  final double epfEmployerAbove;
  final double epfThreshold;
  final double eisEmployee;
  final double eisEmployer;
  final double eisCeiling;
  final double taxRelief;

  /// (wage up to — null = and above, employee RM, employer RM)
  final List<(double?, double, double)> socsoBands;

  /// (chargeable income up to — null = and above, rate %)
  final List<(double?, double)> taxBands;
  final String? notes;

  factory RateSet.fromJson(Map<String, dynamic> j) {
    List<Map<String, dynamic>> rows(String k) => ((j[k] as List?) ?? const []).cast<Map<String, dynamic>>();
    return RateSet(
      id: j['id'] as int,
      name: j['name'] as String? ?? '',
      effectiveFrom: tryCalendarDate(j['effectiveFrom']) ?? DateTime(2000),
      isCurrent: j['isCurrent'] as bool? ?? false,
      payrollsUsing: (j['payrollsUsing'] as num?)?.toInt() ?? 0,
      epfEmployee: toDouble(j['epfEmployeeRate']),
      epfEmployer: toDouble(j['epfEmployerRate']),
      epfEmployerAbove: toDouble(j['epfEmployerRateAboveThreshold']),
      epfThreshold: toDouble(j['epfEmployerThreshold']),
      eisEmployee: toDouble(j['eisEmployeeRate']),
      eisEmployer: toDouble(j['eisEmployerRate']),
      eisCeiling: toDouble(j['eisWageCeiling']),
      taxRelief: toDouble(j['taxPersonalRelief']),
      socsoBands: [
        for (final b in rows('socsoBands'))
          ((b['upTo'] as num?)?.toDouble(), toDouble(b['employee']), toDouble(b['employer']))
      ],
      taxBands: [for (final b in rows('taxBands')) ((b['upTo'] as num?)?.toDouble(), toDouble(b['rate']))],
      notes: j['notes'] as String?,
    );
  }
}
