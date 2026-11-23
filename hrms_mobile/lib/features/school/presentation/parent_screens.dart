import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
