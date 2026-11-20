import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/utils/formatters.dart';
import '../../auth/application/auth_controller.dart';
import '../data/profile_models.dart';
import '../data/profile_repository.dart';

/// Profile tab: employee details from HR, edit phone / bank details,
/// change password, sign out.
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
    final isAdmin = session?.isAdmin ?? false;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: RefreshIndicator(
        onRefresh: () async {
          if (isAdmin) return;
          ref.invalidate(profileProvider);
          await ref.read(profileProvider.future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            // Admin logins have no employee record: just the account.
            if (isAdmin)
              _AccountHeader(title: session?.username ?? '', subtitle: 'Administrator')
            else
              ref.watch(profileProvider).when(
              skipLoadingOnRefresh: true,
              loading: () => const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
              // Accounts without an employee record (e.g. admin) still get
              // the account section below.
              error: (e, _) => _AccountHeader(
                title: session?.username ?? '',
                subtitle: ApiException.from(e).message,
              ),
              data: (p) => _ProfileDetails(profile: p),
            ),
            const SizedBox(height: 16),
            Card(
              child: Column(
                children: [
                  ListTile(
                    leading: const Icon(Icons.badge_outlined),
                    title: const Text('Username'),
                    trailing: Text(session?.username ?? ''),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.lock_reset_outlined),
                    title: const Text('Change password'),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => context.push(Routes.changePassword),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.logout, color: theme.colorScheme.error),
                    title: Text('Sign out',
                        style: TextStyle(color: theme.colorScheme.error)),
                    onTap: () => _confirmLogout(context, ref),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileDetails extends ConsumerWidget {
  const _ProfileDetails({required this.profile});

  final EmployeeProfile profile;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final p = profile;
    final job = [p.designation, p.departmentName]
        .where((s) => s != null && s.isNotEmpty)
        .join(' · ');

    return Column(
      children: [
        _AccountHeader(title: p.name, subtitle: job),
        const SizedBox(height: 16),
        _InfoCard(
          title: 'Contact',
          rows: [
            ('Email', p.email),
            ('Mobile', p.phoneDisplay),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Employment',
          rows: [
            ('Department', p.departmentName),
            ('Designation', p.designation),
            ('Joined', p.joinDate == null ? null : Fmt.date(p.joinDate)),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Personal',
          rows: [
            (p.idType?.isNotEmpty == true ? p.idType! : 'IC / Passport', p.icPassport),
            ('Date of birth', p.dateOfBirth == null ? null : Fmt.date(p.dateOfBirth)),
            ('Tax number', p.taxNumber),
          ],
        ),
        const SizedBox(height: 12),
        _InfoCard(
          title: 'Bank (for salary)',
          rows: [
            ('Bank', p.bankName),
            ('Account number', p.accountNumber),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () async {
              final saved = await context.push<bool>(Routes.editProfile, extra: p);
              if (saved == true) ref.invalidate(profileProvider);
            },
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit mobile number & bank details'),
          ),
        ),
      ],
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(color: scheme.primary, borderRadius: BorderRadius.circular(16)),
      child: Row(
        children: [
          CircleAvatar(
            radius: 28,
            backgroundColor: scheme.onPrimary.withValues(alpha: 0.15),
            child: Text(title.isEmpty ? '?' : title[0].toUpperCase(),
                style: text.headlineSmall?.copyWith(color: scheme.onPrimary)),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: text.titleLarge
                        ?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w600)),
                if (subtitle.isNotEmpty)
                  Text(subtitle,
                      style: text.bodyMedium
                          ?.copyWith(color: scheme.onPrimary.withValues(alpha: 0.85))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.title, required this.rows});

  final String title;
  final List<(String, String?)> rows;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            for (final (label, value) in rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: 120, child: Text(label, style: muted)),
                    Expanded(
                      child: Text(
                        value == null || value.isEmpty ? '—' : value,
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
