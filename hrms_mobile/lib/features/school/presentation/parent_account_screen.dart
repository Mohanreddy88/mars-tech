import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/router/app_router.dart';
import '../../../core/widgets/error_view.dart';
import '../../auth/application/auth_controller.dart';
import '../data/parent_account.dart';
import '../data/school_models.dart';
import '../data/school_repository.dart';
import 'child_day_screen.dart' show ParentNoteSheet;
import 'school_widgets.dart';
import 'setup_widgets.dart';

/// The parent's notes from today on (for "Temporary pickup pass").
final _upcomingNotesProvider = FutureProvider.autoDispose<List<ParentNote>>((ref) async {
  final today = schoolToday();
  final list = await ref.watch(schoolRepositoryProvider).notes();
  return list.where((n) => !n.cancelled && n.toDate.compareTo(today) >= 0).toList()
    ..sort((a, b) => a.fromDate.compareTo(b.fromDate));
});

String _date(String? ymd) => ymd == null ? '—' : DateFormat('d MMM yyyy').format(ymdToDate(ymd));

/// Parent "Account" tab: My profile, Child details, Contacts (who may collect), Temporary pickup
/// pass, and sign out.
class ParentAccountScreen extends ConsumerWidget {
  const ParentAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(parentAccountProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Account')),
      body: account.when(
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(error: e, onRetry: () => ref.invalidate(parentAccountProvider)),
        data: (a) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(_upcomingNotesProvider);
            ref.invalidate(parentAccountProvider);
            await ref.read(parentAccountProvider.future);
          },
          child: ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 32), children: [
            _Section(title: 'My profile', children: [
              _Row(
                leading: CircleAvatar(child: Text(a.fullName.isEmpty ? '?' : a.fullName[0].toUpperCase())),
                title: a.fullName,
                subtitle: '${a.relationship} · ${a.phone == null ? 'no phone yet' : phoneText(a.phone)}',
              ),
              _Row(icon: Icons.badge_outlined, title: 'Personal information',
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _PersonalInfoScreen(account: a)))),
              _Row(icon: Icons.lock_reset_outlined, title: 'Change password', onTap: () => context.push(Routes.changePassword)),
              _Row(icon: Icons.notifications_outlined, title: 'Notifications', onTap: () => context.push(Routes.notifications)),
            ]),
            _Section(title: a.children.length == 1 ? 'Child details' : 'Children', children: [
              if (a.children.isEmpty) const _Row(title: 'No child linked yet. Please contact the school office.'),
              for (final c in a.children)
                _Row(
                  leading: CircleAvatar(
                    backgroundColor: const Color(0xFF38BDF8),
                    child: Text(c.fullName.isEmpty ? '?' : c.fullName[0].toUpperCase(), style: const TextStyle(color: Colors.white)),
                  ),
                  title: c.fullName,
                  subtitle: [if (c.className != null) 'Class ${c.className}', c.sessionType].join(' · '),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => _ChildDetailsScreen(child: c))),
                ),
            ]),
            _ContactsSection(account: a),
            const _PickupPassSection(),
            _Section(title: '', children: [
              _Row(
                icon: Icons.logout,
                danger: true,
                title: 'Sign out',
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
          ]),
        ),
      ),
    );
  }
}

/// A card with a grey header, like the rest of the Account page.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.action});
  final String title;
  final List<Widget> children;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(top: 12),
      clipBehavior: Clip.antiAlias,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (title.isNotEmpty)
          Container(
            color: theme.colorScheme.surfaceContainerHighest,
            padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
            child: Row(children: [
              Expanded(child: Text(title, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700))),
              if (action != null) action!,
            ]),
          ),
        for (var i = 0; i < children.length; i++) ...[if (i > 0) const Divider(height: 1), children[i]],
      ]),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.title, this.subtitle, this.icon, this.leading, this.trailing, this.onTap, this.danger = false});
  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: leading ?? (icon == null ? null : Icon(icon, color: danger ? scheme.error : scheme.primary)),
      title: Text(title, style: danger ? TextStyle(color: scheme.error) : null),
      subtitle: subtitle == null ? null : Text(subtitle!),
      trailing: trailing ?? (onTap == null || danger ? null : const Icon(Icons.arrow_forward, size: 20)),
      onTap: onTap,
    );
  }
}

