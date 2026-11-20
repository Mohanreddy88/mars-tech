import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/router/app_router.dart';
import '../../auth/application/auth_controller.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You will need to sign in again to use the app.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authControllerProvider.notifier).logout();
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authControllerProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        children: [
          const SizedBox(height: 8),
          ListTile(
            leading: CircleAvatar(
              child: Text((session?.username.isNotEmpty ?? false)
                  ? session!.username[0].toUpperCase()
                  : '?'),
            ),
            title: Text(session?.username ?? ''),
            subtitle: Text(session?.role ?? ''),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.lock_reset_outlined),
            title: const Text('Change password'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(Routes.changePassword),
          ),
          ListTile(
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Sign out',
                style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }
}
