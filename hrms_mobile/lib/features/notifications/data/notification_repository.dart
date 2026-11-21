import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/api_exception.dart';
import '../../../core/utils/formatters.dart';

/// One row of GET /api/notification (latest 50).
class AppNotification {
  const AppNotification({
    required this.id,
    required this.title,
    required this.message,
    required this.type,
    required this.isRead,
    this.createdAt,
    this.link,
  });

  final int id;
  final String title;
  final String message;

  /// e.g. leave_approved, attendance_rejected, payroll_generated
  final String type;
  final bool isRead;
  final DateTime? createdAt;

  /// The page it is about (web path, e.g. "/parent/fees"); school notifications have one.
  final String? link;

  /// Which part of the app the notification is about.
  String get area => type.split('_').first; // leave | attendance | payroll

  AppNotification markedRead() => AppNotification(
      id: id, title: title, message: message, type: type, isRead: true, createdAt: createdAt, link: link);

  factory AppNotification.fromJson(Map<String, dynamic> json) => AppNotification(
        id: json['id'] as int,
        title: json['title'] as String? ?? '',
        message: json['message'] as String? ?? '',
        type: json['type'] as String? ?? '',
        isRead: json['isRead'] as bool? ?? false,
        createdAt: tryParseApiDate(json['createdAt']),
        link: json['link'] as String?,
      );
}

class NotificationRepository {
  NotificationRepository(this._dio);

  final Dio _dio;

  Future<List<AppNotification>> list() async {
    try {
      final res = await _dio.get<List<dynamic>>('notification');
      return (res.data ?? const [])
          .map((e) => AppNotification.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<int> unreadCount() async {
    try {
      final res = await _dio.get<Map<String, dynamic>>('notification/unread-count');
      return (res.data?['count'] as num?)?.toInt() ?? 0;
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> markRead(int id) async {
    try {
      await _dio.post<void>('notification/$id/mark-read');
    } catch (e) {
      throw ApiException.from(e);
    }
  }

  Future<void> markAllRead() async {
    try {
      await _dio.post<void>('notification/mark-all-read');
    } catch (e) {
      throw ApiException.from(e);
    }
  }
}

final notificationRepositoryProvider = Provider<NotificationRepository>(
    (ref) => NotificationRepository(ref.watch(dioProvider)));

final notificationsProvider = FutureProvider.autoDispose<List<AppNotification>>(
    (ref) => ref.watch(notificationRepositoryProvider).list());

/// Badge count on the bell. Refreshed when the Home screen or the
/// notifications list changes; failures just hide the badge.
final unreadCountProvider = FutureProvider.autoDispose<int>((ref) async {
  try {
    return await ref.watch(notificationRepositoryProvider).unreadCount();
  } catch (_) {
    return 0;
  }
});