/// Contacts: everyone who may collect the children — parents and guardians (always), and the
/// pick-up people the parents added (once the office approves). "Add" sends a new one for approval.
class _ContactsSection extends ConsumerWidget {
  const _ContactsSection({required this.account});
  final ParentAccount account;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final many = account.children.length > 1;
    // Parents and guardians, once each (with which children when there are several)
    final contacts = <int, (ChildContact, List<String>)>{};
    for (final c in account.children) {
      for (final p in c.contacts) {
        contacts.putIfAbsent(p.id, () => (p, <String>[])).$2.add(c.fullName);
      }
    }
    final people = [for (final c in account.children) for (final p in c.pickupPeople) (p, c.fullName)];

    return _Section(
      title: 'Contacts',
      action: account.children.isEmpty
          ? null
          : OutlinedButton.icon(
              onPressed: () => _addPerson(context, ref),
              icon: const Icon(Icons.person_add_alt, size: 18),
              label: const Text('Add'),
            ),
      children: [
        for (final e in contacts.values)
          _Row(
            leading: CircleAvatar(child: Text(e.$1.fullName.isEmpty ? '?' : e.$1.fullName[0].toUpperCase())),
            title: e.$1.isMe ? '${e.$1.fullName} (you)' : e.$1.fullName,
            subtitle: [e.$1.relationship, if (e.$1.phone != null) phoneText(e.$1.phone), if (many) e.$2.join(', ')].join(' · '),
            trailing: const _PickupBadge.authorized(),
          ),
        for (final (p, child) in people)
          _Row(
            leading: CircleAvatar(
              backgroundColor: p.approved ? null : Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Text(p.fullName.isEmpty ? '?' : p.fullName[0].toUpperCase()),
            ),
            title: p.fullName,
            subtitle: [
              p.relationship,
              if (p.phone != null) phoneText(p.phone),
              if (many) child,
              if (p.rejected && p.rejectReason != null) 'Office: ${p.rejectReason}',
            ].join(' · '),
            trailing: _PickupBadge(p),
            onTap: () => _personActions(context, ref, p),
          ),
        if (contacts.isEmpty && people.isEmpty) const _Row(title: 'No contacts yet.'),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
          child: Text('Parents and guardians may always collect your child. Other people you add can collect once '
              'the school office approves them.', style: TextStyle(fontSize: 12)),
        ),
      ],
    );
  }

  Future<void> _addPerson(BuildContext context, WidgetRef ref) async {
    final added = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => _AddPickupPersonScreen(children: account.children)));
    if (added == true) ref.invalidate(parentAccountProvider);
  }

  Future<void> _personActions(BuildContext context, WidgetRef ref, PickupPersonRec p) async {
    final remove = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(p.fullName),
        content: Text(p.approved
            ? '${p.fullName} may collect your child. Remove them?'
            : p.pending
                ? 'Waiting for the school office to approve. Withdraw the request?'
                : 'The office did not approve ${p.fullName}${p.rejectReason != null ? ': ${p.rejectReason}' : '.'} Remove from your list?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Remove')),
        ],
      ),
    );
    if (remove != true || !context.mounted) return;
    if (await attempt(context, () => ref.read(parentAccountRepositoryProvider).removePickupPerson(p.id), done: 'Removed')) {
      ref.invalidate(parentAccountProvider);
    }
  }
}

class _PickupBadge extends StatelessWidget {
  const _PickupBadge(PickupPersonRec this.person);
  const _PickupBadge.authorized() : person = null;
  final PickupPersonRec? person;

  @override
  Widget build(BuildContext context) {
    final p = person;
    final (String text, Color color) = p == null || p.approved
        ? ('Authorized pick-up', const Color(0xFF16A34A))
        : p.pending
            ? ('Waiting for approval', const Color(0xFFD97706))
            : ('Not approved', Theme.of(context).colorScheme.error);
    return Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600, fontSize: 12));
  }
}

