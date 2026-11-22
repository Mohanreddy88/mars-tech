import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/application/auth_controller.dart';
import '../data/school_repository.dart';

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
