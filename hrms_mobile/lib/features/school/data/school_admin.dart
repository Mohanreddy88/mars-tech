import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';

// Admin-only school setup (classes, children, parents) and fee setup (items, add-ons, settings,
// creating / sending / editing invoices). Same endpoints as the web pages.

String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
double _d(dynamic v) => (v as num?)?.toDouble() ?? 0;
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List<dynamic>? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

const sessionTypes = ['Half day', 'Full day', 'Daycare'];
const relationships = ['Mother', 'Father', 'Guardian'];

class ClassItem {
  const ClassItem({required this.id, required this.name, this.description, this.classTeacherId,
      this.classTeacherName, required this.sortOrder, required this.isActive, required this.studentCount});
  final int id;
  final String name;
  final String? description;
  final int? classTeacherId;
  final String? classTeacherName;
  final int sortOrder;
  final bool isActive;
  final int studentCount;

  factory ClassItem.fromJson(Map<String, dynamic> j) => ClassItem(
        id: _i(j['id']),
        name: j['name'] as String? ?? '',
        description: _s(j['description']),
        classTeacherId: (j['classTeacherId'] as num?)?.toInt(),
        classTeacherName: _s(j['classTeacherName']),
        sortOrder: _i(j['sortOrder']),
        isActive: j['isActive'] as bool? ?? true,
        studentCount: _i(j['studentCount']),
      );
}

class StudentParentRef {
  const StudentParentRef({required this.id, required this.fullName, required this.relationship, this.phone});
  final int id;
  final String fullName;
  final String relationship;
  final String? phone;
  factory StudentParentRef.fromJson(Map<String, dynamic> j) => StudentParentRef(
        id: _i(j['id']), fullName: j['fullName'] as String? ?? '', relationship: j['relationship'] as String? ?? '',
        phone: _s(j['phone']));
}

class ChildRecord {
  const ChildRecord({required this.id, required this.fullName, this.admissionNo, this.dateOfBirth, this.gender,
      this.classId, this.className, required this.sessionType, this.joinedOn, this.medicalNotes,
      this.emergencyContactName, this.emergencyContactPhone, this.notes, required this.isActive, required this.parents});
  final int id;
  final String fullName;
  final String? admissionNo;
  final String? dateOfBirth; // yyyy-MM-dd
  final String? gender;
  final int? classId;
  final String? className;
  final String sessionType;
  final String? joinedOn;
  final String? medicalNotes;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? notes;
  final bool isActive;
  final List<StudentParentRef> parents;

  static String? _day(dynamic v) => v is String && v.length >= 10 ? v.substring(0, 10) : null;

  factory ChildRecord.fromJson(Map<String, dynamic> j) => ChildRecord(
        id: _i(j['id']),
        fullName: j['fullName'] as String? ?? '',
        admissionNo: _s(j['admissionNo']),
        dateOfBirth: _day(j['dateOfBirth']),
        gender: _s(j['gender']),
        classId: (j['classId'] as num?)?.toInt(),
        className: _s(j['className']),
        sessionType: j['sessionType'] as String? ?? 'Full day',
        joinedOn: _day(j['joinedOn']),
        medicalNotes: _s(j['medicalNotes']),
        emergencyContactName: _s(j['emergencyContactName']),
        emergencyContactPhone: _s(j['emergencyContactPhone']),
        notes: _s(j['notes']),
        isActive: j['isActive'] as bool? ?? true,
        parents: _list(j['parents'], StudentParentRef.fromJson),
      );
}

class ParentRecord {
  const ParentRecord({required this.id, required this.fullName, this.email, this.phone, required this.relationship,
      required this.isActive, required this.hasLogin, this.username, required this.loginActive,
      required this.loginPending, required this.children});
  final int id;
  final String fullName;
  final String? email;
  final String? phone;
  final String relationship;
  final bool isActive;
  final bool hasLogin;
  final String? username;
  final bool loginActive;
  final bool loginPending;
  final List<({int id, String fullName, String? className})> children;

