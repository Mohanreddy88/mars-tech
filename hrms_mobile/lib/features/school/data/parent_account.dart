import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';

// The parent app's Account page (GET school/account) and the office's approval of pick-up people.

String? _s(dynamic v) => v is String && v.isNotEmpty ? v : null;
int _i(dynamic v) => (v as num?)?.toInt() ?? 0;
String? _day(dynamic v) => v is String && v.length >= 10 ? v.substring(0, 10) : null;
List<T> _list<T>(dynamic v, T Function(Map<String, dynamic>) f) =>
    (v as List<dynamic>? ?? const []).map((e) => f(e as Map<String, dynamic>)).toList();

/// Someone besides the parents who may collect a child; counts once the office approves.
class PickupPersonRec {
  const PickupPersonRec({required this.id, required this.studentId, required this.fullName, required this.relationship,
      this.phone, this.note, required this.status, this.addedByName, this.rejectReason, this.childName, this.className,
      this.createdAt});
  final int id;
  final int studentId;
  final String fullName;
  final String relationship;
  final String? phone;
  final String? note;
  /// Pending, Approved or Rejected.
  final String status;
  final String? addedByName;
  final String? rejectReason;
  /// Office list only.
  final String? childName;
  final String? className;
  final String? createdAt;

  bool get approved => status == 'Approved';
  bool get pending => status == 'Pending';
  bool get rejected => status == 'Rejected';

  factory PickupPersonRec.fromJson(Map<String, dynamic> j) => PickupPersonRec(
        id: _i(j['id']),
        studentId: _i(j['studentId']),
        fullName: j['fullName'] as String? ?? '',
        relationship: j['relationship'] as String? ?? '',
        phone: _s(j['phone']),
        note: _s(j['note']),
        status: j['status'] as String? ?? 'Pending',
        addedByName: _s(j['addedByName']),
        rejectReason: _s(j['rejectReason']),
        childName: _s(j['childName']),
        className: _s(j['className']),
        createdAt: _s(j['createdAt']),
      );
}

/// A parent or guardian of the child (may always collect them).
class ChildContact {
  const ChildContact({required this.id, required this.fullName, required this.relationship, this.phone, required this.isMe});
  final int id;
  final String fullName;
  final String relationship;
  final String? phone;
  final bool isMe;
}

class AccountChild {
  const AccountChild({required this.id, required this.fullName, this.dateOfBirth, this.gender, required this.sessionType,
      this.joinedOn, this.admissionNo, this.medicalNotes, this.emergencyContactName, this.emergencyContactPhone,
      this.className, this.classTeacher, required this.contacts, required this.pickupPeople, this.photoUpdatedAt});
  final int id;
  final String fullName;
  final String? dateOfBirth;
  final String? gender;
  final String sessionType;
  final String? joinedOn;
  final String? admissionNo;
  final String? medicalNotes;
  final String? emergencyContactName;
  final String? emergencyContactPhone;
  final String? className;
  final String? classTeacher;
  final List<ChildContact> contacts;
  final List<PickupPersonRec> pickupPeople;
  /// Profile photo version (null = none).
  final String? photoUpdatedAt;

  factory AccountChild.fromJson(Map<String, dynamic> j) => AccountChild(
        id: _i(j['id']),
        fullName: j['fullName'] as String? ?? '',
        dateOfBirth: _day(j['dateOfBirth']),
        gender: _s(j['gender']),
        sessionType: j['sessionType'] as String? ?? '',
        joinedOn: _day(j['joinedOn']),
        admissionNo: _s(j['admissionNo']),
        medicalNotes: _s(j['medicalNotes']),
        emergencyContactName: _s(j['emergencyContactName']),
        emergencyContactPhone: _s(j['emergencyContactPhone']),
        className: _s(j['className']),
        classTeacher: _s(j['classTeacher']),
        contacts: _list(j['contacts'], (c) => ChildContact(
              id: _i(c['id']),
              fullName: c['fullName'] as String? ?? '',
              relationship: c['relationship'] as String? ?? '',
              phone: _s(c['phone']),
              isMe: c['isMe'] == true,
            )),
        pickupPeople: _list(j['pickupPeople'], PickupPersonRec.fromJson),
        photoUpdatedAt: _s(j['photoUpdatedAt']),
      );
}

class ParentAccount {
  const ParentAccount({this.id = 0, required this.fullName, this.email, this.phone, required this.relationship, this.username, this.photoUpdatedAt,
      required this.children});
  final String fullName;
  final String? email;
  final String? phone;
  final String relationship;
  final String? username;
  final int id;
  /// Profile photo version (null = none).
  final String? photoUpdatedAt;
  final List<AccountChild> children;

  factory ParentAccount.fromJson(Map<String, dynamic> j) {
    final p = j['parent'] as Map<String, dynamic>? ?? const {};
    return ParentAccount(
      id: _i(p['id']),
      fullName: p['fullName'] as String? ?? '',
      email: _s(p['email']),
      phone: _s(p['phone']),
      relationship: p['relationship'] as String? ?? '',
      username: _s(p['username']),
      photoUpdatedAt: _s(p['photoUpdatedAt']),
      children: _list(j['children'], AccountChild.fromJson),
    );
  }
}

class ParentAccountRepository {
  ParentAccountRepository(this._dio);
  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<ParentAccount> account() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/account');
        return ParentAccount.fromJson(r.data!);
      });

  Future<void> setPhone(String phone) => _call(() => _dio.put<void>('school/account/phone', data: {'phone': phone}));

  Future<void> addPickupPerson({required List<int> studentIds, required String fullName, required String relationship,
          required String phone, String? note}) =>
      _call(() => _dio.post<void>('school/account/pickup-people', data: {
            'studentIds': studentIds,
            'fullName': fullName,
            'relationship': relationship,
            'phone': phone,
            'note': note,
          }));

  Future<void> removePickupPerson(int id) => _call(() => _dio.delete<void>('school/account/pickup-people/$id'));

  // ── Office ──
  Future<List<PickupPersonRec>> pickupPeople({String status = 'Pending'}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/pickup-people', queryParameters: {'status': status});
        return (r.data ?? const []).map((e) => PickupPersonRec.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> approve(int id) => _call(() => _dio.post<void>('school/pickup-people/$id/approve'));

  Future<void> reject(int id, String? reason) =>
      _call(() => _dio.post<void>('school/pickup-people/$id/reject', data: {'reason': reason}));
}

final parentAccountRepositoryProvider =
    Provider<ParentAccountRepository>((ref) => ParentAccountRepository(ref.watch(dioProvider)));

final parentAccountProvider = FutureProvider.autoDispose<ParentAccount>((ref) => ref.watch(parentAccountRepositoryProvider).account());

/// Pick-up people waiting for the office (admin tile badge and list).
final pendingPickupPeopleProvider =
    FutureProvider.autoDispose<List<PickupPersonRec>>((ref) => ref.watch(parentAccountRepositoryProvider).pickupPeople());
