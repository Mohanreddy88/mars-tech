import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/network/api_exception.dart';
import '../../../../core/widgets/error_view.dart';
import '../../../../core/widgets/status_chip.dart';
import '../../../auth/application/auth_controller.dart';
import '../data/master_models.dart';
import '../data/master_repository.dart';

/// Logins: list with role and linked employee, add (employee login or
/// admin / user login), edit role / active / username / email / set a
/// temporary password, resend set-password email, delete.
class UsersScreen extends ConsumerWidget {
  const UsersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final users = ref.watch(usersProvider);
    final me = ref.watch(authControllerProvider)?.username;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Users')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () async {
          final saved = await showModalBottomSheet<bool>(
            context: context,
            isScrollControlled: true,
            showDragHandle: true,
            builder: (_) => const _NewUserSheet(),
          );
          if (saved == true) ref.invalidate(usersProvider);
        },
        icon: const Icon(Icons.person_add_alt),
        label: const Text('Add login'),
      ),
      body: users.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(usersProvider)),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(usersProvider.future),
          child: ListView.separated(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
            itemCount: list.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (_, i) {
              final u = list[i];
              return Card(
                child: ListTile(
                  onTap: () async {
                    final saved = await showModalBottomSheet<bool>(
                      context: context,
                      isScrollControlled: true,
                      showDragHandle: true,
                      builder: (_) => _EditUserSheet(user: u, isMe: u.username == me),
                    );
                    if (saved == true) ref.invalidate(usersProvider);
                  },
                  leading: CircleAvatar(child: Text(u.username.isEmpty ? '?' : u.username[0].toUpperCase())),
                  title: Text(u.username + (u.username == me ? '  (you)' : ''),
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text([u.email, if (u.employeeName != null) u.employeeName!].join(' · ')),
                      if (u.warning != null)
                        Text(u.warning!, style: TextStyle(color: theme.colorScheme.error)),
                    ],
                  ),
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Neutral chip: a role is not a workflow status.
                      StatusChip('role', label: u.role),
                      if (!u.isActive) ...[
                        const SizedBox(height: 4),
                        const StatusChip('Cancelled', label: 'Disabled'),
                      ],
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _NewUserSheet extends ConsumerStatefulWidget {
  const _NewUserSheet();

  @override
  ConsumerState<_NewUserSheet> createState() => _NewUserSheetState();
}

class _NewUserSheetState extends ConsumerState<_NewUserSheet> {
  String _role = 'Employee';
  int? _employeeId;
  final _username = TextEditingController();
  final _email = TextEditingController();
  late final Future<List<AvailableEmployee>> _available =
      ref.read(masterRepositoryProvider).availableEmployees();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Add login', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 16),
              SegmentedButton<String>(
                segments: [for (final r in UserAccount.roles) ButtonSegment(value: r, label: Text(r))],
                selected: {_role},
                onSelectionChanged: (s) => setState(() => _role = s.first),
              ),
              const SizedBox(height: 16),
              if (_role == 'Employee')
                FutureBuilder<List<AvailableEmployee>>(
                  future: _available,
                  builder: (context, snap) {
                    if (!snap.hasData) return const LinearProgressIndicator();
                    final list = snap.data!;
                    if (list.isEmpty) {
                      return const Text('Every active employee already has a login. New employees get one automatically.');
                    }
                    return DropdownButtonFormField<int>(
                      initialValue: _employeeId,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Employee (without a login)'),
                      items: [
                        for (final e in list)
                          DropdownMenuItem(value: e.id, child: Text('${e.name} · ${e.email}', overflow: TextOverflow.ellipsis)),
                      ],
                      onChanged: (v) => setState(() => _employeeId = v),
                    );
                  },
                )
              else ...[
                TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username (min 3 characters)')),
                const SizedBox(height: 12),
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  decoration: const InputDecoration(labelText: 'Email'),
                ),
              ],
              const SizedBox(height: 8),
              Text('A "set your password" email is sent to the login\'s address.',
                  style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                ),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Create login'),
              ),
            ],
          ),
        ),
      );

  Future<void> _save() async {
    if (_role == 'Employee' && _employeeId == null) {
      setState(() => _error = 'Choose the employee.');
      return;
    }
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(masterRepositoryProvider).createUser(
          role: _role, employeeId: _employeeId, username: _username.text, email: _email.text);
      messenger.showSnackBar(const SnackBar(content: Text('Login created and set-password email sent')));
      navigator.pop(true);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = ApiException.from(e).message;
      });
    }
  }
}

class _EditUserSheet extends ConsumerStatefulWidget {
  const _EditUserSheet({required this.user, required this.isMe});

  final UserAccount user;
  final bool isMe;

  @override
  ConsumerState<_EditUserSheet> createState() => _EditUserSheetState();
}

class _EditUserSheetState extends ConsumerState<_EditUserSheet> {
  late final _username = TextEditingController(text: widget.user.username);
  late final _email = TextEditingController(text: widget.user.email);
  final _password = TextEditingController();
  late String _role = UserAccount.roles.contains(widget.user.role) ? widget.user.role : 'User';
  late bool _active = widget.user.isActive;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _username.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  MasterRepository get _repo => ref.read(masterRepositoryProvider);

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit ${widget.user.username}',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 16),
            TextField(controller: _username, decoration: const InputDecoration(labelText: 'Username')),
            const SizedBox(height: 12),
            TextField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email'),
            ),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              segments: [for (final r in UserAccount.roles) ButtonSegment(value: r, label: Text(r))],
              selected: {_role},
              onSelectionChanged: widget.isMe ? null : (s) => setState(() => _role = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Active'),
              subtitle: Text(widget.isMe ? 'You cannot disable your own login' : 'Disabled logins cannot sign in'),
              value: _active,
              onChanged: widget.isMe ? null : (v) => setState(() => _active = v),
            ),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'New temporary password (optional)',
                helperText: 'At least 8 characters; they must change it at next sign-in',
              ),
            ),
            const SizedBox(height: 12),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: scheme.error)),
              ),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: _busy
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Save'),
            ),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _sendWelcome,
                  icon: const Icon(Icons.forward_to_inbox_outlined, size: 18),
                  label: const Text('Send set-password email'),
                ),
              ),
              if (!widget.isMe) ...[
                const SizedBox(width: 8),
                IconButton.outlined(
                  tooltip: 'Delete login',
                  color: scheme.error,
                  onPressed: _busy ? null : _delete,
                  icon: const Icon(Icons.delete_outline),
                ),
              ],
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _run(Future<void> Function() action, String done, {bool close = true}) async {
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(done)));
      if (close) navigator.pop(true);
    } catch (e) {
      setState(() => _error = ApiException.from(e).message);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _save() {
    if (_password.text.isNotEmpty && _password.text.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return Future.value();
    }
    return _run(
        () => _repo.updateUser(widget.user,
            username: _username.text, email: _email.text, role: _role, isActive: _active, password: _password.text),
        'Login updated');
  }

  Future<void> _sendWelcome() =>
      _run(() => _repo.sendWelcome(widget.user.id), 'Set-password email sent to ${widget.user.email}', close: false);

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete login ${widget.user.username}?'),
        content: const Text('They will no longer be able to sign in. The employee record is not affected.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Back')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Delete')),
        ],
      ),
    );
    if (ok == true) await _run(() => _repo.deleteUser(widget.user.id), 'Login deleted');
  }
}