/// Temporary pickup pass: someone else collects the child on a given day (the "Other pickup"
/// note — the teacher sees it at check-out).
class _PickupPassSection extends ConsumerWidget {
  const _PickupPassSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final account = ref.watch(parentAccountProvider).valueOrNull;
    final passes = (ref.watch(_upcomingNotesProvider).valueOrNull ?? const <ParentNote>[]).where((n) => !n.isAbsence).toList();
    final names = {for (final c in account?.children ?? const <AccountChild>[]) c.id: c.fullName};
    return _Section(
      title: 'Temporary pickup pass',
      action: names.isEmpty
          ? null
          : OutlinedButton(onPressed: () => _add(context, ref, account!.children), child: const Text('Add')),
      children: [
        if (passes.isEmpty)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Text('Someone else collecting your child on a particular day? Add a pass and the teacher will be told.',
                style: TextStyle(fontSize: 13)),
          ),
        for (final n in passes)
          _Row(
            icon: Icons.directions_car_outlined,
            title: '${n.pickupName ?? ''}${n.pickupTime != null ? ' · ${n.pickupTime}' : ''}',
            subtitle: [noteWhen(n), if (names.length > 1) names[n.studentId] ?? '', n.seenByName != null ? 'Seen by ${n.seenByName}' : 'Sent']
                .where((s) => s.isNotEmpty)
                .join(' · '),
            trailing: TextButton(
              onPressed: () async {
                if (await attempt(context, () => ref.read(schoolRepositoryProvider).cancelNote(n.id), done: 'Pass withdrawn')) {
                  ref.invalidate(_upcomingNotesProvider);
                }
              },
              child: const Text('Withdraw'),
            ),
          ),
      ],
    );
  }

  Future<void> _add(BuildContext context, WidgetRef ref, List<AccountChild> children) async {
    var child = children.length == 1 ? children.first : null;
    child ??= await pickFromList<AccountChild>(context,
        title: 'Which child?', items: children, label: (c) => c.fullName, subtitle: (c) => c.className ?? '');
    if (child == null || !context.mounted) return;
    final sent = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ParentNoteSheet(childId: child!.id, kind: 'Pickup'),
    );
    if (sent == true) ref.invalidate(_upcomingNotesProvider);
  }
}

/// Personal information: name, email and login are kept by the office; the phone can be changed here.
class _PersonalInfoScreen extends ConsumerStatefulWidget {
  const _PersonalInfoScreen({required this.account});
  final ParentAccount account;

  @override
  ConsumerState<_PersonalInfoScreen> createState() => _PersonalInfoScreenState();
}

class _PersonalInfoScreenState extends ConsumerState<_PersonalInfoScreen> {
  late final _phone = TextEditingController(text: phoneText(widget.account.phone));
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _phone.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(parentAccountRepositoryProvider).setPhone(_phone.text.trim());
      ref.invalidate(parentAccountProvider);
      if (mounted) {
        toast(context, 'Phone number saved');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final a = widget.account;
    InputDecoration locked(String label, IconData icon) =>
        boxDecoration(label, icon: icon).copyWith(suffixIcon: const Icon(Icons.lock_outline, size: 18));
    return Scaffold(
      appBar: AppBar(title: const Text('Personal information')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 32), children: [
        ...spaced([
          TextField(controller: TextEditingController(text: a.fullName), readOnly: true, decoration: locked('Name', Icons.person_outline)),
          TextField(controller: TextEditingController(text: a.relationship), readOnly: true,
              decoration: locked('Relationship', Icons.family_restroom_outlined)),
          TextField(controller: TextEditingController(text: a.email ?? ''), readOnly: true,
              decoration: locked('Email (your login)', Icons.email_outlined)),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            maxLength: 20,
            decoration: boxDecoration('Phone', hint: '012-345 6789', icon: Icons.phone_outlined).copyWith(errorText: _error),
          ),
        ]),
        const SizedBox(height: 8),
        const Text('To change your name or email, please contact the school office.', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Saving…' : 'Save phone number')),
      ]),
    );
  }
}

/// A child's details as the school has them (read only; changes go through the office).
class _ChildDetailsScreen extends StatelessWidget {
  const _ChildDetailsScreen({required this.child});
  final AccountChild child;