  factory ParentRecord.fromJson(Map<String, dynamic> j) => ParentRecord(
        id: _i(j['id']),
        fullName: j['fullName'] as String? ?? '',
        email: _s(j['email']),
        phone: _s(j['phone']),
        relationship: j['relationship'] as String? ?? 'Mother',
        isActive: j['isActive'] as bool? ?? true,
        hasLogin: j['hasLogin'] as bool? ?? false,
        username: _s(j['username']),
        loginActive: j['loginActive'] as bool? ?? false,
        loginPending: j['loginPending'] as bool? ?? false,
        children: _list(j['children'], (c) => (id: _i(c['id']), fullName: c['fullName'] as String? ?? '', className: _s(c['className']))),
      );
}

class FeeItem {
  const FeeItem({required this.id, required this.name, required this.kind, this.sessionType, required this.amount,
      required this.sortOrder, required this.isActive, required this.children});
  final int id;
  final String name;
  final String kind; // Session | AddOn
  final String? sessionType;
  final double amount;
  final int sortOrder;
  final bool isActive;
  final int children;
  bool get isSession => kind == 'Session';
  factory FeeItem.fromJson(Map<String, dynamic> j) => FeeItem(
        id: _i(j['id']), name: j['name'] as String? ?? '', kind: j['kind'] as String? ?? 'Session',
        sessionType: _s(j['sessionType']), amount: _d(j['amount']), sortOrder: _i(j['sortOrder']),
        isActive: j['isActive'] as bool? ?? true, children: _i(j['children']));
}

class FeeSettings {
  FeeSettings({required this.siblingDiscountPercent, required this.feeDueDay, this.paymentInstructions});
  double siblingDiscountPercent;
  int feeDueDay;
  String? paymentInstructions;
  factory FeeSettings.fromJson(Map<String, dynamic> j) => FeeSettings(
      siblingDiscountPercent: _d(j['siblingDiscountPercent']), feeDueDay: _i(j['feeDueDay']),
      paymentInstructions: _s(j['feePaymentInstructions']));
}

class AddOnChild {
  AddOnChild({required this.id, required this.fullName, this.className, required this.sessionType, required this.addOnIds});
  final int id;
  final String fullName;
  final String? className;
  final String sessionType;
  List<int> addOnIds;
}

class EmployeeRef {
  const EmployeeRef(this.id, this.name);
  final int id;
  final String name;
}

/// Thrown when the API says the child may already be on the list (same name and birthday).
class PossibleDuplicate implements Exception {
  PossibleDuplicate(this.message);
  final String message;
}

