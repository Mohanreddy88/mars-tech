import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/router/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../../../core/widgets/error_view.dart';
import '../data/notification_repository.dart';

/// Bell icon with unread badge, for app bars.
class NotificationBell extends ConsumerWidget {
  const NotificationBell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(unreadCountProvider).valueOrNull ?? 0;
    return IconButton(
      tooltip: 'Notifications',
      onPressed: () async {
        await context.push(Routes.notifications);
        ref.invalidate(unreadCountProvider);
      },
      icon: Badge(
        isLabelVisible: count > 0,
        label: Text(count > 99 ? '99+' : '$count'),
        child: const Icon(Icons.notifications_outlined),
      ),
    );
  }
}

/// Latest notifications; tap to mark read and open the related tab.
class NotificationsScreen extends ConsumerWidget {
  const NotificationsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final list = ref.watch(notificationsProvider);
    final hasUnread = list.valueOrNull?.any((n) => !n.isRead) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (hasUnread)
            TextButton(
              onPressed: () async {
                await ref.read(notificationRepositoryProvider).markAllRead();
                ref.invalidate(notificationsProvider);
              },
              child: const Text('Mark all read'),
            ),
        ],
      ),
      body: list.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorView(error: e, onRetry: () => ref.invalidate(notificationsProvider)),
        data: (items) => RefreshIndicator(
          onRefresh: () => ref.refresh(notificationsProvider.future),
          child: items.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(height: 120),
                    Icon(Icons.notifications_none, size: 56),
                    SizedBox(height: 12),
                    Center(child: Text('No notifications yet')),
                  ],
                )
              : ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, i) => _NotificationTile(
                    item: items[i],
                    onTap: () => _open(context, ref, items[i]),
                  ),
                ),
        ),
      ),
    );
  }

  Future<void> _open(BuildContext context, WidgetRef ref, AppNotification n) async {
    if (!n.isRead) {
      try {
        await ref.read(notificationRepositoryProvider).markRead(n.id);
      } catch (_) {
        // Not critical; it stays unread.
      }
      ref.invalidate(notificationsProvider);
    }
    final session = ref.read(authControllerProvider);
    final isAdmin = session?.isAdmin ?? false;
    // School notifications carry the page they are about
    final schoolTarget = session == null ? null : Routes.fromWebLink(session, n.link);
    if (schoolTarget != null) {
      // Tab pages (Fees, Announcements…) are switched to; other pages open on top
      if (context.mounted) Routes.open(GoRouter.of(context), schoolTarget);
      return;
    }
    final target = isAdmin
        ? switch (n.area) {
            // Admins are told about submitted leave / attendance: open approvals.
            'leave' => Routes.adminApprovals,
            'attendance' => '${Routes.adminApprovals}?tab=attendance',
            'payroll' => Routes.adminHome,
            _ => null,
          }
        : switch (n.area) {
            'leave' => Routes.leave,
            'attendance' => Routes.attendance,
            'payroll' => Routes.payslips,
            _ => null,
          };
    if (target != null && context.mounted) context.go(target);
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({required this.item, required this.onTap});

  final AppNotification item;
  final VoidCallback onTap;

  static final _time = DateFormat('dd MMM, h:mm a');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final type = item.type;
    final (IconData icon, Color color) = switch (item.area) {
      'leave' => (Icons.beach_access_outlined, scheme.primary),
      'attendance' => (Icons.event_available_outlined, scheme.tertiary),
      'payroll' => (Icons.receipt_long_outlined, const Color(0xFF15803D)),
      'school' => (Icons.school_outlined, scheme.primary),
      _ => (Icons.notifications_outlined, scheme.secondary),
    };
    final bad = type.endsWith('_rejected');

    return ListTile(
      onTap: onTap,
      tileColor: item.isRead ? null : scheme.primaryContainer.withValues(alpha: 0.25),
      leading: CircleAvatar(
        backgroundColor: (bad ? scheme.error : color).withValues(alpha: 0.12),
        child: Icon(bad ? Icons.error_outline : icon, color: bad ? scheme.error : color),
      ),
      title: Text(item.title,
          style: TextStyle(fontWeight: item.isRead ? FontWeight.w500 : FontWeight.w700)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(item.message),
          if (item.createdAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(_time.format(item.createdAt!.toLocal()),
                  style: theme.textTheme.bodySmall
                      ?.copyWith(color: scheme.onSurfaceVariant)),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: item.isRead
          ? null
          : Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: scheme.primary, shape: BoxShape.circle),
            ),
    );
  }
}