  @override
  Widget build(BuildContext context) {
    final c = child;
    Widget row(String label, String? value, IconData icon) => ListTile(
          leading: Icon(icon),
          title: Text(label, style: Theme.of(context).textTheme.labelMedium),
          subtitle: Text(value == null || value.isEmpty ? '—' : value, style: Theme.of(context).textTheme.bodyLarge),
        );
    return Scaffold(
      appBar: AppBar(title: Text(c.fullName)),
      body: ListView(padding: const EdgeInsets.fromLTRB(8, 8, 8, 32), children: [
        Card(
          child: Column(children: [
            row('Class', c.className, Icons.class_outlined),
            row('Class teacher', c.classTeacher, Icons.school_outlined),
            row('Session', c.sessionType, Icons.schedule_outlined),
            row('Date of birth', _date(c.dateOfBirth), Icons.cake_outlined),
            row('Gender', c.gender, Icons.wc_outlined),
            row('Joined on', _date(c.joinedOn), Icons.event_available_outlined),
            if (c.admissionNo != null) row('Admission no.', c.admissionNo, Icons.tag),
          ]),
        ),
        Card(
          child: Column(children: [
            row('Allergies / medical notes', c.medicalNotes, Icons.medical_information_outlined),
            row('Emergency contact', [c.emergencyContactName, if (c.emergencyContactPhone != null) phoneText(c.emergencyContactPhone)]
                .whereType<String>().join(' · '), Icons.contact_emergency_outlined),
          ]),
        ),
        const Padding(
          padding: EdgeInsets.all(12),
          child: Text('Something wrong or changed (allergies, emergency contact)? Please tell the school office.',
              style: TextStyle(fontSize: 12)),
        ),
      ]),
    );
  }
}

/// A parent adds someone who may collect their child(ren); the office approves.
class _AddPickupPersonScreen extends ConsumerStatefulWidget {
  const _AddPickupPersonScreen({required this.children});
  final List<AccountChild> children;

  @override
  ConsumerState<_AddPickupPersonScreen> createState() => _AddPickupPersonScreenState();
}

class _AddPickupPersonScreenState extends ConsumerState<_AddPickupPersonScreen> {
  final _name = TextEditingController();
  final _relationship = TextEditingController();
  final _phone = TextEditingController();
  final _note = TextEditingController();
  late final Set<int> _kids = {for (final c in widget.children) c.id};
  bool _saving = false;
  String? _error;

  static const _suggestions = ['Grandmother', 'Grandfather', 'Aunt', 'Uncle', 'Driver', 'Nanny', 'Family friend'];

  @override
  void dispose() {
    for (final t in [_name, _relationship, _phone, _note]) {
      t.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_kids.isEmpty) {
      setState(() => _error = 'Choose the child(ren) they may collect.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref.read(parentAccountRepositoryProvider).addPickupPerson(
            studentIds: _kids.toList(),
            fullName: _name.text.trim(),
            relationship: _relationship.text.trim(),
            phone: _phone.text.trim(),
            note: _note.text.trim().isEmpty ? null : _note.text.trim(),
          );
      if (mounted) {
        toast(context, 'Sent to the school office for approval');
        Navigator.pop(context, true);
      }
    } catch (e) {
      if (mounted) setState(() => _error = ApiException.from(e).message);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add pick-up person')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 32), children: [
        const Text('Someone who may collect your child regularly. The school office checks and approves them '
            'before they can collect.'),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        formGap,
        ...spaced([
          TextField(controller: _name, maxLength: 150, textCapitalization: TextCapitalization.words,
              decoration: boxDecoration('Full name *', icon: Icons.person_outline)),
          TextField(controller: _relationship, maxLength: 50, textCapitalization: TextCapitalization.words,
              decoration: boxDecoration('Relationship to the child *', hint: 'e.g. Grandmother', icon: Icons.family_restroom_outlined)),
        ]),
        Wrap(spacing: 6, children: [
          for (final s in _suggestions)
            ActionChip(label: Text(s), onPressed: () => setState(() => _relationship.text = s)),
        ]),
        formGap,
        ...spaced([
          TextField(controller: _phone, maxLength: 20, keyboardType: TextInputType.phone,
              decoration: boxDecoration('Phone *', hint: '012-345 6789', icon: Icons.phone_outlined)),
          TextField(controller: _note, maxLength: 300, minLines: 2, maxLines: 3,
              decoration: boxDecoration('Note for the office (optional)', hint: 'e.g. picks up on Tuesdays', icon: Icons.notes_outlined)),
        ]),
        if (widget.children.length > 1) ...[
          const SectionTitle('May collect'),
          for (final c in widget.children)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              value: _kids.contains(c.id),
              title: Text(c.fullName),
              onChanged: (v) => setState(() => v == true ? _kids.add(c.id) : _kids.remove(c.id)),
            ),
        ],
        const SizedBox(height: 16),
        FilledButton(onPressed: _saving ? null : _save, child: Text(_saving ? 'Sending…' : 'Send for approval')),
      ]),
    );
  }
}