class SchoolAdminRepository {
  SchoolAdminRepository(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  // ── Classes ──
  Future<List<ClassItem>> classes() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/classes');
        return (r.data ?? const []).map((e) => ClassItem.fromJson(e as Map<String, dynamic>)).toList();
      });
  Future<void> saveClass(int? id, Map<String, dynamic> body) =>
      _call(() => id == null ? _dio.post<void>('school/classes', data: body) : _dio.put<void>('school/classes/$id', data: body));
  Future<void> deleteClass(int id) => _call(() => _dio.delete<void>('school/classes/$id'));

  Future<List<EmployeeRef>> teachers() => _call(() async {
        final r = await _dio.get<List<dynamic>>('employees');
        return (r.data ?? const [])
            .map((e) => e as Map<String, dynamic>)
            .where((e) => e['isActive'] != false)
            .map((e) => EmployeeRef(_i(e['id']), e['name'] as String? ?? ''))
            .toList()
          ..sort((a, b) => a.name.compareTo(b.name));
      });

  // ── Children ──
  Future<List<ChildRecord>> children({bool includeInactive = true}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/students', queryParameters: {'includeInactive': includeInactive});
        return (r.data ?? const []).map((e) => ChildRecord.fromJson(e as Map<String, dynamic>)).toList();
      });

  /// Saves a child. Throws [PossibleDuplicate] when the API asks "is this a different child?".
  Future<void> saveChild(int? id, Map<String, dynamic> body) async {
    try {
      id == null ? await _dio.post<void>('school/students', data: body) : await _dio.put<void>('school/students/$id', data: body);
    } on DioException catch (e) {
      final data = e.response?.data;
      if (data is Map && data['duplicate'] == true) throw PossibleDuplicate(data['message'] as String? ?? '');
      throw ApiException.from(e);
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> deleteChild(int id) => _call(() => _dio.delete<void>('school/students/$id'));

  // ── Parents ──
  Future<List<ParentRecord>> parents() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/parents');
        return (r.data ?? const []).map((e) => ParentRecord.fromJson(e as Map<String, dynamic>)).toList();
      });
  Future<String?> saveParent(int? id, Map<String, dynamic> body) => _call(() async {
        final r = id == null
            ? await _dio.post<Map<String, dynamic>>('school/parents', data: body)
            : await _dio.put<Map<String, dynamic>>('school/parents/$id', data: body);
        return r.data?['message'] as String?;
      });
  Future<String> inviteParent(int id) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/parents/$id/invite');
        return r.data?['message'] as String? ?? 'Sent';
      });
  Future<void> deleteParent(int id) => _call(() => _dio.delete<void>('school/parents/$id'));

  // ── Fee items, add-ons, settings ──
  Future<List<FeeItem>> feeItems() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/fees/items');
        return (r.data ?? const []).map((e) => FeeItem.fromJson(e as Map<String, dynamic>)).toList();
      });
  Future<void> saveFeeItem(int? id, Map<String, dynamic> body) => _call(
      () => id == null ? _dio.post<void>('school/fees/items', data: body) : _dio.put<void>('school/fees/items/$id', data: body));
  Future<void> deleteFeeItem(int id) => _call(() => _dio.delete<void>('school/fees/items/$id'));

  Future<(List<({int id, String name, double amount})>, List<AddOnChild>)> addOns() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/fees/addons');
        final items = _list(r.data?['items'], (i) => (id: _i(i['id']), name: i['name'] as String? ?? '', amount: _d(i['amount'])));
        final kids = _list(r.data?['children'], (c) => AddOnChild(
            id: _i(c['id']), fullName: c['fullName'] as String? ?? '', className: _s(c['className']),
            sessionType: c['sessionType'] as String? ?? '',
            addOnIds: (c['addOnIds'] as List<dynamic>? ?? const []).map((e) => _i(e)).toList()));
        return (items, kids);
      });
  Future<void> setAddOns(int studentId, List<int> ids) =>
      _call(() => _dio.put<void>('school/fees/addons/$studentId', data: {'feeItemIds': ids}));

  Future<FeeSettings> feeSettings() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/fees/settings');
        return FeeSettings.fromJson(r.data!);
      });
  Future<void> saveFeeSettings(FeeSettings s) => _call(() => _dio.put<void>('school/fees/settings', data: {
        'siblingDiscountPercent': s.siblingDiscountPercent,
        'feeDueDay': s.feeDueDay,
        'feePaymentInstructions': s.paymentInstructions,
      }));

  // ── Invoices ──
  Future<({int created, int alreadyHad, List<String> skipped})> generate(int year, int month) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/fees/invoices/generate', data: {'year': year, 'month': month});
        return (
          created: _i(r.data?['created']),
          alreadyHad: _i(r.data?['alreadyHad']),
          skipped: _list(r.data?['skipped'], (s) => '${s['fullName']} (${s['reason']})'),
        );
      });
  Future<({int sent, int emailed})> send(int year, int month, {List<int>? invoiceIds, int? classId, bool resend = false}) =>
      _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/fees/invoices/send',
            data: {'year': year, 'month': month, 'invoiceIds': invoiceIds, 'classId': classId, 'resend': resend});
        return (sent: _i(r.data?['sent']), emailed: _i(r.data?['emailed']));
      });
  Future<void> updateInvoice(int id, List<(String, double)> lines, String? dueDate, String? notes) =>
      _call(() => _dio.put<void>('school/fees/invoices/$id', data: {
            'lines': [for (final l in lines) {'description': l.$1, 'amount': l.$2}],
            'dueDate': dueDate,
            'notes': notes,
          }));
  Future<void> voidInvoice(int id, String reason) =>
      _call(() => _dio.post<void>('school/fees/invoices/$id/void', data: {'reason': reason}));
}

final schoolAdminProvider = Provider<SchoolAdminRepository>((ref) => SchoolAdminRepository(ref.watch(dioProvider)));

String money(num v) => Fmt.money(v);
