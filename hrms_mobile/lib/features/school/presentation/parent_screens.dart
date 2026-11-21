import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../../auth/application/auth_controller.dart';
import '../../notifications/presentation/notifications_screen.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'school_widgets.dart';

/// Bottom navigation for parent logins: Home, Messages, Announcements, Fees, Account.
class ParentShell extends ConsumerWidget {
  const ParentShell({super.key, required this.navigationShell});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unread = ref.watch(schoolUnreadProvider).valueOrNull;
    Widget badge(int n, IconData icon) => Badge(isLabelVisible: n > 0, label: Text('$n'), child: Icon(icon));
    return Scaffold(
      body: navigationShell,
      bottomNavigationBar: NavigationBar(
        selectedIndex: navigationShell.currentIndex,
        onDestinationSelected: (i) {
          navigationShell.goBranch(i, initialLocation: i == navigationShell.currentIndex);
          ref.invalidate(schoolUnreadProvider);
        },
        destinations: [
          const NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(
              icon: badge(unread?.messages ?? 0, Icons.chat_bubble_outline),
              selectedIcon: const Icon(Icons.chat_bubble),
              label: 'Messages'),
          NavigationDestination(
              icon: badge(unread?.announcements ?? 0, Icons.campaign_outlined),
              selectedIcon: const Icon(Icons.campaign),
              label: 'News'),
          const NavigationDestination(icon: Icon(Icons.payments_outlined), selectedIcon: Icon(Icons.payments), label: 'Fees'),
          const NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Account'),
        ],
      ),
    );
  }
}

/// Parent home: each child with today's status (arrived, gone home, absent, report ready).
class ParentHomeScreen extends ConsumerWidget {
  const ParentHomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(schoolMeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Home'), actions: const [NotificationBell()]),
      body: me.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(schoolMeProvider)),
        data: (me) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(schoolUnreadProvider);
            ref.invalidate(_todayProvider);
            ref.invalidate(schoolMeProvider);
            await ref.read(schoolMeProvider.future);
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              Text('Hello, ${me.name}', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(me.enabled ? 'Your children at school' : 'The parent portal isn\'t available. Please contact the school office.',
                  style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              if (me.enabled && me.children.isEmpty)
                const Card(child: Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('No child is linked to your account yet. Please ask the school office to link your child.'),
                )),
              for (final c in me.children) _ChildCard(child: c),
            ],
          ),
        ),
      ),
    );
  }
}

final _todayProvider = FutureProvider.autoDispose.family<ChildDay, int>(
    (ref, id) => ref.watch(schoolRepositoryProvider).day(id, schoolToday()));

class _ChildCard extends ConsumerWidget {
  const _ChildCard({required this.child});
  final ChildSummary child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final day = ref.watch(_todayProvider(child.id)).valueOrNull;
    final a = day?.attendance;
    final (String status, PillTone tone) = a == null
        ? ('Not checked in yet', PillTone.neutral)
        : a.absent
            ? ('Absent today', PillTone.bad)
            : a.checkOut != null
                ? ('Went home ${a.checkOut}', PillTone.info)
                : ('At school since ${a.checkIn}', PillTone.good);

    Future<void> message(String kind) async {
      try {
        final id = await ref.read(schoolRepositoryProvider).openConversation(child.id, kind);
        if (context.mounted) context.push('${Routes.schoolChat}/$id');
      } catch (e) {
        if (context.mounted) toast(context, ApiException.from(e).message, error: true);
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: scheme.primaryContainer,
              child: Text(child.fullName.isEmpty ? '?' : child.fullName[0], style: text.titleLarge),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(child.fullName, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
                Text([
                  child.className == null ? 'No class yet' : 'Class ${child.className}',
                  if (child.classTeacherName != null) child.classTeacherName!,
                ].join(' · '), style: text.bodySmall),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill(status, tone: tone),
            if (day?.report != null) const Pill('Daily report ready', tone: PillTone.good),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => context.push('${Routes.schoolChild}/${child.id}'),
                icon: const Icon(Icons.today_outlined),
                label: const Text('Today at school'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => message('Teacher'),
                icon: const Icon(Icons.person_outline, size: 18),
                label: const Text('Teacher'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => message('Office'),
                icon: const Icon(Icons.business_outlined, size: 18),
                label: const Text('Office'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }
}

/// Parent "Account" tab: who is signed in, change password, sign out.
class ParentAccountScreen extends ConsumerWidget {
  const ParentAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final me = ref.watch(schoolMeProvider).valueOrNull;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        Card(
          child: ListTile(
            leading: CircleAvatar(child: Text((me?.name ?? session?.username ?? '?').substring(0, 1).toUpperCase())),
            title: Text(me?.name ?? session?.username ?? ''),
            subtitle: Text('Parent · ${session?.username ?? ''}'),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Column(children: [
            ListTile(
              leading: Icon(Icons.notifications_outlined, color: scheme.primary),
              title: const Text('Notifications'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.notifications),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.lock_reset_outlined, color: scheme.primary),
              title: const Text('Change password'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.push(Routes.changePassword),
            ),
            const Divider(height: 1),
            ListTile(
              leading: Icon(Icons.logout, color: scheme.error),
              title: Text('Sign out', style: TextStyle(color: scheme.error)),
              onTap: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: const Text('Sign out?'),
                    content: const Text('You will need to sign in again to use the app.'),
                    actions: [
                      TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                      FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Sign out')),
                    ],
                  ),
                );
                if (ok == true) await ref.read(authControllerProvider.notifier).logout();
              },
            ),
          ]),
        ),
      ]),
    );
  }
}
