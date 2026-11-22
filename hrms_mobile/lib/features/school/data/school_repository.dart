import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../auth/application/auth_controller.dart';
import 'school_models.dart';

/// A photo or PDF picked on the phone, to send.
class PickedFile {
  const PickedFile({required this.name, required this.bytes});
  final String name;
  final Uint8List bytes;
  static const maxBytes = 5 * 1024 * 1024;
}

/// The HrmsApi school endpoints (api/school/...).
class SchoolRepository {
  SchoolRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() f) async {
    try {
      return await f();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<Uint8List> _bytes(String path) => _call(() async {
        final r = await _dio.get<List<int>>(path,
            options: Options(responseType: ResponseType.bytes, receiveTimeout: const Duration(seconds: 60)));
        return Uint8List.fromList(r.data ?? const []);
      });

  // ── Me ──

  Future<SchoolMe> me() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/me');
        return SchoolMe.fromJson(r.data!);
      });

  /// Staff home counters (checked in today, absent, payment claims to confirm).
  Future<StaffToday> staffToday() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/today');
        return StaffToday.fromJson(r.data!);
      });

  /// Admin: switch the school features on or off for this company.
  Future<void> setEnabled(bool enabled) =>
      _call(() => _dio.put<void>('school/settings', data: {'enabled': enabled}));

  Future<List<StudentInfo>> students({int? classId}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/students',
            queryParameters: {if (classId != null) 'classId': classId});
        return (r.data ?? const []).map((e) => StudentInfo.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<List<SchoolClassRef>> classes() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/classes');
        return (r.data ?? const [])
            .map((e) => e as Map<String, dynamic>)
            .where((e) => e['isActive'] != false)
            .map(SchoolClassRef.fromJson)
            .toList();
      });

  // ── Announcements ──

  Future<List<Announcement>> announcements() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/announcements');
        return (r.data ?? const []).map((e) => Announcement.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> markAnnouncementRead(int id) => _call(() => _dio.post<void>('school/announcements/$id/read'));

  Future<Uint8List> announcementAttachment(int id) => _bytes('school/announcements/$id/attachment');

  Future<int> postAnnouncement({required String title, required String body, int? classId, PickedFile? file}) =>
      _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/announcements',
            data: FormData.fromMap({
              'title': title,
              'body': body,
              if (classId != null) 'classId': classId,
              if (file != null) 'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
            }));
        return (r.data?['sentTo'] as num?)?.toInt() ?? 0;
      });

  Future<void> deleteAnnouncement(int id) => _call(() => _dio.delete<void>('school/announcements/$id'));

  Future<int> unreadAnnouncements() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/announcements/unread-count');
        return (r.data?['count'] as num?)?.toInt() ?? 0;
      });

  // ── Messages ──

  Future<List<ConversationSummary>> conversations() => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/conversations');
        return (r.data ?? const []).map((e) => ConversationSummary.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<int> unreadMessages() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/messages/unread-count');
        return (r.data?['count'] as num?)?.toInt() ?? 0;
      });

  Future<int> openConversation(int studentId, String kind) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/conversations/open',
            data: {'studentId': studentId, 'kind': kind});
        return (r.data!['id'] as num).toInt();
      });

  /// Starts a new conversation about a child with a subject and the first message. Returns its id.
  Future<int> startConversation({
    required int studentId,
    required String kind,
    required String subject,
    required String body,
    PickedFile? file,
  }) =>
      _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/conversations',
            data: FormData.fromMap({
              'studentId': studentId,
              'kind': kind,
              'subject': subject,
              'body': body,
              if (file != null) 'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
            }),
            options: Options(sendTimeout: const Duration(seconds: 60)));
        return (r.data!['id'] as num).toInt();
      });

  /// Staff close a conversation when it's done; anyone in it can reopen it. Returns the new status.
  Future<String> setConversationClosed(int conversationId, bool close) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>(
            'school/conversations/$conversationId/${close ? 'close' : 'reopen'}');
        return r.data?['status'] as String? ?? (close ? 'Closed' : 'Open');
      });

  Future<MessagePage> messages(int conversationId, {int? before}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/conversations/$conversationId/messages',
            queryParameters: {if (before != null) 'before': before});
        return MessagePage.fromJson(r.data!);
      });

  Future<ChatMessage> send(int conversationId, String body, PickedFile? file) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/conversations/$conversationId/messages',
            data: FormData.fromMap({
              'body': body,
              if (file != null) 'file': MultipartFile.fromBytes(file.bytes, filename: file.name),
            }),
            options: Options(sendTimeout: const Duration(seconds: 60)));
        return ChatMessage.fromJson(r.data!);
      });

  Future<void> markRead(int conversationId, int lastMessageId) => _call(() =>
      _dio.post<void>('school/conversations/$conversationId/read', data: {'lastMessageId': lastMessageId}));

  Future<Uint8List> messageAttachment(int messageId) => _bytes('school/attachments/$messageId');

  // ── The child's day ──

  Future<ChildDay> day(int studentId, String date) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/children/$studentId/day', queryParameters: {'date': date});
        return ChildDay.fromJson(r.data!);
      });

  Future<List<ParentNote>> notes({int? studentId}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/notes',
            queryParameters: {if (studentId != null) 'studentId': studentId});
        return (r.data ?? const []).map((e) => ParentNote.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> createNote(Map<String, dynamic> body) => _call(() => _dio.post<void>('school/notes', data: body));
  Future<void> cancelNote(int id) => _call(() => _dio.post<void>('school/notes/$id/cancel'));
  Future<void> markNoteSeen(int id) => _call(() => _dio.post<void>('school/notes/$id/seen'));

  Future<AttendanceDay> attendance({int? classId, required String date}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/attendance',
            queryParameters: {'date': date, if (classId != null) 'classId': classId});
        return AttendanceDay.fromJson(r.data!);
      });

  Future<void> checkIn(int studentId, String date, {String? time}) =>
      _call(() => _dio.post<void>('school/attendance/$studentId/check-in', data: {'date': date, 'time': time}));
  Future<void> checkOut(int studentId, String date, String pickedUpBy, {String? time}) => _call(() => _dio
      .post<void>('school/attendance/$studentId/check-out', data: {'date': date, 'time': time, 'pickedUpBy': pickedUpBy}));
  Future<void> markAbsent(int studentId, String date, String? reason) =>
      _call(() => _dio.post<void>('school/attendance/$studentId/absent', data: {'date': date, 'reason': reason}));
  Future<void> clearAttendance(int studentId, String date) =>
      _call(() => _dio.delete<void>('school/attendance/$studentId', queryParameters: {'date': date}));

  Future<DailyReport> saveReport(int studentId, String date, DailyReport report, {bool publish = false}) =>
      _call(() async {
        final r = await _dio.put<Map<String, dynamic>>('school/reports/$studentId',
            queryParameters: {'date': date}, data: report.toJson(publish: publish));
        return DailyReport.fromJson(r.data)!;
      });

  Future<void> addReportPhoto(int studentId, String date, PickedFile file) => _call(() => _dio.post<void>(
      'school/reports/$studentId/photos',
      queryParameters: {'date': date},
      data: FormData.fromMap({'file': MultipartFile.fromBytes(file.bytes, filename: file.name)}),
      options: Options(sendTimeout: const Duration(seconds: 60))));

  Future<void> deleteReportPhoto(int photoId) => _call(() => _dio.delete<void>('school/reports/photos/$photoId'));

  Future<Uint8List> reportPhoto(int photoId) => _bytes('school/reports/photos/$photoId');

  Future<int> publishReports(String date, List<int> studentIds) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/reports/publish',
            data: {'date': date, 'studentIds': studentIds});
        return (r.data?['published'] as num?)?.toInt() ?? 0;
      });

  // ── Fees ──

  Future<MyFees> myFees() => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/fees/mine');
        return MyFees.fromJson(r.data!);
      });

  Future<InvoiceMonth> invoices(int year, int month, {String? status, int? classId}) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/fees/invoices',
            queryParameters: {'year': year, 'month': month, if (status != null) 'status': status, if (classId != null) 'classId': classId});
        return InvoiceMonth.fromJson(r.data!);
      });

  Future<Invoice> invoice(int id) => _call(() async {
        final r = await _dio.get<Map<String, dynamic>>('school/fees/invoices/$id');
        return Invoice.fromJson(r.data!);
      });

  Future<Invoice> addPayment(int invoiceId, {required double amount, required String paidOn,
          required String method, String? reference}) =>
      _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/fees/invoices/$invoiceId/payments',
            data: {'amount': amount, 'paidOn': paidOn, 'method': method, 'reference': reference});
        return Invoice.fromJson(r.data!);
      });

  Future<int> remind(int year, int month) => _call(() async {
        final r = await _dio.post<Map<String, dynamic>>('school/fees/invoices/remind', data: {'year': year, 'month': month});
        return (r.data?['reminded'] as num?)?.toInt() ?? 0;
      });

  /// Parent: "I've paid" (with an optional slip photo).
  Future<void> createClaim(int invoiceId, {required double amount, required String paidOn, required String method,
          String? reference, String? note, PickedFile? slip}) =>
      _call(() => _dio.post<void>('school/fees/invoices/$invoiceId/claims',
          data: FormData.fromMap({
            'amount': amount.toStringAsFixed(2),
            'paidOn': paidOn,
            'method': method,
            if (reference != null) 'reference': reference,
            if (note != null) 'note': note,
            if (slip != null) 'file': MultipartFile.fromBytes(slip.bytes, filename: slip.name),
          }),
          options: Options(sendTimeout: const Duration(seconds: 60))));

  Future<List<PaymentClaim>> claims({String status = 'Pending'}) => _call(() async {
        final r = await _dio.get<List<dynamic>>('school/fees/claims', queryParameters: {'status': status});
        return (r.data ?? const []).map((e) => PaymentClaim.fromJson(e as Map<String, dynamic>)).toList();
      });

  Future<void> confirmClaim(int id) => _call(() => _dio.post<void>('school/fees/claims/$id/confirm', data: {}));
  Future<void> rejectClaim(int id, String reason) =>
      _call(() => _dio.post<void>('school/fees/claims/$id/reject', data: {'reason': reason}));
  Future<Uint8List> claimSlip(int id) => _bytes('school/fees/claims/$id/slip');

  Future<Uint8List> invoicePdf(int id) => _bytes('school/fees/invoices/$id/pdf');
  Future<Uint8List> receiptPdf(int paymentId) => _bytes('school/fees/payments/$paymentId/receipt');
}

final schoolRepositoryProvider = Provider<SchoolRepository>((ref) => SchoolRepository(ref.watch(dioProvider)));

/// The signed-in user's school role. "Off" when the company has no school features (or on error),
/// so the school screens and menu items simply don't show.
final schoolMeProvider = FutureProvider<SchoolMe>((ref) async {
  final session = ref.watch(authControllerProvider);
  if (session == null) return SchoolMe.off;
  try {
    return await ref.watch(schoolRepositoryProvider).me();
  } catch (_) {
    return SchoolMe.off;
  }
});

/// Unread messages + announcements, for badges. Failures just hide the badge.
final schoolUnreadProvider = FutureProvider.autoDispose<({int messages, int announcements})>((ref) async {
  final me = await ref.watch(schoolMeProvider.future);
  if (!me.enabled) return (messages: 0, announcements: 0);
  final repo = ref.watch(schoolRepositoryProvider);
  int m = 0, a = 0;
  try {
    m = await repo.unreadMessages();
  } catch (_) {}
  if (me.isParent) {
    try {
      a = await repo.unreadAnnouncements();
    } catch (_) {}
  }
  return (messages: m, announcements: a);
});

/// Staff home counters; null for non-staff, when school features are off, or on error.
final staffTodayProvider = FutureProvider.autoDispose<StaffToday?>((ref) async {
  final me = await ref.watch(schoolMeProvider.future);
  if (!me.isStaff) return null;
  try {
    return await ref.watch(schoolRepositoryProvider).staffToday();
  } catch (_) {
    return null;
  }
});

final conversationsProvider = FutureProvider.autoDispose<List<ConversationSummary>>(
    (ref) => ref.watch(schoolRepositoryProvider).conversations());

final announcementsProvider =
    FutureProvider.autoDispose<List<Announcement>>((ref) => ref.watch(schoolRepositoryProvider).announcements());

final myFeesProvider = FutureProvider.autoDispose<MyFees>((ref) => ref.watch(schoolRepositoryProvider).myFees());

/// Photos are kept while the screen that shows them is open.
final reportPhotoProvider = FutureProvider.autoDispose.family<Uint8List, int>(
    (ref, id) => ref.watch(schoolRepositoryProvider).reportPhoto(id));

final messagePhotoProvider = FutureProvider.autoDispose.family<Uint8List, int>(
    (ref, id) => ref.watch(schoolRepositoryProvider).messageAttachment(id));
